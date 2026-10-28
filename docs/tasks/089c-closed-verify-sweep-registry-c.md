# Task 089c: registry closed scripts — part C (S1: 069 branch-tip pin)

- **Mission:** SITE-V1 (verification integrity) — **Status:** in-progress 2026-10-28 (cut from umbrella 089 at dispatch, session 14; umbrella spec-approved 2026-10-26, parts per Q5 ★ A)
- **Agent / model:** qa-engineer (model per frontmatter) — **Budget:** small (one agent-session)
- **Branch / worktree:** `task/089c-closed-verify-sweep-registry-c` / `~/wt/registry-task-089c`, from registry main `32c641b`
- **Umbrella (authoritative for findings, pins, criteria, forbidden list, Q1-Q6):** `docs/tasks/089-closed-verify-sweep-registry.md` (copied
  into this branch from platform main `4321d07`; read-only here — do not edit it).

## Scope of this part
Source files: `docs/tasks/069-verify.sh` (1). New: `docs/tasks/089c-verify.sh`. Log: this file. Anything else = stop and report.

## Acceptance criteria
The umbrella criteria 1-3, 6, 9 and 11, restricted to S1. Shipped as `docs/tasks/089c-verify.sh`. Quiet machine (criterion 9) is mandatory: one script at a time, `ps` logged before each run.
Same pattern as part B (`origin/task/089b-closed-verify-sweep-registry-b`, file `docs/tasks/089b-verify.sh`) and the 084/087 reference pattern.

## Questions  (agent-maintained; see MANAGER.md 8b)

---
# Task 089c log  (append-only)
- 2026-10-28 manager (session 14): cut from umbrella 089 and dispatched for phase 1 (no verify runs while 089b's long driver holds the machine);
  base registry main `32c641b` (087, 082, 039b, 092, 008c merged).
