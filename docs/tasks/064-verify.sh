#!/usr/bin/env bash
#
# 064-verify.sh -- the runnable verification artefact for task 064 (MANAGER.md Section 2c).
#
# Task 064: the registry's schema validators match `pattern` with ECMA-262 semantics (end of input, ASCII \d \w, ECMA \s and .).
# Demonstrates acceptance criteria 1-6 of docs/tasks/064-schema-check-end-anchor.md.
#
# Usage:  docs/tasks/064-verify.sh [--mutate] [NODE_MODULES_DIR]      (any cwd inside the repository)
#   (no flag)  AC1 (red on the red commit), AC2 (fixed at HEAD, controls kept), AC3 (Ajv agreement),
#              AC4 (other suites and the closed verify scripts), AC5 (034 C3.3 re-pinned only), file scope.
#   --mutate   AC6: fifteen mutations in a temporary clone, each must turn the new tests red.
#   NODE_MODULES_DIR  (or env WOM_NODE_MODULES) a node_modules directory containing ajv 8 (a missing ajv is a
#                     FAILURE, never a skip).
# Everything runs on the COMMITTED state (HEAD) in temporary clones; the caller's worktree is never modified.
# Deterministic, no network. Exit code: the number of failed checks. Output has no timestamps or temp paths.
# Requires: git, python3, node, plus everything the closed verify scripts require (minisign, ...).

set -u
set -o pipefail

MUTATE=0
NM="${WOM_NODE_MODULES:-}"
for a in "$@"; do
    case "$a" in
        --mutate) MUTATE=1 ;;
        *) NM="$a" ;;
    esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
BASE="ac22c8f"      # registry origin/main when task 064 was cut
RED="4299b80"       # the commit that adds the new failing cases and nothing else (AC1)
RED2="30ef7d5"      # amendment 1: the commit that turns the Q1 expected failures into normal tests and adds the translation tests, no fix
TESTF="tests/registry/test_pattern_semantics.py"
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT

for c in "$BASE" "$RED" "$RED2"; do
    if ! git -C "$ROOT" rev-parse --verify -q "$c^{commit}" >/dev/null; then
        fail "P0 commit $c is reachable"
        exit "$FAILURES"
    fi
done
HEADSHA="$(git -C "$ROOT" rev-parse HEAD)"
clone_at() { git clone -q --no-hardlinks "$ROOT" "$1" 2>/dev/null && git -C "$1" checkout -q --detach "$2"; }
clone_at "$TMP/head" "$HEADSHA" || exit 99
clone_at "$TMP/red" "$RED" || exit 99
clone_at "$TMP/red2" "$RED2" || exit 99

# run_tests DIR -> runs the new test module in DIR, output to $TMP/t.out, returns its exit code
run_tests() { ( cd "$1" && python3 -I -m unittest discover -s tests/registry -p 'test_pattern_semantics.py' -v >"$TMP/t.out" 2>&1 ); }

section "AC1 -- red first: at the red commit the new cases fail"
if git -C "$ROOT" merge-base --is-ancestor "$RED" "$HEADSHA"; then pass "AC1.1 red commit $RED is an ancestor of HEAD"; else fail "AC1.1 $RED is not an ancestor of HEAD"; fi
if git -C "$ROOT" merge-base --is-ancestor "$BASE" "$RED"; then pass "AC1.2 the base $BASE is an ancestor of the red commit"; else fail "AC1.2 base is not an ancestor of the red commit"; fi
RF=$(git -C "$ROOT" diff --name-only "$RED"~1 "$RED" | tr '\n' ' ')
if [ "$RF" = "docs/tasks/057-corpus.py tests/registry/test_pattern_semantics.py " ]; then pass "AC1.3 the red commit adds only the test module and the corpus cases (no fix)"; else fail "AC1.3 red commit touches: $RF"; fi
if git -C "$ROOT" diff --quiet "$BASE" "$RED" -- tests/contracts tests/validation tools; then pass "AC1.4 validators and tools are unchanged at the red commit"; else fail "AC1.4 the red commit already changes a validator"; fi
run_tests "$TMP/red"; rc=$?
nfail=$(grep -cE '\.\.\. (FAIL|ERROR)$' "$TMP/t.out")
if [ "$rc" != 0 ] && [ "$nfail" -gt 0 ]; then pass "AC1.5 red commit: new test module exits $rc with $nfail failing subtests"; else fail "AC1.5 red commit: exit $rc, failing subtests $nfail (expected red)"; fi
for t in test_valid_value_plus_newline_is_rejected_by_every_path test_one_fullwidth_digit_is_rejected_by_every_path test_the_f1_case_from_the_review; do
    if grep -E "^(FAIL|ERROR): $t " "$TMP/t.out" >/dev/null; then pass "AC1.6 red commit: $t is red"; else fail "AC1.6 red commit: $t is not red"; fi
