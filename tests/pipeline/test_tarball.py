"""AC17 and A-3: tarball hardening. Each hostile tar is hand-built and fed through the real CLI by a
stub `git` whose `archive` subcommand prints it; a clean tar beside each is the positive control."""

import io
import os
import tarfile
import time
import unittest

from helpers import (Base, clean_tar_entries, good_files, make_repo, modlua, tar_gz, vobj, write_entry, write_stub_git)

import archive  # noqa: E402
import build_version as bv  # noqa: E402
from pipeline_errors import Rejected  # noqa: E402

T = tarfile


class Hostile(Base):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.repo, cls.commit = make_repo(cls.tmp, "tarrepo", good_files())

    def feed(self, entries, extra=(), name="h", raw_entries=None):
        tarpath = os.path.join(self.fresh("tars"), name + ".tar.gz")
        tar_gz(tarpath, entries)
        stub = write_stub_git(os.path.join(self.fresh("st"), "bin"), "archive", tar=tarpath)
        return self.build_local(self.repo, self.commit, path_prefix=stub, extra=tuple(extra))

    def reject(self, entries, rule, extra=(), needle=None):
        r = self.feed(entries, extra=extra)
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn(rule, r.stderr)
        if needle:
            self.assertIn(needle, r.stderr)
        self.assertFalse(any(f.endswith(".tar.gz") for f in os.listdir(r.out_dir)), "no artefact for a rejected archive")
        return r

    # ---- positive control ----
    def test_ac17_clean_tar_through_the_same_stub_is_accepted(self):
        r = self.feed(clean_tar_entries())
        self.assertEqual(r.returncode, 0, r.stderr)

    # ---- the AC17 list ----
    def test_ac17_hard_link_entry(self):
        self.reject(clean_tar_entries([{"name": "src/h", "type": T.LNKTYPE, "linkname": "src/mod.lua"}]), "archive-layout/entry-type", needle="hard link")

    def test_ac17_character_device(self):
        self.reject(clean_tar_entries([{"name": "src/c", "type": T.CHRTYPE}]), "archive-layout/entry-type", needle="character device")

    def test_ac17_block_device(self):
        self.reject(clean_tar_entries([{"name": "src/b", "type": T.BLKTYPE}]), "archive-layout/entry-type", needle="block device")

    def test_ac17_fifo(self):
        self.reject(clean_tar_entries([{"name": "src/f", "type": T.FIFOTYPE}]), "archive-layout/entry-type", needle="FIFO")

    def test_ac17_unknown_entry_type(self):
        self.reject(clean_tar_entries([{"name": "src/z", "type": b"Z"}]), "archive-layout/entry-type", needle="unknown entry type")

    def test_ac17_entry_count_limit_boundary(self):
        base = len(clean_tar_entries())
        ok = clean_tar_entries([{"name": f"src/f{i}", "data": b"x"} for i in range(10_000 - base)])
        self.assertEqual(len(ok), 10_000)
        self.assertEqual(self.feed(ok).returncode, 0, "exactly 10,000 entries is accepted")
        bad = clean_tar_entries([{"name": f"src/f{i}", "data": b"x"} for i in range(10_001 - base)])
        self.assertEqual(len(bad), 10_001)
        self.reject(bad, "archive-limits/entry-count", needle="10000")

    def test_ac17_declared_uncompressed_size_over_200_mib_refused_without_buffering(self):
        entries = clean_tar_entries([{"name": "src/huge.bin", "size": 300 * 1024 * 1024}])   # header only, no body
        t0 = time.monotonic()
        r = self.reject(entries, "archive-limits/uncompressed-size", needle=str(200 * 1024 * 1024))
        self.assertLess(time.monotonic() - t0, 10)

    def test_ac17_uncompressed_limit_boundary_with_lowered_limit(self):
        e = clean_tar_entries([{"name": "src/data.bin", "data": b"x" * 3000}])
        total = sum(len(x.get("data", b"")) for x in e)
        self.assertEqual(self.feed(e, extra=("--max-uncompressed-bytes", str(total))).returncode, 0, "exactly at the limit is accepted")
        self.reject(e, "archive-limits/uncompressed-size", extra=("--max-uncompressed-bytes", str(total - 1)))

    def test_ac17_compressed_size_limit_with_lowered_limit(self):
        noisy = os.urandom(30_000)
        self.reject(clean_tar_entries([{"name": "src/noise.bin", "data": noisy}]), "archive-limits/compressed-size", extra=("--max-compressed-bytes", "2000"))
        self.assertEqual(self.feed(clean_tar_entries(), extra=("--max-compressed-bytes", "2000")).returncode, 0)

    def test_ac17_default_limits_are_the_documented_constants(self):
        self.assertEqual(archive.MAX_UNCOMPRESSED_BYTES, 200 * 1024 * 1024)
        self.assertEqual(archive.MAX_COMPRESSED_BYTES, 50 * 1024 * 1024)
        self.assertEqual(archive.MAX_ENTRIES, 10_000)
        a = bv.parse_args(["--entry", "e", "--version", "1.0.0", "--workdir", "w", "--key", "k", "--pubkey", "p", "--out", "o"])
        self.assertEqual((a.max_uncompressed_bytes, a.max_compressed_bytes, a.max_entries), (200 * 1024 * 1024, 50 * 1024 * 1024, 10_000))

    # ---- the three pre-existing escapes, hand-built (AC4 / archive-layout.md) ----
    def test_ac4_dotdot_segment_anywhere(self):
        self.reject(clean_tar_entries([{"name": "src/assets/../../etc/x", "data": b"x"}]), "archive-layout/path-escape")
        self.reject(clean_tar_entries([{"name": "src/../x", "data": b"x"}]), "archive-layout/path-escape")

    def test_ac4_absolute_entry_name(self):
        self.reject(clean_tar_entries([{"name": "/etc/passwd", "data": b"x"}]), "archive-layout/absolute-path")

    def test_ac4_top_level_file_without_root_and_two_roots(self):
        self.reject(clean_tar_entries([{"name": "loose.txt", "data": b"x"}]), "archive-layout/no-root")
        self.reject(clean_tar_entries([{"name": "other/x.txt", "data": b"x"}]), "archive-layout/multiple-roots")

    def test_ac4_symlink_entries_escaping(self):
        self.reject(clean_tar_entries([{"name": "src/l", "type": T.SYMTYPE, "linkname": "/etc"}]), "archive-layout/symlink-escape")
        self.reject(clean_tar_entries([{"name": "src/l", "type": T.SYMTYPE, "linkname": "a/../../b"}]), "archive-layout/symlink-escape")

    # ---- A-3 ----
    def test_a3_write_through_a_symlink(self):
        self.reject(clean_tar_entries([{"name": "src/l", "type": T.SYMTYPE, "linkname": "."}, {"name": "src/l/x", "data": b"pwn"}]), "archive-layout/write-through-symlink")

    def test_a3_write_through_a_symlink_to_a_subdirectory(self):
        self.reject(clean_tar_entries([{"name": "src/sub", "type": T.DIRTYPE}, {"name": "src/l", "type": T.SYMTYPE, "linkname": "sub"}, {"name": "src/l/x", "data": b"pwn"}]), "archive-layout/write-through-symlink")

    def test_a3_symlink_declared_after_the_file_beneath_it(self):
        self.reject(clean_tar_entries([{"name": "src/l/x", "data": b"x"}, {"name": "src/l", "type": T.SYMTYPE, "linkname": "."}]), "archive-layout/path-conflict")

    def test_a3_duplicate_entry_names(self):
        self.reject(clean_tar_entries([{"name": "src/mod.lua", "data": modlua().replace("MIT", "GPL-3.0-only").encode()}]), "archive-layout/duplicate-entry")

    def test_a3_file_and_directory_of_the_same_name(self):
        self.reject(clean_tar_entries([{"name": "src/a", "data": b"x"}, {"name": "src/a/b", "data": b"y"}]), "archive-layout/path-conflict")

    def test_a3_setuid_setgid_and_sticky_modes(self):
        self.reject(clean_tar_entries([{"name": "src/su", "data": b"x", "mode": 0o4755}]), "archive-layout/special-mode")
        self.reject(clean_tar_entries([{"name": "src/sg", "data": b"x", "mode": 0o2755}]), "archive-layout/special-mode")
        self.reject(clean_tar_entries([{"name": "src/st", "type": T.DIRTYPE, "mode": 0o1777}]), "archive-layout/special-mode")

    def test_a3_dot_and_empty_path_segments(self):
        self.reject(clean_tar_entries([{"name": "src/./x", "data": b"x"}]), "archive-layout/non-normalised-name")
        self.reject(clean_tar_entries([{"name": "src//x", "data": b"x"}]), "archive-layout/non-normalised-name")


