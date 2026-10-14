"""AC1-AC8, AC12, AC13: the CLI end to end against local fixture repos (--allow-local-source)."""

import json
import os
import re
import subprocess
import sys
import tarfile
import time
import unittest

from helpers import (Base, CLI, REPO, fb, good_files, make_repo, commit_files, modlua, sha256sum,
                     vobj, write_entry, write_stub_git, git)

import naming  # noqa: E402  (tools/pipeline on sys.path via helpers)
import reference_verify  # noqa: E402

PUBLISHED_AT = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$")


def tar_names(path):
    with tarfile.open(path, "r:gz") as tf:
        return [m.name for m in tf.getmembers() if m.type != tarfile.XGLTYPE]


def tar_read(path, name):
    with tarfile.open(path, "r:gz") as tf:
        return tf.extractfile(name).read()


class Exits(Base):
    def test_ac1_exit_0_clean_build(self):
        repo, c = make_repo(self.tmp, "r0", good_files())
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(sorted(os.listdir(r.out_dir)), ["build.log", "result.json", "test.hello-1.0.0.tar.gz", "test.hello-1.0.0.tar.gz.minisig"])

    def test_ac1_exit_1_rejected_fixture(self):
        repo, c = make_repo(self.tmp, "r1", good_files(license="LicenseRef-Proprietary"))
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("manifest/license-not-osi", r.stderr)
        self.assertNotIn("test.hello-1.0.0.tar.gz", os.listdir(r.out_dir))  # no artefacts for a rejected version

    def test_ac1_exit_2_usage_error_missing_key(self):
        repo, c = make_repo(self.tmp, "r2", good_files())
        r = self.build_local(repo, c, drop=("--key", self.key))
        self.assertEqual(r.returncode, 2, "missing --key must be a usage error (2), never a rejection (1)")
        self.assertIn("--key", r.stderr)

    def test_ac1_exit_2_unreadable_entry_and_key_file(self):
        repo, c = make_repo(self.tmp, "r2b", good_files())
        r = self.run_cli("/nonexistent/entry.json", "1.0.0")
        self.assertEqual(r.returncode, 2)
        entry = write_entry(os.path.join(self.fresh("e"), "entry.json"), "test:hello", [vobj("1.0.0", c, repo)])
        r = self.run_cli(entry, "1.0.0", key="/nonexistent/k.key", extra=("--allow-local-source",))
        self.assertEqual(r.returncode, 2)

    def test_ac1_exit_2_clone_failure_is_not_a_rejection(self):
        repo, c = make_repo(self.tmp, "r2c", good_files())
        stub = write_stub_git(os.path.join(self.fresh("stub"), "bin"), "record", log=os.path.join(self.tmp, "clonefail.log"))
        r = self.build_local(repo, c, path_prefix=stub)
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn("git clone failed", r.stderr)


class ExactCommit(Base):
    def test_ac2_builds_the_entry_commit_even_when_branch_moved_on(self):
        repo, old = make_repo(self.tmp, "mv", {**good_files(), "old.txt": "old\n"})
        new = commit_files(repo, {"new.txt": "new\n"}, msg="later")
        self.assertNotEqual(old, new)
        self.assertEqual(git(repo, "rev-parse", "HEAD"), new)
        r = self.build_local(repo, old)
        self.assertEqual(r.returncode, 0, r.stderr)
        names = tar_names(os.path.join(r.out_dir, "test.hello-1.0.0.tar.gz"))
        self.assertIn("src/old.txt", names)
        self.assertNotIn("src/new.txt", names)

    def test_ac2_commit_absent_from_repo_names_it(self):
        repo, c = make_repo(self.tmp, "absent", good_files())
        missing = "ab" * 20
        r = self.build_local(repo, missing)
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn(missing, r.stderr)

    def test_ac2_uppercase_hex_commit_rejected_before_any_clone(self):
        repo, c = make_repo(self.tmp, "upper", good_files())
        r = self.build_local(repo, c.upper())
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("commit/not-40-lowercase-hex", r.stderr)
        self.assertEqual(os.listdir(r.work_dir), [], "no clone may be attempted")

    def test_ac2_commit_with_trailing_newline_rejected(self):
        # the schema pattern's `$` would tolerate it under re.search; the tool must not
        repo, c = make_repo(self.tmp, "nl", good_files())
        r = self.build_local(repo, c + "\n")
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertEqual(os.listdir(r.work_dir), [])

    def test_ac2_bad_commit_lengths_rejected(self):
        repo, c = make_repo(self.tmp, "short", good_files())
        for bad in (c[:39], c + "0", "", "g" * 40):
            r = self.build_local(repo, bad)
            self.assertEqual(r.returncode, 1, (bad, r.stderr))

    def test_ac2_version_not_semver_and_not_in_entry(self):
        repo, c = make_repo(self.tmp, "ver", good_files())
        entry = write_entry(os.path.join(self.fresh("e"), "entry.json"), "test:hello", [vobj("1.0.0", c, repo)])
        for bad_version, rule in (("1.0", "version/not-semver"), ("v1.0.0", "version/not-semver"), ("1.0.0\n", "version/not-semver"), ("2.0.0", "version/not-in-entry")):
            r = self.run_cli(entry, bad_version, extra=("--allow-local-source",))
            self.assertEqual(r.returncode, 1, (bad_version, r.stderr))
            self.assertIn(rule, r.stderr)
            self.assertEqual(os.listdir(r.work_dir), [], "rejected before any clone")


