#!/usr/bin/env bash
#
# 075-verify.sh -- the runnable verification artefact for task 075 (MANAGER.md Section 2c).
#
# Task 075: any PR whose diff contains a takedown mutation is rejected by R11 unless it is nothing but takedown
# mutations opened by the platform's own identity. Demonstrates acceptance criteria 1-4 and 6 of
# docs/tasks/075-takedown-only-removal.md. Criterion 5 (032-verify.sh and 062-verify.sh on the base, and every
# docs/tasks/*-verify.sh on HEAD, one at a time on a quiet machine) is a sequential run done by hand and logged.
#
# Usage:  docs/tasks/075-verify.sh      (any cwd inside the repository)
# Own-change checks use the EXPLICIT SHAs below (AC6), never HEAD or origin/main, so later tasks cannot redden them.
# Task 084: the declared-file-scope check measures 075's PR #18 range BASE..FINAL (BASE = git merge-base 4356583^1 4356583^2,
# FINAL = 4356583^2), not BASE..HEAD, so a later task that legitimately edits contracts/append-only.rules.md or schema.py
# cannot redden it. Every other check here is a live property of HEAD (the tests, the contract text, 032-verify.sh).
# Task 089b (finding 9): the AC4 contract-text check is 075's OWN change (the R11 / R3 / R7 sentences), so it reads
# contracts/ownership.md at 075's pinned FINAL (git show "$FINAL:..."), not from the HEAD clone: a later task that legitimately edits
# those sentences (008b's ownership carve-out) cannot redden it. An unreadable FINAL is a FAIL. The pins below are full 40-character SHAs.
# Behaviour checks (AC2-AC4) run on the COMMITTED HEAD in a temporary clone; the caller's worktree is not modified.
# Network: none. Exit code: the number of failed checks. Requires: git, python3.

set -u
set -o pipefail

BASE=79d537779c9fe717657aed9c4c85f90ba71fcd14   # registry origin/main containing task 064
RED=45c5be9ef2eadcb3e48b56e5fe3eb7a5c0f9546a    # tests only
FIX=067a45d0f8a125e2a5a20e76afefdb25cbf4f932    # the fix (contract + checker + mutation entries)
FINAL=7d91a3d54d19431f4e3eff2dbed409cf00320887  # the last commit of PR #18 (git rev-parse 4356583^2); BASE above is its fork point (git merge-base 4356583^1 4356583^2)

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }
TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT
G() { git -C "$ROOT" "$@"; }

section "AC6 -- pins: explicit SHAs, ancestry"
for s in "$BASE" "$RED" "$FIX" "$FINAL"; do
    G cat-file -e "$s^{commit}" 2>/dev/null && pass "pin $s exists" || fail "pin $s does not exist"
done
[ "$(G rev-parse "$RED^")" = "$(G rev-parse "$BASE")" ] && pass "red commit's parent is the base" || fail "red commit's parent is not the base"
[ "$(G rev-parse "$FIX^")" = "$(G rev-parse "$RED")" ] && pass "fix commit follows the red commit directly" || fail "fix commit does not follow the red commit"
G merge-base --is-ancestor "$FIX" HEAD && pass "fix commit is an ancestor of HEAD" || fail "fix commit is not an ancestor of HEAD"
G merge-base --is-ancestor "$FIX" "$FINAL" && pass "fix commit is an ancestor of the PR's last commit" || fail "fix commit is not an ancestor of the PR's last commit"

