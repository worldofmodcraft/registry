#!/usr/bin/env bash
#
# 034-verify.sh -- the runnable verification artefact for task 034
# (docs/tasks/034-schema-traversal.md), required by MANAGER.md Section 2c:
# "Any task whose acceptance criteria are command-based ships
# docs/tasks/NNN-verify.sh, committed and executable." All seven of task
# 034's acceptance criteria are command-based; this script demonstrates
# every one of them with real, re-runnable commands, one check per
# criterion (split further wherever a single label would otherwise cover
# more than one fact -- Section 2c rule 3).
#
# Usage:  ./docs/tasks/034-verify.sh          (any working directory; the
#                                              script finds the repo root)
#
# Exit codes (docs/manager/OPERATIONS.md's "tool interfaces that are easy
# to get wrong" convention, task 002's scan_assets.py -- reading a usage
# error as a rejection has already produced one false verification on this
# project, so the three are kept structurally distinct here too):
#   0 -- every check passed ("accepted").
#   1 -- at least one check failed ("rejected"). The FAILURES count is
#        also the process exit code's magnitude source, but never 0 or 2.
#   2 -- usage error: this is not a git repository, the repo root does not
#        contain the files this script needs, or python3 is not on PATH.
#        A usage error is never counted as, or conflated with, a failed
#        check.
#
# BOUNDARY -- read before adding anything here.
# This script does not implement path-traversal enforcement. It never
# edits contracts/page.schema.json or contracts/manifest.schema.json in
# place; every mutation this script performs (Criterion 5) happens inside
# a throwaway temporary directory, created fresh and removed on exit via a
# trap, so a crash mid-run can never leave this repository's own schema
# files altered. What this script does is exactly: (1) run the existing
# test suite's relevant subsets and check their real exit codes and
# output, never their narration; (2) assert textual facts about the two
# schema files and the test file that backs the acceptance criteria;
# (3) reproduce, live, the exact regression task 034 closed -- by pulling
# the pre-fix pattern out of git history (never hand-retyped) and showing
# the current fixtures redden against it, then confirming the real
# worktree is unchanged and green.
#
# DETERMINISM. No wall-clock-dependent values are asserted; unittest's own
# elapsed-time line is left in the pasted output as-is (informational
# only, never compared).

set -u
set -o pipefail

FAILURES=0

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }

# A grep that finds nothing is a broken search, never a clean result
# (Section 2c rule 1): every use below fails loudly on a zero-hit search
# rather than treating "nothing matched" as evidence of anything.
expect_hits() {
    local label="$1" pattern="$2" file="$3" hits
    hits=$(grep -n -- "$pattern" "$file" 2>/dev/null)
    if [ -z "$hits" ]; then
        fail "$label -- pattern matched nothing in $file (a search that finds nothing is a broken search, not a clean result)"
    else
        pass "$label"
        printf '%s\n' "$hits" | sed 's/^/        /'
    fi
}

# --------------------------------------------------------------------------------
# Usage-error gate. Runs BEFORE any check below and is never itself a
# "check": a missing prerequisite here is a usage error (exit 2), not a
# failed acceptance criterion (exit 1). This is what makes the script
# portable (Section 2c rule 4) -- it locates the repo root itself instead
# of assuming the authoring worktree's absolute path.
# --------------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
    printf 'USAGE ERROR: python3 not found on PATH\n' >&2
    exit 2
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$ROOT" ]; then
    printf 'USAGE ERROR: not inside a git repository (git rev-parse --show-toplevel failed)\n' >&2
    exit 2
fi
cd "$ROOT" || { printf 'USAGE ERROR: could not cd to repo root %s\n' "$ROOT" >&2; exit 2; }

for f in contracts/page.schema.json contracts/manifest.schema.json \
         tests/contracts/test_contracts.py tests/contracts/schema_check.py; do
    if [ ! -f "$f" ]; then
        printf 'USAGE ERROR: expected file missing: %s (run this from a checkout of the registry repo)\n' "$f" >&2
        exit 2
    fi
done

printf '034-verify.sh -- task 034 acceptance verification\n'
printf 'repo root: %s\n' "$ROOT"

TEST_FILE="tests/contracts/test_contracts.py"
CHECK_FILE="tests/contracts/schema_check.py"

# --------------------------------------------------------------------------------
section "Criterion 1 -- both schemas reject path traversal in screenshots[] (split per schema, rule 3)"
# --------------------------------------------------------------------------------

