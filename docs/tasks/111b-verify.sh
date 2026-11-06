#!/usr/bin/env bash
#
# 111b-verify.sh -- the runnable verification artefact for task 111b (the whole sweep runs each closed script's nested sweep once;
# MANAGER.md Section 2c).
#
# Demonstrates acceptance criteria 1-7 of docs/tasks/111b-sweep-dedup.md for docs/tasks/064-verify.sh, docs/tasks/065-verify.sh,
# the case in docs/tasks/039a-verify.sh, tools/dev/sweep.py and tests/registry/test_sweep.py.
#
# Usage:  docs/tasks/111b-verify.sh [--mutate]      (any cwd inside the repository)
#   (no flag)  RED   the new fixtures fail at the red commit (missing-main break shown failing first), and only they;
#              AC1/3 064 and 065 with and without --no-closed, run as stubbed slices (see below), nested starts counted via BASH_ENV;
#              AC2   standalone unchanged: the diff of 064 and 065 has additions only, all of them around the flag;
#              AC4   --list on the real tree, the sweep gives 064 and 065 the flag, 039a's case does too;
#              AC5   the missing-main fixture (exit 2) and its positive control; AC6/7 scope at pinned SHAs, time bound, no __pycache__;
#              AC8   (scope extension) 111a-verify.sh's own-change range is FINAL..TIP, not FINAL..HEAD: the OLD blob (at BASE) is red on this
#                    head with the out-of-scope FAIL line, the new one is green on it and on a frame with a later out-of-scope commit.
#   --mutate   AC6: six mutations in a temporary clone (flag ignored in 064; in 065; sweep.py not passing it; missing-main check
#              removed; 039a not passing it; 111a-verify.sh's TIP set back to HEAD, run on a frame with a later out-of-scope commit),
#              each must redden its named check; the restore must be green. (111a-verify.sh's own --mutate takes ~77 s and is not run here.)
# How 064 and 065 are exercised WITHOUT running them end to end: the real script text is cut into a PRELUDE (everything before its
# TMP=, including the real argument parsing and the real pins), the lines of the check that runs 057 (AC3.2 / AC2.4), the real
# AC4 section, and the real RESULT tail. That slice runs in a temporary tree whose docs/tasks/*-verify.sh are stubs that do nothing
# (`exit 0`) and whose tests/ directories hold one trivial passing test. A BASH_ENV file, as tools/dev/sweep.py generates, records
# every *-verify.sh start (PID, PPID, $0). No real closed script, no 039a, no sweep, no real 064/065 run, no network, no credential.
# Own-change checks read the pinned BASE/RED/FIX, never HEAD; live guards read HEAD. No quiet-wait here (it tolerates being run from
# 039a-verify.sh, from the sweep driver and from a fresh clone: it uses env -i for its test runs and its own BASH_ENV for the slices).
# To satisfy AC7's "fresh clone" clause run this script from a fresh `git clone` of the pushed branch.
# Exit code: the number of failed checks. Requires: git, python3, bash.

set -u
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1

BASE=ab5fcba6d26436a7c87df191eb85d9323f83052d   # registry origin/main (111a merged, PR #40) the branch was cut from
RED=62fc5bed6568cf25987ddab832308de8ea7c7698    # tests/registry/test_sweep.py only: the new fixtures, no fix
FIX=b19bf12b1d13d16a4e6c5efd0f5a10886889c5cc    # last commit that changes sweep.py, 064, 065 or 039a
FIX2=23d32e7c85012143c808e8c918e44b13cce24960   # the commit that re-pins 111a-verify.sh (FINAL..HEAD -> FINAL..TIP); the TIP of this script: nothing after it is range-checked
                                                # (a FIX2..HEAD check would be the very HEAD read this script's AC8 removes from 111a; later commits: this script and the log only)

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
SCOPE='^(docs/tasks/064-verify\.sh|docs/tasks/065-verify\.sh|docs/tasks/039a-verify\.sh|tools/dev/sweep\.py|tests/registry/test_sweep\.py|docs/tasks/111a-sweep-measure\.md|docs/tasks/111a-verify\.sh|docs/tasks/111b-sweep-dedup\.md|docs/tasks/111b-verify\.sh)$'
scope_bad() { grep -Ev "$SCOPE"; }   # reads file names on stdin, prints those outside the scope

for c in "$BASE" "$RED" "$FIX" "$FIX2"; do
    G cat-file -e "$c^{commit}" 2>/dev/null || { fail "P0 pinned commit $c is not reachable"; exit "$FAILURES"; }
done
NEWTESTS="NoClosedArguments.064_and_065_get_no_closed_and_other_scripts_get_none NoClosedArguments.the_flag_list_is_one_named_constant_and_a_list_of_three ListReal.list_shows_no_closed_for_039b_064_065_only MissingMain.source_cloned_with_branch_has_no_local_main_exit_2 MissingMain.source_on_a_branch_named_trunk_exit_2"
CONTROLS="MissingMain.positive_control_main_exists_so_the_inner_clone_has_origin_main MissingMain.list_does_not_need_main"