section "AC1 -- red first: the red commit is tests only"
red_files="$(G diff --name-only "$BASE" "$RED")"
echo "$red_files" | sed 's/^/      /'
[ "$red_files" = "tests/registry/test_ownership.py" ] && pass "red commit touches only tests/registry/test_ownership.py" || fail "red commit touches other files"
fix_files="$(G diff --name-only "$RED" "$FIX")"
bad="$(echo "$fix_files" | grep -v -x -e contracts/ownership.md -e tools/registry/ownership.py -e tests/registry/test_ownership_mutations.py)"
[ -z "$bad" ] && pass "fix commit stays in the file scope (ownership.md, ownership.py, test_ownership_mutations.py)" || fail "fix commit touches out-of-scope files: $bad"
allowed='^(contracts/ownership.md|tools/registry/ownership.py|tests/registry/test_ownership.py|tests/registry/test_ownership_mutations.py|docs/tasks/075-takedown-only-removal.md|docs/tasks/075-verify.sh)$'
if range_files="$(G diff --name-only "$BASE" "$FINAL" 2>/dev/null)" && [ -n "$range_files" ]; then
    bad="$(echo "$range_files" | grep -v -E "$allowed")"
    [ -z "$bad" ] && pass "pinned range $BASE..$FINAL touches only the task's declared file scope" || fail "out-of-scope files in pinned range $BASE..$FINAL: $bad"
else
    fail "pinned range $BASE..$FINAL cannot be diffed or is empty (pin unreachable): the file scope was not measured"
fi

run_ut() {  # run_ut DIR [unittest args...]
    local d="$1"; shift
    ( cd "$d" && python3 -I -B -m unittest "$@" > "$TMP/ut.out" 2>&1 ); return $?
}
git clone -q --no-hardlinks "$ROOT" "$TMP/red" && git -C "$TMP/red" checkout -q "$RED"
( cd "$TMP/red" && python3 -I -B -m unittest discover -s tests/registry -p test_ownership.py > "$TMP/red.out" 2>&1 ); rc=$?
nf="$(grep -c -E '^(FAIL|ERROR):' "$TMP/red.out")"
[ "$rc" != 0 ] && [ "$nf" -gt 0 ] && pass "on the red commit the ownership tests (incl. the new mixed-PR ones) fail ($nf failing)" || fail "on the red commit the mixed-PR tests do not fail (exit $rc)"
grep -q 'FAIL: test_r11_reject_owner_bundling_a_removal_with_a_new_version' "$TMP/red.out" \
    && pass "red: the owner + removal + new version case passes the old checker (its test fails)" || fail "red: the owner case does not fail on the old checker"
git -C "$TMP/red" checkout -q "$FIX"
( cd "$TMP/red" && python3 -I -B -m unittest discover -s tests/registry -p test_ownership.py > "$TMP/fix.out" 2>&1 ); rc=$?
[ "$rc" = 0 ] && pass "on the fix commit the same ownership suite passes: $(grep -E '^Ran ' "$TMP/fix.out")" || { fail "on the fix commit the tests fail"; tail -8 "$TMP/fix.out"; }

section "AC2 -- fixed at HEAD: every Approach-3 case, and the whole tests/registry suite"
git clone -q --no-hardlinks "$ROOT" "$TMP/head" && git -C "$TMP/head" checkout -q "$(G rev-parse HEAD)"
( cd "$TMP/head" && python3 -I -B -m unittest discover -s tests/registry -p test_ownership.py -v > "$TMP/cases.out" 2>&1 ); rc=$?
for t in test_r11_reject_owner_bundling_a_removal_with_a_new_version \
         test_r11_reject_platform_identity_bundling_a_removal_with_another_change \
         test_r11_accept_one_and_two_t2s_from_the_configured_identity \
         test_r11_reject_everyone_else \
         test_r11_accept_unchanged_neighbours_of_the_mixed_rule \
         test_r11_reject_two_entries_one_removal_one_unrelated_edit \
         test_r11_reject_page_change_plus_a_removal_from_the_owner \
         test_r11_reject_t2_element_plus_a_malformed_second_element \
         test_r11_reject_checker_error_on_an_entry_fails_closed_naming_the_path \
         test_r11_reject_removal_in_a_reserved_namespace_bundled_with_another_change \
         test_r11_reject_a_takedown_plus_any_other_change; do
    grep -q "^$t " "$TMP/cases.out" && ! grep -q -E "^(FAIL|ERROR): $t " "$TMP/cases.out" && pass "case $t" || fail "case $t did not run green"
