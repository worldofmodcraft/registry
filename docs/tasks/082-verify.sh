#!/usr/bin/env bash
#
# 082-verify.sh -- the runnable verification artefact for task 082 (MANAGER.md Section 2c).
#
# Task 082: the E15 contract contracts/pipeline-trigger.md. Demonstrates acceptance criteria 1-12 of
# docs/tasks/082-pipeline-trigger-contract.md; criterion 13 only with --full (see below).
#
# Usage:  docs/tasks/082-verify.sh [--full] [--platform PLATFORM_CHECKOUT_DIR]      (any cwd inside the repository)
#   (no flag)    AC1-AC11: contract text checks on the file AT the pinned FINAL commit, README index checks, own-change
#                scope on BASE..FINAL, and the mutation proofs (each mutation is applied to a COPY of the FINAL blob,
#                shown red, then the copy is restored from the blob and shown byte-identical and green).
#   --platform D AC12 (ADVISORY, never counted): prints 008b design 1 and 3 from D/docs/tasks/008b-pipeline-workflow.md
#                next to the normative block.
#   --full       AC13: clones the committed HEAD into a temporary directory and runs every OTHER docs/tasks/*-verify.sh
#                there, one at a time, with no argument. Without --full, AC13 is reported as NOT RUN, never as green.
# Own-change checks use the EXPLICIT SHAs below (BASE, FINAL, TIP), never HEAD or origin/main, so later tasks cannot redden them.
# The caller's worktree is never modified. Network: none (the --full clone is of the local repository).
# Exit code: the number of failed checks. Requires: git, python3 (standard library only).
# Before --full, check that no other verify script is running:
#   ps -eo args | grep -E 'docs/tasks/.*-verify\.sh' | grep -v grep

set -u
set -o pipefail

BASE="4356583fb2360592a680f40bee396f9f23df35a4"    # registry origin/main at the cut (merge of PR #18, task 075)
FINAL="afa48f20756c2fca793a0732cf7834e924663c3b"   # the commit carrying the contract and the README row
TIP="002a59ac15917c7a92e9a2d03e8d9ce8e457a62c"      # the last content commit of the branch (own-change checks never use HEAD)

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
FULL=0
PLATFORM=""
while [ $# -gt 0 ]; do
    case "$1" in
        --full) FULL=1 ;;
        --platform) shift; PLATFORM="${1:-}" ;;
        *) echo "unknown argument: $1" >&2; exit 99 ;;
    esac
    shift
done

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT

cat > "$TMP/check.py" <<'PY'
import difflib
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT, BASE, FINAL, TMP, TIP = sys.argv[1:6]
CONTRACT = "contracts/pipeline-trigger.md"
README = "docs/contracts/README.md"
FAILURES = 0


def out(kind, cid, msg):
    global FAILURES
    print("%-5s %s %s" % (kind, cid, msg))
    if kind == "FAIL":
        FAILURES += 1


def git(*args, check=True, repo=None):
    r = subprocess.run(["git", "-C", repo or ROOT] + list(args), capture_output=True)
    if check and r.returncode != 0:
        raise RuntimeError("git %s: %s" % (" ".join(args), r.stderr.decode(errors="replace")))
    return r


def blob(sha, path):
    r = git("show", "%s:%s" % (sha, path), check=False)
    return r.stdout if r.returncode == 0 else None


def norm(s):
    return re.sub(r"\s+", " ", s.replace("**", "")).strip()


