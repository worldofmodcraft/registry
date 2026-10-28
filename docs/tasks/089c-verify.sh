#!/usr/bin/env bash
#
# 089c-verify.sh -- the runnable verification artefact for task 089c (MANAGER.md Section 2c), part C of umbrella 089.
#
# Task 089c, side finding S1: 069-verify.sh AC5.3 read 034-verify.sh from the REMOTE BRANCH origin/task/064-schema-check-end-anchor.
# When that branch is deleted (after the merge of PR #13 it can be at any time) the check printed "note: ... not evaluated" and
# did NOT fail: a silent skip (the check could never fail again). It now reads 034-verify.sh at a pinned full SHA, PIN064
# (the FINAL of PR #13, an ancestor of registry main); a pin that cannot be read is a FAIL, never a skip.
# Demonstrates acceptance criteria 1-3, 6, 9 (the mechanism) and 11 of docs/tasks/089c-closed-verify-sweep-registry-c.md
# (umbrella criteria, restricted to S1). Criterion 4 (--mutate) is the --mutate mode; criterion 5 (item 12) is AC1.e / AC9.
#
# Usage:  docs/tasks/089c-verify.sh [--mutate] [--own-only] [--full] [NODE_MODULES_DIR]   (any cwd inside the repository)
#   (no flag)   AC0  pins re-derived from the merge commit; PIN064 reachable from origin/main; the new 069 reads no branch ref;
#               AC1  RED FIRST: in a clone where origin/task/064-schema-check-end-anchor is DELETED the OLD 069 (registry main when 089c
#                    was cut) prints "not evaluated" and gives no AC5.3 evidence (the defect), the NEW 069 passes AC5.3; controls:
#                    branch present, and a later synthetic branch that edits 034-verify.sh merged in (item 12);
#               AC3  PIN064 = deadbee / a non-existent 40-hex SHA / a commit without the file / a commit whose file is not 064's
#                    all FAIL AC5.3; no "skip" / "not evaluated" word in any NEW run, with a positive control that the grep matches;
#               AC11 089c's own change on fixed SHAs.
#   --mutate    AC4: the pin widened back to the branch ref (red with the branch deleted, green with it present), widened to HEAD
#               (red on the later-branch merge), the silent skip restored (the AC3 detector fires); each reddens only AC5.3.
#   --own-only  AC11 only (fast, runs no other script).
#   --full      AC9: the complete NEW 069-verify.sh (default mode) on HEAD and on the later-branch merge, branch deleted, one at a
#               time, then NEW 069-verify.sh --mutate on HEAD. Hours-scale; needs NODE_MODULES_DIR with ajv. Not part of no-flag mode.
#   NODE_MODULES_DIR (or env WOM_NODE_MODULES, else <repo root>/tools/dev/node_modules) is needed by --full only.
# Truncation: the no-flag/--mutate runs execute 069-verify.sh TRUNCATED to its preamble plus its AC5 section (the section that holds
# the S1 check); the markers are asserted to occur exactly once. The complete script is run by --full.
# Everything runs on the COMMITTED state in temporary clones; the caller's worktree is never modified. The scripts under test are read
# as blobs of the pinned commits below (OLD = registry main when 089c was cut, NEW = 089c's fix commit), never from HEAD.
# Quiet machine: before every run of a child script this script waits until no other *-verify.sh process is running (it logs the
# ps lines it saw, to stderr), up to six hours, then FAILs. Network: none. Exit code: the number of failed checks.
# Requires: git (>= 2.31), python3, ps, awk; node and ajv only for --full.

set -u
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1

MUTATE=0
OWN=0
FULL=0
NM="${WOM_NODE_MODULES:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/tools/dev/node_modules}"
for a in "$@"; do
    case "$a" in
        --mutate) MUTATE=1 ;;
        --own-only) OWN=1 ;;
        --full) FULL=1 ;;
        *) NM="$a" ;;
    esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }
GITID=(-c user.name=verify089c -c user.email=verify089c@invalid -c commit.gpgsign=false)
HEADREV="$(git -C "$ROOT" rev-parse HEAD)"
G() { git -C "$ROOT" "$@"; }

S069=docs/tasks/069-verify.sh
BRANCH_REF=origin/task/064-schema-check-end-anchor
BRANCH_FULLREF=refs/remotes/origin/task/064-schema-check-end-anchor

# Fixed SHAs (full 40 characters). OLD = registry main when 089c was cut (the unfixed 069); the frame of every own-change
# check below is one of these, never HEAD (REVIEW-CHECKLIST item 12).
OLDREF="32c641b5f56139a86c820f0b16d522c0f991d207"
# 089c's own commits (AC11). Filled in by the pin commit after the red and fix commits exist.
PIN_BASE="32c641b5f56139a86c820f0b16d522c0f991d207"   # registry main when 089c was cut
PIN_RED="3b8db962327ea3f4dd82190551b0833e86e9df04"      # 089c-verify.sh + task file only
PIN_FIX="1564ad0731ea794bcd286f6dcd08ed5d7a77b509"      # 069-verify.sh
PIN_FINAL="1564ad0731ea794bcd286f6dcd08ed5d7a77b509"  # last commit touching a source file of the part
PIN_TIP="2f4495902b7c71a89c2fa5d97cab302689819006"      # last commit of the branch before the pin commit (task file only after FINAL)

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT

