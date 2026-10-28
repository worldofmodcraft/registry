#!/usr/bin/env bash
#
# 039a-verify.sh -- the runnable verification artefact for task 039a (the registry CI composer; MANAGER.md Section 2c).
#
# Task 039a (split from 039 by choice C23): tools/registry/ci_gate.py + config/r11-identity.json + tests/registry/test_ci_gate.py
# + tests/registry/fixtures/ci/**. Demonstrates acceptance criteria AC1-AC6 (incl. AC2a), AC8, AC9, AC11 and AC12 of
# docs/tasks/039-registry-ci-workflow.md. AC7 and AC10 (workflow, CONTRIBUTING/README) belong to 039b.
#
# Usage:  docs/tasks/039a-verify.sh [NODE_MODULES_DIR]      (any cwd inside the repository)
#   NODE_MODULES_DIR (or env WOM_NODE_MODULES, else <repo root>/tools/dev/node_modules; install with npm ci --prefix tools/dev)
#   is only needed by the closed verify scripts of AC12 (they use ajv).
# Own-change checks use the EXPLICIT SHAs below (BASE, RED, FINAL, TIP), never HEAD or origin/main. Behaviour checks run on the COMMITTED HEAD in a
# temporary clone under `env -i`; the caller's worktree is not modified. The composer's own tests use throwaway git repos in
# mktemp dirs and recorded payloads: no credential, no gh, no curl, no live PR. Network: only 066-verify.sh (anonymous npm ci).
# AC12 runs the whole registry suite and every closed verify script ONE AT A TIME, and waits while another *-verify.sh runs.
# To satisfy AC12's "fresh clone" clause run this script from a fresh `git clone` of the pushed branch.
# Exit code: the number of failed checks. Requires: git, python3, node (AC12).
#
# Task 089b (closed-verify sweep, part B; findings 10, 11, 12 and S4):
#  - The checks of 039a's OWN change read the pinned FINAL, never HEAD: config/r11-identity.json must be the null configuration AT FINAL
#    (so Ludwig configuring R11 later cannot redden this script), and the per-class test counts are taken from tests/registry/test_ci_gate.py
#    AT FINAL (every test the file has at FINAL must be ok at HEAD; a test ADDED to a class later is allowed, a test REMOVED or RENAMED is a FAIL).
#    An unreadable FINAL is a FAIL for each of these checks. The old unit test AC9ProductionR11Unconfigured (it read the live config) was
#    deleted from test_ci_gate.py and its assertion lives here, at the pin ("AC9 config/r11-identity.json at FINAL").
#  - S4 (the double run): the AC12 sweep below runs every other *-verify.sh, 039b-verify.sh included, ONCE, but with --no-closed. 039b's own
#    AC12 sweeps the same scripts again (twice the hours) and its quiet-wait counts a parent 039a-verify.sh as "another script running", so
#    run from here without the flag it would wait for 039a to finish. With --no-closed 039b runs all its own checks and prints
#    "AC12 NOT RUN (--no-closed)": that sweep is this loop. 039b-verify.sh run standalone still sweeps by itself.

set -u
set -o pipefail

BASE=4356583fb2360592a680f40bee396f9f23df35a4   # registry origin/main (task 075 merged) the branch was cut from
RED=88c97ac5e0f77e429e4905198612ce82b15db47b    # tests + fixtures only; ci_gate.py does not exist yet
FINAL=ceb0458346ecf9f68454d1e3f2f1dafc1ea301c4  # last commit that changes the composer, config or tests (later commits: log and this script only)
TIP=999b2b798adee2ce02271ca82e104a3909e45684    # last commit of the branch before the one that pinned TIP: BASE..TIP is the scope-checked range, so a later
                    # merge with registry main (other tasks' files in BASE..HEAD) cannot redden it. The one commit after TIP changes
                    # only this script (in scope), which no check can pin without a cycle.

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
CLEAN() { env -i PATH="$PATH" HOME="$(mktemp -d "$TMP/home.XXXXXX")" LANG=C.UTF-8 "$@"; }

SCOPE='^(tools/registry/ci_gate\.py|config/r11-identity\.json|tests/registry/test_ci_gate\.py|tests/registry/fixtures/ci/.+|docs/tasks/039-registry-ci-workflow\.md|docs/tasks/039a-verify\.sh)$'

