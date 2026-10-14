"""Shared fixtures for the task 008a suite. Everything here is throwaway: keys are generated at test
time inside a temp directory (prefix wom008a-) and removed afterwards; repositories are local;
nothing touches the network or any real credential (CLAUDE.md rule 11)."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
TOOLS = os.path.join(REPO, "tools", "pipeline")
CLI = os.path.join(TOOLS, "build_version.py")
sys.path.insert(0, TOOLS)

REAL_GIT = shutil.which("git") or "/usr/bin/git"

_spec = importlib.util.spec_from_file_location("wom_fixture_builder", os.path.join(REPO, "tests", "validation", "fixture_builder.py"))
fb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fb)

GIT_ENV = {
    "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
    "HOME": os.environ.get("HOME", "/tmp"),
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
    "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid",
    "GIT_AUTHOR_DATE": "2020-01-01T00:00:00Z", "GIT_COMMITTER_DATE": "2020-01-01T00:00:00Z",
}


def git(repo: str, *args: str, env_extra: dict | None = None) -> str:
    env = dict(GIT_ENV)
    env.update(env_extra or {})
    r = subprocess.run([REAL_GIT, "-C", repo, *args], env=env, capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if r.returncode != 0:
        raise RuntimeError(f"git {args} failed: {r.stderr}")
    return r.stdout.strip()


def modlua(mod_id="test:hello", version="1.0.0", license="MIT", extra="", omit=()):
    fields = {
        "id": f'"{mod_id}"', "name": '"Hello"', "version": f'"{version}"', "api_version": '"1"',
        "license": f'"{license}"', "source": '"https://example.invalid/hello.git"', "type": '"mod"',
        "description": '"A test mod."', "tags": '{"test"}', "screenshots": "{}",
    }
    body = ",\n  ".join(f"{k} = {v}" for k, v in fields.items() if k not in omit)
    return f"-- generated test manifest\nreturn {{\n  {body},\n  {extra}\n}}\n"


def make_repo(root: str, name: str, files: dict, symlinks: dict | None = None, modes: dict | None = None) -> tuple[str, str]:
    """Create a local git repo with one commit; return (path, commit)."""
    repo = os.path.join(root, name)
    os.makedirs(repo)
    git(repo, "init", "-q", "-b", "main")
    return repo, commit_files(repo, files, symlinks, modes, "initial")


def commit_files(repo: str, files: dict, symlinks: dict | None = None, modes: dict | None = None, msg: str = "c", date: str | None = None) -> str:
    for rel, data in files.items():
        p = os.path.join(repo, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(data if isinstance(data, bytes) else data.encode())
    for rel, target in (symlinks or {}).items():
        p = os.path.join(repo, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        if os.path.lexists(p):
            os.unlink(p)
        os.symlink(target, p)
    for rel, mode in (modes or {}).items():
        os.chmod(os.path.join(repo, rel), mode)
    git(repo, "add", "-A")
    env = {"GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date} if date else None
    git(repo, "commit", "-q", "--allow-empty", "-m", msg, env_extra=env)
    return git(repo, "rev-parse", "HEAD")


def good_files(mod_id="test:hello", version="1.0.0", **kw) -> dict:
    return {"mod.lua": modlua(mod_id, version, **kw), "README.md": "# hello\n"}


def make_keypair(root: str, name="k", secret_comment: str | None = None) -> tuple[str, str]:
    """Throwaway minisign keypair (no password). Returns (pub, key). Optionally rewrites the secret
    key file's (unauthenticated) first line so tests can plant a canary in it."""
    pub, key = os.path.join(root, f"{name}.pub"), os.path.join(root, f"{name}.key")
    r = subprocess.run(["minisign", "-G", "-W", "-f", "-p", pub, "-s", key], capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if r.returncode != 0:
        raise RuntimeError(f"minisign -G failed: {r.stderr}")
    os.chmod(key, 0o600)
    if secret_comment is not None:
        lines = open(key).read().split("\n")
        lines[0] = "untrusted comment: " + secret_comment
        open(key, "w").write("\n".join(lines))
    return pub, key


def write_entry(path: str, mod_id: str, versions: list[dict]) -> str:
    entry = {"id": mod_id, "owner": {"provider": "github", "id": 1, "name_at_registration": "tester"}, "versions": versions}
    with open(path, "w") as f:
        json.dump(entry, f)
    return path


def vobj(version: str, commit: str, url: str) -> dict:
    return {"version": version, "commit": commit, "source_url": url}


class Base(unittest.TestCase):
    """Per-class temp dir with a throwaway key pair; removed in tearDownClass."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="wom008a-")
        cls.pub, cls.key = make_keypair(cls.tmp)
        cls._n = 0

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def fresh(self, name: str) -> str:
        """A new empty directory (not pre-created if name ends with '!')."""
        type(self)._n += 1
        d = os.path.join(self.tmp, f"{name}{type(self)._n}")
        os.makedirs(d)
        return d

    def run_cli(self, entry: str, version: str, *, extra=(), key=None, pubkey=None, env_extra=None, path_prefix=None, out=None, work=None, drop=()):
        out = out or os.path.join(self.fresh("outparent"), "out")
        work = work or self.fresh("work")
        argv = [sys.executable, CLI, "--entry", entry, "--version", version, "--workdir", work,
                "--key", key or self.key, "--pubkey", pubkey or self.pub, "--out", out]
        argv = [a for a in argv if a not in drop]
        argv += list(extra)
        env = dict(os.environ)
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        if path_prefix:
            env["PATH"] = path_prefix + os.pathsep + env["PATH"]
        env.update(env_extra or {})
        r = subprocess.run(argv, capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL, timeout=300)
        r.out_dir = out
        r.work_dir = work
        return r

    def build_local(self, repo: str, commit: str, mod_id="test:hello", version="1.0.0", **kw):
        entry = write_entry(os.path.join(self.fresh("e"), "entry.json"), mod_id, [vobj(version, commit, repo)])
        return self.run_cli(entry, version, extra=("--allow-local-source",) + tuple(kw.pop("extra", ())), **kw)


# ---- hand-built tarballs ---------------------------------------------------------

def tar_gz(path: str, entries: list[dict], pax_global: bool = False) -> str:
    """entries: dict(name, type=REGTYPE default, data=b"", linkname="", mode=0o644, size=None)."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT if pax_global else tarfile.GNU_FORMAT) as tf:
        for e in entries:
            ti = tarfile.TarInfo(e["name"])
            ti.type = e.get("type", tarfile.REGTYPE)
            ti.mode = e.get("mode", 0o755 if ti.type == tarfile.DIRTYPE else 0o644)
            ti.linkname = e.get("linkname", "")
            ti.mtime = 1577836800
            data = e.get("data", b"")
            ti.size = e["size"] if e.get("size") is not None else (len(data) if ti.type == tarfile.REGTYPE else 0)
            if ti.type == tarfile.REGTYPE and e.get("size") is not None and e["size"] != len(data):
                raw = ti.tobuf(tf.format, tf.encoding, tf.errors)   # header only: declared size, no body
                tf.fileobj.write(raw)
                tf.offset += len(raw)
            elif ti.type == tarfile.REGTYPE:
                tf.addfile(ti, io.BytesIO(data))
            else:
                tf.addfile(ti)
    import gzip
    with open(path, "wb") as f:
        with gzip.GzipFile(fileobj=f, mode="wb", mtime=0) as gz:
            gz.write(buf.getvalue())
    return path


def clean_tar_entries(extra=()):
    return [
        {"name": "src", "type": tarfile.DIRTYPE},
        {"name": "src/mod.lua", "data": modlua().encode()},
        {"name": "src/README.md", "data": b"# hi\n"},
    ] + list(extra)


def write_stub_git(dirpath: str, mode: str, **kw) -> str:
    """A `git` earlier on PATH. mode:
    record  - log argv and GIT_* env to kw['log'], exit 3 (simulated clone failure)
    archive - for `git ... archive` print kw['tar'] (a hand-built .tar.gz decompressed to tar) instead;
              every other subcommand is the real git
    sleep   - sleep 8 then fail (to exercise the wall-clock timeout)
    bigclone- write 20 MB into the clone directory and linger (to exercise the size cap)"""
    os.makedirs(dirpath, exist_ok=True)
    p = os.path.join(dirpath, "git")
    if mode == "record":
        body = f'#!/bin/bash\n{{ echo "ARGV: $*"; env | grep "^GIT_" | sort; }} >> "{kw["log"]}"\nexit 3\n'
    elif mode == "archive":
        body = (f'#!/bin/bash\nfor a in "$@"; do if [ "$a" = "archive" ]; then gzip -dc "{kw["tar"]}"; exit 0; fi; done\n'
                f'exec "{REAL_GIT}" "$@"\n')
    elif mode == "sleep":
        body = "#!/bin/bash\nsleep 8\nexit 3\n"
    elif mode == "bigclone":
        # writes 20 MB into the clone destination (the last argument) and lingers
        body = '#!/bin/bash\nfor a in "$@"; do d="$a"; done\nmkdir -p "$d"\ndd if=/dev/zero of="$d/big" bs=1M count=20 2>/dev/null\nsleep 8\nexit 3\n'
    else:
        raise ValueError(mode)
    with open(p, "w") as f:
        f.write(body)
    os.chmod(p, 0o755)
    return dirpath


def sha256sum(path: str) -> str:
    r = subprocess.run(["sha256sum", path], capture_output=True, text=True, check=True)
    return r.stdout.split()[0]
