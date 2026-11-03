#!/usr/bin/env bash
#
# 057-verify.sh -- the runnable verification artefact for task 057 (MANAGER.md Section 2c).
#
# Usage:  ./docs/tasks/057-verify.sh [NODE_MODULES_DIR]     (run from the repository root)
#   NODE_MODULES_DIR  a node_modules directory containing ajv 8. Resolution order (task 066): this argument, then env
#                     WOM_NODE_MODULES, then <repo root>/tools/dev/node_modules (install: npm ci --prefix tools/dev).
#                     Without ajv or node, criterion 4 prints SKIPPED and COUNTS AS A FAILURE: a skip never yields green.
#   ADR-0121 (criterion 1, A1): the registry has no ADR directory and its history never contained one, so the status is
#                     read from a fixture blob embedded below (task 089a2, Q4 option B): the title and Status lines of
#                     docs/decisions/0121-version-lifecycle-pending.md at PLATFORM-repo commit 84064c9cf1c858844477701f32f42adea438bc6b
#                     (git blob 16064b511c422acca2d3f628bdfa7614c85440e6). No working copy is read and no path or env var names one.
#   The scope and pre-change checks (T1 README, T2, S1, S2, S4) measure this task's OWN commit range, pinned at both ends
#   (task 062, D-1; full 40-character SHAs since task 089a2): BASE_COMMIT a50daacd7e26235d1acdeadc7d19265f1b2d04e3 (the
#   registry main this task was cut from) .. FINAL_COMMIT 3ab8f43d96013889a48e2005c57a75731b3d655f (the last commit on
#   task/057-version-lifecycle before its merge, registry PR #8: `git rev-parse e009ef0b28413700f0c41470f6e45905bf627cda^2`).
#   T1 hands 057-textchecks.py the docs/contracts/README.md blob AT FINAL_COMMIT (`--readme`), not the HEAD file: a later task
#   may legitimately edit that README (task 089a2, finding 6). An unreadable pin is a FAIL, never a skip.
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
NM="${1:-${WOM_NODE_MODULES:-$(git rev-parse --show-toplevel)/tools/dev/node_modules}}"
BASE_COMMIT="a50daacd7e26235d1acdeadc7d19265f1b2d04e3"
FINAL_COMMIT="3ab8f43d96013889a48e2005c57a75731b3d655f"

echo "== 1 authority (criterion 1)"
# Fixture blob (task 089a2, Q4 option B): lines 1 and 3 of the ADR at platform commit 84064c9cf1c858844477701f32f42adea438bc6b.
ADR="$(cat <<'ADR0121'
# ADR-0121: Version lifecycle — a `pending` state, a one-time pipeline write-back, and a post-merge build
- **Status:** Accepted (Ludwig, in session, 2026-10-15: "Stjärna på allt")
ADR0121
)"
if printf '%s\n' "$ADR" | grep -q '^# ADR-0121:' && printf '%s\n' "$ADR" | grep -q 'Status:\*\* Accepted'; then pass "A1 ADR-0121 (fixture blob of platform commit 84064c9, ADR blob 16064b5) carries 'Status:** Accepted'"; else fail "A1 the ADR-0121 fixture does not carry 'Status:** Accepted'"; fi
grep -q 'ADR-0121' docs/tasks/057-version-lifecycle-contract.md && pass "A2 the task file cites ADR-0121" || fail "A2 task file does not cite ADR-0121"

echo "== 2 contract text (criteria 2, 7)"
# The contracts README is read AT FINAL_COMMIT (task 089a2, finding 6): the "names task 057" check is 057's own change.
README_BLOB="$(mktemp)"
if git show "$FINAL_COMMIT:docs/contracts/README.md" > "$README_BLOB" 2>/dev/null && [ -s "$README_BLOB" ]; then
  $PY docs/tasks/057-textchecks.py --readme "$README_BLOB" > /tmp/057-text.$$ ; rc=$?
  grep -c '^PASS' /tmp/057-text.$$ | sed 's/^/  passing text checks: /'
  grep '^FAIL' /tmp/057-text.$$
  [ $rc -eq 0 ] && pass "T1 all text checks (old sentences gone, new sentences present, sections equal their full-text pins, README at $FINAL_COMMIT names task 057)" || fail "T1 $rc text check(s) failed"
  rm -f /tmp/057-text.$$
else
  fail "T1 cannot read docs/contracts/README.md at pinned FINAL_COMMIT $FINAL_COMMIT: the text checks cannot run"
fi
rm -f "$README_BLOB"
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
  echo "SKIPPED: node or ajv under '${NM:-<no path given>}' unavailable. Criterion 4 is NOT MET (a skip never yields green). Install the pinned ajv with: npm ci --prefix tools/dev"
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
