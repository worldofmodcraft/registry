# Task 094: pipeline modules match schema patterns with ECMA-262 semantics (reuse `ecma_pattern`)

- **Mission:** SITE-V1 (D2 hardening) — **Status:** spec-approved 2026-10-28 (manager, after independent spec review PASS-WITH-AMENDMENTS, all 6 findings folded in)
- **Agent / model:** implementer (model per frontmatter) — **Budget:** small
- **Branch / worktree:** `task/094-pipeline-ecma-patterns` / `~/wt/registry-task-094` — **registry** repo, from registry main `ab5fcba` (re-based 2026-11-06; see the log)
- **Graph:** nodes N5 (build pipeline) and N3 (registry CI): code reuse of the E2/E8 pattern semantics inside the one registry repo; no new
  contract edge; one-way import N5 -> N3 tools; N3 never imports N5 (grep in the verify script). Decision (manager ★, spec review finding 1):
  the import is allowed; `ecma_pattern` is NOT moved, because `tools/registry/schema.py` is pinned by closed scripts 034, 064 and 007b.

## Why
Two findings from 008c (2026-10-28): (1) 008a's `tools/pipeline/build_version.py` `_PAT_SEMVER` is matched with Python `re`, whose `\d`
accepts non-ASCII digits (observed read-only by the 008c fix-round agent; re-demonstrated by criterion 1); (2) 008c's `write_back.py`
translates only `\d`, leaving Python-vs-ECMA `\s` differences (U+FEFF accepted by `\S`; U+001C-U+001F and U+0085 refused; reproduced by the
spec reviewer). The registry gate already validates with `tools/registry/schema.py` `ecma_pattern` via `re.search(...)` (schema.py:127).
After this task the pipeline gives the gate's verdict for every schema pattern. Behaviour change: the pipeline then accepts U+001C and U+0085
inside URLs (ECMA-correct, as the gate does); `docs/pipeline/build-pipeline.md` (around l.214) changes with the code.