# ---------------------------------------------------------------------------------------------------
# The pins: every sentence of PT1-PT12 (rule heading, each sentence, the Source line) by FULL text.
# A paragraph must equal the pinned sentences joined by single spaces, so a sentence added anywhere
# (a tail append included) is red as well as a sentence edited or deleted.
PINS = json.loads(r'''{
 "PT1": [
  "PT1 Trigger set (closed).",
  "The workflow's triggers are exactly two: `push` to `main`, filtered as PT2 states, and `workflow_dispatch`.",
  "It never uses `pull_request`, `pull_request_target`, `workflow_run`, `repository_dispatch`, `schedule` or any other event.",
  "Adding a trigger amends this contract.",
  "The reason is that no secret may be reachable from a run triggered from a fork: GitHub withholds repository secrets from runs triggered by a fork pull request `[unverified]`, and 008b criterion 8 tests this live.",
  "A `workflow_dispatch` can be started only by an account with write access to the registry `[unverified]`, and PT3 states which of its runs may reach a key.",
  "Source: C17 (closed trigger list); 008b design 1; task 039 section 1."
 ],
 "PT2": [
  "PT2 Path filter.",
  "The `push` trigger carries `paths: ['mods/*/entry.json']`.",
  "A push that changes only a `page.json`, or nothing under `mods/`, starts no run.",
  "The filter only saves cost, and correctness never depends on it, because PT4 reads state and not the diff.",
  "In a GitHub path filter `*` does not match `/` `[unverified]`, so the filter is meant to match `mods/<namespace>.<name>/entry.json` and no deeper path.",
  "GitHub may run a path-filtered workflow anyway when it cannot compute the diff `[unverified]`, and such a run is correct because of PT4 and PT5.",
  "Source: task 039 section 3; 008b design 1."
 ],
 "PT3": [
  "PT3 Ref and key binding.",
  "The signing and write-back jobs act only when `github.ref == 'refs/heads/main'`, for both triggers.",
  "The ref condition protects only the unmodified workflow file: a `workflow_dispatch` runs the workflow file of the ref selected at dispatch `[unverified]`, so a modified file on another branch runs without the condition.",
  "The signing key is bound to `main` only by a GitHub Actions environment named `signing` on the signing job, with deployment branches limited to `main` and `MINISIGN_SECRET_KEY` stored as that environment's secret, and the App key is bound only by an environment named `write-back` configured the same way for `PIPELINE_APP_PRIVATE_KEY`.",
  "Ludwig's manual step M11 creates both environments and deletes the repo-level copies of both secrets, because an environment copy protects nothing while a repo-level copy exists, and the environment mechanics are `[unverified]`.",
  "Until M11 is done, the trust boundary of `MINISIGN_SECRET_KEY` and `PIPELINE_APP_PRIVATE_KEY` is every account with write access to the registry.",
  "The dry-run job references neither environment.",
  "Source: C14 (which dispatches reach the key); C20 as extended in spec review round 2, N1 (both keys, repo-level copies deleted); 008b design 8 (follow-up booked)."
 ],
 "PT4": [
  "PT4 Input snapshot.",
  "A run reads `mods/*/entry.json` at the head of `main` as fetched at plan time, and logs that SHA.",
  "The commit range of the push payload, and the push's `github.sha`, are never the authority for what to build.",
  "A run that starts after a later merge has landed therefore sees the state that merge produced.",
  "Source: C12 (input snapshot); 008b design 2."
 ],
 "PT5": [
  "PT5 What a run processes.",
  "A push run, and a `workflow_dispatch` run with an empty `version` input, build every `pending` version on `main`.",
  "Versions that are `published`, `removed` or `rejected` are never built.",
  "A fault or a refusal ends that version only: the run continues with the remaining `pending` versions and fails at the end, naming each version that failed.",
  "A version that keeps faulting with exit 2 is therefore retried by every push run and ends each of those runs red, without blocking other versions.",
  "A `workflow_dispatch` with `version=<namespace>.<name>@<semver>` builds only that version, and only if it is `pending`.",
  "Otherwise, or for a malformed id or an absent entry, it refuses with planner exit 1 and writes nothing, and that refusal is not a 008a verdict.",
  "The `version` input is validated against the entry-id and semver patterns before use, and it reaches scripts only through `env:`, never by interpolation into a `run:` block (task 039's injection rule).",
  "Zero `pending` versions is a success that writes nothing.",
  "Source: C11 (scope of a push run); 008b design 2 and 9, criteria 12 and 17; task 039 injection rule."
 ],
 "PT6": [
  "PT6 Concurrency.",
  "The workflow declares `concurrency: { group: pipeline, cancel-in-progress: false }`, and push runs and `workflow_dispatch` runs share that one group, so at most one run builds at a time.",
  "GitHub keeps at most one waiting run per concurrency group and cancels an older waiting run when a newer one arrives, and a waiting push run can be replaced by a waiting dispatch run `[unverified]`.",
  "That is why PT4 and PT5 read state and not the diff, and why a `workflow_dispatch` with an empty `version` plans all `pending` versions exactly as a push does, so a replaced waiting run loses nothing.",
  "A run holds the `pipeline` group until each PR it opened has reached a terminal state: merged, failed, closed unmerged, or deadline (PT11).",
  "The planner skips any `pending` version that already has a `pipeline/<namespace>.<name>-<version>` branch, and the skip is not silent: it makes the run's conclusion non-green, or raises an error annotation, naming the version.",
  "Source: C13 (in-flight versions); C22 (terminal states); 008b design 3 and 9."
 ],
 "PT7": [
  "PT7 Termination.",
  "A push to `main` caused by the pipeline itself happens only when a write-back PR (PT11) merges, and that PR is a T1 or a T3 transition.",
  "Each such transition moves exactly one version out of `pending`, and a `pending` version leaves that state only this way (PT9).",
  "That a merge made by the GitHub App identity fires a `push` run is `[unverified]` (008 finding F5; 008b criterion 9).",
  "The log commit to `worldofmodcraft/archive` is in another repository and does not trigger E15.",
  "N pending versions therefore cause at most N + 1 runs from pipeline-caused pushes, and the run that finds zero `pending` versions ends having written nothing (PT5).",
  "Source: 008b design 2 (zero pending stops the loop) and criterion 9; 008 finding F5; ADR-0121."
 ],
 "PT8": [
  "PT8 Re-runs and idempotency.",
  "If a published release with the tag already exists in `worldofmodcraft/archive`, the run fails for that version with `artifact-naming.md`'s never-overwrite rule (a pre-existing tag of this name is an error, never something to overwrite), writes nothing else, and leaves the version `pending`; recovery is manual.",
  "If only a draft release with the tag exists, it is deleted and recreated.",
  "A version that is no longer `pending` is never rebuilt.",
  "The log commit is append-only per version: if `logs/<namespace>.<name>/<version>.log` already exists in `worldofmodcraft/archive`, the run fails for that version naming the path, overwrites nothing, and recovery is by hand.",
  "A version skipped under PT6 is recovered by closing its PR, deleting its `pipeline/` branch and dispatching.",
  "A re-run of a workflow run uses the workflow file of the original commit `[unverified]`, and its inputs are still the state PT4 reads, not the original run's.",
  "Source: 008b design 5 and criteria 6 and 18; `contracts/artifact-naming.md` (uniqueness rule, \"What this document does not cover\"); C13."
 ],
 "PT9": [
  "PT9 What the pipeline may assume.",
  "The pipeline may assume that the entry is on `main`, and that its `pending` version's `version`, `commit` and `source_url` are frozen by the conditions of T1 and T3 in `contracts/append-only.rules.md`.",
  "It may assume that only the pipeline identity can move a version out of `pending`, through the pipeline carve-out that E16 adds to `contracts/ownership.md`; until that carve-out merges, a checker implementing T1 or T3 rejects every PR containing one (`append-only.rules.md`, \"Coexistence of T1, T2 and T3\"), so no T1 or T3 PR can merge.",
  "It may not assume anything from `gate`: a PR passing `gate` (task 039; required only after M9) shows liveness and not safety, and 008a re-validates everything.",
  "It may not assume the author's repository still exists, because a failed clone is exit 2.",
  "An entry on `main` that fails the entry schema is a pipeline fault: no build, no T3 transition, and the run fails naming the file.",
  "Source: `contracts/append-only.rules.md` (T1, T3, Coexistence); `contracts/ownership.md` (E16 carve-out); task 039 section 1; C15 (entry failing the schema); ADR-0121."
 ],
 "PT10": [
  "PT10 Outcomes per 008a exit code.",
  "The codes are those of 008a's `build_version.py`: 0 built, 1 rejected, 2 pipeline fault.",
  "Exit 0: the run opens one T1 write-back PR for that version.",
  "Exit 1: the run commits the build log to `worldofmodcraft/archive` at `logs/<namespace>.<name>/<version>.log`, the log commit precedes the T3 PR, and an existing log at that path fails that version (PT8).",
  "It then comments the full `build.log` on the merged PR that appended the version, and opens one T3 PR with a `reason` that is non-empty after trimming and a `build_log_url` that begins with `https://`.",
  "It never blocks or reverts a merge and never deletes the version.",
  "Exit 2: that version's run fails, with no comment, no T3 PR, no release and nothing written, and the version stays `pending` and is retried by the next push or by a dispatch (PT5).",
  "Source: 008b design 7; ADR-0121 decision Q-J; `contracts/append-only.rules.md` (T1, T3)."
 ],
 "PT11": [
  "PT11 Write-back PRs.",
  "Write-back is one PR per version, and its diff is exactly one T1 or one T3 transition.",
  "It goes through `gate` like any PR, with no bypass and no lifted rule.",
  "It is opened with the GitHub App identity (Q-D), never with `GITHUB_TOKEN`.",
  "PRs are opened and merged one at a time, each branched from a `main` head fetched after the previous merge.",
  "The GitHub App merges each PR once `gate` is green; task 039's \"no auto-merge\" means no auto-merge by the 039 workflow.",
  "If `gate` is red, a PR is closed unmerged, or a PR is not merged within 30 minutes, the run fails and stops, and the group is released.",
  "The remaining `pending` versions wait for the next push or for a `workflow_dispatch` with an empty `version`.",
  "The signing and write-back job's `timeout-minutes` is sized from the pending count (N x 30 minutes plus build time), or the per-PR steps carry their own timeouts.",
  "Source: C22 (write-back sequencing); 008b design 4, Forbidden and criterion 9; Q-D (App identity); task 039 Dependencies."
 ],
 "PT12": [
  "PT12 Dry run.",
  "A `workflow_dispatch` with `dry_run=true` writes only workflow artifacts: no release, no branch, no PR, no archive commit and no comment.",
  "It never uses the production key: it signs with an ephemeral key generated inside the run and discarded, and its artifacts say so.",
  "Its source is only a `pending` version on `main`, or an input set that 008b names and this contract reviews.",
  "The `version` input is validated and passed as PT5 states.",
  "Other dry-run inputs are 008b's.",
  "Source: 008b criterion 10; C21 (dry runs never use the production key; 008b criterion 10 follow-up booked)."
 ]
}''')

