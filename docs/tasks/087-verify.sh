#!/usr/bin/env bash
#
# 087-verify.sh -- the runnable verification artefact for task 087 (MANAGER.md Section 2c).
#
# Task 087: 032-verify.sh (N5, N5b) and 067-verify.sh (AC2.5) read docs/contracts/README.md at HEAD as evidence of THEIR OWN
# change; task 082 legitimately edits that file ("eight" -> "nine" prose documents, "None of the three tasks" -> "four"), so all
# three went red on a merge with 082's branch. They now read the README at their task's pinned FINAL commit. Demonstrates
# acceptance criteria 1, 2 and 4 of docs/tasks/087-repin-032-067-readme.md. Criterion 3 (every closed script green on HEAD and on
# the merge with 082's branch, one script at a time on a quiet machine) is a sequential run done by hand and logged; it is not
# repeated here.
#
# Usage:  docs/tasks/087-verify.sh [--mutate] [NODE_MODULES_DIR]      (any cwd inside the repository)
#   (no flag)  AC0 (the pins are the tasks' own merged PR ranges; the README checks no longer read HEAD),
#              AC1 (RED FIRST: on a throw-away merge of 082's branch onto the base, the OLD 032 and 067 fail and name N5, N5b,
#              AC2.5; on the same merge onto HEAD the NEW ones pass; on the plain base the old 032 is green, so the merge is
#              the cause),
#              AC4 (087's own change, measured on fixed SHAs: the red commit touches only 087's files, the fix commit only
#              032-verify.sh and 067-verify.sh).
#   --mutate   AC2 (each re-pinned check widened back to HEAD, and unreachable pins: each red on the 082 merge, none skipped;
#              each widened check turns only itself red).
#   --own-only  AC4 only (087's own change, on the fixed SHAs); fast, runs no other suite. Used by the --mutate controls AC2.o*.
#   NODE_MODULES_DIR  (or env WOM_NODE_MODULES, else <repo root>/tools/dev/node_modules; install with
#                     npm ci --prefix tools/dev) a node_modules directory containing ajv 8, needed by 067-verify.sh -> 062.
# Everything runs on the COMMITTED state (HEAD) in temporary clones; the caller's worktree is never modified.
# Network: none (082's tip is fetched from this repository). Exit code: the number of failed checks. Run it with no other
# registry suite running (it runs 032-verify.sh and 067-verify.sh, several times).
# Requires: git, python3, node, plus everything 032-verify.sh and 067-verify.sh require.

set -u
set -o pipefail

MUTATE=0
OWN=0
NM="${WOM_NODE_MODULES:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/tools/dev/node_modules}"
for a in "$@"; do
    case "$a" in
        --mutate) MUTATE=1 ;;
        --own-only) OWN=1 ;;
        *) NM="$a" ;;
    esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }
GITID=(-c user.name=verify087 -c user.email=verify087@invalid -c commit.gpgsign=false)
HEADREV="$(git -C "$ROOT" rev-parse HEAD)"
S032=docs/tasks/032-verify.sh
S067=docs/tasks/067-verify.sh
S070=docs/tasks/070-verify.sh
README=docs/contracts/README.md

# Fixed SHAs. The frame of every own-change check below is one of these, never HEAD (REVIEW-CHECKLIST item 12).
M032="4d4a204"          # registry PR #4, task 032's merge commit
M067="ac22c8f"          # registry PR #11, task 067's merge commit
T082="65f39793d30d468bb7afed08ef26c44f6cce9bfe"   # tip of origin/task/082-pipeline-trigger-contract (registry PR #20) when 087 was cut
# 087's own commits (AC4): explicit full 40-char SHAs of 087's own PR range, never HEAD (REVIEW-CHECKLIST item 12; the 084 / 039a pattern).
# BASE = registry origin/main when 087 was cut; FINAL = the last commit that touched any script of the range (abede5d, 087-verify.sh);
# TIP = the last commit of the branch before the item-12 fix round (the task-file-only log commit). FINAL..TIP touches only docs/tasks/087-* files.
PIN087_BASE="208c6d1ae63ff56ccac85c6fc9a200ac77259fda"   # registry origin/main when 087 was cut (merge of PR #19)
PIN087_RED="5e5b107a32a8223b9ea0b8a7fc49e207b64b663f"    # 087-verify.sh + task file only
PIN087_FIX="bb1082039f3d59ce5d918035be863b5a41c6b238"    # 032-verify.sh and 067-verify.sh re-pinned
PIN087_PIN="489bd264c90557fba0d3b7bd799423501aa11993"    # the log commit of the first round (the parent of the 070 commit)
PIN087_070="5da249bc6e380d99ba65752a4da5a7820e8501c4"    # manager scope extension: 070-verify.sh AC4.m1 only
PIN087_FINAL="abede5d2223a6271e3e2424ce4f5d9b581323039"  # last commit touching the scripts before the item-12 fix round
PIN087_TIP="49988fd827d2e7ea85f4a24c5b73a137dc26663a"    # last branch commit before the item-12 fix round

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT

