"""Signing with the reference `minisign` binary, and reading the public key's id.

The key is a PATH (design 6): never key bytes in an argument, never read by this process, never
logged. The trusted comment follows contracts/signature-format.md exactly:
    format=1;id=<id>;version=<version>;sha256=<sha256>
"""

from __future__ import annotations

import os
import re
import shutil

from pipeline_errors import PipelineError
from procutil import run_bounded

SIGN_TIMEOUT_S = 60.0
_KEYID_RE = re.compile(r"^untrusted comment: minisign public key ([0-9A-F]{16})$")


def trusted_comment(mod_id: str, version: str, sha256: str) -> str:
    return f"format=1;id={mod_id};version={version};sha256={sha256}"


def _env() -> dict[str, str]:
    return {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "LC_ALL": "C"}


def require_minisign() -> str:
    path = shutil.which("minisign")
    if not path:
        raise PipelineError("minisign is not installed or not on PATH (see docs/pipeline/build-pipeline.md, 'not verified')")
    return path


def pubkey_key_id(pubkey_path: str) -> str:
    """The 16 uppercase hex characters on the public key file's comment line, verbatim
    (signature-format.md: copied from the comment line, never re-derived)."""
    try:
        with open(pubkey_path, "r", encoding="utf-8") as f:
            first = f.readline().rstrip("\n")
    except (OSError, UnicodeDecodeError) as exc:
        raise PipelineError(f"cannot read the public key file: {exc}")
    m = _KEYID_RE.match(first)
    if not m:
        raise PipelineError("public key file does not start with 'untrusted comment: minisign public key <16 hex>'")
    return m.group(1)


def sign(key_path: str, tarball: str, sig_path: str, comment: str) -> None:
    require_minisign()
    if not os.path.isfile(key_path):
        raise PipelineError("the --key path is not a readable file")
    if os.path.exists(sig_path):
        os.unlink(sig_path)
    res = run_bounded(
        ["minisign", "-S", "-s", key_path, "-m", tarball, "-x", sig_path, "-t", comment],
        _env(), timeout=SIGN_TIMEOUT_S, what="minisign -S",
    )
    if res.returncode != 0 or not os.path.isfile(sig_path):
        # minisign's stderr never contains key material; still, bound it and do not echo the key path.
        raise PipelineError(f"minisign could not sign (exit {res.returncode}): {res.stderr.strip()[:300]}")


def minisign_verify(pubkey_path: str, target: str, sig_path: str) -> tuple[bool, str]:
    """(ok, stderr+hint). Delegates the Ed25519 / BLAKE2b work to the reference binary."""
    require_minisign()
    res = run_bounded(
        ["minisign", "-V", "-p", pubkey_path, "-m", target, "-x", sig_path],
        _env(), timeout=SIGN_TIMEOUT_S, what="minisign -V",
    )
    return res.returncode == 0, res.stderr