NORMATIVE = """on:
  push:
    branches: [main]
    paths: ['mods/*/entry.json']
  workflow_dispatch:
concurrency:
  group: pipeline
  cancel-in-progress: false
"""


def paragraphs(text):
    return re.split(r"\n[ \t]*\n", text)


def rule_paragraphs(text):
    found = {}
    for p in paragraphs(text):
        m = re.match(r"\*\*(PT\d+) ", p)
        if m:
            found.setdefault(m.group(1), []).append(p)
    return found


def normative_blocks(text):
    m = re.search(r"(?m)^## Normative trigger block\s*$", text)
    if not m:
        return None
    rest = text[m.end():]
    nxt = re.search(r"(?m)^## ", rest)
    sect = rest if not nxt else rest[: nxt.start()]
    return re.findall(r"(?s)```yaml\n(.*?)```", sect)


def contract_checks(text):
    """Return {check id: (ok, message)} for the contract text. Pure: used for the file and for every mutated copy."""
    res = {}

    def put(cid, ok, msg):
        res[cid] = (ok, msg)

    # AC1 header
    paras = [p for p in paragraphs(text) if p.strip() and not p.lstrip().startswith("#")]
    first = norm(paras[0]) if paras else ""
    need = ["E15", "N2 -> N5", "docs/architecture/depgraph.md"]
    miss = [n for n in need if n not in first]
    put("AC1", not miss, "first paragraph names E15, `N2 -> N5`, docs/architecture/depgraph.md" if not miss
        else "first paragraph lacks %s" % miss)

    # AC2 rule ids
    rp = rule_paragraphs(text)
    bad = []
    for n in range(1, 13):
        k = "PT%d" % n
        if len(rp.get(k, [])) != 1:
            bad.append("%s starts %d paragraphs" % (k, len(rp.get(k, []))))
            continue
        lines = rp[k][0].split("\n")
        if sum(1 for l in lines if l.startswith("Source:")) != 1:
            bad.append("%s has %d Source: lines" % (k, sum(1 for l in lines if l.startswith("Source:"))))
        elif not any(l.startswith("Source:") for l in lines[1:]) or lines[0].startswith("Source:"):
            bad.append("%s Source: line misplaced" % k)
    ids = sorted(set(re.findall(r"\bPT\d+\b", text)), key=lambda s: int(s[2:]))
    extra = [i for i in ids if not 1 <= int(i[2:]) <= 12]
    if extra:
        bad.append("rule ids outside PT1-PT12: %s" % extra)
    starts = re.findall(r"(?m)^\*\*(PT\d+)\b", text)
    if sorted(starts, key=lambda s: int(s[2:])) != ["PT%d" % n for n in range(1, 13)]:
        bad.append("paragraph-start ids are %s" % starts)
    msec = re.search(r"(?m)^## Rules\s*$", text)
    if not msec:
        bad.append("no '## Rules' section")
    else:
        rest = text[msec.end():]
        nx = re.search(r"(?m)^## ", rest)
        for pp in paragraphs(rest if not nx else rest[: nx.start()]):
            if pp.strip() and not re.match(r"\*\*PT\d+ ", pp.lstrip()):
                bad.append("unnumbered paragraph in Rules: %r" % norm(pp)[:80])
    put("AC2", not bad, "PT1-PT12 each start exactly one paragraph, each ends in one Source: line, no other PT<n>, no unnumbered paragraph in Rules"
        if not bad else "; ".join(bad))

    # AC3 normative block
    blocks = normative_blocks(text)
    allyaml = re.findall(r"(?s)```yaml\n(.*?)```", text)
    if blocks is None:
        put("AC3", False, "no heading 'Normative trigger block'")
    elif len(blocks) != 1 or len(allyaml) != 1:
        put("AC3", False, "%d yaml blocks under the heading, %d in the file (want 1 and 1)" % (len(blocks), len(allyaml)))
    elif blocks[0] != NORMATIVE:
        d = "\n".join(difflib.unified_diff(NORMATIVE.splitlines(), blocks[0].splitlines(), "script", "contract", lineterm="", n=0))
        put("AC3", False, "normative block differs from the script's literal:\n" + d)
    else:
        put("AC3", True, "exactly one yaml block under 'Normative trigger block', byte-identical to the script's literal")

    def para(k):
        ps = rp.get(k, [])
        return norm(" ".join(ps[0].split("\n"))) if len(ps) == 1 else ""

    def has(k, phrases):
        p = para(k)
        return [x for x in phrases if norm(x) not in p]

    # AC4 forbidden triggers
    m4 = has("PT1", ["exactly two", "`push` to `main`", "`workflow_dispatch`", "never uses `pull_request`",
                     "`pull_request_target`", "`workflow_run`", "`repository_dispatch`", "`schedule`", "or any other event",
                     "Adding a trigger amends this contract."])
    put("AC4", not m4, "PT1 names the closed list, the forbidden event names and the amendment rule" if not m4
        else "PT1 lacks %s" % m4)

    # AC5 pending only and no-op
    m5 = has("PT5", ["every `pending` version on `main`", "are never built",
                     "A fault or a refusal ends that version only: the run continues with the remaining `pending` versions "
                     "and fails at the end, naming each version that failed.",
                     "Zero `pending` versions is a success that writes nothing.",
                     "it refuses with planner exit 1 and writes nothing, and that refusal is not a 008a verdict.",
                     "`env:`"])
    m5 += has("PT7", ["moves exactly one version out of `pending`", "does not trigger E15",
                      "the run that finds zero `pending` versions ends having written nothing"])
    put("AC5", not m5, "PT5 (pending only, fault ends that version only, zero pending, planner exit 1 / not a 008a verdict, "
        "`env:`) and PT7 (termination argument) carry their sentences" if not m5 else "missing: %s" % m5)

    # AC6 failure semantics
    p10 = para("PT10")
    m6 = has("PT10", ["0 built, 1 rejected, 2 pipeline fault", "Exit 0:", "Exit 1:", "Exit 2:", "`reason`", "`build_log_url`",
                      "`https://`", "non-empty after trimming", "the version stays `pending`",
                      "the log commit precedes the T3 PR",
                      "an existing log at that path fails that version (PT8)",
                      "`logs/<namespace>.<name>/<version>.log`", "the full `build.log`"])
    e2 = re.search(r"Exit 2:.*?(?=Source:|$)", p10)
    e2t = e2.group(0) if e2 else ""
    if not e2t or "no T3 PR" not in e2t or "no comment" not in e2t or "no release" not in e2t or re.search(r"\bopens?\b", e2t):
        m6.append("exit 2 outcome is not 'no comment, no T3 PR, no release, nothing written'")
    put("AC6", not m6, "PT10 names exit codes 0, 1, 2 with their outcomes, `reason`, `build_log_url`, `https://`, "
        "stays `pending`, log-commit-precedes-T3, existing-log fails" if not m6 else "PT10: %s" % m6)

    # AC7 every sentence pinned by full text
    for k in ["PT%d" % n for n in range(1, 13)]:
        pins = PINS[k]
        p = para(k)
        missing = [s for s in pins if norm(s) not in p]
        joined = " ".join(norm(s) for s in pins)
        if not p:
            put("AC7:" + k, False, "%s not found" % k)
        elif missing:
            put("AC7:" + k, False, "%d pinned sentence(s) missing or edited: %s" % (len(missing), " || ".join(m[:90] for m in missing)))
        elif p != joined:
            sm = difflib.SequenceMatcher(None, joined, p)
            added = [p[j1:j2] for tag, i1, i2, j1, j2 in sm.get_opcodes() if tag in ("insert", "replace")]
            put("AC7:" + k, False, "text beyond the pinned sentences: %s" % (" | ".join(a[:120] for a in added) or "order differs"))
        else:
            put("AC7:" + k, True, "%s: %d pinned pieces (heading, %d sentences, Source line) equal the paragraph" % (k, len(pins), len(pins) - 2))

    # AC11 the nine unverified GitHub-behaviour statements
    nine = [
        ("fork secret withholding", "PT1", "withholds repository secrets"),
        ("waiting-run replacement incl. push replaced by dispatch", "PT6", "can be replaced by a waiting dispatch run"),
        ("`*` vs `/`", "PT2", "`*` does not match `/`"),
        ("diff fallback", "PT2", "cannot compute the diff"),
        ("who may dispatch", "PT1", "started only by an account with write access"),
        ("dispatch runs the selected ref's workflow file", "PT3", "runs the workflow file of the ref selected at dispatch"),
        ("merge by the App identity fires push", "PT7", "fires a `push` run is `[unverified]`"),
        ("re-run reuses the original commit's workflow file", "PT8", "uses the workflow file of the original commit"),
        ("environment mechanics of C20/M11", "PT3", "the environment mechanics are"),
    ]
    bad = []
    for label, k, key in nine:
        sents = [s for s in re.split(r"(?<=[.])\s+(?=[A-Z`])", para(k)) if key in s]
        if len(sents) != 1 or "[unverified]" not in sents[0]:
            bad.append(label)
    put("AC11", not bad, "all nine GitHub-behaviour statements carry `[unverified]`" if not bad else "no [unverified] marker: %s" % bad)
    return res


