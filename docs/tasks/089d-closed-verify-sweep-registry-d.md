# Task 089d: registry closed scripts — part D (post-TIP merge-into-branch defect in 092-verify.sh)

- **Mission:** SITE-V1 (verification integrity) — **Status:** in-progress 2026-10-28 (cut from umbrella 089 at dispatch, session 14; umbrella spec-approved 2026-10-26, parts per Q5 ★ A; part D spec-approved 2026-10-28 after independent spec review)
- **Agent / model:** qa-engineer (model per frontmatter) — **Budget:** small (one agent-session)
- **Branch / worktree:** `task/089d-closed-verify-sweep-registry-d` / `~/wt/registry-task-089d`, from registry main `32c641b`
- **Umbrella (authoritative for findings, pins, criteria, forbidden list, Q1-Q6):** `docs/tasks/089-closed-verify-sweep-registry.md` (copied
  into this branch from platform main `4321d07`; read-only here — do not edit it).

## Scope of this part
Source files: `docs/tasks/092-verify.sh` (AC9 post-TIP only, per umbrella part D (f)) (1). New: `docs/tasks/089d-verify.sh`. Log: this file. Anything else = stop and report.

## Acceptance criteria
The umbrella part D criteria (a)-(f) and forbidden list, verbatim; Q6 answered (★ A). Shipped as `docs/tasks/089d-verify.sh`. Quiet machine (criterion 9) is mandatory: one script at a time, `ps` logged before each run.
Same pattern as part B (`origin/task/089b-closed-verify-sweep-registry-b`, file `docs/tasks/089b-verify.sh`) and the 084/087 reference pattern.

## Questions  (agent-maintained; see MANAGER.md 8b)

---
# Task 089d log  (append-only)
- 2026-10-28 manager (session 14): cut from umbrella 089 and dispatched for phase 1 (no verify runs while 089b's long driver holds the machine);
  base registry main `32c641b` (087, 082, 039b, 092, 008c merged).
