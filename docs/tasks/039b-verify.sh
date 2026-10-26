#!/usr/bin/env bash
#
# 039b-verify.sh -- the runnable verification artefact for task 039b (the registry CI workflow; MANAGER.md Section 2c).
#
# Task 039b (second half of 039, split by choice C23): .github/workflows/registry-ci.yml, tests/registry/test_ci_workflow.py,
# CONTRIBUTING.md and the README paragraph. Demonstrates AC7 (workflow structure + every mutation), AC10 (docs), AC11 (own-change
# checks) and AC12 (live guards) of docs/tasks/039-registry-ci-workflow.md. The composer (AC1-AC6, AC8, AC9) is 039a-verify.sh's.
# The platform runbook steps M9/M10/M11 live in the platform repository (task/039b-runbook) and are reviewed there.
#
# Usage:  docs/tasks/039b-verify.sh [NODE_MODULES_DIR]      (any cwd inside the repository)
#   NODE_MODULES_DIR (or env WOM_NODE_MODULES, else <repo root>/tools/dev/node_modules; install with npm ci --prefix tools/dev)
#   is only needed by the closed verify scripts of AC12 (they use ajv).
# Own-change checks use the EXPLICIT SHAs below (BASE, RED, FINAL, TIP), never HEAD or origin/main. Behaviour checks run on the
# COMMITTED HEAD in a temporary clone under `env -i`; the caller's worktree is not modified. No credential, no gh, no act, no live
# PR. Network, all anonymous: `git ls-remote` of the four pinned actions (the pins must exist) and 066-verify.sh (npm ci).
# AC12 runs the whole registry suite and every closed verify script ONE AT A TIME, and waits while another *-verify.sh runs.
# 039a-verify.sh is not re-run here: it runs every verify script, 039b's included, so running it from here would recurse.
# To satisfy AC12's "fresh clone" clause run this script from a fresh `git clone` of the pushed branch.
# Exit code: the number of failed checks (2 if PyYAML is missing: never a skip). Requires: git, python3 + PyYAML, node (AC12).

set -u
set -o pipefail

BASE=4268735        # registry origin/main (039a merged, PR #21) the branch was cut from
RED=6b94a31         # tests + spec log only; .github/workflows/registry-ci.yml does not exist yet
FINAL=2a98fa1       # last commit that changes the workflow, the tests, CONTRIBUTING.md or README.md (later commits: log and this script)
TIP=a3901e5         # last branch commit before the one that pinned TIP: BASE..TIP is the scope-checked range, so a later merge with
                    # registry main cannot redden it. The one commit after TIP changes only this script (in scope).

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
NM="${1:-${WOM_NODE_MODULES:-$ROOT/tools/dev/node_modules}}"
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }
TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT
G() { git -C "$ROOT" "$@"; }
HEADREV="$(G rev-parse HEAD)"
CLEAN() { env -i PATH="$PATH" HOME="$(mktemp -d "$TMP/home.XXXXXX")" LANG=C.UTF-8 GIT_TERMINAL_PROMPT=0 "$@"; }

python3 -I -c 'import yaml' 2>/dev/null || { echo "ERROR: PyYAML is missing (python3 -m pip install pyyaml); AC7 cannot be skipped" >&2; exit 2; }

SCOPE='^(\.github/workflows/registry-ci\.yml|tests/registry/test_ci_workflow\.py|CONTRIBUTING\.md|README\.md|docs/tasks/039-registry-ci-workflow\.md|docs/tasks/039b-verify\.sh)$'