new_clone() { git clone -q --no-hardlinks "$ROOT" "$1" && git -C "$1" checkout -q --detach "$2"; }
mkdir -p "$TMP/tt"
run_tests() {   # run_tests CLONE OUTFILE [unittest -k PATTERN] : the sweep test file only, python3 -I -B, from the clone
    ( cd "$1" && env -i PATH="$PATH" HOME="$TMP" TMPDIR="$TMP/tt" LANG=C.UTF-8 python3 -I -B -m unittest discover -s tests/registry -p test_sweep.py -v ${3:+-k "$3"} ) > "$2" 2>&1
}
test_ok() { grep -Eq "^test_${2#*.} \(test_sweep\.${2%%.*}\.test_${2#*.}\) \.\.\. ok$" "$1"; }
test_bad() { grep -Eq "^(FAIL|ERROR): test_${2#*.} \(test_sweep\.${2%%.*}\.test_${2#*.}\)" "$1"; }
case_line() { grep -F 'case "$f" in *039b-verify.sh)' "$1"; }   # the one case line of the verify loop
case_args() {   # case_args FILE NAME : the args array the file's case line gives to docs/tasks/NAME-verify.sh
    local line; line="$(case_line "$1")"
    [ "$(printf '%s\n' "$line" | grep -c .)" = 1 ] || { echo "ERR"; return; }
    env F="docs/tasks/$2-verify.sh" CL="$line" bash -c 'f="$F"; args=(); note=""; eval "$CL"; echo "${args[*]-}"'
}

run_111a() {   # run_111a FRAME OUTFILE : the FRAME's own docs/tasks/111a-verify.sh, default mode; sets V_RC
    bash "$1/docs/tasks/111a-verify.sh" > "$2" 2>&1; V_RC=$?
}
make_later() {   # make_later DIR : a frame = HEAD plus one later commit that touches an out-of-scope file (a later task's file)
    new_clone "$1" "$HEADREV" && printf 'a later task\n' > "$1/docs/tasks/999-later-task.txt" && git -C "$1" add docs/tasks/999-later-task.txt \
        && git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m "a later task touches an out-of-scope file"
}

# ---------------------------------------------------------------------------------------------------------------------
# The slice harness. slice KIND SRCFILE OUTSCRIPT : cut the real script text SRCFILE (064 or 065) into the stubbed slice described above.
H="$TMP/slicer.py"
cat > "$H" <<'PY'
import sys
kind, src, dst = sys.argv[1:4]
L = open(src, encoding="utf-8").read().split("\n")
def one(pred, what):
    hits = [i for i, l in enumerate(L) if pred(l)]
    if len(hits) != 1:
        print("slicer: %s found %d times in %s (a broken search is a failure)" % (what, len(hits), src)); sys.exit(2)
    return hits[0]
tmp = one(lambda l: l == 'TMP="$(mktemp -d)" || exit 99', 'the TMP= line')
prelude = L[:tmp]
if kind == "064":
    k57 = one(lambda l: "bash docs/tasks/057-verify.sh" in l, "the direct 057 run")
    a4 = one(lambda l: l.startswith('section "AC4 -- no other suite moves'), "section AC4")
    a5 = one(lambda l: l.startswith('section "AC5 -- 034 C3.3'), "section AC5")
    mid = L[k57:k57 + 2] + L[a4:a5]
elif kind == "065":
    k57 = one(lambda l: "bash docs/tasks/057-verify.sh" in l, "the direct 057 run")
    a4 = one(lambda l: l.startswith('section "AC4 -- the repository'), "section AC4")
    a5 = one(lambda l: l.startswith('section "AC5 -- the JSON examples'), "section AC5")
    if L[a4 - 1] != 'if [ "$MUTATE" = 0 ]; then':
        print("slicer: the line before section AC4 is not the MUTATE guard: %r" % L[a4 - 1]); sys.exit(2)
    mid = L[k57:k57 + 2] + L[a4 - 1:a5]
else:
    print("slicer: unknown kind"); sys.exit(2)
res = [i for i, l in enumerate(L) if l == "printf '\\n== RESULT ==\\n'"]
if not res:
    print("slicer: no final RESULT line in %s" % src); sys.exit(2)
tail = L[res[-1]:]
out = prelude + ['TMP="$WOM_H_TMP"', 'section "slice of %s-verify.sh (stubbed)"' % kind] + mid + tail
open(dst, "w", encoding="utf-8").write("\n".join(out))
PY

# make_tree DIR : the stub tree: every docs/tasks/*-verify.sh name of HEAD as an `exit 0` stub; tests/* with one passing test; a git repo (the real script finds its ROOT)
make_tree() {
    mkdir -p "$1/docs/tasks" "$1/tools/dev" && git init -q "$1" || return 1
    local n d
    for n in $(G ls-tree --name-only "$HEADREV" docs/tasks/ | grep -E '^docs/tasks/[0-9]+[a-z0-9]*-verify\.sh$'); do
        printf '#!/usr/bin/env bash\nexit 0\n' > "$1/docs/tasks/$(basename "$n")"
    done
    for d in contracts registry validation pipeline; do
        mkdir -p "$1/tests/$d"
        printf 'import unittest\nclass T(unittest.TestCase):\n    def test_ok(self):\n        pass\n' > "$1/tests/$d/test_trivial.py"
    done
}
printf 'case "$0" in *-verify.sh) printf '"'"'%%s %%s %%s\\n'"'"' "$$" "$PPID" "$0" >> "$WOM_SWEEP_LOG" ;; esac\n' > "$TMP/benv.sh"

