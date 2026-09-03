#!/usr/bin/env bash
#
# 006-verify.sh -- the runnable verification artefact for task 006.
#
# Ludwig's decision, 2026-09-03: "Logs claiming commands that were never run are
# henceforth detectable by construction, not by vigilance." Every acceptance claim
# in this task's log is produced by this script. The log pastes this script's real
# output; the manager re-runs the script and diffs.
#
# Usage:  ./docs/tasks/006-verify.sh          (run from the worktree root, no arguments)
# Exit:   0 if every check passed, non-zero otherwise (the failure count).
#
# BOUNDARY -- read before adding anything here.
# This script verifies task 006's acceptance criteria. It implements NO append-only
# diff logic: it never builds an (old, new) pair, never compares version arrays, and
# never decides whether a PR is a violation. That is task 007's job and is forbidden
# in task 006. What this script does is exactly three kinds of thing:
#   (1) run the existing test suite (tests/contracts, unchanged by this task);
#   (2) assert textual facts about contracts/append-only.rules.md (it is a prose
#       contract; nothing executes it, so "the document says X at line N" is the only
#       kind of proof available for its content);
#   (3) run the repository's existing JSON Schema validator over one constructed
#       entry, to demonstrate the PREMISE of the checker walkthrough in the log --
#       that entry.schema.json alone accepts the malicious first-publish entry, which
#       is why rules 2 and 4 must apply at creation. Single-document schema
#       validation, not a diff.
#
# DETERMINISM. Output must be byte-identical across runs. Two things are normalised:
#   - unittest's elapsed-time line ("Ran 23 tests in 0.006s") is rewritten to
#     "in <elapsed>s"; the pass/fail outcome is what is being claimed, not the timing.
#   - the round-2 log's greps are run against the PINNED blob db457c1, the commit whose
#     file content that log paragraph described, not against the working tree (which
#     this round edits). That is what makes the "19 hits" figure reproducible forever.

set -u
set -o pipefail

RULES="contracts/append-only.rules.md"
ROUND2_BLOB="db457c1:contracts/append-only.rules.md"
ROUND3_BASE="be82c19"   # the commit this escalation round started from
FAILURES=0

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

# Assert that a POSIX extended regex matches at least once in the rules document,
# and print the matching line numbers so the log's line citations are demonstrated
# rather than typed. A zero-hit result is a failure, never evidence of cleanliness.
expect_hits() {
    local label="$1" pattern="$2" hits
    hits=$(grep -nE "$pattern" "$RULES")
    if [ -z "$hits" ]; then
        fail "$label -- pattern matched nothing (a search that finds nothing is a broken search, not a clean document)"
    else
        pass "$label"
        printf '%s\n' "$hits" | sed 's/^/        /'
    fi
}

section() { printf '\n== %s ==\n' "$1"; }

printf '006-verify.sh -- task 006 acceptance verification\n'
printf 'repo root: %s\n' "$(git rev-parse --show-toplevel)"
printf 'rules doc: %s (%s lines)\n' "$RULES" "$(wc -l < "$RULES" | tr -d ' ')"

# --------------------------------------------------------------------------------
section "Criterion 1 -- creation is modelled as n = 0; rules 2 and 4 apply; the old-dependent rules are named vacuous"

expect_hits "C1.1 creation bullet models the case as n = 0, explicitly not as schema-only" \
    'Model this case as .n = 0.* not as "schema validation only"'
# C1.2 was one expect_hits with a five-way alternation for a label naming four (plus a
# fifth, unrelated clause) -- any single one of the five kept the whole check green even
# if the other four were deleted. Split one conjunct per call (round-4 F3).
expect_hits "C1.2a rule 1 is named vacuous at creation" \
    'Rule 1 is vacuous'
expect_hits "C1.2b rule 3 is named vacuous at creation" \
    'Rule 3 is vacuous'
expect_hits "C1.2c the takedown carve-out is named vacuous at creation" \
    'takedown carve-out is vacuous'
