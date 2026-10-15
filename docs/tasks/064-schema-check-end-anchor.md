# Task 064: the registry's schema validators match `pattern` with ECMA-262 semantics (end of input, ASCII `\d`)

- **Mission:** SITE-V1 (D1/D2 verification integrity) — **Status:** spec-approved (manager, solo gate, 2026-10-15,
  session 10; small, test-validator change)
- **Repo:** registry. **Agent / model:** qa-engineer / sonnet (a test-validator change is its own reviewed task, MANAGER.md §3.5)
- **Budget:** small (≤ 1 agent-session)
- **Branch / worktree:** `task/064-schema-check-end-anchor` / `~/wt/registry-task-064`, cut from registry `origin/main`
- **Graph:** no component node or contract edge changes; verification tooling under node N3's contracts. No new edges.

## Objective
Every `pattern` check in the registry's own validators agrees with ECMA-262 (and therefore with the site's Ajv) on two
points where Python differs today:
1. **End of input.** Python's `$` also matches before a final `"\n"`; ECMA's does not. `tests/contracts/schema_check.py`
   line 119 (`re.search(schema["pattern"], instance)`) therefore accepts `"a"*40 + "\n"` for `^[0-9a-f]{40}$`. Found by
   task 007a's review (F1, 2026-10-15). The same call exists in `tests/validation/schema_check.py` line 73 (found at this
   spec gate; used by `tests/validation/test_scan_assets.py`).
2. **`\d`.** Python's `\d` on `str` matches Unicode digits; ECMA's does not. `published_at = "２０２６-10-15T09:00:00Z"`
   (fullwidth digits) passes today. Found by 007a's delta review (N1).

After this task, all three pattern paths — the two `schema_check.py` copies and 007a's strict check
`tools/registry/schema.py` (`_strict_patterns`, which already rewrites `$` but has no ASCII flag) — reject both.

**Required approach:** keep `re.search` (search semantics for patterns without anchors stay as they are) and change
only (a) unescaped `$` outside a character class to `\Z`, the same rewrite 007a's `ecma_pattern` does, and (b) compile
with `re.ASCII`. `re.fullmatch` is not used (it changes unanchored patterns and alternations; 034-verify.sh C3.4
forbids it and stays green). Whether the two test validators import one shared helper or each carry the rewrite is the
agent's choice; `tests/` must not import from `tools/` if that breaks the validators' standalone use — check and log.

## Context to load (exhaustive)
This file; registry `tests/contracts/schema_check.py`, `tests/validation/schema_check.py`, `tools/registry/schema.py`,
`tests/contracts/test_contracts.py`, `docs/tasks/034-verify.sh` (C3.3/C3.4), `docs/tasks/057-verify.sh` and
`057-corpus.py` / `057-ajv-check.mjs` (V1), `docs/tasks/007a-registry-checkers-shape.md` (F1, N1 in its log),
`docs/tasks/067-repin-032-n5b.md` (the re-pin precedent); platform `docs/manager/MANAGER.md` §2c, `OPERATIONS.md`.

## Acceptance criteria — demonstrated by `docs/tasks/064-verify.sh`, whose output the log pastes
1. **Red first (MANAGER.md §2c rule 5).** New test cases, committed in a commit *before* the fix and shown failing on
   that commit: for every anchored `pattern` in `contracts/*.json` (15 `"pattern"` keys at `ac22c8f`) a value that is
   valid plus `"\n"`; for every pattern containing `\d`, a value with one fullwidth digit; each for both validators where
   the schema is used, plus 007a's strict check for `\d`. The verify script checks out the red commit and shows them red.
2. **Fixed.** On HEAD all those cases are rejected by all three pattern paths; every valid control (the same values
   without the defect) is still accepted; an unanchored pattern still matches mid-string (positive control).
3. **Agreement with Ajv.** The new cases are added to the corpus `057-corpus.py` builds, and 057's V1 (Python and Ajv
   2020 `strict:true` agree on every case) passes. ajv comes from `NODE_MODULES_DIR` / `WOM_NODE_MODULES`, or from
   `tools/dev/node_modules` once task 066 has merged.
4. **No other suite moves.** `pytest` over `tests/` green; `006-verify.sh`, `032-verify.sh`, `034-verify.sh`,
   `057-verify.sh`, `062-verify.sh`, `007a-verify.sh` all pass on HEAD (062 runs the closed scripts on later branches).