# ---------------------------------------------------------------------------------------------------------------------
# helpers
edit_py="$TMP/edit.py"
cat > "$edit_py" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if s.count(old) != 1:
    sys.exit("edit.py: pattern found %d times in %s (expected exactly 1): %r" % (s.count(old), p, old[:80]))
open(p, "w").write(s.replace(old, new, 1))
PY
edit_file() { python3 -I "$edit_py" "$1" "$2" "$3"; }   # edit_file FILE OLD NEW : exactly one occurrence

pin_of() { sed -n "s/^$2=\"\{0,1\}\([0-9a-f]\{7,\}\)\"\{0,1\}\([[:space:]].*\)\{0,1\}$/\1/p" "$1" | head -n1; }
full40() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }
first_fail() { grep -E '^FAIL' "$1" | head -n"${2:-4}" | cut -c1-140 | tr '\n' '|'; }
# expect LABEL green|red RC OUTFILE REGEX... : green = rc 0; red = rc != 0; every REGEX must match (a leading '!' demands absence)
expect() {
    local label="$1" want="$2" rc="$3" out="$4" re miss=""; shift 4
    for re in "$@"; do
        if [ "${re:0:1}" = "!" ]; then grep -Eq "${re:1}" "$out" && miss="$miss /$re/"
        else grep -Eq "$re" "$out" || miss="$miss /$re/"; fi
    done
    if [ "$want" = green ] && [ "$rc" = 0 ] && [ -z "$miss" ]; then pass "$label: exit 0"
    elif [ "$want" = red ] && [ "$rc" != 0 ] && [ -z "$miss" ]; then pass "$label: exit $rc, $(grep -E '^FAIL' "$out" | head -n1 | cut -c1-120)"
    else fail "$label: wanted $want, got exit $rc$miss: $(first_fail "$out")"; fi
}

# quiet_wait : block until no other *-verify.sh process is running (not this script, its ancestors, or its own subshells/children).
# Logs the ps lines it saw to stderr; six hours at most, then returns 1. Returns 0 on a quiet machine.
quiet_wait() {
    local waited=0 anc p pp others n
    while :; do
        anc=" $$ "; p=$$
        while [ "${p:-0}" -gt 1 ]; do
            pp=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
            [ -z "$pp" ] && break
            anc="$anc$pp "; p=$pp
        done
        others=$(ps -eo pid=,ppid=,args= 2>/dev/null | awk -v anc="$anc" -v me="$$" '
            { if (index(anc, " " $1 " ") || $2 == me) next
              if ($0 ~ /[0-9a-z]+-verify\.sh/) print $0 }')
        n=$(printf '%s' "$others" | grep -c .)
        if [ "$n" = 0 ]; then
            printf 'ps    %s quiet: no other *-verify.sh process running (waited %ss)\n' "$(date +%H:%M:%S)" "$waited" | tee -a "$TMP/ps.log" >&2
            return 0
        fi
        if [ $((waited % 300)) = 0 ]; then
            printf 'ps    %s waiting: %s other *-verify.sh process(es) running (waited %ss); first 3:\n' "$(date +%H:%M:%S)" "$n" "$waited" | tee -a "$TMP/ps.log" >&2
            printf '%s\n' "$others" | head -n3 | cut -c1-150 | sed 's/^/        /' | tee -a "$TMP/ps.log" >&2
        fi
        [ "$waited" -ge 21600 ] && return 1
        sleep 10; waited=$((waited + 10))
    done
}

# blobs of the script under test
OLDD="$TMP/old"; NEWD="$TMP/new"; mkdir -p "$OLDD" "$NEWD"
G show "$OLDREF:$S069" > "$OLDD/069.sh" 2>/dev/null && [ -s "$OLDD/069.sh" ] || fail "AC0.0 cannot read 069-verify.sh at OLD $OLDREF"
NEW_OK=1
if full40 "$PIN_FIX" && G show "$PIN_FIX:$S069" > "$NEWD/069.sh" 2>/dev/null && [ -s "$NEWD/069.sh" ]; then :
else
    NEW_OK=0; : > "$NEWD/069.sh"
    fail "AC0.0 the fix commit is not pinned or unreadable (PIN_FIX=$PIN_FIX): the NEW 069-verify.sh cannot be read, every check on it is red"
fi

# trunc_069 FILE : FILE's preamble (everything before its 'if [ "$MUTATE" = 0 ]' line), a clone of HEAD for the AC5 section, then
# the AC5 section (up to the AC7 section), then the closing lines. Fails unless each marker occurs exactly once.
M_IF='if [ "$MUTATE" = 0 ]; then'
M_AC5='section "AC5 -- 062'
M_AC7='section "AC7 (amendment 1)'
trunc_069() {
    [ "$(grep -cxF -- "$M_IF" "$1")" = 1 ] && [ "$(grep -cF -- "$M_AC5" "$1")" = 1 ] && [ "$(grep -cF -- "$M_AC7" "$1")" = 1 ] || return 1
    awk -v mif="$M_IF" -v m5="$M_AC5" -v m7="$M_AC7" '
        BEGIN { st = 0 }
        st == 0 && $0 == mif { st = 1
            print "new_clone \"$TMP/head\" \"$HEADREV\" || fail \"AC5.pre cannot clone HEAD\""; next }
        st == 1 && index($0, m5) == 1 { st = 2 }
        st == 2 && index($0, m7) == 1 { exit }
        st != 1 { print }'  "$1"
    printf '%s\n' "printf '\\n== RESULT ==\\n'; [ \"\$FAILURES\" -eq 0 ] && echo 'ALL CHECKS PASSED'; exit \"\$FAILURES\""
}
if [ "$NEW_OK" = 1 ]; then
    trunc_069 "$NEWD/069.sh" > "$NEWD/069.trunc.sh" || { : > "$NEWD/069.trunc.sh"; fail "AC0.0b the NEW 069-verify.sh lacks exactly one of each truncation marker"; }
else : > "$NEWD/069.trunc.sh"; fi
trunc_069 "$OLDD/069.sh" > "$OLDD/069.trunc.sh" || { : > "$OLDD/069.trunc.sh"; fail "AC0.0b the OLD 069-verify.sh lacks exactly one of each truncation marker"; }

P064=""   # the pinned 064 FINAL as the NEW 069 declares it; read in AC0 / AC4, used to build frames
# mk_frame DEST REV [present|deleted] : a clone detached at REV; the remote-tracking ref of task 064's branch is set to the pinned
# 064 FINAL ("present", the situation while the branch exists) or removed ("deleted", the situation after it is deleted).
mk_frame() {
    git clone -q --no-hardlinks "$ROOT" "$1" 2>/dev/null || return 1
    git -C "$1" checkout -q --detach "$2" || return 1
    case "${3:-deleted}" in
        present) git -C "$1" update-ref "$BRANCH_FULLREF" "$P064" || return 1
                 git -C "$1" rev-parse -q --verify "$BRANCH_FULLREF" >/dev/null || return 1 ;;
        deleted) git -C "$1" update-ref -d "$BRANCH_FULLREF" 2>/dev/null
                 ! git -C "$1" rev-parse -q --verify "$BRANCH_FULLREF" >/dev/null || return 1 ;;
    esac
}
# mk_later DEST REV STATE FILE OLD NEW : mk_frame, then a --no-ff merge of a synthetic later branch that edits FILE (OLD -> NEW, once)
mk_later() {
    mk_frame "$1" "$2" "$3" || return 1
    git -C "$1" checkout -q -b later-branch || return 1
    edit_file "$1/$4" "$5" "$6" || return 1
    git -C "$1" "${GITID[@]}" commit -q -am "synthetic later branch: edit $4" || return 1
    git -C "$1" checkout -q --detach "$2" || return 1
    git -C "$1" "${GITID[@]}" merge --no-ff -q -m "merge of the synthetic later branch ($4)" later-branch >/dev/null 2>&1 || return 1
}
# run_in DIR OUTFILE CMD... : wait for a quiet machine, run CMD in DIR (output to OUTFILE); echo the exit code
run_in() {
    local d="$1" o="$2"; shift 2
    if ! quiet_wait; then echo "quiet-machine wait timed out" > "$o"; echo 99; return; fi
    ( cd "$d" && PYTHONDONTWRITEBYTECODE=1 env -u WOM_NODE_MODULES "$@" ) > "$o" 2>&1
    echo $?
}
place() { cp "$2" "$1/$3"; }   # place DIR SRCFILE DESTRELPATH : an (untracked) copy of a script in the clone