class Determinism(Base):
    def test_ac3_two_builds_at_different_times_are_byte_identical(self):
        repo, c = make_repo(self.tmp, "det", {**good_files(), "a/b.txt": "x\n", "run.sh": "#!/bin/sh\n"}, modes={"run.sh": 0o755})
        r1 = self.build_local(repo, c)
        time.sleep(1.2)
        r2 = self.build_local(repo, c)
        self.assertEqual((r1.returncode, r2.returncode), (0, 0), r1.stderr + r2.stderr)
        t1 = os.path.join(r1.out_dir, "test.hello-1.0.0.tar.gz")
        t2 = os.path.join(r2.out_dir, "test.hello-1.0.0.tar.gz")
        self.assertEqual(open(t1, "rb").read(), open(t2, "rb").read())
        res1 = json.load(open(os.path.join(r1.out_dir, "result.json")))
        res2 = json.load(open(os.path.join(r2.out_dir, "result.json")))
        self.assertEqual(res1["artifact"]["source_sha256"], res2["artifact"]["source_sha256"])
        # cross-checked against the OS tool, not the tool's own code
        self.assertEqual(res1["artifact"]["source_sha256"], sha256sum(t1))
        self.assertNotEqual(res1["built_at"] + "x", "", "built_at exists but is not part of the hash")

    def test_ac3_gzip_header_carries_no_name_and_no_timestamp(self):
        repo, c = make_repo(self.tmp, "gzh", good_files())
        r = self.build_local(repo, c)
        head = open(os.path.join(r.out_dir, "test.hello-1.0.0.tar.gz"), "rb").read(10)
        self.assertEqual(head[:4], b"\x1f\x8b\x08\x00", "flags must be 0: no FNAME")
        self.assertEqual(head[4:8], b"\x00\x00\x00\x00", "mtime must be 0")


class Layout(Base):
    def test_ac4_every_entry_has_the_single_root_src(self):
        repo, c = make_repo(self.tmp, "lay", {**good_files(), "deep/er/x.txt": "x\n"})
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 0, r.stderr)
        names = tar_names(os.path.join(r.out_dir, "test.hello-1.0.0.tar.gz"))
        self.assertTrue(names)
        for n in names:
            self.assertTrue(n == "src" or n.startswith("src/"), n)
        self.assertIn("src/mod.lua", names)

    def test_ac4_symlink_with_absolute_target_rejected_whole(self):
        repo, c = make_repo(self.tmp, "sla", good_files(), symlinks={"evil": "/etc/passwd"})
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("archive-layout/symlink-escape", r.stderr)
        self.assertIn("archive-layout.md", r.stderr)
        self.assertFalse(any(f.endswith(".tar.gz") for f in os.listdir(r.out_dir)))

    def test_ac4_symlink_with_dotdot_target_rejected_whole(self):
        repo, c = make_repo(self.tmp, "sld", good_files(), symlinks={"docs/evil": "../../../etc/passwd"})
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("archive-layout/symlink-escape", r.stderr)

    def test_ac4_symlink_staying_inside_root_is_accepted_positive_control(self):
        repo, c = make_repo(self.tmp, "slok", good_files(), symlinks={"link": "README.md"})
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_ac4_export_ignore_on_manifest_is_rejected_as_manifest_missing(self):
        repo, c = make_repo(self.tmp, "ei", {**good_files(), ".gitattributes": "mod.lua export-ignore\n"})
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("manifest missing in the produced archive", r.stderr)
        log = open(os.path.join(r.out_dir, "build.log")).read()
        self.assertIn("export-ignore", log)
        self.assertIn("mod.lua", log)

    def test_ac4_export_subst_observed_behaviour_is_expansion_and_acceptance(self):
        repo, c = make_repo(self.tmp, "es", {**good_files(), "ver.txt": "commit: $Format:%H$\n", ".gitattributes": "ver.txt export-subst\n"})
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 0, r.stderr)
        body = tar_read(os.path.join(r.out_dir, "test.hello-1.0.0.tar.gz"), "src/ver.txt").decode()
        self.assertEqual(body, f"commit: {c}\n", "git archive expands $Format:%H$ in the tarball")
        log = open(os.path.join(r.out_dir, "build.log")).read()
        self.assertIn("export-subst", log)

    def test_ac4_no_working_tree_is_ever_checked_out(self):
        repo, c = make_repo(self.tmp, "nocheck", good_files())
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 0, r.stderr)
        clone = os.path.join(r.work_dir, "clone")
        self.assertEqual(sorted(os.listdir(clone)), [".git"], "clone must hold no working tree files")