done

section "AC1b -- amendment 1, red first: at the second red commit the escape-translation tests fail"
if git -C "$ROOT" merge-base --is-ancestor "$RED2" "$HEADSHA" && git -C "$ROOT" merge-base --is-ancestor "$RED" "$RED2"; then pass "AC1b.1 $RED2 is between the first red commit and HEAD"; else fail "AC1b.1 $RED2 is not in the history between $RED and HEAD"; fi
RF2=$(git -C "$ROOT" diff --name-only "$RED2"~1 "$RED2" | tr '\n' ' ')
if [ "$RF2" = "tests/registry/test_pattern_semantics.py " ]; then pass "AC1b.2 the second red commit changes only the test module (no fix)"; else fail "AC1b.2 second red commit touches: $RF2"; fi
if git -C "$ROOT" diff --quiet "$RED2"~1 "$RED2" -- tests/contracts tests/validation tools; then pass "AC1b.3 validators and tools are unchanged by the second red commit"; else fail "AC1b.3 the second red commit changes a validator"; fi
run_tests "$TMP/red2"; rc=$?
nfail=$(grep -cE '\.\.\. (FAIL|ERROR)$' "$TMP/t.out")
if [ "$rc" != 0 ] && [ "$nfail" -gt 0 ]; then pass "AC1b.4 second red commit: exit $rc with $nfail failing subtests"; else fail "AC1b.4 second red commit: exit $rc, failing subtests $nfail (expected red)"; fi
for t in test_backslash_s_rejects_unicode_whitespace test_dot_rejects_cr_and_line_separators_but_accepts_other_characters test_whitespace_escape_is_the_ecma_set test_unsupported_constructs_raise_not_silently_pass test_no_re_ascii_flag_remains_in_any_pattern_path test_rejection_message_names_the_ecma_reason_for_translated_cases; do
    if grep -E "^(FAIL|ERROR): $t " "$TMP/t.out" >/dev/null; then pass "AC1b.5 second red commit: $t is red"; else fail "AC1b.5 second red commit: $t is not red"; fi
done
if [ -z "$NM" ] || [ ! -d "$NM/ajv" ] || ! command -v node >/dev/null 2>&1; then
    fail "AC0 prerequisite: node and a node_modules directory with ajv are required; pass NODE_MODULES_DIR or set WOM_NODE_MODULES"
    printf '\n== RESULT ==\n%d CHECK(S) FAILED\n' "$FAILURES"
    exit "$FAILURES"
fi

# corpus_compare DIR -> prints "<n_cases> <n_pattern064_cases> <n_pattern064_disagreements> <n_other_disagreements>"
corpus_compare() {
    ( cd "$1" && python3 -I docs/tasks/057-corpus.py > "$TMP/c.json" && node docs/tasks/057-ajv-check.mjs "$NM" < "$TMP/c.json" > "$TMP/a.json" ) || { echo "ERR"; return; }
    python3 -I - "$TMP/c.json" "$TMP/a.json" <<'PYE'
import json, sys
c = json.load(open(sys.argv[1])); a = json.load(open(sys.argv[2]))["verdicts"]
assert len(c) == len(a) and all(x["name"] == y["name"] for x, y in zip(c, a))
dis = [x["name"] for x, y in zip(c, a) if x["python"] != y["ajv"]]
n64 = sum(1 for x in c if x["name"].startswith("pattern064:"))
print(len(c), n64, sum(1 for d in dis if d.startswith("pattern064:")), sum(1 for d in dis if not d.startswith("pattern064:")))
PYE
}
read -r n n64 d64 dother <<<"$(corpus_compare "$TMP/red")"
if [ "${n:-ERR}" != ERR ] && [ "$n64" = 10 ] && [ "$d64" = 10 ] && [ "$dother" = 0 ]; then
    pass "AC1.7 red commit: all $d64 of the $n64 new corpus cases (8 trailing-newline, 2 fullwidth) disagree with Ajv; other disagreements: $dother"