# the later branch: a legitimate later edit of the very file whose blob AC5.3 judges (034-verify.sh), item 12
L_FILE=docs/tasks/034-verify.sh
L_OLD='C4.1 TRAVERSAL_PATHS contains'
L_NEW='C4.1 TRAVERSAL_PATHS holds'

TRUNC=docs/tasks/069-trunc.sh
PINSKIP='skip|not evaluated'

# ==================================================================================================
if [ "$MUTATE" = 0 ]; then

if [ "$OWN" = 0 ]; then
section "AC0 -- the pin re-derived from task 064's merge commit; it is reachable from main; the new check reads no branch ref"
merge_of() { G log --first-parent --merges --format=%H -E --grep="^Merge pull request #[0-9]+ from worldofmodcraft/task/$1\$" "$OLDREF" | head -n2; }
t=064-schema-check-end-anchor
n=$(merge_of "$t" | wc -l)
[ "$n" = 1 ] && pass "AC0.1 exactly one merge commit for task/$t on main: $(merge_of "$t")" || fail "AC0.1 task/$t: expected exactly one merge commit on main, found $n"
M064=$(merge_of "$t")
P064=$(pin_of "$NEWD/069.sh" PIN064)
if [ -z "$P064" ] || [ -z "$M064" ]; then
    fail "AC0.2 cannot read PIN064 from the NEW 069-verify.sh or find the merge (PIN064='$P064' merge='$M064'): a search that finds nothing is broken"
    P064="$(G rev-parse "${M064:-HEAD}^2" 2>/dev/null || echo 0000000000000000000000000000000000000000)"   # keeps the frames below buildable; the checks above already FAILED
