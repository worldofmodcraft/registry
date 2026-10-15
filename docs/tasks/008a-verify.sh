#!/usr/bin/env bash
#
# 008a-verify.sh -- the runnable verification artefact for task 008a (MANAGER.md 2c).
#
# Usage (from anywhere; it cd's to the repository root):
#   ./docs/tasks/008a-verify.sh            run the whole suite + structural checks
#   ./docs/tasks/008a-verify.sh --mutate   break each guard in a scratch copy of the COMMITTED tree
#                                          and require the named checks to turn red
#
# Exit code: the number of failed checks (0 = everything passed). Prints one line per check.
# It needs: git, python3, gzip, sha256sum, tar, minisign. Missing tools are a FAILURE, never a skip.
# It never reads a real key or credential: every key is generated at test time in a wom008a-* temp dir.
set -u
cd "$(dirname "$0")/../.." || exit 99
FAILS=0
fail() { echo "FAIL  $*"; FAILS=$((FAILS + 1)); }
ok()   { echo "ok    $*"; }

for tool in git python3 gzip sha256sum tar minisign; do
  command -v "$tool" >/dev/null 2>&1 && ok "tool present: $tool" || fail "tool missing: $tool"
done
[ "$FAILS" -eq 0 ] || { echo "SUMMARY failed=$FAILS (tools missing)"; exit "$FAILS"; }

if [ "${1:-}" = "--mutate" ]; then
  # the suite must be green on the committed tree first, or a "red" mutation proves nothing
  if [ -n "$(git status --porcelain -- tools tests docs/pipeline docs/validation)" ]; then
    fail "uncommitted changes in tools/ tests/ docs/: mutations run against the COMMITTED tree, commit first"
    echo "SUMMARY failed=$FAILS"; exit "$FAILS"
  fi
  python3 tests/pipeline/mutate.py
  RC=$?
  echo "SUMMARY mutation-runner not_red=$RC"
  exit "$RC"
fi

# Task 069: the suite runs with TMPDIR pointing at a fresh per-run directory, and the leak check below counts only
# inside it. The old check counted every /tmp/wom008a-* entry on the machine, so any concurrent 008a run (another
# agent, another worktree, task 062's clones) raised the count and failed the check without any leak. A real leak
# (a wom008a-* directory a test creates and does not remove) still lands inside RUNTMP and still fails the check.
RUNTMP=$(mktemp -d "${TMPDIR:-/tmp}/w008a-run.XXXXXX") || { echo "FAIL  cannot create the per-run temp dir"; exit 99; }
trap 'rm -rf "$RUNTMP"' EXIT
export TMPDIR="$RUNTMP"
TMP_BEFORE=$(ls -d "$RUNTMP"/wom008a-* 2>/dev/null | wc -l)

# 1. the suite: one CHECK line per test
OUT=$(python3 tests/pipeline/run_checks.py 2>"$RUNTMP/verify-stderr")
echo "$OUT" | grep -v ' PASS$' | grep -v '^CHECK' || true
PASSN=$(echo "$OUT" | grep -c '^CHECK .* PASS$')
FAILN=$(echo "$OUT" | grep -c '^CHECK .* FAIL$')
echo "$OUT" | grep '^CHECK .* FAIL$' | sed 's/^/FAIL  /'
echo "suite: $PASSN passed, $FAILN failed"
[ "$FAILN" -eq 0 ] || { fail "$FAILN suite check(s) failed"; cat "$RUNTMP/verify-stderr" >&2; }
# a search that finds nothing is a broken search (2c rule 1)
[ "$PASSN" -ge 100 ] && ok "suite ran at least 100 checks ($PASSN)" || fail "suite ran only $PASSN checks (floor 100)"
rm -f "$RUNTMP/verify-stderr"

# one named line per acceptance criterion: at least one passing check and none failing
for pat in test_ac1_ test_ac2_ test_ac3_ test_ac4_ test_ac5_ test_ac6_ test_ac7_ test_ac8_ test_ac9_ test_ac10_ test_ac11_ test_ac12_ test_ac13_ test_ac16_ test_ac17_ test_a1_ test_a2_ test_a3_; do
  P=$(echo "$OUT" | grep -c "^CHECK .*$pat.* PASS$")
  F=$(echo "$OUT" | grep -c "^CHECK .*$pat.* FAIL$")
  if [ "$P" -ge 1 ] && [ "$F" -eq 0 ]; then ok "$pat*: $P passing, 0 failing"; else fail "$pat*: $P passing, $F failing"; fi
