#!/usr/bin/env python3
"""Build one registry version: clone, validate, scan, archive, hash, sign (task 008a, offline).

    python3 tools/pipeline/build_version.py --entry <entry.json> --version <semver> \
        --workdir <empty dir> --key <minisign secret key file> --pubkey <public key file> \
        --out <dir> [--allow-local-source]

Exit codes (never conflated, OPERATIONS.md):
    0  built
    1  rejected - the VERSION is bad; the message names the rule/contract clause and the remedy
    2  usage or internal error (bad arguments, missing tool, clone failure, scanner exit 2, timeout)

The commit and source URL are read from the entry's version object; there is no commit argument.
Outputs in --out: <tag>.tar.gz, <tag>.tar.gz.minisig, result.json, build.log.
Pre-flight rejections (before any clone) leave --out untouched and report on stderr only.
See docs/pipeline/build-pipeline.md.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import archive  # noqa: E402
import gitops  # noqa: E402
import naming  # noqa: E402
import reference_verify  # noqa: E402
import signing  # noqa: E402
from pipeline_errors import PipelineError, Rejected  # noqa: E402

sys.path.insert(0, os.path.join(REPO, "tools", "validation"))
import manifest as manifest_reader  # noqa: E402

DEFAULT_SCANNER = os.path.join(REPO, "tools", "validation", "scan_assets.py")
SCAN_TIMEOUT_S = 600.0


def _load_schema_check():
    path = os.path.join(REPO, "tests", "contracts", "schema_check.py")
    spec = importlib.util.spec_from_file_location("wom_contracts_schema_check", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _load_schema(name: str) -> dict:
    with open(os.path.join(REPO, "contracts", name), "r", encoding="utf-8") as f:
        return json.load(f)


# Patterns copied at load time from the contract, matched with fullmatch so a trailing newline
# (which `$` tolerates under re.search) cannot slip through.
_ENTRY_SCHEMA = _load_schema("entry.schema.json")
_VERSION_PROPS = _ENTRY_SCHEMA["properties"]["versions"]["items"]["properties"]
_PAT_ID = _ENTRY_SCHEMA["properties"]["id"]["pattern"]
_PAT_SEMVER = _VERSION_PROPS["version"]["pattern"]
_PAT_COMMIT = _VERSION_PROPS["commit"]["pattern"]
_PAT_PUBLISHED_AT = _VERSION_PROPS["published_at"]["pattern"]


def _fullmatch(pattern: str, value) -> bool:
    return isinstance(value, str) and re.fullmatch(pattern, value) is not None


class Log:
    def __init__(self) -> None:
        self.lines: list[str] = []

    def __call__(self, msg: str) -> None:
        self.lines.append(msg)
        print(msg, flush=True)

    def text(self) -> str:
        return "\n".join(self.lines) + "\n"


def preflight(entry_path: str, version: str, allow_local: bool):
    """Everything decidable before any process is spawned. Raises Rejected (exit 1) or
    PipelineError (exit 2, unreadable/invalid-JSON entry)."""
    try:
        with open(entry_path, "r", encoding="utf-8") as f:
            entry = json.load(f)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PipelineError(f"cannot read --entry as JSON: {exc}")
    if not isinstance(entry, dict):
        raise PipelineError("--entry must contain a JSON object")
    mod_id = entry.get("id")
    if not _fullmatch(_PAT_ID, mod_id):
        raise Rejected("entry/id", f"entry id {mod_id!r} does not match entry.schema.json's id pattern", "fix the entry's id")
    ns, nm = naming.split_id(mod_id)
    naming.check_namespace(ns)
    if not _fullmatch(_PAT_SEMVER, version):
        raise Rejected("version/not-semver", f"--version {version!r} is not a semver string (entry.schema.json)", "pass a version like 1.0.0")
    versions = entry.get("versions")
    if not isinstance(versions, list):
        raise Rejected("entry/versions", "entry has no versions array", "fix the entry")
    matches = [v for v in versions if isinstance(v, dict) and v.get("version") == version]
    if not matches:
        raise Rejected("version/not-in-entry", f"no version object in the entry carries version {version!r}", "add the version to the entry first (publish PR)")
    if len(matches) > 1:
        raise Rejected("version/duplicate", f"{len(matches)} version objects carry version {version!r}", "versions are unique per mod (append-only.rules.md rule 4)")
    vobj = matches[0]
    commit = vobj.get("commit")
    if not _fullmatch(_PAT_COMMIT, commit):
        raise Rejected("commit/not-40-lowercase-hex", f"commit {commit!r} is not 40 lowercase hex characters (entry.schema.json)", "use the full lowercase 40-character commit SHA")
    url = gitops.check_source_url(vobj.get("source_url"), allow_local)
    return mod_id, ns, nm, vobj, commit, url


def validate_manifest(extract_root: str, mod_id: str, version: str) -> dict:
    path = os.path.join(extract_root, "mod.lua")
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        raise Rejected("manifest/missing", "manifest missing in the produced archive: src/mod.lua does not exist", "add mod.lua at the repository root and make sure .gitattributes does not export-ignore it")
    import stat as _stat
    if not _stat.S_ISREG(st.st_mode):
        raise Rejected("manifest/not-a-regular-file", "src/mod.lua is not a regular file (symlinks are not followed)", "make mod.lua a regular file")
    if st.st_size > manifest_reader.MAX_BYTES:
        raise Rejected("manifest/too-large", f"mod.lua is {st.st_size} bytes, over the {manifest_reader.MAX_BYTES} byte limit", "shrink mod.lua")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as f:
        data = f.read()
    try:
        projected = manifest_reader.read_manifest(data)
    except manifest_reader.ManifestError as exc:
        raise Rejected(f"manifest/{exc.rule}", f"mod.lua is not a static literal table: {exc}", "mod.lua must be `return { ... }` with literal values only; it is never executed")
    sc = _load_schema_check()
    try:
        sc.validate(projected, _load_schema("manifest.schema.json"))
    except sc.SchemaValidationError as exc:
        if exc.path == "$.license":
            raise Rejected("manifest/license-not-osi", f"license rejected: {exc.message} (ADR-0049: OSI-approved SPDX identifiers only)", "set license to an OSI-approved SPDX identifier such as MIT or Apache-2.0")
        raise Rejected("manifest/schema", f"mod.lua violates manifest.schema.json: {exc}", "fix the field named above")
    manifest_props = _load_schema("manifest.schema.json")["properties"]
    for key in ("id", "version"):
        if not _fullmatch(manifest_props[key]["pattern"], projected[key]):
            raise Rejected("manifest/schema", f"mod.lua {key} {projected[key]!r} has a trailing or embedded line break", f"fix the {key} field")
    if projected["id"] != mod_id:
        raise Rejected("manifest/id-mismatch", f"mod.lua id {projected['id']!r} != entry id {mod_id!r} (manifest.schema.json: pipeline cross-check)", "make mod.lua's id equal the registry entry's id")
    if projected["version"] != version:
        raise Rejected("manifest/version-mismatch", f"mod.lua version {projected['version']!r} != the version being published {version!r}", "make mod.lua's version equal the published version")
    return projected


def run_scan(directory_parent: str, rel_dir: str, report_path: str, scanner: str) -> dict:
    """Run the existing scanner on `rel_dir` (cwd = its parent). Exit 0 accept, 1 reject; 2 (or
    anything else) is NEVER a rejection: it becomes PipelineError."""
    try:
        res = subprocess.run(
            [sys.executable, scanner, rel_dir, "-o", report_path],
            cwd=directory_parent, stdin=subprocess.DEVNULL, capture_output=True, text=True,
            timeout=SCAN_TIMEOUT_S, env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "LC_ALL": "C", "PYTHONDONTWRITEBYTECODE": "1"},
        )
    except subprocess.TimeoutExpired:
        raise PipelineError(f"asset scanner timed out after {SCAN_TIMEOUT_S:g}s")
    if res.returncode not in (0, 1):
        raise PipelineError(f"asset scanner exited {res.returncode} (a usage/internal error, not a rejection): {res.stderr.strip()[:500]}")
    try:
        with open(report_path, "r", encoding="utf-8") as f:
            report = json.load(f)
        sc = _load_schema_check()
        sc.validate(report, _load_schema("validation-report.schema.json"))
    except Exception as exc:  # noqa: BLE001 - any unreadable/invalid report is an internal error, never a verdict
        raise PipelineError(f"asset scanner produced no valid validation-report (exit {res.returncode}): {exc}")
    if res.returncode == 1:
        rej, errs = report["rejected"], report["scan_errors"]
        if not rej and not errs:
            raise PipelineError("asset scanner exited 1 with an empty rejection list")
        parts = [f"{r['path']}: {r['detected_format']} - {r['reason']} (remedy: {r['remedy']})" for r in rej]
        parts += [f"{e['path']}: scan error - {e['reason']}" for e in errs]
        raise Rejected("asset-scan/rejected", f"{len(rej)} file(s) rejected, {len(errs)} scan error(s) by tools/validation/scan_assets.py (ADR-0004/0120): " + " | ".join(parts[:20]),
                       "remove or replace the listed files with whitelisted formats (PNG, OGG, GLB, plain text); never ship Blizzard data")
    return report


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def make_plan(args) -> dict:
    mod_id, ns, nm, vobj, commit, url = preflight(args.entry, args.version, args.allow_local_source)
    version = args.version
    tarball_name, sig_name = naming.asset_names(ns, nm, version)
    tag = naming.release_tag(ns, nm, version)
    return {"mod_id": mod_id, "ns": ns, "nm": nm, "commit": commit, "url": url, "tag": tag,
            "tarball_name": tarball_name, "sig_name": sig_name}


def execute(args, log: Log, plan: dict) -> dict:
    version = args.version
    work = os.path.abspath(args.workdir)
    clone_dir = os.path.join(work, "clone")
    log(f"building {plan['mod_id']} {version} -> tag {plan['tag']}")
    log(f"commit (from the entry): {plan['commit']}")
    gitops.clone(plan["url"], clone_dir, allow_local=args.allow_local_source,
                 timeout=args.clone_timeout, max_bytes=args.max_clone_bytes, log=log)
    if not gitops.has_commit(clone_dir, plan["commit"], allow_local=args.allow_local_source, timeout=60):
        raise Rejected("commit/not-found", f"commit {plan['commit']} does not exist in the cloned repository (it must be reachable from a branch or tag of the source_url)", "push the commit (or its branch/tag) to the public repository and check the commit hash in the entry")
    tar_path = os.path.join(work, "source.tar")
    tgz_path = os.path.join(work, plan["tarball_name"])
    limits = archive.Limits(args.max_uncompressed_bytes, args.max_compressed_bytes, args.max_entries)
    gitops.archive_to_tar(clone_dir, plan["commit"], tar_path, allow_local=args.allow_local_source,
                          timeout=gitops.ARCHIVE_TIMEOUT_S, max_tar_bytes=limits.max_uncompressed + archive.HEADER_ALLOWANCE)
    gitops.gzip_deterministic(tar_path, tgz_path, timeout=gitops.ARCHIVE_TIMEOUT_S, max_bytes=limits.max_compressed)
    os.unlink(tar_path)
    log(f"archived: {plan['tarball_name']} ({os.path.getsize(tgz_path)} bytes)")

    aplan = archive.inspect_archive(tgz_path, limits)
    log(f"archive inspected: {aplan.count} entries, {aplan.total_bytes} bytes uncompressed, single root {aplan.root!r}")
    extract_parent = os.path.join(work, "extract")
    os.makedirs(extract_parent)
    root_dir = archive.extract(tgz_path, aplan, extract_parent)

    validate_manifest(root_dir, plan["mod_id"], version)
    log("manifest: mod.lua read statically, schema-valid, id and version match the entry")
    report = run_scan(extract_parent, archive.ROOT, os.path.join(work, "scan-report.json"), args.scanner)
    s = report["summary"]
    log(f"asset scan: {s['files_accepted']} accepted, {s['files_rejected']} rejected, {s['files_skipped']} skipped")

    sha = sha256_file(tgz_path)
    log(f"source_sha256: {sha}")
    key_id = signing.pubkey_key_id(args.pubkey)
    sig_path = os.path.join(work, plan["sig_name"])
    signing.sign(args.key, tgz_path, sig_path, signing.trusted_comment(plan["mod_id"], version, sha))
    with open(sig_path, "r", encoding="utf-8", newline="") as f:
        sig_text = f.read()
    try:
        reference_verify.verify(tgz_path, reference_verify.VersionClaim(plan["mod_id"], version, sha, key_id, sig_text), {key_id: args.pubkey})
    except reference_verify.Rejection as exc:
        raise PipelineError(f"the signature just produced fails the reference verifier ({exc}); is --key the secret half of --pubkey?")
    log(f"signed: key_id {key_id}; verified by minisign and the reference verifier")

    built_at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if not _fullmatch(_PAT_PUBLISHED_AT, built_at):
        raise PipelineError(f"internal error: built_at {built_at!r} violates the RFC 3339 pattern")
    return {
        "id": plan["mod_id"], "version": version, "tag": plan["tag"],
        "assets": {"tarball": plan["tarball_name"], "signature": plan["sig_name"]},
        "built_at": built_at,
        "artifact": {"source_sha256": sha, "signature": sig_text, "key_id": key_id},
        "scan": report,
        "_files": (tgz_path, sig_path),
    }


def parse_args(argv):
    p = argparse.ArgumentParser(prog="build_version.py", description="Build, scan, archive, hash and sign one registry version (offline).")
    p.add_argument("--entry", required=True, help="path to the mod's entry.json")
    p.add_argument("--version", required=True, help="semver of the version object to build")
    p.add_argument("--workdir", required=True, help="an existing EMPTY directory for scratch space")
    p.add_argument("--key", required=True, help="PATH to the minisign secret key file (never key bytes)")
    p.add_argument("--pubkey", required=True, help="PATH to the matching public key file")
    p.add_argument("--out", required=True, help="output directory (must not exist or be empty)")
    p.add_argument("--allow-local-source", action="store_true", help="TESTS ONLY: accept file:// URLs and local paths; the workflow never passes this")
    # Test-only knobs. Defaults are the documented constants; tests lower them.
    p.add_argument("--clone-timeout", type=float, default=gitops.CLONE_TIMEOUT_S, help=argparse.SUPPRESS)
    p.add_argument("--max-clone-bytes", type=int, default=gitops.MAX_CLONE_BYTES, help=argparse.SUPPRESS)
    p.add_argument("--max-compressed-bytes", type=int, default=archive.MAX_COMPRESSED_BYTES, help=argparse.SUPPRESS)
    p.add_argument("--max-uncompressed-bytes", type=int, default=archive.MAX_UNCOMPRESSED_BYTES, help=argparse.SUPPRESS)
    p.add_argument("--max-entries", type=int, default=archive.MAX_ENTRIES, help=argparse.SUPPRESS)
    p.add_argument("--scanner", default=DEFAULT_SCANNER, help=argparse.SUPPRESS)
    return p.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    log = Log()
    started = False
    try:
        for label, path in (("--entry", args.entry), ("--key", args.key), ("--pubkey", args.pubkey)):
            if not os.path.isfile(path):
                raise PipelineError(f"{label} is not a readable file")
        plan = make_plan(args)   # pre-flight; raises before anything is created
        if not os.path.isdir(args.workdir) or os.listdir(args.workdir):
            raise PipelineError("--workdir must be an existing empty directory")
        if os.path.exists(args.out) and (not os.path.isdir(args.out) or os.listdir(args.out)):
            raise PipelineError("--out must not exist or must be an empty directory")
        started = True
        result = execute(args, log, plan)
        tgz, sig = result.pop("_files")
        os.makedirs(args.out, exist_ok=True)
        shutil.copyfile(tgz, os.path.join(args.out, plan["tarball_name"]))
        shutil.copyfile(sig, os.path.join(args.out, plan["sig_name"]))
        log(f"result: exit 0 (built {plan['tag']})")
        with open(os.path.join(args.out, "result.json"), "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, sort_keys=True)
            f.write("\n")
        with open(os.path.join(args.out, "build.log"), "w", encoding="utf-8") as f:
            f.write(log.text())
        return 0
    except Rejected as exc:
        print(str(exc), file=sys.stderr)
        _write_failure_log(args, log, started, f"result: exit 1 {exc}")
        return 1
    except PipelineError as exc:
        print(f"ERROR (exit 2): {exc}", file=sys.stderr)
        _write_failure_log(args, log, started, f"result: exit 2 {exc}")
        return 2
    except Exception as exc:  # noqa: BLE001 - last resort: still exit 2, never mistaken for a rejection
        print(f"INTERNAL ERROR (exit 2): {type(exc).__name__}: {exc}", file=sys.stderr)
        _write_failure_log(args, log, started, f"result: exit 2 internal error {type(exc).__name__}: {exc}")
        return 2


def _write_failure_log(args, log: Log, started: bool, last: str) -> None:
    """After the build started, leave build.log (only) behind so the reason can be posted."""
    if not started:
        return
    log.lines.append(last)
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "build.log"), "w", encoding="utf-8") as f:
        f.write(log.text())


if __name__ == "__main__":
    sys.exit(main())
