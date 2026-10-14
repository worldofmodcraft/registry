"""Fetching an exact commit and archiving it, without ever checking attacker content out.

Design decision 1 and 2 of docs/pipeline/build-pipeline.md:
  git clone --no-checkout -- <url> <dir>      (no working tree: no smudge/clean filters, no LFS,
                                                no hooks - hooks are not cloned - on attacker content)
  git cat-file -e <commit>^{commit}
  git archive --format=tar --prefix=src/ <commit>  ->  gzip -n
Transport is restricted to https (design 1); `--allow-local-source` is the tests' escape hatch.
"""

from __future__ import annotations

import os
import re
import shutil
import urllib.parse

from pipeline_errors import PipelineError, Rejected
from procutil import run_bounded

ROOT_PREFIX = "src"           # the fixed archive root literal (design 2)
CLONE_TIMEOUT_S = 300.0       # A-2: wall-clock limit for the clone
MAX_CLONE_BYTES = 512 * 1024 * 1024   # A-2: size cap on the clone directory (assumed constant)
ARCHIVE_TIMEOUT_S = 300.0

_HEX40 = re.compile(r"[0-9a-f]{40}")


def check_source_url(url: str, allow_local: bool) -> str:
    """Return the string to hand to `git clone`, or raise Rejected naming the rule.

    Called before any process is spawned."""
    remedy = "publish a public https URL (https://host/path.git) with no credentials in it"
    if not isinstance(url, str) or not url or url != url.strip() or re.search(r"[\x00-\x20\x7f]", url):
        raise Rejected("clone-transport/malformed", f"source_url {url!r} is empty or contains whitespace/control characters", remedy)
    if url.startswith("-"):
        raise Rejected("clone-transport/option-shaped", f"source_url {url!r} starts with '-' and would be read as a git option", remedy)
    if url.startswith("https://"):
        parts = urllib.parse.urlsplit(url)
        if "@" in parts.netloc:
            raise Rejected("clone-transport/userinfo", "source_url carries credentials (userinfo) - credentials in a stored URL are refused", remedy)
        if not parts.hostname:
            raise Rejected("clone-transport/malformed", f"source_url {url!r} has no host", remedy)
        return url
    if allow_local:
        if url.startswith("file://"):
            return url
        if os.path.isabs(url) and os.path.isdir(url):
            return url
    scheme = url.split("://", 1)[0] if "://" in url else ("scp-like" if re.match(r"^[^/]*@[^/]*:", url) else "local-path-or-unknown")
    raise Rejected(
        "clone-transport/scheme-not-allowed",
        f"source_url scheme {scheme!r} is not allowed: only https:// is accepted (ADR-0058 section 4 reading, docs/pipeline/build-pipeline.md design 1)",
        remedy,
    )


def git_env(allow_local: bool, home: str | None = None) -> dict[str, str]:
    """Whitelisted environment for every git invocation. Nothing else is inherited."""
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_ALLOW_PROTOCOL": "file" if allow_local else "https",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_ASKPASS": "/bin/false",
    }
    if home:
        env["HOME"] = home
    elif "HOME" in os.environ:
        env["HOME"] = os.environ["HOME"]
    if "TMPDIR" in os.environ:
        env["TMPDIR"] = os.environ["TMPDIR"]
    return env


def _protocol_flags(allow_local: bool) -> list[str]:
    return [
        "-c", "protocol.ext.allow=never",
        "-c", "protocol.file.allow=" + ("always" if allow_local else "never"),
    ]


def clone(url: str, dest: str, *, allow_local: bool, timeout: float, max_bytes: int, log) -> None:
    template = dest + ".empty-template"
    os.makedirs(template)
    cmd = (
        ["git"] + _protocol_flags(allow_local)
        + ["clone", "--no-checkout", "--no-tags", "--template=" + template]
        + (["--no-local"] if allow_local else [])
        + ["--", url, dest]
    )
    log("git clone --no-checkout (transport restricted, config isolated)")
    res = run_bounded(
        cmd, git_env(allow_local), timeout=timeout, what="git clone", watch_path=dest, max_bytes=max_bytes,
        size_rule="clone-size-cap",
        size_message=f"the repository is larger than the {max_bytes} byte clone limit",
        size_remedy="reduce the repository size (remove large history/binaries) or publish a smaller repository",
    )
    shutil.rmtree(template, ignore_errors=True)
    if res.returncode != 0:
        raise PipelineError(f"git clone failed (exit {res.returncode}): {res.stderr.strip()[:2000]}")


def has_commit(repo: str, commit: str, *, allow_local: bool, timeout: float) -> bool:
    if not _HEX40.fullmatch(commit):
        raise ValueError("commit must be 40 lowercase hex")
    res = run_bounded(
        ["git", "-C", repo, "cat-file", "-e", commit + "^{commit}"], git_env(allow_local),
        timeout=timeout, what="git cat-file",
    )
    return res.returncode == 0


def archive_to_tar(repo: str, commit: str, tar_path: str, *, allow_local: bool, timeout: float, max_tar_bytes: int) -> None:
    if not _HEX40.fullmatch(commit):
        raise ValueError("commit must be 40 lowercase hex")
    res = run_bounded(
        ["git", "-C", repo, "archive", "--format=tar", f"--prefix={ROOT_PREFIX}/", commit],
        git_env(allow_local), timeout=timeout, what="git archive", stdout_path=tar_path,
        watch_path=tar_path, max_bytes=max_tar_bytes,
        size_rule="archive-uncompressed-size-limit",
        size_message=f"git archive output exceeds the {max_tar_bytes} byte uncompressed size limit",
        size_remedy="reduce the size of the repository tree at this commit",
    )
    if res.returncode != 0:
        raise PipelineError(f"git archive failed (exit {res.returncode}): {res.stderr.strip()[:2000]}")


def gzip_deterministic(tar_path: str, out_path: str, *, timeout: float, max_bytes: int) -> None:
    """`gzip -n`: no name and no timestamp in the header, so equal input gives equal bytes."""
    res = run_bounded(
        ["gzip", "-n", "-c", tar_path], {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "LC_ALL": "C"},
        timeout=timeout, what="gzip", stdout_path=out_path, watch_path=out_path, max_bytes=max_bytes,
        size_rule="archive-compressed-size-limit",
        size_message=f"the compressed tarball exceeds the {max_bytes} byte limit",
        size_remedy="reduce the size of the repository tree at this commit",
    )
    if res.returncode != 0:
        raise PipelineError(f"gzip failed (exit {res.returncode}): {res.stderr.strip()[:500]}")
