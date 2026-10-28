#!/usr/bin/env bash
#
# 089e-verify.sh -- the runnable verification artefact for task 089e (MANAGER.md Section 2c), part E of umbrella 089.
#
# Task 089e: 008c-verify.sh's own-change scope check took its left side from the merge-base with the CURRENT origin/main (task
# 008c review finding 5's fix, right while 008c was open). After 008c merged (M = registry 32c641b, PR #27) that check fails on
# main itself ("no changes since base") and on every later branch (out-of-scope files): REVIEW-CHECKLIST item 12. It now reads the
# fixed merged range BASE..FINAL, BASE = git merge-base M^1 M^2, FINAL = M^2, which a later merge of main cannot change.
# Demonstrates acceptance criteria 1-5, 9 and 11 of docs/tasks/089e-closed-verify-sweep-registry-e.md, for this one check.
#
# Usage:  docs/tasks/089e-verify.sh [--mutate] [--own-only]      (any cwd inside the repository)
#   (no flag)   AC2 (pins re-derived from the merge commit; the scope check names no HEAD / origin/main), AC1 (RED FIRST: the
#               OLD script at M fails on M itself and on later synthetic branches, the NEW one passes), AC3 (deadbee pins fail,
#               nothing is passed silently), AC5 (item-12 control: NEW exits 0 on HEAD and on a merge with a later branch),
#               AC11 (scope, on fixed SHAs).
#   --mutate    AC4: the live scope check widened back to the merge-base with origin/main, and its right side widened to HEAD, on a
#               later-branch merge: red, and only that check; the unmutated control stays green; 008c-verify.sh --mutate (every
#               existing 008c mutation, plus the two scope mutations) is run and must stay green.
#   --own-only  AC2 and AC11 only; fast; runs no 008c-verify.sh.
# AC9 quiet machine: before EVERY child run this script waits until no other *-verify.sh process is running (ancestors and itself
# are excluded) and logs the `ps` lines it saw; the wait is capped (6 hours) and a timeout is a FAIL. One child at a time.
# Everything runs on the COMMITTED state in temporary clones; the caller's worktree is never modified. The scripts under test are
# read as blobs of the pinned commits below (OLD = registry main at M, NEW = 089e's fix commit), never from HEAD, except the HEAD
# control, which is the fixed script as committed at HEAD. No environment variable overrides any pin.
# Network: none. Exit code: the number of failed checks. Requires: git, python3, ps.

set -u
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1

MUTATE=0
OWN=0
for a in "$@"; do
    case "$a" in
        --mutate) MUTATE=1 ;;
        --own-only) OWN=1 ;;
        *) echo "usage: $0 [--mutate] [--own-only]"; exit 99 ;;
    esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }
GITID=(-c user.name=verify089e -c user.email=verify089e@invalid -c commit.gpgsign=false)
HEADREV="$(git -C "$ROOT" rev-parse HEAD)"
G() { git -C "$ROOT" "$@"; }

V008C=docs/tasks/008c-verify.sh
TASKF=docs/tasks/089e-closed-verify-sweep-registry-e.md
SELF=docs/tasks/089e-verify.sh
UMB=docs/tasks/089-closed-verify-sweep-registry.md   # the umbrella, copied into the branch by the cut commit (read-only here)

# Fixed SHAs (full 40 characters). 008c's merged range, recomputed from M below (AC2); never HEAD, never the current main.
M008C="32c641b5f56139a86c820f0b16d522c0f991d207"      # merge of registry PR #27 (task 008c); also registry main when 089e was cut
BASE008C="e2f7fe383d7b2231e1d37a73e474bca7ed56af46"   # git merge-base M^1 M^2
FINAL008C="7810e70af50d7e2ebae1e53dccba37be1095afe7"  # M^2
# 089e's own commits (AC11). Filled in by the pin commit after the content commit exists.
E_BASE="32c641b5f56139a86c820f0b16d522c0f991d207"     # registry main when 089e was cut (= M008C)
E_FIX="c68eec7b910a29be295b1944e826497d37cac326"     # first commit touching 008c-verify.sh
E_FINAL="c68eec7b910a29be295b1944e826497d37cac326"   # last commit touching 008c-verify.sh
E_TIP="48141c31631f6a9dbe6ce2df06a15d1054efed1d"     # last commit before the pin commit; after it only the task file and the pin lines of this script may change

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

