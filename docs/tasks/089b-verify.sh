#!/usr/bin/env bash
#
# 089b-verify.sh -- the runnable verification artefact for task 089b (MANAGER.md Section 2c), part B of umbrella 089.
#
# Task 089b: four closed registry checks read a file at HEAD as evidence of THEIR OWN change; a later, legitimate branch
# reddens them (REVIEW-CHECKLIST item 12). They now read the file at their task's pinned FINAL commit:
#   finding 8   065-verify.sh AC3.5   tests/registry/test_hardening.py        (065, FINAL = PR #19's last commit)
#   finding 9   075-verify.sh AC4     contracts/ownership.md sentences        (075, FINAL = PR #18's last commit)
#   finding 10  039a-verify.sh        config/r11-identity.json must be null   (039a, FINAL = last composer/config/test commit)
#   finding 11  test_ci_gate.py AC9ProductionR11Unconfigured moved into 039a-verify.sh at the pin (the unit test is deleted)
#   finding 12  039a-verify.sh        per-class test counts: taken from the test file at FINAL (every pinned test must be ok
#                                     at HEAD; a later test ADDED to a class no longer reddens the script, a test REMOVED does)
#   S4          039a-verify.sh        its sweep ran 039b-verify.sh, which sweeps again and, nested under 039a, waits for 039a
#                                     (found while building this part); the sweep now runs 039b with --no-closed.
# Demonstrates acceptance criteria 1-5, 8, 9 (the mechanism), 10 (see the task log) and 11 of docs/tasks/089b-closed-verify-sweep-registry-b.md,
# restricted to findings 8-12 and S4. The long sequential runs (every closed script, one at a time, on a quiet machine) are done by hand and logged.
#
# Usage:  docs/tasks/089b-verify.sh [--mutate] [--own-only] [NODE_MODULES_DIR]      (any cwd inside the repository)
#   (no flag)   AC0 (pins re-derived from the merge commits; no own-change check reads HEAD), AC1 (RED FIRST: on a merge of a
#               synthetic later branch the OLD scripts fail and name the check, the NEW ones pass; controls), AC3 (unreachable pins
#               fail, nothing is skipped), AC5 (NEW scripts on plain HEAD), AC8 (S4: the sweep runs each script once), AC11 (scope).
#   --mutate    AC4: each fixed check widened back to HEAD, on the later-branch merge: red, and only that check.
#   --own-only  AC11 only (089b's own change on fixed SHAs); fast, runs no other script.
#   NODE_MODULES_DIR (or env WOM_NODE_MODULES, else <repo root>/tools/dev/node_modules) is needed by 065-verify.sh and by the S4 run.
# Everything runs on the COMMITTED state in temporary clones; the caller's worktree is never modified. The scripts under test are
# read as blobs of the pinned commits below (OLD = registry main when 089b was cut, NEW = 089b's fix commit), never from HEAD.
# 039a-verify.sh is run in the TRUNCATED form (everything before its AC12 section): the fixed checks of 039a are all before AC12, and
# AC12 is the hours-long sweep of every other script, which is run by hand (task log). The truncation point is asserted (exactly one marker).
# Network: none. Exit code: the number of failed checks. Run it with no other registry suite running.
# Requires: git, python3, node (065 and S4).

set -u
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1

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
GITID=(-c user.name=verify089b -c user.email=verify089b@invalid -c commit.gpgsign=false)
HEADREV="$(git -C "$ROOT" rev-parse HEAD)"
G() { git -C "$ROOT" "$@"; }

S065=docs/tasks/065-verify.sh
S075=docs/tasks/075-verify.sh
S039A=docs/tasks/039a-verify.sh
TCG=tests/registry/test_ci_gate.py

# Fixed SHAs (full 40 characters). OLD = registry main when 089b was cut (the unfixed scripts); the frame of every own-change
# check below is one of these, never HEAD (REVIEW-CHECKLIST item 12).
OLDREF="e2f7fe383d7b2231e1d37a73e474bca7ed56af46"
# 089b's own commits (AC11). Filled in by the pin commits after the red and fix commits exist.
PIN_BASE="e2f7fe383d7b2231e1d37a73e474bca7ed56af46"   # registry main when 089b was cut
PIN_RED="__RED__"      # 089b-verify.sh + task file only
PIN_FIX="__FIX__"      # 065-verify.sh, 075-verify.sh, 039a-verify.sh, test_ci_gate.py
PIN_FINAL="__FINAL__"  # last commit touching a source file of the part
PIN_TIP="__TIP__"      # last commit of the branch before the pin commit (log/task-file only after FINAL)

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

# blobs of the scripts under test
OLDD="$TMP/old"; NEWD="$TMP/new"; mkdir -p "$OLDD" "$NEWD"
for s in 065 075 039a; do
    G show "$OLDREF:docs/tasks/$s-verify.sh" > "$OLDD/$s.sh" 2>/dev/null || fail "AC0.0 cannot read $s-verify.sh at OLD $OLDREF"
    if [[ "$PIN_FIX" =~ ^[0-9a-f]{40}$ ]]; then
        G show "$PIN_FIX:docs/tasks/$s-verify.sh" > "$NEWD/$s.sh" 2>/dev/null || fail "AC0.0 cannot read $s-verify.sh at the fix commit $PIN_FIX"
    else : > "$NEWD/$s.sh"; fi
done
[[ "$PIN_FIX" =~ ^[0-9a-f]{40}$ ]] || fail "AC0.0 the fix commit is not pinned yet (PIN_FIX=$PIN_FIX): the NEW scripts cannot be read"