# run_slice KIND SRCFILE FLAG(yes|no) TAG : runs the slice; sets S_RC, S_OUT (file), S_NAMES (sorted basenames of every *-verify.sh started underneath)
run_slice() {
    local kind="$1" src="$2" flag="$3" tag="$4" w="$TMP/w-$4" args=()
    rm -rf "$w"; mkdir -p "$w"
    make_tree "$w/head" || { S_RC=97; return; }
    python3 -I -B "$H" "$kind" "$src" "$w/head/docs/tasks/slice$kind.sh" > "$w/slicer.out" 2>&1 || { S_RC=98; S_OUT="$w/slicer.out"; return; }
    [ "$flag" = yes ] && args=(--no-closed)
    : > "$w/nested.log"
    ( cd "$w/head" && env BASH_ENV="$TMP/benv.sh" WOM_SWEEP_LOG="$w/nested.log" WOM_H_TMP="$w" WOM_NODE_MODULES=/nonexistent/nm \
        bash "docs/tasks/slice$kind.sh" ${args[@]+"${args[@]}"} ) > "$w/out" 2>&1
    S_RC=$?; S_OUT="$w/out"
    S_NAMES="$(while read -r _pid _ppid cmd; do basename "$cmd"; done < "$w/nested.log" | sort)"
}

if [ "$MUTATE" = 0 ]; then
# ---------------------------------------------------------------------------------------------------------------------
section "RED -- the new fixtures fail at the red commit (tests only, on the unfixed sweep.py), and only they"
G merge-base --is-ancestor "$BASE" "$RED" && G merge-base --is-ancestor "$RED" "$FIX" && G merge-base --is-ancestor "$FIX" "$HEADREV" \
    && pass "RED.1 BASE < RED < FIX are ancestors of HEAD in that order" || fail "RED.1 commit order BASE < RED < FIX < HEAD does not hold"
[ "$(G diff --name-only "$RED~1" "$RED")" = "tests/registry/test_sweep.py" ] && pass "RED.2 the red commit changes only tests/registry/test_sweep.py (no fix)" || fail "RED.2 red commit touches: $(G diff --name-only "$RED~1" "$RED" | tr '\n' ' ')"
[ "$(G rev-parse "$RED~2")" = "$BASE" ] && pass "RED.3 the red commit sits two commits (spec copy, then it) above BASE" || fail "RED.3 the red commit is not BASE+2"
new_clone "$TMP/red" "$RED" || { fail "cannot clone RED"; exit "$FAILURES"; }
run_tests "$TMP/red" "$TMP/red.out"; rc=$?
[ "$rc" != 0 ] && pass "RED.4 test_sweep.py at the red commit exits $rc: $(grep -E '^(Ran |FAILED)' "$TMP/red.out" | tr '\n' ' ')" || fail "RED.4 test_sweep.py is green at the red commit (the fixtures prove nothing)"
for t in $NEWTESTS; do
    test_bad "$TMP/red.out" "$t" && pass "RED.5 red at the red commit: $t" || fail "RED.5 not red at the red commit: $t"
done
for t in $CONTROLS; do
    test_ok "$TMP/red.out" "$t" && pass "RED.6 control green at the red commit (the failing ones fail for a reason): $t" || fail "RED.6 control not green at the red commit: $t"
done
nbad="$(grep -cE '^(FAIL|ERROR): ' "$TMP/red.out")"
[ "$nbad" = 5 ] && pass "RED.7 exactly 5 tests are red at the red commit (every older test still green)" || fail "RED.7 $nbad tests red at the red commit (expected exactly the 5 new ones)"
grep -E '^(FAIL|ERROR): ' "$TMP/red.out" | sed 's/^/        red: /'

# ---------------------------------------------------------------------------------------------------------------------
section "AC5 + live guard -- the sweep test file on the committed HEAD (temporary clone, env -i, python3 -I -B)"
new_clone "$TMP/head" "$HEADREV" || { fail "cannot clone HEAD"; exit "$FAILURES"; }
run_tests "$TMP/head" "$TMP/t.out"; rc=$?
tail -4 "$TMP/t.out" | sed 's/^/        /'
[ "$rc" = 0 ] && pass "test_sweep.py green at HEAD: $(grep -E '^Ran ' "$TMP/t.out")" || fail "test_sweep.py red at HEAD (exit $rc)"
for t in $NEWTESTS $CONTROLS; do
    test_ok "$TMP/t.out" "$t" && pass "green at HEAD: $t" || fail "not ok at HEAD: $t"
