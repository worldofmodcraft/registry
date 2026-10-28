#!/usr/bin/env bash
#
# 089a2-verify.sh -- the runnable verification artefact for task 089a2 (MANAGER.md Section 2c), part A2 of umbrella 089.
#
# Task 089a2: three closed registry checks measured a moving frame instead of their task's own change:
#   finding 6  057-verify.sh T1 (via 057-textchecks.py)  "docs/contracts/README.md names task 057" read the README at HEAD; a later
#                                  task may reword it. T1 now writes the README blob AT 057's pinned FINAL commit with `git show`
#                                  and passes it with --readme (the textchecks default path stays, for live use).
#   S2         057-verify.sh A1    read ADR-0121's status from the working copy /home/ludwig/wom (a hard-coded path, on one machine
#                                  only). The registry history never contained an ADR (asserted below), so Q4 option B applies:
#                                  a fixture blob (the ADR's title and Status lines at platform commit 84064c9cf1c858844477701f32f42adea438bc6b,
#                                  git blob 16064b511c422acca2d3f628bdfa7614c85440e6) embedded in 057-verify.sh. No path, no env var.
#   F1 (fix round 1, scope extended by the manager, session 14): 062-verify.sh AC4 mutates 057-verify.sh with the literals
#              'BASE_COMMIT="a50daac"' / 'FINAL_COMMIT="3ab8f43"'; widening 057's pins to 40 characters made them occur 0 times, so 062 went
#              red. 062's 057-mutation literals (that block only) now name the full SHAs; AC1.X below cross-checks every literal against 057.
#   S3         070-verify.sh header   said "ten closed scripts"; the script iterates twelve (derived from its CLOSED list, asserted).
# Demonstrates acceptance criteria 1-5, 7, 9 (the mechanism) and 11 of docs/tasks/089a2-closed-verify-sweep-registry-a2.md (umbrella 089),
# restricted to finding 6, S2 and S3. The long sequential runs (057-verify.sh whole, 070-verify.sh whole, one at a time on a quiet
# machine, on HEAD and on HEAD + a later branch) are done by hand and logged; `--later-clone DIR` builds that merge for them.
#
# Usage:  docs/tasks/089a2-verify.sh [--mutate] [--own-only] [--later-clone DIR]      (any cwd inside the repository)
#   (no flag)   AC0 (pins re-derived from the merge commit; static greps), AC1 (RED FIRST: a later branch rewords the README; the OLD
#               057-verify.sh reddens, the NEW stays green; S2 and S3 red on OLD, green on NEW), AC3 (deadbee is a FAIL, no skips),
#               AC5 (item-12 control: NEW 057 green on HEAD and on HEAD + later branch), AC11 (own change on fixed SHAs, never HEAD).
#   --mutate    AC4: each fixed check widened back / broken in a temp copy, on a later-branch merge: red, and only that check.
#   --own-only  only the AC0 and AC11 sections (static, no clones run).
#   --later-clone DIR  build DIR = a clone at HEAD + a --no-ff merge of a synthetic later branch that rewrites the README, print it, exit 0.
# Everything runs on the COMMITTED state in temporary clones; the caller's worktree is never modified. The scripts under test are
# read as blobs of the pinned commits below (OLD = registry main when 089a2 was cut, NEW = the part's final commit), never from HEAD.
# 057-verify.sh is run in the TRUNCATED form (everything before its "-- text mutations" line): finding 6 and S2 are all before it; the
# oracle, Ajv and unittest sections are the hours-long part, run by hand (task log). The truncation point is asserted (exactly one marker).
# Quiet machine (criterion 9): before EVERY child run the script waits (up to six hours) until no other docs/tasks/*-verify.sh process
# runs, and logs the `ps` reading; a wait that times out is a FAIL, never a skip.
# Network: none. Exit code: the number of failed checks. Requires: git, python3 (and nothing else: node is not needed here).

set -u
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1

MUTATE=0
OWN=0
LATERDIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --mutate) MUTATE=1 ;;
        --own-only) OWN=1 ;;
        --later-clone) shift; LATERDIR="${1:-}"; [ -n "$LATERDIR" ] || { echo "--later-clone needs a directory" >&2; exit 99; } ;;
        *) echo "unknown argument: $1" >&2; exit 99 ;;
    esac
    shift
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }
GITID=(-c user.name=verify089a2 -c user.email=verify089a2@invalid -c commit.gpgsign=false)
HEADREV="$(git -C "$ROOT" rev-parse HEAD)"
G() { git -C "$ROOT" "$@"; }

S057=docs/tasks/057-verify.sh
S070=docs/tasks/070-verify.sh
TXC=docs/tasks/057-textchecks.py
TRUNC057=docs/tasks/057-trunc.sh

# Fixed SHAs (full 40 characters). OLD = registry main when 089a2 was cut (the unfixed scripts); the frame of every own-change
# check below is one of these, never HEAD (REVIEW-CHECKLIST item 12).
OLDREF="32c641b5f56139a86c820f0b16d522c0f991d207"
# 089a2's own commits (AC11). Filled in by the pin commit after the red and fix commits exist.
PIN_BASE="32c641b5f56139a86c820f0b16d522c0f991d207"   # registry main when 089a2 was cut
PIN_RED="42d7d46c9081c11f217e50c4be21f93f3b5e022e"      # 089a2-verify.sh + task files only
PIN_FIX="672edcd971fdf74e0a827fa4255f87cfcbb02cbe"      # 057-verify.sh, 057-textchecks.py, 070-verify.sh
PIN_RED2="__RED2__"    # fix round 1, fixtures first: 089a2-verify.sh + task files only (the 062 cross-check, exact 057 hunk list)
PIN_FIX2="__FIX2__"    # fix round 1: 062-verify.sh only (the 057 mutation literals)
PIN_FINAL="__FINAL__"  # last commit touching a source file or script of the part (= PIN_FIX2; the NEW blobs are read here)
PIN_TIP="__TIP__"      # last commit of the branch before the pin commit (task-file only after FINAL)

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT

# ---------------------------------------------------------------------------------------------------------------------
# helpers
edit_py="$TMP/edit.py"
cat > "$edit_py" <<'PY'
import re, sys
mode, p, old, new = sys.argv[1:5]
s = open(p, encoding="utf-8").read()
if mode == "lit":
    if s.count(old) != 1:
        sys.exit("edit.py: pattern found %d times in %s (expected exactly 1): %r" % (s.count(old), p, old[:80]))
    s = s.replace(old, new, 1)
else:   # "re": every match replaced, at least one required
    s, n = re.subn(old, new, s)
    if n < 1:
        sys.exit("edit.py: regex matched nothing in %s: %r" % (p, old[:80]))
