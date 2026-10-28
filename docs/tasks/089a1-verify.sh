#!/usr/bin/env bash
#
# 089a1-verify.sh -- the runnable verification artefact for task 089a1 (MANAGER.md Section 2c), part A1 of umbrella 089.
#
# Task 089a1: seven closed registry checks read a file at HEAD (the worktree) as evidence of THEIR OWN change; a later,
# legitimate branch reddens them (REVIEW-CHECKLIST item 12). They now read the file at their task's pinned FINAL commit:
#   finding 1   007a-verify.sh  README mentions "tools/registry" and "task 039"            (007a, FINAL = PR #10's last commit)
#   finding 2   007a-verify.sh  README no longer says "task 007$" / "task 007 +builds"      (007a)
#   finding 3   007b-verify.sh  README mentions "ownership" and "task 039"                  (007b, FINAL = PR #12's last commit)
#   finding 4   007b-verify.sh  README no longer lists the ownership checker as still to come; was VACUOUS (the grep matched no
#                               line), now also requires the positive statement that the checker is built
#   finding 5   008a-verify.sh  README mentions build-pipeline.md                          (008a, FINAL = PR #7's last commit)
#   finding 7   tests/registry/test_hardening.py  README contains --no-renames             (007a, FINAL = PR #10's last commit)
#   finding 13  tests/registry/test_classify.py   reserved-namespaces.json names == {mc, test} (007a FINAL; Q3 answer A)
# Demonstrates acceptance criteria 1-5, 9 (the mechanism) and 11 of docs/tasks/089a1-closed-verify-sweep-registry-a1.md (umbrella
# 089 criteria 1-5, 9, 11), restricted to findings 1-5, 7 and 13. The long, whole-suite sequential runs are done by hand and logged.
#
# Usage:  docs/tasks/089a1-verify.sh [--mutate] [--own-only]      (any cwd inside the repository)
#   (no flag)   AC0 (pins re-derived from the merge commits; no own-change check reads HEAD; detectors are not vacuous),
#               AC1 (RED FIRST: on a --no-ff merge of a synthetic later branch the OLD scripts/tests fail and name the check, the
#               NEW ones pass; controls: the OLD ones pass on the plain base, so the later branch is the cause),
#               AC3 (unreachable pins, `deadbee`, fail and name the check; nothing is silently skipped),
#               AC5 (NEW scripts/tests on plain HEAD pass), AC11 (scope on fixed SHAs).
#   --mutate    AC4: each fixed check widened back to the worktree README / reserved list, on the later-branch merge on HEAD:
#               red, and only that check.
#   --own-only  AC11 only (089a1's own change on fixed SHAs); fast, runs no other script, no quiet-machine wait.
# Everything runs on the COMMITTED state in temporary clones; the caller's worktree is never modified. The scripts under test are
# read as blobs of the pinned commits below (OLD = registry main when 089a1 was cut, NEW = 089a1's fix commit), never from HEAD.
# Quiet machine (umbrella criterion 9): before every run of another script this one logs `ps` and WAITS until no other *-verify.sh
# process is running (poll 60 s, give up with a FAIL after 6 h). Run it alone, from a fresh clone of the registry.
# Network: none. Exit code: the number of failed checks. Requires: git, python3 (the 007a/007b/008a scripts also need what they need;
# 008a needs minisign, gzip, sha256sum, tar). The tests are run with unittest (pytest is not required).

set -u
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1

MUTATE=0
OWN=0
for a in "$@"; do
    case "$a" in
        --mutate) MUTATE=1 ;;
        --own-only) OWN=1 ;;
        *) printf 'FAIL  unknown argument %s\n' "$a"; exit 98 ;;
    esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }
GITID=(-c user.name=verify089a1 -c user.email=verify089a1@invalid -c commit.gpgsign=false)
HEADREV="$(git -C "$ROOT" rev-parse HEAD)"
G() { git -C "$ROOT" "$@"; }

S007A=docs/tasks/007a-verify.sh
S007B=docs/tasks/007b-verify.sh
S008A=docs/tasks/008a-verify.sh
T_HARD=tests/registry/test_hardening.py
T_CLS=tests/registry/test_classify.py
README=docs/contracts/README.md

# Fixed SHAs (full 40 characters). OLD = registry main when 089a1 was cut (the unfixed scripts and tests); the frame of every
# own-change check below is one of these, never HEAD (REVIEW-CHECKLIST item 12).
OLDREF="32c641b5f56139a86c820f0b16d522c0f991d207"
# 089a1's own commits (AC11). PIN_RED/FIX/FINAL/TIP are filled in by the pin commit after the red and fix commits exist.
PIN_BASE="32c641b5f56139a86c820f0b16d522c0f991d207"   # registry main when 089a1 was cut
PIN_RED="55c00bc056a93bce8752db022da971ca558f410a"      # 089a1-verify.sh + task files only
PIN_FIX="1cd84e70bbbfb43a1dfffed4614938fd8978c4d6"      # 007a-verify.sh, 007b-verify.sh, 008a-verify.sh, test_hardening.py, test_classify.py
PIN_FINAL="1cd84e70bbbfb43a1dfffed4614938fd8978c4d6"  # last commit in BASE..TIP touching a source file or script of the part
PIN_TIP="b6e08bfb4ed7218c399e673aacf595de5b7e608d"      # last commit of the branch before the pin commit (task-file/log only after FINAL)

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT

# ---------------------------------------------------------------------------------------------------------------------
# helpers
edit_py="$TMP/edit.py"
cat > "$edit_py" <<'PY'
import sys
mode, p, old, new = sys.argv[1:5]
s = open(p).read()
n = s.count(old)
if mode == "once" and n != 1:
    sys.exit("edit.py: pattern found %d times in %s (expected exactly 1): %r" % (n, p, old[:80]))
if mode == "all" and n < 1:
    sys.exit("edit.py: pattern not found in %s: %r" % (p, old[:80]))
if mode == "append":
    open(p, "w").write(s + new)
else:
    open(p, "w").write(s.replace(old, new))
PY
edit_file() { python3 -I "$edit_py" once "$1" "$2" "$3"; }   # edit_file FILE OLD NEW : exactly one occurrence
edit_all() { python3 -I "$edit_py" all "$1" "$2" "$3"; }      # edit_all FILE OLD NEW : every occurrence (at least one)
append_file() { python3 -I "$edit_py" append "$1" "" "$2"; }  # append_file FILE TEXT