# mk_merge DEST REV : a clone detached at REV with 082's tip merged in (the frame of the final run of task 082).
# The merge is a real commit, so the scripts' own temp clones see it as HEAD. Fails (never skips) if 082's tip is unreachable.
mk_merge() {
    git clone -q --no-hardlinks "$ROOT" "$1" 2>/dev/null || return 1
    git -C "$1" cat-file -e "$T082^{commit}" 2>/dev/null || git -C "$1" fetch -q "$ROOT" "$T082" 2>/dev/null || return 1
    git -C "$1" cat-file -e "$T082^{commit}" 2>/dev/null || return 1
    git -C "$1" checkout -q --detach "$2" || return 1
    git -C "$1" "${GITID[@]}" merge --no-ff -q -m "087 frame: merge 082's tip onto $2" "$T082" >/dev/null 2>&1 || return 1
    git -C "$1" show HEAD:"$README" | grep -qF 'None of the four tasks implements checking logic' || return 1
}

run_in() {   # run_in DIR OUTFILE CMD... : run CMD in DIR, output to OUTFILE; echo the exit code
    local d="$1" o="$2"; shift 2
    ( cd "$d" && PYTHONDONTWRITEBYTECODE=1 WOM_NODE_MODULES="$NM" "$@" ) > "$o" 2>&1
    echo $?
}
first_fail() { grep -E '^FAIL' "$1" | head -n"${2:-4}" | cut -c1-130 | tr '\n' '|'; }

# ==================================================================================================
if [ "$MUTATE" = 0 ]; then

# 032 and 067 as of 087's pinned TIP (never the working tree / HEAD: a later branch may touch them; item 12). An unreadable TIP FAILS.
S032T="$TMP/tip-032-verify.sh"; S067T="$TMP/tip-067-verify.sh"; : > "$S032T"; : > "$S067T"
git -C "$ROOT" show "$PIN087_TIP:$S032" > "$S032T" 2>/dev/null && git -C "$ROOT" show "$PIN087_TIP:$S067" > "$S067T" 2>/dev/null \
    || fail "AC0.0 cannot read $S032 / $S067 at the pinned TIP $PIN087_TIP"

if [ "$OWN" = 0 ]; then
section "AC0 -- the README checks read the task's pinned FINAL, and the pins are the tasks' own PR ranges"
pin_of() { sed -n "s/^$2=\"\{0,1\}\([0-9a-f]\{7,\}\)\"\{0,1\}\([[:space:]].*\)\{0,1\}$/\1/p" "$1" | head -n1; }
p032=$(pin_of "$S032T" README_PIN_FINAL); s032=$(pin_of "$S032T" SCOPE_FINAL); f067=$(pin_of "$S067T" FINAL); b067=$(pin_of "$S067T" BASE)
if [ -z "$p032" ] || [ -z "$s032" ] || [ -z "$f067" ] || [ -z "$b067" ]; then
    fail "AC0.1 cannot read README_PIN_FINAL / SCOPE_FINAL from $S032 or FINAL / BASE from $S067 (a search that finds nothing is broken)"