# ---------------------------------------------------------------------------------------------------------------------
own_change_checks() {  # own_change_checks FINALREV : prints PASS/FAIL lines, returns the number of failures it found
    local final="$1" n=0 s
    for s in "$BASE" "$RED" "$final" "$TIP"; do
        G cat-file -e "$s^{commit}" 2>/dev/null && pass "pin $s exists" || { fail "pin $s does not exist"; n=$((n + 1)); }
    done
    G merge-base --is-ancestor "$BASE" "$RED" 2>/dev/null && pass "BASE is an ancestor of the red commit" || { fail "BASE is not an ancestor of the red commit"; n=$((n + 1)); }
    G merge-base --is-ancestor "$RED" "$final" 2>/dev/null && pass "the red commit is an ancestor of FINAL (red first)" || { fail "the red commit is not an ancestor of FINAL"; n=$((n + 1)); }
    G merge-base --is-ancestor "$final" "$TIP" 2>/dev/null && pass "FINAL is an ancestor of TIP" || { fail "FINAL is not an ancestor of TIP"; n=$((n + 1)); }
    if G cat-file -e "$RED:tools/registry/ci_gate.py" 2>/dev/null; then fail "ci_gate.py already exists at the red commit"; n=$((n + 1)); else pass "ci_gate.py does not exist at the red commit"; fi
    if G cat-file -e "$final:tools/registry/ci_gate.py" 2>/dev/null; then pass "ci_gate.py exists at FINAL"; else fail "ci_gate.py does not exist at FINAL"; n=$((n + 1)); fi
    local files bad
    files="$(G diff --name-only "$BASE" "$final")"
    bad="$(printf '%s\n' "$files" | grep -v -E "$SCOPE")"
    [ -n "$files" ] && [ -z "$bad" ] && pass "git diff --name-only BASE FINAL is inside the file scope" || { fail "BASE..FINAL touches out-of-scope or no files: ${bad:-<empty diff>}"; n=$((n + 1)); }
    bad="$(G diff --name-only "$BASE" "$TIP" | grep -v -E "$SCOPE")"
    [ -z "$bad" ] && pass "BASE..TIP touches only the declared file scope" || { fail "out-of-scope files in BASE..TIP: $bad"; n=$((n + 1)); }
    G diff --quiet "$final" "$TIP" -- tools/registry config tests/registry contracts 2>/dev/null \
        && pass "no code, config, test or contract byte differs between FINAL and TIP (merged bytes = verified bytes)" || { fail "code files differ between FINAL and TIP"; n=$((n + 1)); }
    bad="$(G diff --name-only "$BASE" "$final" -- tools/registry contracts | grep -v -x 'tools/registry/ci_gate.py')"
    [ -z "$bad" ] && pass "no checker or contract file other than ci_gate.py changed" || { fail "checker/contract files changed: $bad"; n=$((n + 1)); }
    bad="$(G diff --name-only "$BASE" "$RED" | grep -v -E '^(tests/registry/test_ci_gate\.py|tests/registry/fixtures/ci/.+|docs/tasks/039-registry-ci-workflow\.md)$')"
    [ -z "$bad" ] && pass "the red commit holds tests, fixtures and the spec log only" || { fail "red commit touches: $bad"; n=$((n + 1)); }
    # the tests fail at the red commit (every one of them), in a mktemp clone
    local red="$TMP/red.$$.$RANDOM"
    if git clone -q --no-hardlinks "$ROOT" "$red" 2>/dev/null && git -C "$red" checkout -q --detach "$RED" 2>/dev/null; then
        ( cd "$red" && CLEAN python3 -I -B -m unittest discover -s tests/registry -p test_ci_gate.py > "$red.out" 2>&1 ); local rc=$?
        local ran bad_n
        ran="$(sed -n 's/^Ran \([0-9]*\) tests.*/\1/p' "$red.out")"
        bad_n="$(grep '^FAILED (' "$red.out" | grep -o '[0-9][0-9]*' | awk '{s+=$1} END {print s+0}')"
        [ "$rc" != 0 ] && [ -n "$ran" ] && [ "$ran" -gt 0 ] && [ "$ran" = "${bad_n:-x}" ] \
            && pass "at the red commit all $ran composer tests fail" || { fail "at the red commit not every test fails (exit $rc, ran ${ran:-?}, failing ${bad_n:-?})"; n=$((n + 1)); }
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
# control: with FINAL=BASE the same checks must fail (they must be able to fail)
( own_change_checks "$BASE" ) > "$TMP/ac11c.out"; rc=$?
[ "$rc" -gt 0 ] && pass "AC11 control: FINAL=BASE makes $rc own-change check(s) fail" || fail "AC11 control: FINAL=BASE does not fail the own-change checks"

# ---------------------------------------------------------------------------------------------------------------------
section "AC1-AC6, AC2a, AC8, AC9 -- the composer's tests on the COMMITTED HEAD (temporary clone, env -i)"
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
suite = unittest.defaultTestLoader.discover("tests/registry", pattern="test_ci_gate.py")
res = unittest.TextTestRunner(stream=open(os.devnull, "w"), resultclass=R).run(suite)
print("ran", res.testsRun, "failed", len(res.failures) + len(res.errors))
sys.exit(0 if res.wasSuccessful() else 1)
PY
( cd "$TMP/head" && CLEAN python3 -I -B "$TMP/runner.py" > "$TMP/ci.out" 2> "$TMP/ci.err" ); rc=$?
[ "$rc" = 0 ] && pass "tests/registry/test_ci_gate.py: $(grep '^ran ' "$TMP/ci.out")" || { fail "test_ci_gate.py red (exit $rc)"; grep '^BAD' "$TMP/ci.out"; }
# The test names of tests/registry/test_ci_gate.py AT FINAL (one "Class test_name" per line), parsed with ast: a count taken from HEAD would
# redden when a later branch legitimately adds a test (task 089b, finding 12). An unreadable FINAL leaves the file empty: every class_check FAILs.
PINNED_TESTS="$TMP/pinned-tests.txt"
G show "$FINAL:tests/registry/test_ci_gate.py" 2>/dev/null | python3 -I -c '
import ast, sys
for n in ast.parse(sys.stdin.read()).body:
    if isinstance(n, ast.ClassDef):
        for m in n.body:
            if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef)) and m.name.startswith("test"):
                print(n.name, m.name)