OUT=$(python3 -m unittest discover -s tests/contracts -k test_traversal_paths_rejected_in_page_schema -v 2>&1)
RC=$?
printf '%s\n' "$OUT" | sed 's/^/  /'
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'test_traversal_paths_rejected_in_page_schema .*\.\.\. ok'; then
    pass "C1.1 page.schema.json rejects every TRAVERSAL_PATHS entry (test_traversal_paths_rejected_in_page_schema, exit 0)"
else
    fail "C1.2 page.schema.json did not reject all traversal paths (exit $RC, or the 'ok' line was not found)"
fi

OUT=$(python3 -m unittest discover -s tests/contracts -k test_traversal_paths_rejected_in_manifest_schema -v 2>&1)
RC=$?
printf '%s\n' "$OUT" | sed 's/^/  /'
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'test_traversal_paths_rejected_in_manifest_schema .*\.\.\. ok'; then
    pass "C1.3 manifest.schema.json rejects every TRAVERSAL_PATHS entry (test_traversal_paths_rejected_in_manifest_schema, exit 0)"
else
    fail "C1.4 manifest.schema.json did not reject all traversal paths (exit $RC, or the 'ok' line was not found)"
fi

# --------------------------------------------------------------------------------
section "Criterion 2 -- legitimate paths still validate (split per schema, rule 3)"
# --------------------------------------------------------------------------------

OUT=$(python3 -m unittest discover -s tests/contracts -k test_legitimate_paths_still_accepted_in_page_schema -v 2>&1)
RC=$?
printf '%s\n' "$OUT" | sed 's/^/  /'
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'test_legitimate_paths_still_accepted_in_page_schema .*\.\.\. ok'; then
    pass "C2.1 page.schema.json still accepts every LEGITIMATE_PATHS entry"
else
    fail "C2.2 page.schema.json rejected a legitimate path (exit $RC, or the 'ok' line was not found) -- a pattern that rejects these is a regression, not a fix"
fi

OUT=$(python3 -m unittest discover -s tests/contracts -k test_legitimate_paths_still_accepted_in_manifest_schema -v 2>&1)
RC=$?
printf '%s\n' "$OUT" | sed 's/^/  /'
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'test_legitimate_paths_still_accepted_in_manifest_schema .*\.\.\. ok'; then
    pass "C2.3 manifest.schema.json still accepts every LEGITIMATE_PATHS entry"
else
    fail "C2.4 manifest.schema.json rejected a legitimate path (exit $RC, or the 'ok' line was not found) -- a pattern that rejects these is a regression, not a fix"
fi

# --------------------------------------------------------------------------------
section "Criterion 3 -- rejection demonstrated with the repository's real validator, not by reasoning about the regex"
# --------------------------------------------------------------------------------

expect_hits "C3.1 the test file imports the repo's real hand-rolled validator (not a stub, not jsonschema)" \
    'from schema_check import SchemaValidationError, validate' "$TEST_FILE"

# Whether the third-party 'jsonschema' package happens to be pip-installed on
# whatever machine runs this script is incidental and outside this task's
# control (the sandbox this was written in has it installed globally for
# unrelated reasons) -- what actually matters, and is checked here, is that
# the CODE PATH under test never imports it. A zero-hit search across both
# files under test is the positive result.
JSONSCHEMA_IMPORTS=$(grep -n '^\s*import jsonschema\|^\s*from jsonschema' "$TEST_FILE" "$CHECK_FILE" 2>/dev/null)
if [ -z "$JSONSCHEMA_IMPORTS" ]; then
    pass "C3.2 neither $TEST_FILE nor $CHECK_FILE imports the third-party 'jsonschema' package -- the traversal tests above could only have run against this repo's own hand-rolled validator, the same one CI uses"
else
    fail "C3.2 a jsonschema import was found -- the criterion-3 validator used may not be the repo's own: $JSONSCHEMA_IMPORTS"
fi

expect_hits "C3.3 schema_check.py matches 'pattern' with re.search (not re.fullmatch) -- the anchoring detail every pattern in this repo, old and new, is written around" \
    're\.search(schema\["pattern"\], instance)' "$CHECK_FILE"
# Matches an actual call (open paren), never the docstring's plain-prose mention
# of re.fullmatch (schema_check.py's own docstring names it by contrast, on
# purpose, to explain why re.search is used instead).
if grep -q 're\.fullmatch(' "$CHECK_FILE"; then
    fail "C3.4 schema_check.py now calls re.fullmatch(...) somewhere -- this would silently change every pattern's anchoring semantics"
else
    pass "C3.4 schema_check.py contains no re.fullmatch(...) call -- re.search remains the only pattern-matching code path"