class Manifest(Base):
    def test_ac5_kernel_only_keys_accepted(self):
        repo, c = make_repo(self.tmp, "kern", {"mod.lua": modlua(extra='depends = { {id="mc:core"} }, permissions = { fs = true }'), "README.md": "x\n"})
        self.assertEqual(self.build_local(repo, c).returncode, 0)

    def test_ac5_missing_required_field_rejected(self):
        repo, c = make_repo(self.tmp, "mf", {"mod.lua": modlua(omit=("description",))})
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("manifest/schema", r.stderr)
        self.assertIn("description", r.stderr)

    def test_ac5_id_mismatch_rejected_separately(self):
        repo, c = make_repo(self.tmp, "mi", {"mod.lua": modlua(mod_id="test:other")})
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("manifest/id-mismatch", r.stderr)

    def test_ac5_version_mismatch_rejected_separately(self):
        repo, c = make_repo(self.tmp, "mv2", {"mod.lua": modlua(version="1.0.1")})
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("manifest/version-mismatch", r.stderr)

    def test_ac5_executable_lua_is_never_executed_and_is_named(self):
        marker = os.path.join(self.tmp, "lua-ran")
        src = f'os.execute("touch {marker}")\nreturn {{}}\n'
        repo, c = make_repo(self.tmp, "exec", {"mod.lua": src})
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("manifest/no-return", r.stderr)
        self.assertFalse(os.path.exists(marker))

    def test_ac5_function_call_in_manifest_rejected_through_cli(self):
        repo, c = make_repo(self.tmp, "fc", {"mod.lua": modlua(extra='x = f("a")')})
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("manifest/function-call", r.stderr)

    def test_ac5_manifest_missing_and_manifest_symlink(self):
        repo, c = make_repo(self.tmp, "nomf", {"README.md": "x\n"})
        r = self.build_local(repo, c)
        self.assertEqual((r.returncode, "manifest/missing" in r.stderr), (1, True))
        repo, c = make_repo(self.tmp, "mfl", {"real.lua": modlua()}, symlinks={"mod.lua": "real.lua"})
        r = self.build_local(repo, c)
        self.assertEqual((r.returncode, "manifest/not-a-regular-file" in r.stderr), (1, True))


class Licence(Base):
    def test_ac6_non_osi_licences_rejected_osi_accepted(self):
        for i, (lic, ok) in enumerate((("LicenseRef-Proprietary", False), ("NOASSERTION", False), ("Totally-Invented-1.0", False), ("MIT", True), ("Apache-2.0", True))):
            repo, c = make_repo(self.tmp, f"lic{i}", {"mod.lua": modlua(license=lic)})
            r = self.build_local(repo, c)
            if ok:
                self.assertEqual(r.returncode, 0, (lic, r.stderr))
            else:
                self.assertEqual(r.returncode, 1, (lic, r.stderr))
                self.assertIn("manifest/license-not-osi", r.stderr, lic)


