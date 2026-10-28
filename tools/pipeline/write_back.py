"""Pipeline write-back (task 008c, edge E8): the five write-back values, the project-owned
`source_archive` URL, and the `pending -> published` entry (transition T1, ADR-0121).

Pure functions: no I/O beyond reading the two contract files at import, no process spawning,
no network, no key material (`signature` is the public, detached signature text that
`build_version` already produced). Nothing here checks a hash against a tarball; that is the
E9 verifiers' job (docs/pipeline/build-pipeline.md, "Write-back").
"""

from __future__ import annotations

import copy
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import naming  # noqa: E402
from pipeline_errors import PipelineError, Rejected  # noqa: E402

# The one place the archive hostname is written. Its value is fixed by
# contracts/artifact-naming.md, "The archived-source URL (`source_archive`)".
ARCHIVE_HOST = "archive.worldofmodcraft.com"

# The exact key set of a `pending` version: contracts/append-only.rules.md, "pending" row of the
# key-set table, and the `pending` branch of contracts/entry.schema.json's version `oneOf`.
PENDING_KEYS = frozenset({"version", "commit", "source_url", "status"})

FIVE_KEYS = ("source_archive", "source_sha256", "signature", "key_id", "published_at")


class WriteBackRefused(PipelineError):
    """The write-back cannot be applied: the pipeline is inconsistent (exit 2), never a PR rejection."""

    def __init__(self, reason: str, message: str):
        super().__init__(f"write-back refused [{reason}]: {message}")
        self.reason = reason


def _load_schema() -> dict:
    with open(os.path.join(REPO, "contracts", "entry.schema.json"), "r", encoding="utf-8") as f:
        return json.load(f)


_SCHEMA = _load_schema()
_VPROPS = _SCHEMA["properties"]["versions"]["items"]["properties"]
_PAT_ID = _SCHEMA["properties"]["id"]["pattern"]
_PAT_SEMVER = _VPROPS["version"]["pattern"]


def _ecma_digits(pattern: str) -> str:
    r"""The schema pattern with every unescaped `\d` replaced by `[0-9]` (`0-9` inside a character class).

    Why: the schema patterns are ECMA-262 regexes (JSON Schema's dialect). ECMA `\d` is ASCII-only, but Python's
    default `re` `\d` matches any Unicode decimal digit (Arabic-Indic, fullwidth, ...). ECMA `\s`/`\S` are
    Unicode-aware (they cover NBSP, U+2028, ...) and Python's default `re` agrees, so `\s`/`\S` are left alone and
    no global flag (`re.ASCII` would narrow `\S` too) is used. Escapes are consumed in pairs, so `\\d` (a literal
    backslash, then `d`) is not mangled. `\D` would need its own translation; none of the schema's patterns has
    one, so it raises rather than silently keeping Python's meaning."""
    out, i, in_class = [], 0, False
    while i < len(pattern):
        c = pattern[i]
        if c == "\\":
            if i + 1 >= len(pattern):
                raise NotImplementedError(f"pattern {pattern!r}: dangling backslash")
            e = pattern[i + 1]
            if e == "d":
                out.append("0-9" if in_class else "[0-9]")
            elif e == "D":
                raise NotImplementedError(f"pattern {pattern!r}: \\D is not translated to ECMA-262 semantics")
            else:
                out.append(pattern[i:i + 2])
            i += 2
            continue
        if c == "[":
            in_class = True
        elif c == "]":
            in_class = False
        out.append(c)
        i += 1
    return "".join(out)


_PATTERNS = {k: _ecma_digits(_VPROPS[k]["pattern"]) for k in ("source_archive", "source_sha256", "key_id", "published_at")}
_PAT_ID = _ecma_digits(_PAT_ID)
_PAT_SEMVER = _ecma_digits(_PAT_SEMVER)


def _fullmatch(pattern: str, value) -> bool:
    # fullmatch, not search: `$` would tolerate a trailing newline. The pattern was translated by `_ecma_digits` when
    # it was loaded (no re flag here; see that function for why).
    return isinstance(value, str) and re.fullmatch(pattern, value) is not None