fi

# --------------------------------------------------------------------------------
section "Criterion 4 -- the required TRAVERSAL_PATHS and LEGITIMATE_PATHS fixtures are present and permanent (one check per literal, rule 3)"
# --------------------------------------------------------------------------------

expect_hits "C4.1 TRAVERSAL_PATHS contains '../etc/passwd'" '"\.\./etc/passwd"' "$TEST_FILE"
expect_hits "C4.2 TRAVERSAL_PATHS contains 'a/../../etc/passwd'" '"a/\.\./\.\./etc/passwd"' "$TEST_FILE"
expect_hits "C4.3 TRAVERSAL_PATHS contains './../x'" '"\./\.\./x"' "$TEST_FILE"
expect_hits "C4.4 TRAVERSAL_PATHS contains 'a/..'" '"a/\.\."' "$TEST_FILE"
expect_hits "C4.5 TRAVERSAL_PATHS contains the bare '..' entry" '^\s*"\.\.",\s*$' "$TEST_FILE"
expect_hits "C4.6 TRAVERSAL_PATHS contains the clamping-trap deep '../' case (spec's named trap: path.join clamps excess '..' at the filesystem root, so a fixture must assert on the schema verdict, never on a real file lookup)" \
    '"\.\./\.\./\.\./\.\./\.\./\.\./\.\./\.\./etc/passwd"' "$TEST_FILE"

expect_hits "C4.7 LEGITIMATE_PATHS contains 'assets/screenshots/shop.png'" '"assets/screenshots/shop\.png"' "$TEST_FILE"
expect_hits "C4.8 LEGITIMATE_PATHS contains 'docs/img/a.b/c.png'" '"docs/img/a\.b/c\.png"' "$TEST_FILE"
expect_hits "C4.9 LEGITIMATE_PATHS contains 'screenshots/v1.2.3.png'" '"screenshots/v1\.2\.3\.png"' "$TEST_FILE"
expect_hits "C4.10 LEGITIMATE_PATHS contains 'a..b/c.png' (two dots inside one segment, not a traversal segment)" '"a\.\.b/c\.png"' "$TEST_FILE"

# --------------------------------------------------------------------------------
section "Criterion 5 -- mutation-tested: revert the pattern to the proven-vulnerable value pulled from git history, watch the fixtures redden, then confirm the real worktree was never touched (Section 2c rules 2 and 5)"
# --------------------------------------------------------------------------------

PRE_FIX_COMMIT="bf8d9cb"   # task 006's commit: the last commit before task 034's fix (454911a)