else
    full40 "$P064" && pass "AC0.2 PIN064 is a full 40-character SHA: $P064" || fail "AC0.2 PIN064 '$P064' is not a full 40-character SHA"
    [ "$P064" = "$(G rev-parse "$M064^2")" ] && pass "AC0.3 PIN064 is PR #13's last commit (git rev-parse $M064^2)" || fail "AC0.3 PIN064=$P064 is not $M064^2"
    # criterion 6: reachable from registry main, so a clone that no longer has the branch still has the commit
    MAINREF=refs/remotes/origin/main
    if G rev-parse -q --verify "$MAINREF" >/dev/null; then
        G merge-base --is-ancestor "$P064" "$MAINREF" && pass "AC0.4 git merge-base --is-ancestor $P064 origin/main ($(G rev-parse --short "$MAINREF")): reachable from registry main" || fail "AC0.4 PIN064 is NOT reachable from origin/main: a committed fixture blob is needed (umbrella S1)"
    else fail "AC0.4 refs/remotes/origin/main does not exist in this clone: reachability from main cannot be shown (run in a fresh clone of the registry)"; fi
    G merge-base --is-ancestor "$P064" "$OLDREF" && pass "AC0.4b PIN064 is an ancestor of OLD $OLDREF (registry main when 089c was cut)" || fail "AC0.4b PIN064 is not an ancestor of OLD"
    G cat-file -e "$P064:docs/tasks/034-verify.sh" 2>/dev/null && pass "AC0.5 docs/tasks/034-verify.sh exists at PIN064" || fail "AC0.5 docs/tasks/034-verify.sh does not exist at PIN064"
fi
# non-zero counts required (2c rule 1): the new check reads the pin; no read of the branch ref remains in code lines
cnt() { grep -cF -- "$2" "$1"; }
code_lines() { grep -vE '^[[:space:]]*#' "$1"; }
[ "$(cnt "$NEWD/069.sh" '"$PIN064:docs/tasks/034-verify.sh"')" -ge 1 ] && pass "AC0.6 NEW 069 reads 034-verify.sh with git show \"\$PIN064:...\" ($(cnt "$NEWD/069.sh" '"$PIN064:docs/tasks/034-verify.sh"') use(s))" || fail "AC0.6 NEW 069 does not read 034-verify.sh at PIN064"
c=$(code_lines "$NEWD/069.sh" | grep -cF 'origin/task/064-schema-check-end-anchor'); [ "$c" = 0 ] && [ "$NEW_OK" = 1 ] && pass "AC0.7 NEW 069 code lines name no origin/task/064 branch ref (0 hits)" || fail "AC0.7 NEW 069 still names the 064 branch ref in code ($c hit(s)) or is unreadable"
c=$(code_lines "$OLDD/069.sh" | grep -cF 'origin/task/064-schema-check-end-anchor'); [ "$c" -ge 1 ] && pass "AC0.7b positive control: the same grep finds the branch ref in the OLD 069 ($c hit(s))" || fail "AC0.7b the branch-ref grep cannot match the OLD 069"
c=$(code_lines "$NEWD/069.sh" | grep -Ec 'not evaluated|PIN064:-|WOM_PIN|\$\{PIN064'); [ "$c" = 0 ] && [ "$NEW_OK" = 1 ] && pass "AC0.8 NEW 069 has no 'not evaluated' branch and no environment override of PIN064 (0 hits)" || fail "AC0.8 NEW 069 has a silent-skip text or an env override of the pin ($c hit(s)) or is unreadable"
c=$(code_lines "$OLDD/069.sh" | grep -Ec 'not evaluated'); [ "$c" -ge 1 ] && pass "AC0.8b positive control: the same grep finds 'not evaluated' in the OLD 069 ($c hit(s))" || fail "AC0.8b the grep cannot match the OLD 069"

section "AC1 -- red first: with the 064 branch deleted, the OLD 069 gives no AC5.3 evidence (silent skip); the NEW one passes it"
[ -s "$OLDD/069.trunc.sh" ] && [ -s "$NEWD/069.trunc.sh" ] && pass "AC1.0 positive control: both truncated copies are non-empty ($(wc -l < "$OLDD/069.trunc.sh") / $(wc -l < "$NEWD/069.trunc.sh") lines)" || fail "AC1.0 a truncated copy is empty"
# a. control: while the branch exists the OLD script passes AC5.3 (so the deletion is the cause)
if mk_frame "$TMP/o-present" "$HEADREV" present; then
    place "$TMP/o-present" "$OLDD/069.trunc.sh" "$TRUNC"; rc=$(run_in "$TMP/o-present" "$TMP/o-present.out" bash "$TRUNC")
    expect "AC1.a control: the OLD 069 (truncated) with the branch PRESENT passes AC5.3" green "$rc" "$TMP/o-present.out" '^PASS  AC5\.3 ' '!not evaluated'
else fail "AC1.a cannot build the branch-present frame"; fi
# b. RED: branch deleted -> the OLD script exits 0 yet states it did not evaluate AC5.3 and has no AC5.3 verdict line
if mk_frame "$TMP/o-del" "$HEADREV" deleted; then
    place "$TMP/o-del" "$OLDD/069.trunc.sh" "$TRUNC"; rc=$(run_in "$TMP/o-del" "$TMP/o-del.out" bash "$TRUNC")
    if [ "$rc" = 0 ] && grep -q 'AC5\.3 (the real branch file) not evaluated' "$TMP/o-del.out" && ! grep -Eq '^(PASS|FAIL)  AC5\.3 ' "$TMP/o-del.out"; then
        pass "AC1.b red first: the OLD 069 with the branch DELETED exits 0 and prints 'not evaluated' with no AC5.3 verdict (the silent skip): $(grep 'not evaluated' "$TMP/o-del.out" | head -n1 | sed 's/^ *//' | cut -c1-100)"
    else fail "AC1.b the OLD 069 with the branch deleted did not show the silent skip: exit $rc, verdict lines: $(grep -E '^(PASS|FAIL)  AC5\.3' "$TMP/o-del.out" | head -n2 | tr '\n' '|')"; fi
    [ "$(grep -Eic "$PINSKIP" "$TMP/o-del.out")" -ge 1 ] && pass "AC1.b2 positive control: the skip/not-evaluated grep matches the OLD run's output ($(grep -Eic "$PINSKIP" "$TMP/o-del.out") line(s))" || fail "AC1.b2 the skip/not-evaluated grep cannot match the OLD run's output"