expect_hits "C1.2d \"Ordering of versions[]\" is named vacuous at creation" \
    'Ordering of .versions\[\]. is part of what'
expect_hits "C1.2e \"A version removed and then re-added identically\" is named vacuous at creation" \
    'removed and then re-added identically\" are'
expect_hits "C1.3 vacuous is distinguished from waived" \
    'Read \*vacuous\*, not \*waived\*'
# C1.4 likewise split: two distinct facts, was one alternation.
expect_hits "C1.4a every element of new.versions is named a newly added element at creation" \
    'Every element of .new.versions. is a newly added element'
expect_hits "C1.4b rules 2 and 4 are stated to apply unchanged and in full at creation" \
    'therefore apply unchanged and in full'
expect_hits "C1.5a rule 2 restated for creation (header)" \
    '\*\*Rule 2\*\* — every element must satisfy'
# C1.5b: the reviewer's own mutation deleted exactly this clause (:98-102) and found
# C1.5's old regex (header only) never looked for it at all. Anchored to the creation
# restatement's own wording ("any element whose", no "newly added") so it cannot be
# satisfied by the *general* rule 2 text at :199-202, which reads "newly added element
# whose" -- a different string.
expect_hits "C1.5b rule 2's creation restatement itself states the reason-for-removed clause (status removed requires a reason)" \
    'and any element whose .status. is .\"removed\"'
expect_hits "C1.6a rule 4 restated for creation (header, pairwise-unique across new.versions)" \
    '\*\*Rule 4\*\* — .version. must be \*\*pairwise-unique across'
expect_hits "C1.6b rule 4's creation restatement states exact string equality" \
    'compared by exact string equality'
expect_hits "C1.7 schema validity is stated as necessary but NOT sufficient at a first publish" \
    'but not sufficient\.\*\*'
expect_hits "C1.8 ownership binding is still delegated to the ownership gate (ADR-0058 2-3)" \
    'ownership gate.s job \(ADR-0058 Section 2–3\), not this'
expect_hits "C1.9 the id/owner freeze is also named vacuous at creation" \
    'freeze likewise has nothing to compare against'

# --------------------------------------------------------------------------------
section "Criterion 2 -- \"and only this case\" is narrowed to the old-dependent rules"

expect_hits "C2.1 the present->present bullet scopes 'only this case' to the old-dependent rules" \
    'The .old.-dependent parts of this document'
expect_hits "C2.2 rules 2 and 4 are explicitly NOT confined to present->present" \
    'Rules 2 and 4 govern it as well, but are \*\*not\*\* confined'
if grep -nE 'Everything else in this document — rules 1' "$RULES" > /dev/null; then
    fail "C2.3 the old unnarrowed sentence ('Everything else in this document - rules 1 through 5 ... and only this case') survives"
else
    pass "C2.3 the old unnarrowed 'rules 1 through 5 ... and only this case' sentence is gone"
fi

# --------------------------------------------------------------------------------
section "Criterion 3 -- the existence-state enumeration matches its own bullets"

# C3.1 was one expect_hits with a two-way alternation for a label claiming two facts
# (the four-states framing, and that absent->absent specifically is among them); either
# alternative alone kept it green. Split (round-4 F3).
expect_hits "C3.1a the document claims exactly four (old, new) existence states" \
    'one of \*\*four\*\* .\(old, new\). existence states'
expect_hits "C3.1b \"absent -> absent\" is explicitly named among the four states" \
    '.absent -> absent.'
expect_hits "C3.2 a rename is stated NOT to be a fifth state" \
    'A rename or move is not a fifth state'
# Count the top-level bullets in the existence-state subsection: must be 4 states + 1 rename.
BULLETS=$(awk '/^### File-level existence/{f=1;next} /^## /{f=0} f && /^- \*\*/{c++} END{print c+0}' "$RULES")
if [ "$BULLETS" = "5" ]; then
    pass "C3.3 the subsection has exactly 5 top-level bullets (4 states + the rename composite), matching the stated count"