# trunc_039a FILE : print FILE up to (not including) its AC12 section, then a closing line. Fails (empty output) unless the marker occurs exactly once.
trunc_039a() {
    [ "$(grep -c '^section "AC12 -- ' "$1")" = 1 ] || return 1
    awk '/^section "AC12 -- /{exit} {print}' "$1"
    printf '%s\n' "printf '\\n== RESULT ==\\n'; exit \"\$FAILURES\""
}

# mk_frame DEST REV : a clone detached at REV
mk_frame() {
    git clone -q --no-hardlinks "$ROOT" "$1" 2>/dev/null || return 1
    git -C "$1" checkout -q --detach "$2" || return 1
}
# mk_later DEST REV FILE OLD NEW : a clone at REV plus a --no-ff merge of a synthetic later branch that edits FILE (OLD -> NEW, exactly once)
mk_later() {
    mk_frame "$1" "$2" || return 1
    git -C "$1" checkout -q -b later-branch || return 1
    edit_file "$1/$3" "$4" "$5" || return 1
    git -C "$1" "${GITID[@]}" commit -q -am "synthetic later branch: edit $3" || return 1
    git -C "$1" checkout -q --detach "$2" || return 1
    git -C "$1" "${GITID[@]}" merge --no-ff -q -m "merge of the synthetic later branch ($3)" later-branch >/dev/null 2>&1 || return 1
}
run_in() {   # run_in DIR OUTFILE CMD... : run CMD in DIR (clean of WOM_NODE_MODULES), output to OUTFILE; echo the exit code
    local d="$1" o="$2"; shift 2
    ( cd "$d" && PYTHONDONTWRITEBYTECODE=1 "$@" ) > "$o" 2>&1
    echo $?
}
# place DIR SRCFILE DESTRELPATH : put an (untracked) copy of a script into the clone
place() { cp "$2" "$1/$3"; }

# --- the later branches (each is the legitimate edit a later task makes to the file the old check read at HEAD)
OWN_OLD='and `R11` rejects it as well'
OWN_NEW='and `R11` also rejects it'
HARD_OLD='def test_f1_key_id_with_trailing_newline_is_rejected_task_065('
HARD_NEW='def test_f1_key_id_trailing_newline_is_rejected_task_065('
CFG_OLD='"r11_identity": null'
CFG_NEW='"r11_identity": {"provider": "github", "id": 1, "name": "later-identity"}'
ADD_OLD='class AC2PositiveControls(Base):
'
ADD_NEW='class AC2PositiveControls(Base):
    def test_synthetic_later_addition(self):
        self.assertTrue(True)

'
REM_OLD='    def test_actor_env_and_commit_metadata_do_not_make_a_stranger_the_owner(self):'
REM_NEW='    def test_actor_env_and_commit_metadata_renamed_by_a_later_branch(self):'

# ==================================================================================================
if [ "$MUTATE" = 0 ]; then

if [ "$OWN" = 0 ]; then
section "AC0 -- pins re-derived from the merge commits; own-change checks read the pinned FINAL, not HEAD"
merge_of() { G log --first-parent --merges --format=%H -E --grep="^Merge pull request #[0-9]+ from worldofmodcraft/task/$1\$" "$OLDREF" | head -n2; }
for t in 075-takedown-only-removal 065-entry-schema-key-id 039-registry-ci-workflow; do
    n=$(merge_of "$t" | wc -l)
    [ "$n" = 1 ] && pass "AC0.1 exactly one merge commit for task/$t: $(merge_of "$t")" || fail "AC0.1 task/$t: expected exactly one merge commit on main, found $n"
done
M075=$(merge_of 075-takedown-only-removal); M065=$(merge_of 065-entry-schema-key-id); M039=$(merge_of 039-registry-ci-workflow)
f075=$(pin_of "$NEWD/075.sh" FINAL); b075=$(pin_of "$NEWD/075.sh" BASE)
f065=$(pin_of "$NEWD/065.sh" FINAL)
f039=$(pin_of "$NEWD/039a.sh" FINAL); b039=$(pin_of "$NEWD/039a.sh" BASE)
if [ -z "$f075" ] || [ -z "$f065" ] || [ -z "$f039" ] || [ -z "$M075" ] || [ -z "$M065" ] || [ -z "$M039" ]; then
    fail "AC0.2 cannot read a pin or find a merge (075 FINAL='$f075' 065 FINAL='$f065' 039a FINAL='$f039'): a search that finds nothing is broken"
else
    for p in "$f075" "$f065" "$f039" "$b075" "$b039"; do full40 "$p" || fail "AC0.2 pin '$p' is not a full 40-character SHA"; done
    [ "$f075" = "$(G rev-parse "$M075^2")" ] && pass "AC0.3 075 FINAL=$f075 is PR #18's last commit (git rev-parse $M075^2)" || fail "AC0.3 075 FINAL=$f075 is not $M075^2"
    [ "$b075" = "$(G merge-base "$M075^1" "$M075^2")" ] && pass "AC0.4 075 BASE=$b075 is PR #18's fork point (git merge-base $M075^1 $M075^2)" || fail "AC0.4 075 BASE=$b075 is not the fork point"
    [ "$f065" = "$(G rev-parse "$M065^2")" ] && pass "AC0.5 065 FINAL=$f065 is PR #19's last commit (git rev-parse $M065^2)" || fail "AC0.5 065 FINAL=$f065 is not $M065^2"
    [ "$b039" = "$(G merge-base "$M039^1" "$M039^2")" ] && pass "AC0.6 039a BASE=$b039 is PR #21's fork point (git merge-base $M039^1 $M039^2)" || fail "AC0.6 039a BASE=$b039 is not the fork point"
    # 039a's FINAL is not M^2 (log/script commits follow it): it must be an ancestor of M^2 with no composer/config/test/contract byte differing
    if G merge-base --is-ancestor "$f039" "$M039^2" && G diff --quiet "$f039" "$M039^2" -- tools/registry config tests/registry contracts; then
        pass "AC0.7 039a FINAL=$f039 is an ancestor of PR #21's last commit $(G rev-parse "$M039^2" | cut -c1-12) and no tools/registry, config, tests/registry or contracts byte differs between them"
    else fail "AC0.7 039a FINAL=$f039 is not the last code/config/test commit of PR #21"; fi
fi
# own-change reads: the new check reads a blob of the pin; no read of the HEAD clone remains (non-zero counts required, §2c rule 1)
cnt() { grep -cF -- "$2" "$1"; }
[ "$(cnt "$NEWD/065.sh" 'blob "$FINAL" tests/registry/test_hardening.py')" -ge 1 ] && [ "$(cnt "$NEWD/065.sh" '$TMP/head/tests/registry/test_hardening')" = 0 ] \
    && pass "AC0.8 065 AC3.5 reads test_hardening.py with blob \"\$FINAL\" and no longer from the HEAD clone" || fail "AC0.8 065 AC3.5 still reads the HEAD clone (or does not read the pin)"
[ "$(cnt "$NEWD/075.sh" 'G show "$FINAL:contracts/ownership.md"')" -ge 1 ] && [ "$(cnt "$NEWD/075.sh" '$TMP/head/contracts/ownership.md')" = 0 ] \
    && pass "AC0.9 075 AC4 reads ownership.md with G show \"\$FINAL:...\" and no longer from the HEAD clone" || fail "AC0.9 075 AC4 still reads the HEAD clone (or does not read the pin)"
[ "$(cnt "$NEWD/039a.sh" 'G show "$FINAL:config/r11-identity.json"')" -ge 1 ] && [ "$(cnt "$NEWD/039a.sh" 'HEAD:config/r11-identity.json')" = 0 ] \
    && pass "AC0.10 039a reads r11-identity.json with G show \"\$FINAL:...\" and no longer at HEAD" || fail "AC0.10 039a still reads r11-identity.json at HEAD (or does not read the pin)"
[ "$(cnt "$NEWD/039a.sh" 'G show "$FINAL:tests/registry/test_ci_gate.py"')" -ge 1 ] && [ "$(cnt "$NEWD/039a.sh" 'class_check AC9ProductionR11Unconfigured')" = 0 ] \
    && pass "AC0.11 039a takes the per-class test names from the test file at \$FINAL; the AC9 unit-test class_check is gone (moved, finding 11)" || fail "AC0.11 039a does not read the test file at \$FINAL, or still counts the AC9 class"
# finding 11: the unit test is deleted; the assertion it made is made, in the same words, in 039a-verify.sh at the pin
if G show "$OLDREF:$TCG" | grep -qF 'self.assertEqual(doc, {"schema_version": "1.0.0", "r11_identity": None})' \
    && ! G show "$HEADREV:$TCG" | grep -qF 'AC9ProductionR11Unconfigured' && grep -qF '{"schema_version":"1.0.0","r11_identity":None}' "$NEWD/039a.sh"; then
    pass "AC0.12 the old unit test's condition (doc == {schema_version 1.0.0, r11_identity None}) is asserted in 039a-verify.sh; the test class is deleted from $TCG"
else fail "AC0.12 the AC9 unit test is still in $TCG, or its condition is not asserted in 039a-verify.sh"; fi

section "AC1 -- red first: a later branch is merged; the OLD scripts fail and name the check, the NEW ones pass on the same kind of merge"
# ---- finding 8: 065 AC3.5 (a later branch renames the key_id test in test_hardening.py)
if ! mk_later "$TMP/o8" "$OLDREF" tests/registry/test_hardening.py "$HARD_OLD" "$HARD_NEW"; then fail "AC1.8.0 cannot build the later-branch merge on OLD"; else
    place "$TMP/o8" "$OLDD/065.sh" "$S065"; rc=$(run_in "$TMP/o8" "$TMP/o8.out" bash "$S065" --mutate "$NM")
    expect "AC1.8a the OLD 065-verify.sh on OLD + a later test_hardening.py edit" red "$rc" "$TMP/o8.out" '^FAIL  AC3\.5 ' '^PASS  AC3\.4 '
fi
rc=$(mk_frame "$TMP/c8" "$OLDREF" && place "$TMP/c8" "$OLDD/065.sh" "$S065" && run_in "$TMP/c8" "$TMP/c8.out" bash "$S065" --mutate "$NM")
expect "AC1.8b control: the OLD 065-verify.sh on plain OLD (the later branch is the cause)" green "$rc" "$TMP/c8.out" '^PASS  AC3\.5 '
if ! mk_later "$TMP/n8" "$HEADREV" tests/registry/test_hardening.py "$HARD_OLD" "$HARD_NEW"; then fail "AC1.8.1 cannot build the later-branch merge on HEAD"; else
    place "$TMP/n8" "$NEWD/065.sh" "$S065"; rc=$(run_in "$TMP/n8" "$TMP/n8.out" bash "$S065" --mutate "$NM")
    expect "AC1.8c the NEW 065-verify.sh on HEAD + the same later edit" green "$rc" "$TMP/n8.out" '^PASS  AC3\.5 ' '!^FAIL'
fi
# ---- finding 9: 075 AC4 (a later branch rewords an ownership.md sentence the check pins)
if ! mk_later "$TMP/o9" "$OLDREF" contracts/ownership.md "$OWN_OLD" "$OWN_NEW"; then fail "AC1.9.0 cannot build the later-branch merge on OLD"; else
    place "$TMP/o9" "$OLDD/075.sh" "$S075"; rc=$(run_in "$TMP/o9" "$TMP/o9.out" bash "$S075")
    expect "AC1.9a the OLD 075-verify.sh on OLD + a later ownership.md edit" red "$rc" "$TMP/o9.out" '^FAIL  contract text check failed' '^PASS  pinned range '
fi
rc=$(mk_frame "$TMP/c9" "$OLDREF" && place "$TMP/c9" "$OLDD/075.sh" "$S075" && run_in "$TMP/c9" "$TMP/c9.out" bash "$S075")
expect "AC1.9b control: the OLD 075-verify.sh on plain OLD" green "$rc" "$TMP/c9.out" '^PASS  R11.s mixed-PR sentence is amended'
if ! mk_later "$TMP/n9" "$HEADREV" contracts/ownership.md "$OWN_OLD" "$OWN_NEW"; then fail "AC1.9.1 cannot build the later-branch merge on HEAD"; else
    place "$TMP/n9" "$NEWD/075.sh" "$S075"; rc=$(run_in "$TMP/n9" "$TMP/n9.out" bash "$S075")
    expect "AC1.9c the NEW 075-verify.sh on HEAD + the same later edit" green "$rc" "$TMP/n9.out" '^PASS  R11.s mixed-PR sentence is amended' '!^FAIL'
fi
# ---- finding 10 (and 11): 039a, truncated before AC12. A later branch configures R11 (config/r11-identity.json stops being null).
trunc_039a "$OLDD/039a.sh" > "$OLDD/039a.trunc.sh" || fail "AC1.10.0 the OLD 039a-verify.sh has no single AC12 marker"
trunc_039a "$NEWD/039a.sh" > "$NEWD/039a.trunc.sh" || fail "AC1.10.0 the NEW 039a-verify.sh has no single AC12 marker"
[ -s "$OLDD/039a.trunc.sh" ] && [ -s "$NEWD/039a.trunc.sh" ] && pass "AC1.10.00 positive control: both truncated copies are non-empty ($(wc -l < "$OLDD/039a.trunc.sh") / $(wc -l < "$NEWD/039a.trunc.sh") lines)"
if ! mk_later "$TMP/o10" "$OLDREF" config/r11-identity.json "$CFG_OLD" "$CFG_NEW"; then fail "AC1.10.1 cannot build the config-later-branch merge on OLD"; else
    place "$TMP/o10" "$OLDD/039a.trunc.sh" docs/tasks/039a-trunc.sh; rc=$(run_in "$TMP/o10" "$TMP/o10.out" bash docs/tasks/039a-trunc.sh)
    expect "AC1.10a the OLD 039a-verify.sh on OLD + R11 configured" red "$rc" "$TMP/o10.out" '^FAIL  AC9 config/r11-identity.json is not the null configuration' '^PASS  AC11: all own-change checks pass'
fi
rc=$(mk_frame "$TMP/c10" "$OLDREF" && place "$TMP/c10" "$OLDD/039a.trunc.sh" docs/tasks/039a-trunc.sh && run_in "$TMP/c10" "$TMP/c10.out" bash docs/tasks/039a-trunc.sh)
expect "AC1.10b control: the OLD 039a-verify.sh (truncated) on plain OLD" green "$rc" "$TMP/c10.out" '^PASS  AC9 config/r11-identity.json at HEAD parses'
if ! mk_later "$TMP/n10" "$HEADREV" config/r11-identity.json "$CFG_OLD" "$CFG_NEW"; then fail "AC1.10.2 cannot build the config-later-branch merge on HEAD"; else
    place "$TMP/n10" "$NEWD/039a.trunc.sh" docs/tasks/039a-trunc.sh; rc=$(run_in "$TMP/n10" "$TMP/n10.out" bash docs/tasks/039a-trunc.sh)
    expect "AC1.10c the NEW 039a-verify.sh on HEAD + R11 configured" green "$rc" "$TMP/n10.out" '^PASS  AC9 config/r11-identity.json at FINAL' '!^FAIL'
fi
# ---- finding 11: the moved assertion is red when the config AT THE PIN is non-null (a synthetic commit, the pin pointed at it in a copy)
if ! mk_frame "$TMP/n11" "$HEADREV"; then fail "AC1.11.0 cannot clone HEAD"; else
    X=""; pinned039=$(pin_of "$NEWD/039a.sh" FINAL)
    git -C "$TMP/n11" checkout -q -b cfg-at-pin "$pinned039" && edit_file "$TMP/n11/config/r11-identity.json" "$CFG_OLD" "$CFG_NEW" \
        && git -C "$TMP/n11" "${GITID[@]}" commit -q -am "synthetic: R11 configured at the pin" && X=$(git -C "$TMP/n11" rev-parse HEAD) && git -C "$TMP/n11" checkout -q --detach "$HEADREV"
    if [ -z "${X:-}" ]; then fail "AC1.11.1 cannot build the synthetic non-null commit"; else
        cp "$NEWD/039a.trunc.sh" "$TMP/n11/docs/tasks/039a-trunc.sh" && edit_file "$TMP/n11/docs/tasks/039a-trunc.sh" "FINAL=$pinned039" "FINAL=$X" \
            && rc=$(run_in "$TMP/n11" "$TMP/n11.out" bash docs/tasks/039a-trunc.sh)
        expect "AC1.11 the moved assertion is red when config/r11-identity.json at the pin is non-null" red "${rc:-0}" "$TMP/n11.out" '^FAIL  AC9 config/r11-identity.json at FINAL .* is not the null configuration'
    fi
fi
# ---- finding 12: a later branch ADDS a test to a counted class (old: red; new: green) / REMOVES a pinned test (new: red)
if ! mk_later "$TMP/o12" "$OLDREF" "$TCG" "$ADD_OLD" "$ADD_NEW"; then fail "AC1.12.0 cannot build the test-added later branch on OLD"; else
    place "$TMP/o12" "$OLDD/039a.trunc.sh" docs/tasks/039a-trunc.sh; rc=$(run_in "$TMP/o12" "$TMP/o12.out" bash docs/tasks/039a-trunc.sh)
    expect "AC1.12a the OLD 039a-verify.sh on OLD + a test added to AC2PositiveControls" red "$rc" "$TMP/o12.out" '^FAIL  AC2 positive controls: expected 7 ok tests, ran 8'
fi
if ! mk_later "$TMP/n12" "$HEADREV" "$TCG" "$ADD_OLD" "$ADD_NEW"; then fail "AC1.12.1 cannot build the test-added later branch on HEAD"; else
    place "$TMP/n12" "$NEWD/039a.trunc.sh" docs/tasks/039a-trunc.sh; rc=$(run_in "$TMP/n12" "$TMP/n12.out" bash docs/tasks/039a-trunc.sh)
    expect "AC1.12b the NEW 039a-verify.sh on HEAD + the same added test" green "$rc" "$TMP/n12.out" '^PASS  AC2 positive controls' '!^FAIL'
fi
if ! mk_later "$TMP/r12" "$HEADREV" "$TCG" "$REM_OLD" "$REM_NEW"; then fail "AC1.12.2 cannot build the test-removed later branch on HEAD"; else
    place "$TMP/r12" "$NEWD/039a.trunc.sh" docs/tasks/039a-trunc.sh; rc=$(run_in "$TMP/r12" "$TMP/r12.out" bash docs/tasks/039a-trunc.sh)
    expect "AC1.12c positive control: the NEW 039a-verify.sh still fails when a pinned test disappears from a counted class" red "$rc" "$TMP/r12.out" '^FAIL  AC4 identity source'
fi
fi   # OWN = 0

# ==================================================================================================
if [ "$OWN" = 0 ]; then
section "AC5 -- the NEW scripts on plain HEAD exit 0 (the unmerged state)"
if mk_frame "$TMP/h" "$HEADREV"; then
    place "$TMP/h" "$NEWD/065.sh" "$S065"; place "$TMP/h" "$NEWD/075.sh" "$S075"; place "$TMP/h" "$NEWD/039a.trunc.sh" docs/tasks/039a-trunc.sh
    rc=$(run_in "$TMP/h" "$TMP/h065.out" bash "$S065" --mutate "$NM"); expect "AC5.1 NEW 065-verify.sh --mutate on HEAD" green "$rc" "$TMP/h065.out" '^PASS  AC3\.5 '
    rc=$(run_in "$TMP/h" "$TMP/h075.out" bash "$S075"); expect "AC5.2 NEW 075-verify.sh on HEAD" green "$rc" "$TMP/h075.out" '^PASS  R11.s mixed-PR sentence is amended'
    rc=$(run_in "$TMP/h" "$TMP/h039.out" bash docs/tasks/039a-trunc.sh); expect "AC5.3 NEW 039a-verify.sh (truncated before AC12) on HEAD" green "$rc" "$TMP/h039.out" '^PASS  AC9 config/r11-identity.json at FINAL'
else fail "AC5.0 cannot clone HEAD"; fi

section "AC3 -- an unreachable pin (deadbee) is a FAIL naming the check; nothing is skipped"
pinreplace() {   # pinreplace SCRIPT_BLOB OUT PIN : copy with the FINAL pin replaced by deadbee
    cp "$1" "$2" && edit_file "$2" "FINAL=$3" "FINAL=deadbee"
}
if mk_frame "$TMP/d" "$HEADREV"; then
    p065=$(pin_of "$NEWD/065.sh" FINAL); p075=$(pin_of "$NEWD/075.sh" FINAL); p039=$(pin_of "$NEWD/039a.sh" FINAL)
    pinreplace "$NEWD/065.sh" "$TMP/d/$S065" "$p065" && rc=$(run_in "$TMP/d" "$TMP/d065.out" bash "$S065" --mutate "$NM")
    expect "AC3.1 065 with FINAL=deadbee" red "${rc:-0}" "$TMP/d065.out" '^FAIL  AC3\.5 ' '^PASS  AC3\.4 '
    pinreplace "$NEWD/075.sh" "$TMP/d/$S075" "$p075" && rc=$(run_in "$TMP/d" "$TMP/d075.out" bash "$S075")
    expect "AC3.2 075 with FINAL=deadbee" red "${rc:-0}" "$TMP/d075.out" '^FAIL  pin deadbee does not exist' '^FAIL  contract text check failed'
    pinreplace "$NEWD/039a.trunc.sh" "$TMP/d/docs/tasks/039a-trunc.sh" "$p039" && rc=$(run_in "$TMP/d" "$TMP/d039.out" bash docs/tasks/039a-trunc.sh)
    expect "AC3.3 039a with FINAL=deadbee" red "${rc:-0}" "$TMP/d039.out" '^FAIL  pin deadbee does not exist' '^FAIL  AC9 config/r11-identity.json at FINAL' '^FAIL  AC2 positive controls'
    # the words of a silent skip never appear in the output of any run above, and the grep can match (positive control)
    printf 'x skipped y\n' > "$TMP/skipctl.txt"
    grep -Eiq 'skip|not evaluated' "$TMP/skipctl.txt" && pass "AC3.4a positive control: the skip-word grep matches a sample line" || fail "AC3.4a the skip-word grep cannot match"
    hits=$(cat "$TMP"/d065.out "$TMP"/d075.out "$TMP"/d039.out "$TMP"/h065.out "$TMP"/h075.out "$TMP"/h039.out 2>/dev/null | grep -Eic 'skip|not evaluated')
    [ "$hits" = 0 ] && pass "AC3.4 'skip' / 'not evaluated' occur 0 times in the outputs of the deadbee and HEAD runs" || fail "AC3.4 $hits skip/not-evaluated line(s) in the run outputs"
else fail "AC3.0 cannot clone HEAD"; fi

section "AC8 -- S4: the 039a sweep runs each script once; 039b is run with --no-closed (its own sweep is this one)"
# 1. the nested-wait defect, observed: 039b's quiet-wait predicate sees a parent 039a-verify.sh and would wait for it (up to six hours).
G show "$OLDREF:docs/tasks/039b-verify.sh" | grep '^others_running()' > "$TMP/pred.sh"
[ -s "$TMP/pred.sh" ] && pass "AC8.1a positive control: 039b's others_running predicate was read" || fail "AC8.1a cannot read 039b's others_running predicate"
( . "$TMP/pred.sh"; ps() { printf 'bash docs/tasks/039a-verify.sh /nm\n'; }; others_running ) \
    && pass "AC8.1 observed: with a parent 039a-verify.sh in the process list, 039b's others_running is TRUE, i.e. 039b run from 039a's sweep waits for 039a (up to six hours)" \
    || fail "AC8.1 039b's others_running did not see a parent 039a-verify.sh process"
( . "$TMP/pred.sh"; ps() { printf 'bash docs/tasks/039b-verify.sh\n'; }; others_running ) \
    && fail "AC8.1b control: 039b's predicate counts itself" || pass "AC8.1b control: with only 039b-verify.sh itself in the process list the predicate is FALSE"
# 2. invocation counts: every other script replaced by a logging stub, 039a (OLD and NEW) run whole in a clone
stub_run() {   # stub_run LABEL 039A_BLOB : count invocations of each stubbed script
    local label="$1" blob="$2" d="$TMP/s-$1" log="$TMP/s-$1.log" f
    mk_frame "$d" "$HEADREV" || { fail "AC8.$label cannot clone HEAD"; return; }
    : > "$log"
    for f in "$d"/docs/tasks/*-verify.sh; do
        case "$f" in */039a-verify.sh) continue ;; esac
        printf '#!/usr/bin/env bash\necho "$(basename "$0")${*:+ $*}" >> "%s"\nexit 0\n' "$log" > "$f"
    done
    git -C "$d" "${GITID[@]}" commit -q -am "stubs" || { fail "AC8.$label cannot commit the stubs"; return; }
    cp "$blob" "$d/$S039A"
    ( cd "$d" && PYTHONDONTWRITEBYTECODE=1 env -u WOM_NODE_MODULES bash "$S039A" "$NM" ) > "$TMP/s-$label.out" 2>&1; echo "$?" > "$TMP/s-$label.rc"
}
stub_run old "$OLDD/039a.sh"; stub_run new "$NEWD/039a.sh"
for v in old new; do
    nlogs=$(wc -l < "$TMP/s-$v.log" 2>/dev/null || echo 0)
    maxn=$(sed 's/ .*//' "$TMP/s-$v.log" 2>/dev/null | sort | uniq -c | sort -rn | awk 'NR==1{print $1+0}')
    echo "      $v 039a sweep: $nlogs invocation(s), max per script ${maxn:-0}; 039b line: $(grep '^039b' "$TMP/s-$v.log" | head -n1)"
