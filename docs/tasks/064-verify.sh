#!/usr/bin/env bash
#
# 064-verify.sh -- the runnable verification artefact for task 064 (MANAGER.md Section 2c).
#
# Task 064: the registry's schema validators match `pattern` with ECMA-262 semantics (end of input, ASCII \d).
# Demonstrates acceptance criteria 1-6 of docs/tasks/064-schema-check-end-anchor.md.
#
# Usage:  docs/tasks/064-verify.sh [--mutate] [NODE_MODULES_DIR]      (any cwd inside the repository)
#   (no flag)  AC1 (red on the red commit), AC2 (fixed at HEAD, controls kept), AC3 (Ajv agreement),
#              AC4 (other suites and the closed verify scripts), AC5 (034 C3.3 re-pinned only), file scope.
#   --mutate   AC6: nine mutations in a temporary clone, each must turn the new tests red.
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
TESTF="tests/registry/test_pattern_semantics.py"
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT

for c in "$BASE" "$RED"; do
    if ! git -C "$ROOT" rev-parse --verify -q "$c^{commit}" >/dev/null; then
        fail "P0 commit $c is reachable"
        exit "$FAILURES"
    fi
done
HEADSHA="$(git -C "$ROOT" rev-parse HEAD)"
clone_at() { git clone -q --no-hardlinks "$ROOT" "$1" 2>/dev/null && git -C "$1" checkout -q --detach "$2"; }
clone_at "$TMP/head" "$HEADSHA" || exit 99
clone_at "$TMP/red" "$RED" || exit 99

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
if grep -c 'expected failure' "$TMP/t.out" >/dev/null && [ "$(grep -cE '\.\.\. expected failure$' "$TMP/t.out")" = 2 ]; then pass "AC2.3 HEAD: the 2 known ECMA gaps (Questions Q1) are reported as expected failures"; else fail "AC2.3 HEAD: expected exactly 2 expected-failure tests"; fi
if grep -nE 're\.fullmatch\(' "$TMP/head/tests/contracts/schema_check.py" "$TMP/head/tests/validation/schema_check.py" "$TMP/head/tools/registry/schema.py"; then fail "AC2.4 re.fullmatch( is called somewhere"; else pass "AC2.4 no re.fullmatch( call in the three pattern paths"; fi

section "AC3 -- agreement with Ajv (057 V1 corpus now carries the new cases)"
read -r n n64 d64 dother <<<"$(corpus_compare "$TMP/head")"
if [ "${n:-ERR}" != ERR ] && [ "$n64" = 10 ] && [ "$d64" = 0 ] && [ "$dother" = 0 ]; then
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
for s in 006 032 034 057 062 007a; do
    ( cd "$TMP/head" && bash docs/tasks/$s-verify.sh "$NM" >"$TMP/s.out" 2>&1 ); rc=$?
    if [ "$rc" = 0 ]; then pass "AC4.2 $s-verify.sh exits 0 at HEAD"; else fail "AC4.2 $s-verify.sh exits $rc at HEAD"; fi
done

