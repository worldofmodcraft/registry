#!/usr/bin/env python3
"""Sign a tarball that the build job produced with `build_version.py --no-sign` (task 008b-2, design 8).

    python3 tools/pipeline/sign_built.py --tarball <tag>.tar.gz --result result.json \
        --key <minisign secret key file> --pubkey <public key file> --out <dir>

The build job cloned an author-controlled URL, so its output is untrusted input to this step. Before
signing, the tarball is re-checked from its own bytes, independently of the build job: compressed size,
uncompressed size, entry count and every per-entry rule (archive.inspect_archive, 008a's limits), and
sha256(tarball) == result.json artifact.source_sha256. Any mismatch is a named refusal (exit 1) and nothing
is signed. The signature is produced with signing.sign and must pass reference_verify.verify, else exit 2.

Exit codes: 0 signed; 1 refused (the artefact failed re-verification; the line starts `REFUSED [rule]`);
2 usage or pipeline error (bad arguments, minisign missing, signing failed, signature fails verification).
The workflow's handoff layer (handoff.py finish-sign) maps BOTH 1 and 2 to outcome exit_code 2: only 008a's
own exit 1 is a rejection of the author's version.

Output in --out (created only on success): <tag>.tar.gz, <tag>.tar.gz.minisig, result.json with
`signed: true`, artifact.signature and artifact.key_id. The key is a PATH: this process never reads, logs or
prints key bytes. See docs/pipeline/build-pipeline.md.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tarfile
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import archive  # noqa: E402
import build_version  # noqa: E402  (008a's patterns and schema validator are reused, not re-implemented)
import naming  # noqa: E402
import reference_verify  # noqa: E402
import signing  # noqa: E402
from pipeline_errors import PipelineError, Rejected  # noqa: E402

_SHA_RE = re.compile(r"[0-9a-f]{64}")


def _scan_keys() -> frozenset:
    with open(os.path.join(os.path.dirname(HERE), "..", "contracts", "validation-report.schema.json"), "r", encoding="utf-8") as f:
        return frozenset(json.load(f)["properties"])


# The exact shape build_version.py --no-sign writes (docs/pipeline/build-pipeline.md); the build job is untrusted,
# so nothing outside it is copied into the signed result.json.
_RESULT_KEYS = frozenset({"id", "version", "tag", "assets", "built_at", "artifact", "signed", "scan"})
_ASSET_KEYS = frozenset({"tarball", "signature"})
_ARTIFACT_KEYS = frozenset({"source_sha256"})


class SignRefused(Exception):
    """The built artefact failed re-verification: named, nothing signed (exit 1 of this tool)."""

    def __init__(self, rule: str, message: str):
        super().__init__(message)
        self.rule = rule
        self.message = message

    def __str__(self) -> str:
        return f"REFUSED [{self.rule}]: {self.message}"


def _sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _read_result(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as f:
            res = json.load(f)
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        raise SignRefused("result/unreadable", f"result.json cannot be read as JSON: {exc}")
    if not isinstance(res, dict):
        raise SignRefused("result/shape", "result.json is not a JSON object")
    art = res.get("artifact")
    assets = res.get("assets")
    if not (isinstance(art, dict) and isinstance(assets, dict) and isinstance(res.get("id"), str)
            and isinstance(res.get("version"), str) and isinstance(res.get("tag"), str)):
        raise SignRefused("result/shape", "result.json lacks id, version, tag, assets or artifact")
    if res.get("signed") is not False:
        raise SignRefused("result/already-signed", "result.json does not say `signed: false`; only an unsigned build result is signed here")
    if "signature" in art or "key_id" in art:
        raise SignRefused("result/already-signed", "result.json already carries artifact.signature or artifact.key_id")
    if (set(res) != _RESULT_KEYS or set(assets) != _ASSET_KEYS or set(art) != _ARTIFACT_KEYS
            or not isinstance(res.get("scan"), dict) or set(res["scan"]) != _scan_keys()):
        raise SignRefused("result/shape", "result.json has keys outside 008a's result shape")
    if not build_version._fullmatch(build_version._PAT_PUBLISHED_AT, res["built_at"]):
        raise SignRefused("result/built-at", "built_at is not an RFC 3339 UTC timestamp (entry.schema.json published_at pattern)")
    sc = build_version._load_schema_check()
    try:
        sc.validate(res["scan"], build_version._load_schema("validation-report.schema.json"))
    except sc.SchemaValidationError as exc:
        raise SignRefused("result/scan", f"scan does not satisfy validation-report.schema.json: {exc}")
    if not (isinstance(art.get("source_sha256"), str) and _SHA_RE.fullmatch(art["source_sha256"])):
        raise SignRefused("result/sha-format", "artifact.source_sha256 is not 64 lowercase hex characters")
    return res


def verify_built(tarball: str, res: dict, limits: archive.Limits) -> None:
    """Every re-check that must pass before signing. Raises SignRefused."""
    try:
        ns, nm = naming.split_id(res["id"])
    except ValueError as exc:
        raise SignRefused("result/id", str(exc))
    tag = naming.release_tag(ns, nm, res["version"])
    tarball_name, sig_name = naming.asset_names(ns, nm, res["version"])
    if res["tag"] != tag or res["assets"].get("tarball") != tarball_name or res["assets"].get("signature") != sig_name:
        raise SignRefused("result/naming", f"tag and asset names in result.json do not follow artifact-naming.md for {res['id']}@{res['version']}")
    if os.path.basename(tarball) != tarball_name:
        raise SignRefused("tarball/name", f"the tarball is named {os.path.basename(tarball)!r}, expected {tarball_name!r}")
    comment = signing.trusted_comment(res["id"], res["version"], res["artifact"]["source_sha256"])
    if not reference_verify._COMMENT_RE.fullmatch(comment):
        raise SignRefused("result/trusted-comment", f"id or version would not form a valid trusted comment: {comment!r}")
    try:
        size = os.path.getsize(tarball)
    except OSError as exc:
        raise SignRefused("tarball/unreadable", f"cannot stat the tarball: {exc}")
    if size > limits.max_compressed:
        raise SignRefused("tarball/compressed-size", f"tarball is {size} bytes, over the {limits.max_compressed} byte limit")
    try:
        archive.inspect_archive(tarball, limits)
    except Rejected as exc:
        raise SignRefused(f"tarball/{exc.rule}", f"{exc.message} (re-check by the signing job, independent of the build job)")
    except (PipelineError, OSError, EOFError, zlib.error, tarfile.TarError) as exc:
        raise SignRefused("tarball/unreadable", f"the tarball cannot be inspected: {type(exc).__name__}: {exc}")
    actual = _sha256(tarball)
    if actual != res["artifact"]["source_sha256"]:
        raise SignRefused("tarball/sha-mismatch", f"sha256 of the tarball is {actual}, result.json says {res['artifact']['source_sha256']}")


def sign_built(tarball: str, result_path: str, key: str, pubkey: str, out: str, limits: archive.Limits | None = None) -> dict:
    """Re-verify, sign, verify the signature, write --out. Returns the new result dict."""
    limits = limits or archive.Limits()
    res = _read_result(result_path)
    verify_built(tarball, res, limits)
    if os.path.exists(out) and (not os.path.isdir(out) or os.listdir(out)):
        raise PipelineError("--out must not exist or must be an empty directory")
    key_id = signing.pubkey_key_id(pubkey)
    sha = res["artifact"]["source_sha256"]
    with tempfile.TemporaryDirectory(prefix="wom008b2-sign-") as td:
        tgz = os.path.join(td, res["assets"]["tarball"])
        shutil.copyfile(tarball, tgz)           # sign the bytes that were just checked, not a path that can change
        if _sha256(tgz) != sha:
            raise SignRefused("tarball/sha-mismatch", "the tarball changed while it was being copied")
        sig_path = os.path.join(td, res["assets"]["signature"])
        signing.sign(key, tgz, sig_path, signing.trusted_comment(res["id"], res["version"], sha))
        with open(sig_path, "r", encoding="utf-8", newline="") as f:
            sig_text = f.read()
        try:
            reference_verify.verify(tgz, reference_verify.VersionClaim(res["id"], res["version"], sha, key_id, sig_text), {key_id: pubkey})
        except reference_verify.Rejection as exc:
            raise PipelineError(f"the signature just produced fails the reference verifier ({exc}); is --key the secret half of --pubkey?")
        new = dict(res)
        new["artifact"] = dict(res["artifact"], signature=sig_text, key_id=key_id)
        new["signed"] = True
        os.makedirs(out, exist_ok=True)
        shutil.copyfile(tgz, os.path.join(out, res["assets"]["tarball"]))
        shutil.copyfile(sig_path, os.path.join(out, res["assets"]["signature"]))
    with open(os.path.join(out, "result.json"), "w", encoding="utf-8") as f:
        json.dump(new, f, indent=2, sort_keys=True)
        f.write("\n")
    return new


class _Parser(argparse.ArgumentParser):
    def error(self, message):  # argparse's default is already 2; kept explicit
        print(f"ERROR (exit 2): usage: {message}", file=sys.stderr)
        sys.exit(2)


def main(argv=None) -> int:
    p = _Parser(prog="sign_built.py", description="Re-verify and sign a tarball built with build_version.py --no-sign.")
    p.add_argument("--tarball", required=True)
    p.add_argument("--result", required=True, help="the build job's result.json")
    p.add_argument("--key", required=True, help="PATH to the minisign secret key file (never key bytes)")
    p.add_argument("--pubkey", required=True, help="PATH to the matching public key file")
    p.add_argument("--out", required=True, help="output directory (must not exist or be empty)")
    a = p.parse_args(argv)
    try:
        for label, path in (("--tarball", a.tarball), ("--result", a.result), ("--key", a.key), ("--pubkey", a.pubkey)):
            if not os.path.isfile(path):
                raise PipelineError(f"{label} is not a readable file")
        res = sign_built(a.tarball, a.result, a.key, a.pubkey, a.out)
    except SignRefused as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except PipelineError as exc:
        print(f"ERROR (exit 2): {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # noqa: BLE001 - last resort: exit 2, never mistaken for a refusal
        print(f"INTERNAL ERROR (exit 2): {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    print(f"signed {res['tag']}: key_id {res['artifact']['key_id']}; verified by minisign and the reference verifier")
    return 0


if __name__ == "__main__":
    sys.exit(main())