def readme_checks(text):
    res = {}
    rows = [l for l in text.splitlines() if l.startswith("| `contracts/pipeline-trigger.md`")]
    ok = len(rows) == 1 and rows[0].rstrip().endswith("| E15 |")
    res["AC8.row"] = (ok, "README has one table row for contracts/pipeline-trigger.md ending in the edge E15" if ok
                      else "README row for pipeline-trigger.md: %d row(s), E15 column missing or wrong" % len(rows))
    n = len(re.findall(r"does not exist yet", text))
    res["AC8.bullet"] = (n == 0, "README has no 'does not exist yet' bullet" if n == 0 else "README still says 'does not exist yet' (%d)" % n)
    return res


def report(res, only=None):
    for cid in sorted(res, key=lambda s: (s.split(":")[0], s)):
        ok, msg = res[cid]
        out("PASS" if ok else "FAIL", cid, msg.replace("\n", "\n        "))


# ---------------------------------------------------------------------------------------------------
print("\n== AC10 -- pins: explicit SHAs, scope, control ==")
for name, sha in (("BASE", BASE), ("FINAL", FINAL), ("TIP", TIP)):
    ok = git("cat-file", "-e", sha + "^{commit}", check=False).returncode == 0
    out("PASS" if ok else "FAIL", "AC10.pin", "%s %s exists" % (name, sha[:12]) if ok else "%s %s does not exist" % (name, sha))