class AssetScan(Base):
    def mod(self, name, files):
        repo, c = make_repo(self.tmp, name, {"mod.lua": modlua(), **files})
        return self.build_local(repo, c)

    def test_ac7_blizzard_magic_named_png_rejected_naming_the_format(self):
        for name, builder, fmt in (("dbc", fb.build_dbc, "DBC"), ("mpq", fb.build_mpq, "MPQ"), ("blp", fb.build_blp, "BLP"), ("m2", fb.build_m2, "M2")):
            r = self.mod("bl-" + name, {"innocent.png": builder()})
            self.assertEqual(r.returncode, 1, (name, r.stderr))
            self.assertIn("asset-scan/rejected", r.stderr)
            self.assertIn("innocent.png", r.stderr)
            self.assertIn(fmt, r.stderr)

    def test_ac7_glb_with_embedded_blizzard_payload_rejected(self):
        r = self.mod("glbbad", {"model.glb": fb.build_glb_with_embedded_image(fb.build_blp(), "image/x-blp")})
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("asset-scan/rejected", r.stderr)
        self.assertIn("model.glb", r.stderr)

    def test_ac7_clean_mod_with_png_ogg_glb_and_text_accepted(self):
        glb = fb.build_glb_with_embedded_image(fb.build_png(), "image/png")
        r = self.mod("clean", {"a.png": fb.build_png(), "s.ogg": fb.build_ogg(), "m.glb": glb, "notes.txt": "hello\n"})
        self.assertEqual(r.returncode, 0, r.stderr)
        res = json.load(open(os.path.join(r.out_dir, "result.json")))
        self.assertEqual(res["scan"]["summary"]["files_rejected"], 0)
        fmts = {a["path"]: a["format"] for a in res["scan"]["accepted"]}
        self.assertEqual({fmts["a.png"], fmts["s.ogg"], fmts["m.glb"]}, {"PNG", "OGG", "GLB"})

    def test_ac7_scanner_exit_2_surfaces_as_exit_2_not_1(self):
        repo, c = make_repo(self.tmp, "scan2", good_files())
        stub = os.path.join(self.fresh("sc"), "scanner.py")
        open(stub, "w").write("import sys\nprint('usage problem', file=sys.stderr)\nsys.exit(2)\n")
        r = self.build_local(repo, c, extra=("--scanner", stub))
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn("not a rejection", r.stderr)

    def test_ac7_real_scanner_pointed_at_a_file_exits_2_via_run_scan(self):
        import build_version as bv
        d = self.fresh("rs")
        open(os.path.join(d, "afile"), "w").write("x")
        from pipeline_errors import PipelineError
        with self.assertRaises(PipelineError) as cm:
            bv.run_scan(d, "afile", os.path.join(d, "rep.json"), bv.DEFAULT_SCANNER)
        self.assertIn("exited 2", str(cm.exception))


class ReservedNames(Base):
    def test_ac8_reserved_device_namespaces_rejected_before_any_output(self):
        for ns in ("com1", "aux", "nul", "con", "prn", "lpt9", "com0"):
            repo, c = make_repo(self.tmp, f"rv-{ns}", {"mod.lua": modlua(mod_id=f"{ns}:anytool")})
            entry = write_entry(os.path.join(self.fresh("e"), "entry.json"), f"{ns}:anytool", [vobj("1.0.0", c, repo)])
            r = self.run_cli(entry, "1.0.0", extra=("--allow-local-source",))
            self.assertEqual(r.returncode, 1, (ns, r.stderr))
            self.assertIn("artifact-naming/reserved-device-name", r.stderr)
            self.assertTrue(not os.path.exists(r.out_dir) or os.listdir(r.out_dir) == [], f"--out must be empty for {ns}")
            self.assertEqual(os.listdir(r.work_dir), [])

    def test_ac8_case_insensitive_unit(self):
        from pipeline_errors import Rejected
        for ns in ("AUX", "Nul", "COM1", "lPt3"):
            with self.assertRaises(Rejected):
                naming.check_namespace(ns)

    def test_ac8_comet_and_console_are_accepted_positive_controls(self):
        for ns in ("comet", "console", "com10", "auxiliary"):
            repo, c = make_repo(self.tmp, f"ok-{ns}", {"mod.lua": modlua(mod_id=f"{ns}:tool")})
            r = self.build_local(repo, c, mod_id=f"{ns}:tool")
            self.assertEqual(r.returncode, 0, (ns, r.stderr))


