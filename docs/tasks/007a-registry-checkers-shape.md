# Task 007a: Registry checkers, shape half — PR classification, schema validation, append-only (T1/T2/T3)

- **Mission:** SITE-V1, D1 — **Status:** review (implementer, 2026-10-15; was spec-approved by the manager
  after independent spec review rounds 1–3: FAIL, FAIL, PASS)
- **Umbrella:** `docs/tasks/007-registry-ci-checkers.md` — read it in full, **including the
  "Revision 2026-10-15" section, which overrides its older text**. This file states only what is
  specific to 007a.
- **Agent / model:** implementer / sonnet
- **Budget:** medium (≤ 3 agent-sessions)
- **Branch / worktree:** `task/007a-registry-checkers-shape` / `~/wt/registry-task-007a`, cut from
  registry `origin/main` (`e009ef0` or later; 062 may have landed first, which is fine)
- **Graph:** node N3; edges E2, E3, E4. No new edges.

## Objective
Three offline checkers and one shared module exist in the registry under `tools/registry/`, with tests
under `tests/registry/` and `docs/tasks/007a-verify.sh`:
1. `report` — the shared verdict shape and the three exit codes (accepted / rejected / usage-or-internal
   error), used by all checkers including 007b's.
2. `classify` — changed-path set → exactly one PR class (entry-touching, `page.json`-only,
   reserved-namespace, other/mixed), failing closed on anything unrecognised (umbrella criterion 8).
3. `schema` — every changed JSON file validated against the schema its path implies, using
   `tests/contracts/schema_check.py` (umbrella "Forbidden": no re-implementation).
4. `append_only` — field-level `old`/`new` `entry.json` comparison implementing
   `contracts/append-only.rules.md` as merged by task 057: file-level existence states, rules 1–5,
   the four-state shape table, born-`pending` only, T1/T2/T3 and their coexistence, ordering,
   remove-and-re-add, malformed edits. Its verdict **classifies each changed element** (unchanged /
   appended / T1 / T2 / T3 / violation with the **list** of rule ids it breaks, e.g. `["rule 2", "rule 4"]`),
   because 007b's R11 decision consumes that classification (007b's fail-closed key deliberately does not). It does **not** decide authority: a T1 or T3 is shape-legal here. **Its verdict
   therefore carries `authority_required`**, the list of transitions present that need an authority
   decision (`["T1"]`, `["T3"]`, `["T2"]`, or combinations), and the CLI documents that an `accepted`
   exit from `append_only` alone is never a merge signal when that list is non-empty (task 039 must
   run 007b). Tested: every T1/T2/T3 accept fixture yields the exact list.

**Ownership of path-form rejection.** `classify` owns `ownership.md` R1's path-form rule: any path under
`mods/` not of the form R1 states is a rejection here, with a message citing R1. The reserved-namespace
class reads the reserved list from the **merge-base** revision of `reserved-namespaces.json`
(`ownership.md` I4), passed in as data by the caller; a PR that edits that file does not change its own
classification (tested).

## Context to load (exhaustive; INDEX.json lookup as in the umbrella)
- Umbrella 007 (all), ADR-0121, and the ADRs the umbrella lists for E2/E3/E4 (0039, 0041, 0042, 0058 §2,
  0059 §2–3, 0120 boundary only).
- Registry `origin/main`: `contracts/append-only.rules.md` (all), `contracts/entry.schema.json`,
  `contracts/page.schema.json`, `contracts/examples/**`, `tests/contracts/schema_check.py`,
  `docs/contracts/README.md`, `docs/tasks/057-transition-fixtures.json`, `docs/tasks/057-oracle.py`
  (reference reading only), `docs/tasks/006-verify.sh` lines 210–264 (the `attacker:mod` construction).