if (git("merge-base", "--is-ancestor", BASE, FINAL, check=False).returncode == 0
        and git("merge-base", "--is-ancestor", FINAL, TIP, check=False).returncode == 0):
    out("PASS", "AC10.order", "BASE is an ancestor of FINAL, and FINAL of TIP")
else:
    out("FAIL", "AC10.order", "BASE, FINAL, TIP are not in ancestor order")
SCOPE_FINAL = {CONTRACT, README, "docs/tasks/082-pipeline-trigger-contract.md"}
SCOPE_HEAD = SCOPE_FINAL | {"docs/tasks/082-verify.sh"}


def own_change(base, final, repo=None):
    """Return a list of failure strings for the own-change checks on base..final."""
    bad = []
    names = set(git("diff", "--name-only", base, final, repo=repo).stdout.decode().split())
    if not names:
        bad.append("empty diff")
    extra = sorted(names - SCOPE_FINAL)
    if extra:
        bad.append("files outside the declared scope: %s" % extra)
    if CONTRACT not in names:
        bad.append("%s not in the diff" % CONTRACT)
    c = git("diff", "--name-only", base, final, "--", "contracts/", repo=repo).stdout.decode().split()
    if c != [CONTRACT]:
        bad.append("contracts/ diff lists %s, want only [%s]" % (c, CONTRACT))
    return bad


bad = own_change(BASE, FINAL)
out("PASS" if not bad else "FAIL", "AC9/AC10.scope",
    "BASE..FINAL touches only the declared scope, and under contracts/ only the new file" if not bad else "; ".join(bad))
bad = own_change(BASE, BASE)
out("PASS" if bad else "FAIL", "AC10.control", "control FINAL=BASE is red (%s)" % "; ".join(bad) if bad else "control FINAL=BASE was NOT red")


def tip_checks(base, final, tip, repo=None):
    """Own-change checks on the pinned TIP (never HEAD): scope on base..tip, and the merged bytes equal the verified bytes."""
    bad = []
    names = set(git("diff", "--name-only", base, tip, repo=repo).stdout.decode().split())
    extra = sorted(names - SCOPE_HEAD)
    if extra:
        bad.append("BASE..TIP touches files outside the scope: %s" % extra)
    d = git("diff", "--name-only", final, tip, "--", CONTRACT, README, repo=repo).stdout.decode().split()
    if d:
        bad.append("FINAL..TIP changes %s (the merged bytes differ from the verified bytes)" % d)
    return bad


