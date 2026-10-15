# Task 070: no closed task's verify script measures its own change against `HEAD` (audit + re-pin), and every script finds the pinned ajv

- **Mission:** SITE-V1 (verification integrity) — **Status:** spec-approved (manager, solo gate, 2026-10-16, session 10;
  test-artefact maintenance, the shape of tasks 062, 067, 069)
- **Repo:** registry. **Agent / model:** qa-engineer / sonnet (§3.5: changing closed tasks' verify scripts is its own
  reviewed task). **Budget:** small–medium (≤ 2 agent-sessions)
- **Branch / worktree:** `task/070-closed-verify-head-audit` / `~/wt/registry-task-070`, cut from registry `origin/main`
  (`2347ffb`, after 069)
- **Graph:** verification tooling only; no node or edge.

## Objective
1. **The defect class, closed for good.** On 2026-10-16 the manager's merge gate for task 007b found `067-verify.sh`
   AC2.4 red: it checks `git diff "$BASE" HEAD -- docs/contracts/README.md` is empty, so any later task that legitimately
   edits that README (007b does, in scope) turns 067 red. AC2.1–AC2.3 measure `"$BASE" HEAD` on `032-verify.sh` the same
   way. This is the fourth instance of one class in two days (062: 006/008a/032/057; 069: 007a, 067 AC5.1). After this task,
   **every** check in every closed task's verify script that is meant to describe *that task's own change* measures the
   task's pinned range `BASE..FINAL` (FINAL = the last commit of its PR, `<merge commit>^2`), never `HEAD` or the working
   tree. Checks that are meant to hold on the live tree (e.g. 067 AC2.5 "the README states the sentence", 032 N5b) stay
   live — the audit classifies each, with a one-line reason.
2. **Audit artefact.** `docs/tasks/070-audit.md` lists, for every closed verify script on `main` (`006, 007a, 008a, 032,
   034, 057, 062, 066, 067, 069`), every git-diff / file-scope / size / "unchanged" check: line, what it compares, and
   the verdict *own-change → re-pin* or *live property → stays*, with the reason. A script with zero such checks is listed
   with "none found" and the grep that proved it, plus that grep's positive control (§2c rule 1).
3. **ajv default everywhere.** `067-verify.sh` and `069-verify.sh` (and any other closed script that needs ajv) resolve
   it like 057/062 after task 066: argument → `WOM_NODE_MODULES` → `<repo root>/tools/dev/node_modules`, failing (never
   skipping) with a message naming `npm ci --prefix tools/dev`.

## Context to load (exhaustive)
This file; registry `docs/tasks/*-verify.sh` (the ten above), `docs/tasks/062-registry-test-maintenance.md` (D-1),
`docs/tasks/069-closed-verify-maintenance.md` (the pinning pattern and how PR pins were derived), `tools/dev/README.md`;
platform `docs/manager/MANAGER.md` §2c, §3.5, `docs/manager/OPERATIONS.md`.

## Acceptance criteria — `docs/tasks/070-verify.sh`, whose output the log pastes
1. **Red first (§2c rule 5):** before any fix, a commit adds checks to `070-verify.sh` that build a throw-away later branch
   touching `docs/contracts/README.md` (007b's shape) and every other file an own-change check guards, and run each
   closed script there; shown red on that commit for 067 AC2.4 at least, and for every other own-change check the audit
   reclassifies.
2. After the fix, every closed script is green on HEAD **and** on that later branch.
3. Mutations (`--mutate`), each red: for every re-pinned check, widening its range back to `HEAD`; an unreachable pin
   fails, never skips; for the ajv default, removing it from 067 and from 069.
4. Live-property checks are not converted: a mutation that breaks the live property (e.g. deleting the README sentence)
   still reddens the corresponding live check on HEAD.
5. Measured on a quiet machine (`ps` checked and logged before each run), run one script at a time: all ten closed
   scripts green on HEAD; `062-verify.sh`, `067-verify.sh` and `007b-verify.sh` green on the merge of this branch with
   `origin/task/007b-registry-checker-ownership`; `062-verify.sh` green on the merge with
   `origin/task/064-schema-check-end-anchor` (a red that belongs to 064's open R1 cleanup is reported, not fixed here).

## File scope (declared)
`docs/tasks/{006,007a,008a,032,034,057,062,066,067,069}-verify.sh` (re-pins and ajv resolution only),
`docs/tasks/070-closed-verify-head-audit.md` (log), `docs/tasks/070-audit.md` (new), `docs/tasks/070-verify.sh` (new).
Any change under `tests/`, `tools/` or `contracts/` = stop and report.

## Size
Verify scripts and docs only; excluded from the counts. Reading list: 13 files (ten scripts are the subject matter, not
background). Over the cap of 10; reason: the audit's whole point is completeness across all closed scripts — splitting
it per script is exactly how this class survived three earlier rounds.

## Forbidden here
Loosening any check beyond moving its comparison range from `HEAD` to the task's own pinned range; converting a
live-property check into a pinned one; a skip that yields green; running suites concurrently.

## Dependencies
After 069 (merged). Before 007b (PR #12) and 064 (PR #13) merge; both merge `main` after this lands.

---
# Task 070 log
- 2026-10-16 manager (session 10): written and approved (solo gate). Source: manager's merge gate on 007b's merge result
  (`8e0d57b`): 007b, 007a, 008a, 032, 034, 057, 062 green; `067-verify.sh` FAIL AC2.4 "docs/contracts/README.md was
  modified" (`067-verify.sh:76-78`, `git diff "$BASE" HEAD`). 067/069 needing ajv passed explicitly found in 069's gate.
- 2026-10-16 manager: worktree cut from registry origin/main `2347ffb`; dispatched. check-log-entry baseline = 2.
