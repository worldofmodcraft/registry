# Task 007a: Registry checkers, shape half — PR classification, schema validation, append-only (T1/T2/T3)

- **Mission:** SITE-V1, D1 — **Status:** spec-approved (manager, 2026-10-15, after independent spec review rounds 1–3:
  FAIL, FAIL, PASS)
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