# ---------------------------------------------------------------------------------------------------------------------
own_change_checks() {  # own_change_checks FINALREV : prints PASS/FAIL lines, returns the number of failures it found
    local final="$1" n=0 s
    for s in "$BASE" "$RED" "$final" "$TIP"; do
        G cat-file -e "$s^{commit}" 2>/dev/null && pass "pin $s exists" || { fail "pin $s does not exist"; n=$((n + 1)); }
    done
    G merge-base --is-ancestor "$BASE" "$RED" 2>/dev/null && pass "BASE is an ancestor of the red commit" || { fail "BASE is not an ancestor of the red commit"; n=$((n + 1)); }
    G merge-base --is-ancestor "$RED" "$final" 2>/dev/null && pass "the red commit is an ancestor of FINAL (red first)" || { fail "the red commit is not an ancestor of FINAL"; n=$((n + 1)); }
    G merge-base --is-ancestor "$final" "$TIP" 2>/dev/null && pass "FINAL is an ancestor of TIP" || { fail "FINAL is not an ancestor of TIP"; n=$((n + 1)); }
    if G cat-file -e "$RED:.github/workflows/registry-ci.yml" 2>/dev/null; then fail "the workflow already exists at the red commit"; n=$((n + 1)); else pass "the workflow does not exist at the red commit"; fi
    if G cat-file -e "$final:.github/workflows/registry-ci.yml" 2>/dev/null; then pass "the workflow exists at FINAL"; else fail "the workflow does not exist at FINAL"; n=$((n + 1)); fi
    local files bad
    files="$(G diff --name-only "$BASE" "$final")"
    bad="$(printf '%s\n' "$files" | grep -v -E "$SCOPE")"
    [ -n "$files" ] && [ -z "$bad" ] && pass "git diff --name-only BASE FINAL is inside the file scope" || { fail "BASE..FINAL touches out-of-scope or no files: ${bad:-<empty diff>}"; n=$((n + 1)); }
    bad="$(G diff --name-only "$BASE" "$TIP" | grep -v -E "$SCOPE")"
    [ -z "$bad" ] && pass "BASE..TIP touches only the declared file scope" || { fail "out-of-scope files in BASE..TIP: $bad"; n=$((n + 1)); }
    G diff --quiet "$final" "$TIP" -- .github tests/registry CONTRIBUTING.md README.md tools config contracts 2>/dev/null \
        && pass "no workflow, test, doc, tool, config or contract byte differs between FINAL and TIP (merged bytes = verified bytes)" || { fail "files differ between FINAL and TIP"; n=$((n + 1)); }
    bad="$(G diff --name-only "$BASE" "$final" -- tools config contracts)"
    [ -z "$bad" ] && pass "no tool, config or contract file changed (the 039a composer is reviewed as merged)" || { fail "tool/config/contract files changed: $bad"; n=$((n + 1)); }
    bad="$(G diff --name-only "$BASE" "$RED" | grep -v -E '^(tests/registry/test_ci_workflow\.py|docs/tasks/039-registry-ci-workflow\.md)$')"
    [ -z "$bad" ] && pass "the red commit holds the AC7 tests and the spec log only" || { fail "red commit touches: $bad"; n=$((n + 1)); }
    local red="$TMP/red.$$.$RANDOM"   # the tests fail at the red commit (every one of them), in a mktemp clone
    if git clone -q --no-hardlinks "$ROOT" "$red" 2>/dev/null && git -C "$red" checkout -q --detach "$RED" 2>/dev/null; then
        ( cd "$red" && CLEAN python3 -I -B -m unittest discover -s tests/registry -p test_ci_workflow.py > "$red.out" 2>&1 ); local rc=$?
        local ran bad_n
        ran="$(sed -n 's/^Ran \([0-9]*\) tests.*/\1/p' "$red.out")"
        bad_n="$(grep '^FAILED (' "$red.out" | grep -o '[0-9][0-9]*' | awk '{s+=$1} END {print s+0}')"
        [ "$rc" != 0 ] && [ -n "$ran" ] && [ "$ran" -gt 0 ] && [ "$ran" = "${bad_n:-x}" ] \
            && pass "at the red commit all $ran workflow tests fail" || { fail "at the red commit not every test fails (exit $rc, ran ${ran:-?}, failing ${bad_n:-?})"; n=$((n + 1)); }
        rm -rf "$red"
    else
        fail "cannot check out the red commit"; n=$((n + 1))
    fi
    return "$n"
}

