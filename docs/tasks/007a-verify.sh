#!/usr/bin/env bash
#
# 007a-verify.sh -- the runnable verification artefact for task 007a (MANAGER.md 2c).
#
# Usage (from anywhere; it cd's to the repository root):
#   ./docs/tasks/007a-verify.sh            run the suite and the structural checks
#   ./docs/tasks/007a-verify.sh --mutate   break each guard in a scratch CLONE of the COMMITTED tree and
#                                          require the named tests to turn red (A3). Set WOM_TMP to choose
#                                          the scratch parent directory (default: the system temp dir).
#
# Exit code: the number of failed checks (0 = everything passed). One line per check.
# Needs: git, python3. A missing tool is a FAILURE, never a skip. Reads no credential, reaches no network.
set -u
cd "$(dirname "$0")/../.." || exit 99
FAILS=0
fail() { echo "FAIL  $*"; FAILS=$((FAILS + 1)); }
ok()   { echo "ok    $*"; }

for tool in git python3; do
  command -v "$tool" >/dev/null 2>&1 && ok "tool present: $tool" || fail "tool missing: $tool"
done
[ "$FAILS" -eq 0 ] || { echo "SUMMARY failed=$FAILS (tools missing)"; exit "$FAILS"; }

# A3(a) completeness, read from the oracle's own list as TEXT (the oracle is never imported): every name in
# 057-oracle.py's MUTATIONS list has an oracle-NN-<name> mutation in the runner.
oracle_names() { python3 - <<'PY'
import re
src = open("docs/tasks/057-oracle.py").read()
block = re.search(r"MUTATIONS = \[(.*?)\]", src, re.S).group(1)
print("\n".join(re.findall(r'"([a-z0-9_]+)"', block)))
PY
}
check_oracle_coverage() {
  local names listed missing=0 n
  names=$(oracle_names)
  listed=$(python3 tests/registry/mutate.py --list)
  [ "$(echo "$names" | wc -l)" -ge 29 ] && ok "A3(a) oracle MUTATIONS list read from text: $(echo "$names" | wc -l) names" || fail "A3(a) oracle list has fewer than 29 names (search found too little)"
  for n in $names; do
    echo "$listed" | grep -Eq "^oracle-[0-9]+-$n\$" || { fail "A3(a) no analogue mutation for oracle mutation '$n'"; missing=1; }
  done
  [ "$missing" -eq 0 ] && ok "A3(a) every oracle mutation name has an analogue in tests/registry/mutate.py"
}

if [ "${1:-}" = "--mutate" ]; then
  if [ -n "$(git status --porcelain -- tools tests docs)" ]; then
    fail "uncommitted changes in tools/ tests/ docs/: mutations run against the COMMITTED tree, commit first"
    echo "SUMMARY failed=$FAILS"; exit "$FAILS"
  fi
  check_oracle_coverage
  python3 tests/registry/mutate.py
  RC=$?
  [ "$RC" -eq 0 ] && ok "every mutation turned its named tests red" || fail "$RC mutation(s) did not turn their named tests red"
  echo "SUMMARY failed=$FAILS"
  exit "$FAILS"
fi

# 1. the suite, verbose: one line per test
OUT=$(python3 -B -m unittest discover -s tests/registry -v 2>&1)
RUNLINE=$(echo "$OUT" | grep -E '^Ran [0-9]+ tests')
N=$(echo "$RUNLINE" | grep -oE '[0-9]+' | head -1)
echo "$OUT" | tail -4
echo "$OUT" | tail -1 | grep -q '^OK' && ok "unittest: $RUNLINE, OK" || { fail "unittest not OK"; echo "$OUT" | grep -E '^(FAIL|ERROR)' ; }
[ "${N:-0}" -ge 120 ] && ok "suite ran at least 120 tests (${N})" || fail "suite ran only ${N:-0} tests (floor 120): a search that finds nothing is broken"