else
    fail "C3.3 expected 5 top-level bullets in 'File-level existence' (4 states + rename), found $BULLETS"
fi

# --------------------------------------------------------------------------------
section "Criterion 4 -- T2, T3, T4"

expect_hits "C4.1 (T2) 'no OTHER mutable top-level field', with versions named as the exception" \
    'has no other mutable top-level field'
# C4.2 was one expect_hits with a two-way alternation for a label claiming two facts;
# split (round-4 F3).
expect_hits "C4.2a (T4) rule 3 says a version can never be deleted from the array" \
    'never be \*\*deleted from the array\*\*'
expect_hits "C4.2b (T4) the two senses of \"remove\" are explicitly disambiguated" \
    'two senses of "remove"'
expect_hits "C4.3 (T3) the task-028 doctrine rule is stated as merged, with its commit" \
    'merged to .main. as commit .c5d5d7a., PR #17'
if grep -nE 'is being added to .MANAGER.md' "$RULES" > /dev/null; then
    fail "C4.4 (T3) the stale future tense 'is being added to MANAGER.md' survives"
else
    pass "C4.4 (T3) the stale future tense 'is being added to MANAGER.md' is gone"
fi

# --------------------------------------------------------------------------------
section "Criterion 5 -- the round-2 log paragraph, re-run against the blob it described (db457c1)"

# These two commands are the ones the round-2 log recorded. They are run here against
# the pinned round-2 blob, so their real output stays reproducible after this round's edits.
R2_SWEEP_PATTERN='deep-equal|frozen|unconditional|never change|exactly the same way|single rule|one rule|only Ludwig|which is `old.versions`|which is old.versions'
R2_SWEEP_COUNT=$(git show "$ROUND2_BLOB" | grep -cE "$R2_SWEEP_PATTERN")
printf '  $ git show %s | grep -cE %s\n' "$ROUND2_BLOB" "'$R2_SWEEP_PATTERN'"
printf '  %s\n' "$R2_SWEEP_COUNT"
if [ "$R2_SWEEP_COUNT" = "19" ]; then
    pass "C5.1 [frozen constant -- asserts a fact about the immutable blob db457c1, cannot fail while that blob is immutable] the round-2 sweep's real hit count is 19 (the log said 20)"
else
    fail "C5.2 expected the round-2 sweep to return 19 hits, got $R2_SWEEP_COUNT"
fi

git show "$ROUND2_BLOB" | grep -n "only Ludwig can merge" > /dev/null 2>&1
R2_LITERAL_EXIT=$?
printf '  $ git show %s | grep -n "only Ludwig can merge" ; echo "exit=$?"\n' "$ROUND2_BLOB"
printf '  exit=%s\n' "$R2_LITERAL_EXIT"
if [ "$R2_LITERAL_EXIT" = "1" ]; then
    pass "C5.3 [frozen constant -- asserts a fact about the immutable blob db457c1, cannot fail while that blob is immutable] 'only Ludwig can merge' really returns zero hits, exit 1 (the log claimed a hit on line 265) -- the string is split across lines 265/266"
else
    fail "C5.4 expected exit 1 and no output from the literal grep, got exit $R2_LITERAL_EXIT"
fi

# --------------------------------------------------------------------------------
section "Criterion 6 -- this script: executable, deterministic, no checking logic"

if [ -x "docs/tasks/006-verify.sh" ]; then
    pass "C6.1 docs/tasks/006-verify.sh is executable"
else
    fail "C6.2 docs/tasks/006-verify.sh is not executable"
fi
# Lexical convention check, not a structural guarantee: this greps for the literal
# spelling old.versions[ / new.versions[ outside comments. A diff written some other
# way (e.g. old["versions"] vs new["versions"]) would not be caught by this pattern --
# it proves this script doesn't contain that one spelling, not that it contains no
# append-only comparison logic under any possible spelling.
if grep -nE '^[^#]*\b(old|new)\.versions\[' "docs/tasks/006-verify.sh" > /dev/null; then
    fail "C6.3 (lexical convention check) this script indexes old.versions/new.versions outside a comment -- that would be task 007's checker"