else fail "AC1.b cannot build the branch-deleted frame (the ref still resolves or the clone failed)"; fi
# c. GREEN: the same frame, the NEW script
if mk_frame "$TMP/n-del" "$HEADREV" deleted; then
    place "$TMP/n-del" "$NEWD/069.trunc.sh" "$TRUNC"; rc=$(run_in "$TMP/n-del" "$TMP/n-del.out" bash "$TRUNC")
    expect "AC1.c the NEW 069 (truncated) with the branch DELETED passes AC5.3 from the pin" green "$rc" "$TMP/n-del.out" "^PASS  AC5\\.3 .*$P064" '!^FAIL' "!$PINSKIP"
else fail "AC1.c cannot build the branch-deleted frame"; fi
# d. control: branch present, NEW script (the pin, not the branch, is what is read)
if mk_frame "$TMP/n-present" "$HEADREV" present; then
    place "$TMP/n-present" "$NEWD/069.trunc.sh" "$TRUNC"; rc=$(run_in "$TMP/n-present" "$TMP/n-present.out" bash "$TRUNC")
    expect "AC1.d control: the NEW 069 with the branch PRESENT passes AC5.3" green "$rc" "$TMP/n-present.out" "^PASS  AC5\\.3 .*$P064" '!^FAIL' "!$PINSKIP"
else fail "AC1.d cannot build the branch-present frame"; fi
# e. item 12: a later branch edits 034-verify.sh (the file whose blob AC5.3 judges); NEW stays green, branch deleted
if mk_later "$TMP/n-later" "$HEADREV" deleted "$L_FILE" "$L_OLD" "$L_NEW"; then
    place "$TMP/n-later" "$NEWD/069.trunc.sh" "$TRUNC"; rc=$(run_in "$TMP/n-later" "$TMP/n-later.out" bash "$TRUNC")
    expect "AC1.e item 12: the NEW 069 on HEAD merged with a later branch that edits 034-verify.sh, branch deleted" green "$rc" "$TMP/n-later.out" "^PASS  AC5\\.3 .*$P064" '!^FAIL' "!$PINSKIP"
else fail "AC1.e cannot build the later-branch merge"; fi

section "AC3 -- an unreadable pin is a FAIL naming AC5.3; nothing is skipped"
pinrepl() {   # pinrepl OUT NEWPIN : the truncated NEW script with PIN064 replaced
    cp "$NEWD/069.trunc.sh" "$1" && edit_file "$1" "PIN064=\"$P064\"" "PIN064=\"$2\""
}
BASE062_FULL="$(G rev-parse e009ef0 2>/dev/null || echo 0000000000000000000000000000000000000000)"
NOFILE_COMMIT="$(G rev-list --max-parents=0 "$OLDREF" 2>/dev/null | head -n1)"
if mk_frame "$TMP/d" "$HEADREV" deleted; then
    : > "$TMP/d.outs"
    for spec in "deadbee|AC3.1 PIN064=deadbee (abbreviated, non-existent)|^FAIL  AC5\\.3 pinned commit deadbee" \
                "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef|AC3.2 PIN064 = a well-formed 40-hex SHA that is not in the repository|^FAIL  AC5\\.3 pinned commit deadbeefdeadbeef" \
                "${NOFILE_COMMIT:-0}|AC3.3 PIN064 = the root commit (exists, has no docs/tasks/034-verify.sh)|^FAIL  AC5\\.3 pinned commit" \
                "$BASE062_FULL|AC3.4 PIN064 = 062's base (exists, its 034-verify.sh is untouched, not 064's)|^FAIL  AC5\\.3 the actual 064 034-verify.sh at" ; do
        pin="${spec%%|*}"; rest="${spec#*|}"; label="${rest%%|*}"; re="${rest#*|}"
        k=$(printf '%s' "$label" | sed 's/ .*//'); out="$TMP/d-$k.out"
        if pinrepl "$TMP/d/$TRUNC" "$pin"; then
            rc=$(run_in "$TMP/d" "$out" bash "$TRUNC"); cat "$out" >> "$TMP/d.outs"
            expect "$label" red "$rc" "$out" "$re" '^PASS  AC5\.2 '
        else fail "$label: the pin replacement did not apply"; fi
    done
    # the words of a silent skip never appear in the output of any NEW run in this script, and the grep can match (positive control)
    printf 'x skipped y\n' > "$TMP/skipctl.txt"
    grep -Eiq "$PINSKIP" "$TMP/skipctl.txt" && pass "AC3.5a positive control: the skip-word grep matches a sample line" || fail "AC3.5a the skip-word grep cannot match"
    grep -Eiq "$PINSKIP" "$TMP/o-del.out" 2>/dev/null && pass "AC3.5b positive control: it also matches the real OLD run output (AC1.b)" || fail "AC3.5b the skip-word grep does not match the OLD run output (or AC1.b did not run)"
    hits=$(cat "$TMP/n-del.out" "$TMP/n-present.out" "$TMP/n-later.out" "$TMP/d.outs" 2>/dev/null | grep -Eic "$PINSKIP")
    [ "$hits" = 0 ] && pass "AC3.5 'skip' / 'not evaluated' occur 0 times in the output of every NEW run (branch deleted, present, later merge, four bad pins)" || fail "AC3.5 $hits skip/not-evaluated line(s) in the NEW run outputs"