# ---- AC9: the quiet machine. Other *-verify.sh processes (ancestors of this script and 089e itself excluded) block every child run.
others() {   # every *-verify.sh process that is not this script's PID, a descendant of it, or an ancestor of it (a second 089e run counts)
    ps -eo pid=,ppid=,args= 2>/dev/null | awk -v me="$$" '
        { pid=$1; ppid[pid]=$2; line[pid]=$0; ord[++n]=pid }
        END {
            for (i = 1; i <= n; i++) { pid = ord[i]; skip = (pid == me)
                for (q = pid; !skip && q != "" && q > 1; q = ppid[q]) { if (q == me) skip = 1 }
                if (!skip && line[pid] ~ /[0-9A-Za-z]+-verify[.]sh/ && line[pid] !~ /awk -v me=/) { sub(/^ *[0-9]+ +[0-9]+ +/, "", line[pid]); print pid " " line[pid] }
            }
        }' | while read -r pid rest; do
        anc=0; p=$$
        while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
            [ "$p" = "$pid" ] && { anc=1; break; }
            nxt=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); [ "$nxt" = "$p" ] && break; p="$nxt"
        done
        [ "$anc" = 1 ] || printf '%s %s\n' "$pid" "$rest"
    done
}
wait_quiet() {   # wait_quiet LABEL : block until nothing else runs, logging ps; returns 1 after 6 hours (the caller marks a FAIL)
    local label="$1" o waited=0
    while :; do
        o="$(others)"
        if [ -z "$o" ]; then printf 'ps    %s: no other *-verify.sh process running (waited %ss)\n' "$label" "$waited"; return 0; fi
        printf 'ps    %s: waiting, %s other process(es):\n' "$label" "$(printf '%s\n' "$o" | wc -l)"; printf '%s\n' "$o" | cut -c1-160 | sed 's/^/        /'
        [ "$waited" -ge 21600 ] && return 1
        sleep 30; waited=$((waited + 30))
    done
}

# mk_frame DEST REV [ORIGIN_MAIN] : a clone detached at REV whose refs/remotes/origin/main and refs/heads/main are ORIGIN_MAIN (default M008C)
mk_frame() {
    git clone -q --no-hardlinks "$ROOT" "$1" 2>/dev/null || return 1
    git -C "$1" checkout -q --detach "$2" || return 1
    git -C "$1" update-ref refs/remotes/origin/main "${3:-$M008C}" || return 1
    git -C "$1" update-ref refs/heads/main "${3:-$M008C}" || return 1
}
# add_later DIR BASEREV : in clone DIR, build a synthetic later branch (one commit adding a file outside the 008c scope) on BASEREV,
# return to BASEREV detached and --no-ff merge it; prints the later commit
add_later() {
    local d="$1" b="$2" later
    git -C "$d" checkout -q --detach "$b" || return 1
    git -C "$d" checkout -q -b "later-$RANDOM" || return 1
    printf 'synthetic later branch (089e)\n' > "$d/docs/089e-synthetic-later.md"
    git -C "$d" add docs/089e-synthetic-later.md || return 1
    git -C "$d" "${GITID[@]}" commit -q -m "synthetic later branch: a file outside the 008c scope" || return 1
    later=$(git -C "$d" rev-parse HEAD)
    git -C "$d" checkout -q --detach "$b" || return 1
    git -C "$d" "${GITID[@]}" merge --no-ff -q -m "merge of the synthetic later branch" "$later" >/dev/null 2>&1 || return 1
    printf '%s\n' "$later"
}
# mk_later DEST KIND : HEAD = M plus a --no-ff merge of a synthetic later branch adding a file outside the 008c scope.
#   KIND=other  -> origin/main stays at M;   KIND=mainmv -> origin/main has moved to the later commit (main merged INTO the branch)
mk_later() {
    local later
    mk_frame "$1" "$M008C" || return 1
    later=$(add_later "$1" "$M008C") || return 1
    [ "$2" = mainmv ] && { git -C "$1" update-ref refs/remotes/origin/main "$later"; git -C "$1" update-ref refs/heads/main "$later"; }
    return 0
}
# run008c DIR OUTFILE [SCRIPT_BLOB] [ARG] : wait for a quiet machine, then run 008c-verify.sh (the clone's own, or SCRIPT_BLOB copied over it); echo the exit code
run008c() {
    local d="$1" o="$2" blob="${3:-}" arg="${4:-}"
    if ! wait_quiet "$(basename "$d")" >&2; then touch "$TMP/timeout"; echo 99; return; fi
    [ -z "$blob" ] || { cp "$blob" "$d/$V008C"; chmod +x "$d/$V008C"; }
    ( cd "$d" && PYTHONDONTWRITEBYTECODE=1 bash "$V008C" ${arg:+"$arg"} ) > "$o" 2>&1
    echo $?
}