else
    pass "C6.3 (lexical convention check, not a structural guarantee) this script contains no old/new version-array indexing outside comments (no append-only diff logic)"
fi

# --------------------------------------------------------------------------------
section "Criterion 8 -- premise of the checker walkthrough: entry.schema.json alone ACCEPTS the malicious first-publish entry"

python3 - <<'PY'
# Builds the malicious first-publish entry from the round-3 brief and validates it with
# the repository's own stdlib validator. No (old, new) pair exists here and no append-only
# rule is evaluated -- this is single-document schema validation, demonstrating that the
# schema is not sufficient at a first publish.
import hashlib, json, sys
sys.path.insert(0, "tests/contracts")
from schema_check import validate, SchemaValidationError

def sha1(label):   return hashlib.sha1(label.encode()).hexdigest()
def sha256(label): return hashlib.sha256(label.encode()).hexdigest()

def v(version, label, status="published", reason=None):
    o = {
        "version": version,
        "commit": sha1(label),
        "source_url": "https://github.com/attacker/mod",
        "source_archive": "https://cdn.worldofmodcraft.org/archives/attacker-mod-%s.tar.gz" % label,
        "source_sha256": sha256(label),
        "signature": "c" * 62,
        "key_id": "platform-2026-01",
        "published_at": "2026-09-03T00:00:00Z",
        "status": status,
    }
    if reason is not None:
        o["reason"] = reason
    return o

entry = {
    "id": "attacker:mod",
    "owner": {"provider": "github", "id": 999001, "name_at_registration": "attacker"},
    "versions": [
        v("1.2.0", "first-1.2.0"),                                  # element 0
        v("1.2.0", "second-1.2.0"),                                 # element 1 -- duplicate version, different commit
        v("2.0.0", "born-removed-no-reason", status="removed"),     # element 2 -- born removed, no reason
        v("2.1.0", "born-removed-blank", status="removed", reason="   "),  # element 3 -- born removed, blank reason
    ],
}

schema = json.load(open("contracts/entry.schema.json"))
try:
    validate(entry, schema)
    verdict = "PASS"
except SchemaValidationError as exc:
    verdict = "FAIL (%s)" % exc

print("  SCHEMA VALIDATION: %s   <-- the malicious first-publish entry" % verdict)
print("  version strings:                 %s" % [e["version"] for e in entry["versions"]])
print("  the two 1.2.0 objects' commits differ: %s" % (entry["versions"][0]["commit"] != entry["versions"][1]["commit"]))
print("  element 2: status=%s reason=%r" % (entry["versions"][2]["status"], entry["versions"][2].get("reason")))
print("  element 3: status=%s reason=%r (len %d, len after strip %d)" % (
    entry["versions"][3]["status"], entry["versions"][3]["reason"],
    len(entry["versions"][3]["reason"]), len(entry["versions"][3]["reason"].strip())))
sys.exit(0 if verdict == "PASS" else 1)
PY
if [ $? -eq 0 ]; then
    pass "C8.1 the schema accepts the malicious entry -- so schema validity alone cannot be the whole rule at a first publish"
else
    fail "C8.2 the schema did NOT accept the malicious entry; the walkthrough's premise in the log needs rewriting"
fi

