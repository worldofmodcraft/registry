# Task 089a2: registry closed scripts — part A2 (finding 6, S2, S3)

- **Mission:** SITE-V1 (verification integrity) — **Status:** in-progress 2026-10-28 (cut from umbrella 089 at dispatch, session 14; umbrella spec-approved 2026-10-26, parts per Q5 ★ A)
- **Agent / model:** qa-engineer (model per frontmatter) — **Budget:** small (one agent-session)
- **Branch / worktree:** `task/089a2-closed-verify-sweep-registry-a2` / `~/wt/registry-task-089a2`, from registry main `32c641b`
- **Umbrella (authoritative for findings, pins, criteria, forbidden list, Q1-Q6):** `docs/tasks/089-closed-verify-sweep-registry.md` (copied
  into this branch from platform main `4321d07`; read-only here — do not edit it).

## Scope of this part
Source files: `docs/tasks/057-verify.sh`, `docs/tasks/057-textchecks.py`, `docs/tasks/070-verify.sh` (header text only) (3). New: `docs/tasks/089a2-verify.sh`. Log: this file. Anything else = stop and report.

## Acceptance criteria
The umbrella criteria 1-5, 7, 9 and 11, restricted to finding 6, S2 and S3. Q4 is decided ★ A (manager, session 14, overnight ruling): read ADR-0121 at a pinned commit of a history the script can reach without a hard-coded working-copy path; if no such history is reachable from the registry clone, use a committed fixture blob (Q4 option B) and log why. Shipped as `docs/tasks/089a2-verify.sh`. Quiet machine (criterion 9) is mandatory: one script at a time, `ps` logged before each run.
Same pattern as part B (`origin/task/089b-closed-verify-sweep-registry-b`, file `docs/tasks/089b-verify.sh`) and the 084/087 reference pattern.

## Questions  (agent-maintained; see MANAGER.md 8b)

---
# Task 089a2 log  (append-only)
- 2026-10-28 manager (session 14): cut from umbrella 089 and dispatched for phase 1 (no verify runs while 089b's long driver holds the machine);
  base registry main `32c641b` (087, 082, 039b, 092, 008c merged).