open(p, "w", encoding="utf-8").write(s)
PY
edit_file() { python3 -I "$edit_py" lit "$1" "$2" "$3"; }      # edit_file FILE OLD NEW : exactly one occurrence
edit_re() { python3 -I "$edit_py" re "$1" "$2" "$3"; }          # edit_re FILE REGEX NEW : at least one match, all replaced

pin_of() { sed -n "s/^$2=\"\{0,1\}\([0-9a-f]\{7,\}\)\"\{0,1\}\([[:space:]].*\)\{0,1\}$/\1/p" "$1" | head -n1; }
full40() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }
first_fail() { grep -E '^FAIL' "$1" | head -n"${2:-4}" | cut -c1-140 | tr '\n' '|'; }
# expect LABEL green|red|has RC OUTFILE REGEX... : green = rc 0; red = rc != 0; has = any rc (used for the OLD scripts, whose other checks
# may depend on the machine); every REGEX must match (a leading '!' demands absence)
expect() {
    local label="$1" want="$2" rc="$3" out="$4" re miss=""; shift 4
    for re in "$@"; do
        if [ "${re:0:1}" = "!" ]; then grep -Eq "${re:1}" "$out" && miss="$miss /$re/"
        else grep -Eq "$re" "$out" || miss="$miss /$re/"; fi
    done
    if [ "$want" = green ] && [ "$rc" = 0 ] && [ -z "$miss" ]; then pass "$label: exit 0"
    elif [ "$want" = red ] && [ "$rc" != 0 ] && [ -z "$miss" ]; then pass "$label: exit $rc, $(grep -E '^FAIL' "$out" | head -n1 | cut -c1-120)"
    elif [ "$want" = has ] && [ -z "$miss" ]; then pass "$label: exit $rc, as expected"
    else fail "$label: wanted $want, got exit $rc$miss: $(first_fail "$out")"; fi
}

# quiet machine (criterion 9): no other docs/tasks/*-verify.sh process (this script and its own children are not counted: children are
# only started after this predicate was evaluated, one at a time)
others_list() { ps -eo pid,args 2>/dev/null | grep -E 'docs/tasks/[^ ]*-verify\.sh' | grep -v grep | grep -v '089a2-verify\.sh'; }
wait_quiet() {   # wait_quiet LABEL : log the ps reading; wait up to six hours; return 1 on timeout
    local waited=0 n
    n=$(others_list | grep -c .)
    printf '      ps[%s]: %s other *-verify.sh process(es) before this run%s\n' "$1" "$n" "$([ "$n" != 0 ] && printf ': %s' "$(others_list | head -n3 | cut -c1-100 | tr '\n' '|')")" >&2
    while [ "$(others_list | grep -c .)" != 0 ]; do
        [ "$waited" -ge 21600 ] && return 1
        sleep 10; waited=$((waited + 10))
    done
    [ "$n" != 0 ] && printf '      ps[%s]: quiet after waiting %ss\n' "$1" "$waited" >&2
    return 0
}

# blobs of the scripts under test
OLDD="$TMP/old"; NEWD="$TMP/new"; mkdir -p "$OLDD" "$NEWD"
for s in 057 070 062; do
    G show "$OLDREF:docs/tasks/$s-verify.sh" > "$OLDD/$s.sh" 2>/dev/null || fail "AC0.0 cannot read $s-verify.sh at OLD $OLDREF"
    if full40 "$PIN_FINAL"; then
        G show "$PIN_FINAL:docs/tasks/$s-verify.sh" > "$NEWD/$s.sh" 2>/dev/null || fail "AC0.0 cannot read $s-verify.sh at the final commit $PIN_FINAL"
    else : > "$NEWD/$s.sh"; fi
done
G show "$OLDREF:$TXC" > "$OLDD/textchecks.py" 2>/dev/null || fail "AC0.0 cannot read $TXC at OLD $OLDREF"
if full40 "$PIN_FINAL"; then G show "$PIN_FINAL:$TXC" > "$NEWD/textchecks.py" 2>/dev/null || fail "AC0.0 cannot read $TXC at the final commit"; else : > "$NEWD/textchecks.py"; fi
full40 "$PIN_FINAL" || fail "AC0.0 the final commit is not pinned yet (PIN_FINAL=$PIN_FINAL): the NEW scripts cannot be read"