pin_of() { sed -n "s/^$2=\"\{0,1\}\([0-9a-f]\{7,\}\)\"\{0,1\}\([[:space:]].*\)\{0,1\}$/\1/p" "$1" | head -n1; }   # pin_of FILE NAME  (NAME=sha)
pin_py() { sed -n "s/^$2 = \"\([0-9a-f]\{7,\}\)\".*$/\1/p" "$1" | head -n1; }                                      # pin_py FILE NAME  (NAME = "sha")
full40() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }
first_fail() { grep -E '^(FAIL|ERROR)' "$1" | head -n"${2:-4}" | cut -c1-150 | tr '\n' '|'; }
# expect LABEL green|red RC OUTFILE REGEX... : green = rc 0; red = rc != 0; every REGEX must match (a leading '!' demands absence)
expect() {
    local label="$1" want="$2" rc="$3" out="$4" re miss=""; shift 4
    for re in "$@"; do
        if [ "${re:0:1}" = "!" ]; then grep -Eq "${re:1}" "$out" && miss="$miss /$re/"
        else grep -Eq "$re" "$out" || miss="$miss /$re/"; fi
    done
    if [ "$want" = green ] && [ "$rc" = 0 ] && [ -z "$miss" ]; then pass "$label: exit 0"
    elif [ "$want" = red ] && [ "$rc" != 0 ] && [ -z "$miss" ]; then pass "$label: exit $rc, $(grep -E '^(FAIL|ERROR)' "$out" | head -n1 | cut -c1-130)"
    else fail "$label: wanted $want, got exit $rc$miss: $(first_fail "$out")"; fi
}

# ---- quiet machine: log ps, wait until no other *-verify.sh runs (this script's own name excluded)
others() { ps -eo pid,args 2>/dev/null | grep -E '[0-9A-Za-z]+-verify\.sh' | grep -v -e '089a1-verify\.sh' -e 'grep -E'; }
wait_quiet() {   # wait_quiet LABEL : messages go to stderr (the callers capture stdout)
    local waited=0
    if [ -n "$(others)" ]; then
        printf '      [ps before %s] other *-verify.sh processes are running; waiting:\n' "$1" >&2
        others | sed 's/^/        /' >&2
    fi
    while [ -n "$(others)" ]; do
        sleep 60; waited=$((waited + 60))
        if [ "$waited" -ge 21600 ]; then printf '      [quiet-wait] %s: gave up after 6 h\n' "$1" >&2; return 1; fi
    done
    if [ "$waited" -gt 0 ]; then printf '      [quiet-wait] %s: machine quiet after %s s\n' "$1" "$waited" >&2
    else printf '      [ps before %s] no other *-verify.sh process\n' "$1" >&2; fi
    return 0
}

# blobs of the scripts and tests under test
OLDD="$TMP/old"; NEWD="$TMP/new"; mkdir -p "$OLDD" "$NEWD"
for f in "$S007A" "$S007B" "$S008A" "$T_HARD" "$T_CLS"; do
    G show "$OLDREF:$f" > "$OLDD/$(basename "$f")" 2>/dev/null || fail "AC0.0 cannot read $f at OLD $OLDREF"
    if [[ "$PIN_FIX" =~ ^[0-9a-f]{40}$ ]]; then
        G show "$PIN_FIX:$f" > "$NEWD/$(basename "$f")" 2>/dev/null || fail "AC0.0 cannot read $f at the fix commit $PIN_FIX"
    else : > "$NEWD/$(basename "$f")"; fi
done
[[ "$PIN_FIX" =~ ^[0-9a-f]{40}$ ]] || fail "AC0.0 the fix commit is not pinned yet (PIN_FIX=$PIN_FIX): the NEW scripts cannot be read"
b007a=007a-verify.sh; b007b=007b-verify.sh; b008a=008a-verify.sh; bhard=test_hardening.py; bcls=test_classify.py

# mk_frame DEST REV : a clone detached at REV
mk_frame() {
    git clone -q --no-hardlinks "$ROOT" "$1" 2>/dev/null || return 1
    git -C "$1" checkout -q --detach "$2" || return 1
}
# mk_lb DEST REV EDITFN : a clone at REV plus a --no-ff merge of a synthetic later branch whose edits are EDITFN DEST
mk_lb() {
    mk_frame "$1" "$2" || return 1
    git -C "$1" checkout -q -b later-branch || return 1
    "$3" "$1" || return 1
    git -C "$1" "${GITID[@]}" commit -q -am "synthetic later branch ($3)" || return 1
    git -C "$1" checkout -q --detach "$2" || return 1
    git -C "$1" "${GITID[@]}" merge --no-ff -q -m "merge of the synthetic later branch ($3)" later-branch >/dev/null 2>&1 || return 1
}
# run_in DIR OUTFILE CMD... : (quiet-machine wait, then) run CMD in DIR, output to OUTFILE; echo the exit code
run_in() {
    local d="$1" o="$2"; shift 2
    wait_quiet "$(basename "$o")" || { : > "$o"; echo 97; return; }
    ( cd "$d" && PYTHONDONTWRITEBYTECODE=1 "$@" ) > "$o" 2>&1
    echo $?
}
place() { cp "$2" "$1/$3" && chmod +x "$1/$3"; }   # place DIR SRCFILE DESTRELPATH : put a copy of a script/test into the clone
run_test() { run_in "$1" "$2" python3 -B -m unittest discover -s tests/registry -p "$3"; }   # run_test DIR OUTFILE FILENAME

# --- the later branches: each is the legitimate edit a later task makes to the file the old check read at HEAD
lb_007a() {   # README reworded: "task 039" and "tools/registry" no longer appear, and a later note says "task 007 builds ..."
    edit_all "$1/$README" 'task 039' 'the CI-workflow task' && edit_all "$1/$README" 'tools/registry' 'the registry tools directory' \
        && append_file "$1/$README" $'\ntask 007 builds the gates (a later note)\n'
}
lb_007b() {   # README reworded: "task 039" gone; the built/still-to-come statements are reflowed onto one line
    edit_all "$1/$README" 'task 039' 'the CI-workflow task' \
        && edit_file "$1/$README" '**built** (task 007b) is the ownership checker' '**built** is the ownership checker (task 007b) and **still to come** is the CI workflow'
}
lb_008a() { edit_all "$1/$README" 'build-pipeline.md' 'pipeline-doc.md'; }                 # the pipeline doc is renamed
lb_hard() { edit_all "$1/$README" '--no-renames' '--no-rename-detection'; }                # README no longer spells the flag
lb_cls() {    # a new namespace is reserved
    edit_file "$1/reserved-namespaces.json" '    "test": {' $'    "later": {"owner": {"provider": "github", "id": 1, "name_at_registration": "later"}, "reason": "synthetic later reserved namespace"},\n    "test": {'
}

# needles for the mutations and the deadbee runs (the exact text the fix commit wrote)
PF="printf '%s\\n' \"\$README_TXT\""

# ==================================================================================================
if [ "$MUTATE" = 0 ]; then

if [ "$OWN" = 0 ]; then
section "AC0 -- pins re-derived from the merge commits; own-change checks read the pinned FINAL, not HEAD; detectors are not vacuous"
merge_of() { G log --first-parent --merges --format=%H -E --grep="^Merge pull request #[0-9]+ from worldofmodcraft/task/$1\$" "$OLDREF" | head -n2; }
for t in 007a-registry-checkers-shape 007b-registry-checker-ownership 008a-pipeline-core; do
    n=$(merge_of "$t" | wc -l)
    [ "$n" = 1 ] && pass "AC0.1 exactly one merge commit for task/$t: $(merge_of "$t")" || fail "AC0.1 task/$t: expected exactly one merge commit on main, found $n"