class DirectArchive(Base):
    """Library-level checks that need a tarball the CLI cannot be made to see."""

    def test_malformed_gzip_and_truncated_tar_are_rejected_not_crashed(self):
        d = self.fresh("mal")
        bad = os.path.join(d, "bad.tar.gz")
        open(bad, "wb").write(b"not gzip at all")
        with self.assertRaises(Rejected) as cm:
            archive.inspect_archive(bad)
        self.assertIn("archive-layout/malformed", cm.exception.rule)
        good = tar_gz(os.path.join(d, "g.tar.gz"), clean_tar_entries())
        raw = open(good, "rb").read()
        trunc = os.path.join(d, "t.tar.gz")
        open(trunc, "wb").write(raw[: len(raw) // 2])
        with self.assertRaises(Rejected):
            archive.inspect_archive(trunc)

    def test_extraction_writes_nothing_when_any_entry_is_hostile(self):
        d = self.fresh("none")
        p = tar_gz(os.path.join(d, "x.tar.gz"), clean_tar_entries([{"name": "src/ok.txt", "data": b"ok"}, {"name": "src/../evil", "data": b"x"}]))
        with self.assertRaises(Rejected):
            archive.inspect_archive(p)       # inspection is whole-archive and precedes any extraction
        self.assertEqual(os.listdir(d), ["x.tar.gz"])

    def test_extraction_modes_are_chosen_by_the_tool_not_the_tar(self):
        d = self.fresh("modes")
        p = tar_gz(os.path.join(d, "x.tar.gz"), clean_tar_entries([{"name": "src/run.sh", "data": b"#!/bin/sh\n", "mode": 0o755}, {"name": "src/w", "data": b"w", "mode": 0o666}]))
        plan = archive.inspect_archive(p)
        out = archive.extract(p, plan, os.path.join(d, "out"))
        self.assertEqual(os.stat(os.path.join(out, "run.sh")).st_mode & 0o7777, 0o755)
        self.assertEqual(os.stat(os.path.join(out, "w")).st_mode & 0o7777, 0o644)

    def test_decompression_bomb_after_the_tar_is_not_read(self):
        # a valid small tar followed by a huge run of zero padding inside the gzip stream
        d = self.fresh("bomb")
        import gzip
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w") as tf:
            ti = tarfile.TarInfo("src/a"); ti.size = 1
            tf.addfile(ti, io.BytesIO(b"a"))
        p = os.path.join(d, "b.tar.gz")
        with gzip.GzipFile(p, "wb", mtime=0) as gz:
            gz.write(buf.getvalue())
            gz.write(b"\0" * (64 * 1024 * 1024))
        t0 = time.monotonic()
        plan = archive.inspect_archive(p)
        self.assertLess(time.monotonic() - t0, 5)
        self.assertEqual(plan.count, 1)


if __name__ == "__main__":
    unittest.main()
