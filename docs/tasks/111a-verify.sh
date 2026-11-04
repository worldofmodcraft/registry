#!/usr/bin/env bash
#
# 111a-verify.sh -- the runnable verification artefact for task 111a (the measuring sweep driver; MANAGER.md Section 2c).
#
# Demonstrates acceptance criteria 1-6 of docs/tasks/111a-sweep-measure.md for tools/dev/sweep.py and tests/registry/test_sweep.py.
#
# Usage:  docs/tasks/111a-verify.sh [--mutate]      (any cwd inside the repository)
#   (no flag)  AC1 stubs (green/red/runner, exit 1; all green exit 0), AC2 failure modes, AC3 --list on the real tree,
#              AC4 source unchanged / no __pycache__, AC6 time bound and own-change scope (pinned SHAs).
#   --mutate   AC5: three mutations of sweep.py, each must redden its named test; the restore must be green.
# Everything runs on the COMMITTED HEAD in a temporary clone; the caller's worktree is never modified. The real closed verify
# scripts and a whole sweep are NEVER run (stubs and --only only). No network, no credentials, no quiet-wait in this script
# (it tolerates being run from 039a-verify.sh). Own-change checks read the pinned BASE/FINAL, never HEAD; live guards read HEAD.
# To satisfy AC6's "fresh clone" clause run this script from a fresh `git clone` of the pushed branch.
# Exit code: the number of failed checks. Requires: git, python3, bash.

set -u
set -o pipefail

BASE=428df021bf89738768bc2a13f82461479318ab35   # registry origin/main (task 008b-2 merged) the branch was cut from
FINAL=dbf228bcbf68045f4ab149c9c24ec67ebd9eaaa6  # last commit that changes sweep.py or its tests (later commits: this script and the log only)

MUTATE=0
for a in "$@"; do
    case "$a" in
        --mutate) MUTATE=1 ;;
        *) printf 'usage: %s [--mutate]\n' "$0" >&2; exit 99 ;;
    esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }
TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT
G() { git -C "$ROOT" "$@"; }
START=$SECONDS
HEADREV="$(G rev-parse HEAD)" || exit 99
SCOPE='^(tools/dev/sweep\.py|tests/registry/test_sweep\.py|docs/tasks/111a-sweep-measure\.md|docs/tasks/111a-verify\.sh)$'

new_clone() { git clone -q --no-hardlinks "$ROOT" "$1" && git -C "$1" checkout -q --detach "$HEADREV"; }
run_tests() {   # run_tests CLONE OUTFILE : the sweep test file only, python3 -I -B, from the clone
    ( cd "$1" && env -i PATH="$PATH" HOME="$TMP" LANG=C.UTF-8 python3 -I -B -m unittest discover -s tests/registry -p test_sweep.py -v ) > "$2" 2>&1
}
test_ok() {   # test_ok OUTFILE CLASS.TEST : the named test reported ok
    grep -Eq "^test_${2#*.} \(test_sweep\.${2%%.*}\.test_${2#*.}\) \.\.\. ok$" "$1"
}
scope_bad() { grep -Ev "$SCOPE"; }   # reads file names on stdin, prints those outside the scope

new_clone "$TMP/head" || { fail "cannot clone HEAD"; exit "$FAILURES"; }