# trunc_057 FILE : print FILE up to (not including) its "-- text mutations" line, then a closing line. Fails (empty output) unless the marker occurs exactly once.
trunc_057() {
    [ "$(grep -c '^echo "-- text mutations' "$1")" = 1 ] || return 1
    awk '/^echo "-- text mutations/{exit} {print}' "$1"
    printf '%s\n' "printf '\\n== RESULT ==\\n'; exit \"\$FAILURES\""
}
trunc_057 "$OLDD/057.sh" > "$OLDD/057.trunc.sh" || fail "AC0.0b the OLD 057-verify.sh has no single text-mutations marker"
trunc_057 "$NEWD/057.sh" > "$NEWD/057.trunc.sh" || fail "AC0.0b the NEW 057-verify.sh has no single text-mutations marker"

# mk_frame DEST REV : a clone detached at REV
mk_frame() {
    git clone -q --no-hardlinks "$ROOT" "$1" 2>/dev/null || return 1
    git -C "$1" checkout -q --detach "$2" || return 1
}
# mk_later DEST REV FILE REGEX NEW : a clone at REV plus a --no-ff merge of a synthetic later branch that rewrites FILE (REGEX -> NEW, every match, at least one)
mk_later() {
    mk_frame "$1" "$2" || return 1
    git -C "$1" checkout -q -b later-branch || return 1
    edit_re "$1/$3" "$4" "$5" || return 1
    git -C "$1" "${GITID[@]}" commit -q -am "synthetic later branch: edit $3" || return 1
    git -C "$1" checkout -q --detach "$2" || return 1
    git -C "$1" "${GITID[@]}" merge --no-ff -q -m "merge of the synthetic later branch ($3)" later-branch >/dev/null 2>&1 || return 1
}
run_in() {   # run_in DIR OUTFILE CMD... : (quiet machine first) run CMD in DIR, output to OUTFILE; echo the exit code (98 = machine never quiet)
    local d="$1" o="$2"; shift 2
    if ! wait_quiet "$(basename "$o")"; then echo "no quiet machine after six hours" > "$o"; echo 98; return; fi
    ( cd "$d" && PYTHONDONTWRITEBYTECODE=1 "$@" ) > "$o" 2>&1
    echo $?
}
# place DIR SRCFILE DESTRELPATH : put an (untracked) copy of a script into the clone
place() { cp "$2" "$1/$3"; }

# --- the later branch: a legitimate README edit by a later task (every mention of task 057 reworded)
RD_RE='(?i)task 057'
RD_NEW='task 0xx'
README=docs/contracts/README.md

if [ -n "$LATERDIR" ]; then
    mk_later "$LATERDIR" "$HEADREV" "$README" "$RD_RE" "$RD_NEW" || { echo "cannot build the later-branch clone" >&2; exit 99; }
    echo "$LATERDIR  (HEAD $HEADREV + a --no-ff merge of a synthetic later branch that rewrites every 'task 057' in $README)"
    exit 0
fi

# F1 cross-script check: every literal 062-verify.sh's AC4 block applies to 057-verify.sh must occur in the 057 blob (exactly once for the
# "one" mutations of the block; at least once for the AC5 "all" mutation). cross062 FILE062 FILE057 : X_WHY describes, rc 0 good, 1 mismatch, 2 broken search
cat > "$TMP/cross.py" <<'PYX'
import re, sys
t62 = open(sys.argv[1], encoding="utf-8").read()
t57 = open(sys.argv[2], encoding="utf-8").read()
m = re.search(r"(?m)^f=docs/tasks/057-verify\.sh$(.*?)^# ---- ", t62, re.S)
if not m:
    print("no 057 block found in 062-verify.sh"); sys.exit(2)
lit = re.findall(r"mutate \$f '([^']*)'", m.group(1))
allm = re.findall(r"(?m)^mutate docs/tasks/057-verify\.sh '([^']*)'", t62)
if len(lit) < 4 or len(allm) < 1:
    print("too few literals extracted (%d block, %d all): a search that finds nothing is broken" % (len(lit), len(allm))); sys.exit(2)
bad = [l for l in lit if t57.count(l) != 1] + [l for l in allm if t57.count(l) < 1]
print("%d block literal(s) + %d AC5 literal(s); not matching: %s" % (len(lit), len(allm), bad if bad else "none"))
sys.exit(1 if bad else 0)
PYX
cross062() { X_WHY="$(python3 -I "$TMP/cross.py" "$1" "$2")"; return $?; }

# S3 helper: s3_check FILE : the header of a 070-verify.sh blob names the number of closed scripts its CLOSED list holds (and iterates)
num_word() { case "$1" in 10) echo ten ;; 11) echo eleven ;; 12) echo twelve ;; 13) echo thirteen ;; 14) echo fourteen ;; 15) echo fifteen ;; 16) echo sixteen ;; *) return 1 ;; esac; }
S3_WHY=""
s3_check() {
    local f="$1" n w right stale
    n=$(sed -n 's/^CLOSED="\([^"]*\)".*/\1/p' "$f" | wc -w)
    [ "$n" -gt 0 ] || { S3_WHY="no CLOSED list found (a search that finds nothing is broken)"; return 1; }
    [ "$(grep -c 'for n in \$CLOSED; do' "$f")" -ge 1 ] || { S3_WHY="the script does not iterate \$CLOSED"; return 1; }
    w=$(num_word "$n") || { S3_WHY="count $n has no word in the table"; return 1; }
    right=$(sed -n '1,25p' "$f" | grep -c "$w closed scripts")
    stale=$(sed -n '1,25p' "$f" | grep -Eic '(ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen) closed scripts')
    [ "$right" -ge 2 ] && [ "$right" = "$stale" ] || { S3_WHY="CLOSED holds $n scripts ($w) but the header names that number $right time(s) of $stale count mention(s)"; return 1; }
    S3_WHY="CLOSED holds $n scripts, the header says '$w closed scripts' $right time(s), no other count"
    return 0
}

# ==================================================================================================
if [ "$MUTATE" = 0 ]; then

section "AC0 -- pins re-derived from the merge commit; own-change checks read the pinned FINAL, not HEAD"
merge_of() { G log --first-parent --merges --format=%H -E --grep="^Merge pull request #[0-9]+ from worldofmodcraft/task/$1\$" "$OLDREF" | head -n2; }
n=$(merge_of 057-version-lifecycle | wc -l)
[ "$n" = 1 ] && pass "AC0.1 exactly one merge commit for task/057-version-lifecycle: $(merge_of 057-version-lifecycle)" || fail "AC0.1 task/057-version-lifecycle: expected exactly one merge commit on main, found $n"
M057=$(merge_of 057-version-lifecycle)
f057=$(pin_of "$NEWD/057.sh" FINAL_COMMIT); b057=$(pin_of "$NEWD/057.sh" BASE_COMMIT)
o_f057=$(pin_of "$OLDD/057.sh" FINAL_COMMIT); o_b057=$(pin_of "$OLDD/057.sh" BASE_COMMIT)
if [ -z "$f057" ] || [ -z "$b057" ] || [ -z "$M057" ] || [ -z "$o_f057" ] || [ -z "$o_b057" ]; then
    fail "AC0.2 cannot read a pin or find the merge (057 NEW FINAL='$f057' BASE='$b057', OLD FINAL='$o_f057' BASE='$o_b057'): a search that finds nothing is broken"
else
    for p in "$f057" "$b057"; do full40 "$p" || fail "AC0.2 pin '$p' is not a full 40-character SHA"; done
    [ "$f057" = "$(G rev-parse "$M057^2")" ] && pass "AC0.3 057 FINAL_COMMIT=$f057 is PR #8's last commit (git rev-parse $M057^2)" || fail "AC0.3 057 FINAL_COMMIT=$f057 is not $M057^2"
    [ "$b057" = "$(G merge-base "$M057^1" "$M057^2")" ] && pass "AC0.4 057 BASE_COMMIT=$b057 is PR #8's fork point (git merge-base $M057^1 $M057^2)" || fail "AC0.4 057 BASE_COMMIT=$b057 is not the fork point"
    [ "$(G rev-parse "$o_f057^{commit}" 2>/dev/null)" = "$f057" ] && [ "$(G rev-parse "$o_b057^{commit}" 2>/dev/null)" = "$b057" ] \
        && pass "AC0.5 the OLD short pins ($o_b057, $o_f057) expand to exactly the NEW full pins: the range did not move" || fail "AC0.5 the OLD short pins do not expand to the NEW full pins"
fi
cnt() { grep -cF -- "$2" "$1"; }
[ "$(cnt "$NEWD/057.sh" 'git show "$FINAL_COMMIT:docs/contracts/README.md"')" -ge 1 ] && [ "$(cnt "$NEWD/057.sh" 'textchecks.py --readme "$README_BLOB"')" -ge 1 ] \
    && [ "$(grep -v '^[[:space:]]*#' "$NEWD/057.sh" | grep -F 'textchecks.py' | grep -vc -e '--readme' -e '--old-present')" = 0 ] \
    && pass "AC0.6 057 T1 reads the README with git show \"\$FINAL_COMMIT:...\" and passes it with --readme; every other textchecks call in 057-verify.sh is the --old-present control" \
    || fail "AC0.6 057 T1 does not read the README at FINAL_COMMIT / pass --readme (or an un-flagged textchecks call remains)"