class ComputedValues(Base):
    def test_ac12_result_json_values(self):
        repo, c = make_repo(self.tmp, "res", good_files())
        r = self.build_local(repo, c)
        self.assertEqual(r.returncode, 0, r.stderr)
        res = json.load(open(os.path.join(r.out_dir, "result.json")))
        self.assertEqual(res["id"], "test:hello")
        self.assertEqual(res["version"], "1.0.0")
        self.assertEqual(res["tag"], "test.hello-1.0.0")
        self.assertEqual(res["assets"], {"tarball": "test.hello-1.0.0.tar.gz", "signature": "test.hello-1.0.0.tar.gz.minisig"})
        self.assertRegex(res["built_at"], PUBLISHED_AT)
        art = res["artifact"]
        self.assertEqual(set(art), {"source_sha256", "signature", "key_id"})
        tarball = os.path.join(r.out_dir, res["assets"]["tarball"])
        self.assertEqual(art["source_sha256"], sha256sum(tarball))
        self.assertEqual(art["signature"], open(os.path.join(r.out_dir, res["assets"]["signature"]), encoding="utf-8", newline="").read())
        self.assertEqual(art["signature"].count("\n"), 4)
        self.assertIn("scan", res)

    def test_ac12_release_asset_url_pinned_over_artifact_naming_examples(self):
        # literals typed from contracts/artifact-naming.md's examples, not derived from the code
        self.assertEqual(naming.release_tag("mc", "hello-world", "1.0.0"), "mc.hello-world-1.0.0")
        self.assertEqual(naming.asset_names("mc", "hello-world", "1.0.0"), ("mc.hello-world-1.0.0.tar.gz", "mc.hello-world-1.0.0.tar.gz.minisig"))
        self.assertEqual(
            naming.release_asset_url("worldofmodcraft", "archive", "mc.hello-world-1.0.0", "mc.hello-world-1.0.0.tar.gz"),
            "https://github.com/worldofmodcraft/archive/releases/download/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz",
        )
        self.assertEqual(
            naming.release_asset_url("worldofmodcraft", "archive", "mc.hello-world-1.0.0", "mc.hello-world-1.0.0.tar.gz.minisig"),
            "https://github.com/worldofmodcraft/archive/releases/download/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz.minisig",
        )
        self.assertEqual(naming.release_tag("a", "b", "1.0.0-rc.1+build.5"), "a.b-1.0.0-rc.1+build.5")
        for bad in (("o/x", "r", "t", "a"), ("o", "r", "t/../x", "a"), ("o", "r", "t", "a b")):
            with self.assertRaises(ValueError):
                naming.release_asset_url(*bad)


class PositiveControls(Base):
    def test_ac13_first_second_version_and_text_only_mod_build_and_verify(self):
        repo, c1 = make_repo(self.tmp, "pc", good_files())
        c2 = commit_files(repo, good_files(version="1.1.0") | {"CHANGES.md": "more\n"}, msg="v2")
        entry = write_entry(os.path.join(self.fresh("e"), "entry.json"), "test:hello", [vobj("1.0.0", c1, repo), vobj("1.1.0", c2, repo)])
        outs = {}
        for v in ("1.0.0", "1.1.0"):
            r = self.run_cli(entry, v, extra=("--allow-local-source",))
            self.assertEqual(r.returncode, 0, r.stderr)
            outs[v] = r.out_dir
        textrepo, tc = make_repo(self.tmp, "txt", {"mod.lua": modlua(), "a.txt": "t\n", "b.md": "# b\n", "c.lua": "print('x')\n"})
        r = self.build_local(textrepo, tc)
        self.assertEqual(r.returncode, 0, r.stderr)
        outs["text"] = r.out_dir
        for key, out in outs.items():
            res = json.load(open(os.path.join(out, "result.json")))
            claim = reference_verify.VersionClaim(res["id"], res["version"], res["artifact"]["source_sha256"], res["artifact"]["key_id"], res["artifact"]["signature"])
            reference_verify.verify(os.path.join(out, res["assets"]["tarball"]), claim, {res["artifact"]["key_id"]: self.pub})
        self.assertNotEqual(open(os.path.join(outs["1.0.0"], "test.hello-1.0.0.tar.gz"), "rb").read(),
                            open(os.path.join(outs["1.1.0"], "test.hello-1.1.0.tar.gz"), "rb").read())


if __name__ == "__main__":
    unittest.main()