else fail "AC3.0 cannot build the frame"; fi

# ==================================================================================================
if [ "$FULL" = 1 ]; then
section "AC9 -- the complete NEW 069-verify.sh, one run at a time, branch deleted (hours-scale)"
if [ ! -d "$NM/ajv" ] || ! command -v node >/dev/null 2>&1; then fail "AC9.0 node and a node_modules directory with ajv are required: run: npm ci --prefix tools/dev (or pass NODE_MODULES_DIR)"
else
    if mk_frame "$TMP/f-head" "$HEADREV" deleted; then
        place "$TMP/f-head" "$NEWD/069.sh" "$S069"; rc=$(run_in "$TMP/f-head" "$TMP/f-head.out" bash "$S069" "$NM")
        expect "AC9.1 NEW 069-verify.sh (complete) on HEAD, branch deleted" green "$rc" "$TMP/f-head.out" "^PASS  AC5\\.3 .*$P064" "!$PINSKIP"
    else fail "AC9.1 cannot build the frame"; fi
    if mk_later "$TMP/f-later" "$HEADREV" deleted "$L_FILE" "$L_OLD" "$L_NEW"; then
        place "$TMP/f-later" "$NEWD/069.sh" "$S069"; rc=$(run_in "$TMP/f-later" "$TMP/f-later.out" bash "$S069" "$NM")
        expect "AC9.2 NEW 069-verify.sh (complete) on HEAD merged with a later branch editing 034-verify.sh, branch deleted" green "$rc" "$TMP/f-later.out" "^PASS  AC5\\.3 .*$P064" "!$PINSKIP"
    else fail "AC9.2 cannot build the later-branch merge"; fi
    if mk_frame "$TMP/f-mut" "$HEADREV" deleted; then
        place "$TMP/f-mut" "$NEWD/069.sh" "$S069"; rc=$(run_in "$TMP/f-mut" "$TMP/f-mut.out" bash "$S069" --mutate "$NM")
        expect "AC9.3 NEW 069-verify.sh --mutate (complete) on HEAD, branch deleted" green "$rc" "$TMP/f-mut.out" '^PASS  AC5\.m1 ' "!^FAIL"
    else fail "AC9.3 cannot build the frame"; fi
    # S5: if 062 inside 067 fails its AC1.5 anywhere above, that is a finding against 062: the output is kept
    for f in f-head f-later f-mut; do grep -q 'FAIL  AC1\.5' "$TMP/$f.out" 2>/dev/null && { echo "S5: FAIL AC1.5 seen in $f; full output follows"; cat "$TMP/$f.out"; }; done
fi
fi
fi   # OWN = 0

section "AC11 -- 089c's own change, measured on fixed SHAs (never HEAD)"
if [ "$PIN_RED" = "__RED__" ] || [ "$PIN_FIX" = "__FIX__" ] || [ "$PIN_FINAL" = "__FINAL__" ] || [ "$PIN_TIP" = "__TIP__" ]; then
    fail "AC11.0 the 089c red/fix/final/tip SHAs are not pinned yet"