done
M007A=$(merge_of 007a-registry-checkers-shape); M007B=$(merge_of 007b-registry-checker-ownership); M008A=$(merge_of 008a-pipeline-core)
a_b=$(pin_of "$NEWD/$b007a" BASE);   a_f=$(pin_of "$NEWD/$b007a" FINAL)
b_b=$(pin_of "$NEWD/$b007b" BASE007B); b_f=$(pin_of "$NEWD/$b007b" FINAL007B)
c_b=$(pin_of "$NEWD/$b008a" BASE);   c_f=$(pin_of "$NEWD/$b008a" FINAL)
h_f=$(pin_py "$NEWD/$bhard" README_PIN_FINAL); k_f=$(pin_py "$NEWD/$bcls" RESERVED_PIN_FINAL)
if [ -z "$M007A" ] || [ -z "$M007B" ] || [ -z "$M008A" ] || [ -z "$a_f" ] || [ -z "$b_f" ] || [ -z "$c_f" ] || [ -z "$h_f" ] || [ -z "$k_f" ]; then
    fail "AC0.2 cannot read a pin or find a merge (007a '$a_f' 007b '$b_f' 008a '$c_f' hardening '$h_f' classify '$k_f'): a search that finds nothing is broken"
else
    for p in "$a_b" "$a_f" "$b_b" "$b_f" "$c_b" "$c_f" "$h_f" "$k_f"; do full40 "$p" || fail "AC0.2 pin '$p' is not a full 40-character SHA"; done
    [ "$a_f" = "$(G rev-parse "$M007A^2")" ] && pass "AC0.3 007a FINAL=$a_f is PR #10's last commit (git rev-parse $M007A^2)" || fail "AC0.3 007a FINAL=$a_f is not $M007A^2"
    [ "$a_b" = "$(G merge-base "$M007A^1" "$M007A^2")" ] && pass "AC0.4 007a BASE=$a_b is PR #10's fork point (git merge-base $M007A^1 $M007A^2)" || fail "AC0.4 007a BASE=$a_b is not the fork point"
    [ "$b_f" = "$(G rev-parse "$M007B^2")" ] && pass "AC0.5 007b FINAL=$b_f is PR #12's last commit (git rev-parse $M007B^2)" || fail "AC0.5 007b FINAL=$b_f is not $M007B^2"
    [ "$b_b" = "$(G merge-base "$M007B^1" "$M007B^2")" ] && pass "AC0.6 007b BASE=$b_b is PR #12's fork point (git merge-base $M007B^1 $M007B^2)" || fail "AC0.6 007b BASE=$b_b is not the fork point"
    [ "$c_f" = "$(G rev-parse "$M008A^2")" ] && pass "AC0.7 008a FINAL=$c_f is PR #7's last commit (git rev-parse $M008A^2)" || fail "AC0.7 008a FINAL=$c_f is not $M008A^2"
    [ "$c_b" = "$(G merge-base "$M008A^1" "$M008A^2")" ] && pass "AC0.8 008a BASE=$c_b is PR #7's fork point (git merge-base $M008A^1 $M008A^2)" || fail "AC0.8 008a BASE=$c_b is not the fork point"
    [ "$h_f" = "$a_f" ] && [ "$k_f" = "$a_f" ] && pass "AC0.9 test_hardening.py and test_classify.py pin 007a's FINAL $a_f (finding 7 and 13: same merge $M007A)" || fail "AC0.9 the test pins ($h_f, $k_f) are not 007a's FINAL $a_f"
    for p in "$a_f" "$b_f" "$c_f"; do
        G merge-base --is-ancestor "$p" "$OLDREF" && pass "AC0.10 pin $p is reachable from registry main at the cut ($OLDREF)" || fail "AC0.10 pin $p is not an ancestor of $OLDREF"
    done
fi
# own-change reads: the new check reads a blob of the pin; no worktree read of the README / reserved list remains (non-zero counts required, §2c rule 1)
cnt() { grep -cF -- "$2" "$1"; }
# wt FILE : lines (comments stripped) that hand docs/contracts/README.md (the worktree path) to a command as an argument after a quoted pattern
wt() { grep -v '^[[:space:]]*#' "$1" | grep -cE "[\"'] docs/contracts/README\.md([[:space:]]|\$)"; }
[ "$(cnt "$NEWD/$b007a" 'git show "$FINAL:$README_PATH"')" -ge 1 ] \
    && [ "$(wt "$NEWD/$b007a")" = 0 ] \
    && pass "AC0.11 007a reads the README with git show \"\$FINAL:...\" and no grep/cat of docs/contracts/README.md in the worktree remains" || fail "AC0.11 007a still reads the worktree README (or does not read the pin)"
[ "$(cnt "$NEWD/$b007b" 'git show "$FINAL007B:$README_PATH"')" -ge 1 ] && [ "$(wt "$NEWD/$b007b")" = 0 ] \
    && pass "AC0.12 007b reads the README with git show \"\$FINAL007B:...\" and no grep/cat of docs/contracts/README.md in the worktree remains" || fail "AC0.12 007b still reads the worktree README (or does not read the pin)"
[ "$(cnt "$NEWD/$b008a" 'git show "$FINAL:docs/contracts/README.md"')" -ge 1 ] && [ "$(wt "$NEWD/$b008a")" = 0 ] \
    && pass "AC0.13 008a reads the README with git show \"\$FINAL:...\" and no grep of docs/contracts/README.md in the worktree remains" || fail "AC0.13 008a still reads the worktree README (or does not read the pin)"
[ "$(cnt "$NEWD/$bhard" 'readme_at(README_PIN_FINAL)')" -ge 1 ] && [ "$(cnt "$NEWD/$bhard" 'support.REPO / "docs" / "contracts" / "README.md"')" = 0 ] \
    && pass "AC0.14 test_hardening.py reads the README blob at README_PIN_FINAL and no longer from the worktree" || fail "AC0.14 test_hardening.py still reads the worktree README (or does not read the pin)"
[ "$(cnt "$NEWD/$bcls" 'RESERVED_PIN_FINAL + ":reserved-namespaces.json"')" -ge 1 ] && [ "$(cnt "$NEWD/$bcls" 'support.REPO / "reserved-namespaces.json"')" = 0 ] \
    && pass "AC0.15 test_classify.py reads reserved-namespaces.json at RESERVED_PIN_FINAL and no longer from the worktree" || fail "AC0.15 test_classify.py still reads the worktree list (or does not read the pin)"
# the OLD scripts did read the worktree (positive control for the counts above: the grep CAN match)
[ "$(wt "$OLDD/$b007a")" -ge 2 ] && [ "$(wt "$OLDD/$b007b")" -ge 2 ] && [ "$(wt "$OLDD/$b008a")" -ge 1 ] \
    && pass "AC0.16 positive control: the OLD 007a/007b/008a scripts do contain worktree README greps (>= 2, >= 2, >= 1)" || fail "AC0.16 the worktree-read grep cannot match the OLD scripts"