[ "$(grep -v '^[[:space:]]*#' "$OLDD/057.sh" | grep -F 'textchecks.py' | grep -vc -e '--readme' -e '--old-present')" -ge 1 ] \
    && pass "AC0.6b positive control: the OLD 057-verify.sh has a textchecks call with neither --readme nor --old-present (the defect the grep finds)" || fail "AC0.6b the grep cannot find the OLD defect"
[ "$(grep -v '^[[:space:]]*#' "$NEWD/057.sh" | grep -cE '/ho[m]e/|PLATFORM_REPO|git -C ')" = 0 ] && [ "$(grep -v '^[[:space:]]*#' "$OLDD/057.sh" | grep -cE '/ho[m]e/|PLATFORM_REPO')" -ge 1 ] \
    && pass "AC0.7 S2: no working-copy path, PLATFORM_REPO or git -C read remains in the NEW 057-verify.sh (code lines); the OLD one has them (positive control)" || fail "AC0.7 S2: the NEW 057-verify.sh still names a working copy, or the OLD one does not (the grep is broken)"
[ "$(cnt "$NEWD/057.sh" "Status:** Accepted (Ludwig, in session, 2026-10-15")" -ge 1 ] && [ "$(cnt "$NEWD/057.sh" 'ADR0121')" -ge 2 ] \
    && pass "AC0.8 S2: the NEW 057-verify.sh carries the ADR-0121 fixture blob (Status line and heredoc markers)" || fail "AC0.8 S2: no ADR-0121 fixture in the NEW 057-verify.sh"
# Q4: option A needs a history the script can reach; the registry's never held an ADR, so option B (fixture) is the right one. A search that finds nothing is broken: the same command on docs/tasks must find commits.
na=$(G log --all --format=%H -- 'docs/decisions' 'docs/decisions/0121-version-lifecycle-pending.md' | wc -l); nt=$(G log --all --format=%H -- docs/tasks | wc -l)
[ "$na" = 0 ] && [ "$nt" -gt 0 ] && pass "AC0.9 Q4: no commit of any ref of this repository ever touched docs/decisions ($na); the same search on docs/tasks finds $nt commits (positive control): option B, fixture blob" || fail "AC0.9 Q4: docs/decisions history found ($na commits) or the control search is empty ($nt)"
for s in 057 070 062; do bash -n "$NEWD/$s.sh" && pass "AC0.10 NEW $s-verify.sh passes bash -n" || fail "AC0.10 NEW $s-verify.sh has a syntax error"; done
python3 -I -c 'import ast,sys; ast.parse(sys.stdin.read())' < "$NEWD/textchecks.py" && pass "AC0.11 NEW 057-textchecks.py parses" || fail "AC0.11 NEW 057-textchecks.py does not parse"
bash -n "$NEWD/057.trunc.sh" && [ -s "$NEWD/057.trunc.sh" ] && [ -s "$OLDD/057.trunc.sh" ] \
    && pass "AC0.12 positive control: both truncated 057 copies are non-empty and the NEW one parses ($(wc -l < "$OLDD/057.trunc.sh") / $(wc -l < "$NEWD/057.trunc.sh") lines)" || fail "AC0.12 a truncated 057 copy is empty or does not parse"

if [ "$OWN" = 0 ]; then
section "AC1 -- red first: a later branch rewrites the README; the OLD 057-verify.sh fails and names T1, the NEW one passes"
# ---- finding 6: the later branch rewrites every 'task 057' in docs/contracts/README.md
if ! mk_later "$TMP/o6" "$OLDREF" "$README" "$RD_RE" "$RD_NEW"; then fail "AC1.6.0 cannot build the later-branch merge on OLD"; else
    place "$TMP/o6" "$OLDD/057.trunc.sh" "$TRUNC057"; rc=$(run_in "$TMP/o6" "$TMP/o6.out" bash "$TRUNC057")
    expect "AC1.6a the OLD 057-verify.sh (truncated) on OLD + a later README edit" red "$rc" "$TMP/o6.out" '^FAIL  required/readme-names-057: ' '^FAIL  T1 ' '^PASS  T2 '
fi
if mk_frame "$TMP/c6" "$OLDREF"; then
    place "$TMP/c6" "$OLDD/057.trunc.sh" "$TRUNC057"; rc=$(run_in "$TMP/c6" "$TMP/c6.out" bash "$TRUNC057")
    expect "AC1.6b control: the OLD 057-verify.sh (truncated) on plain OLD (the later branch is the cause; A1 depends on the machine, so only T1 is judged)" has "$rc" "$TMP/c6.out" '^PASS  T1 ' '!^FAIL  T1 ' '!^FAIL  required/'
else fail "AC1.6.1 cannot clone OLD"; fi
if ! mk_later "$TMP/n6" "$HEADREV" "$README" "$RD_RE" "$RD_NEW"; then fail "AC1.6.2 cannot build the later-branch merge on HEAD"; else
    place "$TMP/n6" "$NEWD/057.trunc.sh" "$TRUNC057"; rc=$(run_in "$TMP/n6" "$TMP/n6.out" bash "$TRUNC057")
    expect "AC1.6c the NEW 057-verify.sh (truncated) on HEAD + the same later README edit" green "$rc" "$TMP/n6.out" '^PASS  T1 ' '^PASS  T2 ' '!^FAIL'
    # the later branch really removed the sentence from the README the OLD check would read
    [ "$(git -C "$TMP/n6" show HEAD:"$README" | grep -ci 'task 057')" = 0 ] && [ "$(G show "$PIN_FINAL:$README" | grep -ci 'task 057')" -ge 1 ] \
        && pass "AC1.6d the merged HEAD README has 0 'task 057' mentions while the README at 057's FINAL has $(G show "$PIN_FINAL:$README" | grep -ci 'task 057') (the fixture is real, the pinned blob unaffected)" || fail "AC1.6d the later branch did not remove the mentions, or the README at FINAL does not carry them"
fi
# ---- S2: the ADR status without a working copy of the platform repo
NOPLAT="$TMP/no-platform-checkout"
if mk_frame "$TMP/o2" "$OLDREF"; then
    place "$TMP/o2" "$OLDD/057.trunc.sh" "$TRUNC057"; rc=$(PLATFORM_REPO="$NOPLAT" run_in "$TMP/o2" "$TMP/o2.out" bash "$TRUNC057")
    expect "AC1.2a the OLD 057-verify.sh on a machine whose platform checkout is absent (PLATFORM_REPO=nonexistent)" red "$rc" "$TMP/o2.out" '^FAIL  A1 ADR-0121 not found or not Accepted'
else fail "AC1.2.0 cannot clone OLD"; fi
if mk_frame "$TMP/n2" "$HEADREV"; then
    place "$TMP/n2" "$NEWD/057.trunc.sh" "$TRUNC057"; rc=$(PLATFORM_REPO="$NOPLAT" run_in "$TMP/n2" "$TMP/n2.out" bash "$TRUNC057")
    expect "AC1.2b the NEW 057-verify.sh with the same absent platform checkout (the variable has no effect)" green "$rc" "$TMP/n2.out" '^PASS  A1 ADR-0121 \(fixture blob' '!^FAIL'
else fail "AC1.2.1 cannot clone HEAD"; fi

section "AC1.S3 -- red first: the 070-verify.sh header count equals the number of closed scripts the script iterates"
if s3_check "$OLDD/070.sh"; then fail "AC1.S3a the OLD 070-verify.sh header already matches its CLOSED list ($S3_WHY): the check is vacuous"; else pass "AC1.S3a the OLD 070-verify.sh header is wrong, as the finding says: $S3_WHY"; fi
if s3_check "$NEWD/070.sh"; then pass "AC1.S3b the NEW 070-verify.sh header is right: $S3_WHY"; else fail "AC1.S3b the NEW 070-verify.sh header is wrong: $S3_WHY"; fi
d070="$(G diff -U0 "$OLDREF" "$PIN_FINAL" -- "$S070" 2>/dev/null)"
nchg=$(printf '%s\n' "$d070" | grep -E '^[+-]' | grep -vcE '^(\+\+\+|---)'); nonc=$(printf '%s\n' "$d070" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vcE '^[+-]#')
maxl=$(printf '%s\n' "$d070" | sed -n 's/^@@ -\([0-9]*\).*/\1/p' | sort -n | tail -n1)
[ "$nchg" -ge 2 ] && [ "$nonc" = 0 ] && [ "${maxl:-99}" -le 25 ] && pass "AC1.S3c git diff of 070-verify.sh OLD..FINAL: $nchg changed line(s), all '#' header comments (last hunk at line $maxl <= 25)" || fail "AC1.S3c 070-verify.sh changed outside its header ($nchg changed, $nonc not comments, last hunk at ${maxl:-?})"
G diff -U0 "$OLDREF" "$PIN_FINAL" -- "$S070" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -E 'ten closed|twelve closed' > "$TMP/s3lines.txt"
[ "$(grep -c '^-.*ten closed' "$TMP/s3lines.txt")" -ge 1 ] && [ "$(grep -c '^+.*twelve closed' "$TMP/s3lines.txt")" -ge 1 ] && pass "AC1.S3d the diff replaces 'ten closed scripts' by 'twelve closed scripts'" || fail "AC1.S3d the diff does not replace ten by twelve"

section "AC1.X -- F1: the literals 062-verify.sh mutates 057-verify.sh with must exist in the NEW 057 (red first: the OLD 062 against the NEW 057)"
cross062 "$OLDD/062.sh" "$OLDD/057.sh"; rcx=$?
[ "$rcx" = 0 ] && pass "AC1.Xa baseline: the OLD 062 literals all occur exactly once in the OLD 057 ($X_WHY)" || fail "AC1.Xa baseline broken: $X_WHY"
cross062 "$OLDD/062.sh" "$NEWD/057.sh"; rcx=$?
[ "$rcx" = 1 ] && pass "AC1.Xb red first: the OLD 062's 057 mutation literals do NOT all occur in the NEW 057, so 062 would print 'the mutation did not apply' ($X_WHY)" || fail "AC1.Xb the OLD 062 literals still fit the NEW 057 (rc $rcx): the finding is not reproduced: $X_WHY"
cross062 "$NEWD/062.sh" "$NEWD/057.sh"; rcx=$?
[ "$rcx" = 0 ] && pass "AC1.Xc the NEW 062's 057 mutation literals each occur exactly once in the NEW 057 ($X_WHY)" || fail "AC1.Xc the NEW 062 literals do not fit the NEW 057: $X_WHY"
# no closed script at FINAL still names 057's short pins as a mutation literal (the grep must be able to match)
printf 'x BASE_COMMIT="a50daac" y\n' > "$TMP/pinctl.txt"
grep -q 'BASE_COMMIT="a50daac"' "$TMP/pinctl.txt" && pass "AC1.Xd positive control: the short-pin grep matches a sample line" || fail "AC1.Xd the short-pin grep cannot match"
short=0
for f in $(G ls-tree --name-only "$PIN_FINAL" docs/tasks/ | grep -E 'docs/tasks/[^/]*-verify\.sh$'); do
    n=$(G show "$PIN_FINAL:$f" | grep -cE '(BASE|FINAL)_COMMIT="(a50daac|3ab8f43)"'); short=$((short + n))
done
[ "$short" = 0 ] && pass "AC1.Xe no closed verify script at FINAL still names 057's short pins as a literal (0 hits over every docs/tasks/*-verify.sh)" || fail "AC1.Xe $short script line(s) at FINAL still name 057's short pins"
fi   # OWN = 0

# ==================================================================================================
if [ "$OWN" = 0 ]; then
section "AC5 -- item-12 control: the NEW 057-verify.sh (truncated) on plain HEAD exits 0 (the unmerged state); on the merge it did so in AC1.6c"
if mk_frame "$TMP/h" "$HEADREV"; then
    place "$TMP/h" "$NEWD/057.trunc.sh" "$TRUNC057"; rc=$(run_in "$TMP/h" "$TMP/h057.out" bash "$TRUNC057")
    expect "AC5.1 NEW 057-verify.sh (truncated) on HEAD" green "$rc" "$TMP/h057.out" '^PASS  A1 ' '^PASS  T1 ' '^PASS  T2 '
else fail "AC5.0 cannot clone HEAD"; fi

section "AC3 -- an unreachable pin (deadbee) is a FAIL naming the check; nothing is skipped"
if mk_frame "$TMP/d" "$HEADREV"; then
    p057=$(pin_of "$NEWD/057.sh" FINAL_COMMIT)
    cp "$NEWD/057.trunc.sh" "$TMP/d/$TRUNC057" && edit_file "$TMP/d/$TRUNC057" "FINAL_COMMIT=\"$p057\"" 'FINAL_COMMIT="deadbee"' && rc=$(run_in "$TMP/d" "$TMP/d057.out" bash "$TRUNC057")
    expect "AC3.1 057 with FINAL_COMMIT=deadbee" red "${rc:-0}" "$TMP/d057.out" '^FAIL  T1 cannot read docs/contracts/README.md at pinned FINAL_COMMIT deadbee' '^FAIL  P0 pinned commit deadbee' '^PASS  A1 '
    printf 'x skipped y\n' > "$TMP/skipctl.txt"
    grep -Eiq 'skip|not evaluated' "$TMP/skipctl.txt" && pass "AC3.2a positive control: the skip-word grep matches a sample line" || fail "AC3.2a the skip-word grep cannot match"
    hits=$(cat "$TMP"/d057.out "$TMP"/h057.out "$TMP"/n6.out "$TMP"/n2.out 2>/dev/null | grep -Eic 'skip|not evaluated')
    [ "$hits" = 0 ] && pass "AC3.2 'skip' / 'not evaluated' occur 0 times in the outputs of the deadbee, HEAD and later-branch runs" || fail "AC3.2 $hits skip/not-evaluated line(s) in the run outputs"
else fail "AC3.0 cannot clone HEAD"; fi
# S3 has no pin to break; its unreachable analogue is a missing CLOSED list (a search that finds nothing), covered by AC4.m-S3c in --mutate.
fi   # OWN = 0

section "AC11 -- 089a2's own change, measured on fixed SHAs (never HEAD)"
if [ "$PIN_RED2" = "__RED2__" ] || [ "$PIN_FIX2" = "__FIX2__" ] || [ "$PIN_FINAL" = "__FINAL__" ] || [ "$PIN_TIP" = "__TIP__" ]; then
    fail "AC11.0 the 089a2 red/fix/final/tip SHAs are not pinned yet"
else
    for s in "$PIN_BASE" "$PIN_RED" "$PIN_FIX" "$PIN_RED2" "$PIN_FIX2" "$PIN_FINAL" "$PIN_TIP"; do
        full40 "$s" || fail "AC11.1 pin '$s' is not a full 40-character SHA"
        G cat-file -e "$s^{commit}" 2>/dev/null && pass "AC11.1 pin $s exists" || fail "AC11.1 pin $s does not exist"
    done
    G merge-base --is-ancestor "$PIN_BASE" "$PIN_RED" && G merge-base --is-ancestor "$PIN_RED" "$PIN_FIX" \
        && G merge-base --is-ancestor "$PIN_FIX" "$PIN_RED2" && G merge-base --is-ancestor "$PIN_RED2" "$PIN_FIX2" && [ "$PIN_FIX2" = "$PIN_FINAL" ] && G merge-base --is-ancestor "$PIN_FINAL" "$PIN_TIP" && G merge-base --is-ancestor "$PIN_TIP" HEAD \
        && pass "AC11.2 BASE < RED < FIX <= RED2 < FIX2 = FINAL <= TIP <= HEAD (ancestry)" || fail "AC11.2 the pins are not in ancestry order"
    TASKFILES='docs/tasks/089-closed-verify-sweep-registry.md|docs/tasks/089a2-closed-verify-sweep-registry-a2.md'
    red_files="$(G diff --name-only "$PIN_BASE" "$PIN_RED" 2>/dev/null | grep -vxE "$TASKFILES" | sort | tr '\n' ' ')"
    [ "$red_files" = "docs/tasks/089a2-verify.sh " ] && pass "AC11.3 the red commit touches only 089a2-verify.sh and the task files" || fail "AC11.3 the red commit touches: $red_files"
    fix_files="$(G diff --name-only "$PIN_RED" "$PIN_FIX" 2>/dev/null | grep -vxE "$TASKFILES" | sort | tr '\n' ' ')"
    [ "$fix_files" = "docs/tasks/057-textchecks.py docs/tasks/057-verify.sh docs/tasks/070-verify.sh " ] \
        && pass "AC11.4 the fix commit touches only 057-verify.sh, 057-textchecks.py and 070-verify.sh (and task files)" || fail "AC11.4 the fix commit touches: $fix_files"
    rf2="$(G diff --name-only "$PIN_FIX" "$PIN_RED2" 2>/dev/null | grep -vxE "$TASKFILES" | sort | tr '\n' ' ')"
    [ "$rf2" = "docs/tasks/089a2-verify.sh " ] && pass "AC11.3b fixtures first: FIX..RED2 touches only 089a2-verify.sh and the task files (the 062 cross-check exists before the 062 fix)" || fail "AC11.3b FIX..RED2 touches: $rf2"
    ff2="$(G diff --name-only "$PIN_RED2" "$PIN_FIX2" 2>/dev/null | grep -vxE "$TASKFILES" | sort | tr '\n' ' ')"
    [ "$ff2" = "docs/tasks/062-verify.sh " ] && pass "AC11.4b the second fix commit touches only 062-verify.sh (and task files)" || fail "AC11.4b RED2..FIX2 touches: $ff2"
    if ! scope_files="$(G diff --name-only "$PIN_BASE" "$PIN_TIP" 2>&1)"; then fail "AC11.5 cannot compute $PIN_BASE..$PIN_TIP"; else
        extra="$(printf '%s\n' "$scope_files" | grep -vxE "docs/tasks/057-verify\.sh|docs/tasks/057-textchecks\.py|docs/tasks/070-verify\.sh|docs/tasks/062-verify\.sh|docs/tasks/089a2-verify\.sh|$TASKFILES" | tr '\n' ' ')"
        [ -n "$scope_files" ] && [ -z "$extra" ] && pass "AC11.5 BASE..TIP stays inside the declared file scope" || fail "AC11.5 out-of-scope files in BASE..TIP (or the range is empty): $extra"
    fi
    last_src="$(G log -1 --format=%H "$PIN_BASE..$PIN_TIP" -- docs/tasks/057-verify.sh docs/tasks/057-textchecks.py docs/tasks/070-verify.sh docs/tasks/062-verify.sh docs/tasks/089a2-verify.sh 2>/dev/null)"
    [ -n "$last_src" ] && [ "$last_src" = "$(G rev-parse "$PIN_FINAL^{commit}" 2>/dev/null)" ] && pass "AC11.6a FINAL is the last commit in BASE..TIP that touched a source or script file" || fail "AC11.6 FINAL ${PIN_FINAL:0:12} is not the last source-touching commit (that is ${last_src:0:12})"
    if ! tail_files="$(G diff --name-only "$PIN_FINAL" "$PIN_TIP" 2>&1)"; then fail "AC11.6 cannot compute FINAL..TIP"
    elif [ -z "$(printf '%s\n' "$tail_files" | grep -vE '^docs/tasks/089a2-closed-verify-sweep-registry-a2\.md$')" ]; then pass "AC11.6b FINAL..TIP touches only the 089a2 task file"
    else fail "AC11.6 FINAL..TIP touches: $(printf '%s' "$tail_files" | tr '\n' ' ')"; fi
    # hunk limits: each source file changes only where the finding says
    nonc() { G diff -U0 "$OLDREF" "$PIN_FINAL" -- "$1" | grep -E '^[+-][^+-]' | grep -vE '^[+-][[:space:]]*#' ; }
    # exact expected non-comment hunk text of 057-verify.sh (sorted, C locale): the pins, the A1 block, the T1 block; anything else is a finding
    LC_ALL=C sort > "$TMP/exp057.txt" <<'EXP057'
+  $PY docs/tasks/057-textchecks.py --readme "$README_BLOB" > /tmp/057-text.$$ ; rc=$?
+  [ $rc -eq 0 ] && pass "T1 all text checks (old sentences gone, new sentences present, sections equal their full-text pins, README at $FINAL_COMMIT names task 057)" || fail "T1 $rc text check(s) failed"
+  fail "T1 cannot read docs/contracts/README.md at pinned FINAL_COMMIT $FINAL_COMMIT: the text checks cannot run"
+  grep '^FAIL' /tmp/057-text.$$
+  grep -c '^PASS' /tmp/057-text.$$ | sed 's/^/  passing text checks: /'
+  rm -f /tmp/057-text.$$
+)"
+ADR0121
+ADR="$(cat <<'ADR0121'
+BASE_COMMIT="a50daacd7e26235d1acdeadc7d19265f1b2d04e3"
+FINAL_COMMIT="3ab8f43d96013889a48e2005c57a75731b3d655f"
+README_BLOB="$(mktemp)"
+else
+fi
+if git show "$FINAL_COMMIT:docs/contracts/README.md" > "$README_BLOB" 2>/dev/null && [ -s "$README_BLOB" ]; then
+if printf '%s\n' "$ADR" | grep -q '^# ADR-0121:' && printf '%s\n' "$ADR" | grep -q 'Status:\*\* Accepted'; then pass "A1 ADR-0121 (fixture blob of platform commit 84064c9, ADR blob 16064b5) carries 'Status:** Accepted'"; else fail "A1 the ADR-0121 fixture does not carry 'Status:** Accepted'"; fi
+rm -f "$README_BLOB"
-$PY docs/tasks/057-textchecks.py > /tmp/057-text.$$ ; rc=$?
-ADR="$(git -C "$PLATFORM_REPO" show main:docs/decisions/0121-version-lifecycle-pending.md 2>/dev/null)"
-BASE_COMMIT="a50daac"
-FINAL_COMMIT="3ab8f43"
-PLATFORM_REPO="${PLATFORM_REPO:-/home/ludwig/wom}"
-[ $rc -eq 0 ] && pass "T1 all text checks (old sentences gone, new sentences present, sections equal their full-text pins)" || fail "T1 $rc text check(s) failed"
-grep '^FAIL' /tmp/057-text.$$
-grep -c '^PASS' /tmp/057-text.$$ | sed 's/^/  passing text checks: /'
-if [ -n "$ADR" ] && printf '%s\n' "$ADR" | grep -q 'Status:\*\* Accepted'; then pass "A1 ADR-0121 on $PLATFORM_REPO main carries 'Status:** Accepted'"; else fail "A1 ADR-0121 not found or not Accepted on $PLATFORM_REPO main"; fi
-rm -f /tmp/057-text.$$
EXP057
    nonc docs/tasks/057-verify.sh | LC_ALL=C sort > "$TMP/act057.txt"
    d057="$(diff "$TMP/exp057.txt" "$TMP/act057.txt" | grep -c '^[<>]')"; [ -s "$TMP/act057.txt" ] || d057=999
    [ "$d057" = 0 ] && pass "AC11.7 057-verify.sh non-comment hunks equal the recorded exact list (27 lines: the two pins, the A1 block, the T1 block)" || fail "AC11.7 057-verify.sh hunks differ from the recorded exact list ($d057 differing lines): $(diff "$TMP/exp057.txt" "$TMP/act057.txt" | head -n3 | cut -c1-90 | tr '\n' '|')"
    d062="$(G diff -U0 "$OLDREF" "$PIN_FINAL" -- docs/tasks/062-verify.sh | grep -E '^[+-][^+-]')"
    n062=$(printf '%s\n' "$d062" | grep -c .); b062=$(printf '%s\n' "$d062" | grep -vcE "^[+-]mutate \\\$f '(BASE|FINAL)_COMMIT=\"[0-9a-f]+\"' '(BASE|FINAL)_COMMIT=\"[0-9a-f]+\"' one")
    [ "$n062" = 4 ] && [ "$b062" = 0 ] && pass "AC11.13 062-verify.sh changed in exactly 4 lines (2 removed, 2 added), each a 057 BASE/FINAL_COMMIT mutation line, nothing else" || fail "AC11.13 062-verify.sh changed outside the 057 pin-literal mutations ($n062 changed lines, $b062 not of that shape)"
    # 057-textchecks.py: the AST without its docstring is identical (only the docstring changed)
    G show "$OLDREF:$TXC" > "$TMP/tx.old.py"; G show "$PIN_FINAL:$TXC" > "$TMP/tx.new.py"
    cat > "$TMP/astcmp.py" <<'PY'