else
    echo "  red corpus: n=$n n64=$n64 d64=$d64 dother=$dother"
    fail "AC1.7 red commit: expected 10 new corpus cases, all 10 disagreeing with Ajv"
fi

section "AC2 -- fixed at HEAD: the cases are rejected, the controls kept"
run_tests "$TMP/head"; rc=$?
ran=$(grep -E '^Ran [0-9]+ tests' "$TMP/t.out")
if [ "$rc" = 0 ]; then pass "AC2.1 HEAD: new test module green ($ran; $(tail -1 "$TMP/t.out"))"; else fail "AC2.1 HEAD: new test module exits $rc"; tail -15 "$TMP/t.out"; fi
for t in test_valid_samples_are_accepted_by_every_path test_unanchored_pattern_still_matches_mid_string test_end_anchor_only_pattern_still_matches_a_suffix test_alternation_with_end_anchor_keeps_search_semantics test_dollar_inside_class_or_escaped_is_literal_not_end_anchor test_valid_value_plus_newline_is_rejected_by_every_path test_one_fullwidth_digit_is_rejected_by_every_path; do
    if grep -qE "^$t .*\.\.\. ok$" "$TMP/t.out"; then pass "AC2.2 HEAD: $t ok"; else fail "AC2.2 HEAD: $t not ok"; fi
done
if [ "$(grep -cE '\.\.\. (expected failure|skipped)' "$TMP/t.out")" = 0 ]; then pass "AC2.3 HEAD: no expected-failure or skipped test remains (the Q1 gaps are closed by amendment 1)"; else fail "AC2.3 HEAD: expected-failure or skipped tests remain"; fi
for t in test_backslash_s_rejects_unicode_whitespace test_dot_rejects_cr_and_line_separators_but_accepts_other_characters test_backslash_s_still_accepts_non_ascii_visible_characters test_whitespace_escape_is_the_ecma_set test_unsupported_constructs_raise_not_silently_pass test_rejection_message_names_the_ecma_reason_for_translated_cases; do
    if grep -qE "^$t .*\.\.\. ok$" "$TMP/t.out"; then pass "AC2.3b HEAD: $t ok"; else fail "AC2.3b HEAD: $t not ok"; fi
done
if grep -nE 're\.fullmatch\(' "$TMP/head/tests/contracts/schema_check.py" "$TMP/head/tests/validation/schema_check.py" "$TMP/head/tools/registry/schema.py"; then fail "AC2.4 re.fullmatch( is called somewhere"; else pass "AC2.4 no re.fullmatch( call in the three pattern paths"; fi

section "AC3 -- agreement with Ajv (057 V1 corpus now carries the new cases)"
read -r n n64 d64 dother <<<"$(corpus_compare "$TMP/head")"
if [ "${n:-ERR}" != ERR ] && [ "$n64" = 12 ] && [ "$d64" = 0 ] && [ "$dother" = 0 ]; then
    AJV=$(python3 -I -c "import json;print(json.load(open('$TMP/a.json'))['ajv_version'])")
    pass "AC3.1 HEAD: Python and Ajv $AJV (2020, strict:true) agree on all $n corpus cases, including the $n64 new ones"
else
    echo "  head corpus: n=$n n64=$n64 d64=$d64 dother=$dother"
    fail "AC3.1 HEAD: disagreement with Ajv"