done
test_ok "$TMP/t.out" NoClosedArguments.064_and_065_get_no_closed_and_other_scripts_get_none && pass "AC4 the driver gives 039b, 064 and 065 --no-closed and 069/070 nothing (stub scripts)" || fail "AC4 driver arguments"
test_ok "$TMP/t.out" MissingMain.source_cloned_with_branch_has_no_local_main_exit_2 && pass "AC5 a source clone made with --branch (no local main) exits 2, no script runs, no report, no inner clone" || fail "AC5 missing-main exit 2"
test_ok "$TMP/t.out" MissingMain.positive_control_main_exists_so_the_inner_clone_has_origin_main && pass "AC5 positive control: with a local main the inner clone has origin/main and the sweep exits 0" || fail "AC5 positive control"
[ "$(find "$TMP/tt" -name 'wom-sweep.*' | wc -l)" = 0 ] && pass "the test run leaves no wom-sweep.* in the TMPDIR it sets" || fail "wom-sweep.* directories left"
[ "$(find "$TMP/head" -name __pycache__ | wc -l)" = 0 ] && pass "AC7 no __pycache__ in the clone" || fail "AC7 __pycache__ left in the clone"

# ---------------------------------------------------------------------------------------------------------------------
section "AC1 + AC3 -- 064 and 065 at HEAD, stubbed slices: with --no-closed only 057 starts; without it the closed scripts start; labels"
for kind in 064 065; do
    SRC="$TMP/head/docs/tasks/$kind-verify.sh"
    run_slice "$kind" "$SRC" yes "$kind-flag"
    [ "$S_RC" = 0 ] && pass "AC1 $kind --no-closed: the slice exits 0 (all remaining checks pass on the stub tree)" || { fail "AC1 $kind --no-closed: slice exit $S_RC"; sed 's/^/        /' "$S_OUT" | tail -8; }
    [ "$S_NAMES" = "057-verify.sh" ] && pass "AC1 $kind --no-closed: nested starts are exactly {057-verify.sh} (the direct run of its own subject)" || fail "AC1 $kind --no-closed: nested starts: $(printf '%s' "$S_NAMES" | tr '\n' ' ')"
    if [ "$kind" = 064 ]; then
        grep -qx 'AC4.2 NOT RUN (--no-closed)' "$S_OUT" && pass "AC3 064 --no-closed prints 'AC4.2 NOT RUN (--no-closed)'" || fail "AC3 064 NOT RUN line missing"
        grep -qx 'NOTE: AC4.2 NOT RUN (--no-closed); this is not a full pass' "$S_OUT" && pass "AC3 064 --no-closed prints the NOTE 'not a full pass'" || fail "AC3 064 NOTE missing"
    else
        grep -qx 'AC4.2 NOT RUN (--no-closed)' "$S_OUT" && grep -qx 'AC4.3 NOT RUN (--no-closed)' "$S_OUT" && pass "AC3 065 --no-closed prints 'AC4.2 NOT RUN (--no-closed)' and 'AC4.3 NOT RUN (--no-closed)'" || fail "AC3 065 NOT RUN lines missing"
        grep -qx 'NOTE: AC4.2 and AC4.3 NOT RUN (--no-closed); this is not a full pass' "$S_OUT" && pass "AC3 065 --no-closed prints the NOTE 'not a full pass'" || fail "AC3 065 NOTE missing"
    fi
    grep -q 'PASS  AC4.1 unittest discover' "$S_OUT" && pass "AC1 $kind --no-closed: the suites (AC4.1) still run" || fail "AC1 $kind --no-closed: AC4.1 did not run"
    printf '        %s --no-closed nested starts: %s\n' "$kind" "$(printf '%s' "$S_NAMES" | tr '\n' ' ')"
    run_slice "$kind" "$SRC" no "$kind-plain"
    n="$(printf '%s\n' "$S_NAMES" | grep -c .)"
    [ "$S_RC" = 0 ] && pass "AC1 $kind without the flag: the slice exits 0" || fail "AC1 $kind without the flag: slice exit $S_RC"
    [ "$n" -ge 13 ] && pass "AC1 $kind without the flag: $n closed-script starts (>= 13) still happen" || fail "AC1 $kind without the flag: only $n starts"
    for need in 057-verify.sh 070-verify.sh 062-verify.sh 007a-verify.sh; do
        printf '%s\n' "$S_NAMES" | grep -qx "$need" && pass "AC1 $kind without the flag starts $need" || fail "AC1 $kind without the flag does not start $need"
    done
    [ "$kind" = 065 ] && { printf '%s\n' "$S_NAMES" | grep -qx 064-verify.sh && printf '%s\n' "$S_NAMES" | grep -qx 006-verify.sh && pass "AC1 065 without the flag starts 064 and 006" || fail "AC1 065 without the flag does not start 064 and 006"; }
    ! grep -q 'NOT RUN' "$S_OUT" && pass "AC3 $kind without the flag prints no NOT RUN line and no NOTE" || fail "AC3 $kind without the flag prints a NOT RUN line"
    printf '        %s without the flag: %s starts\n' "$kind" "$n"
done

section "AC1 control -- the same slices cut from BASE (no flag support): --no-closed does NOT stop the nested starts"
for kind in 064 065; do
    G show "$BASE:docs/tasks/$kind-verify.sh" > "$TMP/base-$kind.sh" 2>/dev/null
    run_slice "$kind" "$TMP/base-$kind.sh" yes "$kind-base"
    n="$(printf '%s\n' "$S_NAMES" | grep -c .)"
    [ "$n" -ge 13 ] && pass "AC1 control: BASE $kind given --no-closed still starts $n closed scripts (the harness can see the break)" || fail "AC1 control: BASE $kind started only $n (rc $S_RC)"
done