else
    [ "$(git -C "$ROOT" rev-parse "$p032^{commit}" 2>/dev/null)" = "$(git -C "$ROOT" rev-parse "$M032^2" 2>/dev/null)" ] \
        && pass "AC0.1 032's README_PIN_FINAL=$p032 is the last commit of PR #4 (git rev-parse $M032^2)" || fail "AC0.1 032's README_PIN_FINAL=$p032 is not $M032^2"
    [ "$(git -C "$ROOT" rev-parse "$p032^{commit}" 2>/dev/null)" = "$(git -C "$ROOT" rev-parse "$s032^{commit}" 2>/dev/null)" ] \
        && pass "AC0.2 README_PIN_FINAL is the same commit as 032's SCOPE_FINAL=$s032 (one frame for 032's own change)" || fail "AC0.2 README_PIN_FINAL=$p032 differs from SCOPE_FINAL=$s032"
    [ "$(git -C "$ROOT" rev-parse "$f067^{commit}" 2>/dev/null)" = "$(git -C "$ROOT" rev-parse "$M067^2" 2>/dev/null)" ] \
        && pass "AC0.3 067's FINAL=$f067 is the last commit of PR #11 (git rev-parse $M067^2)" || fail "AC0.3 067's FINAL=$f067 is not $M067^2"
    [ "$(git -C "$ROOT" rev-parse "$b067^{commit}" 2>/dev/null)" = "$(git -C "$ROOT" merge-base "$M067^1" "$M067^2" 2>/dev/null)" ] \
        && pass "AC0.4 067's BASE=$b067 is PR #11's fork point (git merge-base $M067^1 $M067^2)" || fail "AC0.4 067's BASE=$b067 is not PR #11's fork point"
fi
if grep -qE '^[^#]*git show "\$README_PIN_FINAL:\$CONTRACTS_README_PATH"' "$S032T"; then
    pass "AC0.5 $S032 materialises the README with git show \"\$README_PIN_FINAL:...\""
else fail "AC0.5 $S032 does not read the README with git show \"\$README_PIN_FINAL:...\""; fi
if grep -E '^(expect_hits|expect_hits_flow) "N5b? ' -A1 "$S032T" | grep -E 'CONTRACTS_README_PATH|HEAD:' >/dev/null; then
    fail "AC0.6 an N5/N5b call reads the README path (HEAD) instead of the pinned copy"
else pass "AC0.6 neither N5 nor N5b call reads the README path (HEAD) directly"; fi
a25=$(grep -E '^if .*AC2\.5|AC2\.5 the' "$S067T" | head -n3)
if printf '%s\n' "$a25" | grep -qF 'show "$FINAL:docs/contracts/README.md"' && ! printf '%s\n' "$a25" | grep -qF '$TMP/head/docs/contracts/README.md'; then
    pass "AC0.7 $S067 AC2.5 reads the README at \"\$FINAL\" and not from the HEAD clone"
else fail "AC0.7 $S067 AC2.5 does not read the README at \"\$FINAL\" (or still reads the HEAD clone): $(printf '%s' "$a25" | cut -c1-160)"; fi

section "AC1 -- red first: merge 082's branch; the OLD 032 and 067 fail, the NEW ones pass on the same merge"
# --- old pair: the scripts as they were at the base, on 082's merge onto the base
if ! mk_merge "$TMP/OLD" "$PIN087_BASE"; then fail "AC1.0 cannot build the merge of $T082 onto $PIN087_BASE"; else
    git -C "$TMP/OLD" diff --stat HEAD^1 HEAD | tail -n1 | sed 's/^/  082 brings: /'
    rc=$(run_in "$TMP/OLD" "$TMP/old032.out" bash $S032)
    if [ "$rc" != 0 ] && grep -q '^FAIL  N5 ' "$TMP/old032.out" && grep -q '^FAIL  N5b ' "$TMP/old032.out"; then
        pass "AC1.1 the OLD 032-verify.sh exits $rc on the merge with 082: N5 and N5b FAIL"
    else fail "AC1.1 the OLD 032 did not fail N5 and N5b on the merge (exit $rc): $(first_fail "$TMP/old032.out")"; fi
    rc=$(run_in "$TMP/OLD" "$TMP/old067.out" bash $S067 "$NM")
    if [ "$rc" != 0 ] && grep -q '^FAIL  AC2\.5 ' "$TMP/old067.out" && grep -q '^FAIL  AC3\.1 ' "$TMP/old067.out"; then
        pass "AC1.2 the OLD 067-verify.sh exits $rc on the merge with 082: AC2.5 and AC3.1 FAIL"
    else fail "AC1.2 the OLD 067 did not fail AC2.5 and AC3.1 on the merge (exit $rc): $(first_fail "$TMP/old067.out")"; fi