fi
( cd "$TMP/head" && bash docs/tasks/057-verify.sh "$NM" >"$TMP/057.out" 2>&1 ); rc=$?
if [ "$rc" = 0 ]; then pass "AC3.2 057-verify.sh (V1) exits 0 at HEAD"; else fail "AC3.2 057-verify.sh exits $rc at HEAD"; fi

section "AC4 -- no other suite moves"
for d in tests/contracts tests/registry tests/validation tests/pipeline; do
    ( cd "$TMP/head" && python3 -I -m unittest discover -s "$d" >"$TMP/u.out" 2>&1 ); rc=$?
    if [ "$rc" = 0 ]; then pass "AC4.1 unittest discover -s $d: $(grep -E '^Ran ' "$TMP/u.out")"; else fail "AC4.1 unittest discover -s $d exits $rc"; tail -8 "$TMP/u.out"; fi
done
for s in 006 032 034 057; do
    ( cd "$TMP/head" && bash docs/tasks/$s-verify.sh "$NM" >"$TMP/s.out" 2>&1 ); rc=$?
    if [ "$rc" = 0 ]; then pass "AC4.2 $s-verify.sh exits 0 at HEAD"; else fail "AC4.2 $s-verify.sh exits $rc at HEAD"; fi
done
# 007a-verify.sh checks its declared file scope as `git diff origin/main...HEAD` against ITS OWN scope, so on any branch of a
# later task that check is red by construction (062 does not include 007a in its later-branch set). Everything else it checks
# must be green, and the one red line must list only task 064's declared files.
( cd "$TMP/head" && bash docs/tasks/007a-verify.sh >"$TMP/s.out" 2>&1 ); rc=$?
fails=$(grep -E '^FAIL' "$TMP/s.out")
if [ "$rc" = 0 ]; then pass "AC4.2 007a-verify.sh exits 0 at HEAD"
elif [ "$(printf '%s\n' "$fails" | grep -c .)" = 1 ] && printf '%s\n' "$fails" | grep -q '^FAIL  files outside the declared scope'; then
    listed=$(awk '/^FAIL  files outside the declared scope/ {sub(/^FAIL  files outside the declared scope: /, ""); print; f=1; next} f && /^(docs|tests|tools|contracts)\// {print; next} {f=0}' "$TMP/s.out")
    extra=$(printf '%s\n' "$listed" | grep -vxE 'tests/contracts/schema_check\.py|tests/validation/schema_check\.py|docs/tasks/057-corpus\.py|docs/tasks/034-verify\.sh|docs/tasks/064-schema-check-end-anchor\.md|docs/tasks/064-verify\.sh')
    if [ -z "$extra" ]; then pass "AC4.2 007a-verify.sh: every check green except its by-construction branch-scope check, which lists only task 064's own declared files"; else fail "AC4.2 007a-verify.sh scope line lists files beyond task 064's scope: $extra"; fi
else fail "AC4.2 007a-verify.sh exits $rc; failing lines: $fails"; fi
# 062-verify.sh asserts `git diff $BASE062 HEAD -- docs/tasks/034-verify.sh` is empty (its AC6.034). Criterion 5 of task 064
# edits exactly that file, so that one check is red by construction; this is reported, never hidden (see the task log, Questions).
( cd "$TMP/head" && bash docs/tasks/062-verify.sh "$NM" >"$TMP/s.out" 2>&1 ); rc=$?
fails=$(grep -E '^FAIL' "$TMP/s.out" | grep -vE '^FAIL  AC[0-9a-z.]*\.008a ')   # 008a's temp-dir count check is racy when another agent runs 008a concurrently
if [ "$rc" = 0 ] || [ -z "$fails" ]; then pass "AC4.2 062-verify.sh exits 0 at HEAD"
else fail "AC4.2 062-verify.sh: $(printf '%s\n' "$fails" | awk '{print $2}' | tr '\n' ' ') -- BLOCKED by its own AC6.034 pin on 034-verify.sh (spec criteria 4 and 5 conflict; task 069 amends 062-verify.sh, then 064 rebases and must be green)"; fi