# the detectors of findings 2 and 4 can match (positive controls on the commits BEFORE each task's change), and do not match at FINAL
if [ -n "${a_b:-}" ] && [ -n "${b_b:-}" ]; then
    [ "$(G show "$a_b:$README" | grep -cE 'task 007$|task 007 +builds')" -ge 1 ] && [ "$(G show "$a_f:$README" | grep -cE 'task 007$|task 007 +builds')" = 0 ] \
        && pass "AC0.17 finding 2 detector: matches the README at 007a's BASE ($a_b) and nothing at its FINAL: it is not vacuous" || fail "AC0.17 finding 2 detector does not separate BASE from FINAL"
    [ "$(G show "$b_b:$README" | grep -n 'ownership checker (task 007b' | grep -ci 'still to come')" -ge 1 ] && [ "$(G show "$b_f:$README" | grep -n 'ownership checker (task 007b' | grep -ci 'still to come')" = 0 ] \
        && [ "$(G show "$b_f:$README" | grep -cF '**built** (task 007b) is the ownership checker')" = 1 ] \
        && pass "AC0.18 finding 4: the old wording is present at 007b's BASE ($b_b), absent at FINAL, and the positive statement 'built' is present exactly once at FINAL" || fail "AC0.18 finding 4: detector or positive statement does not separate BASE from FINAL"
fi
# every mutation needle used below occurs exactly once in the NEW blob (a mutation that cannot apply proves nothing)
need_once() {   # need_once FILE NEEDLE LABEL
    local n; n=$(python3 -I -c 'import sys; print(open(sys.argv[1]).read().count(sys.argv[2]))' "$1" "$2")
    [ "$n" = 1 ] && pass "AC0.19 mutation needle present exactly once: $3" || fail "AC0.19 mutation needle occurs $n times (want 1): $3"
}
need_once "$NEWD/$b007a" "if $PF | grep -q \"tools/registry\" && $PF | grep -q \"task 039\"" "007a finding 1 check"
need_once "$NEWD/$b007a" "elif $PF | grep -n \"task 007\$\" >/dev/null || $PF | grep -nE \"task 007 +builds\" >/dev/null; then" "007a finding 2 check"
need_once "$NEWD/$b007b" "if $PF | grep -q \"ownership\" && $PF | grep -q \"task 039\"" "007b finding 3 check"
need_once "$NEWD/$b007b" "elif $PF | grep -n \"ownership checker (task 007b\" | grep -qi \"still to come\"; then" "007b finding 4 check"
need_once "$NEWD/$b008a" "git show \"\$FINAL:docs/contracts/README.md\" 2>/dev/null | grep -q 'build-pipeline.md'" "008a finding 5 check"
need_once "$NEWD/$bhard" 'code, readme = readme_at(README_PIN_FINAL)' "test_hardening finding 7 read"
need_once "$NEWD/$bcls" 'data = json.loads(p.stdout)' "test_classify finding 13 read"

section "AC1 -- red first: a later branch is merged; the OLD scripts/tests fail and name the check, the NEW ones pass on the same kind of merge"
# ---- findings 1 and 2: 007a (a later branch rewords the README: "task 039" / "tools/registry" gone, "task 007 builds" added)
if ! mk_lb "$TMP/o1" "$OLDREF" lb_007a; then fail "AC1.1.0 cannot build the later-branch merge on OLD"; else
    place "$TMP/o1" "$OLDD/$b007a" "$S007A"; rc=$(run_in "$TMP/o1" "$TMP/o1.out" bash "$S007A")
    expect "AC1.1a the OLD 007a-verify.sh on OLD + a later README rewording (findings 1 and 2)" red "$rc" "$TMP/o1.out" '^FAIL  criterion 12: README not updated' '^FAIL  README still says task 007 builds the gates'
fi
rc=$(mk_frame "$TMP/c1" "$OLDREF" && place "$TMP/c1" "$OLDD/$b007a" "$S007A" && run_in "$TMP/c1" "$TMP/c1.out" bash "$S007A")
expect "AC1.1b control: the OLD 007a-verify.sh on plain OLD (the later branch is the cause)" green "$rc" "$TMP/c1.out" '^ok    criterion 12: docs/contracts/README.md updated' '^ok    README no longer says task 007 builds the gates'
if ! mk_lb "$TMP/n1" "$HEADREV" lb_007a; then fail "AC1.1.1 cannot build the later-branch merge on HEAD"; else
    place "$TMP/n1" "$NEWD/$b007a" "$S007A"; rc=$(run_in "$TMP/n1" "$TMP/n1.out" bash "$S007A")
    expect "AC1.1c the NEW 007a-verify.sh on HEAD + the same later edit" green "$rc" "$TMP/n1.out" '^ok    criterion 12: docs/contracts/README.md at [0-9a-f]{40} updated' '^ok    README at [0-9a-f]{40} no longer says task 007 builds the gates' '!^FAIL'
fi
# ---- findings 3 and 4: 007b (a later branch rewords the README: "task 039" gone; built / still-to-come reflowed onto one line)
if ! mk_lb "$TMP/o3" "$OLDREF" lb_007b; then fail "AC1.3.0 cannot build the later-branch merge on OLD"; else
    place "$TMP/o3" "$OLDD/$b007b" "$S007B"; rc=$(run_in "$TMP/o3" "$TMP/o3.out" bash "$S007B")
    expect "AC1.3a the OLD 007b-verify.sh on OLD + a later README rewording (findings 3 and 4)" red "$rc" "$TMP/o3.out" '^FAIL  criterion 12: README not updated' '^FAIL  README still lists the ownership checker as still to come'
fi
rc=$(mk_frame "$TMP/c3" "$OLDREF" && place "$TMP/c3" "$OLDD/$b007b" "$S007B" && run_in "$TMP/c3" "$TMP/c3.out" bash "$S007B")
expect "AC1.3b control: the OLD 007b-verify.sh on plain OLD (the later branch is the cause)" green "$rc" "$TMP/c3.out" '^ok    criterion 12: docs/contracts/README.md names the ownership checker' '^ok    README no longer lists the ownership checker as still to come'
if ! mk_lb "$TMP/n3" "$HEADREV" lb_007b; then fail "AC1.3.1 cannot build the later-branch merge on HEAD"; else
    place "$TMP/n3" "$NEWD/$b007b" "$S007B"; rc=$(run_in "$TMP/n3" "$TMP/n3.out" bash "$S007B")
    expect "AC1.3c the NEW 007b-verify.sh on HEAD + the same later edit" green "$rc" "$TMP/n3.out" '^ok    criterion 12: docs/contracts/README.md at [0-9a-f]{40} names the ownership checker' '^ok    README at [0-9a-f]{40} lists the ownership checker as built' '!^FAIL'
