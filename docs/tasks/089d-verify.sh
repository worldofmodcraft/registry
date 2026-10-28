#!/usr/bin/env bash
#
# 089d-verify.sh -- the runnable verification artefact for task 089d (MANAGER.md Section 2c), part D of umbrella 089.
#
# Defect (part D, from session 12): 092-verify.sh AC9 "post-TIP" listed the files after TIP with a first-parent `git log` using name-only
# output. With git >= 2.31 --first-parent implies --diff-merges=first-parent, so a merge of MAIN INTO the task branch (GitHub's "Update
# branch", required once M9's "up to date" rule is on) listed all of main's files and the check went red on a correct branch. The fix
# (commit PIN_FIX below) lists non-merge first-parent commits as before and, for every merge C: adds `git diff-tree --cc` files; adds
# `git diff C^1 C^2` when C^2 is not an ancestor of the local main ref (refs/remotes/origin/main when a remote exists, else refs/heads/main;
# an absent ref means "not from main"); an octopus merge is RED. A stale clone whose main predates a merge from main is therefore RED,
# never a skip (accepted, Q6 star A).
#
# Mechanism (D criteria): the script pins the RED and the FIXED commit of docs/tasks/092-verify.sh as full 40-character SHAs, extracts
# post_tip_check from each with `git show <sha>:docs/tasks/092-verify.sh` and a sed range between two marker lines (START_RE/END_RE below),
# and evaluates each, with stub G/pass/fail, against synthetic repositories (an upstream plus a clone, so origin/main is a real
# remote-tracking ref) built in a temp directory. The blobs are read from a temp clone of the repository, never from its worktree or HEAD.
# Every extraction is asserted non-empty (positive control).
#
# Usage:  docs/tasks/089d-verify.sh [--mutate] [--own-only]      (any cwd inside the repository)
#   (no flag)   AC0 pins + extraction (positive controls), (a) red first, (b) controls red after the fix, (c) the existing AC9 controls,
#               (f) scope. Network: none. Exit code: the number of failed checks.
#   --mutate    (e): the fixed function with the old first-parent name-only pattern restored must redden (a) and ONLY (a).
#   --own-only  (f) only: scope of part D's own change on fixed SHAs; runs nothing else.
# Criterion (d) is NOT in this script: 092-verify.sh (default and --live-selftest) and standalone 039a-verify.sh are run by hand, one at a
# time on a quiet machine, and pasted into the task log (they would recurse or take hours here).
# Requires: git >= 2.31 (the behaviour under test), python3 (mutation only), a clone that can reach the pinned SHAs.

set -u
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1

MUTATE=0; OWN=0
for a in "$@"; do
    case "$a" in
        --mutate) MUTATE=1 ;;
        --own-only) OWN=1 ;;
        *) echo "usage: 089d-verify.sh [--mutate] [--own-only]" >&2; exit 99 ;;
    esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }

S092=docs/tasks/092-verify.sh
# Fixed SHAs (full 40 characters); no check below reads HEAD, a branch name or origin/main of the repository under test for its frame.
PIN_RED="32c641b5f56139a86c820f0b16d522c0f991d207"    # registry main when 089d was cut: the UNFIXED 092-verify.sh
PIN_FIX="becb41802d95fc776000f381a45728d08826b3b2"    # the commit that fixes post_tip_check (092-verify.sh only)
PIN_START="75eb9b0ce7ccddd8400eecd06f1a64eec0a1e753"  # 089d dispatch commit (adds the umbrella copy and the task file); 089d's own work starts after it
PIN_TIP="d065a8643eaf095488c944c7fda2efa64e0cdd95"    # last commit before the pin commit (a placeholder is RED: an unreachable pin is never skipped)
# 092's own pins, typed here (the controls below use them); asserted to be unchanged in both blobs.
P092_BASE="426873502a150ef746063c1b55c2cfbfeed31566"
P092_FINAL="ab31a88e6e828db689b64e73d4310320938570de"
P092_TIP="ab31a88e6e828db689b64e73d4310320938570de"
# Marker lines of the extraction (sed basic regexes, matched against both blobs; each must occur exactly once).
START_RE='^post_tip_check() {'
END_RE='^section "AC9 -- pinned own-change checks'
# Region 092 part D may change: from the post-TIP comment up to (excluding) the scope-pattern control loop.
REG_START_RE='^# AC9 post-TIP: the commits after TIP'
REG_END_RE='^for p in tools'
CTRL_START_RE='^( post_tip_check "$BASE" "$FINAL" )'
SECTION_RE='^section "AC9 -- pinned own-change checks'
OWN_FILES="docs/tasks/092-verify.sh
docs/tasks/089d-verify.sh
docs/tasks/089d-closed-verify-sweep-registry-d.md"

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT
GITID=(-c user.name=verify089d -c user.email=verify089d@invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null)