done
n_sc=$(ls "$TMP/s-new/docs/tasks/"*-verify.sh 2>/dev/null | grep -vc '039a-verify.sh')
n_new=$(wc -l < "$TMP/s-new.log"); max_new=$(sed 's/ .*//' "$TMP/s-new.log" | sort | uniq -c | awk '{print $1}' | sort -rn | head -n1)
[ "$n_new" = "$n_sc" ] && [ "${max_new:-0}" = 1 ] && pass "AC8.2 the NEW 039a sweep invoked each of the $n_sc other scripts exactly once ($n_new invocations)" || fail "AC8.2 NEW sweep: $n_new invocations for $n_sc scripts, max per script ${max_new:-?}"
grep -qx '039b-verify.sh --no-closed' "$TMP/s-new.log" && pass "AC8.3 the NEW sweep runs 039b-verify.sh with --no-closed (no nested sweep, no wait on its parent)" || fail "AC8.3 the NEW sweep does not pass --no-closed to 039b: $(grep '^039b' "$TMP/s-new.log" | head -n1)"
grep -qx '039b-verify.sh' "$TMP/s-old.log" && pass "AC8.4 positive control: the OLD sweep ran 039b-verify.sh with no flag (the defect)" || fail "AC8.4 the OLD sweep did not run 039b without a flag: $(grep '^039b' "$TMP/s-old.log" | head -n1)"
[ "$(cat "$TMP/s-new.rc")" = 0 ] && pass "AC8.5 the NEW 039a-verify.sh (whole, stubbed sweep) exits 0" || fail "AC8.5 the NEW 039a-verify.sh stubbed run exits $(cat "$TMP/s-new.rc"): $(first_fail "$TMP/s-new.out")"
sed -n '1,45p' "$NEWD/039a.sh" | grep -qi '039b.*--no-closed\|--no-closed.*039b' && pass "AC8.6 the 039a header documents the 039b relation (--no-closed)" || fail "AC8.6 the 039a header does not mention 039b"
fi   # OWN = 0

