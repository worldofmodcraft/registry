"""Hostile-input-safe inspection and extraction of the source tarball.

Design decision 4 of docs/pipeline/build-pipeline.md. Two phases:

  1. `inspect_archive` walks every tar header (never extracting) and rejects the WHOLE archive on the
     first violation - contracts/archive-layout.md "path-escape rule" and "Malformed archives" -
     plus the cases that contract is silent on (hard links, devices, FIFOs, unknown types, setuid
     bits, symlink write-through, duplicate names, size and entry-count limits).
  2. `extract` writes the validated plan to a fresh directory: regular files with O_EXCL|O_NOFOLLOW
     and modes this module chooses (never the tar's), directories, and - last - symlinks.

The stream is bounded: sizes are judged from the tar headers before any data is read, and the
decompressed stream position is capped, so a decompression bomb is refused without being buffered.
"""

from __future__ import annotations

import gzip
import os
import tarfile
import zlib
from dataclasses import dataclass, field

from pipeline_errors import PipelineError, Rejected

# Assumed constants (no ADR or contract states them; docs/pipeline/build-pipeline.md records them).
MAX_UNCOMPRESSED_BYTES = 200 * 1024 * 1024
MAX_COMPRESSED_BYTES = 50 * 1024 * 1024
MAX_ENTRIES = 10_000
# Headers (512 bytes each, plus pax/long-name records) are not part of the declared sizes; the stream
# position is capped at the data limit plus this allowance.
HEADER_ALLOWANCE = 48 * 1024 * 1024
ROOT = "src"
_CHUNK = 1 << 20

_CITE = "contracts/archive-layout.md"


def _reject(rule: str, msg: str, remedy: str) -> Rejected:
    return Rejected(rule, msg, remedy)


@dataclass
class Limits:
    max_uncompressed: int = MAX_UNCOMPRESSED_BYTES
    max_compressed: int = MAX_COMPRESSED_BYTES
    max_entries: int = MAX_ENTRIES


@dataclass
class Entry:
    rel: tuple[str, ...]     # path components below the root ("" root itself = ())
    kind: str                # "file" | "dir" | "symlink"
    mode: int
    size: int = 0
    offset_data: int = 0
    target: str = ""


@dataclass
class Plan:
    root: str
    entries: list[Entry] = field(default_factory=list)
    total_bytes: int = 0
    count: int = 0


class _BoundedStream:
    """Seekable view of the decompressed stream that refuses to go past `hard_limit` bytes, and
    reads in chunks so one hostile length field cannot make us allocate it in one go."""

    def __init__(self, path: str, hard_limit: int):
        self._f = gzip.GzipFile(path, "rb")
        self._limit = hard_limit

    def tell(self) -> int:
        return self._f.tell()

    def read(self, n: int = -1) -> bytes:
        if n is None or n < 0:
            n = self._limit + 1
        parts = []
        remaining = n
        while remaining > 0:
            b = self._f.read(min(_CHUNK, remaining))
            if not b:
                break
            parts.append(b)
            remaining -= len(b)
            if self._f.tell() > self._limit:
                raise _reject("archive-limits/uncompressed-size", f"the decompressed stream passed {self._limit} bytes", "reduce the size of the repository tree")
        return b"".join(parts)

    def seek(self, pos: int, whence: int = 0) -> int:
        if whence != 0:
            raise OSError("only absolute seeks are supported")
        cur = self._f.tell()
        if pos > cur:
            while cur < pos:
                b = self._f.read(min(_CHUNK, pos - cur))
                if not b:
                    break
                cur += len(b)
                if cur > self._limit:
                    raise _reject("archive-limits/uncompressed-size", f"the decompressed stream passed {self._limit} bytes", "reduce the size of the repository tree")
            return cur
        return self._f.seek(pos)

    def close(self) -> None:
        self._f.close()


def _type_name(t: bytes) -> str:
    names = {
        tarfile.LNKTYPE: "hard link", tarfile.CHRTYPE: "character device", tarfile.BLKTYPE: "block device",
        tarfile.FIFOTYPE: "FIFO", tarfile.CONTTYPE: "contiguous-file", tarfile.GNUTYPE_SPARSE: "GNU sparse file",
    }
    return names.get(t, f"unknown entry type {t!r}")


