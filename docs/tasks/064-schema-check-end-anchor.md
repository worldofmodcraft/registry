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