section "AC11 -- 089b's own change, measured on fixed SHAs (never HEAD)"
if [ "$PIN_RED" = "__RED__" ] || [ "$PIN_FIX" = "__FIX__" ] || [ "$PIN_FINAL" = "__FINAL__" ] || [ "$PIN_TIP" = "__TIP__" ]; then
    fail "AC11.0 the 089b red/fix/final/tip SHAs are not pinned yet"
else
    for s in "$PIN_BASE" "$PIN_RED" "$PIN_FIX" "$PIN_FINAL" "$PIN_TIP"; do
        full40 "$s" || fail "AC11.1 pin '$s' is not a full 40-character SHA"
        G cat-file -e "$s^{commit}" 2>/dev/null && pass "AC11.1 pin $s exists" || fail "AC11.1 pin $s does not exist"
    done
    [ "$(G rev-parse "$PIN_RED^" 2>/dev/null)" != "" ] && G merge-base --is-ancestor "$PIN_BASE" "$PIN_RED" && G merge-base --is-ancestor "$PIN_RED" "$PIN_FIX" \
        && G merge-base --is-ancestor "$PIN_FIX" "$PIN_FINAL" && G merge-base --is-ancestor "$PIN_FINAL" "$PIN_TIP" && G merge-base --is-ancestor "$PIN_TIP" HEAD \
        && pass "AC11.2 BASE < RED < FIX <= FINAL <= TIP <= HEAD (ancestry)" || fail "AC11.2 the pins are not in ancestry order"
    red_files="$(G diff --name-only "$PIN_BASE" "$PIN_RED" 2>/dev/null | grep -vx -e docs/tasks/089-closed-verify-sweep-registry.md -e docs/tasks/089b-closed-verify-sweep-registry-b.md | sort | tr '\n' ' ')"
    [ "$red_files" = "docs/tasks/089b-verify.sh " ] && pass "AC11.3 the red commit touches only 089b-verify.sh and the task files" || fail "AC11.3 the red commit touches: $red_files"
    fix_files="$(G diff --name-only "$PIN_RED" "$PIN_FIX" 2>/dev/null | sort | tr '\n' ' ')"
    [ "$fix_files" = "docs/tasks/039a-verify.sh docs/tasks/065-verify.sh docs/tasks/075-verify.sh tests/registry/test_ci_gate.py " ] \
        && pass "AC11.4 the fix commit touches only 039a-verify.sh, 065-verify.sh, 075-verify.sh and test_ci_gate.py" || fail "AC11.4 the fix commit touches: $fix_files"
    if ! scope_files="$(G diff --name-only "$PIN_BASE" "$PIN_TIP" 2>&1)"; then fail "AC11.5 cannot compute $PIN_BASE..$PIN_TIP"; else
        extra="$(printf '%s\n' "$scope_files" | grep -vxE 'docs/tasks/039a-verify\.sh|docs/tasks/065-verify\.sh|docs/tasks/075-verify\.sh|tests/registry/test_ci_gate\.py|docs/tasks/089b-verify\.sh|docs/tasks/089b-closed-verify-sweep-registry-b\.md|docs/tasks/089-closed-verify-sweep-registry\.md' | tr '\n' ' ')"
        [ -n "$scope_files" ] && [ -z "$extra" ] && pass "AC11.5 BASE..TIP stays inside the declared file scope" || fail "AC11.5 out-of-scope files in BASE..TIP (or the range is empty): $extra"
    fi
    last_src="$(G log -1 --format=%H "$PIN_BASE..$PIN_TIP" -- docs/tasks/039a-verify.sh docs/tasks/065-verify.sh docs/tasks/075-verify.sh tests/registry/test_ci_gate.py docs/tasks/089b-verify.sh 2>/dev/null)"
    [ -n "$last_src" ] && [ "$last_src" = "$(G rev-parse "$PIN_FINAL^{commit}" 2>/dev/null)" ] && pass "AC11.6a FINAL is the last commit in BASE..TIP that touched a source or script file" || fail "AC11.6 FINAL ${PIN_FINAL:0:12} is not the last source-touching commit (that is ${last_src:0:12})"
    if ! tail_files="$(G diff --name-only "$PIN_FINAL" "$PIN_TIP" 2>&1)"; then fail "AC11.6 cannot compute FINAL..TIP"
    elif [ -z "$(printf '%s\n' "$tail_files" | grep -vE '^docs/tasks/089b-closed-verify-sweep-registry-b\.md$')" ]; then pass "AC11.6b FINAL..TIP touches only the 089b task file"
    else fail "AC11.6 FINAL..TIP touches: $(printf '%s' "$tail_files" | tr '\n' ' ')"; fi
    # hunk limits: each source file changes only where the finding says (comment lines and the named checks)
    nonc() { G diff -U0 "$PIN_RED" "$PIN_FIX" -- "$1" | grep -E '^[+-][^+-]' | grep -vE '^[+-][[:space:]]*#' ; }
    d065="$(nonc docs/tasks/065-verify.sh | grep -vE 'FINAL=|th-final|AC3\.5|blob "\$FINAL"|sys\.argv\[1\]|^[+-]python3 -I - |^[+-]PYE$' | wc -l)"
    [ "$d065" = 0 ] && pass "AC11.7 065-verify.sh changed only in the FINAL pin, comments and the AC3.5 check" || fail "AC11.7 065-verify.sh changed outside AC3.5 ($d065 lines)"
    d075="$(nonc docs/tasks/075-verify.sh | grep -vE 'FINAL|BASE=|RED=|FIX=|ownership|^[+-]C=|"\$C"' | wc -l)"
    [ "$d075" = 0 ] && pass "AC11.8 075-verify.sh changed only in pins (full SHAs), comments and the AC4 contract-text read" || fail "AC11.8 075-verify.sh changed outside AC4 and the pins ($d075 lines)"
    d039="$(nonc docs/tasks/039a-verify.sh | grep -vE 'BASE=|RED=|FINAL=|TIP=|PINNED_TESTS|class_check|missing|pinned|ran=|ok=|r11|AC9|039b|args|note|FINAL|^[+-]\s*(fi|else|done|\)|\}|local)' | wc -l)"
    [ "$d039" = 0 ] && pass "AC11.9 039a-verify.sh changed only in pins, class_check, the r11 assertion and the 039b call" || fail "AC11.9 039a-verify.sh changed outside the named checks ($d039 lines)"
    d_tcg="$(G diff -U0 "$PIN_RED" "$PIN_FIX" -- tests/registry/test_ci_gate.py | grep -E '^\+[^+]' | wc -l)"
    [ "$d_tcg" = 0 ] && pass "AC11.10 test_ci_gate.py only lost lines (the AC9 unit test); nothing was added" || fail "AC11.10 test_ci_gate.py gained $d_tcg line(s)"
    G show "$PIN_FIX:$TCG" | python3 -I -c 'import ast,sys; ast.parse(sys.stdin.read())' && pass "AC11.11 test_ci_gate.py at the fix commit still parses" || fail "AC11.11 test_ci_gate.py does not parse"