# blobs of the script under test
OLDF="$TMP/old008c.sh"; NEWF="$TMP/new008c.sh"
G show "$M008C:$V008C" > "$OLDF" 2>/dev/null && [ -s "$OLDF" ] || fail "AC0.0 cannot read 008c-verify.sh at M $M008C (the OLD script)"
if full40 "$E_FIX"; then G show "$E_FIX:$V008C" > "$NEWF" 2>/dev/null && [ -s "$NEWF" ] || fail "AC0.0 cannot read 008c-verify.sh at the fix commit $E_FIX"
else : > "$NEWF"; fail "AC0.0 the fix commit is not pinned yet (E_FIX=$E_FIX): the NEW script cannot be read"; fi

if [ "$MUTATE" = 0 ]; then
# ==================================================================================================
section "AC2 -- pins are full SHAs, recomputed from the merge commit (never copied)"
for p in M008C BASE008C FINAL008C E_BASE; do
    full40 "${!p}" && G cat-file -e "${!p}^{commit}" 2>/dev/null && pass "AC2.1 $p is a full 40-character SHA and exists" || fail "AC2.1 $p='${!p}' is not a full SHA that exists"
done
mlist="$(G log --merges --first-parent --format=%H --grep='Merge pull request #27 from worldofmodcraft/task/008c-pipeline-write-back' HEAD 2>/dev/null)"
[ "$mlist" = "$M008C" ] && pass "AC2.2 the merge found by 'git log --merges --grep' on HEAD's first-parent chain is exactly M ($M008C)" || fail "AC2.2 merge search returned '$mlist', expected exactly $M008C"
d_base="$(G merge-base "$M008C^1" "$M008C^2" 2>/dev/null)"; d_final="$(G rev-parse "$M008C^2" 2>/dev/null)"
[ -n "$d_base" ] && [ "$d_base" = "$BASE008C" ] && pass "AC2.3 BASE = git merge-base M^1 M^2 = $d_base" || fail "AC2.3 derived BASE '$d_base' != pinned $BASE008C"
[ -n "$d_final" ] && [ "$d_final" = "$FINAL008C" ] && pass "AC2.4 FINAL = M^2 = $d_final" || fail "AC2.4 derived FINAL '$d_final' != pinned $FINAL008C"
for pr in "$M008C:PIN_M" "$BASE008C:PIN_BASE" "$FINAL008C:PIN_FINAL"; do
    want="${pr%%:*}"; key="${pr##*:}"; got="$(pin_of "$NEWF" "$key")"
    [ "$got" = "$want" ] && full40 "$got" && pass "AC2.5 the NEW 008c-verify.sh pins $key to the derived full SHA" || fail "AC2.5 the NEW 008c-verify.sh has $key='$got', derived $want"