import ast, sys
def dump(p):
    t = ast.parse(open(p).read())
    if t.body and isinstance(t.body[0], ast.Expr) and isinstance(getattr(t.body[0], "value", None), ast.Constant) and isinstance(t.body[0].value.value, str):
        t.body = t.body[1:]
    return ast.dump(t)
a, b = dump(sys.argv[1]), dump(sys.argv[2])
print(len(a))
sys.exit(0 if a == b and len(a) > 1000 else 1)
PY
    python3 -I "$TMP/astcmp.py" "$TMP/tx.old.py" "$TMP/tx.new.py" > /dev/null && pass "AC11.8 057-textchecks.py: the code (AST without the module docstring) is identical OLD vs FINAL; only the docstring changed" || fail "AC11.8 057-textchecks.py changed in code, not only in its docstring"
    # no weakening: every check id of the OLD 057-verify.sh is still a pass/fail label (062 AC6 and 006 retirement read them), and no check was dropped
    ids() { sed -n 's/.*\b\(pass\|fail\) "\([A-Z][0-9]\) .*/\2/p' "$1" | sort -u | tr '\n' ' '; }
    oi=$(ids "$OLDD/057.sh"); ni=$(ids "$NEWD/057.sh")
    [ -n "$oi" ] && [ "$oi" = "$ni" ] && pass "AC11.9 every check id of 057-verify.sh survives unchanged ($ni)" || fail "AC11.9 057-verify.sh check ids differ: OLD [$oi] NEW [$ni]"
    oc=$(grep -cE '\b(pass|fail) "' "$OLDD/057.sh"); nc=$(grep -cE '\b(pass|fail) "' "$NEWD/057.sh")
    [ "$nc" -ge "$oc" ] && pass "AC11.10 no check was dropped from 057-verify.sh (pass/fail statements: OLD $oc, NEW $nc)" || fail "AC11.10 057-verify.sh lost checks (OLD $oc, NEW $nc)"
    for f in docs/tasks/057-verify.sh docs/tasks/070-verify.sh docs/tasks/057-textchecks.py docs/tasks/089a2-verify.sh; do
        m_old=$(G ls-tree "$OLDREF" -- "$f" | cut -c1-6); m_new=$(G ls-tree "$PIN_FINAL" -- "$f" | cut -c1-6)
        case "$f" in *089a2-verify.sh) [ "$m_new" = 100755 ] && pass "AC11.11 $f is executable (100755) at FINAL" || fail "AC11.11 $f is not executable at FINAL ($m_new)" ;;
            *) [ "$m_old" = "$m_new" ] && [ -n "$m_new" ] && pass "AC11.11 $f keeps its mode ($m_new)" || fail "AC11.11 $f mode changed ($m_old -> $m_new)" ;; esac
    done
    # no hard-coded working-copy path in this script (S2 is about removing one)
    [ "$(grep -v '^[[:space:]]*#' "$0" | grep -c '/ho[m]e/')" = 0 ] && pass "AC11.12 089a2-verify.sh itself names no /home path in a code line" || fail "AC11.12 089a2-verify.sh names a /home path"