' > "$PINNED_TESTS" 2>/dev/null
class_check() {  # class_check CLASS EXPECTED_COUNT LABEL : the class has EXPECTED_COUNT tests at FINAL and every one of them is ok at HEAD
    local pinned ran ok missing
    pinned="$(awk -v c="$1" '$1 == c' "$PINNED_TESTS" | wc -l)"
    ran="$(grep -c -E "^(ok|BAD) $1 " "$TMP/ci.out")"
    ok="$(grep -c -E "^ok $1 " "$TMP/ci.out")"
    missing="$(awk -v c="$1" '$1 == c {print $2}' "$PINNED_TESTS" | while read -r t; do grep -q -x "ok $1 $t" "$TMP/ci.out" || printf '%s ' "$t"; done)"
    if [ "$pinned" != "$2" ] || [ "$2" -le 0 ]; then fail "$3: the test file at FINAL ($FINAL) has $pinned test(s) in $1, expected $2 (unreadable pin or wrong count)"
    elif [ -n "$missing" ]; then fail "$3: pinned test(s) not ok at HEAD: $missing"
    else pass "$3: all $2 tests the file has at FINAL are ok at HEAD (HEAD runs $ran in the class, $ok ok)"; fi
}
named() {  # named TEST LABEL : one specific test ran and is ok
    grep -q -E "^ok [A-Za-z0-9]+ $1$" "$TMP/ci.out" && pass "$2 ($1)" || fail "$2 ($1) did not run green"
}
class_check AC1RegistryTrio 3 "AC1 registry trio"
named test_invalid_schema_owner_id_as_string "AC1a invalid schema (owner.id string) exit 1, rule named in comment"
named test_wrong_account_for_existing_namespace_ids_not_usernames "AC1b wrong account for an existing namespace, login equals the owner's name: R3"
named test_modified_version_object_by_its_own_owner "AC1c modified version object: append-only rule 1"
class_check AC2PositiveControls 7 "AC2 positive controls"
named test_first_publish_of_alice_demo "AC2 first publish: ADR-0058 section 3 sentence byte-exact"
named test_owner_adds_a_version "AC2 owner adds a version"
named test_owner_page_only_pr "AC2 page-only PR"
named test_infra_pr_touching_only_readme "AC2 infra PR touching README.md"
class_check AC2aHostileStrings 8 "AC2a hostile strings"
named test_infra_pr_names_stay_inside_the_fence "AC2a @org/team, backtick and newline names stay inside the fence"
named test_hostile_login_exits_2_and_writes_no_free_text_output "AC2a hostile login: exit 2, strict outputs"
class_check AC3FailClosed 26 "AC3 fail-closed matrix"
named test_precedence_exit_2_beats_a_rejection "AC3 precedence: a checker exit 2 beats another's rejection"
named test_a_checker_over_its_timeout "AC3 checker timeout"
named test_any_exception_in_main_exits_2 "AC3 any exception in main exits 2"
named test_empty_diff_is_a_rejection_and_no_checker_runs "AC3 empty diff exits 1, no checker runs"
named test_stub_checker_exit_3_and_non_json_and_disagreeing_exit "AC3 stub checker exit 3 / non-JSON / disagreeing exit"
named test_no_tools_dir_option_on_the_cli "AC3 no checker-directory option on the CLI"
class_check AC4IdentitySource 2 "AC4 identity source"
class_check AC5MergeBaseReads 6 "AC5 merge-base reads"
named test_membership_statuses "AC5 membership none/302/500 R9, 204 passes, 404 R7"
named test_a_pr_setting_the_config_to_its_own_author_gains_nothing "AC5 a PR setting the R11 config gains nothing"
class_check AC6TreeHandlingAndArgv 17 "AC6 tree handling and argv safety"
named test_flag_named_files_are_unrecognised_paths_never_checker_options "AC6 flag-named files are paths, never options"
named test_flag_named_file_alone_takes_the_infra_route_and_runs_no_checker "AC6 a flag-named file alone takes the infra route"
class_check ClassifyOnlyPrePass 4 "--classify-only pre-pass"
class_check AC8NoNetworkNoEnvNoShell 4 "AC8 no network, no environment, no shell (AST scan + mutations)"
# AC9, moved here from the unit test AC9ProductionR11Unconfigured (task 089b, finding 11; it asserted the same condition on the live file):
#   doc == {"schema_version": "1.0.0", "r11_identity": None}. Read at FINAL: configuring R11 later is Ludwig's decision, not a regression of 039a.
G show "$FINAL:config/r11-identity.json" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d=={"schema_version":"1.0.0","r11_identity":None} else 1)' \
    && pass "AC9 config/r11-identity.json at FINAL $FINAL parses with r11_identity null" || fail "AC9 config/r11-identity.json at FINAL $FINAL is not the null configuration (or the pin is unreadable)"
