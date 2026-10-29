#!/usr/bin/env python3
"""The build-result handoff between the pipeline workflow's jobs (task 008b-2; consumed by 008b-3b).

The layout is documented in docs/pipeline/build-pipeline.md ("The pipeline workflow"). This module writes
`outcome.json`, computes the plan job's outputs, and is the ONE reader of the handoff files:
`read_outcomes(dir)`; no other code parses them.

    outcome.json  {"version_id": str, "tag": str, "exit_code": 0|1|2, "reason": str}
        exit_code 0 built, 1 rejected by 008a, 2 pipeline fault; `reason` is non-empty only for exit 1.

Subcommands (the workflow calls these; every value reaches them as an argument built from `env:`):
    plan-outputs, synth-entry, check-checkout, finish-build, guard, finish-sign, summarize.
No network, no secret, no key is read here.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import naming  # noqa: E402
import plan_pending  # noqa: E402
import write_back as wb  # noqa: E402

OUTCOME_FIELDS = ("version_id", "tag", "exit_code", "reason")
_WS = re.compile(r"\s+")


class HandoffError(Exception):
    """A handoff input is malformed (the caller exits 1 or 2; never a verdict on a version)."""


# ------------------------------------------------------------------ outcome.json

def normalize_reason(text: str) -> str:
    return _WS.sub(" ", text).strip()


def _read_text(path: str) -> str | None:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except FileNotFoundError:
        return None


def rejection_reason(out_dir: str) -> str:
    """008a's `REJECTED [rule]: message -- remedy: remedy` line without the prefix, whitespace collapsed.
    Read first from build.stderr, else from the last `result: exit 1 ` line of build.log. '' if neither has it."""
    err = _read_text(os.path.join(out_dir, "build.stderr"))
    text = ""
    if err is not None:
        m = re.search(r"^REJECTED \[", err, re.M)
        if m:
            text = err[m.start():].split("\n", 1)[0]     # the one line, never what follows it
    if not normalize_reason(text):
        log = _read_text(os.path.join(out_dir, "build.log"))
        if log is not None:
            i = log.rfind("result: exit 1 ")
            if i >= 0:
                text = log[i + len("result: exit 1 "):].split("\n", 1)[0]
    text = normalize_reason(text)
    if text.startswith("REJECTED "):
        text = text[len("REJECTED "):]
    return text


def write_outcome(out_dir: str, version_id: str, tag: str, exit_code: int) -> dict:
    """Write out_dir/outcome.json for a finished build leg and return it. Anything that is not a clean
    exit 0 / 1 is a pipeline fault (2); an exit 0 without its tarball and result.json, or an exit 1 with an
    empty reason, is a fault too."""
    if isinstance(exit_code, bool) or exit_code not in (0, 1):
        exit_code = 2
    reason = ""
    if exit_code == 0:
        if not all(os.path.isfile(os.path.join(out_dir, n)) for n in (f"{tag}.tar.gz", "result.json")):
            exit_code = 2
    elif exit_code == 1:
        reason = rejection_reason(out_dir)
        if not reason:
            exit_code = 2
    outcome = {"version_id": version_id, "tag": tag, "exit_code": exit_code, "reason": reason}
    _write_json(os.path.join(out_dir, "outcome.json"), outcome)
    return outcome


def _write_json(path: str, obj) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, sort_keys=True)
        f.write("\n")


def _read_outcome_file(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as f:
            o = json.load(f)
    except (OSError, ValueError) as exc:
        raise ValueError(f"{path}: cannot read outcome.json: {exc}")
    if not (isinstance(o, dict) and set(o) == set(OUTCOME_FIELDS) and isinstance(o["version_id"], str)
            and isinstance(o["tag"], str) and isinstance(o["reason"], str)
            and o["exit_code"] in (0, 1, 2) and not isinstance(o["exit_code"], bool)):
        raise ValueError(f"{path}: outcome.json must hold exactly version_id, tag (str), exit_code (0|1|2), reason (str)")
    return o


def read_outcomes(root: str, require_signed: bool = False) -> list:
    """The one reader. `root` holds one directory per downloaded artifact: `build-<tag>` and `signed-<tag>`.
    Returns one outcome per tag (sorted by tag), the four fields only. `signed-<tag>` overrides `build-<tag>`
    (a failed sign step rewrites the outcome to exit 2). With require_signed=True, a build leg that ended
    exit 0 and has no `signed-<tag>` is reported as exit 2 (it was never signed): the non-dry-run reading.
    Raises ValueError for a malformed file or a directory whose name disagrees with its tag."""
    found: dict = {}
    for name in sorted(os.listdir(root)):
        for prefix in ("build-", "signed-"):
            full = os.path.join(root, name)
            if name.startswith(prefix) and os.path.isdir(full):
                tag = name[len(prefix):]
                o = _read_outcome_file(os.path.join(full, "outcome.json"))
                if o["tag"] != tag:
                    raise ValueError(f"{name}: outcome.json names tag {o['tag']!r}")
                slot = found.setdefault(tag, {})
                slot[prefix[:-1]] = o
    out = []
    for tag in sorted(found):
        slot = found[tag]
        o = slot.get("signed") or slot.get("build")
        if o is None:  # pragma: no cover - unreachable by construction
            continue
        if require_signed and "signed" not in slot and o["exit_code"] == 0:
            o = dict(o, exit_code=2, reason="")
        out.append(dict(o))
    return out


def exit_classes(outcomes: list) -> list:
    """Outcomes in the shape plan_pending.summarize_outcomes takes: one `{version_id, exit_class}` per version."""
    return [{"version_id": o["version_id"], "exit_class": o["exit_code"]} for o in outcomes]


# ------------------------------------------------------------------ plan job outputs

def plan_flags(plan: dict, synthetic: int = 0) -> dict:
    """has_build: the plan's build list is non-empty (or a dry run's synthetic leg exists); has_writeback:
    build or refuse is non-empty. Strings, ready for $GITHUB_OUTPUT."""
    has_build = bool(plan["build"]) or synthetic > 0
    has_writeback = has_build or bool(plan["refuse"])
    return {"has_build": "true" if has_build else "false", "has_writeback": "true" if has_writeback else "false"}


def _leg(version_id: str, entry_path: str, synthetic: bool) -> dict:
    ns, nm, semver = plan_pending.parse_version_id(version_id)
    return {"version_id": version_id, "tag": naming.release_tag(ns, nm, semver), "semver": semver,
            "entry_path": entry_path, "synthetic": synthetic}


def synthetic_entry(mod_id: str, version: str, commit: str, url: str) -> dict:
    """The dry run's in-run entry (never written to main). The id and version must be the ones mod.lua carries
    (008a cross-checks them); the pair's URL and commit were validated by the planner."""
    if not wb._fullmatch(wb._PAT_ID, mod_id):
        raise HandoffError(f"dry_run_id {mod_id!r} does not match entry.schema.json's id pattern")
    if not wb._fullmatch(wb._PAT_SEMVER, version):
        raise HandoffError(f"dry_run_version {version!r} is not a semver string")
    return {"id": mod_id, "versions": [{"version": version, "commit": commit, "source_url": url, "status": "pending"}]}


