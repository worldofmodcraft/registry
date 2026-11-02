#!/usr/bin/env python3
"""Pipeline planner (task 008b-1, node N5; edge E15 in, plan document out to 008b-2 / 008b-3b).

Reads the registry state at `main`'s head (a directory the caller checked out; the SHA is passed in and
logged), the names of the existing `pipeline/*` branches, the existing paths under `logs/` in
`worldofmodcraft/archive`, and the dispatch inputs; prints ONE plan document that sorts every `pending`
version into exactly one of four lists: build, refuse, skip, fault (docs/pipeline/build-pipeline.md,
"The planner (task 008b-1)"). Published, removed and rejected versions appear nowhere.

Exit codes (pinned by the task): 0 and the document whenever the inputs are well-formed, even if the plan
holds skip/refuse/fault entries; 1 for malformed or conflicting inputs, and then NO document is written.
A skip or fault is never reported by a non-zero exit; `summarize_outcomes` is how the run ends non-green.

No network, no subprocess, no clock, no secret: everything is injected. Schema patterns are matched through
write_back's helpers (`_ecma_digits`, `_fullmatch`): full-match, ASCII-only `\\d`. (Task 094 will later move the
pipeline to tools/registry/schema.py's `ecma_pattern`; the residual `\\s` differences are booked in task 008c.)
"""

from __future__ import annotations

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import naming  # noqa: E402
import write_back as wb  # noqa: E402
from pipeline_errors import PipelineError  # noqa: E402

# Exact text of contracts/artifact-naming.md, "The archived-source URL", producer obligation 3 (092 Q10).
PLUS_REFUSAL_REASON = ("versions with build metadata (+) are not yet published — "
                       "pending proof that GitHub resolves them (task 010)")

LISTS = ("build", "refuse", "skip", "fault")
ENTRY_FIELDS = ("version_id", "entry_path", "kind", "reason")


class PlanInputError(PipelineError):
    """Malformed or conflicting inputs, or unreadable state: the planner exits 1 and writes no document."""


# ------------------------------------------------------------------ schema validation (entry.schema.json)

_IGNORED_KEYWORDS = {"$schema", "$id", "title", "description"}
_KNOWN_KEYWORDS = _IGNORED_KEYWORDS | {"type", "required", "properties", "additionalProperties", "items",
                                       "minItems", "minLength", "minimum", "pattern", "enum", "oneOf"}


class SchemaFault(Exception):
    pass


_PATTERN_CACHE: dict = {}


def _pattern(p: str) -> str:
    if p not in _PATTERN_CACHE:
        _PATTERN_CACHE[p] = wb._ecma_digits(p)
    return _PATTERN_CACHE[p]


def _type_ok(inst, t: str) -> bool:
    if t == "object":
        return isinstance(inst, dict)
    if t == "array":
        return isinstance(inst, list)
    if t == "string":
        return isinstance(inst, str)
    if t == "integer":
        return isinstance(inst, int) and not isinstance(inst, bool)
    raise NotImplementedError(f"schema type {t!r}")


def _validate(inst, sch: dict, path: str) -> None:
    """The subset of JSON Schema that contracts/entry.schema.json uses. An unknown keyword raises
    NotImplementedError (a visible error, never a silent pass)."""
    for k in sch:
        if k not in _KNOWN_KEYWORDS:
            raise NotImplementedError(f"schema keyword {k!r} at {path}")
    if "type" in sch and not _type_ok(inst, sch["type"]):
        raise SchemaFault(f"{path}: expected {sch['type']}")
    if "enum" in sch and inst not in sch["enum"]:
        raise SchemaFault(f"{path}: not one of {sch['enum']}")
    if isinstance(inst, str):
        if "minLength" in sch and len(inst) < sch["minLength"]:
            raise SchemaFault(f"{path}: shorter than {sch['minLength']}")
        if "pattern" in sch and not wb._fullmatch(_pattern(sch["pattern"]), inst):
            raise SchemaFault(f"{path}: does not match pattern {sch['pattern']}")
    if isinstance(inst, int) and not isinstance(inst, bool) and "minimum" in sch and inst < sch["minimum"]:
        raise SchemaFault(f"{path}: below {sch['minimum']}")
    if isinstance(inst, list):
        if "minItems" in sch and len(inst) < sch["minItems"]:
            raise SchemaFault(f"{path}: fewer than {sch['minItems']} items")
        if "items" in sch:
            for i, item in enumerate(inst):
                _validate(item, sch["items"], f"{path}[{i}]")
    if isinstance(inst, dict):
        for r in sch.get("required", []):
            if r not in inst:
                raise SchemaFault(f"{path}: missing required key {r!r}")
        props = sch.get("properties", {})
        if sch.get("additionalProperties") is False:
            for k in inst:
                if k not in props:
                    raise SchemaFault(f"{path}: unexpected key {k!r}")
        for k, sub in props.items():
            if k in inst:
                _validate(inst[k], sub, f"{path}.{k}")
    if "oneOf" in sch:
        errors, matches = [], 0
        for branch in sch["oneOf"]:
            try:
                _validate(inst, branch, path)
                matches += 1
            except SchemaFault as exc:
                errors.append(str(exc))
        if matches != 1:
            # Report the branch the object's own status points at, if any; that is the useful message.
            status = inst.get("status") if isinstance(inst, dict) else None
            names = [b["properties"]["status"]["enum"][0] for b in sch["oneOf"]]
            detail = errors[names.index(status)] if status in names and matches == 0 else "; ".join(errors)
            raise SchemaFault(f"{path}: matches {matches} of the {len(names)} version states ({detail})")