fi
# ---- finding 4, vacuity: the OLD condition passes on a README that does NOT say the checker is built (it matched no line); the NEW check is red on that README at the pin
OLDCOND='grep -n "ownership checker (task 007b" docs/contracts/README.md | grep -qi "still to come"'
[ "$(cnt "$OLDD/$b007b" "$OLDCOND")" = 1 ] && pass "AC1.4.0 the old finding-4 condition is present exactly once in the OLD 007b-verify.sh" || fail "AC1.4.0 the old finding-4 condition was not found in the OLD script"
G show "$OLDREF:$README" | sed 's/\*\*built\*\* (task 007b) is the ownership checker/was never built here, the ownership checker/' > "$TMP/readme-notbuilt.md"
[ "$(grep -c 'was never built here, the ownership checker' "$TMP/readme-notbuilt.md")" = 1 ] && pass "AC1.4.1 fixture README built: it no longer says the ownership checker is built" || fail "AC1.4.1 fixture README was not built"
if grep -n "ownership checker (task 007b" "$TMP/readme-notbuilt.md" | grep -qi "still to come"; then fail "AC1.4a the old condition fired on the not-built README (the vacuity premise is wrong)"
else pass "AC1.4a defect shown: the OLD finding-4 condition does not fire on a README that no longer says the checker is built, so the old check would print ok (vacuous)"; fi
mk_pin_variant() {   # mk_pin_variant DEST SEDEXPR : clone of HEAD + merge of a synthetic commit X on top of 007b's pin whose README is edited; echoes nothing, sets X
    mk_frame "$1" "$HEADREV" || return 1
    local pin; pin=$(pin_of "$NEWD/$b007b" FINAL007B)
    git -C "$1" checkout -q -b at-pin "$pin" || return 1
    sed -i "$2" "$1/$README" || return 1
    git -C "$1" "${GITID[@]}" commit -q -am "synthetic: README at 007b's pin edited" || return 1
    X=$(git -C "$1" rev-parse HEAD) || return 1
    git -C "$1" checkout -q --detach "$HEADREV" || return 1
    git -C "$1" "${GITID[@]}" merge --no-ff -q -m "merge the synthetic pin variant" at-pin >/dev/null 2>&1 || return 1
}
X=""
if mk_pin_variant "$TMP/n4a" 's/\*\*built\*\* (task 007b) is the ownership checker/was never built here, the ownership checker/' && [ -n "$X" ]; then
    cp "$NEWD/$b007b" "$TMP/n4a/$S007B" && chmod +x "$TMP/n4a/$S007B" && edit_file "$TMP/n4a/$S007B" "FINAL007B=\"$(pin_of "$NEWD/$b007b" FINAL007B)\"" "FINAL007B=\"$X\"" \
        && rc=$(run_in "$TMP/n4a" "$TMP/n4a.out" bash "$S007B")
    expect "AC1.4b the NEW 007b-verify.sh is RED when the README at the pin does not say the checker is built (finding 4 is not vacuous)" red "${rc:-0}" "$TMP/n4a.out" "^FAIL  README at $X does not state that the ownership checker"
else fail "AC1.4.2 cannot build the not-built pin variant"; fi
X=""
if mk_pin_variant "$TMP/n4b" 's/\*\*built\*\* (task 007b) is the ownership checker/**still to come** are the ownership checker (task 007b/' && [ -n "$X" ]; then
    cp "$NEWD/$b007b" "$TMP/n4b/$S007B" && chmod +x "$TMP/n4b/$S007B" && edit_file "$TMP/n4b/$S007B" "FINAL007B=\"$(pin_of "$NEWD/$b007b" FINAL007B)\"" "FINAL007B=\"$X\"" \
        && rc=$(run_in "$TMP/n4b" "$TMP/n4b.out" bash "$S007B")
    expect "AC1.4c the NEW 007b-verify.sh is RED when the README at the pin lists the checker as still to come" red "${rc:-0}" "$TMP/n4b.out" "^FAIL  README at $X still lists the ownership checker as still to come"
else fail "AC1.4.3 cannot build the still-to-come pin variant"; fi
# ---- finding 5: 008a (a later branch renames the pipeline doc, so the README no longer says build-pipeline.md)
if ! mk_lb "$TMP/o5" "$OLDREF" lb_008a; then fail "AC1.5.0 cannot build the later-branch merge on OLD"; else
    place "$TMP/o5" "$OLDD/$b008a" "$S008A"; rc=$(run_in "$TMP/o5" "$TMP/o5.out" bash "$S008A")
    expect "AC1.5a the OLD 008a-verify.sh on OLD + a later README edit" red "$rc" "$TMP/o5.out" '^FAIL  docs/contracts/README.md not updated'
fi
rc=$(mk_frame "$TMP/c5" "$OLDREF" && place "$TMP/c5" "$OLDD/$b008a" "$S008A" && run_in "$TMP/c5" "$TMP/c5.out" bash "$S008A")
expect "AC1.5b control: the OLD 008a-verify.sh on plain OLD (the later branch is the cause)" green "$rc" "$TMP/c5.out" '^ok    docs/contracts/README.md points at the pipeline doc'
if ! mk_lb "$TMP/n5" "$HEADREV" lb_008a; then fail "AC1.5.1 cannot build the later-branch merge on HEAD"; else
    place "$TMP/n5" "$NEWD/$b008a" "$S008A"; rc=$(run_in "$TMP/n5" "$TMP/n5.out" bash "$S008A")
    expect "AC1.5c the NEW 008a-verify.sh on HEAD + the same later edit" green "$rc" "$TMP/n5.out" '^ok    docs/contracts/README.md at 008a.s pinned FINAL [0-9a-f]{40} points at the pipeline doc' '!^FAIL'
fi
# ---- finding 7: test_hardening.py (a later branch renames the flag in the README)
if ! mk_lb "$TMP/o7" "$OLDREF" lb_hard; then fail "AC1.7.0 cannot build the later-branch merge on OLD"; else
    place "$TMP/o7" "$OLDD/$bhard" "$T_HARD"; rc=$(run_test "$TMP/o7" "$TMP/o7.out" test_hardening.py)
    expect "AC1.7a the OLD test_hardening.py on OLD + a later README edit" red "$rc" "$TMP/o7.out" '^FAIL: test_f2_help_and_readme_say_diff_with_no_renames'
fi
rc=$(mk_frame "$TMP/c7" "$OLDREF" && place "$TMP/c7" "$OLDD/$bhard" "$T_HARD" && run_test "$TMP/c7" "$TMP/c7.out" test_hardening.py)
expect "AC1.7b control: the OLD test_hardening.py on plain OLD (the later branch is the cause)" green "$rc" "$TMP/c7.out" '^OK$'
if ! mk_lb "$TMP/n7" "$HEADREV" lb_hard; then fail "AC1.7.1 cannot build the later-branch merge on HEAD"; else
    place "$TMP/n7" "$NEWD/$bhard" "$T_HARD"; rc=$(run_test "$TMP/n7" "$TMP/n7.out" test_hardening.py)
    expect "AC1.7c the NEW test_hardening.py on HEAD + the same later edit" green "$rc" "$TMP/n7.out" '^OK$' '!^(FAIL|ERROR)'