# 2. one named line per acceptance criterion: >=1 passing test and none failing
crit() { # label pattern
  local P F
  P=$(echo "$OUT" | grep -cE "^$2.* \.\.\. ok$")
  F=$(echo "$OUT" | grep -cE "^$2.* \.\.\. (FAIL|ERROR)$")
  if [ "$P" -ge 1 ] && [ "$F" -eq 0 ]; then ok "$1: $P passing, 0 failing"; else fail "$1: $P passing, $F failing"; fi
}
crit "umbrella 1/2  CLI + verdict shape + three distinct exit codes"        "test_(the_three_exit_codes|run_maps|usage_errors_exit_2|classify_(accepts|rejects)|schema_cli|append_only_cli_lists)"
crit "umbrella 3/A2 attacker:mod four-element, per-element attribution"   "test_a2_four_element"
crit "A2            attacker:mod three-element variant [0,1,3]"             "test_a2_three_element"
crit "A2            schema REJECT / VALID premises asserted"                "test_a2_(premise|measured|three_element_variant_is_schema_valid)"
crit "umbrella 7/A5 multi-T2 accepted, T2 + other change rejected"          "test_a5_"
crit "umbrella 7    T2/T3 variants (whitespace reason, extra field, old status)" "test_(t2_|t3_|takedown_from|exact_t)"
crit "umbrella 8    classification exhaustive and fail closed"              "test_(paths_outside_mods|empty_path_set|good_plus_outside|every_result_has|page_plus_entry|every_malformed_path)"
crit "ownership R1  path form rejected with a message citing R1"           "test_every_malformed_path_under_mods"
crit "I4            reserved list is merge-base data"                       "test_(the_list_is_what_the_caller|a_pr_editing_reserved)"
crit "umbrella 9    positive controls accepted"                             "test_(clean_|entry_only_pr|page_only_pr|valid_entry_and_page|exact_t1)"
crit "umbrella 10   messages name the problem, the rule and the remedy"     "test_(rejection_messages|parity_every_reject_fixture_carries|deletion_message)"
crit "umbrella 13   057 fixture parity (read at test time)"                 "test_parity_every_fixture_matches"
crit "A1            element classification of T1/T2/T3 accept fixtures"     "test_a1_"
crit "A4            fixture-count guard"                                    "test_a4_"
crit "F1            trailing newline rejected (ECMA end-of-input), 5 probes + schema path" "test_f1_"
crit "F2            symlinks rejected; --no-renames documented"             "test_f2_"
crit "F3            duplicate JSON keys rejected"                           "test_f3_"
crit "schema        reuses schema_check; unsupported keyword is exit 2"    "test_(an_unsupported_schema|the_attacker_four_element_entry_is_schema|every_published_example)"

# 3. structural checks
# Task 069: the size cap and the file-scope check below measure THIS task's own commit range, pinned at both ends, so
# they give the same answer on main, on any later branch (007b adds two source files) and in any fresh clone -- the
# same re-basing task 062 (D-1) applied to 006/008a/032/057. BASE is the registry commit the branch was cut from
# (e009ef0, the merge of task 057); FINAL is the last commit on task/007a-registry-checkers-shape before its merge
# (registry PR #10: the second parent of merge 3c94cf2, `git rev-parse 3c94cf2^2`). An unreachable pin is a FAILURE
# naming the commit, never a skip.
# Task 089a1 (findings 1 and 2): the two README checks below are task 007a's OWN change to docs/contracts/README.md, so they
# read the README blob at FINAL (`git show $FINAL:docs/contracts/README.md`), never the worktree or HEAD; a later task may
# legitimately reword the README (REVIEW-CHECKLIST item 12). An unreadable pin FAILS both checks (no skip, no vacuous pass).
# Pins are full 40-character SHAs: BASE = `git merge-base 3c94cf2^1 3c94cf2^2`, FINAL = `git rev-parse 3c94cf2^2`.
BASE=e009ef0b28413700f0c41470f6e45905bf627cda
FINAL=aaf426060338776a4556f35c1bb5cb6a20d65ea4
PINS_OK=1
for pin in "$BASE" "$FINAL"; do
  if ! git merge-base --is-ancestor "$pin" HEAD 2>/dev/null; then
    fail "pinned commit $pin is not an ancestor of HEAD: the size and scope checks cannot run"
    PINS_OK=0
  fi