def _no_dup_keys(pairs):
    d = {}
    for k, v in pairs:
        if k in d:
            raise SchemaFault(f"duplicate JSON key {k!r}")
        d[k] = v
    return d


def _reject_constant(name):
    raise SchemaFault(f"non-standard JSON constant {name}")


# ------------------------------------------------------------------ input validation

_HEX = frozenset("0123456789abcdef")


def parse_version_id(value: str) -> tuple[str, str, str]:
    """`<namespace>.<name>@<semver>` -> (namespace, name, semver). Patterns are entry.schema.json's."""
    if not isinstance(value, str):
        raise PlanInputError(f"version input is not a string: {value!r}")
    head, at, semver = value.partition("@")
    ns, dot, name = head.partition(".")
    if not at or not dot:
        raise PlanInputError(f"version input {value!r} is not <namespace>.<name>@<semver>")
    if not wb._fullmatch(wb._PAT_ID, f"{ns}:{name}"):
        raise PlanInputError(f"version input {value!r}: {ns!r}.{name!r} is not a valid entry id")
    if not wb._fullmatch(wb._PAT_SEMVER, semver):
        raise PlanInputError(f"version input {value!r}: {semver!r} is not a semver string")
    return ns, name, semver


def _check_url(value: str) -> None:
    printable = all(0x21 <= ord(c) < 0x7F for c in value)
    if not (printable and value.startswith("https://") and len(value) > len("https://")
            and value[len("https://")] != "/"):
        raise PlanInputError(f"dry_run_source_url {value!r} is not an https:// URL of printable ASCII")


def _check_commit(value: str) -> None:
    if not (len(value) == 40 and set(value) <= _HEX):
        raise PlanInputError(f"dry_run_commit {value!r} is not 40 lowercase hex characters")


def validate_dispatch(dry_run: str, version: str, source_url: str, commit: str) -> dict:
    """The dispatch input set (082 PT5, PT12; Q-M option A). Empty strings mean 'not given' (a push has no
    inputs). Returns {"dry_run": bool, "version": (ns, name, semver) | None, "pair": bool}."""
    if dry_run not in ("", "true", "false"):
        raise PlanInputError(f"dry_run must be 'true' or 'false', got {dry_run!r}")
    dry = dry_run == "true"
    given = bool(source_url) + bool(commit)
    if given == 1:
        raise PlanInputError("dry_run_source_url and dry_run_commit are accepted only together")
    pair = given == 2
    if pair and not dry:
        raise PlanInputError("dry_run_source_url/dry_run_commit are accepted only with dry_run=true")
    if pair and version:
        raise PlanInputError("dry_run_source_url/dry_run_commit are accepted only with version empty")
    if dry and not pair and not version:
        raise PlanInputError("dry_run=true needs a version, or the pair dry_run_source_url + dry_run_commit")
    if pair:
        _check_url(source_url)
        _check_commit(commit)
    return {"dry_run": dry, "version": parse_version_id(version) if version else None, "pair": pair}


def _check_head_sha(sha: str) -> None:
    if not (isinstance(sha, str) and len(sha) == 40 and set(sha) <= _HEX):
        raise PlanInputError(f"head sha {sha!r} is not 40 lowercase hex characters")


def _check_names(kind: str, names) -> frozenset:
    out = set()
    for n in names:
        if not isinstance(n, str) or n != n.strip() or any(c.isspace() or ord(c) < 0x20 for c in n):
            raise PlanInputError(f"{kind}: malformed line {n!r}")
        if n:
            out.add(n)
    return frozenset(out)