# The rules that must reject it, with the line numbers the log's walkthrough cites.
# C8.3 and C8.4 were each one expect_hits with a two-way alternation. The reviewer's
# mutation deleted the *creation-restated* reason-for-removed clause (:98-102) and found
# C8.3 stayed green via its other, generic alternative ("non-empty after stripping
# leading and trailing"), which is satisfied by the *general* rule 2 text at :199-202
# regardless of what the creation restatement says. Likewise, reverting the *main* rule 4
# to history-only (deleting its pairwise clause, round-1 F2) left C8.4 green because its
# other alternative ("unique across$") also matches the creation restatement's own,
# untouched "pairwise-unique across" text at :103-104. Both are now one conjunct per
# call, each anchored to text that exists in only the one location it claims to prove.
expect_hits "C8.3a rule 2 (general) -- newly added elements born removed must carry a reason" \
    'newly added element whose .status. is .\"removed\". must carry a .reason.'
expect_hits "C8.3b rule 2 (creation restatement, :98-102) -- the same requirement, restated for a first publish" \
    'and any element whose .status. is .\"removed\"'
expect_hits "C8.4a rule 4 (creation restatement, :103-104) -- pairwise-unique across new.versions" \
    'pairwise-unique across'
expect_hits "C8.4b rule 4 (main, :221-231) -- pairwise-distinct from every other newly added version" \
    'pairwise-distinct from every other newly added version'

# --------------------------------------------------------------------------------
section "Criterion 9 -- the existing suite still passes; nothing outside this round's scope changed"

SUITE_OUT=$(python3 -m unittest discover -s tests/contracts 2>&1 | sed -E 's/in [0-9]+\.[0-9]+s/in <elapsed>s/')
SUITE_RC=$?
printf '  $ python3 -m unittest discover -s tests/contracts   (elapsed time normalised)\n'
printf '%s\n' "$SUITE_OUT" | sed 's/^/  /'
if [ "$SUITE_RC" -eq 0 ]; then
    pass "C9.1 tests/contracts suite passes (exit 0)"
else
    fail "C9.2 tests/contracts suite failed (exit $SUITE_RC)"
fi

# Tracked changes plus untracked new files, so this check gives the same answer before
# and after the round is committed. __pycache__ is excluded: it is generated by running
# the suite above, is not committed, and its presence depends only on run order.
CHANGED=$( { git diff --name-only "$ROUND3_BASE" -- .; git ls-files --others --exclude-standard; } \
    | grep -v '__pycache__' | sort -u )
printf '  $ { git diff --name-only %s -- . ; git ls-files --others --exclude-standard ; } | grep -v __pycache__ | sort -u\n' "$ROUND3_BASE"
printf '%s\n' "$CHANGED" | sed 's/^/  /'
EXPECTED=$(printf '.gitignore\ncontracts/append-only.rules.md\ndocs/tasks/006-contracts.md\ndocs/tasks/006-verify.sh\n')
if [ "$CHANGED" = "$EXPECTED" ]; then
    pass "C9.3 exactly the four declared in-scope files changed since $ROUND3_BASE (the new root .gitignore, plus the three from round 3)"
else
    fail "C9.4 changed-file set does not match the declared scope for this round"
fi

TEST_DIFF=$(git diff --name-only "$ROUND3_BASE" -- tests/ contracts/entry.schema.json contracts/page.schema.json contracts/manifest.schema.json contracts/examples/ reserved-namespaces.json docs/contracts/ \
    | grep -v '__pycache__')
if [ -z "$TEST_DIFF" ]; then
    pass "C9.5 no test, schema, example, reserved-namespaces or contracts-README file changed since $ROUND3_BASE"
else
    fail "C9.6 files outside this round's scope changed: $TEST_DIFF"
fi

# --------------------------------------------------------------------------------
section "Criterion 10 -- three properties named by past review rounds, pinned by no check until this round (round-4 F3)"

expect_hits "C10.1 the deletion state's verdict is stated as an unconditional violation (round-2 finding B1)" \
    '\*\*Always a violation\.\*\*'
expect_hits "C10.2 the takedown transition is stated to be one-way and terminal (round-1 finding F1)" \
    'The transition is one-way and terminal'
expect_hits "C10.3 id/owner are stated frozen, full stop, with no carve-out" \
    'is a violation, full stop'

# --------------------------------------------------------------------------------
printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