- Doctrine: MANAGER.md §2c, §3.3, §3.7, guardrail 6c; REVIEW-CHECKLIST.md; OPERATIONS.md ("Tool interfaces
  that are easy to get wrong"; Python 3 stdlib only, `python3 -m unittest`).

## Measured facts (manager, 2026-10-15, registry `e009ef0`)
Probe: the four `attacker:mod` elements (0: `1.2.0` published; 1: `1.2.0` published, other commit;
2: `2.0.0` removed, no `reason`; 3: `2.1.0` removed, `reason "   "`), each with the five pipeline
fields, validated with `schema_check.validate(entry, entry.schema.json)`:
```
0 schema ACCEPTS
1 schema ACCEPTS
2 schema REJECTS: $.versions[0]: matched none of the oneOf branches: branch 0: unexpected properties: ['key_id', 'published_at', 'signature', 'source_archive', 'source_sha256'];
3 schema ACCEPTS
whole entry: schema REJECTS: $.versions[2]: matched none of the oneOf branches: ...
```
The test suite must re-establish these facts itself (assert them), not rely on this paste.

## Size (SPEC-CHECKLIST 5b)
Source files: 4 (`report`, `classify`, `schema`, `append_only`) plus at most one CLI entry module = 5, at the
cap. Changed source lines: expected 400–600, over the 300 cap. Reason splitting further is worse: the
append-only checker is one contract with cross-referencing rules (born-`pending`, T1/T2/T3 coexistence, rule 4
across appended elements); cutting it in two would put half a rule set in each branch, and each half's
verification would need the other's classification. Classification and schema validation are small and share
the report module the append-only checker defines. The ownership checker is already split out (007b).

## Size, reading list (SPEC-CHECKLIST 5b; added after spec review round 1)
The reading list is about 20 files against a cap of 10. Justification: eight of them are ADRs the umbrella
already names for edges E2–E4 and are short; the load-bearing reading is four files (`append-only.rules.md`,
`entry.schema.json`, `schema_check.py`, `057-transition-fixtures.json`). Splitting the task would not shrink
the list, because every checker here consumes the same contract text.

## Acceptance criteria — all demonstrated by `docs/tasks/007a-verify.sh`, whose output the log pastes
(MANAGER.md §2c; the manager and the reviewer re-run the same script)
Umbrella criteria 1, 2, 3 (as re-based in the revision), 7 (shape: T1/T2/T3 classification), 8, 9, 10 (for
these checkers), 11, 12, and 13 (057 fixture parity), plus:
- **A1. Element classification is exposed and exact.** For each of 057's fixtures, the verdict's per-element
  classification is asserted for at least the T1, T2 and T3 accept fixtures (which element, which transition).
- **A2. Both `attacker:mod` variants** per the umbrella revision: four-element (schema REJECT asserted;
  append-only rejects with the per-element rule attribution) and three-element `[0, 1, 3]` (schema VALID
  asserted; append-only rejects). Each attribution is a separate assertion (§2c rule 3).
- **A3. Mutation (§2c rule 2).** `007a-verify.sh --mutate` runs in a temporary clone. Required set:
  (a) **an analogue of every one of the 29 mutations in `057-oracle.py`'s `MUTATIONS` list** (read the list to
  derive them; do not import the oracle), each shown to make criterion 13's fixture parity fail on named
  fixtures — this is also the parity criterion's own mutation proof; (b) the rule-1/3 and file-level
  mutations the oracle does not cover: allow an in-place edit of a `published` element (rule 1); allow
  truncation (rule 3); allow an `id` or `owner` change; allow deleting or renaming `entry.json`; allow
  reordering, or remove-and-re-add; allow `published → pending`; (c) T2 variants: accept a T2 that also
  changes another field, a whitespace `reason`, or an old status other than `published`; (d) T3 with an
  `http://` `build_log_url` or an extra key; a born-`pending` element with a fifth key; `published → rejected`;
  (e) skip schema validation, or validate a path against the wrong schema; corrupt the path→class mapping;
  (f) classify a mixed `page.json` + `entry.json` PR as `page.json`-only; treat an unknown path class as
  accepted; report usage errors with the rejection exit code; drop `authority_required`; (g) reject
  everything (positive control). Each mutation reddens named tests; a mutation that stays green fails A3.
- **A4. Fixture-count guard.** The parity test fails if `057-transition-fixtures.json` holds fewer than 73
  fixtures, or fewer than 11 accepts, or cannot be read.
- **A5. Multi-T2.** A PR with two valid T2s is shape-accepted with `authority_required: ["T2"]`; a PR with one
  valid T2 and one other in-place change is rejected, naming the second element.

## File scope (declared; anything else = stop and report)
`tools/registry/` (new), `tests/registry/` (new), `docs/tasks/007a-registry-checkers-shape.md` (log),
`docs/tasks/007a-verify.sh` (new), `docs/contracts/README.md` (umbrella criterion 12, shape half only).