fi
# ---- finding 13: test_classify.py (a later branch reserves one more namespace)
if ! mk_lb "$TMP/o13" "$OLDREF" lb_cls; then fail "AC1.13.0 cannot build the later-branch merge on OLD"; else
    place "$TMP/o13" "$OLDD/$bcls" "$T_CLS"; rc=$(run_test "$TMP/o13" "$TMP/o13.out" test_classify.py)
    expect "AC1.13a the OLD test_classify.py on OLD + a later reserved namespace" red "$rc" "$TMP/o13.out" '^FAIL: test_the_real_reserved_list_in_this_repo_has_mc_and_test'
fi
rc=$(mk_frame "$TMP/c13" "$OLDREF" && place "$TMP/c13" "$OLDD/$bcls" "$T_CLS" && run_test "$TMP/c13" "$TMP/c13.out" test_classify.py)
expect "AC1.13b control: the OLD test_classify.py on plain OLD (the later branch is the cause)" green "$rc" "$TMP/c13.out" '^OK$'
if ! mk_lb "$TMP/n13" "$HEADREV" lb_cls; then fail "AC1.13.1 cannot build the later-branch merge on HEAD"; else
    place "$TMP/n13" "$NEWD/$bcls" "$T_CLS"; rc=$(run_test "$TMP/n13" "$TMP/n13.out" test_classify.py)
    expect "AC1.13c the NEW test_classify.py on HEAD + the same later edit (Q3 A consequence: it no longer guards the live list)" green "$rc" "$TMP/n13.out" '^OK$' '!^(FAIL|ERROR)'
fi
fi   # OWN = 0

# ==================================================================================================
if [ "$OWN" = 0 ]; then
section "AC5 -- the NEW scripts and tests on plain HEAD exit 0 (the unmerged state)"
if mk_frame "$TMP/h" "$HEADREV"; then
    place "$TMP/h" "$NEWD/$b007a" "$S007A"; place "$TMP/h" "$NEWD/$b007b" "$S007B"; place "$TMP/h" "$NEWD/$b008a" "$S008A"
    place "$TMP/h" "$NEWD/$bhard" "$T_HARD"; place "$TMP/h" "$NEWD/$bcls" "$T_CLS"
    rc=$(run_in "$TMP/h" "$TMP/h007a.out" bash "$S007A"); expect "AC5.1 NEW 007a-verify.sh on HEAD" green "$rc" "$TMP/h007a.out" '^ok    criterion 12: docs/contracts/README.md at [0-9a-f]{40} updated'
    rc=$(run_in "$TMP/h" "$TMP/h007b.out" bash "$S007B"); expect "AC5.2 NEW 007b-verify.sh on HEAD" green "$rc" "$TMP/h007b.out" '^ok    README at [0-9a-f]{40} lists the ownership checker as built'
    rc=$(run_in "$TMP/h" "$TMP/h008a.out" bash "$S008A"); expect "AC5.3 NEW 008a-verify.sh on HEAD" green "$rc" "$TMP/h008a.out" '^ok    docs/contracts/README.md at 008a.s pinned FINAL [0-9a-f]{40} points at the pipeline doc'
    rc=$(run_test "$TMP/h" "$TMP/hhard.out" test_hardening.py); expect "AC5.4 NEW test_hardening.py on HEAD" green "$rc" "$TMP/hhard.out" '^OK$'
    rc=$(run_test "$TMP/h" "$TMP/hcls.out" test_classify.py); expect "AC5.5 NEW test_classify.py on HEAD" green "$rc" "$TMP/hcls.out" '^OK$'
else fail "AC5.0 cannot clone HEAD"; fi

section "AC3 -- an unreachable pin (deadbee) is a FAIL naming the check; nothing is skipped"
if mk_frame "$TMP/d" "$HEADREV"; then
    pa=$(pin_of "$NEWD/$b007a" FINAL); pb=$(pin_of "$NEWD/$b007b" FINAL007B); pc=$(pin_of "$NEWD/$b008a" FINAL)
    ph=$(pin_py "$NEWD/$bhard" README_PIN_FINAL); pk=$(pin_py "$NEWD/$bcls" RESERVED_PIN_FINAL)
    place "$TMP/d" "$NEWD/$b007a" "$S007A" && edit_file "$TMP/d/$S007A" "FINAL=$pa" "FINAL=deadbee" && rc=$(run_in "$TMP/d" "$TMP/d007a.out" bash "$S007A")
    expect "AC3.1 007a with FINAL=deadbee (findings 1, 2)" red "${rc:-0}" "$TMP/d007a.out" '^FAIL  pinned commit deadbee \(or docs/contracts/README.md at it\) is not readable' '^FAIL  criterion 12: README at deadbee not updated' '^FAIL  README-no-longer-says check cannot run'
    place "$TMP/d" "$NEWD/$b007b" "$S007B" && edit_file "$TMP/d/$S007B" "FINAL007B=\"$pb\"" "FINAL007B=\"deadbee\"" && rc=$(run_in "$TMP/d" "$TMP/d007b.out" bash "$S007B")
    expect "AC3.2 007b with FINAL007B=deadbee (findings 3, 4)" red "${rc:-0}" "$TMP/d007b.out" '^FAIL  pinned commit deadbee \(or docs/contracts/README.md at it\) is not readable' '^FAIL  criterion 12: README at deadbee not updated' '^FAIL  README-ownership-checker-built check cannot run'
    place "$TMP/d" "$NEWD/$b008a" "$S008A" && edit_file "$TMP/d/$S008A" "FINAL=$pc" "FINAL=deadbee" && rc=$(run_in "$TMP/d" "$TMP/d008a.out" bash "$S008A")
    expect "AC3.3 008a with FINAL=deadbee (finding 5)" red "${rc:-0}" "$TMP/d008a.out" '^FAIL  docs/contracts/README.md at pinned FINAL deadbee does not point at the pipeline doc'
    place "$TMP/d" "$NEWD/$bhard" "$T_HARD" && edit_file "$TMP/d/$T_HARD" "README_PIN_FINAL = \"$ph\"" 'README_PIN_FINAL = "deadbee"' && rc=$(run_test "$TMP/d" "$TMP/dhard.out" test_hardening.py)
    expect "AC3.4 test_hardening.py with README_PIN_FINAL=deadbee (finding 7)" red "${rc:-0}" "$TMP/dhard.out" '^FAIL: test_f2_help_and_readme_say_diff_with_no_renames' 'unreachable pin is a failure'
    place "$TMP/d" "$NEWD/$bcls" "$T_CLS" && edit_file "$TMP/d/$T_CLS" "RESERVED_PIN_FINAL = \"$pk\"" 'RESERVED_PIN_FINAL = "deadbee"' && rc=$(run_test "$TMP/d" "$TMP/dcls.out" test_classify.py)
    expect "AC3.5 test_classify.py with RESERVED_PIN_FINAL=deadbee (finding 13)" red "${rc:-0}" "$TMP/dcls.out" '^FAIL: test_the_real_reserved_list_in_this_repo_has_mc_and_test' 'unreachable pin is a failure'
    # no silent skip: outside FAIL lines (which may quote the words in their explanation) the words of a skip never appear in any run above;
    # the grep can match (positive control)
    printf 'x skipped y\nok    a check that was not evaluated\n' > "$TMP/skipctl.txt"
    [ "$(grep -v '^FAIL' "$TMP/skipctl.txt" | grep -Eic 'skip|not evaluated')" = 2 ] && pass "AC3.6a positive control: the skip-word grep (non-FAIL lines) matches both sample lines" || fail "AC3.6a the skip-word grep cannot match"
    hits=$(cat "$TMP"/d007a.out "$TMP"/d007b.out "$TMP"/d008a.out "$TMP"/dhard.out "$TMP"/dcls.out "$TMP"/h007a.out "$TMP"/h007b.out "$TMP"/h008a.out "$TMP"/hhard.out "$TMP"/hcls.out 2>/dev/null | grep -v '^FAIL' | grep -Eic 'skip|not evaluated')
    [ "$hits" = 0 ] && pass "AC3.6 'skip' / 'not evaluated' occur 0 times outside FAIL lines in the deadbee and HEAD runs (FAIL lines may quote 'a skipped check proves nothing')" || fail "AC3.6 $hits skip/not-evaluated line(s) in the run outputs"