# BEGIN-LIB (functions only; a development harness may source exactly this block, which runs nothing by itself)
sg() { local d="$1"; shift; git -C "$d" "${GITID[@]}" "$@"; }
SC_BAD=0
must() { "$@" </dev/null >/dev/null 2>&1 || { echo "scenario step failed: $*" >&2; SC_BAD=1; }; }
cfile() {  # cfile DIR PATH CONTENT MSG: append a line to PATH and commit
    mkdir -p "$(dirname "$1/$2")"; printf '%s\n' "$3" >> "$1/$2"; must sg "$1" add -A; must sg "$1" commit -q -m "$4"
}
# Scenario builders. Each sets SC_ROOT (the working clone), SC_TIP, SC_HEAD and clears/sets SC_BAD.
scn_remote() {  # scn_remote NAME: upstream main (other.txt, shared.txt, a 092 file) + clone + branch "task" with TIP and one post-TIP 092-only commit
    local n="$1"; SC_BAD=0
    SC_UP="$TMP/$n-up"; SC_ROOT="$TMP/$n-wk"
    must git init -q -b main "$SC_UP"
    cfile "$SC_UP" other.txt a "m0"; cfile "$SC_UP" shared.txt s "m0b"; cfile "$SC_UP" docs/tasks/092-x.md b "m0c"
    must git clone -q "$SC_UP" "$SC_ROOT"
    must sg "$SC_ROOT" checkout -q -b task
    cfile "$SC_ROOT" docs/tasks/092-x.md tip "tip"
    SC_TIP="$(git -C "$SC_ROOT" rev-parse HEAD)"
    cfile "$SC_ROOT" docs/tasks/092-log.md p1 "post-TIP commit touching only a 092 file"
}
scn_adv() {  # main advances by a commit touching a file outside docs/tasks/092-* ; the clone fetches it
    cfile "$SC_UP" other.txt m1 "m1: main changes other.txt"; must sg "$SC_ROOT" fetch -q origin
}
scn_norem() {  # scn_norem NAME: single repository, NO remote; main advances after the branch is cut (the caller merges it)
    local n="$1"; SC_BAD=0; SC_ROOT="$TMP/$n-wk"
    must git init -q -b main "$SC_ROOT"
    cfile "$SC_ROOT" other.txt a "m0"; cfile "$SC_ROOT" docs/tasks/092-x.md b "m0c"
    must sg "$SC_ROOT" checkout -q -b task
    cfile "$SC_ROOT" docs/tasks/092-x.md tip "tip"
    SC_TIP="$(git -C "$SC_ROOT" rev-parse HEAD)"
    cfile "$SC_ROOT" docs/tasks/092-log.md p1 "post-TIP commit touching only a 092 file"
    must sg "$SC_ROOT" checkout -q main; cfile "$SC_ROOT" other.txt m1 "m1: main changes other.txt"
    must sg "$SC_ROOT" checkout -q task
}
scn_build() {  # scn_build ID -> sets SC_ROOT SC_TIP SC_HEAD
    local id="$1"
    case "$id" in
        g0)  scn_remote "$id" ;;
        a1)  scn_remote "$id"; scn_adv; must sg "$SC_ROOT" merge -q --no-ff -m "merge main into the branch" origin/main ;;
        a2)  scn_remote "$id"; scn_adv; must sg "$SC_ROOT" merge -q --no-commit --no-ff origin/main
             must sg "$SC_ROOT" checkout origin/main -- other.txt; must sg "$SC_ROOT" commit -q -m "merge main, resolved to main's version" ;;
        a2b) scn_remote "$id"; scn_adv; must sg "$SC_ROOT" merge -q --no-commit --no-ff origin/main
             printf 'evil\n' >> "$SC_ROOT/other.txt"; must sg "$SC_ROOT" add -A   # edit the merge ...
             must sg "$SC_ROOT" checkout origin/main -- other.txt; must sg "$SC_ROOT" commit -q -m "merge main, edited, then restored to main's version" ;;
        a3)  scn_norem "$id"; must sg "$SC_ROOT" merge -q --no-ff -m "merge main into the branch (no remote)" main ;;
        b1)  scn_remote "$id"; cfile "$SC_ROOT" other.txt x "branch commit touching a non-092 file" ;;
        b2i) scn_remote "$id"; scn_adv; must sg "$SC_ROOT" merge -q --no-commit --no-ff origin/main
             printf 'evil\n' >> "$SC_ROOT/other.txt"; must sg "$SC_ROOT" add -A; must sg "$SC_ROOT" commit -q -m "merge main, then edit a main-supplied file" ;;
        b2ii) scn_remote "$id"; scn_adv; must sg "$SC_ROOT" merge -q --no-commit --no-ff origin/main
             printf 'evil\n' > "$SC_ROOT/evil.txt"; must sg "$SC_ROOT" add -A; must sg "$SC_ROOT" commit -q -m "merge main, adding a new file" ;;
        b3)  scn_remote "$id"; must sg "$SC_ROOT" checkout -q -b side task; cfile "$SC_ROOT" side.txt s "side branch change"
             must sg "$SC_ROOT" checkout -q task; must sg "$SC_ROOT" merge -q --no-ff -m "merge a side branch" side ;;
        b4)  scn_remote "$id"; must sg "$SC_ROOT" branch s1 task; must sg "$SC_ROOT" branch s2 task
             must sg "$SC_ROOT" checkout -q s1; cfile "$SC_ROOT" side1.txt 1 "s1"
             must sg "$SC_ROOT" checkout -q s2; cfile "$SC_ROOT" docs/tasks/092-s2.md 2 "s2"
             must sg "$SC_ROOT" checkout -q task; must sg "$SC_ROOT" merge -q --no-ff -m "octopus" s1 s2 ;;
        b5)  scn_remote "$id"; scn_adv; must sg "$SC_ROOT" merge -q --no-ff -m "merge main" origin/main
             must sg "$SC_ROOT" branch -f main origin/main   # a LOCAL main that would accept the merge, if it were wrongly used as a fallback
             must sg "$SC_ROOT" update-ref -d refs/remotes/origin/main ;;
        b5b) scn_norem "$id"; must sg "$SC_ROOT" merge -q --no-ff -m "merge main (no remote)" main; must sg "$SC_ROOT" branch -D main ;;
        *)   echo "unknown scenario $id" >&2; SC_BAD=1 ;;
    esac
    SC_HEAD="$(git -C "$SC_ROOT" rev-parse HEAD 2>/dev/null)"
}
# run_blob BLOBFILE ROOTDIR TIP HEAD -> OUT (stdout+stderr) and RC; the stubs only print (the caller reads OUT).
run_blob() {
    OUT="$( ( ROOT="$2"; G() { git -C "$ROOT" "$@"; }; pass() { printf 'PASS  %s\n' "$1"; }; fail() { printf 'FAIL  %s\n' "$1"; }
              . "$1" && post_tip_check "$3" "$4" ) 2>&1 )"; RC=$?
}
verdict() {  # verdict of the last run_blob: PASS, FAIL, NA or ERR
    if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q '^PASS '; then echo PASS
    elif [ "$RC" != 0 ] && printf '%s\n' "$OUT" | grep -q '^FAIL '; then echo FAIL
    elif [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q '^NA '; then echo NA
    else echo ERR; fi
}
# END-LIB

# ---------------------------------------------------------------------------------------------------------------------
section "AC0 -- pins and temp clone"
printf 'git version: %s\n' "$(git --version)"
REAL="$TMP/real"
if git clone -q --no-hardlinks "$ROOT" "$REAL" 2>/dev/null; then pass "temp clone of the repository created (blobs below are read from it, not from the worktree or HEAD)"
else fail "cannot clone the repository"; echo; echo "SUMMARY failed=$FAILURES (stopped: no clone)"; exit "$FAILURES"; fi
rg() { git -C "$REAL" "$@"; }
for s in "$PIN_RED" "$PIN_FIX" "$PIN_START" "$PIN_TIP" "$P092_BASE" "$P092_FINAL"; do
    if printf '%s' "$s" | grep -q -E '^[0-9a-f]{40}$' && rg cat-file -e "$s^{commit}" 2>/dev/null; then pass "pin $s is a full SHA and exists"
    else fail "pin $s is not a full 40-hex SHA or does not exist (an unreachable pin is red, never skipped)"; fi
done

# Scope (f): part D's own change on fixed SHAs, and the region the 092 hunks may touch.
scope_checks() {
    local names exp f bad
    names="$(rg diff --name-only "$PIN_START" "$PIN_TIP" 2>/dev/null | sort)"; exp="$(printf '%s\n' "$OWN_FILES" | sort)"
    if [ -n "$names" ] && [ "$names" = "$exp" ]; then pass "(f) git diff --name-only PIN_START PIN_TIP equals exactly the three files of part D"
    else fail "(f) PIN_START..PIN_TIP is not exactly the three own files: $(printf '%s' "$names" | tr '\n' ' ')"; fi
    rg show "$PIN_RED:$S092" > "$TMP/red.sh" 2>/dev/null; rg show "$PIN_FIX:$S092" > "$TMP/fix.sh" 2>/dev/null
    if [ -s "$TMP/red.sh" ] && [ -s "$TMP/fix.sh" ]; then pass "(f) both 092-verify.sh blobs read"; else fail "(f) a 092-verify.sh blob is empty or unreadable"; return; fi
    if cmp -s "$TMP/red.sh" "$TMP/fix.sh"; then fail "(f) red and fixed blobs are identical (the fix changed nothing)"; else pass "(f) red and fixed blobs differ"; fi
    for f in red fix; do
        if [ "$(grep -c -- "$REG_START_RE" "$TMP/$f.sh")" = 1 ] && [ "$(grep -c -- "$REG_END_RE" "$TMP/$f.sh")" = 1 ]; then
            pass "(f) $f blob: region start and end markers occur exactly once"
        else fail "(f) $f blob: a region marker is missing or ambiguous"; fi
        awk -v s="$REG_START_RE" '$0 ~ s {exit} {print}' "$TMP/$f.sh" > "$TMP/$f.pre"
        awk -v e="$REG_END_RE" '$0 ~ e {p=1} p {print}' "$TMP/$f.sh" > "$TMP/$f.post"
        sed -n "/$SECTION_RE/,/$REG_END_RE/{/$REG_END_RE/!p}" "$TMP/$f.sh" > "$TMP/$f.mid"
        sed -n "/$CTRL_START_RE/,/$REG_END_RE/{/$REG_END_RE/!p}" "$TMP/$f.sh" > "$TMP/$f.ctrl"
    done
    if [ -s "$TMP/red.pre" ] && [ -s "$TMP/red.post" ] && [ -s "$TMP/red.mid" ] && [ -s "$TMP/red.ctrl" ]; then
        pass "(f) positive control: every sliced region of the red blob is non-empty"
    else fail "(f) a sliced region of the red blob is empty (the slicing found nothing)"; fi
    if cmp -s "$TMP/red.pre" "$TMP/fix.pre"; then pass "(f) everything BEFORE the post-TIP comment is byte-identical (pins BASE/FINAL/TIP and own_change_checks included)"
    else fail "(f) a hunk before the post-TIP comment (pins or own_change_checks changed)"; fi
    if cmp -s "$TMP/red.post" "$TMP/fix.post"; then pass "(f) everything FROM the scope-pattern control loop on is byte-identical"; else fail "(f) a hunk after the AC9 controls"; fi
    if cmp -s "$TMP/red.mid" "$TMP/fix.mid"; then pass "(f) the AC9 section from its header to the control loop (call-site line and all existing controls) is byte-identical"
    else fail "(f) the AC9 section (call site or controls) differs between red and fixed"; fi
    if cmp -s "$TMP/red.ctrl" "$TMP/fix.ctrl"; then pass "(c) the existing AC9 post-TIP controls (incl. the merged-case control) are byte-for-byte unchanged"
    else fail "(c) an existing AC9 control differs between red and fixed"; fi
    for f in red fix; do
        if grep -q "^BASE=$P092_BASE " "$TMP/$f.sh" && grep -q "^FINAL=$P092_FINAL " "$TMP/$f.sh" && grep -q "^TIP=$P092_TIP " "$TMP/$f.sh"; then
            pass "(f) $f blob: 092's BASE, FINAL and TIP pins equal the typed ones"
        else fail "(f) $f blob: a 092 pin differs from the typed one"; fi
    done
    bad="$(diff <(cat "$TMP/red.pre" "$TMP/red.post") <(cat "$TMP/fix.pre" "$TMP/fix.post") | wc -l)"
    if [ "$bad" = 0 ]; then pass "(f) outside the post-TIP comment/function/controls region the two blobs are identical (diff lines 0)"
    else fail "(f) $bad diff line(s) outside the region"; fi
}
if [ "$OWN" = 1 ]; then
    section "(f) scope"; scope_checks
    echo; echo "SUMMARY failed=$FAILURES"; exit "$FAILURES"
fi

# ---------------------------------------------------------------------------------------------------------------------
section "Extraction (positive controls)"
extract() {  # extract SHA OUTFILE: post_tip_check from that commit's 092-verify.sh (sed range between the marker lines, end marker excluded)
    local whole="$TMP/whole.$$"
    if ! rg show "$1:$S092" > "$whole" 2>/dev/null; then : > "$2"; return 1; fi
    if [ "$(grep -c -- "$START_RE" "$whole")" != 1 ] || [ "$(grep -c -- "$END_RE" "$whole")" != 1 ]; then : > "$2"; return 1; fi
    sed -n "/$START_RE/,/$END_RE/{/$END_RE/!p}" "$whole" > "$2"
}
RED_FN="$TMP/red.fn"; FIX_FN="$TMP/fix.fn"
if extract "$PIN_RED" "$RED_FN" && [ "$(wc -l < "$RED_FN")" -gt 8 ] && head -1 "$RED_FN" | grep -q '^post_tip_check() {'; then
    pass "red extraction is non-empty ($(wc -l < "$RED_FN") lines) and starts at post_tip_check"
else fail "red extraction is empty or malformed (a sed range that finds nothing is a broken search)"; fi
if extract "$PIN_FIX" "$FIX_FN" && [ "$(wc -l < "$FIX_FN")" -gt 8 ] && head -1 "$FIX_FN" | grep -q '^post_tip_check() {'; then
    pass "fixed extraction is non-empty ($(wc -l < "$FIX_FN") lines) and starts at post_tip_check"
else fail "fixed extraction is empty or malformed"; fi
if grep -q -- 'log --first-parent --name-only' "$RED_FN"; then pass "red extraction contains the old pattern (it is the unfixed function)"
else fail "red extraction lacks the old pattern; PIN_RED is not the unfixed script"; fi
if grep -q -- 'log --first-parent --name-only' "$FIX_FN"; then fail "fixed extraction still contains the old first-parent name-only pattern"
else pass "fixed extraction no longer contains the old pattern"; fi
if grep -q -- 'diff-tree --cc' "$FIX_FN" && grep -q -- 'refs/remotes/origin/main' "$FIX_FN" && grep -q -- 'octopus' "$FIX_FN"; then
    pass "fixed extraction has the --cc listing, the local main ref and the octopus rule"
else fail "fixed extraction lacks --cc, the main ref or the octopus rule"; fi
# D forbidden: no merge skipped (the only return 0 lines are the merged NA case and the final PASS line)
if [ "$(grep -c 'return 0' "$FIX_FN")" = 2 ] && [ "$(grep 'return 0' "$FIX_FN" | grep -c -E 'NOT-APPLICABLE|post-TIP: commits after TIP touch only')" = 2 ]; then
    pass "fixed extraction has exactly two 'return 0' lines (merged NA, final PASS): no skip path"
else fail "fixed extraction has an unexpected 'return 0' (a skip?)"; fi

# ---------------------------------------------------------------------------------------------------------------------
# case table: ID | group | expected verdict with the fix | expected verdict on the unfixed function (asserted for groups a and g) | needle in the fixed output | text the fixed output must NOT contain
CASES="g0|g|PASS|PASS|(1 file name(s))|
a1|a|PASS|FAIL|(1 file name(s))|
a2|a|PASS|FAIL|(1 file name(s))|
a2b|a|PASS|FAIL|(1 file name(s))|
a3|a|PASS|FAIL|(1 file name(s))|
b1|b|FAIL|FAIL|other.txt|
b2i|b|FAIL|FAIL|other.txt|
b2ii|b|FAIL|FAIL|evil.txt|other.txt
b3|b|FAIL|FAIL|side.txt|
b4|b|FAIL|FAIL|octopus|
b5|b|FAIL|FAIL|other.txt|
b5b|b|FAIL|FAIL|other.txt|"
NEEDLE_RED_A="other.txt"   # on (a) the unfixed function must be red FOR THE RIGHT REASON: it names the file main changed

run_cases() {  # run_cases FNFILE LABEL -> $TMP/res.LABEL ("id verdict" lines) and $TMP/out.LABEL.ID
    local fnf="$1" label="$2" id grp ef er nd nn
    : > "$TMP/res.$label"
    while IFS='|' read -r id grp ef er nd nn; do
        scn_build "$id"
        if [ "$SC_BAD" != 0 ] || [ -z "$SC_HEAD" ]; then fail "scenario $id could not be built"; echo "$id ERR" >> "$TMP/res.$label"; : > "$TMP/out.$label.$id"; continue; fi
        run_blob "$fnf" "$SC_ROOT" "$SC_TIP" "$SC_HEAD"
        echo "$id $(verdict)" >> "$TMP/res.$label"
        printf '%s\n' "$OUT" > "$TMP/out.$label.$id"
    done <<< "$CASES"
}

if [ "$MUTATE" = 0 ]; then
    section "(a)/(b) red first, then controls red after the fix: each scenario run against the UNFIXED and the FIXED function"
    run_cases "$RED_FN" red; run_cases "$FIX_FN" fix
    while IFS='|' read -r id grp ef er nd nn; do
        gv="$(grep "^$id " "$TMP/res.fix" | cut -d' ' -f2)"; rv="$(grep "^$id " "$TMP/res.red" | cut -d' ' -f2)"
        printf 'case %-5s unfixed=%-4s fixed=%-4s  fixed output: %s\n' "$id" "$rv" "$gv" "$(head -c 230 "$TMP/out.fix.$id" | tr '\n' ' ')"
        if [ "$gv" = "$ef" ]; then pass "[$id] fixed function verdict is $ef"
        else fail "[$id] fixed function verdict is $gv, required $ef (output: $(head -c 300 "$TMP/out.fix.$id" | tr '\n' ' '))"; fi
        if grep -q -F -- "$nd" "$TMP/out.fix.$id"; then pass "[$id] fixed output contains '$nd'"; else fail "[$id] fixed output lacks '$nd'"; fi
        if [ -n "$nn" ]; then
            if grep -q -F -- "$nn" "$TMP/out.fix.$id"; then fail "[$id] fixed output names '$nn' (it must not: that file is main's, not a resolution edit)"
            else pass "[$id] fixed output does not name '$nn'"; fi
        fi
        if [ "$grp" = a ] || [ "$grp" = g ]; then
            if [ "$rv" = "$er" ]; then pass "[$id] UNFIXED function verdict is $er"
            else fail "[$id] UNFIXED function verdict is $rv, required $er (a fixture that passes on the unfixed script is rejected)"; fi
            if [ "$grp" = a ]; then
                if grep -q -F -- "$NEEDLE_RED_A" "$TMP/out.red.$id"; then pass "[$id] unfixed output is red for the right reason (names $NEEDLE_RED_A)"
                else fail "[$id] unfixed output does not name $NEEDLE_RED_A"; fi
            fi
        fi
    done <<< "$CASES"

    # (c) the existing AC9 controls on the FIXED function, with 092's real pins, in the temp clone of the repository
    section "(c) existing AC9 controls on the fixed function (real 092 pins, temp clone)"
    z=0000000000000000000000000000000000000000
    run_blob "$FIX_FN" "$REAL" "$P092_BASE" "$P092_FINAL"
    if [ "$RC" != 0 ] && printf '%s\n' "$OUT" | grep -q '^FAIL  post-TIP: commits after TIP touch files outside docs/tasks/092-'; then pass "(c) BASE..FINAL as the post-TIP range is red"
    else fail "(c) BASE..FINAL not red (rc $RC: $(printf '%s' "$OUT" | head -c 200))"; fi
    run_blob "$FIX_FN" "$REAL" "$P092_BASE" "$z"
    if [ "$RC" != 0 ] && printf '%s\n' "$OUT" | grep -q '^FAIL '; then pass "(c) an unreachable HEAD pin is red, never skipped"; else fail "(c) unreachable HEAD pin not red (rc $RC)"; fi
    run_blob "$FIX_FN" "$REAL" "$z" "$P092_BASE"
    if [ "$RC" != 0 ] && printf '%s\n' "$OUT" | grep -q '^FAIL '; then pass "(c) an unreachable TIP pin is red, never skipped"; else fail "(c) unreachable TIP pin not red (rc $RC)"; fi
    run_blob "$FIX_FN" "$REAL" "$P092_FINAL" "$P092_BASE"
    if [ "$RC" != 0 ] && printf '%s\n' "$OUT" | grep -q '^FAIL  post-TIP'; then pass "(c) a non-ancestor TIP (rewritten away) is red"; else fail "(c) non-ancestor TIP not red (rc $RC)"; fi
    MC="$TMP/mergedclone"
    if git clone -q --no-hardlinks "$REAL" "$MC" 2>/dev/null && git -C "$MC" checkout -q --detach "$P092_BASE" 2>/dev/null \
        && git -C "$MC" "${GITID[@]}" merge -q --no-ff -m "synthetic merge of the branch into main" "$P092_TIP" >/dev/null 2>&1; then
        MH="$(git -C "$MC" rev-parse HEAD)"
        run_blob "$FIX_FN" "$MC" "$P092_TIP" "$MH"
        if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q '^NA    post-TIP NOT-APPLICABLE (merged)' && ! printf '%s\n' "$OUT" | grep -q '^PASS'; then
            pass "(c) the merged case prints NOT-APPLICABLE (merged), not a PASS"
        else fail "(c) merged case wrong (rc $RC: $(printf '%s' "$OUT" | head -c 200))"; fi
    else fail "(c) could not build the synthetic merged clone"; fi

    section "(f) scope"; scope_checks
else
    section "(e) mutation: the old first-parent name-only pattern restored in a temp copy of the FIXED function"
    MUT_FN="$TMP/mut.fn"
    python3 -I - "$FIX_FN" "$MUT_FN" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = s.index('    files="$(G log --first-parent --no-merges')
b = s.index("    files=\"$(printf '%s\\n' \"$files\" | sed '/^$/d' | sort -u)\"")
old = '    files="$(G log --first-parent --name-only --format= "$t..$h" 2>/dev/null | sort -u | sed \'/^$/d\')"\n'
open(sys.argv[2], 'w').write(s[:a] + old + s[b:])
PY
    if [ -s "$MUT_FN" ] && grep -q -- 'log --first-parent --name-only' "$MUT_FN" && ! cmp -s "$MUT_FN" "$FIX_FN"; then
        pass "(e) positive control: the mutant exists, differs from the fixed function and contains the old pattern"
    else fail "(e) the mutant was not produced"; fi
    if bash -n "$MUT_FN" 2>/dev/null; then pass "(e) the mutant parses"; else fail "(e) the mutant does not parse"; fi
    run_cases "$MUT_FN" mut
    red_ids=""; other_bad=""
    while IFS='|' read -r id grp ef er nd nn; do
        mv="$(grep "^$id " "$TMP/res.mut" | cut -d' ' -f2)"
        printf 'mutant %-5s verdict=%-4s expected-with-fix=%s group=%s\n' "$id" "$mv" "$ef" "$grp"
        if [ "$grp" = a ]; then
            if [ "$mv" != "$ef" ]; then pass "(e) [$id] the mutant reddens (a): verdict $mv, the fixed function gives $ef"; red_ids="$red_ids $id"
            else fail "(e) [$id] the mutant does NOT redden (a)"; fi
        else
            if [ "$mv" = "$ef" ]; then pass "(e) [$id] the mutant leaves this case unchanged ($mv)"
            else fail "(e) [$id] the mutant also changes a non-(a) case: $mv, expected $ef"; other_bad="$other_bad $id"; fi
        fi
    done <<< "$CASES"
    if [ -n "$red_ids" ] && [ -z "$other_bad" ]; then pass "(e) the mutant reddens exactly the (a) cases:$red_ids"
    else fail "(e) mutation result is not 'only (a)' (red:$red_ids; other:$other_bad)"; fi
    # second mutant: the forbidden "--no-merges alone" variant (merge handling removed; non-merge first-parent commits only)
    MUT2_FN="$TMP/mut2.fn"
    python3 -I - "$FIX_FN" "$MUT2_FN" <<'PY2'
import sys
s = open(sys.argv[1]).read()
a = s.index('    merges="$(G rev-list --first-parent --merges')
b = s.index("    files=\"$(printf '%s\\n' \"$files\" | sed '/^$/d' | sort -u)\"")
open(sys.argv[2], 'w').write(s[:a] + s[b:])
PY2
    if [ -s "$MUT2_FN" ] && ! grep -q -- 'diff-tree --cc' "$MUT2_FN" && grep -q -- '--no-merges' "$MUT2_FN" && bash -n "$MUT2_FN" 2>/dev/null; then
        pass "(e2) positive control: the --no-merges-alone mutant exists, parses, has no --cc/merge handling"
    else fail "(e2) the --no-merges-alone mutant was not produced"; fi
    run_cases "$MUT2_FN" mut2
    flipped=""; other2=""
    while IFS='|' read -r id grp ef er nd nn; do
        mv="$(grep "^$id " "$TMP/res.mut2" | cut -d' ' -f2)"
        if [ "$mv" != "$ef" ]; then flipped="$flipped $id"; fi
        printf 'mutant2 %-5s verdict=%-4s expected-with-fix=%s\n' "$id" "$mv" "$ef"
    done <<< "$CASES"
    # Every merge scenario whose RED depends on merge handling flips to PASS: b2i/b2ii (--cc), b3 (C^1..C^2 diff), b4 (octopus), b5/b5b (no main ref).
    # All (a) cases, g0 and b1 keep the fixed function's verdict.
    if [ "$flipped" = " b2i b2ii b3 b4 b5 b5b" ]; then pass "(e2) the --no-merges-alone mutant flips exactly b2i b2ii b3 b4 b5 b5b to PASS; (a), g0 and b1 are unchanged"
    else fail "(e2) --no-merges-alone mutant flipped:$flipped (expected exactly b2i b2ii b3 b4 b5 b5b)"; fi
fi

echo; echo "SUMMARY failed=$FAILURES"
exit "$FAILURES"