## Design
One new module `tools/pipeline/ecma.py` loads `tools/registry/schema.py` (by `importlib.util.spec_from_file_location`, or `sys.path` insert +
`import schema`; implementer's choice, stated in the log with the reason, watching that `tests/validation/schema_check.py` must not shadow
`tests/contracts/schema_check.py`) and exposes `matches(pattern, value) -> bool` = `isinstance(value, str) and re.search(schema.ecma_pattern(pattern), value) is not None`
(the gate's exact expression; `ecma_pattern` is built for `re.search`, not `fullmatch`). `build_version` and `write_back` use it for every
schema pattern; `write_back._ecma_digits` is removed. `NotImplementedError` from the translator propagates (never caught).

## Context to load
`tools/registry/schema.py` (docstring + `ecma_pattern` + l.127), `tools/pipeline/build_version.py`, `tools/pipeline/write_back.py`,
`tests/pipeline/test_write_back.py`, `tests/pipeline/mutate.py`, `contracts/entry.schema.json`, `docs/pipeline/build-pipeline.md` (write-back
section), task logs 008c (findings' origin) and 064 (the translator). Doctrine: MANAGER.md §2c rules 1-5, §3.7; REVIEW-CHECKLIST item 12.

## Acceptance criteria (shipped as `docs/tasks/094-verify.sh`; own-change checks pinned BASE=`32c641b`, FINAL = reviewed tip recorded in the log)
1. **Red first.** Commit A (tests only, on `32c641b`); the log pastes the failing output at A: (a) a `build_version` semver with `1.0.1٣`
   and a `published_at` with an Arabic-Indic digit are rejected (FAIL at A); (b) `write_back` with `source_archive` containing U+FEFF raises
   `WriteBackRefused` (`bad-value`) (FAIL at A); (c) `source_archive` containing U+001C and U+0085 is ACCEPTED (FAIL at A). Commit B (fix)
   turns all green.
2. **Positive controls:** U+00A0, U+2028, U+2029, U+3000, U+2003 inside `source_archive` stay refused (008c's fix3 test); ordinary non-ASCII
   visible characters stay accepted; `id` with a trailing newline stays rejected; `commit` stays hex-only.
3. **Equivalence:** for each pattern in `contracts/entry.schema.json`, collected by a recursive walk (assert the count is 9, so a schema change
   forces review), and for >= 20 000 strings per pattern from a seeded generator (fixed seed; alphabet ASCII printable + `\n`, `\r`, U+0663,
   U+FF11, U+FEFF, U+001C-U+001F, U+0085, U+00A0, U+2028, U+2029, plus near-valid mutants of one known-valid example per pattern), the helper's
   verdict equals `re.search(schema.ecma_pattern(p), s) is not None` computed in the test independently of `ecma.py`; each pattern's set holds
   >= 1 accepted and >= 1 rejected string; and every pattern starts with `^` and ends with `$` (else fail loudly).
4. **Mutations, each named red:** (m1) helper uses `re.fullmatch` on the raw pattern (reddens 1, 3); (m2) the helper bypassed in
   `build_version` only; (m3) in `write_back` only; (m5) the helper catches `NotImplementedError` (a test feeding an unsupported construct,
   e.g. `\D` inside a class, expects propagation); (m6) `tests/pipeline/mutate.py`'s existing mutations all still red (`not red = 0`), with its
   `fullmatch-becomes-search` mutation (around line 99) adapted to the new code, never dropped. `re.fullmatch(ecma_pattern(p))` is an
   equivalent mutation on the 9 anchored patterns and is documented as such, not counted.
5. **Regression frame:** the full pipeline suite (the invocation `008a-verify.sh` uses) green at the 094 head, `SUMMARY failed=0`, count >= 147
   plus the new tests; `008a-verify.sh` green once on the head in the final fresh clone. `008c-verify.sh` is **not** a 094 criterion (its
   own-change scope check is bound to the 008c branch): one command shows it red on the 094 branch for scope reasons only (paste the
   out-of-scope files it lists) while `tests/pipeline/test_write_back.py` passes in full. Re-pinning 008c-verify is booked under task 089.
6. **Replaced, not deleted:** the `_ecma_digits` tests (escaped backslash `\\d`, `\D` raising) move to equivalent tests of the new helper; a grep
   shows `_ecma_digits` absent from `tools/` and `tests/`. Docs: build-pipeline.md's `bad-value` row and the `\s` sentence match the new code.
7. **Artefact:** `094-verify.sh` executable, `--mutate` mode, run in a fresh clone of the pushed branch from GitHub; outputs pasted. No N3 -> N5
   import (grep with a positive control). The helper imports neither subprocess nor a network library (008c AC6's grep stays green).

## File scope (registry)
New: `tools/pipeline/ecma.py`, `tests/pipeline/test_ecma_patterns.py`, `docs/tasks/094-verify.sh`. Changed: `tools/pipeline/build_version.py`,
`tools/pipeline/write_back.py`, `tools/pipeline/plan_pending.py` (its pattern matching and subset validator, added 2026-10-28 from 008b-1 Q-P6), `tests/pipeline/test_write_back.py` (the `_ecma_digits` tests only), `tests/pipeline/mutate.py` (the one
adapted mutation), `docs/pipeline/build-pipeline.md` (write-back section), `docs/tasks/094-pipeline-ecma-patterns.md` (log).

## Size
4 source files (`ecma.py`, `build_version.py`, `write_back.py`, `plan_pending.py`), est. under 160 changed lines; within the §2b soft cap.

## Forbidden here
Editing `tools/registry/schema.py`, `tests/contracts/schema_check.py`, `contracts/*` or any other task's verify script; `re.ASCII` or any global
flag; `except NotImplementedError` around the translator; copying the translator into `tools/pipeline`; deleting `_ecma_digits` tests without
replacement; reading schema patterns from anywhere but `contracts/entry.schema.json`; copying 092-verify.sh's post-TIP pattern.

---
# Task 094 log  (append-only)
- 2026-10-28 manager (session 13): drafted from 008c's review (findings 1 and the residual-\s decision) and fix-round observation.
- 2026-10-28 manager (session 13): independent spec review PASS-WITH-AMENDMENTS (6 findings: import direction + graph line (★ allow, no move);
  file scope + size; HIGH criterion 5 undemonstrable (008c-verify bound to its branch -> regression frame; repin booked under 089); red-first
  frame; non-vacuous equivalence; artefact pins + Forbidden). All folded in. **spec-approved.** Dispatch after 089b releases the machine.
- 2026-10-28 manager (session 13): scope extended by `tools/pipeline/plan_pending.py` (008b-1 Q-P6: it borrows `write_back`'s private helpers and carries a fail-closed subset schema validator; both move to the gate's semantics here). Dispatch after 008b-1 merges; the delta is re-checked against SPEC-CHECKLIST at dispatch.
- 2026-11-06 manager (session 15): **delta re-check against registry main `ab5fcba`** (spec was written on `32c641b`; base now `ab5fcba`). In scope and changed since: `tools/pipeline/build_version.py`, `tools/pipeline/plan_pending.py` (008b-1/2): re-read them, do not trust this spec's line numbers. **New callers since:** `tools/pipeline/handoff.py:167,169` (`wb._fullmatch(wb._PAT_ID|_PAT_SEMVER, ...)`) and `tools/pipeline/sign_built.py:101` (`build_version._fullmatch(build_version._PAT_PUBLISHED_AT, ...)`). They go through the helpers this task replaces, so they are not added to the file scope. **Added criterion 3b:** a test calls `handoff`'s and `sign_built`'s validation paths and shows the gate's verdict on a non-ASCII digit and on U+001C/U+0085, red before the change; if either module needs editing to get there, stop and report (scope). Not in scope, booked: hand-written ID and semver patterns in `naming.py:22-24` and `reference_verify.py:31` duplicate schema patterns and could drift. **Merge gate:** a whole sweep with `tools/dev/sweep.py` on the merge result (the manager), after 111b. Sequenced after 111b: two agents with quiet-waits on one machine can wait on each other.