# The vulnerable pattern is never hand-retyped here -- it is read straight out of
# the pre-fix commit, so this check reproduces the actual historical regression
# rather than a paraphrase of it.
OLD_PAGE_PATTERN=$(git show "${PRE_FIX_COMMIT}:contracts/page.schema.json" | python3 -c '
import json, sys
print(json.load(sys.stdin)["properties"]["screenshots"]["items"]["pattern"])')
OLD_MANIFEST_PATTERN=$(git show "${PRE_FIX_COMMIT}:contracts/manifest.schema.json" | python3 -c '
import json, sys
print(json.load(sys.stdin)["properties"]["screenshots"]["items"]["pattern"])')

if [ -z "$OLD_PAGE_PATTERN" ] || [ -z "$OLD_MANIFEST_PATTERN" ]; then
    fail "C5.0 could not read the pre-fix pattern from commit $PRE_FIX_COMMIT -- cannot mutation-test"
else
    printf '  pre-fix pattern (commit %s): %s\n' "$PRE_FIX_COMMIT" "$OLD_PAGE_PATTERN"

    BEFORE_PAGE_SHA=$(sha256sum contracts/page.schema.json | awk '{print $1}')
    BEFORE_MANIFEST_SHA=$(sha256sum contracts/manifest.schema.json | awk '{print $1}')

    SCRATCH=$(mktemp -d)
    cleanup() { rm -rf "$SCRATCH"; }
    trap cleanup EXIT

    cp -r contracts "$SCRATCH/contracts"
    cp -r tests "$SCRATCH/tests"

    python3 - "$SCRATCH" "$OLD_PAGE_PATTERN" "$OLD_MANIFEST_PATTERN" <<'PY'
import json, sys
root, old_page, old_manifest = sys.argv[1], sys.argv[2], sys.argv[3]
targets = {"page": old_page, "manifest": old_manifest}
for name, old_pattern in targets.items():
    path = f"{root}/contracts/{name}.schema.json"
    doc = json.load(open(path))
    doc["properties"]["screenshots"]["items"]["pattern"] = old_pattern
    json.dump(doc, open(path, "w"), indent=2)
    print(f"  mutated {path}: screenshots[].items.pattern reverted to the pre-fix value")
PY

    MUT_OUT=$(cd "$SCRATCH" && python3 -m unittest discover -s tests/contracts -k ScreenshotTraversalTests -v 2>&1)
    MUT_RC=$?
    printf '%s\n' "$MUT_OUT" | sed 's/^/    /'

    N_TRAVERSAL=$(python3 -c '
import re
src = open("tests/contracts/test_contracts.py").read()
m = re.search(r"TRAVERSAL_PATHS = \[(.*?)\n    \]", src, re.S)
print(len([l for l in m.group(1).splitlines() if l.strip().startswith("\"")]))
')

    PAGE_FAIL_COUNT=$(printf '%s' "$MUT_OUT" | grep -c '^FAIL: test_traversal_paths_rejected_in_page_schema')
    if [ "$PAGE_FAIL_COUNT" = "$N_TRAVERSAL" ]; then
        pass "C5.1 reverting to the pre-fix pattern reddens all $N_TRAVERSAL page-schema traversal subtests (found $PAGE_FAIL_COUNT FAIL blocks) -- the fixture actually exercises the fix, not vacuously true"
    else
        fail "C5.2 expected $N_TRAVERSAL page-schema traversal subtests to redden against the pre-fix pattern, found $PAGE_FAIL_COUNT"
    fi

    MANIFEST_FAIL_COUNT=$(printf '%s' "$MUT_OUT" | grep -c '^FAIL: test_traversal_paths_rejected_in_manifest_schema')
    if [ "$MANIFEST_FAIL_COUNT" = "$N_TRAVERSAL" ]; then
        pass "C5.3 reverting to the pre-fix pattern reddens all $N_TRAVERSAL manifest-schema traversal subtests (found $MANIFEST_FAIL_COUNT FAIL blocks)"
    else
        fail "C5.4 expected $N_TRAVERSAL manifest-schema traversal subtests to redden against the pre-fix pattern, found $MANIFEST_FAIL_COUNT"
    fi

    if [ "$MUT_RC" -ne 0 ]; then
        pass "C5.5 the mutated (pre-fix) run's overall exit code is non-zero ($MUT_RC) -- the suite as a whole reddens"
    else
        fail "C5.6 the mutated (pre-fix) run exited 0 -- it should have reddened and did not"
    fi

    # Positive controls (Section 2c rule 5's first consequence): the legitimate
    # paths must STILL validate even under the vulnerable pattern -- the old
    # pattern was permissive, not a blanket rejector, and a suite that passes by
    # rejecting everything is not a suite.
    if printf '%s' "$MUT_OUT" | grep -q 'test_legitimate_paths_still_accepted_in_page_schema .*\.\.\. ok' \
       && printf '%s' "$MUT_OUT" | grep -q 'test_legitimate_paths_still_accepted_in_manifest_schema .*\.\.\. ok'; then
        pass "C5.7 the positive controls (LEGITIMATE_PATHS) still pass even against the mutated pre-fix pattern -- the traversal failures above are a real, targeted regression, not blanket rejection"
    else
        fail "C5.8 a positive-control (LEGITIMATE_PATHS) test did not pass against the mutated pre-fix pattern -- the mutation broke more than the traversal handling, which invalidates C5.1-C5.6 as evidence"
    fi

    trap - EXIT
    cleanup

    AFTER_PAGE_SHA=$(sha256sum contracts/page.schema.json | awk '{print $1}')
    AFTER_MANIFEST_SHA=$(sha256sum contracts/manifest.schema.json | awk '{print $1}')
    if [ "$BEFORE_PAGE_SHA" = "$AFTER_PAGE_SHA" ] && [ "$BEFORE_MANIFEST_SHA" = "$AFTER_MANIFEST_SHA" ]; then
        pass "C5.9 the real worktree's contracts/page.schema.json and contracts/manifest.schema.json are byte-identical before and after the mutation test -- only the scratch copy was ever mutated"
    else
        fail "C5.10 the real worktree's schema files changed during the mutation test -- this must never happen"
    fi

    RESTORE_OUT=$(python3 -m unittest discover -s tests/contracts -k ScreenshotTraversalTests -v 2>&1)
    RESTORE_RC=$?
    printf '%s\n' "$RESTORE_OUT" | sed 's/^/  /'
    if [ "$RESTORE_RC" -eq 0 ]; then
        pass "C5.11 restored: the real (unmutated, fixed) worktree's ScreenshotTraversalTests are green again immediately after the mutation test"
    else
        fail "C5.12 the real worktree's ScreenshotTraversalTests did not pass after the mutation test (exit $RESTORE_RC)"
    fi
fi

# --------------------------------------------------------------------------------
section "Criterion 6 -- contracts/examples/ still validates, counts shown"
# --------------------------------------------------------------------------------

check_example_count() {
    local label="$1" schema="$2" kind="$3" dir count
    dir="contracts/examples/$schema/$kind"
    count=$(ls "$dir"/*.json 2>/dev/null | wc -l | tr -d ' ')
    printf '  $ ls %s/*.json | wc -l  ->  %s\n' "$dir" "$count"
    if [ "$count" -gt 0 ]; then
        pass "$label $schema/$kind has $count example file(s)"
    else
        fail "$label $schema/$kind has zero example files -- an examples directory that finds nothing is not proof of anything"
    fi
}

check_example_count "C6.1" page valid
check_example_count "C6.2" page invalid
check_example_count "C6.3" manifest valid
check_example_count "C6.4" manifest invalid

OUT=$(python3 -m unittest discover -s tests/contracts -k PageExampleTests -v 2>&1)
RC=$?
printf '%s\n' "$OUT" | sed 's/^/  /'
if [ "$RC" -eq 0 ]; then
    pass "C6.5 PageExampleTests passes -- every page/valid example validates, every page/invalid example is rejected"
else
    fail "C6.6 PageExampleTests failed (exit $RC)"
fi

OUT=$(python3 -m unittest discover -s tests/contracts -k ManifestExampleTests -v 2>&1)
RC=$?
printf '%s\n' "$OUT" | sed 's/^/  /'
if [ "$RC" -eq 0 ]; then
    pass "C6.7 ManifestExampleTests passes -- every manifest/valid example validates, every manifest/invalid example is rejected"
else
    fail "C6.8 ManifestExampleTests failed (exit $RC)"
fi

# --------------------------------------------------------------------------------
section "Criterion 7 -- field descriptions state the traversal rule (one check per file, and per fact within each file, rule 3)"
# --------------------------------------------------------------------------------

expect_hits "C7.1 page.schema.json's screenshots[].items description mentions a traversal segment" \
    'traversal segment' contracts/page.schema.json
expect_hits "C7.2 page.schema.json's description explicitly calls out a non-traversal dots-in-segment example (a..b or v1.2.3)" \
    'a\.\.b\|v1\.2\.3' contracts/page.schema.json
expect_hits "C7.3 manifest.schema.json's screenshots[].items description mentions a traversal segment" \
    'traversal segment' contracts/manifest.schema.json
expect_hits "C7.4 manifest.schema.json's description explicitly calls out a non-traversal dots-in-segment example (a..b)" \
    'a\.\.b' contracts/manifest.schema.json

# --------------------------------------------------------------------------------
section "Informational (not one of the seven numbered criteria) -- ADR-0030 conformance re-check, Finding 2 of the fix-round brief"
# --------------------------------------------------------------------------------
# ADR-0030 governs the manifest's `screenshots` field. This task's diff must only
# tighten the per-item pattern and its description -- never touch the field's type,
# required-ness, or top-level meaning. Checked structurally here so a future PR
# that widens this task's change cannot silently drift from that boundary.

MANIFEST_REQUIRED_HAS_SCREENSHOTS=$(python3 -c '
import json
d = json.load(open("contracts/manifest.schema.json"))
print("screenshots" in d.get("required", []))')
if [ "$MANIFEST_REQUIRED_HAS_SCREENSHOTS" = "True" ]; then
    pass "ADR-0030.1 manifest.schema.json still lists 'screenshots' as required (field existence untouched by this task)"
else
    fail "ADR-0030.2 manifest.schema.json no longer requires 'screenshots' -- this task must not change field existence, only the item pattern"
fi

if python3 -c '
import json, sys
d = json.load(open("contracts/manifest.schema.json"))
outer = sorted(k for k in d["properties"]["screenshots"].keys() if k != "items")
sys.exit(0 if outer == ["description", "type"] else 1)
'; then
    pass "ADR-0030.3 manifest.schema.json's screenshots property keeps exactly its original outer keys (type, description) -- only items.pattern/items.description changed"
else
    fail "ADR-0030.4 manifest.schema.json's screenshots property gained or lost an outer key (expected exactly [description, type])"
fi

# --------------------------------------------------------------------------------
printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit 1
