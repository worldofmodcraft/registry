"""Reference verifier for contracts/signature-format.md ("What a verifier must reject", rules 1-11).

Written for task 008a as an INDEPENDENT second implementation: it imports nothing from the signing
code, derives the key id by reversing bytes itself, and checks the signature file's structure from
the contract text. The one thing it does not implement is Ed25519/BLAKE2b arithmetic (task forbids
hand-rolling it): `minisign -V` does that. minisign verifies the core signature (rule 4) and the
global signature (rule 5) in one run; its error text separates them ("Comment signature
verification failed" is rule 5, any other failure rule 4).

Order of checks: 1, 2, 3, 6, 7, 8, then 4/5 via minisign, then 9, 10, 11. Each Rejection carries the
contract's rule number.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import os
import re
import subprocess
import tempfile
from dataclasses import dataclass

_ID_RE = r"[a-z0-9][a-z0-9_-]*:[a-z0-9][a-z0-9_-]*"
_SEMVER_RE = (
    r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
    r"(?:-(?:(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?"
    r"(?:\+[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*)?"
)
_COMMENT_RE = re.compile(rf"format=1;id=({_ID_RE});version=({_SEMVER_RE});sha256=([0-9a-f]{{64}})")
_PUBKEY_LINE = re.compile(r"^untrusted comment: minisign public key ([0-9A-F]{16})$")


class Rejection(Exception):
    def __init__(self, rule: int, message: str):
        super().__init__(f"rule {rule}: {message}")
        self.rule = rule
        self.message = message


@dataclass
class VersionClaim:
    """The fields of the entry's version object this verification is about."""
    id: str
    version: str
    source_sha256: str
    key_id: str
    signature: str


def pubkey_comment_id(pubkey_path: str) -> str:
    with open(pubkey_path, "r", encoding="utf-8") as f:
        m = _PUBKEY_LINE.match(f.readline().rstrip("\n"))
    if not m:
        raise ValueError("not a minisign public key file")
    return m.group(1)


def parse_signature(text: str) -> tuple[bytes, bytes, str, bytes]:
    """Rules 1-3. Returns (line2 bytes, line4 bytes, trusted comment raw string, algo)."""
    body = text[:-1] if text.endswith("\n") else text
    lines = body.split("\n")
    if len(lines) != 4:
        raise Rejection(1, f"signature has {len(lines)} lines, expected exactly four")
    if not lines[0].startswith("untrusted comment:"):
        raise Rejection(1, "line 1 does not start with 'untrusted comment:'")
    if not lines[2].startswith("trusted comment: "):
        raise Rejection(1, "line 3 does not start with 'trusted comment: '")
    try:
        l2 = base64.b64decode(lines[1], validate=True)
        l4 = base64.b64decode(lines[3], validate=True)
    except (binascii.Error, ValueError) as exc:
        raise Rejection(2, f"base64 payload does not decode: {exc}")
    if len(l2) != 74:
        raise Rejection(2, f"line 2 decodes to {len(l2)} bytes, expected 74")
    if len(l4) != 64:
        raise Rejection(2, f"line 4 decodes to {len(l4)} bytes, expected 64")
    if l2[:2] not in (b"Ed", b"ED"):
        raise Rejection(3, f"algorithm bytes {l2[:2]!r} are neither 'Ed' nor 'ED'")
    return l2, l4, lines[2][len("trusted comment: "):], l2[:2]


def verify(tarball_path: str, claim: VersionClaim, trusted_pubkeys: dict[str, str]) -> str:
    """Return the trusted comment on acceptance; raise Rejection(rule) otherwise.

    `trusted_pubkeys` maps a 16-hex key id (as stored in entry.json) to a public key file path.
    The key is selected by looking `claim.key_id` up (rule 7), never by trying every key."""
    l2, l4, comment, _algo = parse_signature(claim.signature)

    embedded = l2[2:10][::-1].hex().upper()      # the reversal the contract demonstrates
    if embedded != claim.key_id:
        raise Rejection(6, f"entry key_id {claim.key_id} != key id embedded in the signature ({embedded}, bytes reversed)")
    pub = trusted_pubkeys.get(claim.key_id)
    if pub is None:
        raise Rejection(7, f"key_id {claim.key_id} names no trusted public key")

    m = _COMMENT_RE.fullmatch(comment)
    if not m:
        raise Rejection(8, f"trusted comment {comment!r} does not match format=1;id=..;version=..;sha256=..")
    c_id, c_version, c_sha = m.groups()

    with tempfile.TemporaryDirectory(prefix="wom008a-verify-") as td:
        sig_file = os.path.join(td, "sig.minisig")
        with open(sig_file, "w", encoding="utf-8", newline="") as f:
            f.write(claim.signature)
        res = subprocess.run(
            ["minisign", "-V", "-p", pub, "-m", tarball_path, "-x", sig_file],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
    if res.returncode != 0:
        err = res.stderr.strip()
        if "Comment signature verification failed" in err:
            raise Rejection(5, f"global (trusted-comment) signature does not verify: {err}")
        raise Rejection(4, f"core signature does not verify: {err}")

    h = hashlib.sha256()
    with open(tarball_path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    if c_sha != h.hexdigest():
        raise Rejection(9, f"trusted comment sha256 {c_sha} != sha256 computed over the received bytes {h.hexdigest()}")
    if claim.source_sha256 != c_sha:
        raise Rejection(10, f"entry source_sha256 {claim.source_sha256} != trusted comment sha256 {c_sha}")
    if (c_id, c_version) != (claim.id, claim.version):
        raise Rejection(11, f"trusted comment names {c_id}@{c_version}, not this entry's {claim.id}@{claim.version}")
    return comment