if [ "$MUTATE" = 0 ]; then
# ---------------------------------------------------------------------------------------------------------------------
section "AC1/AC2/AC4 -- the sweep test file on the committed HEAD (temporary clone, env -i, python3 -I -B)"
before="$(git -C "$TMP/head" status --porcelain)"
run_tests "$TMP/head" "$TMP/t.out"; rc=$?
tail -4 "$TMP/t.out" | sed 's/^/        /'
[ "$rc" = 0 ] && pass "test_sweep.py green: $(grep -E '^Ran ' "$TMP/t.out")" || fail "test_sweep.py red (exit $rc)"
check() { test_ok "$TMP/t.out" "$2" && pass "$1 [$2]" || fail "$1 [$2] not ok"; }
check "AC1 stubs: exit/seconds>0/nested_starts per script, driver exit 1 (red stub)" MixedSweep.exit_seconds_and_nested
check "AC1 a red script does not stop the sweep" MixedSweep.red_script_does_not_stop_the_sweep
check "AC1 positive control: all green gives exit 0 and the nested count" AllGreen.positive_control_exit_zero
check "AC1 039a skipped with reason, 039b gets --no-closed" SpecialScripts.039a_skipped_with_reason_and_039b_gets_no_closed
check "AC1 nested counting works; cleared environment is declared, not counted" ClearedEnvironment.child_of_cleared_environment_is_not_counted
check "AC1 quiet-wait excludes own tree, an unrelated run counts" QuietWait.tree_exclusion
check "AC2 empty script list exits 2" FailureModes.empty_script_list_exits_2
check "AC2 missing ajv exits 2" FailureModes.missing_ajv_exits_2
check "AC2 --out inside the repository exits 2" FailureModes.out_inside_repository_exits_2
check "AC2 broken search (unknown --only name) exits 2" FailureModes.unknown_only_name_exits_2
check "AC2 broken search (garbled ps table) is an error" QuietWait.garbled_table_is_an_error
check "Fix1 report carries planned/complete; finished set only when complete" ReportCompleteness.complete_report
check "Fix1 a sweep killed mid-way leaves complete=false, finished=null" ReportCompleteness.partial_report_is_marked_incomplete
check "Fix2 quiet_wait and waited_seconds recorded" ReportCompleteness.complete_report
check "Fix3 scripts get 039a's environment (env unset, node_modules copied)" GateEnvironment.env_unset_and_node_modules_is_a_real_directory
check "Fix4 a dirty clone before the first script exits 2" GateEnvironment.untracked_files_in_the_clone_before_the_first_script_exit_2
check "Fix5 wait loop waits until quiet" WaitLoop.waits_until_quiet
check "Fix5 wait loop timeout" WaitLoop.timeout_returns_false
check "Fix5 timeout records error and null exit" WaitLoop.timeout_records_error_and_null_exit
check "Fix5 no-wait never calls the waiter" WaitLoop.no_wait_never_calls_the_waiter
check "Fix5 waiter is used when waiting is on" WaitLoop.wait_is_used_when_not_no_wait
check "AC4 stub source checkout unchanged, no __pycache__" MixedSweep.source_checkout_unchanged_and_no_pycache
[ "$(git -C "$TMP/head" status --porcelain)" = "$before" ] && pass "AC4 the real clone is unchanged by the test run (git status --porcelain: '${before}')" || fail "AC4 the test run changed the clone"
n="$(find "$TMP/head" -name __pycache__ | wc -l)"
[ "$n" = 0 ] && pass "AC4 no __pycache__ left in the clone" || fail "AC4 $n __pycache__ directories left"

# ---------------------------------------------------------------------------------------------------------------------
section "AC3 -- --list on the real tree (HEAD clone)"
( cd "$TMP/head" && python3 -I -B tools/dev/sweep.py --list ) > "$TMP/list.out" 2> "$TMP/list.err"; rc=$?
want="$(ls "$TMP/head"/docs/tasks/*-verify.sh | wc -l)"
listed="$(grep -c -- '-verify\.sh' "$TMP/list.out")"
[ "$rc" = 0 ] && pass "--list exits 0" || fail "--list exit $rc: $(head -2 "$TMP/list.err")"
[ "$want" -gt 0 ] && [ "$listed" = "$want" ] && pass "--list names all $want docs/tasks/*-verify.sh (glob count $want, non-zero)" || fail "--list names $listed, glob has $want"
grep -qx '039a-verify.sh  \[skipped: it is the sweep\]' "$TMP/list.out" && pass "039a marked skipped" || fail "039a not marked skipped"
grep -qx '039b-verify.sh  args: --no-closed' "$TMP/list.out" && pass "039b shows --no-closed" || fail "039b --no-closed not shown"
tail -1 "$TMP/list.out" | sed 's/^/        /'