done
# no own-change read of HEAD/origin/main remains in the scope check (non-zero counts, with a positive control on the OLD script)
region() { awk '/^PIN_M=/{f=1} f{print} f&&/^}/{exit}' "$1" | grep -v '^[[:space:]]*#'; }
liveregion() { awk '/^for p in PIN_M PIN_BASE PIN_FINAL/{f=1} f{print} f&&/scope pins unusable/{exit}' "$1" | grep -v '^[[:space:]]*#'; }
oldliveregion() { awk '/^if SB=\$\(scope_base\); then/{f=1} f{print} f&&/cannot be checked/{exit}' "$1" | grep -v '^[[:space:]]*#'; }
oldregion() { awk '/^scope_base\(\)/{f=1} f{print} /^scope_violations\(\)/{g=1} g&&/^}/{exit}' "$1" | grep -v '^[[:space:]]*#'; }
nr="$(region "$NEWF" | wc -l)"; or="$(oldregion "$OLDF" | wc -l)"
[ "$nr" -gt 5 ] && pass "AC2.6a the NEW scope region was extracted ($nr code lines)" || fail "AC2.6a the NEW scope region is empty or tiny ($nr lines): the markers moved"
[ "$or" -gt 5 ] && pass "AC2.6b the OLD scope region was extracted ($or code lines)" || fail "AC2.6b the OLD scope region is empty or tiny ($or lines)"
nl="$(liveregion "$NEWF" | wc -l)"; ol="$(oldliveregion "$OLDF" | wc -l)"
[ "$nl" -gt 5 ] && [ "$ol" -gt 3 ] && pass "AC2.6a2 the live scope-check blocks were extracted (NEW $nl lines, OLD $ol lines)" || fail "AC2.6a2 a live scope-check block is empty or tiny (NEW $nl, OLD $ol): the markers moved"
oh="$( { oldregion "$OLDF"; oldliveregion "$OLDF"; } | grep -cE 'HEAD|origin/main|refs/heads/main')"; nh="$( { region "$NEWF"; liveregion "$NEWF"; } | grep -cE 'HEAD|origin/main|refs/heads/main')"
[ "$oh" -ge 2 ] && pass "AC2.6c positive control: the grep finds $oh HEAD/main reads in the OLD scope region and live block" || fail "AC2.6c the HEAD/main grep is blind on the OLD scope region ($oh hits)"
[ "$nh" = 0 ] && pass "AC2.6d the NEW scope region and live check block have 0 HEAD / origin/main / refs/heads/main reads" || fail "AC2.6d the NEW scope region still reads HEAD or main ($nh hit lines)"
live_new="$(grep -c 'git diff --name-only "\$PIN_BASE" "\$PIN_FINAL"' "$NEWF")"
[ "$live_new" -ge 2 ] && pass "AC2.6e the NEW script diffs the pinned range in the function and in the live check ($live_new occurrences)" || fail "AC2.6e expected >= 2 pinned-range diffs, found $live_new"
[ "$(grep -v '^[[:space:]]*#' "$NEWF" | grep -c 'scope_base')" = 0 ] && [ "$(grep -v '^[[:space:]]*#' "$OLDF" | grep -c 'scope_base')" -ge 2 ] \
    && pass "AC2.6f scope_base (the merge-base-with-main formula) is gone from the NEW script (positive control: the OLD one has it)" || fail "AC2.6f scope_base is still referenced in the NEW script (or the control is blind)"

if [ "$OWN" = 0 ]; then
section "AC1 -- RED FIRST: OLD 008c-verify.sh (at M) vs NEW, on M and on later synthetic branches (one run at a time, quiet machine)"
mk_frame "$TMP/f1" "$M008C" || fail "AC1.0 cannot build frame 1"
mk_later "$TMP/f2" other || fail "AC1.0 cannot build frame 2 (later branch, origin/main stays at M)"
mk_later "$TMP/f3" mainmv || fail "AC1.0 cannot build frame 3 (main moved, merged into the branch)"
for fr in f1 f2 f3; do
    case "$fr" in f1) lab="registry main itself (HEAD = M)"; rx='^FAIL  no changes since base' ;;
                  f2) lab="M + merge of a later branch touching another file"; rx='^FAIL  out of scope: .*089e-synthetic-later\.md' ;;
                  f3) lab="main moved to the later branch and merged into HEAD"; rx='^FAIL  no changes since base' ;; esac
    rc=$(run008c "$TMP/$fr" "$TMP/o-$fr.out" "$OLDF"); expect "AC1.$fr the OLD script on $lab" red "$rc" "$TMP/o-$fr.out" "$rx"
done
for fr in f1 f2 f3; do
    rc=$(run008c "$TMP/$fr" "$TMP/n-$fr.out" "$NEWF"); expect "AC1.$fr the NEW script on the same frame" green "$rc" "$TMP/n-$fr.out" \
        '^ok    scope pins re-derived from the merge commit' '^ok    all changes of 008c.s merged range inside the declared file scope' '!^FAIL'
done

section "AC3 -- an unresolvable pin is a FAIL: PIN_M, PIN_BASE, PIN_FINAL each replaced with deadbee; nothing is passed silently"
mk_frame "$TMP/d" "$M008C" || fail "AC3.0 cannot build the deadbee frame"
for key in PIN_M PIN_BASE PIN_FINAL; do
    val="$(pin_of "$NEWF" "$key")"
    cp "$NEWF" "$TMP/dead.sh"
    if edit_file "$TMP/dead.sh" "$key=\"$val\"" "$key=\"deadbee\""; then
        rc=$(run008c "$TMP/d" "$TMP/d-$key.out" "$TMP/dead.sh"); expect "AC3.$key the NEW script with $key=deadbee" red "$rc" "$TMP/d-$key.out" "^FAIL  scope pin $key='deadbee' is not a full 40-character SHA"
    else fail "AC3.$key the pin line was not found exactly once"; fi