done
if [ "$PINS_OK" = 1 ]; then
  SRC=$(git ls-tree --name-only "$FINAL" tools/registry/ | grep -c '\.py$')
  [ "$SRC" -le 5 ] && ok "size: $SRC source files in tools/registry at $FINAL (cap 5: report, classify, schema, append_only, cli)" || fail "size: $SRC source files in tools/registry at $FINAL (cap 5)"
fi
if grep -rnE '^\s*(import|from)\s+[^#]*(057-oracle|oracle)' tools tests/registry --include=*.py | grep -v 'mutate.py' >/dev/null; then fail "tools/ or tests/ imports the oracle"; else ok "no module imports 057-oracle.py"; fi
if grep -rn '057-oracle' tools --include=*.py >/dev/null; then fail "tools/ mentions the oracle"; else ok "tools/ never mentions the oracle (no copied logic)"; fi
if ls tests/registry | grep -q 'fixtures.*json'; then fail "tests/registry holds a copy of the fixtures"; else ok "057 fixtures are read from docs/tasks/057-transition-fixtures.json, not copied"; fi
grep -q "057-transition-fixtures.json" tests/registry/support.py && ok "support.py reads the fixture file by path" || fail "support.py does not reference the fixture file"
python3 tools/registry/cli.py --help | grep -q "never authorises a merge" && ok "CLI help documents that append-only alone is never a merge signal" || fail "CLI help lacks the authority warning"
python3 tools/registry/cli.py --help | grep -q "2 usage or internal error" && ok "CLI help documents the three exit codes" || fail "CLI help lacks the exit codes"
README_PATH=docs/contracts/README.md
if README_TXT=$(git show "$FINAL:$README_PATH" 2>/dev/null) && [ -n "$README_TXT" ]; then
  ok "$README_PATH is readable at 007a's pinned FINAL $FINAL (criterion 12 reads that copy, never HEAD)"
else
  README_TXT=""
  fail "pinned commit $FINAL (or $README_PATH at it) is not readable: criterion 12 has no README to read"
fi
if printf '%s\n' "$README_TXT" | grep -q "tools/registry" && printf '%s\n' "$README_TXT" | grep -q "task 039"; then ok "criterion 12: docs/contracts/README.md at $FINAL updated (built vs still owed)"; else fail "criterion 12: README at $FINAL not updated (or unreadable)"; fi
if [ -z "$README_TXT" ]; then fail "README-no-longer-says check cannot run: README at $FINAL unreadable (an empty input proves nothing)"
elif printf '%s\n' "$README_TXT" | grep -n "task 007$" >/dev/null || printf '%s\n' "$README_TXT" | grep -nE "task 007 +builds" >/dev/null; then fail "README at $FINAL still says task 007 builds the gates"; else ok "README at $FINAL no longer says task 007 builds the gates"; fi
# real exit codes through the real CLI (not only through unittest)
RES=$(mktemp)
echo '{"namespaces": {"mc": {}}}' > "$RES"
python3 tools/registry/cli.py classify --reserved-file "$RES" mods/a.b/page.json >/dev/null 2>&1; A=$?
python3 tools/registry/cli.py classify --reserved-file "$RES" mods/a.b/notes.txt >/dev/null 2>&1; B=$?
python3 tools/registry/cli.py classify --reserved-file /nonexistent mods/a.b/page.json >/dev/null 2>&1; C=$?
rm -f "$RES"
[ "$A $B $C" = "0 1 2" ] && ok "CLI exit codes accepted/rejected/error = $A $B $C" || fail "CLI exit codes were '$A $B $C', expected '0 1 2'"
# declared file scope, measured over the pinned range BASE..FINAL (pins verified above)
if [ "$PINS_OK" = 1 ]; then
  BAD=$(git diff --name-only "$BASE" "$FINAL" | grep -vE '^(tools/registry/|tests/registry/|docs/tasks/007a-registry-checkers-shape\.md$|docs/tasks/007a-verify\.sh$|docs/contracts/README\.md$)' || true)
  [ -z "$BAD" ] && ok "every path changed in $BASE..$FINAL is within the declared file scope" || fail "files outside the declared scope: $BAD"
fi
check_oracle_coverage

echo "SUMMARY failed=$FAILS"
exit "$FAILS"
