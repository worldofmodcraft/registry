# Task 089e: registry closed scripts — part E (008c-verify.sh own-change scope check re-pinned to 008c's merged range)

- **Mission:** SITE-V1 (verification integrity) — **Status:** in-progress 2026-10-28 (cut from umbrella 089 at dispatch, session 14; umbrella spec-approved 2026-10-26, parts per Q5 ★ A; part E cut by the manager in session 14 from the finding booked in the umbrella log (094 spec review), spec-approved solo under MANAGER.md §2b as a small, mechanical one-file task of the umbrella pattern)
- **Agent / model:** qa-engineer (model per frontmatter) — **Budget:** small (one agent-session)
- **Branch / worktree:** `task/089e-closed-verify-sweep-registry-e` / `~/wt/registry-task-089e`, from registry main `32c641b`
- **Umbrella (authoritative for findings, pins, criteria, forbidden list, Q1-Q6):** `docs/tasks/089-closed-verify-sweep-registry.md` (copied
  into this branch from platform main `4321d07`; read-only here — do not edit it).

## Scope of this part
Source files: `docs/tasks/008c-verify.sh` (the own-change scope check and its pins only) (1). New: `docs/tasks/089e-verify.sh`. Log: this file. Anything else = stop and report.

## Acceptance criteria
Re-pin `008c-verify.sh`'s own-change scope check from "merge-base with current origin/main" to 008c's merged range: BASE = `git merge-base M^1 M^2`, FINAL = `M^2`, M = `32c641b` (the merge of registry PR #27; the agent re-derives all three as full 40-character SHAs and records them). Criteria, mirroring the umbrella 1-5, 9, 11 for this one check: (1) red first: the unfixed script FAILs on registry main (observed "no changes since base") and on a later synthetic branch that touches another file; the fixed one passes both; (2) pins are full SHAs, recomputed and asserted in `089e-verify.sh`; (3) a `deadbee` pin is FAIL, never skip; (4) `--mutate`: widening the check back to the merge-base with origin/main reddens it, only it; the existing 008c mutations still all go red; (5) item-12 control: fixed `008c-verify.sh` exits 0 on HEAD and on a merge with a later synthetic branch; (9) quiet machine; (11) scope: only `008c-verify.sh` (that check and its pins), `089e-verify.sh`, this file. Shipped as `docs/tasks/089e-verify.sh`. Quiet machine (criterion 9) is mandatory: one script at a time, `ps` logged before each run.
Same pattern as part B (`origin/task/089b-closed-verify-sweep-registry-b`, file `docs/tasks/089b-verify.sh`) and the 084/087 reference pattern.

## Questions  (agent-maintained; see MANAGER.md 8b)

---
# Task 089e log  (append-only)
- 2026-10-28 manager (session 14): cut from umbrella 089 and dispatched for phase 1 (no verify runs while 089b's long driver holds the machine);
  base registry main `32c641b` (087, 082, 039b, 092, 008c merged).