bad = tip_checks(BASE, FINAL, TIP)
out("PASS" if not bad else "FAIL", "AC10.tip", "BASE..TIP touches only the declared scope (log and script included)" if not bad else "; ".join(bad))
out("PASS" if not [b for b in bad if "FINAL..TIP" in b] else "FAIL", "AC10.bytes",
    "git diff FINAL TIP -- contracts/pipeline-trigger.md docs/contracts/README.md is empty: merged bytes equal verified bytes"
    if not [b for b in bad if "FINAL..TIP" in b] else "FINAL..TIP differs in the contract or README")

# Mutation proofs for the TIP checks: commits on top of TIP in a throw-away clone (the real repository is never written).
mc = os.path.join(TMP, "tipclone")
subprocess.run(["git", "clone", "-q", "--no-hardlinks", ROOT, mc], check=True, capture_output=True)
GC = ["-c", "user.name=verify", "-c", "user.email=verify@example.invalid", "-c", "commit.gpgsign=false"]


def mk_commit(msg, path, content, append=False):
    git("checkout", "-q", "--detach", TIP, repo=mc)
    fp = os.path.join(mc, path)
    os.makedirs(os.path.dirname(fp), exist_ok=True)
    with open(fp, "a" if append else "w") as fh:
        fh.write(content)
    git("add", path, repo=mc)
    git(*GC, "commit", "-q", "-m", msg, repo=mc)
    return git("rev-parse", "HEAD", repo=mc).stdout.decode().strip()


m1 = mk_commit("mutant: out-of-scope file on top of TIP", "tools/mutant.txt", "x\n")
b1 = tip_checks(BASE, FINAL, m1, repo=mc)
out("PASS" if any("outside the scope" in b for b in b1) else "FAIL", "MUT.tip-scope",
    "AC10.tip mutation: a commit on top adding tools/mutant.txt is red (%s)" % ("; ".join(b1) or "NOT RED"))
m2 = mk_commit("mutant: post-FINAL edit of the contract", CONTRACT, "\nExtra permissive line.\n", append=True)
b2 = tip_checks(BASE, FINAL, m2, repo=mc)
out("PASS" if any("FINAL..TIP" in b for b in b2) else "FAIL", "MUT.tip-bytes",
    "AC10.bytes mutation: a post-FINAL edit of the contract is red (%s)" % ("; ".join(b2) or "NOT RED"))
m3 = mk_commit("mutant: post-FINAL edit of the README", README, "\nExtra line.\n", append=True)
b3 = tip_checks(BASE, FINAL, m3, repo=mc)
out("PASS" if any("FINAL..TIP" in b for b in b3) else "FAIL", "MUT.tip-bytes",
    "AC10.bytes mutation: a post-FINAL edit of the README is red (%s)" % ("; ".join(b3) or "NOT RED"))
b4 = tip_checks(BASE, FINAL, TIP, repo=mc)
out("PASS" if not b4 else "FAIL", "MUT.tip-restored", "restored: the real TIP is green again in the clone" if not b4 else "TIP red after restore: %s" % b4)

print("\n== AC1 -- the file exists at FINAL, absent at BASE ==")
final_bytes = blob(FINAL, CONTRACT)
if final_bytes is None:
    out("FAIL", "AC1.exists", "%s is absent at FINAL" % CONTRACT)
    print("cannot continue without the contract")
    print("\n== RESULT ==\n%d CHECK(S) FAILED" % FAILURES)
    sys.exit(FAILURES)
out("PASS", "AC1.exists", "%s exists at FINAL (%d lines)" % (CONTRACT, final_bytes.count(b"\n")))
out("PASS" if blob(BASE, CONTRACT) is None else "FAIL", "AC1.control", "control: the file is absent at BASE (red there)"
    if blob(BASE, CONTRACT) is None else "the file already exists at BASE")
text = final_bytes.decode("utf-8")
FINAL_SHA256 = hashlib.sha256(final_bytes).hexdigest()

print("\n== AC1-AC7, AC11 -- contract text at FINAL ==")
res = contract_checks(text)
report(res)

print("\n== AC8 -- index ==")
rb = blob(BASE, README).decode()
rf = blob(FINAL, README).decode()
n0 = len(re.findall(r"does not exist yet", rb))
out("PASS" if n0 >= 1 else "FAIL", "AC8.control", "control: 'does not exist yet' appears %d time(s) at BASE" % n0 if n0 >= 1
    else "control: 'does not exist yet' absent at BASE")
rres = readme_checks(rf)
report(rres)
bres = readme_checks(rb)
out("PASS" if not all(ok for ok, _ in bres.values()) else "FAIL", "AC8.control2", "control: the README checks are red at BASE")

print("\n== AC3-AC7, AC8, AC11 -- mutations: each applied to a copy of the FINAL blob, red, then restored byte-identically and green ==")


def flex(old):
    return re.compile(r"\s+".join(re.escape(w) for w in old.split()))


def mut_text(old, new):
    rx = flex(old)

    def f(t):
        ms = rx.findall(t)
        assert len(ms) == 1, "mutation target %r found %d times" % (old, len(ms))
        return rx.sub(lambda m: new, t, count=1)
    return f