def read_lines(path: str, kind: str) -> list:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return [ln.strip() for ln in f.read().splitlines()]
    except (OSError, UnicodeDecodeError) as exc:
        raise PlanInputError(f"{kind}: cannot read {path!r}: {exc}") from exc


# ------------------------------------------------------------------ reading the registry state

def _entry_path(dirname: str) -> str:
    return f"mods/{dirname}/entry.json"


def _fault(entry_path: str, reason: str, version_id=None) -> dict:
    return {"version_id": version_id, "entry_path": entry_path, "kind": "fault", "reason": reason}


def _load_entry(registry: str, dirname: str, schema: dict):
    """Returns (entry, None) or (None, fault-reason). Only a file that cannot be read at all is an input error."""
    full = os.path.join(registry, "mods", dirname, "entry.json")
    if not os.path.isfile(full):
        return None, f"{_entry_path(dirname)} is missing"
    try:
        with open(full, "rb") as f:
            raw = f.read()
    except OSError as exc:
        raise PlanInputError(f"cannot read {full!r}: {exc}") from exc
    try:
        entry = json.loads(raw.decode("utf-8"), object_pairs_hook=_no_dup_keys, parse_constant=_reject_constant)
        _validate(entry, schema, "$")
    except (SchemaFault, ValueError) as exc:  # json.JSONDecodeError and UnicodeDecodeError are ValueErrors
        return None, f"{_entry_path(dirname)} fails entry.schema.json: {exc}"
    except RecursionError:  # a hostile, deeply nested file: a fault of this entry only (C15, PT5), never a crash
        return None, f"{_entry_path(dirname)} fails entry.schema.json: nested too deeply to parse"
    ns, name = naming.split_id(entry["id"])
    if dirname != f"{ns}.{name}":
        return None, f"{_entry_path(dirname)} fails entry.schema.json: id {entry['id']!r} does not belong in directory {dirname!r}"
    seen = set()
    for v in entry["versions"]:
        if v["version"] in seen:
            return None, f"{_entry_path(dirname)} fails entry.schema.json: version {v['version']!r} appears twice"
        seen.add(v["version"])
    return entry, None


def _classify(entry: dict, dirname: str, only_semver, branches: frozenset, logs: frozenset) -> list:
    ns, name = naming.split_id(entry["id"])
    out = []
    for v in entry["versions"]:
        if v["status"] != "pending":
            continue
        semver = v["version"]
        if only_semver is not None and semver != only_semver:
            continue
        base = {"version_id": f"{ns}.{name}@{semver}", "entry_path": _entry_path(dirname)}
        branch = f"pipeline/{naming.release_tag(ns, name, semver)}"
        if branch in branches:
            out.append({**base, "kind": "skip", "reason": branch})
        elif "+" in semver:
            out.append({**base, "kind": "refuse", "reason": PLUS_REFUSAL_REASON,
                        "log_exists": f"logs/{ns}.{name}/{semver}.log" in logs})
        else:
            out.append({**base, "kind": "build", "reason": ""})
    return out


def plan(registry: str, head_sha: str, branches, archive_logs, dry_run: str = "", version: str = "",
         dry_run_source_url: str = "", dry_run_commit: str = "") -> dict:
    """The plan document. Raises PlanInputError for anything that must exit 1."""
    _check_head_sha(head_sha)
    d = validate_dispatch(dry_run, version, dry_run_source_url, dry_run_commit)
    branches = _check_names("branches", branches)
    logs = _check_names("archive logs", archive_logs)
    doc = {"head_sha": head_sha, **{k: [] for k in LISTS}}
    if d["pair"]:
        return doc  # the synthetic in-run entry is 008b-2's; nothing on main is planned
    if not os.path.isdir(registry):
        raise PlanInputError(f"registry state {registry!r} is not a directory")
    try:
        schema = wb._SCHEMA
        mods = os.path.join(registry, "mods")
        dirs = sorted(e for e in os.listdir(mods) if os.path.isdir(os.path.join(mods, e))) if os.path.isdir(mods) else []
    except OSError as exc:
        raise PlanInputError(f"cannot list {registry!r}/mods: {exc}") from exc
    only = d["version"]
    if only is not None:
        dirname = f"{only[0]}.{only[1]}"
        if dirname not in dirs:
            raise PlanInputError(f"version input names {only[0]}.{only[1]}@{only[2]}, but {_entry_path(dirname)} does not exist")
        dirs = [dirname]
    for dirname in dirs:
        entry, reason = _load_entry(registry, dirname, schema)
        if entry is None:
            doc["fault"].append(_fault(_entry_path(dirname), reason,
                                       f"{only[0]}.{only[1]}@{only[2]}" if only else None))
            continue
        found = _classify(entry, dirname, only[2] if only else None, branches, logs)
        if only is not None and not found:
            raise PlanInputError(f"version input {only[0]}.{only[1]}@{only[2]} is not a pending version of {entry['id']}")
        for item in found:
            doc[item["kind"]].append(item)
    return doc