# ---------------------------------------------------------------------------------------------------------------------
section "AC2 -- standalone unchanged: BASE..FIX of 064 and 065 has additions only, all around the flag"
allowed() {   # allowed FILE : reads added lines on stdin, prints those that are neither comments, the flag logic, nor a bare fi
    grep -Ev '^[+]#|NOCLOSED|^[+]fi$|^[+][+][+] '
}
for kind in 064 065; do
    f="docs/tasks/$kind-verify.sh"
    G diff -U0 "$BASE" "$FIX" -- "$f" > "$TMP/$kind.diff"
    ns="$(G diff --numstat "$BASE" "$FIX" -- "$f")"
    added="$(printf '%s' "$ns" | cut -f1)"; deleted="$(printf '%s' "$ns" | cut -f2)"
    [ "$deleted" = 0 ] && [ "$added" -gt 0 ] && pass "AC2 $kind: $added lines added, 0 removed (every BASE line is byte-identical and in place)" || fail "AC2 $kind: numstat $added added / $deleted removed"
    [ -z "$(grep -E '^-' "$TMP/$kind.diff" | grep -Ev '^--- ')" ] && pass "AC2 $kind: the diff has no '-' line at all" || fail "AC2 $kind: the diff has '-' lines"
    stray="$(grep -E '^[+]' "$TMP/$kind.diff" | allowed)"
    [ -z "$stray" ] && pass "AC2 $kind: every added line is a comment, flag logic (NOCLOSED / NOT RUN) or the closing fi" || fail "AC2 $kind: added lines outside the flag: $stray"
    nfi="$(grep -cE '^[+]fi$' "$TMP/$kind.diff")"
    [ "$nfi" = 1 ] && pass "AC2 $kind: exactly one guarded block (one added if-line, one added fi)" || fail "AC2 $kind: $nfi added fi lines"
    [ "$(grep -cE '^[+]if \[ "\$NOCLOSED" = 1 \]; then echo ' "$TMP/$kind.diff")" = 1 ] && pass "AC2 $kind: the guard is 'if NOCLOSED then echo \"ACx NOT RUN (--no-closed)\"; else'" || fail "AC2 $kind: guard line not as specified"
    grep -E '^[+]' "$TMP/$kind.diff" | grep -Ev '^[+]#' | grep -q '057' && fail "AC2 $kind: an added line mentions 057 (its own subject stays unguarded)" || pass "AC2 $kind: nothing about 057 added (its own run is outside the guard)"
done
# the guarded sections, listed from the real HEAD text: which check sections sit between the guard's if and fi
for kind in 064 065; do
    awk '/^if \[ "\$NOCLOSED" = 1 \]; then echo/{on=1} on&&/AC4\.[0-9]/{match($0,/AC4\.[0-9]+/); s=substr($0,RSTART,RLENGTH); seen[s]=1} on&&/^fi$/{on=0} END{for(k in seen) print k}' "$TMP/head/docs/tasks/$kind-verify.sh" | sort | tr '\n' ' ' > "$TMP/guard-$kind.txt"
    printf '        %s guarded check sections (labels inside the guard): %s\n' "$kind" "$(cat "$TMP/guard-$kind.txt")"
done
grep -q 'AC4.2' "$TMP/guard-064.txt" && ! grep -q 'AC4.1' "$TMP/guard-064.txt" && pass "AC2 064 guards AC4.2 (and not AC4.1)" || fail "AC2 064 guard labels: $(cat "$TMP/guard-064.txt")"
grep -q 'AC4.2' "$TMP/guard-065.txt" && grep -q 'AC4.3' "$TMP/guard-065.txt" && ! grep -q 'AC4.1' "$TMP/guard-065.txt" && pass "AC2 065 guards AC4.2 and AC4.3 (and not AC4.1)" || fail "AC2 065 guard labels: $(cat "$TMP/guard-065.txt")"
# control: the checker itself detects a removed or a stray line
printf -- '-removed line\n+stray line\n' > "$TMP/ctl.diff"
[ -n "$(grep -E '^-' "$TMP/ctl.diff")" ] && [ -n "$(grep -E '^[+]' "$TMP/ctl.diff" | allowed)" ] && pass "AC2 control: a removed line and a stray added line are both detected" || fail "AC2 control: the diff checker cannot fail"
# 039a: one line replaced, and it is the case line
G diff -U0 "$BASE" "$FIX" -- docs/tasks/039a-verify.sh > "$TMP/039a.diff"
[ "$(grep -cE '^-[^-]' "$TMP/039a.diff")" = 1 ] && [ "$(grep -cE '^[+][^+]' "$TMP/039a.diff")" = 1 ] && grep -E '^-[^-]' "$TMP/039a.diff" | grep -q 'case "\$f" in \*039b-verify.sh)' && grep -E '^[+][^+]' "$TMP/039a.diff" | grep -q 'case "\$f" in \*039b-verify.sh)' \
    && pass "AC2 039a-verify.sh: exactly one line replaced, and it is the case in the verify loop" || fail "AC2 039a-verify.sh diff is not the one case line"

