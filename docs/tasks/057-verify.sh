#!/usr/bin/env bash
#
# 057-verify.sh -- the runnable verification artefact for task 057 (MANAGER.md Section 2c).
#
# Usage:  ./docs/tasks/057-verify.sh [NODE_MODULES_DIR]     (run from the repository root)
#   NODE_MODULES_DIR  a node_modules directory containing ajv 8 (e.g. the site repo's). Without it, or
#                     without node, criterion 4 prints SKIPPED and COUNTS AS A FAILURE: a skip never yields green.
#   PLATFORM_REPO     env, default /home/ludwig/wom: the platform checkout that holds docs/decisions/0121-*.md
#                     (criterion 1 reads it from that repo's main; the registry itself has no ADR directory).
#   The scope and pre-change checks (T2, S1, S2, S4) measure this task's OWN commit range, pinned at both ends
#   (task 062, D-1): BASE_COMMIT a50daac (the registry main this task was cut from) .. FINAL_COMMIT 3ab8f43 (the
#   last commit on task/057-version-lifecycle before its merge, registry PR #8: `git rev-parse e009ef0^2`).
#   The range never moves, so they answer the same on main, on any later branch and in a fresh clone.
# Exit code: the number of failed checks. Every check that decides the verdict reads committed repository
# content only and makes no network call.
set -u
set -o pipefail
cd "$(git rev-parse --show-toplevel)" || exit 99
FAILURES=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILURES=$((FAILURES + 1)); }
PY="python3 -I"
NM="${1:-}"
PLATFORM_REPO="${PLATFORM_REPO:-/home/ludwig/wom}"
BASE_COMMIT="a50daac"
FINAL_COMMIT="3ab8f43"

echo "== 1 authority (criterion 1)"
ADR="$(git -C "$PLATFORM_REPO" show main:docs/decisions/0121-version-lifecycle-pending.md 2>/dev/null)"
if [ -n "$ADR" ] && printf '%s\n' "$ADR" | grep -q 'Status:\*\* Accepted'; then pass "A1 ADR-0121 on $PLATFORM_REPO main carries 'Status:** Accepted'"; else fail "A1 ADR-0121 not found or not Accepted on $PLATFORM_REPO main"; fi
grep -q 'ADR-0121' docs/tasks/057-version-lifecycle-contract.md && pass "A2 the task file cites ADR-0121" || fail "A2 task file does not cite ADR-0121"

echo "== 2 contract text (criteria 2, 7)"
$PY docs/tasks/057-textchecks.py > /tmp/057-text.$$ ; rc=$?
grep -c '^PASS' /tmp/057-text.$$ | sed 's/^/  passing text checks: /'
grep '^FAIL' /tmp/057-text.$$
[ $rc -eq 0 ] && pass "T1 all text checks (old sentences gone, new sentences present, sections equal their full-text pins)" || fail "T1 $rc text check(s) failed"
rm -f /tmp/057-text.$$
# An unreachable pin FAILS naming the commit; it never skips (MANAGER.md Section 2c rule 1).
PINS_OK=1
for pin in "$BASE_COMMIT" "$FINAL_COMMIT"; do
  git merge-base --is-ancestor "$pin" HEAD 2>/dev/null || { fail "P0 pinned commit $pin is not an ancestor of HEAD: T2, S1, S2 and S4 cannot run"; PINS_OK=0; }
done
MB="$BASE_COMMIT"
if [ "$PINS_OK" = 0 ]; then fail "T2 no usable pinned base commit"; else
  TMPD="$(mktemp -d)"
  git show "$MB:contracts/append-only.rules.md" > "$TMPD/rules.md"; git show "$MB:contracts/entry.schema.json" > "$TMPD/schema.json"
  OUT="$($PY docs/tasks/057-textchecks.py --old-present --rules "$TMPD/rules.md" --schema "$TMPD/schema.json")"; rc=$?
  echo "$OUT" | sed 's/^/  /' | head -30
  [ $rc -eq 0 ] && pass "T2 positive control: every old sentence is FOUND in the pre-change blobs at $MB" || fail "T2 positive control failed"
  rm -rf "$TMPD"
fi
echo "-- text mutations (criterion 6)"
$PY docs/tasks/057-textmutations.py; rc=$?
[ $rc -eq 0 ] && pass "T3 every contract-text mutation turns a check red" || fail "T3 $rc text mutation(s) survived"

echo "== 3 oracle, fixtures, mutations (criteria 5, 6)"
$PY docs/tasks/057-gen-fixtures.py | diff -q - docs/tasks/057-transition-fixtures.json >/dev/null && pass "F1 committed fixtures equal the generator's output" || fail "F1 fixtures differ from generator"
$PY docs/tasks/057-oracle.py; rc=$?
[ $rc -eq 0 ] && pass "O1 oracle classifies every fixture as recorded" || fail "O1 oracle disagrees with the fixtures"
survivors=0
for m in $($PY docs/tasks/057-oracle.py --list-mutations); do
  out="$($PY docs/tasks/057-oracle.py --mutation "$m")"
  names="$(printf '%s\n' "$out" | sed -n 's/^  MISMATCH \([^:]*\):.*/\1/p' | paste -sd, -)"
  if [ -n "$names" ]; then echo "  RED   $m -> $names"; else echo "  SURVIVED $m"; survivors=$((survivors + 1)); fi