# ------------------------------------------------------------------ run conclusion (PT5; criterion 17(c))

def summarize_outcomes(plan_doc: dict, outcomes) -> tuple:
    """(green, message). `outcomes` is a list of {"version_id": str, "exit_class": 0|1|2}, one per built version.

    The run is non-green if the plan has any `skip` or `fault` entry, any outcome of exit class 2 (a pipeline
    fault), or a `build` entry with no reported outcome (fail closed). Exit class 1 is a 008a verdict on the
    version, handled by its T3 (008b-3b), so it does not by itself make the run non-green. `refuse` entries
    alone leave the run green. The message names every such version; it is empty when green."""
    by_id = {}
    for o in outcomes:
        if not (isinstance(o, dict) and isinstance(o.get("version_id"), str) and o.get("exit_class") in (0, 1, 2)
                and not isinstance(o.get("exit_class"), bool)):
            raise ValueError(f"malformed outcome {o!r}: need version_id (str) and exit_class 0, 1 or 2")
        if o["version_id"] in by_id:
            raise ValueError(f"two outcomes for {o['version_id']}")
        by_id[o["version_id"]] = o["exit_class"]
    built = {e["version_id"] for e in plan_doc["build"]}
    stray = sorted(set(by_id) - built)
    if stray:
        raise ValueError(f"outcomes for versions that are not in the build list: {stray}")
    problems = []
    for e in plan_doc["skip"]:
        problems.append(f"skipped {e['version_id']}: branch {e['reason']} exists (close its PR, delete the branch, dispatch)")
    for e in plan_doc["fault"]:
        problems.append(f"fault in {e['entry_path']}" + (f" ({e['version_id']})" if e["version_id"] else "") + f": {e['reason']}")
    for e in plan_doc["build"]:
        vid = e["version_id"]
        if vid not in by_id:
            problems.append(f"no outcome reported for {vid}")
        elif by_id[vid] == 2:
            problems.append(f"pipeline fault (exit 2) in {vid}")
    return (not problems), "\n".join(problems)


# ------------------------------------------------------------------ CLI

class _Parser(argparse.ArgumentParser):
    def error(self, message):  # argparse exits 2; this tool's contract is 1 for malformed input
        raise PlanInputError(f"usage: {message}")


def main(argv=None) -> int:
    p = _Parser(prog="plan_pending.py", add_help=True)
    p.add_argument("--registry", required=True, help="directory holding mods/*/entry.json at main's head")
    p.add_argument("--head-sha", required=True, help="the SHA of main's head that --registry was checked out at")
    p.add_argument("--branches", required=True, help="file: existing branch names, one per line")
    p.add_argument("--archive-logs", required=True, help="file: existing paths under logs/ in the archive repo")
    p.add_argument("--dry-run", default="")
    p.add_argument("--version", default="")
    p.add_argument("--dry-run-source-url", default="")
    p.add_argument("--dry-run-commit", default="")
    p.add_argument("--out", default="", help="also write the document to this file (only on success)")
    try:
        a = p.parse_args(argv)
        doc = plan(a.registry, a.head_sha, read_lines(a.branches, "branches"), read_lines(a.archive_logs, "archive logs"),
                   a.dry_run, a.version, a.dry_run_source_url, a.dry_run_commit)
        text = json.dumps(doc, indent=2, ensure_ascii=True) + "\n"
        if a.out:
            try:
                with open(a.out, "w", encoding="utf-8") as f:
                    f.write(text)
            except OSError as exc:
                raise PlanInputError(f"cannot write {a.out!r}: {exc}") from exc
    except (PlanInputError, NotImplementedError) as exc:
        print(f"plan_pending: {exc}", file=sys.stderr)
        return 1
    print(f"plan_pending: head_sha={doc['head_sha']} " + " ".join(f"{k}={len(doc[k])}" for k in LISTS), file=sys.stderr)
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