fi

# ==================================================================================================
else
section "AC4 mutations (each fixed check widened back to HEAD, on the later-branch merge on HEAD; red, and only that check)"
mutate_run() {   # mutate_run LABEL FRAMEKIND(8|9|10|12) SCRIPTKEY OLD NEW RUNKIND ONLYREGEX FAILREGEX
    local label="$1" kind="$2" key="$3" old="$4" new="$5" run="$6" fr="$7" rc
    local d="$TMP/m-$kind" blob
    case "$kind" in
        8)  mk_later "$d" "$HEADREV" tests/registry/test_hardening.py "$HARD_OLD" "$HARD_NEW" ;;
        9)  mk_later "$d" "$HEADREV" contracts/ownership.md "$OWN_OLD" "$OWN_NEW" ;;
        10) mk_later "$d" "$HEADREV" config/r11-identity.json "$CFG_OLD" "$CFG_NEW" ;;
        12) mk_later "$d" "$HEADREV" "$TCG" "$ADD_OLD" "$ADD_NEW" ;;
    esac || { fail "$label cannot build the frame"; return; }
    blob="$NEWD/$key.sh"; [ "$key" = 039a ] && blob="$NEWD/039a.trunc.sh"
    cp "$blob" "$TMP/mut.sh"
    edit_file "$TMP/mut.sh" "$old" "$new" || { fail "$label: the mutation did not apply (pattern not found exactly once)"; return; }
    case "$run" in
        065)  cp "$TMP/mut.sh" "$d/$S065"; rc=$(run_in "$d" "$TMP/mut.out" bash "$S065" --mutate "$NM") ;;
        075)  cp "$TMP/mut.sh" "$d/$S075"; rc=$(run_in "$d" "$TMP/mut.out" bash "$S075") ;;
        039a) cp "$TMP/mut.sh" "$d/docs/tasks/039a-trunc.sh"; rc=$(run_in "$d" "$TMP/mut.out" bash docs/tasks/039a-trunc.sh) ;;
    esac
    nfail=$(grep -c '^FAIL' "$TMP/mut.out")
    if [ "$rc" != 0 ] && grep -Eq "$fr" "$TMP/mut.out" && [ "$nfail" = 1 ]; then pass "$label turns red, and only that check: exit $rc, $(grep '^FAIL' "$TMP/mut.out" | head -n1 | cut -c1-120)"
    else fail "$label: exit $rc, $nfail FAIL line(s) (want exactly 1 matching /$fr/): $(first_fail "$TMP/mut.out")"; fi
}
mutate_run "AC4.m8 065 AC3.5 widened back to the HEAD clone's test_hardening.py" 8 065 \
    'blob "$FINAL" tests/registry/test_hardening.py > "$TMP/th-final.py"' 'cat "$TMP/head/tests/registry/test_hardening.py" > "$TMP/th-final.py"' 065 '^FAIL  AC3\.5 '
mutate_run "AC4.m9 075 AC4 widened back to the HEAD clone's ownership.md" 9 075 \
    'G show "$FINAL:contracts/ownership.md" > "$C" 2>/dev/null' 'cp "$TMP/head/contracts/ownership.md" "$C"' 075 '^FAIL  contract text check failed'
mutate_run "AC4.m10 039a r11-identity.json widened back to HEAD" 10 039a \
    'G show "$FINAL:config/r11-identity.json"' 'git -C "$TMP/head" show HEAD:config/r11-identity.json' 039a '^FAIL  AC9 config/r11-identity.json'
mutate_run "AC4.m11 039a moved AC9 assertion: the same line, widened (finding 11 is this check)" 10 039a \
    'G show "$FINAL:config/r11-identity.json"' 'git -C "$TMP/head" show HEAD:config/r11-identity.json' 039a '^FAIL  AC9 config/r11-identity.json at'
mutate_run "AC4.m12 039a class_check widened back to exact counts at HEAD" 12 039a \
    'elif [ -n "$missing" ]; then' 'elif [ "$ran" != "$2" ] || [ "$ok" != "$2" ]; then' 039a '^FAIL  AC2 positive controls: .*'
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