fi

# ==================================================================================================
else
section "AC4 mutations (each fixed check widened back / broken in a temp copy, on a later-branch merge on HEAD: red, and only that check)"
mutate_057() {   # mutate_057 LABEL OLD NEW REQUIRED_FAIL_REGEX ALLOWED_FAIL_REGEX
    local label="$1" old="$2" new="$3" req="$4" allow="$5" d="$TMP/m-$RANDOM" rc nreq nbad
    mk_later "$d" "$HEADREV" "$README" "$RD_RE" "$RD_NEW" || { fail "$label cannot build the later-branch frame"; return; }
    cp "$NEWD/057.trunc.sh" "$d/$TRUNC057"
    edit_file "$d/$TRUNC057" "$old" "$new" || { fail "$label: the mutation did not apply (pattern not found exactly once)"; return; }
    rc=$(run_in "$d" "$TMP/mut.out" bash "$TRUNC057")
    nreq=$(grep -Ec "$req" "$TMP/mut.out"); nbad=$(grep -E '^FAIL  ' "$TMP/mut.out" | grep -vcE "$allow")
    if [ "$rc" != 0 ] && [ "$nreq" -ge 1 ] && [ "$nbad" = 0 ]; then pass "$label turns red, and only that check: exit $rc, $(grep '^FAIL' "$TMP/mut.out" | head -n1 | cut -c1-110)"
    else fail "$label: exit $rc, $nreq required FAIL line(s), $nbad unrelated FAIL line(s): $(first_fail "$TMP/mut.out")"; fi
}
mutate_057 "AC4.m6 T1 widened back to the working-copy README (HEAD, where the later branch rewrote it)" \
    'git show "$FINAL_COMMIT:docs/contracts/README.md" > "$README_BLOB"' 'cat docs/contracts/README.md > "$README_BLOB"' \
    '^FAIL  required/readme-names-057: ' '^FAIL  (T1 |required/readme-names-057: )'