# ---------------------------------------------------------------------------------------------------------------------
section "AC4 -- --list on the real tree; 039a's case; the driver's constant"
( cd "$TMP/head" && python3 -I -B tools/dev/sweep.py --list ) > "$TMP/list.out" 2> "$TMP/list.err"; rc=$?
[ "$rc" = 0 ] && pass "--list exits 0" || fail "--list exit $rc: $(head -2 "$TMP/list.err")"
for n in 039b 064 065; do
    grep -qx "$n-verify.sh  args: --no-closed" "$TMP/list.out" && pass "AC4 --list shows --no-closed for $n" || fail "AC4 --list does not show --no-closed for $n"
done
[ "$(grep -c 'args:' "$TMP/list.out")" = 3 ] && pass "AC4 --list shows arguments for exactly those three scripts (070, 069 and the rest get none)" || fail "AC4 --list shows arguments for $(grep -c 'args:' "$TMP/list.out") scripts"
tail -1 "$TMP/list.out" | sed 's/^/        /'
for n in 039b 064 065; do
    [ "$(case_args "$TMP/head/docs/tasks/039a-verify.sh" $n)" = "--no-closed" ] && pass "AC4 039a's case gives $n --no-closed" || fail "AC4 039a's case does not give $n --no-closed ($(case_args "$TMP/head/docs/tasks/039a-verify.sh" $n))"
done
for n in 069 070 057 062; do
    [ -z "$(case_args "$TMP/head/docs/tasks/039a-verify.sh" $n)" ] && pass "AC4 039a's case gives $n nothing (positive control: not every script gets the flag)" || fail "AC4 039a's case gives $n an argument"
done

# ---------------------------------------------------------------------------------------------------------------------
section "AC6/7 -- own change at the pinned SHAs (BASE..FIX touches only the declared scope)"
files="$(G diff --name-only "$BASE" "$FIX")"
want="docs/tasks/039a-verify.sh docs/tasks/064-verify.sh docs/tasks/065-verify.sh docs/tasks/111a-sweep-measure.md docs/tasks/111b-sweep-dedup.md tests/registry/test_sweep.py tools/dev/sweep.py"
[ "$(printf '%s\n' "$files" | sort | tr '\n' ' ' | sed 's/ $//')" = "$want" ] && pass "BASE..FIX changes exactly: $want" || fail "BASE..FIX changes: $(printf '%s' "$files" | tr '\n' ' ')"
[ -z "$(printf '%s\n' "$files" | scope_bad)" ] && pass "every file BASE..FIX changes is in the declared scope (no other closed script, 070 and 069 untouched)" || fail "out of scope: $(printf '%s\n' "$files" | scope_bad | tr '\n' ' ')"
ctl="$(printf '%s\n' "$files" docs/tasks/070-verify.sh | scope_bad)"
[ "$ctl" = "docs/tasks/070-verify.sh" ] && pass "control: an edit of 070-verify.sh would be flagged" || fail "control: the scope check cannot fail"
G merge-base --is-ancestor "$FIX" "$FIX2" && G merge-base --is-ancestor "$FIX2" "$HEADREV" && pass "FIX < FIX2 (this script's TIP) are ancestors of HEAD in that order" || fail "FIX < FIX2 < HEAD does not hold"
G diff --name-only "$FIX" "$FIX2" > "$TMP/fix2.files"
[ -z "$(scope_bad < "$TMP/fix2.files")" ] && grep -qx 'docs/tasks/111a-verify.sh' "$TMP/fix2.files" && pass "FIX..FIX2 (fixed range) touches only in-scope files and includes docs/tasks/111a-verify.sh ($(tr '\n' ' ' < "$TMP/fix2.files"))" || fail "FIX..FIX2 changes: $(tr '\n' ' ' < "$TMP/fix2.files")"
[ -z "$(G diff --name-only "$FIX" "$FIX2" | grep 'verify\.sh$' | grep -vE '^docs/tasks/111[ab]-verify\.sh$')" ] && pass "FIX..FIX2 changes no closed verify script except 111a-verify.sh (and this one)" || fail "FIX..FIX2 touches another verify script"
[ "$(G diff --numstat "$FIX" "$FIX2" -- docs/tasks/111a-verify.sh | cut -f1,2)" = "$(printf '8\t1')" ] && pass "111a-verify.sh: 8 lines added, 1 removed (the FINAL..HEAD check line); the live guards (tests, --list, timing) are untouched" || fail "111a-verify.sh FIX..FIX2 numstat: $(G diff --numstat "$FIX" "$FIX2" -- docs/tasks/111a-verify.sh | cut -f1,2 | tr '\t' '/')"
G diff -U0 "$FIX" "$FIX2" -- docs/tasks/111a-verify.sh | grep -E '^-[^-]' | grep -qF 'FINAL..HEAD touches only in-scope files' && pass "the one removed line is the FINAL..HEAD check" || fail "the removed line of 111a-verify.sh is not the FINAL..HEAD check"
[ "$(G diff --numstat "$BASE" "$FIX" -- tests/registry/test_sweep.py | cut -f2)" = 2 ] && pass "no test was removed or weakened: test_sweep.py loses exactly 2 lines (the Stub's git init line and its signature), both replaced" || fail "test_sweep.py BASE..FIX removes $(G diff --numstat "$BASE" "$FIX" -- tests/registry/test_sweep.py | cut -f2) lines"
G diff -U0 "$BASE" "$FIX" -- tests/registry/test_sweep.py | grep -E '^-[^-]' | sed 's/^/        removed: /'