fi
# --- control: the same old 032 on the plain base is green, so the merge with 082 is the cause
if ! git clone -q --no-hardlinks "$ROOT" "$TMP/BASE" 2>/dev/null || ! git -C "$TMP/BASE" checkout -q --detach "$PIN087_BASE"; then fail "AC1.3 cannot clone the base $PIN087_BASE"; else
    rc=$(run_in "$TMP/BASE" "$TMP/base032.out" bash $S032)
    if [ "$rc" = 0 ]; then pass "AC1.3 control: the OLD 032 exits 0 on the plain base (the merge with 082 is what reddens it)"; else fail "AC1.3 control: the OLD 032 exits $rc on the plain base: $(first_fail "$TMP/base032.out")"; fi
fi
# --- new pair: HEAD, on the same merge
if ! mk_merge "$TMP/NEW" "$HEADREV"; then fail "AC1.4 cannot build the merge of $T082 onto HEAD"; else
    rc=$(run_in "$TMP/NEW" "$TMP/new032.out" bash $S032)
    if [ "$rc" = 0 ] && grep -q '^PASS  N5 ' "$TMP/new032.out" && grep -q '^PASS  N5b ' "$TMP/new032.out"; then
        pass "AC1.4 the NEW 032-verify.sh exits 0 on the merge with 082, N5 and N5b PASS"
    else fail "AC1.4 the NEW 032 on the merge (exit $rc): $(first_fail "$TMP/new032.out")"; fi
    rc=$(run_in "$TMP/NEW" "$TMP/new067.out" bash $S067 "$NM")
    if [ "$rc" = 0 ] && grep -q '^PASS  AC2\.5 ' "$TMP/new067.out" && grep -q '^PASS  AC3\.1 ' "$TMP/new067.out"; then
        pass "AC1.5 the NEW 067-verify.sh exits 0 on the merge with 082, AC2.5 and AC3.1 PASS"
    else fail "AC1.5 the NEW 067 on the merge (exit $rc): $(first_fail "$TMP/new067.out")"; fi
fi

fi   # OWN = 0

section "AC4 -- 087's own change, measured on fixed SHAs (never HEAD)"
if [ "$PIN087_RED" = "__RED__" ] || [ "$PIN087_FIX" = "__FIX__" ]; then
    fail "AC4.0 the 087 red/fix SHAs are not pinned yet"