else fail "AC3.0 cannot clone HEAD"; fi
fi   # OWN = 0

section "AC11 -- 089a1's own change, measured on fixed SHAs (never HEAD)"
SRCS='docs/tasks/007a-verify.sh docs/tasks/007b-verify.sh docs/tasks/008a-verify.sh tests/registry/test_hardening.py tests/registry/test_classify.py'
if [ "$PIN_RED" = "__RED__" ] || [ "$PIN_FIX" = "__FIX__" ] || [ "$PIN_FINAL" = "__FINAL__" ] || [ "$PIN_TIP" = "__TIP__" ]; then
    fail "AC11.0 the 089a1 red/fix/final/tip SHAs are not pinned yet"
else
    for s in "$PIN_BASE" "$PIN_RED" "$PIN_FIX" "$PIN_FINAL" "$PIN_TIP"; do
        full40 "$s" || fail "AC11.1 pin '$s' is not a full 40-character SHA"
        G cat-file -e "$s^{commit}" 2>/dev/null && pass "AC11.1 pin $s exists" || fail "AC11.1 pin $s does not exist"
    done
    [ "$(G rev-parse "$PIN_RED^" 2>/dev/null)" != "" ] && G merge-base --is-ancestor "$PIN_BASE" "$PIN_RED" && G merge-base --is-ancestor "$PIN_RED" "$PIN_FIX" \
        && G merge-base --is-ancestor "$PIN_FIX" "$PIN_FINAL" && G merge-base --is-ancestor "$PIN_FINAL" "$PIN_TIP" && G merge-base --is-ancestor "$PIN_TIP" HEAD \
        && pass "AC11.2 BASE < RED < FIX <= FINAL <= TIP <= HEAD (ancestry)" || fail "AC11.2 the pins are not in ancestry order"
    task_md=docs/tasks/089a1-closed-verify-sweep-registry-a1.md
    red_files="$(G diff --name-only "$PIN_BASE" "$PIN_RED" 2>/dev/null | grep -vx -e docs/tasks/089-closed-verify-sweep-registry.md -e "$task_md" | sort | tr '\n' ' ')"
    [ "$red_files" = "docs/tasks/089a1-verify.sh " ] && pass "AC11.3 the red commit touches only 089a1-verify.sh and the task files" || fail "AC11.3 the red commit touches: $red_files"
    fix_files="$(G diff --name-only "$PIN_RED" "$PIN_FIX" 2>/dev/null | grep -vx "$task_md" | sort | tr '\n' ' ')"
    [ "$fix_files" = "$(printf '%s\n' $SRCS | sort | tr '\n' ' ')" ] \
        && pass "AC11.4 the fix commit touches exactly the five source files (007a, 007b, 008a, test_hardening, test_classify)" || fail "AC11.4 the fix commit touches: $fix_files"
    if ! scope_files="$(G diff --name-only "$PIN_BASE" "$PIN_TIP" 2>&1)"; then fail "AC11.5 cannot compute $PIN_BASE..$PIN_TIP"; else
        extra="$(printf '%s\n' "$scope_files" | grep -vxE 'docs/tasks/007a-verify\.sh|docs/tasks/007b-verify\.sh|docs/tasks/008a-verify\.sh|tests/registry/test_hardening\.py|tests/registry/test_classify\.py|docs/tasks/089a1-verify\.sh|docs/tasks/089a1-closed-verify-sweep-registry-a1\.md|docs/tasks/089-closed-verify-sweep-registry\.md' | tr '\n' ' ')"
        [ -n "$scope_files" ] && [ -z "$extra" ] && pass "AC11.5 BASE..TIP stays inside the declared file scope" || fail "AC11.5 out-of-scope files in BASE..TIP (or the range is empty): $extra"
    fi
    last_src="$(G log -1 --format=%H "$PIN_BASE..$PIN_TIP" -- $SRCS docs/tasks/089a1-verify.sh 2>/dev/null)"
    [ -n "$last_src" ] && [ "$last_src" = "$(G rev-parse "$PIN_FINAL^{commit}" 2>/dev/null)" ] && pass "AC11.6a FINAL is the last commit in BASE..TIP that touched a source or script file" || fail "AC11.6 FINAL ${PIN_FINAL:0:12} is not the last source-touching commit (that is ${last_src:0:12})"
    if ! tail_files="$(G diff --name-only "$PIN_FINAL" "$PIN_TIP" 2>&1)"; then fail "AC11.6 cannot compute FINAL..TIP"
    elif [ -z "$(printf '%s\n' "$tail_files" | grep -vE '^docs/tasks/089a1-closed-verify-sweep-registry-a1\.md$')" ]; then pass "AC11.6b FINAL..TIP touches only the 089a1 task file"
    else fail "AC11.6 FINAL..TIP touches: $(printf '%s' "$tail_files" | tr '\n' ' ')"; fi
    # the source tests each only had a pin and the named checks edited: non-comment changed lines outside the named checks must be 0 (and some must exist)
    nonc() { G diff -U0 "$PIN_RED" "$PIN_FIX" -- "$1" | grep -E '^[+-][^+-]' | grep -vE '^[+-][[:space:]]*#' ; }
    hunk() {   # hunk FILE ALLOWED_REGEX LABEL
        local all out; all="$(nonc "$1" | wc -l)"; out="$(nonc "$1" | grep -vE "$2" | wc -l)"
        [ "$all" -gt 0 ] && [ "$out" = 0 ] && pass "AC11.7 $3: $all changed non-comment line(s), 0 outside the named checks and pins" || fail "AC11.7 $3: $all changed line(s), $out outside the named checks and pins"
    }
    hunk docs/tasks/007a-verify.sh 'BASE=|FINAL=|README|^[+-](else|fi)$' "007a-verify.sh (pins; findings 1, 2)"
    hunk docs/tasks/007b-verify.sh 'BASE007B=|FINAL007B=|README|^[+-](else|fi)$' "007b-verify.sh (pins; findings 3, 4)"
    hunk docs/tasks/008a-verify.sh 'BASE=|FINAL=|README' "008a-verify.sh (pins, moved above the docs checks; finding 5)"
    hunk tests/registry/test_hardening.py 'README|readme|^\+def readme_at|^\+    p = subprocess\.run\(\["git"|^\+    return p\.returncode' "test_hardening.py (finding 7)"
    hunk tests/registry/test_classify.py 'import subprocess|RESERVED_PIN_FINAL|reserved-namespaces|capture_output|p\.returncode|json\.loads\(p\.stdout\)' "test_classify.py (finding 13)"
    for f in tests/registry/test_hardening.py tests/registry/test_classify.py; do
        G show "$PIN_FIX:$f" | python3 -I -c 'import ast,sys; ast.parse(sys.stdin.read())' && pass "AC11.8 $f at the fix commit still parses" || fail "AC11.8 $f does not parse"
    done
    for f in docs/tasks/007a-verify.sh docs/tasks/007b-verify.sh docs/tasks/008a-verify.sh; do
        G show "$PIN_FIX:$f" | bash -n /dev/stdin 2>/dev/null && pass "AC11.9 $f at the fix commit passes bash -n" || fail "AC11.9 $f has a syntax error at the fix commit"
    done
    [ "$(G ls-tree "$PIN_FIX" docs/tasks/007a-verify.sh docs/tasks/007b-verify.sh docs/tasks/008a-verify.sh | grep -c '^100755 ')" = 3 ] && pass "AC11.10 the three scripts are still executable (mode 100755) at the fix commit" || fail "AC11.10 a script lost its executable bit"