done
printf 'x skipped y\n' > "$TMP/skipctl.txt"
grep -Eiq 'skip|not evaluated' "$TMP/skipctl.txt" && pass "AC3.4a positive control: the skip-word grep matches a sample line" || fail "AC3.4a the skip-word grep cannot match"
hits=$(cat "$TMP"/d-PIN_*.out "$TMP"/n-f?.out 2>/dev/null | grep -Eic 'skip|not evaluated')
[ "$hits" = 0 ] && pass "AC3.4 'skip' / 'not evaluated' occur 0 times in the outputs of the deadbee and NEW runs" || fail "AC3.4 $hits skip/not-evaluated line(s) in the run outputs"

section "AC5 -- item-12 control: the fixed 008c-verify.sh as committed at HEAD exits 0 on HEAD and on a merge with a later synthetic branch"
if ! full40 "$E_FIX"; then fail "AC5.0 E_FIX='$E_FIX' is not a full SHA: cannot compare 008c-verify.sh at HEAD with the fix commit"
elif G diff --quiet "$E_FIX" "$HEADREV" -- "$V008C" 2>/dev/null; then pass "AC5.0 008c-verify.sh at HEAD equals the fix commit's (HEAD is the fixed script)"
else fail "AC5.0 008c-verify.sh at HEAD differs from the fix commit $E_FIX"; fi
mk_frame "$TMP/h" "$HEADREV" "$HEADREV" || fail "AC5.0 cannot clone HEAD"
rc=$(run008c "$TMP/h" "$TMP/h.out"); expect "AC5.1 the HEAD script on HEAD" green "$rc" "$TMP/h.out" '!^FAIL'
if mk_frame "$TMP/hl" "$HEADREV" "$HEADREV" && lh=$(add_later "$TMP/hl" "$HEADREV"); then git -C "$TMP/hl" update-ref refs/remotes/origin/main "$lh"
else fail "AC5.0 cannot build the HEAD + later-branch frame"; fi
rc=$(run008c "$TMP/hl" "$TMP/hl.out"); expect "AC5.2 the HEAD script on HEAD merged with a later branch (main moved)" green "$rc" "$TMP/hl.out" '!^FAIL'
fi   # OWN = 0

section "AC11 -- 089e's own change, measured on fixed SHAs (never HEAD)"
if ! full40 "$E_FIX" || ! full40 "$E_FINAL" || ! full40 "$E_TIP"; then
    fail "AC11.0 the 089e fix/final/tip SHAs are not pinned yet (E_FIX=$E_FIX E_FINAL=$E_FINAL E_TIP=$E_TIP)"