section "AC11 -- own-change checks pinned (BASE $BASE, RED $RED, FINAL $FINAL)"
( own_change_checks "$FINAL" ) > "$TMP/ac11.out"; rc=$?   # subshell: its FAIL lines are counted below, not twice
cat "$TMP/ac11.out"
FAILURES=$((FAILURES + $(grep -c '^FAIL ' "$TMP/ac11.out")))
[ "$rc" = 0 ] && pass "AC11: all own-change checks pass" || fail "AC11: $rc own-change check(s) failed"
( own_change_checks "$BASE" ) > "$TMP/ac11c.out"; rc=$?   # control: with FINAL=BASE the same checks must fail
[ "$rc" -gt 0 ] && pass "AC11 control: FINAL=BASE makes $rc own-change check(s) fail" || fail "AC11 control: FINAL=BASE does not fail the own-change checks"

# ---------------------------------------------------------------------------------------------------------------------
section "AC7 -- workflow structure and mutations on the COMMITTED HEAD (temporary clone, env -i)"
git clone -q --no-hardlinks "$ROOT" "$TMP/head" && git -C "$TMP/head" checkout -q --detach "$HEADREV" || { fail "cannot clone HEAD"; exit "$FAILURES"; }
cat > "$TMP/runner.py" <<'PY'
import os, sys, unittest
sys.path.insert(0, "tests/registry")
class R(unittest.TextTestResult):
    def addSuccess(self, t):
        super().addSuccess(t); print("ok", type(t).__name__, t._testMethodName, flush=True)
    def addFailure(self, t, e):
        super().addFailure(t, e); print("BAD", type(t).__name__, t._testMethodName, flush=True)
    def addError(self, t, e):
        super().addError(t, e); print("BAD", type(t).__name__, t._testMethodName, flush=True)
suite = unittest.defaultTestLoader.discover("tests/registry", pattern="test_ci_workflow.py")
res = unittest.TextTestRunner(stream=open(os.devnull, "w"), resultclass=R).run(suite)
print("ran", res.testsRun, "failed", len(res.failures) + len(res.errors))
sys.exit(0 if res.wasSuccessful() else 1)
PY
( cd "$TMP/head" && CLEAN python3 -I -B "$TMP/runner.py" > "$TMP/wf.out" 2> "$TMP/wf.err" ); rc=$?
[ "$rc" = 0 ] && pass "tests/registry/test_ci_workflow.py: $(grep '^ran ' "$TMP/wf.out")" || { fail "test_ci_workflow.py red (exit $rc)"; grep '^BAD' "$TMP/wf.out"; }
class_check() {  # class_check CLASS EXPECTED_COUNT LABEL : the class ran exactly N tests and every one is ok (zero matches fail)
    local ran ok
    ran="$(grep -c -E "^(ok|BAD) $1 " "$TMP/wf.out")"
    ok="$(grep -c -E "^ok $1 " "$TMP/wf.out")"
    [ "$ran" = "$2" ] && [ "$ok" = "$2" ] && pass "$3: $ok/$2 tests ok" || fail "$3: expected $2 ok tests, ran $ran, ok $ok"
}
class_check AC7Structure 7 "AC7 structure (positive control, on->True, shape, pins, size, no --tools-dir, run-log link)"
class_check AC7ZeroMatches 2 "AC7 fails on zero matches"
class_check AC7Mutations 2 "AC7 mutations"
# every mutation, one line each, run by an independent driver on a COPY of the file; the real file is hashed before and after
python3 -I - "$TMP/head" <<'PY' > "$TMP/mut.out" 2>&1
import hashlib, sys, tempfile
from pathlib import Path
sys.path.insert(0, sys.argv[1] + "/tests/registry")
sys.dont_write_bytecode = True
import test_ci_workflow as t
before = hashlib.sha256(t.WORKFLOW.read_bytes()).hexdigest()
text = t.WORKFLOW.read_text()
base = t.check(text)
print(("PASS  positive control: the unmodified workflow has no violation" if not base else "FAIL  positive control red: %s" % base))
bad = len(base)
with tempfile.TemporaryDirectory() as d:
    copy = Path(d) / "registry-ci.yml"
    for m in t.MUTATIONS:
        copy.write_text(t.mutate(text, m))
        found = t.check(copy.read_text())
        if found: print("PASS  mutation red: %s  [%s]" % (m, found[0][:70]))
        else: print("FAIL  mutation NOT red: %s" % m); bad += 1
        copy.write_bytes(text.encode())
        if t.check(copy.read_text()): print("FAIL  restored copy still red after: %s" % m); bad += 1