done

# 2. AC15 docs: each required section heading is present (prose is read by the reviewer)
for h in '^## CLI' '^### Exit codes' '^### Outputs' '^## Design decisions' '^## The reference verifier' '^## SSRF note' '^## What is NOT verified' '^## Tests and verification'; do
  grep -q -E "$h" docs/pipeline/build-pipeline.md && ok "build-pipeline.md has $h" || fail "build-pipeline.md lacks $h"
done
for n in 1 2 3 4 5 6 7; do
  grep -q -E "^$n\. \*\*" docs/pipeline/build-pipeline.md && ok "design decision $n documented" || fail "design decision $n missing"
done
for h in '^## What it accepts' '^## What it rejects' '^## Projection'; do
  grep -q -E "$h" docs/validation/manifest-reader.md && ok "manifest-reader.md has $h" || fail "manifest-reader.md lacks $h"
done
grep -q 'build-pipeline.md' docs/contracts/README.md && ok "docs/contracts/README.md points at the pipeline doc" || fail "docs/contracts/README.md not updated"

# 3. hygiene
if git ls-files | grep -E '(__pycache__|\.pyc$)' >/dev/null; then fail "bytecode is tracked"; else ok "no __pycache__/.pyc tracked"; fi
[ -x docs/tasks/008a-verify.sh ] && ok "verify script is executable" || fail "verify script not executable"
TMP_AFTER=$(ls -d "$RUNTMP"/wom008a-* 2>/dev/null | wc -l)
[ "$TMP_AFTER" -le "$TMP_BEFORE" ] && ok "no wom008a-* temp dirs left behind by the suite" || fail "suite left $((TMP_AFTER - TMP_BEFORE)) wom008a-* temp dir(s)"
# no key material tracked
if git ls-files | grep -E '\.(key|pem)$|minisign\.key' >/dev/null; then fail "a key-like file is tracked"; else ok "no key-like file tracked"; fi
# file scope: every changed path is inside the declared scope (needs the base ref; missing base = failure, not skip)
# Task 062 (D-1): the check measures this task's OWN commit range, pinned at both ends, so it gives the same
# answer on main, on any later branch and in any fresh clone. BASE is the registry commit the branch was cut
# from (4d4a204, the merge of task 032). FINAL is the last commit on task/008a-pipeline-core before its merge
# (registry PR #7: the second parent of merge a50daac, from `git log --first-parent` then `git rev-parse a50daac^2`).
# An unreachable pin is a FAILURE naming the commit, never a skip.
BASE=4d4a204
FINAL=9ccb3ec
PINS_OK=1
for pin in "$BASE" "$FINAL"; do
  if ! git merge-base --is-ancestor "$pin" HEAD 2>/dev/null; then
    fail "pinned commit $pin is not an ancestor of HEAD: file-scope check cannot run"
    PINS_OK=0
  fi
done
if [ "$PINS_OK" = 1 ]; then
  BAD=$(git diff --name-only "$BASE" "$FINAL" | grep -v -E '^(tools/pipeline/|tools/validation/manifest\.py$|tests/pipeline/|docs/pipeline/build-pipeline\.md$|docs/validation/manifest-reader\.md$|docs/contracts/README\.md$|docs/tasks/008a-pipeline-core\.md$|docs/tasks/008a-verify\.sh$)' || true)
  [ -z "$BAD" ] && ok "every path changed in $BASE..$FINAL is within the declared file scope" || { fail "paths outside the declared scope:"; echo "$BAD"; }
fi
for f in contracts reserved-namespaces.json tools/validation/scan_assets.py tools/validation/magic.py; do
  if [ "$PINS_OK" = 1 ] && git diff --quiet "$BASE" "$FINAL" -- "$f"; then ok "untouched in $BASE..$FINAL: $f"; else fail "changed or unverifiable: $f"; fi
done

echo "SUMMARY failed=$FAILS"
exit "$FAILS"