else
    for s in "$PIN087_BASE" "$PIN087_RED" "$PIN087_FIX" "$PIN087_FINAL" "$PIN087_TIP"; do
        git -C "$ROOT" cat-file -e "$s^{commit}" 2>/dev/null && pass "AC4.1 pin $s exists" || fail "AC4.1 pin $s does not exist"
    done
    [ "$(git -C "$ROOT" rev-parse "$PIN087_RED^" 2>/dev/null)" = "$(git -C "$ROOT" rev-parse "$PIN087_BASE^{commit}" 2>/dev/null)" ] \
        && pass "AC4.2 the red commit's parent is the base" || fail "AC4.2 the red commit's parent is not the base"
    [ "$(git -C "$ROOT" rev-parse "$PIN087_FIX^" 2>/dev/null)" = "$(git -C "$ROOT" rev-parse "$PIN087_RED^{commit}" 2>/dev/null)" ] \
        && pass "AC4.3 the fix commit follows the red commit directly" || fail "AC4.3 the fix commit does not follow the red commit"
    git -C "$ROOT" merge-base --is-ancestor "$PIN087_FIX" "$PIN087_TIP" && pass "AC4.4 the fix commit is an ancestor of the pinned TIP" || fail "AC4.4 the fix commit is not an ancestor of the pinned TIP"
    red_files="$(git -C "$ROOT" diff --name-only "$PIN087_BASE" "$PIN087_RED" 2>/dev/null | sort | tr '\n' ' ')"
    [ "$red_files" = "docs/tasks/087-repin-032-067-readme.md docs/tasks/087-verify.sh " ] \
        && pass "AC4.5 the red commit touches only 087-verify.sh and the task file" || fail "AC4.5 the red commit touches: $red_files"
    fix_files="$(git -C "$ROOT" diff --name-only "$PIN087_RED" "$PIN087_FIX" 2>/dev/null | sort | tr '\n' ' ')"
    [ "$fix_files" = "docs/tasks/032-verify.sh docs/tasks/067-verify.sh " ] \
        && pass "AC4.6 the fix commit touches only 032-verify.sh and 067-verify.sh" || fail "AC4.6 the fix commit touches: $fix_files"
    # the whole PR range (BASE..TIP, never HEAD) stays inside the declared file scope. A diff that cannot be computed FAILS (never an empty list).
    if ! scope_files="$(git -C "$ROOT" diff --name-only "$PIN087_BASE" "$PIN087_TIP" 2>&1)"; then
        fail "AC4.7 cannot compute $PIN087_BASE..$PIN087_TIP: $(printf '%s' "$scope_files" | head -n1 | cut -c1-100)"
    else
        extra="$(printf '%s\n' "$scope_files" | grep -vxE 'docs/tasks/032-verify\.sh|docs/tasks/067-verify\.sh|docs/tasks/070-verify\.sh|docs/tasks/087-repin-032-067-readme\.md|docs/tasks/087-verify\.sh' | tr '\n' ' ')"
        [ -n "$scope_files" ] && [ -z "$extra" ] && pass "AC4.7 base..TIP stays inside the declared file scope" || fail "AC4.7 out-of-scope files changed in base..TIP (or the range is empty): $extra"
    fi
    # the fix commit changes README-pin checks only: in 067 only the AC2.5 line, in 032 only the pin block, N5/N5b and the variable
    d067="$(git -C "$ROOT" diff -U0 "$PIN087_RED" "$PIN087_FIX" -- $S067 | grep -E '^[+-][^+-]' | grep -vE 'AC2\.5|Task 087|^[+-]#' | wc -l)"
    [ "$d067" = 0 ] && pass "AC4.8 in 067-verify.sh only the AC2.5 check (and comments) changed" || fail "AC4.8 067-verify.sh changed outside AC2.5 and comments ($d067 lines)"
    d032="$(git -C "$ROOT" diff -U0 "$PIN087_RED" "$PIN087_FIX" -- $S032 | grep -E '^[+-][^+-]' | grep -vE '^[+-]#|README|CONTRACTS_README|N5|^\+(if|else|fi|    fail|    pass|    : )' | wc -l)"
    [ "$d032" = 0 ] && pass "AC4.9 in 032-verify.sh only the README pin block, the N5/N5b file argument and comments changed" || fail "AC4.9 032-verify.sh changed outside the README pin ($d032 lines)"
    # the manager's scope extension: 070-verify.sh changed in ONE hunk, replacing the single AC4.m1 line
    if [ "$PIN087_070" = "__070__" ]; then fail "AC4.11 the 070 SHA is not pinned yet"; else
        [ "$(git -C "$ROOT" rev-parse "$PIN087_070^" 2>/dev/null)" = "$(git -C "$ROOT" rev-parse "$PIN087_PIN^{commit}" 2>/dev/null)" ] \
            && pass "AC4.11 the 070 commit follows the pin commit directly" || fail "AC4.11 the 070 commit does not follow the pin commit"
        git -C "$ROOT" merge-base --is-ancestor "$PIN087_070" "$PIN087_TIP" && pass "AC4.12 the 070 commit is an ancestor of the pinned TIP" || fail "AC4.12 the 070 commit is not an ancestor of the pinned TIP"
        files070="$(git -C "$ROOT" diff --name-only "$PIN087_PIN" "$PIN087_070" 2>/dev/null | tr '\n' ' ')"
        d070="$(git -C "$ROOT" diff -U0 "$PIN087_PIN" "$PIN087_070" -- $S070 2>/dev/null)"
        if [ "$files070" = "$S070 " ] && [ "$(printf '%s\n' "$d070" | grep -c '^@@')" = 1 ] \
            && [ "$(printf '%s\n' "$d070" | grep -cE '^-[^-]')" = 1 ] && printf '%s\n' "$d070" | grep -E '^-[^-]' | grep -q 'AC4\.m1'; then
            pass "AC4.13 the 070 commit touches only 070-verify.sh, one hunk, replacing the one AC4.m1 line"
        else fail "AC4.13 the 070 commit is not a single-hunk AC4.m1 replacement (files: $files070)"; fi
    fi
    # FINAL is the last commit that touched a script of the range, and FINAL..TIP touches only 087's own task files (the 084 / 039a pattern)
    last_script="$(git -C "$ROOT" log -1 --format=%H "$PIN087_BASE..$PIN087_TIP" -- $S032 $S067 $S070 docs/tasks/087-verify.sh 2>/dev/null)"
    [ -n "$last_script" ] && [ "$last_script" = "$(git -C "$ROOT" rev-parse "$PIN087_FINAL^{commit}" 2>/dev/null)" ] \
        && pass "AC4.14a FINAL is the last commit in BASE..TIP that touched a script" || fail "AC4.14 FINAL ${PIN087_FINAL:0:12} is not the last script-touching commit in BASE..TIP (that is ${last_script:0:12})"
    if ! tail_files="$(git -C "$ROOT" diff --name-only "$PIN087_FINAL" "$PIN087_TIP" 2>&1)"; then fail "AC4.14 cannot compute FINAL..TIP: $(printf '%s' "$tail_files" | head -n1 | cut -c1-100)"
    elif [ -z "$(printf '%s\n' "$tail_files" | grep -vE '^docs/tasks/087-' )" ]; then pass "AC4.14b FINAL..TIP touches only docs/tasks/087-* files ($(printf '%s' "$tail_files" | tr '\n' ' '))"
    else fail "AC4.14 FINAL..TIP touches files other than docs/tasks/087-*: $(printf '%s' "$tail_files" | grep -vE '^docs/tasks/087-' | tr '\n' ' ')"; fi
    git -C "$ROOT" merge-base --is-ancestor "$PIN087_TIP" HEAD && pass "AC4.15 the pinned TIP is reachable from HEAD" || fail "AC4.15 the pinned TIP is not reachable from HEAD"
    # the patterns of N5 and N5b are not loosened: still the exact old strings
    grep -qF "'eight prose' \"\$CONTRACTS_README\"" "$S032T" && grep -qF "'None of the three tasks implements checking logic' \"\$CONTRACTS_README\"" "$S032T" \
        && pass "AC4.10 N5 and N5b keep their exact patterns ('eight prose', 'None of the three tasks implements checking logic')" || fail "AC4.10 N5 / N5b patterns changed"