def plan_matrix(plan: dict, dry_id: str = "", dry_version: str = "", pair: bool = False) -> dict:
    """The build matrix: one leg per `build` entry (refuse, skip and fault get none; PT5), plus the dry run's
    synthetic leg when the source pair was given."""
    if pair != bool(dry_id and dry_version) or (not pair and (dry_id or dry_version)):
        raise HandoffError("dry_run_id and dry_run_version are required with the source pair, and accepted only with it")
    include = [_leg(e["version_id"], e["entry_path"], False) for e in plan["build"]]
    if pair:
        synthetic_entry(dry_id, dry_version, "0" * 40, "https://example.invalid/")  # validates id and version
        ns, nm = naming.split_id(dry_id)
        include.append(_leg(f"{ns}.{nm}@{dry_version}", "", True))
    return {"include": include}


# ------------------------------------------------------------------ checkout check

def check_checkout(repo: str) -> int:
    """Fail closed on a broken or sparse checkout (008b-1 review F2): every mods/<dir>/entry.json that git
    tracks at HEAD must exist as a file, and mods/ must exist whenever git tracks anything under it.
    Returns the number of tracked entries."""
    res = subprocess.run(["git", "-C", repo, "ls-tree", "-r", "--name-only", "HEAD", "--", "mods"],
                         capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if res.returncode != 0:
        raise HandoffError(f"git ls-tree failed in {repo!r}: {res.stderr.strip()[:300]}")
    tracked = [p for p in res.stdout.splitlines() if p]
    if tracked and not os.path.isdir(os.path.join(repo, "mods")):
        raise HandoffError(f"git tracks {len(tracked)} file(s) under mods/ but the checkout has no mods/ directory")
    missing = [p for p in tracked if not os.path.isfile(os.path.join(repo, p))]
    if missing:
        raise HandoffError(f"{len(missing)} tracked file(s) under mods/ are missing from the checkout, e.g. {missing[0]}")
    return sum(1 for p in tracked if re.fullmatch(r"mods/[^/]+/entry\.json", p))


# ------------------------------------------------------------------ build and sign legs

def finish_build(out_dir: str, stderr_file: str, version_id: str, tag: str, exit_code: int) -> dict:
    """After build_version.py ran with its stderr redirected to `stderr_file` (outside --out, which that tool
    needs empty): put build.stderr next to the rest and write outcome.json."""
    os.makedirs(out_dir, exist_ok=True)
    try:
        shutil.copyfile(stderr_file, os.path.join(out_dir, "build.stderr"))
    except OSError as exc:
        raise HandoffError(f"cannot copy the captured stderr {stderr_file!r}: {exc}")
    return write_outcome(out_dir, version_id, tag, exit_code)


def finish_sign(build_dir: str, signed_dir: str, rc: int) -> dict:
    """After sign_built.py ran with --out signed_dir. rc 0 and the exact file set -> outcome.json copied
    unchanged. Any other rc (1 refused, 2 error, anything else), or an incomplete output, is a pipeline fault:
    signed_dir is reset to outcome.json alone with exit_code 2 and no signature."""
    prior = _read_outcome_file(os.path.join(build_dir, "outcome.json"))
    tag = prior["tag"]
    want = {f"{tag}.tar.gz", f"{tag}.tar.gz.minisig", "result.json"}
    have = set(os.listdir(signed_dir)) if os.path.isdir(signed_dir) else set()
    if rc == 0 and have == want and prior["exit_code"] == 0:
        shutil.copyfile(os.path.join(build_dir, "outcome.json"), os.path.join(signed_dir, "outcome.json"))
        return prior
    if os.path.isdir(signed_dir):
        shutil.rmtree(signed_dir)
    os.makedirs(signed_dir)
    fault = {"version_id": prior["version_id"], "tag": tag, "exit_code": 2, "reason": ""}
    _write_json(os.path.join(signed_dir, "outcome.json"), fault)
    return fault


# ------------------------------------------------------------------ CLI

def _gh(pairs: dict) -> None:
    for k, v in pairs.items():
        sys.stdout.write(f"{k}={v}\n")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="handoff.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("plan-outputs"); s.add_argument("--plan", required=True)
    s.add_argument("--dry-run-id", default=""); s.add_argument("--dry-run-version", default="")
    s.add_argument("--pair", default="false", choices=("true", "false"))
    s = sub.add_parser("synth-entry")
    for a in ("--id", "--version", "--commit", "--url", "--out"):
        s.add_argument(a, required=True)
    s = sub.add_parser("check-checkout"); s.add_argument("--repo", required=True)
    s = sub.add_parser("finish-build")
    for a in ("--out", "--stderr", "--version-id", "--tag"):
        s.add_argument(a, required=True)
    s.add_argument("--exit-code", type=int, required=True)
    s = sub.add_parser("guard"); s.add_argument("--dir", required=True)
    s = sub.add_parser("finish-sign")
    s.add_argument("--build-dir", required=True); s.add_argument("--signed-dir", required=True)
    s.add_argument("--rc", type=int, required=True)
    s = sub.add_parser("summarize")
    s.add_argument("--plan", required=True); s.add_argument("--outcomes", required=True)
    s.add_argument("--dry-run", default="false", choices=("true", "false"))
    a = p.parse_args(argv)
    try:
        if a.cmd == "plan-outputs":
            with open(a.plan, "r", encoding="utf-8") as f:
                plan = json.load(f)
            m = plan_matrix(plan, a.dry_run_id, a.dry_run_version, a.pair == "true")
            flags = plan_flags(plan, sum(1 for leg in m["include"] if leg["synthetic"]))
            _gh({"head_sha": plan["head_sha"], **flags, "matrix": json.dumps(m, separators=(",", ":"))})
        elif a.cmd == "synth-entry":
            _write_json(a.out, synthetic_entry(a.id, a.version, a.commit, a.url))
        elif a.cmd == "check-checkout":
            n = check_checkout(a.repo)
            print(f"handoff: checkout holds {n} tracked mods/*/entry.json, all present on disk")
        elif a.cmd == "finish-build":
            o = finish_build(a.out, a.stderr, a.version_id, a.tag, a.exit_code)
            print(f"handoff: {o['version_id']} exit_code {o['exit_code']}" + (f" reason: {o['reason']}" if o["reason"] else ""))
        elif a.cmd == "guard":
            o = _read_outcome_file(os.path.join(a.dir, "outcome.json"))
            _gh({"proceed": "true" if o["exit_code"] == 0 else "false", "exit_code": o["exit_code"]})
        elif a.cmd == "finish-sign":
            o = finish_sign(a.build_dir, a.signed_dir, a.rc)
            print(f"handoff: {o['version_id']} signing outcome exit_code {o['exit_code']}")
            return 0 if o["exit_code"] == 0 else 1
        elif a.cmd == "summarize":
            with open(a.plan, "r", encoding="utf-8") as f:
                plan = json.load(f)
            dry = a.dry_run == "true"
            outcomes = read_outcomes(a.outcomes, require_signed=not dry)   # a dry run signs in its own job
            if dry:  # the pair's synthetic version is in no plan list: adopt it as a built version
                known = {e["version_id"] for e in plan["build"]}
                plan = dict(plan, build=plan["build"] + [{"version_id": o["version_id"]} for o in outcomes if o["version_id"] not in known])
            green, message = plan_pending.summarize_outcomes(plan, exit_classes(outcomes))
            if not green:
                print("pipeline run is NOT green:\n" + message)
                return 1
            print("pipeline run is green: " + ", ".join(f"{o['version_id']}={o['exit_code']}" for o in outcomes))
    except (HandoffError, plan_pending.PlanInputError, ValueError, OSError, KeyError) as exc:
        print(f"handoff: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