def _split(name: str) -> tuple[str, ...]:
    if name.startswith("/"):
        raise _reject("archive-layout/absolute-path", f"tar entry {name!r} is an absolute path ({_CITE}, path-escape rule)", "do not commit files with absolute names; rebuild the repository tree normally")
    segs = name.split("/")
    if ".." in segs:
        raise _reject("archive-layout/path-escape", f"tar entry {name!r} contains a '..' segment ({_CITE}, path-escape rule)", "remove the path-traversal entry from the repository")
    if any(s in ("", ".") for s in segs):
        raise _reject("archive-layout/non-normalised-name", f"tar entry {name!r} has an empty or '.' path segment ({_CITE}, malformed archives)", "the archive must be produced by `git archive`")
    return tuple(segs)


def _check_symlink_target(name: str, target: str) -> None:
    if target == "":
        raise _reject("archive-layout/symlink-escape", f"symlink {name!r} has an empty target ({_CITE})", "remove the symlink")
    if target.startswith("/"):
        raise _reject("archive-layout/symlink-escape", f"symlink {name!r} -> {target!r} is absolute ({_CITE}, path-escape rule)", "remove the symlink or make it a regular file")
    if ".." in target.split("/"):
        raise _reject("archive-layout/symlink-escape", f"symlink {name!r} -> {target!r} contains a '..' segment ({_CITE}, path-escape rule)", "remove the symlink or make it a regular file")


def inspect_archive(path: str, limits: Limits | None = None, expected_root: str = ROOT) -> Plan:
    """Validate `path` (a .tar.gz) as a whole; return the extraction plan or raise Rejected."""
    limits = limits or Limits()
    size = os.path.getsize(path)
    if size > limits.max_compressed:
        raise _reject("archive-limits/compressed-size", f"compressed tarball is {size} bytes, over the {limits.max_compressed} byte limit", "reduce the size of the repository tree at this commit")
    stream = _BoundedStream(path, limits.max_uncompressed + HEADER_ALLOWANCE)
    plan = Plan(root=expected_root)
    seen: dict[tuple[str, ...], str] = {}      # normalised path -> kind of the explicit entry
    implicit: set[tuple[str, ...]] = set()     # directories implied only by a deeper entry
    symlinks: set[tuple[str, ...]] = set()
    try:
        tf = tarfile.open(fileobj=stream, mode="r:")
        try:
            while True:
                m = tf.next()
                if m is None:
                    break
                t = m.type
                if t == tarfile.XGLTYPE:
                    continue   # pax global header (git archive writes one); carries no file
                plan.count += 1
                if plan.count > limits.max_entries:
                    raise _reject("archive-limits/entry-count", f"more than {limits.max_entries} entries", "reduce the number of files in the repository")
                if t in (tarfile.REGTYPE, tarfile.AREGTYPE):
                    kind = "file"
                elif t == tarfile.DIRTYPE:
                    kind = "dir"
                elif t == tarfile.SYMTYPE:
                    kind = "symlink"
                else:
                    raise _reject(
                        "archive-layout/entry-type",
                        f"tar entry {m.name!r} is a {_type_name(t)}; only regular files, directories and symlinks are allowed "
                        f"({_CITE} is silent on this; docs/pipeline/build-pipeline.md design 4)",
                        "remove the entry from the repository",
                    )
                if m.mode & 0o7000:
                    raise _reject("archive-layout/special-mode", f"tar entry {m.name!r} has setuid/setgid/sticky bits (mode {m.mode:o})", "commit files with ordinary modes (644/755)")
                segs = _split(m.name)
                if segs[0] != expected_root:
                    if len(segs) == 1 and kind != "dir":
                        raise _reject("archive-layout/no-root", f"tar entry {m.name!r} sits at the archive's top level; every entry needs the single root directory {expected_root!r} ({_CITE})", "rebuild with git archive --prefix=src/")
                    raise _reject("archive-layout/multiple-roots", f"tar entry {m.name!r} is not under the single root {expected_root!r} ({_CITE}, root convention)", "rebuild with git archive --prefix=src/")
                rel = segs[1:]
                if kind == "file" and len(segs) == 1:
                    raise _reject("archive-layout/no-root", f"the root {expected_root!r} is a file, not a directory ({_CITE})", "rebuild with git archive --prefix=src/")
                # duplicate names, write-through-a-symlink, file/directory conflicts
                for i in range(1, len(rel)):
                    pre = rel[:i]
                    if pre in symlinks:
                        raise _reject("archive-layout/write-through-symlink", f"tar entry {m.name!r} is written through the symlink {'/'.join(pre)!r} ({_CITE}; docs/pipeline/build-pipeline.md design 4)", "remove the symlink")
                    if seen.get(pre, "dir") != "dir":
                        raise _reject("archive-layout/path-conflict", f"tar entry {m.name!r} has a parent {'/'.join(pre)!r} that is a {seen[pre]}, not a directory", "remove the conflicting entry")
                    implicit.add(pre)
                if rel in seen:
                    raise _reject("archive-layout/duplicate-entry", f"tar entry {m.name!r} appears more than once", "the archive must contain each path once")
                if rel in implicit and kind != "dir":
                    raise _reject("archive-layout/path-conflict", f"tar entry {m.name!r} is a {kind} but an earlier entry lies beneath it", "remove the conflicting entry")
                if kind != "dir":
                    seen[rel] = kind
                else:
                    seen[rel] = "dir"
                if kind == "symlink":
                    _check_symlink_target(m.name, m.linkname)
                    symlinks.add(rel)
                    plan.entries.append(Entry(rel, "symlink", m.mode, target=m.linkname))
                elif kind == "dir":
                    plan.entries.append(Entry(rel, "dir", m.mode))
                else:
                    plan.total_bytes += m.size
                    if plan.total_bytes > limits.max_uncompressed:
                        raise _reject("archive-limits/uncompressed-size", f"declared uncompressed size passes {limits.max_uncompressed} bytes at {m.name!r}", "reduce the size of the repository tree")
                    plan.entries.append(Entry(rel, "file", m.mode, size=m.size, offset_data=m.offset_data))
        finally:
            tf.close()
    except Rejected:
        raise
    except (tarfile.TarError, EOFError, OSError, zlib.error, UnicodeError, ValueError) as exc:
        raise _reject("archive-layout/malformed", f"not a valid .tar.gz: {type(exc).__name__}: {exc} ({_CITE}, malformed archives)", "rebuild the archive with git archive | gzip -n") from exc
    finally:
        stream.close()
    return plan