fi

# ==================================================================================================
else
section "AC2 mutations (the merge with 082 onto HEAD; each mutation is committed in the clone, run, and reverted)"
if ! mk_merge "$TMP/M" "$HEADREV"; then fail "AC2.0 cannot build the merge of $T082 onto HEAD"; else
    mutate_commit() {   # mutate_commit FILE OLD NEW : replace OLD (exactly once) with NEW in the clone, commit it
        if [ "$(grep -cF -- "$2" "$TMP/M/$1")" != 1 ]; then return 1; fi
        python3 -I - "$TMP/M/$1" "$2" "$3" <<'PY' || return 1
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert s.count(old) == 1
open(p, "w").write(s.replace(old, new, 1))
PY
        git -C "$TMP/M" "${GITID[@]}" commit -q -am "mutation" || return 1
    }
    # expect_red LABEL SCRIPT FILE OLD NEW REGEX... : mutate, run SCRIPT, demand exit!=0 and every REGEX (a leading '!' demands absence)
    expect_red() {
        local label="$1" script="$2" file="$3" old="$4" new="$5" rc re miss="" ; shift 5
        if ! mutate_commit "$file" "$old" "$new"; then fail "$label: the mutation did not apply (pattern not found exactly once in $file)"; return; fi
        if [ "$script" = "$S067" ]; then rc=$(run_in "$TMP/M" "$TMP/mut.out" bash "$script" "$TMP/no-such-node-modules"); else rc=$(run_in "$TMP/M" "$TMP/mut.out" bash "$script"); fi
        for re in "$@"; do
            if [ "${re:0:1}" = "!" ]; then grep -Eq "${re:1}" "$TMP/mut.out" && miss="$miss /$re/"
            else grep -Eq "$re" "$TMP/mut.out" || miss="$miss /$re/"; fi
        done
        if [ "$rc" != 0 ] && [ -z "$miss" ]; then pass "$label turns red: exit $rc, $(grep -E "^FAIL  (N5|AC2\.5)" "$TMP/mut.out" | head -n1 | cut -c1-130)"
        else fail "$label stayed green or missed$miss: exit $rc"; fi
        git -C "$TMP/M" reset -q --hard HEAD~1
    }
    # controls: unmutated, on the merge. 032 green; 067 differs from green only by AC3.2 (the missing ajv path used to keep this fast).
    rc=$(run_in "$TMP/M" "$TMP/c032.out" bash $S032)
    [ "$rc" = 0 ] && pass "AC2.c1 control: the unmutated 032 exits 0 on the merge" || fail "AC2.c1 control: the unmutated 032 exits $rc on the merge: $(first_fail "$TMP/c032.out")"
    rc=$(run_in "$TMP/M" "$TMP/c067.out" bash $S067 "$TMP/no-such-node-modules")
    if grep -q '^PASS  AC2\.5 ' "$TMP/c067.out" && grep -q '^PASS  AC3\.1 ' "$TMP/c067.out" && [ "$(grep -c '^FAIL' "$TMP/c067.out")" = 1 ] && grep -q '^FAIL  AC3\.2 ' "$TMP/c067.out"; then
        pass "AC2.c2 control: the unmutated 067 on the merge fails only AC3.2 (no ajv path given, by design here)"
    else fail "AC2.c2 control: 067 on the merge: $(first_fail "$TMP/c067.out" 6)"; fi

    # ---- 032: each re-pinned check widened back to the README path (HEAD), then the pin made unreachable
    expect_red "AC2.m1 032 N5 widened back to HEAD's README" $S032 $S032 \
        "'eight prose' \"\$CONTRACTS_README\"" "'eight prose' \"\$CONTRACTS_README_PATH\"" '^FAIL  N5 ' '^PASS  N5b '
    expect_red "AC2.m2 032 N5b widened back to HEAD's README" $S032 $S032 \
        "'None of the three tasks implements checking logic' \"\$CONTRACTS_README\"" "'None of the three tasks implements checking logic' \"\$CONTRACTS_README_PATH\"" '^FAIL  N5b ' '^PASS  N5 '
    expect_red "AC2.m3 032 pin block reads HEAD instead of README_PIN_FINAL" $S032 $S032 \
        'git show "$README_PIN_FINAL:$CONTRACTS_README_PATH"' 'git show "HEAD:$CONTRACTS_README_PATH"' '^FAIL  N5 ' '^FAIL  N5b '
    P032="$(git -C "$ROOT" show "HEAD:$S032" | sed -n 's/^README_PIN_FINAL="\{0,1\}\([0-9a-f]\{7,\}\)"\{0,1\}\([[:space:]].*\)\{0,1\}$/\1/p' | head -n1)"
    P067="$(git -C "$ROOT" show "HEAD:$S067" | sed -n 's/^FINAL="\{0,1\}\([0-9a-f]\{7,\}\)"\{0,1\}\([[:space:]].*\)\{0,1\}$/\1/p' | head -n1)"
    if [ -z "$P032" ] || [ -z "$P067" ]; then fail "AC2.0 cannot read the pins from $S032 / $S067 (a search that finds nothing is broken)"; else
    expect_red "AC2.m4 032 unreachable README_PIN_FINAL must FAIL, never skip" $S032 $S032 \
        "README_PIN_FINAL=\"$P032\"" 'README_PIN_FINAL="deadbee"' '^FAIL  N5pin .*deadbee' '^FAIL  N5 ' '^FAIL  N5b '
    # ---- 067: AC2.5 widened back to the HEAD clone's README, then FINAL unreachable
    expect_red "AC2.m5 067 AC2.5 widened back to HEAD's README" $S067 $S067 \
        "git -C \"\$TMP/head\" show \"\$FINAL:docs/contracts/README.md\" 2>/dev/null | grep -qF \"\$SENTENCE\"" "grep -qF \"\$SENTENCE\" \"\$TMP/head/docs/contracts/README.md\"" '^FAIL  AC2\.5 ' '^PASS  AC2\.4 '
    expect_red "AC2.m6 067 unreachable FINAL must FAIL AC2.5, never skip" $S067 $S067 \
        "FINAL=\"$P067\"" 'FINAL="deadbee"' '^FAIL  AC2\.5 ' '^FAIL  AC5\.1 pinned commit deadbee'
    fi