done
[ "$rc" = 0 ] && pass "ownership test file green at HEAD" || fail "R11 classes red"
( cd "$TMP/head" && python3 -I -B -m unittest discover -s tests/registry > "$TMP/all.out" 2>&1 ); rc=$?
[ "$rc" = 0 ] && pass "full tests/registry suite: $(grep -E '^Ran ' "$TMP/all.out")" || { fail "full tests/registry suite red"; tail -8 "$TMP/all.out"; }

section "AC3 -- mutation red: the new b7 mutations turn the new tests red"
( cd "$TMP/head" && python3 -I -B tests/registry/test_ownership_mutations.py b7-r11-mixed-pr-branch-removed \
    b7-r11-mixed-ignores-checker-error b7-r11-mixed-ignores-raw-status-change > "$TMP/mut.out" 2>&1 ); rc=$?
sed 's/^/      /' "$TMP/mut.out"
[ "$rc" = 0 ] && [ "$(grep -c '^red ' "$TMP/mut.out")" = 3 ] && pass "all three b7 mutations are red" || fail "a b7 mutation is NOT RED (exit $rc)"
grep -q 'b7-r11-mixed-pr-branch-removed' "$TMP/head/tests/registry/test_ownership_mutations.py" && pass "the mixed-PR mutation is in the mutation list" || fail "mutation missing from the list"

section "AC4 -- contract text"
C="$TMP/ownership.final.md"
G show "$FINAL:contracts/ownership.md" > "$C" 2>/dev/null
python3 -I - "$C" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
def para(marker):
    i = t.index(marker)
    j = t.index("\n\n", i)
    return t[i:j]
fails = []
r11 = para("**R11 (MUST)**")
if re.search(r"not a takedown for this rule's purposes and is judged\s+in full by the ordinary rules", r11):
    fails.append("R11 mixed-PR sentence still says judged in full by the ordinary rules")
for need in ("ADR-0041", "Ludwig, 2026-10-17", "rejected\nby `R11` itself", ):
    if need not in r11:
        fails.append("R11 paragraph lacks %r" % need)
checks = {
    "R3": (para("**R3 (MUST)**"), r"`R11` rejects it as well"),
    "R7": (para("**R7 (MUST)**"), r"rejected by `R11`\s+as well as by this rule"),
    "R11 other authors": (r11, r"`R11` rejects that author's takedown PR as well"),
    "R11 precedence": (r11, r"rejected by `R11` itself"),
    "R11 unconfigured": (para("**The mechanism, marked"), r"rejected by `R11` \(and by `R3`/`R7`\)"),
    "Attempt 8": (para("**Attempt 8"), r"rejected by `R11` itself, whoever its author is"),
    "Attempt 9": (para("**Attempt 9"), r"rejected by `R11` and by `R3`/`R7`"),
    "table row": ("\n".join(l for l in t.splitlines() if l.startswith("| `R11` |")), r"takedown mutation appears in a PR that is not nothing but takedown mutations"),
}
for k, (body, pat) in checks.items():
    if not re.search(pat, body):
        fails.append("%s does not state that R11 rejects (pattern %r)" % (k, pat))
    else:
        print("      ok  %s" % k)
for f in fails:
    print("FAILMSG " + f)
sys.exit(1 if fails else 0)
PY
[ $? = 0 ] && [ -s "$C" ] && pass "R11's mixed-PR sentence is amended, R11 names ADR-0041 and Ludwig 2026-10-17, and R3/R7/R11/Attempt 8/Attempt 9/table row each state that R11 rejects (ownership.md at FINAL $FINAL)" || fail "contract text check failed (FAILMSG lines above; or ownership.md unreadable at FINAL $FINAL)"
( cd "$TMP/head" && bash docs/tasks/032-verify.sh > "$TMP/032.out" 2>&1 ); rc=$?
[ "$rc" = 0 ] && pass "032-verify.sh (incl. T16, T17) exits 0 on HEAD" || { fail "032-verify.sh exits $rc"; grep '^FAIL' "$TMP/032.out"; }

printf '\n== RESULT ==\n'
if [ "$FAILURES" = 0 ]; then echo "ALL CHECKS PASSED"; else echo "$FAILURES CHECK(S) FAILED"; fi
exit "$FAILURES"