after = hashlib.sha256(t.WORKFLOW.read_bytes()).hexdigest()
print("PASS  the real workflow file is byte-identical before and after (%s)" % before[:12] if before == after else "FAIL  the real workflow changed")
bad += before != after
print("PASS  %d mutations all red" % len(t.MUTATIONS) if bad == 0 else "FAIL  %d problem(s)" % bad)
sys.exit(1 if bad else 0)
PY
cat "$TMP/mut.out"
FAILURES=$((FAILURES + $(grep -c '^FAIL ' "$TMP/mut.out")))
# independent facts straight from the file text (not through the test module)
WF="$TMP/head/.github/workflows/registry-ci.yml"
n_uses="$(grep -c -E '^\s*(- )?uses:' "$WF")"; n_pin="$(grep -c -E '^\s*(- )?uses: [A-Za-z0-9_./-]+@[0-9a-f]{40}( #.*)?$' "$WF")"
[ "$n_uses" -ge 4 ] && [ "$n_uses" = "$n_pin" ] && pass "all $n_uses uses: lines are pinned to 40 hex" || fail "uses lines: $n_uses, pinned: $n_pin"
grep -q -E '^  pull_request_target:' "$WF" && ! grep -q -E '^  (pull_request|workflow_run|push|schedule|workflow_dispatch):' "$WF" && pass "the only trigger is pull_request_target" || fail "trigger set is not exactly pull_request_target"
! grep -q -E 'GITHUB_ENV|GITHUB_PATH|PIPELINE_APP_PRIVATE_KEY|MINISIGN_SECRET_KEY|--tools-dir|--paths-file' "$WF" && pass "no GITHUB_ENV/GITHUB_PATH/forbidden secret/--tools-dir/--paths-file in the file" || fail "forbidden text in the workflow"
python3 -I - "$WF" <<'PY' && pass "no run: block contains an expression interpolation (independent scan)" || fail "an expression interpolation sits in a run: block"
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
bad = [(j, s.get("name")) for j, job in doc["jobs"].items() for s in job["steps"] if "${{" in s.get("run", "")]
print(bad); sys.exit(1 if bad else 0)
PY
# the pinned actions exist upstream (anonymous git ls-remote; no credential)
while read -r repo sha; do
    found=no   # anonymous and over the network: retry a transient failure twice, then fail
    for try in 1 2 3; do
        if CLEAN git ls-remote "https://github.com/$repo" > "$TMP/lsr.out" 2>/dev/null && [ -s "$TMP/lsr.out" ]; then
            cut -f1 "$TMP/lsr.out" | grep -q -x "$sha" && found=yes; break
        fi
        sleep 3
    done
    [ "$found" = yes ] && pass "pin exists upstream: $repo@${sha:0:12}" || fail "pin not found upstream (after $try attempt(s)): $repo@$sha"
done < <(grep -E '^\s*(- )?uses:' "$WF" | sed -E 's/^\s*(- )?uses: ([^@]+)@([0-9a-f]{40}).*/\2 \3/' | sort -u)