# AC8, independent of the unit test: the composer source itself
python3 -I - "$TMP/head/tools/registry/ci_gate.py" <<'PY' && pass "AC8 independent scan: no network/env/shell/eval, argv[0] is git or sys.executable" || fail "AC8 independent scan found a violation"
import ast, sys
src = open(sys.argv[1]).read()
bad = []
for n in ast.walk(ast.parse(src)):
    if isinstance(n, ast.Import) and any(a.name.split(".")[0] in {"socket", "urllib", "http", "ssl", "requests"} for a in n.names):
        bad.append("network import")
    if isinstance(n, ast.Attribute) and ast.unparse(n) in {"os.environ", "os.getenv", "os.system", "os.popen"}:
        bad.append(ast.unparse(n))
    if isinstance(n, ast.keyword) and n.arg == "shell":
        bad.append("shell=")
    if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in {"eval", "exec", "__import__"}:
        bad.append(n.func.id)
    if isinstance(n, ast.Call) and ast.unparse(n.func).startswith("subprocess."):
        a0 = ast.unparse(n.args[0].elts[0]) if n.args and isinstance(n.args[0], ast.List) else "?"
        if a0 not in ('"git"', "'git'", "sys.executable"):
            bad.append("argv0 " + a0)
if "tools-dir" in src:
    bad.append("tools-dir")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY

# ---------------------------------------------------------------------------------------------------------------------
section "AC12 -- live guards on HEAD: the whole registry suite, then every closed verify script, one at a time"
others_running() { ps -eo args | grep -E 'docs/tasks/[^ ]*-verify\.sh' | grep -v grep | grep -v '039a-verify\.sh' | grep -q .; }
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
        case "$f" in *039a-verify.sh) continue ;; esac
        wait_quiet || { fail "$f: another verify script kept running"; continue; }
        args=(); note=""
        case "$f" in *039b-verify.sh) args=(--no-closed); note=" (--no-closed: its AC12 sweep is this loop)" ;; esac
        ( cd "$TMP/head" && env -u WOM_NODE_MODULES -u NODE_MODULES_DIR bash "$f" ${args[@]+"${args[@]}"} > "$TMP/v.out" 2>&1 ); rc=$?
        if [ "$rc" = 0 ]; then pass "$(basename "$f") exits 0 on HEAD$note"; else fail "$(basename "$f") exit $rc on HEAD: $(grep -m3 '^FAIL' "$TMP/v.out" | tr '\n' ' ')"; fi
    done
else
    fail "AC12 prerequisite: node and a node_modules directory with ajv are needed for the closed scripts (npm ci --prefix tools/dev, or pass NODE_MODULES_DIR)"
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" = 0 ]; then echo "ALL CHECKS PASSED"; else echo "$FAILURES CHECK(S) FAILED"; fi
exit "$FAILURES"