# ---------------------------------------------------------------------------------------------------------------------
section "AC8 -- 111a-verify.sh reads FINAL..TIP: the OLD blob is red on this head, the new one is green on it and after a later out-of-scope commit"
new_clone "$TMP/a-old" "$HEADREV" && G show "$BASE:docs/tasks/111a-verify.sh" > "$TMP/a-old/docs/tasks/111a-verify.sh" || fail "AC8 cannot build the OLD-blob frame"
run_111a "$TMP/a-old" "$TMP/a-old.out"
grep -E '^FAIL' "$TMP/a-old.out" | sed 's/^/        old 111a-verify.sh: /'
[ "$V_RC" = 1 ] && [ "$(grep -c '^FAIL' "$TMP/a-old.out")" = 1 ] && grep -qx 'FAIL  FINAL..HEAD touches out-of-scope files' "$TMP/a-old.out" \
    && pass "AC8 red first: the OLD 111a-verify.sh (blob at BASE) on this head exits 1 with exactly one FAIL, 'FINAL..HEAD touches out-of-scope files'" || fail "AC8 the OLD 111a-verify.sh on this head: exit $V_RC, FAIL lines: $(grep '^FAIL' "$TMP/a-old.out" | tr '\n' '|')"
new_clone "$TMP/a-new" "$HEADREV" || fail "AC8 cannot clone HEAD"
run_111a "$TMP/a-new" "$TMP/a-new.out"
tail -2 "$TMP/a-new.out" | sed 's/^/        new 111a-verify.sh: /'
[ "$V_RC" = 0 ] && grep -qx 'ALL PASS' "$TMP/a-new.out" && ! grep -q '^FAIL' "$TMP/a-new.out" && pass "AC8 green: the new 111a-verify.sh on the same head exits 0, ALL PASS" || fail "AC8 the new 111a-verify.sh on this head: exit $V_RC, FAIL lines: $(grep '^FAIL' "$TMP/a-new.out" | tr '\n' '|')"
grep -qx 'PASS  FINAL..TIP touches only in-scope files' "$TMP/a-new.out" && grep -q '^PASS  TIP is reachable' "$TMP/a-new.out" && pass "AC8 the new run prints the FINAL..TIP check and the TIP ancestry check" || fail "AC8 the new run lacks the FINAL..TIP or the TIP ancestry line"
make_later "$TMP/a-later" || fail "AC8 cannot build the later-commit frame"
run_111a "$TMP/a-later" "$TMP/a-later.out"
[ "$V_RC" = 0 ] && grep -qx 'ALL PASS' "$TMP/a-later.out" && pass "AC8 the new 111a-verify.sh stays green on a frame where a later commit touches an out-of-scope file (TIP is fixed)" || fail "AC8 the new 111a-verify.sh on the later-commit frame: exit $V_RC, FAIL lines: $(grep '^FAIL' "$TMP/a-later.out" | tr '\n' '|')"
G show "$BASE:docs/tasks/111a-verify.sh" > "$TMP/a-later/docs/tasks/111a-verify.sh"
run_111a "$TMP/a-later" "$TMP/a-later-old.out"
[ "$V_RC" != 0 ] && grep -qx 'FAIL  FINAL..HEAD touches out-of-scope files' "$TMP/a-later-old.out" && pass "AC8 control: the OLD blob is red on that later-commit frame too (the frame discriminates)" || fail "AC8 control: the OLD blob on the later-commit frame: exit $V_RC"
[ "$(find "$TMP/a-old" "$TMP/a-new" "$TMP/a-later" -name __pycache__ | wc -l)" = 0 ] && pass "AC8 the 111a runs left no __pycache__ in their frames" || fail "AC8 __pycache__ left by the 111a runs"
fi

if [ "$MUTATE" = 1 ]; then
# ---------------------------------------------------------------------------------------------------------------------
section "AC6 -- mutations in a temporary clone (each must redden its named check; the restore must be green)"
new_clone "$TMP/head" "$HEADREV" || { fail "cannot clone HEAD"; exit "$FAILURES"; }
M="$TMP/head"
cat > "$TMP/mut.py" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path).read()
if text.count(old) != 1:
    print("search found %d matches (a broken search is a failure): %r" % (text.count(old), old)); sys.exit(2)
open(path, "w").write(text.replace(old, new))
PY
mutate() { python3 -I -B "$TMP/mut.py" "$@"; }
flag_works() {   # flag_works KIND SRC : 0 if --no-closed leaves only 057 starting, exits 0 and prints the NOT RUN label
    run_slice "$1" "$2" yes "m-$1"
    [ "$S_RC" = 0 ] && [ "$S_NAMES" = "057-verify.sh" ] && grep -q 'AC4.2 NOT RUN (--no-closed)' "$S_OUT"
}
for kind in 064 065; do
    flag_works "$kind" "$M/docs/tasks/$kind-verify.sh" && pass "AC6.0 control: unmutated $kind passes the flag check" || fail "AC6.0 control: unmutated $kind fails the flag check"