# ---------------------------------------------------------------------------------------------------------------------
section "AC10 -- CONTRIBUTING.md and README.md"
SENT='This creates the namespace `X:` permanently bound to your GitHub account (id N). Namespaces are never reassigned.'
grep -F -q -- "$SENT" "$TMP/head/CONTRIBUTING.md" && pass "CONTRIBUTING.md carries the ADR-0058 section 3 sentence verbatim" || fail "ADR-0058 section 3 sentence missing or altered"
grep -F -q '`X` is your namespace' "$TMP/head/CONTRIBUTING.md" && grep -F -q '`N` is your numeric GitHub account id' "$TMP/head/CONTRIBUTING.md" && pass "the placeholders X and N are explained" || fail "placeholders not explained"
grep -q 'never reassigned' "$TMP/head/CONTRIBUTING.md" && pass "CONTRIBUTING.md says 'never reassigned'" || fail "'never reassigned' missing"
grep -q -E 'CONTRIBUTING\.md[^.]*will' "$TMP/head/README.md" && fail "README.md still says CONTRIBUTING will document the flow" || pass "README.md no longer says CONTRIBUTING 'will' exist"
grep -q 'CONTRIBUTING.md' "$TMP/head/README.md" && pass "README.md links CONTRIBUTING.md" || fail "README.md does not mention CONTRIBUTING.md"
# control: a README that still says 'will' must fail the same check
printf 'CONTRIBUTING.md will document the flow\n' | grep -q -E 'CONTRIBUTING\.md[^.]*will' && pass "AC10 control: the old README wording is detected" || fail "AC10 control: the old wording is not detected"

# ---------------------------------------------------------------------------------------------------------------------
section "AC12 -- live guards on HEAD: the whole registry suite, then every closed verify script, one at a time"
others_running() { ps -eo args | grep -E 'docs/tasks/[^ ]*-verify\.sh' | grep -v grep | grep -v '039b-verify\.sh' | grep -q .; }
wait_quiet() {
    local waited=0
    while others_running; do
        [ "$waited" -ge 21600 ] && return 1
        sleep 10; waited=$((waited + 10))
    done
    return 0
}
wait_quiet && pass "no other *-verify.sh is running" || fail "another *-verify.sh kept running for six hours"
( cd "$TMP/head" && CLEAN python3 -I -B -m unittest discover -s tests/registry > "$TMP/all.out" 2>&1 ); rc=$?
[ "$rc" = 0 ] && pass "full tests/registry suite: $(grep -E '^Ran ' "$TMP/all.out")" || { fail "full tests/registry suite red"; tail -8 "$TMP/all.out"; }
if [ -d "$NM/ajv" ] && command -v node >/dev/null 2>&1; then
    mkdir -p "$TMP/head/tools/dev" && cp -a "$NM" "$TMP/head/tools/dev/node_modules"
    for f in $(cd "$TMP/head" && ls docs/tasks/*-verify.sh | sort); do
        case "$f" in *039a-verify.sh|*039b-verify.sh) continue ;; esac
        wait_quiet || { fail "$f: another verify script kept running"; continue; }
        ( cd "$TMP/head" && env -u WOM_NODE_MODULES -u NODE_MODULES_DIR bash "$f" > "$TMP/v.out" 2>&1 ); rc=$?
        if [ "$rc" = 0 ]; then pass "$(basename "$f") exits 0 on HEAD"; else fail "$(basename "$f") exit $rc on HEAD: $(grep -m3 '^FAIL' "$TMP/v.out" | tr '\n' ' ')"; fi
    done
else
    fail "AC12 prerequisite: node and a node_modules directory with ajv are needed for the closed scripts (npm ci --prefix tools/dev, or pass NODE_MODULES_DIR)"
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" = 0 ]; then echo "ALL CHECKS PASSED"; else echo "$FAILURES CHECK(S) FAILED"; fi
exit "$FAILURES"