def mut_block(old, new):
    def f(t):
        i = t.index("## Normative trigger block")
        j = t.index("```yaml", i)
        k = t.index("```", j + 7)
        blk = t[j:k]
        assert blk.count(old) == 1, "block mutation target %r found %d times" % (old, blk.count(old))
        return t[:j] + blk.replace(old, new) + t[k:]
    return f


MUTATIONS = [
    # (label, mutation, check ids of which at least one must turn red)
    ("AC3 block: paths -> mods/**", mut_block("'mods/*/entry.json'", "'mods/**'"), ["AC3"]),
    ("AC3 block: cancel-in-progress: true", mut_block("cancel-in-progress: false", "cancel-in-progress: true"), ["AC3"]),
    ("AC3 block: pull_request: added", mut_block("on:\n", "on:\n  pull_request:\n"), ["AC3"]),
    ("AC3 block: group renamed", mut_block("group: pipeline", "group: pipelines"), ["AC3"]),
    ("AC4 PT1: delete the closed-list/forbidden-names sentence",
     mut_text("It never uses `pull_request`, `pull_request_target`, `workflow_run`, `repository_dispatch`, `schedule` or any other event.", ""),
     ["AC4", "AC7:PT1"]),
    ("AC5 PT5: drop 'pending' (build every version)", mut_text("build every `pending` version on `main`", "build every version on `main`"),
     ["AC5", "AC7:PT5"]),
    ("AC5 PT5: delete the zero-pending sentence", mut_text("Zero `pending` versions is a success that writes nothing.", ""),
     ["AC5", "AC7:PT5"]),
    ("AC5 PT5: delete the fault-ends-that-version-only sentence",
     mut_text("A fault or a refusal ends that version only: the run continues with the remaining `pending` versions and fails at "
              "the end, naming each version that failed.", ""), ["AC5", "AC7:PT5"]),
    ("AC5 PT5: the version input may be interpolated (env: sentence deleted)",
     mut_text("and it reaches scripts only through `env:`, never by interpolation into a `run:` block", "and it reaches scripts"),
     ["AC5", "AC7:PT5"]),
    ("AC5 PT7: delete the termination sentence", mut_text("Each such transition moves exactly one version out of `pending`, and a `pending` version leaves that state only this way (PT9).", ""),
     ["AC5", "AC7:PT7"]),
    ("AC6 PT10: exit 2 opens a T3 PR", mut_text("with no comment, no T3 PR, no release and nothing written", "with a T3 PR and no release"),
     ["AC6", "AC7:PT10"]),
    ("AC6 PT10: the log commit no longer precedes the T3 PR", mut_text("the log commit precedes the T3 PR", "the log commit follows the T3 PR"),
     ["AC6", "AC7:PT10"]),
    ("AC7 PT3: tail-append one permissive sentence",
     mut_text("The dry-run job references neither environment.", "The dry-run job references neither environment. Any account may dispatch from any ref and reach the key."),
     ["AC7:PT3"]),
    ("AC7 PT3: widen the ref (refs/heads/main -> refs/heads/*)", mut_text("'refs/heads/main'", "'refs/heads/*'"), ["AC7:PT3"]),
    ("AC7 PT3: drop the write-access/trust-boundary sentence",
     mut_text("Until M11 is done, the trust boundary of `MINISIGN_SECRET_KEY` and `PIPELINE_APP_PRIVATE_KEY` is every account with write access to the registry.", ""),
     ["AC7:PT3"]),
    ("AC7 PT3: drop the signing environment",
     mut_text("only by a GitHub Actions environment named `signing` on the signing job, with deployment branches limited to `main` and `MINISIGN_SECRET_KEY` stored as that environment's secret,", "only by the ref condition,"),
     ["AC7:PT3"]),
    ("AC7 PT3: drop the write-back environment",
     mut_text(", and the App key is bound only by an environment named `write-back` configured the same way for `PIPELINE_APP_PRIVATE_KEY`", ""),
     ["AC7:PT3"]),
    ("AC7 PT3: drop the 'repo-level copies deleted' clause",
     mut_text("creates both environments and deletes the repo-level copies of both secrets, because an environment copy protects nothing while a repo-level copy exists, and", "creates both environments, and"),
     ["AC7:PT3"]),
    ("AC7 PT11: allow GITHUB_TOKEN", mut_text("never with `GITHUB_TOKEN`", "with `GITHUB_TOKEN`"), ["AC7:PT11"]),
    ("AC7 PT11: drop the 30-minute deadline", mut_text("or a PR is not merged within 30 minutes, ", ""), ["AC7:PT11"]),
    ("AC7 PT12: the dry run uses the production key", mut_text("It never uses the production key:", "It uses the production key:"), ["AC7:PT12"]),
    ("AC7 PT6: cancel-in-progress sentence edited to true", mut_text("cancel-in-progress: false }", "cancel-in-progress: true }"), ["AC7:PT6"]),
    ("AC11 PT7: drop the [unverified] marker on the App-merge statement",
     mut_text("fires a `push` run is `[unverified]`", "fires a `push` run is certain"), ["AC11", "AC7:PT7"]),
    ("AC2 Rules: unnumbered 'Exception:' paragraph inserted after PT3",
     lambda t: t.replace("\n\n**PT4 Input snapshot.**", "\n\n**Exception:** a dispatch from any ref may reach the key.\n\n**PT4 Input snapshot.**", 1), ["AC2"]),
    ("AC2 PT13 id added", lambda t: t.replace("**PT12 Dry run.**", "**PT13 Extra rule.** Anything goes.\nSource: none.\n\n**PT12 Dry run.**", 1), ["AC2"]),
]
for label, fn, want in MUTATIONS:
    path = os.path.join(TMP, "mutant.md")
    try:
        mutated = fn(text)
    except AssertionError as e:
        out("FAIL", "MUT", "%s: cannot apply (%s)" % (label, e))
        continue
    if mutated == text:
        out("FAIL", "MUT", "%s: the mutation did not change the text" % label)
        continue
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(mutated)
    mres = contract_checks(open(path, encoding="utf-8", newline="").read())
    red = sorted(k for k, (ok, _) in mres.items() if not ok)
    hit = [w for w in want if w in red]
    # restore from the FINAL blob and prove it
    with open(path, "wb") as fh:
        fh.write(final_bytes)
    same = hashlib.sha256(open(path, "rb").read()).hexdigest() == FINAL_SHA256
    rres2 = contract_checks(open(path, encoding="utf-8", newline="").read())
    green = all(ok for ok, _ in rres2.values())
    good = bool(hit) and same and green
    out("PASS" if good else "FAIL", "MUT",
        "%s: red on %s; restored byte-identical=%s, green=%s" % (label, ",".join(red) or "NOTHING", same, green))