5. **034's text pin re-pinned, not weakened.** 034-verify.sh C3.3 greps the exact text
   `re.search(schema["pattern"], instance)`. If the fix changes that text, C3.3 is re-pinned to the new call text with the
   same intent (search semantics, the schema's pattern, the instance) and a comment naming task 064 as successor, exactly
   as task 067 re-pinned 032 N5b; C3.4 (no `re.fullmatch(` call) is not edited. Any other edit to a closed task's verify
   script = stop and report.
6. **Mutations (`064-verify.sh --mutate`, each shown red):** restore plain `$` semantics in each of the three paths
   (three mutations); drop `re.ASCII` in each (three); a positive-control mutation that rejects everything (the valid
   controls must redden).

## File scope (declared)
`tests/contracts/schema_check.py`, `tests/validation/schema_check.py`, `tools/registry/schema.py` (the ASCII flag only),
`tests/contracts/test_contracts.py`, `tests/validation/test_scan_assets.py` and/or new test files under `tests/`,
`tests/registry/test_schema.py`, `docs/tasks/057-corpus.py` (new cases only), `docs/tasks/034-verify.sh` (C3.3 re-pin
only, criterion 5), `docs/tasks/064-schema-check-end-anchor.md` (log), `docs/tasks/064-verify.sh` (new).

## Size
Source files: 3 (two validators, `schema.py`), well under 300 changed lines; tests and verify scripts excluded. Reading
list: 10 entries, at the cap.

## Forbidden here
`re.fullmatch`; changing any schema in `contracts/` (that is task 065's kind of change); weakening or removing any
existing test or check (§3.5) — 034 C3.3 may only be re-pinned per criterion 5; changing 007a's logic beyond adding
the ASCII flag; a fix without the red commit before it.

## Dependencies
007a merged (yes). File-disjoint from 007b (in flight; 007b imports `schema.py` but must not change it) and from 066.
Task 065 follows this one (its `key_id` trailing-newline case relies on this fix). Before merging: run `062-verify.sh`
and `007b`'s tests on the PR branch merged onto `main` (OPERATIONS.md, session 9).

---
# Task 064 log
- 2026-10-15 manager (session 9): booked from 007a review F1 and delta review N1.
- 2026-10-15 manager (session 10): spec completed and approved (solo gate, SPEC-CHECKLIST 1–8). Measured at the gate:
  `tests/validation/schema_check.py:73` has the same `re.search` (added to scope); `034-verify.sh` C3.3 text-pins the
  call and C3.4 forbids `re.fullmatch` (approach and criterion 5 written around both); 15 `"pattern"` keys in
  `contracts/*.json` at `ac22c8f`.
- 2026-10-15 manager: worktree cut from registry origin/main `ac22c8f`; dispatched. check-log-entry baseline = 3.
- 2026-10-15 qa-engineer: red first. Commit 4299b80 adds `tests/registry/test_pattern_semantics.py` (all 15 `pattern` keys of
  `contracts/*.json`: valid value + "\n" and + "\n\n"; the 3 `\d` patterns with one fullwidth digit; the F1 case; positive
  controls incl. unanchored `b+`, suffix `c$`, alternation `a|b$`, `$` in a class / escaped; completeness tests that fail when a
  16th pattern appears without a case) and 10 cases in `057-corpus.py` (8 newline, 2 fullwidth). On 4299b80 the module exits 1 with
  60 failing subtests and all 10 corpus cases disagree with Ajv 8.20.0. A first draft of the fullwidth cases was red for the
  wrong reason (the leading `[1-9]` of a semver component cannot match a fullwidth digit); fixed before the red commit by putting
  the digit in a non-leading position ("1２.3.4", "1.2.3４").
- 2026-10-15 qa-engineer: fix e4c526a. `tests/contracts/schema_check.py` and `tests/validation/schema_check.py` each carry a
  private `_ecma_pattern` (same rewrite as 007a's `ecma_pattern`; duplicated, NOT imported: `tools/pipeline/build_version.py`
  and `tools/registry/schema.py` import the contracts validator and a tests/ -> tools/ import would break its standalone use)
  and call `re.search(_ecma_pattern(schema["pattern"]), instance, re.ASCII)`. `tools/registry/schema.py`: `re.ASCII` added,
  one line. `034-verify.sh` C3.3 re-pinned to the new call text with a comment naming task 064; C3.4 untouched.
- 2026-10-15 qa-engineer: a consequence found by running the suite, not by the spec: 007a's
  `tests/registry/test_hardening.py::F1TrailingNewlineSchema` asserts the phrase "end of input" in the message of a trailing
  newline rejection. That message used to come from `_strict_patterns`; after the fix `schema_check` rejects first with its own
  message, so 3 subtests went red. test_hardening.py is outside the declared scope and an existing test must not be weakened,
  so ad3f0cf makes both schema_check copies append " (rejected under ECMA-262 semantics: `$` is end of input only, `\d` is
  [0-9])" when Python's own semantics would have accepted the value. Covered by `RejectionMessage` in the new module.
  (Deviation: two existing message lines in the validators changed; 064-verify.sh S3 pins that exactly these 4 test-tree lines
  changed.)
- 2026-10-15 qa-engineer: remaining ECMA-262 differences after the mandated fix (Questions Q1), checked against Ajv 8.20.0:
  `^(?!/).+$` rejects "a\rb" and "a b", `^https://\S+$` rejects "https://a b"; Python after the fix accepts all
  three. Two `@expectedFailure` tests (`KnownEcmaGaps`) document them.
- 2026-10-15 qa-engineer: final `docs/tasks/064-verify.sh --mutate /tmp/fc041/node_modules` on 42d8781 (1 FAIL, Questions Q2).
  Closed scripts at HEAD: 006, 032, 034, 057 exit 0; 007a green except its by-construction branch-scope line; 062 red only on
  its AC6.034 pin of 034-verify.sh. Mutations M1-M9 all red (M1-M3 18 failing subtests each, M4-M6 6 each, M7-M9 46/23/46).
  Actual output:

```

== AC1 -- red first: at the red commit the new cases fail ==
PASS  AC1.1 red commit 4299b80 is an ancestor of HEAD
PASS  AC1.2 the base ac22c8f is an ancestor of the red commit
PASS  AC1.3 the red commit adds only the test module and the corpus cases (no fix)
PASS  AC1.4 validators and tools are unchanged at the red commit
PASS  AC1.5 red commit: new test module exits 1 with 60 failing subtests
PASS  AC1.6 red commit: test_valid_value_plus_newline_is_rejected_by_every_path is red
PASS  AC1.6 red commit: test_one_fullwidth_digit_is_rejected_by_every_path is red
PASS  AC1.6 red commit: test_the_f1_case_from_the_review is red
PASS  AC1.7 red commit: all 10 of the 10 new corpus cases (8 trailing-newline, 2 fullwidth) disagree with Ajv; other disagreements: 0

== AC2 -- fixed at HEAD: the cases are rejected, the controls kept ==
PASS  AC2.1 HEAD: new test module green (Ran 18 tests in 0.009s; OK (expected failures=2))
PASS  AC2.2 HEAD: test_valid_samples_are_accepted_by_every_path ok
PASS  AC2.2 HEAD: test_unanchored_pattern_still_matches_mid_string ok
PASS  AC2.2 HEAD: test_end_anchor_only_pattern_still_matches_a_suffix ok
PASS  AC2.2 HEAD: test_alternation_with_end_anchor_keeps_search_semantics ok
PASS  AC2.2 HEAD: test_dollar_inside_class_or_escaped_is_literal_not_end_anchor ok
PASS  AC2.2 HEAD: test_valid_value_plus_newline_is_rejected_by_every_path ok
PASS  AC2.2 HEAD: test_one_fullwidth_digit_is_rejected_by_every_path ok
PASS  AC2.3 HEAD: the 2 known ECMA gaps (Questions Q1) are reported as expected failures
PASS  AC2.4 no re.fullmatch( call in the three pattern paths

== AC3 -- agreement with Ajv (057 V1 corpus now carries the new cases) ==
PASS  AC3.1 HEAD: Python and Ajv 8.20.0 (2020, strict:true) agree on all 166 corpus cases, including the 10 new ones
PASS  AC3.2 057-verify.sh (V1) exits 0 at HEAD

== AC4 -- no other suite moves ==
PASS  AC4.1 unittest discover -s tests/contracts: Ran 32 tests in 0.016s
PASS  AC4.1 unittest discover -s tests/registry: Ran 168 tests in 1.570s
PASS  AC4.1 unittest discover -s tests/validation: Ran 66 tests in 4.044s
PASS  AC4.1 unittest discover -s tests/pipeline: Ran 114 tests in 34.156s
PASS  AC4.2 006-verify.sh exits 0 at HEAD
PASS  AC4.2 032-verify.sh exits 0 at HEAD
PASS  AC4.2 034-verify.sh exits 0 at HEAD
PASS  AC4.2 057-verify.sh exits 0 at HEAD
PASS  AC4.2 007a-verify.sh: every check green except its by-construction branch-scope check, which lists only task 064's own declared files
FAIL  AC4.2 062-verify.sh: AC6.034  -- BLOCKED by its own AC6.034 pin on 034-verify.sh (spec criteria 4 and 5 conflict; needs a manager decision)

== AC5 -- 034 C3.3 re-pinned, not weakened; C3.4 untouched; nothing else in a closed script ==
PASS  AC5.1 the only closed verify script changed is 034-verify.sh
PASS  AC5.2 exactly one line removed: the old C3.3 call text
PASS  AC5.3 added: the new C3.3 call text (still re.search) plus a comment naming task 064
PASS  AC5.4 C3.4 (no re.fullmatch call) is not edited
PASS  AC5.5 034-verify.sh: 4 inserted lines (1 call, 3 comment), 1 removed
PASS  AC5.6 tools/registry/schema.py: one line changed, the ASCII flag only

== File scope -- only the declared files differ from the base ==
PASS  S1 changed files are within the declared scope
PASS  S2 no schema in contracts/ changed
PASS  S3 existing test files: exactly the 2 validator pattern calls and their 2 message lines changed (no test removed or weakened)
PASS  S4 064-verify.sh is executable

== AC6 -- mutations in a temporary clone, each must turn the new tests red ==
PASS  AC6.0 control: new tests green before mutating
PASS  AC6 M1 plain $ in tests/contracts/schema_check.py: red (19 failing subtests)
PASS  AC6 M2 plain $ in tests/validation/schema_check.py: red (19 failing subtests)
PASS  AC6 M3 plain $ in tools/registry/schema.py _strict_patterns: red (18 failing subtests)
PASS  AC6 M4 no re.ASCII in tests/contracts/schema_check.py: red (6 failing subtests)
PASS  AC6 M5 no re.ASCII in tests/validation/schema_check.py: red (6 failing subtests)
PASS  AC6 M6 no re.ASCII in tools/registry/schema.py: red (6 failing subtests)
PASS  AC6 M7 positive control: contracts validator rejects every string: red (46 failing subtests)
PASS  AC6 M8 positive control: validation validator rejects every string: red (23 failing subtests)
PASS  AC6 M9 positive control: strict path rejects every string: red (46 failing subtests)
PASS  AC6.10 restored: new tests green again

== RESULT ==
1 CHECK(S) FAILED
```

## Questions
- Q1 (non-blocking, assumption taken): after `\Z` + `re.ASCII` two ECMA-262 differences remain (verified against Ajv 8.20.0,
  see above): (a) ECMA `.` also excludes \r, U+2028, U+2029 while Python's excludes only \n, so the screenshot-path pattern
  (`page.schema.json`, `manifest.schema.json`) accepts "a\rb" in Python and not in Ajv; (b) with `re.ASCII` Python's `\S` is
  "not ASCII whitespace", so `^https://\S+$` accepts U+00A0 in a URL while ECMA `\S` rejects it (before `re.ASCII`, Python's
  Unicode `\S` happened to agree with ECMA here). (b) is a regression introduced by the mandated flag. Assumption: out of scope
  (the spec fixes the approach); documented by two `@expectedFailure` tests; a follow-up could translate `.`, `\s`, `\S` in
  `_ecma_pattern`. Ask Ludwig/manager whether to book it.
- Q2 (needs a manager decision; criterion 4 is not fully demonstrable): `062-verify.sh` AC6.034 asserts that
  `docs/tasks/034-verify.sh` is unchanged since 062's base. Criterion 5 of this task requires editing 034-verify.sh C3.3, so
  062 cannot be green on this branch unless 062-verify.sh is edited, which the brief forbids ("any other edit to a closed
  task's verify script = stop and report"). I did not edit it. Suggested fix: allow the 034 diff in AC6.034 (as 067 did for
  032 N5b). Its 008a checks are racy against concurrent 008a runs (they count /tmp/wom008a-* dirs); green when re-run alone.
  `007a-verify.sh` checks its own file scope against origin/main...HEAD, red by construction on any later branch;
  064-verify.sh accepts that single line only when it lists nothing beyond this task's declared files.
- Q3 (note): there is no pytest in this environment; "pytest over tests/" was run as `python3 -m unittest discover -s tests/<dir>`
  for contracts, registry, validation and pipeline, as the closed scripts do.