## Forbidden here
The umbrella's list, plus: importing `057-oracle.py` or copying its logic into `tools/`; copying 057's
fixtures into `tests/registry/` instead of reading the file; any authority decision (who may carry T1/T3 is
007b's); enforcing monotonic versions or semver normalisation (rule 5, Q11).

## Dependencies
After 057 (merged). Parallel-safe with 062 (disjoint files). Blocks 007b. 039 follows 007b.

---
# Task 007a log
- 2026-10-15 manager: spec written (session 9) from the umbrella's revision.
- 2026-10-15 manager: spec review rounds 1-3 (FAIL, FAIL, PASS); spec-approved.
- 2026-10-15 implementer (sonnet): DONE, status set to review. Branch `task/007a-registry-checkers-shape`, cut from
  `origin/main` e009ef0, not pushed. Delivered: `tools/registry/{report,classify,schema,append_only,cli}.py`
  (5 source files, the cap), `tests/registry/{support,test_parity,test_append_only,test_classify,test_schema,test_report_cli,mutate}.py`,
  `docs/tasks/007a-verify.sh`, `docs/contracts/README.md` (criterion 12, shape half). 131 tests, all green.
- 2026-10-15 decisions with reasons (none changes a schema or contract):
  - Layout follows `tools/validation/` (flat modules, no `__init__.py`; `cli.py` and `tests/registry/support.py` put the
    sibling directory on `sys.path`). 007b imports `report` the same way.
  - Report shape is new, not `validation-report.schema.json`: that is the asset scanner's per-file scan report with no place
    for rule-id lists, per-element transitions or `authority_required` (stated in `report.py`'s docstring).
  - `classify`: class `other` (anything outside `mods/<ns>.<name>/{entry,page}.json`, an empty path set, or a malformed
    path under `mods/`) is always a REJECTION: findings `R1` (under `mods/`, cites ownership.md R1) or `unrecognised-path`
    (outside `mods/`). `reserved-namespace` wins over `entry`/`page-only`. A PR that edits `reserved-namespaces.json` is
    class `other` (rejected) and cannot change its own classification because only the merge-base data is an input.
    Consequence for 039: a maintainer PR touching e.g. `README.md` is rejected by this classifier, so the workflow must not
    route non-contributor PRs through it.
  - Rule-id vocabulary of `append_only`: `rule 1`..`rule 4`, `id-freeze`, `owner-freeze`, `deletion` (present->absent and a
    rename, which `check_pr` sees as a deletion at the old path plus a creation at the new), `malformed`,
    `unrecognised-path`. An illegal attempt at T1/T2/T3, or any other in-place change, is `["rule 1"]` (the contract:
    "every other change to an existing element is a violation of rule 1"), with `attempted` naming the transition.
    A bad appended element is `["rule 2"]`, `["rule 4"]` or both.
  - Strict equality: parsed-JSON deep equality where `true != 1` (Python's `True == 1` would otherwise let `owner.id: true`
    pass the freeze); key order is irrelevant (contract). Tested and mutation-proved.
  - Per-field patterns for T1/T3/born-pending come from `entry.schema.json`'s item sub-schemas through
    `schema_check.validate`, never from a re-implemented regex; key sets are explicit so each defence is a separate
    mutation target (no redundant layer hides a mutant). The whole-document schema check stays in `schema.py`.
  - Stricter than 057's oracle in one place the contract states: T3 requires `reason` and `build_log_url` absent from the
    OLD element (T3 clause 3). Parity on all 73 fixtures is unaffected.
  - `authority_required` is the sorted list of T1/T2/T3 present among the elements, also when the verdict is rejected.
  - Malformed merge-base data is exit 2 (tool error), not a rejection: the PR is not at fault.
  - Attacker attribution matches the umbrella revision exactly; no divergence from `append-only.rules.md`, so no stop.
    Four-element: elements 0 and 1 `["rule 2","rule 4"]`, elements 2 and 3 `["rule 2"]` (neither is rule 4); three-element
    `[0,1,3]`: indices 0,1 `["rule 2","rule 4"]`, index 2 (the whitespace-reason born-removed) `["rule 2"]`. No further rule
    is reported. Measured facts re-established by tests: schema accepts elements 0, 1, 3 alone and rejects element 2
    (`$.versions[2]`), rejects the four-element entry, accepts the three-element variant.
  - Hostile fixtures were shown red before counting: the mutation runner (below) is that proof; e.g. `oracle-12..14`
    (allow born published/removed/rejected) redden `first-publish-born-*` and the attacker element tests.
  - The mutation runner found my own expectation mistakes: a stale-bytecode hazard (it now runs `python3 -B` with
    `PYTHONDONTWRITEBYTECODE=1`) and named tests that a layered defence legitimately kept green (corrected to the tests that
    do redden). It also showed `b-allow-reorder-by-content` is caught only by my unit tests, not by fixture
    `t1-reorders-versions`, which stays red through its T1 element (recorded, not hidden).
- 2026-10-15 verify output, normal, run in the worktree AND in a fresh clone of the committed branch (`961a213`), both exit 0:
  ```
  Ran 131 tests in 1.447s / OK
  ok    umbrella 1/2  CLI + verdict shape + three distinct exit codes: 8 passing, 0 failing
  ok    umbrella 3/A2 attacker:mod four-element, per-element attribution: 8 passing, 0 failing
  ok    A2            attacker:mod three-element variant [0,1,3]: 5 passing, 0 failing
  ok    A2            schema REJECT / VALID premises asserted: 2 passing, 0 failing
  ok    umbrella 7/A5 multi-T2 accepted, T2 + other change rejected: 2 passing, 0 failing
  ok    umbrella 8    classification exhaustive and fail closed: 6 passing, 0 failing
  ok    umbrella 13   057 fixture parity (read at test time): 1 passing, 0 failing
  ok    A1            element classification of T1/T2/T3 accept fixtures: 7 passing, 0 failing
  ok    A4            fixture-count guard: 2 passing, 0 failing
  ok    size: 5 source files in tools/registry (cap 5: report, classify, schema, append_only, cli)
  ok    CLI exit codes accepted/rejected/error = 0 1 2
  ok    changed files all inside the declared scope
  ok    A3(a) oracle MUTATIONS list read from text: 29 names
  ok    A3(a) every oracle mutation name has an analogue in tests/registry/mutate.py
  SUMMARY failed=0
  ```
- 2026-10-15 verify output, `--mutate` (scratch clone; also run from a fresh clone), exit 0:
  ```
  baseline green on committed 961a21362
  SUMMARY 73 mutations, not_red=0
  ok    every mutation turned its named tests red
  SUMMARY failed=0
  ```
  Composition: 29 `oracle-*` analogues (every name in 057-oracle.py's MUTATIONS, read from text by the script), 9 (b),
  3 (c), 6 (d), 7 (e), 13 (f: classify, exit codes, authority_required, messages, attribution collapse, page.json), 2 (g)
  reject-everything controls, 4 A4 guards (fewer than 73 fixtures, fewer than 11 accepts, unreadable, missing file). Each
  names the tests/fixtures that must be red; a green or under-reddening run counts as NOT RED. First full run had 4 NOT RED
  (my wrong expectations); the final run has 0.
- 2026-10-15 remaining / for the manager: nothing blocking. For 007b: import `report`, `classify.parse_mod_path`,
  `append_only.check_pr` (its `elements[*].classification` and `authority_required` are the R11 inputs). For 039: run 007b whenever
  `authority_required` is non-empty; a T1/T3 is shape-legal here.

## Questions
None blocking. Non-blocking, for the manager to book (MANAGER.md 8b): (A) `classify` rejects class `other`, including any
PR that touches files outside `mods/` (e.g. a maintainer's docs change). Lean: keep, and let 039 decide which PRs the checker
sees. Alternative: accept a named maintainer class here, which would be a new decision, so not taken.
- 2026-10-15 manager: question (A) answered: keep rejecting class `other` (umbrella criterion 8, fail closed); which PRs
  reach the checker is task 039's path filter (ADR-0099). Manager re-ran `007a-verify.sh` in a fresh clone at `b5db29b`:
  normal `SUMMARY failed=0`; `--mutate` 73 mutations, `not_red=0`. Sent to independent review.
- 2026-10-15 manager brief, fix round 1 (independent review FAIL, one blocking finding). Findings as briefed:
  F1 BLOCKING: every `$`-anchored pattern check accepts a trailing newline (schema_check.py uses `re.search`; Python `$`
  matches before a final "\n"). Probes wrongly accepted: pending commit = "a"*40+"\n"; T1 source_sha256 = "b"*64+"\n"; T3
  build_log_url = "https://x.org/log\n"; T1 signature = "c"*62+"\n"; T1 key_id = "platform-2026-01\n". Contract patterns
  follow ECMA-262 (`$` only at end of input). Fix inside 007a scope (append_only `_field_ok`, schema.py), do NOT edit
  tests/contracts/schema_check.py (manager books the root-cause fix); `re.fullmatch` alone is not equivalent; document the
  approach; hostile fixtures for all five probes plus the schema.check path, positive controls, a mutation restoring the old
  behaviour. F2: cli `_read` follows symlinks: a symlinked entry.json/page.json is a rejection finding; state in cli help and
  README that the caller must diff with `--no-renames` (039 wires it). F3: reject duplicate JSON object keys in `_read` and
  schema.check's string path, with tests and a mutation. F5: 007a-verify.sh must FAIL when origin/main is missing. F4: no
  change (the contract does not require it); considered and recorded. Rule: each break first as a test shown red, then fixed.
- 2026-10-15 implementer, fix round 1 DONE (status back to review; commits ed9cb67, c2babbc). Red first: the new
  `tests/registry/test_hardening.py` (18 tests) against the unfixed code gave `FAILED (failures=25, errors=1)`, e.g.
  `FAIL: test_f1_born_pending_commit_with_trailing_newline_is_rule_2`, `test_f1_t1_pipeline_fields_with_trailing_newline_are_rejected
  (field='source_sha256')`, `test_f1_t3_build_log_url_with_trailing_newline_is_rejected`, `test_f1_schema_check_rejects_entry_strings_...`,
  `test_f2_a_symlinked_entry_json_...`, `test_f3_schema_check_text_path_rejects_duplicate_keys`. After the fix: `Ran 150 tests ... OK`
  (also under `python3 -W error`). Fixes: F1 `schema.validate()` = schema_check.validate plus a re-check of every string
  pattern with unescaped `$` (outside classes) rewritten to `\Z` (`ecma_pattern`; documented in schema.py: `re.fullmatch`
  differs for unanchored patterns, the rewrite changes only where `$` may match); used by `schema.check` and by append_only
  `_field_ok`. F2 `cli._read` rejects symlinks (rule `symlink`, message and help/README say `git diff --no-renames`). F3
  `schema.loads_strict` rejects duplicate keys (rule `duplicate-key`) in `cli._read` and the `schema.check` text path. F5
  verify script now FAILS without origin/main; new criterion lines F1/F2/F3. F4 considered, no change (the contract does not
  require it). Source files still 5. Mutations added (5): old `search`-`$` behaviour, `$` not rewritten, append_only on the
  plain validator, symlink read-through, duplicate keys allowed; all red. Fresh clone of `c2babbc`: normal `Ran 150 tests ... OK`,
  `SUMMARY failed=0`; `--mutate`: `baseline green on committed c2babbcf5`, `SUMMARY 78 mutations, not_red=0`, `SUMMARY failed=0`
  (the first fresh-clone mutate run correctly failed on a stale anchor, `ANCHOR ERROR ... occurs 0 times`, which I fixed).
  SPEC/CONTRACT CONFLICT, not improvised: two of the five reviewer probes (T1 `signature` = "c"*62+"\n" and `key_id` =
  "platform-2026-01\n") are NOT rejected. `entry.schema.json` gives those fields minLength only (no pattern), append-only T1
  clause 3 says "its pattern (or, for signature and key_id, its minimum length)", and `signature-format.md` says `signature`
  holds multi-line text. Rejecting them would invent a rule; tests assert the contract-valid behaviour explicitly.
  signature-format.md also states `key_id` is 16 uppercase hex, which the schema does not enforce: that is a schema change
  (out of scope) for the manager to decide.

## Questions
- BLOCKING for the manager (F1 probes 4 and 5): decide whether `signature`/`key_id` need a pattern (schema change, probably
  `key_id` `^[0-9A-F]{16}$` per signature-format.md, and a signature grammar), or whether the reviewer's probes are accepted as
  contract-valid. 007a enforces what the contract states and nothing more.
- A (manager, 2026-10-15): accepted as contract-valid today (T1 clause 3: "or, for signature and key_id, its minimum
  length"); the reviewer agrees. The schema/signature-format.md inconsistency for `key_id` is booked as platform task 065.
- 2026-10-15 manager: fresh-clone re-run at `05322bf`: 150 tests OK, `SUMMARY failed=0`; `--mutate` 78 mutations,
  `not_red=0`. Delta review of fix round 1: PASS, no blocking findings. New non-blocking N1 (Python `\d` matches Unicode
  digits, unlike ECMA; fullwidth digits in `published_at` pass) is folded into platform task 064 (`re.ASCII`, here and in
  `schema_check.py`). Merge held for Ludwig: security-relevant CI (MANAGER.md §7).