done
[ $survivors -eq 0 ] && pass "O2 every oracle mutation reddens at least one named fixture" || fail "O2 $survivors oracle mutation(s) survived"

echo "== 4 schema and the repository's own tests (criterion 3)"
python3 -m unittest discover -s tests/contracts > /tmp/057-ut.$$ 2>&1; rc=$?
tail -3 /tmp/057-ut.$$; rm -f /tmp/057-ut.$$
[ $rc -eq 0 ] && pass "U1 python3 -m unittest over tests/contracts exits 0" || fail "U1 unittest exit $rc"
$PY - <<'PYE' && pass "U2 missing-key-id.json is still rejected, and for the right reason" || fail "U2 missing-key-id.json"
import json, sys
sys.path.insert(0, "tests/contracts")
from schema_check import SchemaValidationError, validate
schema = json.load(open("contracts/entry.schema.json"))
ex = json.load(open("contracts/examples/entry/invalid/missing-key-id.json"))["example"]
try:
    validate(ex, schema)
except SchemaValidationError as e:
    print("  rejected:", e)
    sys.exit(0 if "oneOf" in str(e) else 1)
sys.exit(1)
PYE

echo "== 5 two validators agree (criterion 4)"
if [ -z "$NM" ] || ! command -v node >/dev/null 2>&1 || [ ! -d "$NM/ajv" ]; then
  echo "SKIPPED: node or ajv under '${NM:-<no path given>}' unavailable. Criterion 4 is NOT MET (a skip never yields green)."
  fail "V1 Ajv agreement not demonstrated"
else
  $PY docs/tasks/057-corpus.py > /tmp/057-corpus.$$ && node docs/tasks/057-ajv-check.mjs "$NM" < /tmp/057-corpus.$$ > /tmp/057-ajv.$$ ; rc=$?
  if [ $rc -ne 0 ]; then fail "V1 Ajv strict compile or run failed (exit $rc)"; else
    $PY - /tmp/057-corpus.$$ /tmp/057-ajv.$$ <<'PYE' && pass "V1 schema_check.py and Ajv 2020 strict:true agree on every corpus case" || fail "V1 validators disagree"
import json, sys
c = json.load(open(sys.argv[1])); a = json.load(open(sys.argv[2]))
dis = [(x["name"], x["python"], y["ajv"]) for x, y in zip(c, a["verdicts"]) if x["name"] != y["name"] or x["python"] != y["ajv"]]
n_valid = sum(1 for x in c if x["python"] == "valid")
print(f"  ajv {a['ajv_version']}; {len(c)} cases ({n_valid} valid, {len(c)-n_valid} invalid); {len(a['verdicts'])} Ajv verdicts; disagreements: {dis}")
sys.exit(1 if dis or len(c) != len(a["verdicts"]) or n_valid == 0 or n_valid == len(c) else 0)
PYE
  fi
  rm -f /tmp/057-corpus.$$ /tmp/057-ajv.$$
fi

echo "== 6 scope and test integrity (criterion 8, task 045 criterion 6)"
if [ "$PINS_OK" = 1 ]; then
  echo "  \$ git diff --name-only $BASE_COMMIT $FINAL_COMMIT"
  CHANGED="$(git diff --name-only "$BASE_COMMIT" "$FINAL_COMMIT" | grep -v __pycache__ | sort -u)"
  BAD="$(printf '%s\n' "$CHANGED" | grep -v -E '^(contracts/entry\.schema\.json|contracts/append-only\.rules\.md|contracts/examples/entry/.*|tests/contracts/schema_check\.py|tests/contracts/test_contracts\.py|docs/contracts/README\.md|docs/tasks/057-.*)$' | grep -v '^$')"
  printf '%s\n' "$CHANGED" | sed 's/^/  changed: /'
  [ -z "$BAD" ] && pass "S1 every changed file is inside task 057's declared scope" || { fail "S1 out of scope: $BAD"; }
  DEL="$(git diff "$BASE_COMMIT" "$FINAL_COMMIT" -- tests/contracts/test_contracts.py tests/contracts/schema_check.py | grep -E '^-[^-]' )"
  [ -z "$DEL" ] && pass "S2 tests/contracts changes are additions only (no line removed)" || fail "S2 lines removed from tests: $DEL"
  PYC="$(git ls-files | grep -c '\.pyc$')"
  [ "$PYC" = 0 ] && pass "S3 no .pyc is tracked" || fail "S3 $PYC .pyc tracked"
  NONADD="$(git diff --name-status "$BASE_COMMIT" "$FINAL_COMMIT" -- contracts/examples/entry | grep -v '^A')"
  [ "$NONADD" = "M	contracts/examples/entry/invalid/status-not-in-enum.json" ] && pass "S4 existing entry examples untouched except the _comment of status-not-in-enum.json" || fail "S4 existing examples changed: $NONADD"
fi

echo
echo "== RESULT: $FAILURES check(s) failed"
exit "$FAILURES"