else
    for s in "$PIN_BASE" "$PIN_RED" "$PIN_FIX" "$PIN_FINAL" "$PIN_TIP"; do
        full40 "$s" || fail "AC11.1 pin '$s' is not a full 40-character SHA"
        G cat-file -e "$s^{commit}" 2>/dev/null && pass "AC11.1 pin $s exists" || fail "AC11.1 pin $s does not exist"
    done
    [ "$(G rev-parse "$PIN_RED^" 2>/dev/null)" != "" ] && G merge-base --is-ancestor "$PIN_BASE" "$PIN_RED" && G merge-base --is-ancestor "$PIN_RED" "$PIN_FIX" \
        && G merge-base --is-ancestor "$PIN_FIX" "$PIN_FINAL" && G merge-base --is-ancestor "$PIN_FINAL" "$PIN_TIP" && G merge-base --is-ancestor "$PIN_TIP" HEAD \
        && pass "AC11.2 BASE < RED < FIX <= FINAL <= TIP <= HEAD (ancestry)" || fail "AC11.2 the pins are not in ancestry order"
    red_files="$(G diff --name-only "$PIN_BASE" "$PIN_RED" 2>/dev/null | grep -vx -e docs/tasks/089-closed-verify-sweep-registry.md -e docs/tasks/089c-closed-verify-sweep-registry-c.md | sort | tr '\n' ' ')"
    [ "$red_files" = "docs/tasks/089c-verify.sh " ] && pass "AC11.3 the red commit touches only 089c-verify.sh and the task files" || fail "AC11.3 the red commit touches: $red_files"
    fix_files="$(G diff --name-only "$PIN_RED" "$PIN_FIX" 2>/dev/null | grep -vx -e docs/tasks/089c-closed-verify-sweep-registry-c.md | sort | tr '\n' ' ')"
    [ "$fix_files" = "docs/tasks/069-verify.sh " ] && pass "AC11.4 the fix commit touches only 069-verify.sh (and the task file)" || fail "AC11.4 the fix commit touches: $fix_files"
    if ! scope_files="$(G diff --name-only "$PIN_BASE" "$PIN_TIP" 2>&1)"; then fail "AC11.5 cannot compute $PIN_BASE..$PIN_TIP"; else
        extra="$(printf '%s\n' "$scope_files" | grep -vxE 'docs/tasks/069-verify\.sh|docs/tasks/089c-verify\.sh|docs/tasks/089c-closed-verify-sweep-registry-c\.md|docs/tasks/089-closed-verify-sweep-registry\.md' | tr '\n' ' ')"
        [ -n "$scope_files" ] && [ -z "$extra" ] && pass "AC11.5 BASE..TIP stays inside the declared file scope (069-verify.sh, 089c-verify.sh, the task files)" || fail "AC11.5 out-of-scope files in BASE..TIP (or the range is empty): $extra"
    fi
    last_src="$(G log -1 --format=%H "$PIN_BASE..$PIN_TIP" -- docs/tasks/069-verify.sh docs/tasks/089c-verify.sh 2>/dev/null)"
    [ -n "$last_src" ] && [ "$last_src" = "$(G rev-parse "$PIN_FINAL^{commit}" 2>/dev/null)" ] && pass "AC11.6a FINAL is the last commit in BASE..TIP that touched a source or script file" || fail "AC11.6 FINAL ${PIN_FINAL:0:12} is not the last source-touching commit (that is ${last_src:0:12})"
    if ! tail_files="$(G diff --name-only "$PIN_FINAL" "$PIN_TIP" 2>&1)"; then fail "AC11.6 cannot compute FINAL..TIP"
    elif [ -z "$(printf '%s\n' "$tail_files" | grep -vE '^docs/tasks/089c-closed-verify-sweep-registry-c\.md$')" ]; then pass "AC11.6b FINAL..TIP touches only the 089c task file"
    else fail "AC11.6 FINAL..TIP touches: $(printf '%s' "$tail_files" | tr '\n' ' ')"; fi
    # hunk limit: 069-verify.sh changes only the PIN064 definition and the AC5.3 check (comments aside)
    nonc() { G diff -U0 "$PIN_RED" "$PIN_FIX" -- "$1" | grep -E '^[+-][^+-]' | grep -vE '^[+-][[:space:]]*#' ; }
    npin=$(G diff -U0 "$PIN_RED" "$PIN_FIX" -- docs/tasks/069-verify.sh | grep -cE '^\+[^+].*PIN064')
    d069="$(nonc docs/tasks/069-verify.sh | grep -vE 'PIN064|AC5\.3|034\.real|c33_judge|origin/task/064|^[+-][[:space:]]*(else|fi)$' | wc -l)"
    [ "$d069" = 0 ] && [ "$npin" -ge 2 ] && pass "AC11.7 069-verify.sh changed only in the PIN064 pin and the AC5.3 check ($npin added PIN064 line(s), 0 other)" || fail "AC11.7 069-verify.sh changed outside AC5.3 and the pin ($d069 line(s)), or the pin is not added ($npin)"
    # after TIP only the pin commit(s) and the log: 089c-verify.sh changes only its PIN_* lines, no other file but the task file
    post_files="$(G diff --name-only "$PIN_TIP" HEAD 2>/dev/null | grep -vx docs/tasks/089c-closed-verify-sweep-registry-c.md | sort | tr '\n' ' ')"
    [ -z "$post_files" ] || [ "$post_files" = "docs/tasks/089c-verify.sh " ] && pass "AC11.9a TIP..HEAD touches only 089c-verify.sh and the task file" || fail "AC11.9a TIP..HEAD touches: $post_files"
    npost=$(G diff -U0 "$PIN_TIP" HEAD -- docs/tasks/089c-verify.sh | grep -E '^[+-][^+-]' | wc -l)
    nother=$(G diff -U0 "$PIN_TIP" HEAD -- docs/tasks/089c-verify.sh | grep -E '^[+-][^+-]' | grep -vcE '^[+-]PIN_(RED|FIX|FINAL|TIP)=')
    [ "$nother" = 0 ] && [ "$npost" -ge 1 ] && pass "AC11.9b TIP..HEAD changes only the PIN_* lines of 089c-verify.sh ($npost changed line(s), 0 other)" || fail "AC11.9b 089c-verify.sh changed after TIP outside the PIN_* lines ($nother line(s)) or the pins were not written ($npost)"
    bash -n <(G show "$PIN_FIX:docs/tasks/069-verify.sh") 2>/dev/null && pass "AC11.8 069-verify.sh at the fix commit passes bash -n" || fail "AC11.8 069-verify.sh at the fix commit does not parse"
fi