fi

# ---- AC2.o*: controls for the AC4 own-change frame (REVIEW-CHECKLIST item 12). Run on a clone of HEAD, --own-only (no other suite).
#      Pins are replaced in the clone's copy of this script; "LATER" adds a synthetic commit that touches files outside the scope.
if ! git clone -q --no-hardlinks "$ROOT" "$TMP/O" 2>/dev/null || ! git -C "$TMP/O" checkout -q --detach "$HEADREV"; then fail "AC2.o0 cannot clone HEAD for the own-change controls"; else
    own_case() {   # own_case LABEL green|red LATER(0|1) OLD NEW REGEX... ; OLD empty = no replacement; a leading '!' on REGEX demands absence
        local label="$1" want="$2" later="$3" old="$4" new="$5" rc re miss=""; shift 5
        git -C "$TMP/O" reset -q --hard "$HEADREV"
        if [ -n "$old" ]; then
            if [ "$(grep -cF -- "$old" "$TMP/O/docs/tasks/087-verify.sh")" != 1 ]; then fail "$label: the mutation did not apply (pattern not found exactly once)"; return; fi
            python3 -I - "$TMP/O/docs/tasks/087-verify.sh" "$old" "$new" <<'PY' || { fail "$label: the mutation did not apply"; return; }
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert s.count(old) == 1
open(p, "w").write(s.replace(old, new, 1))
PY
            git -C "$TMP/O" "${GITID[@]}" commit -q -am "mutation" || { fail "$label: cannot commit the mutation"; return; }
        fi
        if [ "$later" = 1 ]; then   # a later branch's commit: out-of-scope files, as after 082 / 039a merge
            mkdir -p "$TMP/O/tools/registry" && echo later > "$TMP/O/tools/registry/later_branch.py" && echo later >> "$TMP/O/docs/contracts/README.md"
            git -C "$TMP/O" add -A && git -C "$TMP/O" "${GITID[@]}" commit -q -m "synthetic later-branch commit (outside 087's scope)" || { fail "$label: cannot commit the later-branch change"; return; }
        fi
        rc=$(run_in "$TMP/O" "$TMP/own.out" bash docs/tasks/087-verify.sh --own-only)
        for re in "$@"; do
            if [ "${re:0:1}" = "!" ]; then grep -Eq "${re:1}" "$TMP/own.out" && miss="$miss /$re/"
            else grep -Eq "$re" "$TMP/own.out" || miss="$miss /$re/"; fi
        done
        if [ "$want" = green ] && [ "$rc" = 0 ] && [ -z "$miss" ]; then pass "$label stays green: exit 0"
        elif [ "$want" = red ] && [ "$rc" != 0 ] && [ -z "$miss" ]; then pass "$label turns red: exit $rc, $(grep -E '^FAIL' "$TMP/own.out" | head -n1 | cut -c1-110)"
        else fail "$label wanted $want, got exit $rc$miss: $(first_fail "$TMP/own.out")"; fi
    }
    NOSHA="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    own_case "AC2.o1 control: --own-only on HEAD" green 0 "" "" '^PASS  AC4\.7 ' '!^FAIL'
    own_case "AC2.o2 a later branch's out-of-scope commit leaves AC4.7 green (item 12: the merge with 082 / 039a)" green 1 "" "" '^PASS  AC4\.7 ' '!^FAIL'
    own_case "AC2.o3 the range widened back to BASE..HEAD is red on a later branch's commit" red 1 \
        'diff --name-only "$PIN087_BASE" "$PIN087_'"TIP"'"' 'diff --name-only "$PIN087_BASE" HEAD' '^FAIL  AC4\.7 '
    own_case "AC2.o4 FINAL=BASE makes the own-change check red" red 0 \
        "PIN087_FINAL=\"$PIN087_FINAL\"" "PIN087_FINAL=\"$PIN087_BASE\"" '^FAIL  AC4\.14 '
    own_case "AC2.o5 an unreachable TIP pin is red, not skipped" red 0 \
        "PIN087_TIP=\"$PIN087_TIP\"" "PIN087_TIP=\"$NOSHA\"" '^FAIL  AC4\.1 pin '"$NOSHA" '^FAIL  AC4\.7 '
    own_case "AC2.o6 an unreachable FINAL pin is red, not skipped" red 0 \
        "PIN087_FINAL=\"$PIN087_FINAL\"" "PIN087_FINAL=\"$NOSHA\"" '^FAIL  AC4\.1 pin '"$NOSHA" '^FAIL  AC4\.14 '
fi
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