mutate_057 "AC4.m6b T1 pin unreachable (FINAL_COMMIT=deadbee)" \
    "FINAL_COMMIT=\"$(pin_of "$NEWD/057.sh" FINAL_COMMIT)\"" 'FINAL_COMMIT="deadbee"' \
    '^FAIL  T1 cannot read .* deadbee' '^FAIL  (T1 |P0 |T2 )'
mutate_057 "AC4.m2 A1 fixture says Proposed (the check reads the fixture, so it must redden)" \
    '- **Status:** Accepted (Ludwig, in session' '- **Status:** Proposed (Ludwig, in session' \
    '^FAIL  A1 ' '^FAIL  A1 '
mutate_057 "AC4.m2b A1 fixture title line removed (an empty search is broken, not clean)" \
    "grep -q '^# ADR-0121:'" "grep -q '^# ADR-9999:'" \
    '^FAIL  A1 ' '^FAIL  A1 '
# F1: a 057 whose pin literal changed shape reddens the cross-check; a 062 without the 057 block is an error, not green
mutx() {   # mutx LABEL FILE062 FILE057 OLD NEW (the 057 edit)
    cp "$3" "$TMP/x57.sh"; edit_file "$TMP/x57.sh" "$4" "$5" || { fail "AC4.$1: the mutation did not apply"; return; }
    cross062 "$2" "$TMP/x57.sh"; local rc=$?
    [ "$rc" = 1 ] && pass "AC4.$1 turns red: $X_WHY" || fail "AC4.$1 stayed green or errored (rc $rc): $X_WHY"
}
mutx "m-X1 057 BASE_COMMIT back to the short form" "$NEWD/062.sh" "$NEWD/057.sh" "BASE_COMMIT=\"$(pin_of "$NEWD/057.sh" BASE_COMMIT)\"" 'BASE_COMMIT="a50daac"'
mutx "m-X2 057 FINAL_COMMIT assignment renamed" "$NEWD/062.sh" "$NEWD/057.sh" "FINAL_COMMIT=\"$(pin_of "$NEWD/057.sh" FINAL_COMMIT)\"" 'FINAL_PIN="x"'
cp "$NEWD/062.sh" "$TMP/x62.sh"
if edit_file "$TMP/x62.sh" 'f=docs/tasks/057-verify.sh' 'f=docs/tasks/057-verify.shX'; then
    cross062 "$TMP/x62.sh" "$NEWD/057.sh"; rcx=$?
    [ "$rcx" = 2 ] && pass "AC4.m-X3 a 062 without the 057 block is an error (rc 2), never green: $X_WHY" || fail "AC4.m-X3 a missing 057 block in 062 did not error (rc $rcx): $X_WHY"