section "AC5 -- 034 C3.3 re-pinned, not weakened; C3.4 untouched; nothing else in a closed script"
CLOSED=$(git -C "$TMP/head" diff --name-only "$BASE" HEAD | grep -E '^docs/tasks/[0-9]+[a-z]?-verify\.sh$|^docs/tasks/(032|057)-' | grep -vE '^docs/tasks/(064-verify\.sh|057-corpus\.py)$')
if [ "$CLOSED" = "docs/tasks/034-verify.sh" ]; then pass "AC5.1 the only closed verify script changed is 034-verify.sh"; else fail "AC5.1 closed-script files changed: $CLOSED"; fi
D=$(git -C "$TMP/head" diff -U0 "$BASE" HEAD -- docs/tasks/034-verify.sh | grep -E '^[+-][^+-]')
DM=$(printf '%s\n' "$D" | grep -E '^-')
DP=$(printf '%s\n' "$D" | grep -E '^\+')
if [ "$(printf '%s\n' "$DM" | grep -c .)" = 1 ] && printf '%s\n' "$DM" | grep -qF "re\\.search(schema\\[\"pattern\"\\], instance)"; then pass "AC5.2 exactly one line removed: the old C3.3 call text"; else fail "AC5.2 removed lines: $DM"; fi
if printf '%s\n' "$DP" | grep -qF 're\.search\(_ecma_pattern(schema\["pattern"\]), instance, re\.ASCII\)' && printf '%s\n' "$DP" | grep -q 'task 064'; then pass "AC5.3 added: the new C3.3 call text (still re.search) plus a comment naming task 064"; else fail "AC5.3 added lines: $DP"; fi
if printf '%s\n' "$D" | grep -vE '^\+#' | grep -qE 'C3\.4|fullmatch'; then fail "AC5.4 C3.4 / fullmatch lines were edited"; else pass "AC5.4 C3.4 (no re.fullmatch call) is not edited"; fi
if [ "$(git -C "$TMP/head" diff --stat "$BASE" HEAD -- docs/tasks/034-verify.sh | tail -1 | grep -oE '[0-9]+ insertions?')" = "4 insertions" ]; then pass "AC5.5 034-verify.sh: 4 inserted lines (1 call, 3 comment), 1 removed"; else fail "AC5.5 unexpected 034-verify.sh diff size"; fi
SRCDIFF=$(git -C "$TMP/head" diff -U0 "$BASE" HEAD -- tools/registry/schema.py | grep -E '^[+-][^+-]')
if [ "$(printf '%s\n' "$SRCDIFF" | grep -c .)" = 2 ] && printf '%s\n' "$SRCDIFF" | grep -qF 're.ASCII'; then pass "AC5.6 tools/registry/schema.py: one line changed, the ASCII flag only"; else fail "AC5.6 schema.py diff: $SRCDIFF"; fi

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
    mutate $CC '_ecma_pattern(schema["pattern"]), instance, re.ASCII)' 'schema["pattern"], instance, re.ASCII)';  check_red "M1 plain \$ in tests/contracts/schema_check.py"
    mutate $VC '_ecma_pattern(schema["pattern"]), instance, re.ASCII)' 'schema["pattern"], instance, re.ASCII)';  check_red "M2 plain \$ in tests/validation/schema_check.py"
    mutate $SP 'ecma_pattern(sub["pattern"]), instance, re.ASCII)' 'sub["pattern"], instance, re.ASCII)';        check_red "M3 plain \$ in tools/registry/schema.py _strict_patterns"
    mutate $CC 'instance, re.ASCII)' 'instance)';                                                                  check_red "M4 no re.ASCII in tests/contracts/schema_check.py"
    mutate $VC 'instance, re.ASCII)' 'instance)';                                                                  check_red "M5 no re.ASCII in tests/validation/schema_check.py"
    mutate $SP 'instance, re.ASCII)' 'instance)';                                                                  check_red "M6 no re.ASCII in tools/registry/schema.py"
    mutate $CC 'instance, re.ASCII) is None:' 'instance, re.ASCII) is None or True:';                              check_red "M7 positive control: contracts validator rejects every string"
    mutate $VC 'instance, re.ASCII) is None:' 'instance, re.ASCII) is None or True:';                              check_red "M8 positive control: validation validator rejects every string"
    mutate $SP 'instance, re.ASCII) is None:' 'instance, re.ASCII) is None or True:';                              check_red "M9 positive control: strict path rejects every string"
    run_tests "$M"; if [ $? = 0 ]; then pass "AC6.10 restored: new tests green again"; else fail "AC6.10 restored tree is not green"; fi
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" = 0 ]; then echo "ALL CHECKS PASSED"; else echo "$FAILURES CHECK(S) FAILED"; fi
exit "$FAILURES"