fi

# ==================================================================================================
else
section "AC4 mutations (each fixed check widened back to the worktree, on the later-branch merge on HEAD; red, and only that check)"
mutate_run() {   # mutate_run LABEL KIND KEY OLD NEW RUN FAILREGEX   (KIND = lb_ function suffix; RUN = script|test)
    local label="$1" kind="$2" key="$3" old="$4" new="$5" run="$6" fr="$7" rc nfail d="$TMP/m-$2-$RANDOM" dest
    mk_lb "$d" "$HEADREV" "lb_$kind" || { fail "$label cannot build the frame"; return; }
    cp "$NEWD/$key" "$TMP/mut.src"
    edit_file "$TMP/mut.src" "$old" "$new" || { fail "$label: the mutation did not apply (pattern not found exactly once)"; return; }
    case "$key" in
        *-verify.sh) dest="docs/tasks/$key" ;;
        *) dest="tests/registry/$key" ;;
    esac
    cp "$TMP/mut.src" "$d/$dest"; chmod +x "$d/$dest"
    if [ "$run" = script ]; then rc=$(run_in "$d" "$TMP/mut.out" bash "$dest"); nfail=$(grep -c '^FAIL  ' "$TMP/mut.out")
    else rc=$(run_test "$d" "$TMP/mut.out" "$key"); nfail=$(grep -cE '^(FAIL|ERROR): ' "$TMP/mut.out"); fi
    if [ "$rc" != 0 ] && grep -Eq "$fr" "$TMP/mut.out" && [ "$nfail" = 1 ]; then pass "$label turns red, and only that check: exit $rc, $(grep -E '^(FAIL|ERROR)' "$TMP/mut.out" | head -n1 | cut -c1-120)"
    else fail "$label: exit $rc, $nfail FAIL line(s) (want exactly 1 matching /$fr/): $(first_fail "$TMP/mut.out")"; fi
}
mutate_run "AC4.m1 007a finding 1 (README tools/registry, task 039) widened back to the worktree README" 007a "$b007a" \
    "if $PF | grep -q \"tools/registry\" && $PF | grep -q \"task 039\"" 'if grep -q "tools/registry" "$README_PATH" && grep -q "task 039" "$README_PATH"' script '^FAIL  criterion 12: README at [0-9a-f]{40} not updated'
mutate_run "AC4.m2 007a finding 2 (README no longer says task 007 builds) widened back to the worktree README" 007a "$b007a" \
    "elif $PF | grep -n \"task 007\$\" >/dev/null || $PF | grep -nE \"task 007 +builds\" >/dev/null; then" 'elif grep -n "task 007$" "$README_PATH" >/dev/null || grep -nE "task 007 +builds" "$README_PATH" >/dev/null; then' script '^FAIL  README at [0-9a-f]{40} still says task 007 builds the gates'
mutate_run "AC4.m3 007b finding 3 (README ownership, task 039) widened back to the worktree README" 007b "$b007b" \
    "if $PF | grep -q \"ownership\" && $PF | grep -q \"task 039\"" 'if grep -q "ownership" "$README_PATH" && grep -q "task 039" "$README_PATH"' script '^FAIL  criterion 12: README at [0-9a-f]{40} not updated'
mutate_run "AC4.m4 007b finding 4 (still to come) widened back to the worktree README" 007b "$b007b" \
    "elif $PF | grep -n \"ownership checker (task 007b\" | grep -qi \"still to come\"; then" 'elif grep -n "ownership checker (task 007b" "$README_PATH" | grep -qi "still to come"; then' script '^FAIL  README at [0-9a-f]{40} still lists the ownership checker as still to come'
mutate_run "AC4.m5 008a finding 5 (README mentions build-pipeline.md) widened back to the worktree README" 008a "$b008a" \
    "git show \"\$FINAL:docs/contracts/README.md\" 2>/dev/null | grep -q 'build-pipeline.md'" "grep -q 'build-pipeline.md' docs/contracts/README.md" script '^FAIL  docs/contracts/README.md at pinned FINAL [0-9a-f]{40} does not point at the pipeline doc'
mutate_run "AC4.m7 test_hardening finding 7 (README --no-renames) widened back to the worktree README" hard "$bhard" \
    'code, readme = readme_at(README_PIN_FINAL)' 'code, readme = 0, (support.REPO / "docs" / "contracts" / "README.md").read_text()' test '^FAIL: test_f2_help_and_readme_say_diff_with_no_renames'
mutate_run "AC4.m13 test_classify finding 13 (reserved list names) widened back to the worktree list" cls "$bcls" \
    'data = json.loads(p.stdout)' 'data = json.loads((support.REPO / "reserved-namespaces.json").read_text())' test '^FAIL: test_the_real_reserved_list_in_this_repo_has_mc_and_test'
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
