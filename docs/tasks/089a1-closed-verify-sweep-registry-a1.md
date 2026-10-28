# Task 089a1: registry closed scripts — part A1 (README and namespace pins; findings 1-5, 7, 13)

- **Mission:** SITE-V1 (verification integrity) — **Status:** in-progress 2026-10-28 (cut from umbrella 089 at dispatch, session 14; umbrella spec-approved 2026-10-26, parts per Q5 ★ A)
- **Agent / model:** qa-engineer (model per frontmatter) — **Budget:** medium (≤ 3 agent-sessions)
- **Branch / worktree:** `task/089a1-closed-verify-sweep-registry-a1` / `~/wt/registry-task-089a1`, from registry main `32c641b`
- **Umbrella (authoritative for findings, pins, criteria, forbidden list, Q1-Q6):** `docs/tasks/089-closed-verify-sweep-registry.md` (copied
  into this branch from platform main `4321d07`; read-only here — do not edit it).

## Scope of this part
Source files: `docs/tasks/007a-verify.sh`, `docs/tasks/007b-verify.sh`, `docs/tasks/008a-verify.sh`, `tests/registry/test_hardening.py`, `tests/registry/test_classify.py` (5). New: `docs/tasks/089a1-verify.sh`. Log: this file. Anything else = stop and report.

## Acceptance criteria
The umbrella criteria 1-5, 9 and 11, restricted to findings 1-5, 7 and 13 (Q3 answered: A, consequence accepted). Shipped as `docs/tasks/089a1-verify.sh`. Quiet machine (criterion 9) is mandatory: one script at a time, `ps` logged before each run.
Same pattern as part B (`origin/task/089b-closed-verify-sweep-registry-b`, file `docs/tasks/089b-verify.sh`) and the 084/087 reference pattern.

## Questions  (agent-maintained; see MANAGER.md 8b)

---
# Task 089a1 log  (append-only)
- 2026-10-28 manager (session 14): cut from umbrella 089 and dispatched for phase 1 (no verify runs while 089b's long driver holds the machine);
  base registry main `32c641b` (087, 082, 039b, 092, 008c merged).
- 2026-10-28 qa-engineer (phase 1; NO `*-verify.sh` executed, per the brief: another task's long driver holds the machine): read the task, umbrella 089,
  part B's `089b-verify.sh` (reference pattern), 087/084 files. Machine state at start (`ps`): `039a-verify.sh`, `064-verify.sh`, `062-verify.sh`, `008a-verify.sh` of other
  worktrees running, which confirms the constraint. Tooling note: `pytest` is NOT installed here (`No module named pytest`); the two test files are run with
  `python3 -m unittest discover -s tests/registry -p <file>` instead (same tests; the repo's own runner is unittest). Recorded as an assumption, see Questions.
  RED commit (next): `docs/tasks/089a1-verify.sh` only (plus this log). The source fixes follow in the FIX commit, so the script exists before the fix (§2c rule 5).
  The script is WRITTEN-BUT-NOT-RUN: every criterion is unproven until phase 2.