# ==================================================================================================
else
section "AC4 mutations (the fixed check widened; each red and only AC5.3; the controls green)"
if [ "$NEW_OK" != 1 ] || [ ! -s "$NEWD/069.trunc.sh" ]; then fail "AC4.0 the NEW 069-verify.sh is not readable: no mutation can be built"
else
P064=$(pin_of "$NEWD/069.sh" PIN064); [ -n "$P064" ] || fail "AC4.0 cannot read PIN064 from the NEW 069-verify.sh"
mut_run() {   # mut_run LABEL FRAME(dir) OLD NEW REGEX : mutate the truncated NEW script, run it in FRAME; red, and only that check
    local label="$1" d="$2" old="$3" new="$4" re="$5" rc nfail
    cp "$NEWD/069.trunc.sh" "$d/$TRUNC"
    edit_file "$d/$TRUNC" "$old" "$new" || { fail "$label: the mutation did not apply (pattern not found exactly once)"; return; }
    rc=$(run_in "$d" "$TMP/mut.out" bash "$TRUNC"); nfail=$(grep -c '^FAIL  ' "$TMP/mut.out")
    if [ "$rc" != 0 ] && grep -Eq "$re" "$TMP/mut.out" && [ "$nfail" = 1 ]; then pass "$label turns red, and only that check: exit $rc, $(grep '^FAIL' "$TMP/mut.out" | head -n1 | cut -c1-120)"
    else fail "$label: exit $rc, $nfail FAIL line(s) (want exactly 1 matching /$re/): $(first_fail "$TMP/mut.out")"; fi
}
# m1: widened back to the branch ref. Branch deleted: red. Branch present (control): green, i.e. the branch is the only difference.
if mk_frame "$TMP/m1" "$HEADREV" deleted; then
    mut_run "AC4.m1 the pin widened back to origin/task/064-schema-check-end-anchor, branch deleted" "$TMP/m1" "PIN064=\"$P064\"" "PIN064=\"$BRANCH_REF\"" '^FAIL  AC5\.3 pinned commit'
else fail "AC4.m1 cannot build the frame"; fi
if mk_frame "$TMP/m1c" "$HEADREV" present; then
    cp "$NEWD/069.trunc.sh" "$TMP/m1c/$TRUNC"; edit_file "$TMP/m1c/$TRUNC" "PIN064=\"$P064\"" "PIN064=\"$BRANCH_REF\"" && rc=$(run_in "$TMP/m1c" "$TMP/m1c.out" bash "$TRUNC")
    expect "AC4.m1c control: the same widened script with the branch PRESENT is green (the branch is the only difference)" green "${rc:-1}" "$TMP/m1c.out" '^PASS  AC5\.3 '
else fail "AC4.m1c cannot build the frame"; fi
# m2: widened to HEAD, on a merge with a later branch that edited 034-verify.sh: red (the later edit is read as if it were 064's)
if mk_later "$TMP/m2" "$HEADREV" deleted "$L_FILE" "$L_OLD" "$L_NEW"; then
    mut_run "AC4.m2 the pin widened to HEAD, on HEAD merged with a later branch editing 034-verify.sh" "$TMP/m2" "PIN064=\"$P064\"" 'PIN064="HEAD"' '^FAIL  AC5\.3 the actual 064 034-verify\.sh at HEAD is not accepted'
else fail "AC4.m2 cannot build the later-branch merge"; fi
# m3: the guard removed: AC5.3's `fail` line (the else branch) becomes a no-op. With each unreadable pin the expected `FAIL AC5.3` must then
# be ABSENT (rc 0, no AC5.3 verdict): i.e. the AC3.1-3.3 detector set reddens when the guard is removed, so it does bite on 069's own line.
GUARD='fail "AC5.3 pinned commit $PIN064 (task 064'"'"'s FINAL) or its docs/tasks/034-verify.sh cannot be read in this clone"'
NOFILE_COMMIT="$(G rev-list --max-parents=0 "$OLDREF" 2>/dev/null | head -n1)"
for bad in deadbee deadbeefdeadbeefdeadbeefdeadbeefdeadbeef "${NOFILE_COMMIT:-0}"; do
    if mk_frame "$TMP/m3" "$HEADREV" deleted; then
        rm -f "$TMP/m3.out"
        cp "$NEWD/069.trunc.sh" "$TMP/m3/$TRUNC"
        if edit_file "$TMP/m3/$TRUNC" "PIN064=\"$P064\"" "PIN064=\"$bad\"" && edit_file "$TMP/m3/$TRUNC" "$GUARD" ':'; then
            rc=$(run_in "$TMP/m3" "$TMP/m3.out" bash "$TRUNC")
            if [ "$rc" = 0 ] && ! grep -Eq '^FAIL  AC5\.3 ' "$TMP/m3.out" && ! grep -Eq '^PASS  AC5\.3 ' "$TMP/m3.out"; then
                pass "AC4.m3 guard removed, PIN064=${bad:0:12}: exit 0 and the expected 'FAIL AC5.3' is absent (the AC3 detector would redden)"
            else fail "AC4.m3 guard removed, PIN064=${bad:0:12}: the expected FAIL AC5.3 is still produced or the run is not silent (exit $rc): $(first_fail "$TMP/m3.out")"; fi
        else fail "AC4.m3 the guard-removal mutation did not apply (pattern not found exactly once)"; fi
    else fail "AC4.m3 cannot build the frame"; fi
done
# control: the unmutated NEW script on the later-branch merge stays green
if mk_later "$TMP/m4" "$HEADREV" deleted "$L_FILE" "$L_OLD" "$L_NEW"; then
    place "$TMP/m4" "$NEWD/069.trunc.sh" "$TRUNC"; rc=$(run_in "$TMP/m4" "$TMP/m4.out" bash "$TRUNC")
    expect "AC4.m4 control: unmutated NEW on the later-branch merge stays green" green "$rc" "$TMP/m4.out" "^PASS  AC5\\.3 .*$P064" '!^FAIL'
else fail "AC4.m4 cannot build the frame"; fi
fi
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