section "AC5 -- 034 C3.3 re-pinned, not weakened; C3.4 untouched; nothing else in a closed script"
CLOSED=$(git -C "$TMP/head" diff --name-only "$BASE" HEAD | grep -E '^docs/tasks/[0-9]+[a-z]?-verify\.sh$|^docs/tasks/(032|057)-' | grep -vE '^docs/tasks/(064-verify\.sh|057-corpus\.py)$')
if [ "$CLOSED" = "docs/tasks/034-verify.sh" ]; then pass "AC5.1 the only closed verify script changed is 034-verify.sh"; else fail "AC5.1 closed-script files changed: $CLOSED"; fi
D=$(git -C "$TMP/head" diff -U0 "$BASE" HEAD -- docs/tasks/034-verify.sh | grep -E '^[+-][^+-]')
DM=$(printf '%s\n' "$D" | grep -E '^-')
DP=$(printf '%s\n' "$D" | grep -E '^\+')
if [ "$(printf '%s\n' "$DM" | grep -c .)" = 1 ] && printf '%s\n' "$DM" | grep -qF "re\\.search(schema\\[\"pattern\"\\], instance)"; then pass "AC5.2 exactly one line removed: the old C3.3 call text"; else fail "AC5.2 removed lines: $DM"; fi
if printf '%s\n' "$DP" | grep -qF 're\.search(_ecma_pattern(schema\["pattern"\]), instance)' && printf '%s\n' "$DP" | grep -q 'task 064'; then pass "AC5.3 added: the new C3.3 call text (still re.search) plus a comment naming task 064"; else fail "AC5.3 added lines: $DP"; fi
if printf '%s\n' "$D" | grep -vE '^\+#' | grep -qE 'C3\.4|fullmatch'; then fail "AC5.4 C3.4 / fullmatch lines were edited"; else pass "AC5.4 C3.4 (no re.fullmatch call) is not edited"; fi
if [ "$(git -C "$TMP/head" diff --stat "$BASE" HEAD -- docs/tasks/034-verify.sh | tail -1 | grep -oE '[0-9]+ insertions?')" = "4 insertions" ]; then pass "AC5.5 034-verify.sh: 4 inserted lines (1 call, 3 comment), 1 removed"; else fail "AC5.5 unexpected 034-verify.sh diff size"; fi
SRCDIFF=$(git -C "$TMP/head" diff -U0 "$BASE" HEAD -- tools/registry/schema.py | grep -E '^[+-][^+-]')
if [ -n "$SRCDIFF" ] && ! git -C "$TMP/head" diff -U0 "$BASE" HEAD -- tools/registry/schema.py | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -qE 'def (check|validate|_strict_patterns|load_schema|loads_strict)'; then pass "AC5.6 tools/registry/schema.py: only ecma_pattern (translation, amendment 1) and the pattern call changed; no other function touched"; else fail "AC5.6 schema.py diff touches more than ecma_pattern"; fi
if grep -rn 're\.ASCII' "$TMP/head/tests/contracts/schema_check.py" "$TMP/head/tests/validation/schema_check.py" "$TMP/head/tools/registry/schema.py"; then fail "AC5.7 re.ASCII is still present in a pattern path"; else pass "AC5.7 no re.ASCII anywhere in the three pattern paths (amendment 1)"; fi