else fail "AC4.m-X3 the mutation did not apply"; fi
# S3: the header count is derived from the CLOSED list; a list that grows, shrinks or disappears must redden the check
mut_s3() {   # mut_s3 LABEL OLD NEW
    cp "$NEWD/070.sh" "$TMP/s3m.sh"
    if ! edit_file "$TMP/s3m.sh" "$2" "$3"; then fail "$1: the mutation did not apply"; return; fi
    if s3_check "$TMP/s3m.sh"; then fail "$1: the S3 check stayed green on the mutated 070-verify.sh ($S3_WHY)"; else pass "$1 turns red: $S3_WHY"; fi
}
mut_s3 "AC4.m-S3a a 13th script added to CLOSED while the header says twelve" 'CLOSED="006 007a 007b 008a 032 034 057 062 066 067 069 075"' 'CLOSED="006 007a 007b 008a 032 034 057 062 066 067 069 075 092"'
mut_s3 "AC4.m-S3b a script removed from CLOSED while the header says twelve" 'CLOSED="006 007a 007b 008a 032 034 057 062 066 067 069 075"' 'CLOSED="006 007a 007b 008a 032 034 057 062 066 067 069"'
mut_s3 "AC4.m-S3c the CLOSED list renamed (a search that finds nothing)" 'CLOSED="006 007a' 'CLOSED_X="006 007a'
mut_s3 "AC4.m-S3d the loop no longer iterates CLOSED" 'for n in $CLOSED; do' 'for n in $CLOSED_NOT; do'
mut_s3 "AC4.m-S3e one header line reverts to ten" 'plus everything the twelve closed scripts require' 'plus everything the ten closed scripts require'
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