# README mutation: the old bullet comes back
old_bullet = "- **`contracts/pipeline-trigger.md` (E15) is not part of either task** and does not exist yet\n"
rm = rf + old_bullet
rr = readme_checks(rm)
red = sorted(k for k, (ok, _) in rr.items() if not ok)
same = hashlib.sha256(rf.encode()).hexdigest() == hashlib.sha256(blob(FINAL, README)).hexdigest()
out("PASS" if "AC8.bullet" in red and same and all(ok for ok, _ in readme_checks(rf).values()) else "FAIL", "MUT",
    "AC8 README: the 'does not exist yet' bullet re-added: red on %s; restored identical=%s, green" % (",".join(red) or "NOTHING", same))
rr = readme_checks("\n".join(l for l in rf.splitlines() if not l.startswith("| `contracts/pipeline-trigger.md`")))
out("PASS" if "AC8.row" in [k for k, (ok, _) in rr.items() if not ok] else "FAIL", "MUT", "AC8 README: the E15 row deleted: red on AC8.row")

# positive control, once more, after all mutations: the FINAL blob itself
res = contract_checks(text)
out("PASS" if all(ok for ok, _ in res.values()) else "FAIL", "MUT.control", "positive control after all mutations: the FINAL blob is green on every contract check")

print("\n== RESULT ==")
print("ALL CHECKS PASSED" if FAILURES == 0 else "%d CHECK(S) FAILED" % FAILURES)
sys.exit(FAILURES)
PY

python3 -I -B "$TMP/check.py" "$ROOT" "$BASE" "$FINAL" "$TMP" "$TIP"
RC=$?
FAILURES=$RC

if [ -n "$PLATFORM" ]; then
    printf '\n== AC12 -- ADVISORY (not counted): 008b design 1 and 3 next to the normative block ==\n'
    S="$PLATFORM/docs/tasks/008b-pipeline-workflow.md"
    if [ -r "$S" ]; then
        echo "-- normative block in the contract at FINAL --"
        git -C "$ROOT" show "$FINAL:contracts/pipeline-trigger.md" | python3 -I -B -c '
import re, sys
t = sys.stdin.read()
i = t.index("## Normative trigger block")
print("\n".join(re.findall(r"(?s)```yaml\n(.*?)```", t[i:])[:1]))'
        echo "-- 008b design 1 and 3 --"
        awk '/^1\. \*\*Trigger \(E15/{p=1} /^2\. \*\*What to build/{p=0} /^3\. \*\*Concurrency/{p=1} /^4\. \*\*Branch and PR/{p=0} p' "$S"
    else
        echo "ADVISORY: $S not readable; skipped"
    fi
else
    printf '\nAC12 ADVISORY: not run (pass --platform DIR to print 008b design 1 and 3)\n'
fi

printf '\n== AC13 -- fresh clone, every closed verify script green on HEAD ==\n'
if [ "$FULL" = 1 ]; then
    NM="${WOM_NODE_MODULES:-$ROOT/tools/dev/node_modules}"
    git clone -q --no-hardlinks "$ROOT" "$TMP/fresh" && git -C "$TMP/fresh" checkout -q "$(git -C "$ROOT" rev-parse HEAD)" || { echo "FAIL  AC13 cannot clone"; FAILURES=$((FAILURES + 1)); }
    if [ -d "$TMP/fresh" ]; then
        for s in "$TMP"/fresh/docs/tasks/*-verify.sh; do
            n="$(basename "$s")"
            [ "$n" = "082-verify.sh" ] && continue
            ( cd "$TMP/fresh" && env WOM_NODE_MODULES="$NM" PYTHONDONTWRITEBYTECODE=1 bash "docs/tasks/$n" ) > "$TMP/$n.out" 2>&1
            rc=$?
            if [ "$rc" = 0 ]; then echo "PASS  AC13 $n exits 0"; else echo "FAIL  AC13 $n exits $rc"; grep -m5 '^FAIL' "$TMP/$n.out" | sed 's/^/        /'; FAILURES=$((FAILURES + 1)); fi
        done
    fi
else
    echo "NOT RUN  AC13 (pass --full; it runs the other verify scripts one at a time in a fresh clone). Not green."
fi

printf '\n== TOTAL ==\n'
if [ "$FAILURES" = 0 ]; then echo "ALL CHECKS PASSED (AC13 only if --full was given)"; else echo "$FAILURES CHECK(S) FAILED"; fi
exit "$FAILURES"