else
    for s in "$E_BASE" "$E_FIX" "$E_FINAL" "$E_TIP"; do G cat-file -e "$s^{commit}" 2>/dev/null && pass "AC11.1 pin ${s:0:12} exists" || fail "AC11.1 pin $s does not exist"; done
    anc() { G merge-base --is-ancestor "$1" "$2" 2>/dev/null; }
    anc "$E_BASE" "$E_FIX" && anc "$E_FIX" "$E_FINAL" && anc "$E_FINAL" "$E_TIP" && anc "$E_TIP" "$HEADREV" && [ "$E_BASE" != "$E_FIX" ] \
        && pass "AC11.2 BASE < FIX <= FINAL <= TIP <= HEAD (ancestry)" || fail "AC11.2 the pins are not in ancestry order"
    first_touch="$(G log --reverse --format=%H "$E_BASE..$E_TIP" -- "$V008C" | head -n1)"; last_touch="$(G log --format=%H -n1 "$E_BASE..$E_TIP" -- "$V008C")"
    [ -n "$first_touch" ] && [ "$first_touch" = "$E_FIX" ] && pass "AC11.3a FIX is the first commit in BASE..TIP touching 008c-verify.sh" || fail "AC11.3a FIX ${E_FIX:0:12} is not the first 008c-verify.sh commit (that is ${first_touch:0:12})"
    [ -n "$last_touch" ] && [ "$last_touch" = "$E_FINAL" ] && pass "AC11.3b FINAL is the last commit in BASE..TIP touching 008c-verify.sh" || fail "AC11.3b FINAL ${E_FINAL:0:12} is not the last 008c-verify.sh commit (that is ${last_touch:0:12})"
    if ! scope_files="$(G diff --name-only "$E_BASE" "$E_TIP" 2>&1)"; then fail "AC11.4 cannot compute $E_BASE..$E_TIP"; else
        extra="$(printf '%s\n' "$scope_files" | grep -vxE "$V008C|$SELF|$TASKF|$UMB" || true)"
        [ -n "$scope_files" ] && [ -z "$extra" ] && pass "AC11.4 BASE..TIP stays inside the declared file scope ($(echo $scope_files | tr '\n' ' '))" || fail "AC11.4 out-of-scope files in BASE..TIP (or empty range): $extra"
        # the umbrella may appear only as the cut commit's copy-in: exactly one commit touched it, it is not 089e's fix, and nothing later changes it
        n_umb="$(G log --format=%H "$E_BASE..$HEADREV" -- "$UMB" | wc -l)"; umb_c="$(G log --format=%H -n1 "$E_BASE..$HEADREV" -- "$UMB")"
        { [ "$n_umb" = 1 ] && [ "$umb_c" != "$E_FIX" ] && anc "$umb_c" "$E_FIX"; } && pass "AC11.4c the umbrella file was touched by exactly one commit (the cut copy-in ${umb_c:0:12}), before the fix" || fail "AC11.4c the umbrella file was touched by $n_umb commit(s) in BASE..HEAD, or by the fix commit"
        for need in "$V008C" "$SELF"; do printf '%s\n' "$scope_files" | grep -qx "$need" && pass "AC11.4b BASE..TIP contains $need" || fail "AC11.4b BASE..TIP lacks $need"; done
    fi
    tail_files="$(G diff --name-only "$E_TIP" "$HEADREV" 2>&1)"
    [ -z "$(printf '%s\n' "$tail_files" | grep -vxE "$SELF|$TASKF")" ] && pass "AC11.5a TIP..HEAD touches only this script and the task file" || fail "AC11.5a TIP..HEAD touches: $(printf '%s' "$tail_files" | tr '\n' ' ')"
    nonpin="$(G diff "$E_TIP" "$HEADREV" -- "$SELF" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-]E_(FIX|FINAL|TIP)=' || true)"
    [ -z "$nonpin" ] && pass "AC11.5b TIP..HEAD changes only the E_FIX/E_FINAL/E_TIP pin lines of this script" || fail "AC11.5b TIP..HEAD changes this script beyond its pin lines: $(printf '%s' "$nonpin" | head -n3 | tr '\n' '|')"
    G diff --quiet "$E_FINAL" "$HEADREV" -- "$V008C" && pass "AC11.5c 008c-verify.sh at HEAD equals FINAL" || fail "AC11.5c 008c-verify.sh changed after FINAL"
    # the existing 008c checks are untouched: the mutation block up to the scope mutations, and the normal-mode suite checks, are byte-identical
    cut_mut() { awk '/^  run_mut copy-commit-from-result/{f=1} /^  # finding 5/{f=0} f{print}' "$1"; }
    cut_norm() { awk '/^OUT=\$\(python3 tests\/pipeline\/run_checks\.py/{f=1} /^# hygiene and scope/{f=0} f{print}' "$1"; }
    for c in cut_mut cut_norm; do
        a="$($c "$OLDF")"; b="$($c "$NEWF")"
        [ "$(printf '%s\n' "$a" | wc -l)" -gt 10 ] && [ "$a" = "$b" ] && pass "AC11.6 $c: $(printf '%s\n' "$a" | wc -l) lines of existing 008c checks are byte-identical OLD vs NEW" || fail "AC11.6 $c differs between OLD and NEW (or is empty)"
    done
    [ "$(G ls-tree "$HEADREV" "$V008C" "$SELF" | awk '$1=="100755"' | wc -l)" = 2 ] && pass "AC11.7 both scripts are executable at HEAD" || fail "AC11.7 a script is not mode 100755 at HEAD"
    bash -n "$NEWF" && pass "AC11.8 the NEW 008c-verify.sh parses (bash -n)" || fail "AC11.8 the NEW 008c-verify.sh does not parse"
fi