section "File scope -- only the declared files differ from the base"
extra=$(git -C "$TMP/head" diff --name-only "$BASE" HEAD | grep -vxE 'tests/contracts/schema_check\.py|tests/validation/schema_check\.py|tools/registry/schema\.py|tests/registry/test_pattern_semantics\.py|docs/tasks/057-corpus\.py|docs/tasks/034-verify\.sh|docs/tasks/064-schema-check-end-anchor\.md|docs/tasks/064-verify\.sh')
if [ -z "$extra" ]; then pass "S1 changed files are within the declared scope"; else fail "S1 out-of-scope files changed: $(printf '%s' "$extra" | tr '\n' ' ')"; fi
if git -C "$TMP/head" diff --quiet "$BASE" HEAD -- contracts; then pass "S2 no schema in contracts/ changed"; else fail "S2 contracts/ changed"; fi
REM=$(git -C "$TMP/head" diff "$BASE" HEAD -- tests | grep -E '^-[^-]')
# the only existing lines that change are the two schema_check pattern calls and (task 064) the message line below them
if [ "$(printf '%s\n' "$REM" | grep -c .)" = 4 ] && [ "$(printf '%s\n' "$REM" | grep -cF 're.search(schema["pattern"], instance) is None:')" = 2 ] && [ "$(printf '%s\n' "$REM" | grep -cF 'does not match pattern')" = 2 ]; then
    pass "S3 existing test files: exactly the 2 validator pattern calls and their 2 message lines changed (no test removed or weakened)"
else fail "S3 unexpected removed lines under tests/: $REM"; fi
if [ -x "$ROOT/docs/tasks/064-verify.sh" ]; then pass "S4 064-verify.sh is executable"; else fail "S4 064-verify.sh is not executable"; fi

if [ "$MUTATE" = 1 ]; then
    section "AC6 -- mutations in a temporary clone, each must turn the new tests red"
    M="$TMP/head"
    CC=tests/contracts/schema_check.py; VC=tests/validation/schema_check.py; SP=tools/registry/schema.py
    # mutate FILE OLD NEW -> replace exactly one occurrence
    mutate() { python3 -I - "$M/$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
t = open(p, encoding="utf-8").read()
assert t.count(old) == 1, (p, old, t.count(old))
open(p, "w", encoding="utf-8").write(t.replace(old, new))
PY
    }
    restore() { git -C "$M" checkout -q -- . ; }
    run_tests "$M"; if [ $? = 0 ]; then pass "AC6.0 control: new tests green before mutating"; else fail "AC6.0 control: new tests not green before mutating"; fi
    check_red() { # label
        if run_tests "$M"; then fail "AC6 $1: tests stayed GREEN (mutation survived)"; else pass "AC6 $1: red ($(grep -cE '\.\.\. (FAIL|ERROR)$' "$TMP/t.out") failing subtests)"; fi
        restore
    }
    for P in "$CC:contracts" "$VC:validation"; do
        F="${P%%:*}"; N="${P##*:}"
        mutate $F 'out.append("\\Z")' 'out.append("$")';                                  check_red "plain \$ in tests/$N/schema_check.py"
        mutate $F '"d": "[0-9]"' '"d": "\\d"';                                            check_red "translation \\d removed in tests/$N/schema_check.py"
        mutate $F '"S": "[^" + _WS + "]"' '"S": "\\S"';                                   check_red "translation \\S removed in tests/$N/schema_check.py"
        mutate $F '_DOT = "[^\\n\\r\\u2028\\u2029]"' '_DOT = "."';                     check_red "translation . removed in tests/$N/schema_check.py"
        mutate $F 'instance) is None:' 'instance) is None or True:';                         check_red "positive control: tests/$N/schema_check.py rejects every string"
    done
    F=$SP; N="tools/registry/schema.py"
    mutate $F 'out.append("\\Z")' 'out.append("$")';                                      check_red "plain \$ in $N"
    mutate $F '"d": "[0-9]"' '"d": "\\d"';                                                check_red "translation \\d removed in $N"
    mutate $F '"S": "[^" + _WS + "]"' '"S": "\\S"';                                       check_red "translation \\S removed in $N"
    mutate $F '_DOT = "[^\\n\\r\\u2028\\u2029]"' '_DOT = "."';                         check_red "translation . removed in $N"
    mutate $F 'instance) is None:' 'instance) is None or True:';                             check_red "positive control: $N strict path rejects every string"
    run_tests "$M"; if [ $? = 0 ]; then pass "AC6.10 restored: new tests green again"; else fail "AC6.10 restored tree is not green"; fi
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" = 0 ]; then echo "ALL CHECKS PASSED"; else echo "$FAILURES CHECK(S) FAILED"; fi
exit "$FAILURES"
