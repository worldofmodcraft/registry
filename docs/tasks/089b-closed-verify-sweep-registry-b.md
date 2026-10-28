# Task 089b: registry closed scripts — part B (contract and R11 pins; findings 8-12, S4)

- **Mission:** SITE-V1 (verification integrity) — **Status:** in-progress 2026-10-28 (cut from umbrella 089 at dispatch, session 13; umbrella spec-approved 2026-10-26, parts per Q5 ★ A)
- **Agent / model:** qa-engineer (model per frontmatter) — **Budget:** medium (≤ 3 agent-sessions)
- **Branch / worktree:** `task/089b-closed-verify-sweep-registry-b` / `~/wt/registry-task-089b`, from registry main `e2f7fe3`
- **Umbrella (authoritative for findings, pins, criteria, forbidden list, Q1-Q6):** `docs/tasks/089-closed-verify-sweep-registry.md` (copied
  into this branch from platform `session/13` `5c59f34`; read-only here except nothing — do not edit it).

## Scope of this part
Findings **8, 9, 10, 11, 12** and side finding **S4** of the umbrella table. Source files (4): `docs/tasks/065-verify.sh`,
`docs/tasks/075-verify.sh`, `docs/tasks/039a-verify.sh`, `tests/registry/test_ci_gate.py`. New: `docs/tasks/089b-verify.sh`.
Log: this file. Anything else = stop and report.
Decisions already taken (umbrella): Q1 assumed A (document the double run in the 039a header; S4); Q2 ★ B (move AC9ProductionR11Unconfigured
into `039a-verify.sh` at the pin, delete the unit test, show the preserved assertion).

## Acceptance criteria
The umbrella's criteria 1-5, 8, 9, 10 and 11, restricted to findings 8-12 and S4, shipped as `docs/tasks/089b-verify.sh`.
Criterion 9 (quiet machine) is mandatory: one script at a time, `ps` logged before each run.

---
# Task 089b log  (append-only)
- 2026-10-28 manager (session 13): cut from umbrella 089 and dispatched; base registry main `e2f7fe3` (087, 082, 039b, 092 merged). Machine quiet.