else
# ==================================================================================================
section "AC4 -- mutations (the live scope check widened back; red, and only that check) and the existing 008c mutations"
mk_later "$TMP/m" other || fail "AC4.0 cannot build the later-branch frame"
rc=$(run008c "$TMP/m" "$TMP/m-ctl.out" "$NEWF"); expect "AC4.0 control: the unmutated NEW script on the later-branch frame" green "$rc" "$TMP/m-ctl.out" '!^FAIL'
cp "$NEWF" "$TMP/mut1.sh"
if edit_file "$TMP/mut1.sh" '  BAD=$(scope_violations || echo "BASE-ERROR")' '  BAD=$(git diff --name-only "$(git merge-base HEAD origin/main)" HEAD | grep -vxE "$SCOPE_RE" || true)'; then
    rc=$(run008c "$TMP/m" "$TMP/m1.out" "$TMP/mut1.sh")
    nf=$(grep -c '^FAIL  ' "$TMP/m1.out")
    [ "$rc" != 0 ] && [ "$nf" = 1 ] && grep -q '^FAIL  out of scope: .*089e-synthetic-later\.md' "$TMP/m1.out" \
        && pass "AC4.m1 the live check widened to the merge-base with origin/main turns red, and only that check: exit $rc, $(grep '^FAIL' "$TMP/m1.out" | head -n1 | cut -c1-100)" \
        || fail "AC4.m1 exit $rc, $nf FAIL line(s) (want exactly 1, 'out of scope'): $(first_fail "$TMP/m1.out")"
else fail "AC4.m1 the mutation did not apply (pattern not found exactly once)"; fi
cp "$NEWF" "$TMP/mut2.sh"
if edit_file "$TMP/mut2.sh" '  git merge-base --is-ancestor "$PIN_BASE" "$PIN_FINAL" || return 1
  d=$(git diff --name-only "$PIN_BASE" "$PIN_FINAL") || return 1' '  git merge-base --is-ancestor "$PIN_BASE" "$PIN_FINAL" || return 1
  d=$(git diff --name-only "$PIN_BASE" HEAD) || return 1'; then
    rc=$(run008c "$TMP/m" "$TMP/m2.out" "$TMP/mut2.sh")
    other="$(grep '^FAIL  ' "$TMP/m2.out" | grep -vE '^FAIL  (out of scope: |scope self-test failed|scope scenario )' || true)"
    [ "$rc" != 0 ] && grep -q '^FAIL  out of scope: ' "$TMP/m2.out" && grep -q '^FAIL  scope self-test failed' "$TMP/m2.out" && [ -z "$other" ] \
        && pass "AC4.m2 the pinned range's right side widened to HEAD turns red in the scope check and its self-test only: exit $rc" \
        || fail "AC4.m2 exit $rc; unexpected FAIL lines: '$other'; $(first_fail "$TMP/m2.out")"
else fail "AC4.m2 the mutation did not apply (pattern not found exactly once)"; fi

# every existing 008c mutation (and the two scope mutations) is red, via 008c-verify.sh --mutate run from a clean clone of HEAD
mk_frame "$TMP/mh" "$HEADREV" "$HEADREV" || fail "AC4.0 cannot clone HEAD"
exp_n=$(( $(grep -cE '^  (run_mut|scope_mut) [a-z]' "$TMP/mh/$V008C") + 1 ))
rc=$(run008c "$TMP/mh" "$TMP/mh.out" "" --mutate)
got_n=$(grep -c '^ok    mutation ' "$TMP/mh.out")
[ "$rc" = 0 ] && [ "$exp_n" = 28 ] && [ "$got_n" = 28 ] && [ "$got_n" = "$exp_n" ] && ! grep -q '^FAIL' "$TMP/mh.out" \
    && grep -q '^ok    mutation scope-right-side-head: red -> scope scenario merge-from-main' "$TMP/mh.out" \
    && grep -q '^ok    mutation scope-unusable-pin-passes: red -> scope scenario bad-pin' "$TMP/mh.out" \
    && pass "AC4.m3 008c-verify.sh --mutate at HEAD: exit 0, all $got_n mutations red (expected $exp_n), both scope mutations named" \
    || fail "AC4.m3 008c-verify.sh --mutate: exit $rc, $got_n red mutations vs $exp_n expected: $(first_fail "$TMP/mh.out")"
fi

[ -e "$TMP/timeout" ] && fail "AC9 the machine did not become quiet within 6 hours before at least one run (that run was not executed)"
printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