done
for kind in 064 065; do
    mutate "$M/docs/tasks/$kind-verify.sh" '[ "${1:-}" = "--no-closed" ] && { NOCLOSED=1; shift; }' '[ "${1:-}" = "--no-closed" ] && { shift; }' || { fail "AC6 flag ignored in $kind: the mutation did not apply"; continue; }
    if flag_works "$kind" "$M/docs/tasks/$kind-verify.sh"; then fail "AC6 flag ignored in $kind: the check stayed GREEN (mutation survived)"; else pass "AC6 flag ignored in $kind turns red: rc $S_RC, nested starts $(printf '%s\n' "$S_NAMES" | grep -c .) (expected only 057)"; fi
    git -C "$M" checkout -q -- .
done
mutate "$M/tools/dev/sweep.py" '    "064-verify.sh": NO_CLOSED_ARGS,
    "065-verify.sh": NO_CLOSED_ARGS,
' '' || fail "AC6 sweep.py not passing the flag: the mutation did not apply"
run_tests "$M" "$TMP/m.out" NoClosedArguments; rc=$?
if [ "$rc" != 0 ] && test_bad "$TMP/m.out" NoClosedArguments.064_and_065_get_no_closed_and_other_scripts_get_none; then pass "AC6 sweep.py not passing --no-closed to 064 and 065 turns red: exit $rc, failing: $(grep -E '^(FAIL|ERROR):' "$TMP/m.out" | sed -E 's/ \(.*//' | tr '\n' ' ')"; else fail "AC6 sweep.py not passing the flag stayed green (exit $rc)"; fi
git -C "$M" checkout -q -- .
mutate "$M/tools/dev/sweep.py" '    if has_main.returncode != 0:' '    if False:' || fail "AC6 missing-main check removed: the mutation did not apply"
run_tests "$M" "$TMP/m.out" MissingMain; rc=$?
if [ "$rc" != 0 ] && test_bad "$TMP/m.out" MissingMain.source_cloned_with_branch_has_no_local_main_exit_2; then pass "AC6 missing-main check removed turns red: exit $rc, failing: $(grep -E '^(FAIL|ERROR):' "$TMP/m.out" | sed -E 's/ \(.*//' | tr '\n' ' ')"; else fail "AC6 missing-main check removed stayed green (exit $rc)"; fi
git -C "$M" checkout -q -- .
[ "$(case_args "$M/docs/tasks/039a-verify.sh" 064)" = "--no-closed" ] && pass "AC6.0 control: unmutated 039a's case gives 064 the flag" || fail "AC6.0 control: unmutated 039a's case does not give 064 the flag"
mutate "$M/docs/tasks/039a-verify.sh" '*064-verify.sh|*065-verify.sh) args=(--no-closed)' '*064-verify.sh|*065-verify.sh) args=()' || fail "AC6 039a not passing the flag: the mutation did not apply"
if [ "$(case_args "$M/docs/tasks/039a-verify.sh" 064)" = "--no-closed" ]; then fail "AC6 039a not passing the flag stayed green"; else pass "AC6 039a's case no longer giving 064 and 065 the flag turns the AC4 check red"; fi
git -C "$M" checkout -q -- .
make_later "$TMP/lf" || fail "AC6 cannot build the later-commit frame"
run_111a "$TMP/lf" "$TMP/lf0.out"
[ "$V_RC" = 0 ] && pass "AC6.0 control: the unmutated 111a-verify.sh is green on a frame whose later commit touches an out-of-scope file" || fail "AC6.0 control: unmutated 111a-verify.sh exit $V_RC on the later-commit frame"
mutate "$TMP/lf/docs/tasks/111a-verify.sh" 'TIP=58c75c033cbddc506f55358e6716682e9bfe9a53' 'TIP="$(git -C "$(dirname "$0")" rev-parse HEAD)"' || fail "AC6 111a TIP mutation did not apply"
run_111a "$TMP/lf" "$TMP/lf1.out"
if [ "$V_RC" != 0 ] && grep -qx 'FAIL  FINAL..TIP touches out-of-scope files' "$TMP/lf1.out"; then pass "AC6 111a-verify.sh with TIP set back to HEAD turns red on the later-commit frame: exit $V_RC, 'FINAL..TIP touches out-of-scope files'"; else fail "AC6 111a-verify.sh with TIP set back to HEAD stayed green or missed the FAIL line (exit $V_RC)"; fi
run_tests "$M" "$TMP/r.out"; rc=$?
[ "$rc" = 0 ] && pass "AC6 restore: unmutated clone is green again ($(grep -E '^Ran ' "$TMP/r.out"))" || fail "AC6 restore: unmutated clone is red"
for kind in 064 065; do
    flag_works "$kind" "$M/docs/tasks/$kind-verify.sh" && pass "AC6 restore: $kind passes the flag check again" || fail "AC6 restore: $kind fails the flag check"
done
fi

printf '\n== RESULT ==\n'
elapsed=$((SECONDS - START))
[ "$elapsed" -lt 120 ] && pass "AC7 finished in ${elapsed}s (< 120s; no real closed script was run)" || fail "AC7 took ${elapsed}s (>= 120s)"
[ "$FAILURES" = 0 ] && printf 'ALL PASS\n' || printf '%d FAILED\n' "$FAILURES"
exit "$FAILURES"