def extract(path: str, plan: Plan, dest: str) -> str:
    """Write the validated `plan` below `dest`/<root>; return that directory. `dest` must be new/empty."""
    root_dir = os.path.join(dest, plan.root)
    os.makedirs(root_dir, exist_ok=False)
    real_root = os.path.realpath(root_dir)

    def target(rel: tuple[str, ...]) -> str:
        p = os.path.join(root_dir, *rel)
        if os.path.commonpath([os.path.realpath(os.path.dirname(p) if rel else p), real_root]) != real_root:
            raise PipelineError(f"internal error: extraction path escaped the root: {rel!r}")
        return p

    stream = _BoundedStream(path, 1 << 62)
    try:
        for e in plan.entries:
            if e.kind == "dir":
                os.makedirs(target(e.rel) if e.rel else root_dir, mode=0o755, exist_ok=True)
        for e in plan.entries:
            if e.kind != "file":
                continue
            p = target(e.rel)
            os.makedirs(os.path.dirname(p), mode=0o755, exist_ok=True)
            fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            try:
                stream.seek(e.offset_data)
                left = e.size
                with os.fdopen(fd, "wb") as out:
                    fd = -1
                    while left > 0:
                        b = stream.read(min(_CHUNK, left))
                        if not b:
                            raise _reject("archive-layout/malformed", f"archive is truncated inside {'/'.join(e.rel)!r}", "rebuild the archive")
                        out.write(b)
                        left -= len(b)
            finally:
                if fd >= 0:
                    os.close(fd)
            os.chmod(p, 0o755 if e.mode & 0o111 else 0o644)
        for e in plan.entries:
            if e.kind == "symlink":
                p = target(e.rel)
                os.makedirs(os.path.dirname(p), mode=0o755, exist_ok=True)
                os.symlink(e.target, p)
    except OSError as exc:
        raise _reject("archive-layout/unextractable", f"cannot extract the archive: {exc}", "use ordinary file names and a smaller tree") from exc
    finally:
        stream.close()
    return root_dir