def source_archive_url(namespace: str, name: str, version: str) -> str:
    """The project-owned archive URL (contracts/artifact-naming.md). Invalid triples are refused
    before any string is built; `+` is written literally, never percent-encoded."""
    if not (isinstance(namespace, str) and isinstance(name, str) and _fullmatch(_PAT_ID, f"{namespace}:{name}")):
        raise WriteBackRefused("bad-id", f"{namespace!r}:{name!r} does not match entry.schema.json's id pattern")
    if not _fullmatch(_PAT_SEMVER, version):
        raise WriteBackRefused("bad-version", f"{version!r} is not a semver string (entry.schema.json)")
    try:
        naming.check_namespace(namespace)
    except Rejected as exc:
        # 008a's check is a statement about a version; here the caller handed us an id that
        # should never have passed validation, so it is a pipeline inconsistency (exit 2).
        raise WriteBackRefused("reserved-namespace", exc.message) from exc
    tag = naming.release_tag(namespace, name, version)
    return f"https://{ARCHIVE_HOST}/{tag}/{tag}.tar.gz"


def write_back_values(result: dict, source_archive: str) -> dict:
    """The five values for E8. `published_at` is the pipeline's own `built_at`, recorded once.
    `source_archive` is passed through; its equality with the derived URL is not checked here."""
    try:
        art = result["artifact"]
        values = {
            "source_archive": source_archive,
            "source_sha256": art["source_sha256"],
            "signature": art["signature"],
            "key_id": art["key_id"],
            "published_at": result["built_at"],
        }
    except (KeyError, TypeError) as exc:
        raise WriteBackRefused("result-missing-field", f"result lacks a field the write-back needs: {exc!r}")
    return values


def apply_write_back(entry: dict, result: dict, source_archive: str) -> dict:
    """Return a new entry in which the version `result` built has gone `pending -> published`.
    Inputs are never mutated."""
    if not isinstance(entry, dict) or not isinstance(entry.get("versions"), list):
        raise WriteBackRefused("entry-malformed", "entry is not an object with a versions array")
    if not isinstance(result, dict):
        raise WriteBackRefused("result-malformed", "result is not an object")
    if result.get("id") != entry.get("id"):
        raise WriteBackRefused("id-mismatch", f"result is for {result.get('id')!r}, entry is {entry.get('id')!r}")
    rv = result.get("version")
    matches = [i for i, v in enumerate(entry["versions"]) if isinstance(v, dict) and v.get("version") == rv]
    if not matches:
        raise WriteBackRefused("version-absent", f"no version of the entry equals {rv!r}")
    if len(matches) > 1:
        raise WriteBackRefused("version-duplicate", f"{len(matches)} versions equal {rv!r}")
    idx = matches[0]
    status = entry["versions"][idx].get("status")
    if status != "pending":
        raise WriteBackRefused("not-pending", f"version {rv!r} has status {status!r}; only `pending` may be written back (ADR-0121)")

    if set(entry["versions"][idx]) != PENDING_KEYS:
        raise WriteBackRefused("pending-shape", f"version {rv!r} has keys {sorted(entry['versions'][idx])}, a pending version has exactly {sorted(PENDING_KEYS)} (append-only.rules.md)")

    values = write_back_values(result, source_archive)
    if set(values) != set(FIVE_KEYS) or len(values) != len(FIVE_KEYS):
        raise WriteBackRefused("key-set", f"write-back values have keys {sorted(values)}, expected exactly {sorted(FIVE_KEYS)}")
    for k, pat in _PATTERNS.items():
        if not _fullmatch(pat, values[k]):
            raise WriteBackRefused("bad-value", f"{k} {values[k]!r} does not match entry.schema.json's pattern")
    if not isinstance(values["signature"], str) or values["signature"] == "":
        raise WriteBackRefused("bad-value", "signature is empty or not a string")

    out = copy.deepcopy(entry)
    version_obj = out["versions"][idx]
    version_obj.update(copy.deepcopy(values))
    version_obj["status"] = "published"
    return out