# ---------------------------------------------------------------------------------------------------------------------
section "AC6 -- own change at the pinned SHAs (BASE..FINAL touches only the declared scope)"
if G cat-file -e "$BASE^{commit}" 2>/dev/null && G cat-file -e "$FINAL^{commit}" 2>/dev/null && G merge-base --is-ancestor "$BASE" "$FINAL"; then
    pass "pins BASE and FINAL exist and BASE is an ancestor of FINAL"
    files="$(G diff --name-only "$BASE" "$FINAL")" || files=""
    [ -n "$files" ] && pass "BASE..FINAL changes $(printf '%s\n' "$files" | wc -l) file(s)" || fail "BASE..FINAL is empty or unreadable"
    bad="$(printf '%s\n' "$files" | scope_bad)"
    [ -z "$bad" ] && pass "every changed file is in scope (no existing verify script, workflow, tool or test touched)" || fail "out of scope: $(printf '%s' "$bad" | tr '\n' ' ')"
    ctl="$(printf '%s\n' "$files" docs/tasks/062-verify.sh | scope_bad)"
    [ "$ctl" = "docs/tasks/062-verify.sh" ] && pass "control: an edit of 062-verify.sh would be flagged" || fail "control: scope check cannot fail"
else
    fail "pins BASE/FINAL unreachable (BASE=$BASE FINAL=$FINAL)"
fi
G merge-base --is-ancestor "$FINAL" "$HEADREV" && pass "FINAL is an ancestor of HEAD" || fail "FINAL is not an ancestor of HEAD"
[ -z "$(G diff --name-only "$FINAL" "$HEADREV" | scope_bad)" ] && pass "FINAL..HEAD touches only in-scope files" || fail "FINAL..HEAD touches out-of-scope files"
else
# ---------------------------------------------------------------------------------------------------------------------
section "AC5 -- mutations of sweep.py in a temporary clone (each must redden its named test; the restore must be green)"
H="$TMP/helper.py"
cat > "$H" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path).read()
if text.count(old) != 1:
    print("search found %d matches (a broken search is a failure): %r" % (text.count(old), old)); sys.exit(2)
open(path, "w").write(text.replace(old, new))
PY
mutation() {   # mutation LABEL OLD NEW TESTNAME
    local label="$1" old="$2" new="$3" want="$4" rc
    python3 -I -B "$H" "$TMP/head/tools/dev/sweep.py" "$old" "$new" || { fail "$label: the mutation did not apply"; return; }
    run_tests "$TMP/head" "$TMP/m.out"; rc=$?
    if [ "$rc" != 0 ] && grep -Eq "^(FAIL|ERROR): test_${want}\b" "$TMP/m.out"; then
        pass "$label turns red: exit $rc, failing: $(grep -E '^(FAIL|ERROR):' "$TMP/m.out" | sed -E 's/ \(.*//' | tr '\n' ' ')"
    else
        fail "$label stayed green or missed test_$want (exit $rc)"
    fi
    git -C "$TMP/head" checkout -q -- tools/dev/sweep.py
}
mutation "AC5a nested counting removed (BASH_ENV not exported)" '    env["BASH_ENV"] = str(work / "bash_env.sh")
' '' exit_seconds_and_nested
mutation "AC5b exit code ignored" 'rec["exit"] = proc.returncode' 'rec["exit"] = 0' exit_seconds_and_nested
mutation "AC5c --no-closed argument dropped" 'NO_CLOSED_ARGS = ["--no-closed"]' 'NO_CLOSED_ARGS = []' 039a_skipped_with_reason_and_039b_gets_no_closed
mutation "Fix5 quiet-wait guard removed (waiter always called)" '    if not no_wait:
        quiet, rec' '    if True:
        quiet, rec' no_wait_never_calls_the_waiter
run_tests "$TMP/head" "$TMP/r.out"; rc=$?
[ "$rc" = 0 ] && pass "restore: unmutated clone is green again ($(grep -E '^Ran ' "$TMP/r.out"))" || fail "restore: unmutated clone is red"
fi

printf '\n== RESULT ==\n'
elapsed=$((SECONDS - START))
[ "$elapsed" -lt 120 ] && pass "AC6 finished in ${elapsed}s (< 120s; no real closed script was run)" || fail "AC6 took ${elapsed}s (>= 120s)"
[ "$FAILURES" = 0 ] && printf 'ALL PASS\n' || printf '%d FAILED\n' "$FAILURES"
exit "$FAILURES"
