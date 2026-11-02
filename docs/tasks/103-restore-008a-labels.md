# Task 103: restore 008a-verify.sh's two README check labels (089a1 renamed them; closed script 062 is red on main)

- **Mission:** SITE-V1 (verification integrity) — **Status:** spec-approved 2026-11-02 (manager, session 14; repair of the manager's merge of 089a1, small, solo §2b)
- **Agent / model:** qa-engineer — **Budget:** small
- **Branch / worktree:** `task/103-restore-008a-labels` / `~/wt/registry-task-103`, from registry main `4eca251`

## Objective
Since 089a1 merged (`4eca251`), `062-verify.sh` on registry main exits 1: `FAIL AC6L.008a a check id of 008a-verify.sh that existed at 82fa564 is gone at HEAD`
(the manager reproduced it in a fresh clone of main). 089a1 rewrote the two labels of 008a's README check
(`ok "docs/contracts/README.md points at the pipeline doc"` / `fail "docs/contracts/README.md not updated"`) to include the pin. 062 guards that 008a's check
ids never disappear. Restore both label strings **exactly**; keep 089a1's behaviour (the check reads the README blob at 008a's pinned FINAL; unreadable pin =
FAIL); if the pin detail is wanted in the output, print it as a separate line that is not a check id. Do not touch 062-verify.sh (closed).

## File scope
`docs/tasks/008a-verify.sh` (that one check's lines only), `docs/tasks/103-verify.sh` (new), this file.

## Acceptance criteria (in 103-verify.sh; fixed SHAs only, as decision A requires)
1. Red first: `062-verify.sh` on a clone at `4eca251` FAILs AC6L.008a; on this branch's fixed content commit it passes AC6L.008a (run 062 whole on both, or its
   AC6L section if separable — log which).
2. The two label strings are byte-identical to `82fa564`'s (grep -F on the blob at the fix commit; positive control on `82fa564`).
3. 008a-verify.sh exits 0 on the fix commit; its README check still reads the blob at its pinned FINAL (089a1's mutation for that check still reddens it).
4. Scope: the three files; 008a diff limited to that check's lines.
5. Quiet machine, `ps` logged; `npm ci --prefix tools/dev`, absolute node_modules path for 062.

---
# Task 103 log
- 2026-11-02 manager (session 14): created after reproducing 062 red on main (fresh clone at `4eca251`); dispatched.
- 2026-11-02 qa-engineer: 103-verify.sh committed red-first (FIX unrecorded: AC0 fails).
- 2026-11-03 qa-engineer: executed. Commits: 103-verify.sh red-first (it exits 1: AC0, FIX unrecorded) -> 008a fix `67df935ec7754c48b3ede6ec522305404e4e7cfb`
  (both label strings restored exactly; pinned-blob read and FAIL-on-unreadable-pin kept; the pin is shown on a separate non-check `echo` line without ok/FAIL prefix)
  -> FIX pinned in 103-verify.sh. Fresh non-shallow clone of github.com/worldofmodcraft/registry, `npm ci --prefix tools/dev`, PYTHONDONTWRITEBYTECODE=1,
  absolute node_modules path, `ps` logged (no other verify/pytest/npm process) before each run. 062 run WHOLE in both cases (AC6L is not separated out).
  - 062-verify.sh at 4eca251: exit 1, only `FAIL AC6L.008a a check id of 008a-verify.sh that existed at 82fa564 is gone at HEAD` (1 CHECK FAILED).
  - 008a-verify.sh at head: exit 0. 062-verify.sh at head: exit 0, `PASS AC6L.008a`. 103-verify.sh at head: exit 0, 30 ok, `SUMMARY failed=0`.
  - Own defect: the first 103-verify.sh run at head exited 1 on AC4.4 (my filter rejected a pure comment line of the fix); a test defect, not a production one;
    filter widened to comment lines in baab0e9, rerun exit 0. 103's own `ps` listing shows only 103's own process (self-match), the independent `ps` before each run showed none.
  - 103-verify.sh checks: labels byte-identical to 82fa564 (control on 82fa564 and on 4eca251), pin read from blob (emptying worktree README leaves it green,
    unreadable FINAL reddens exactly that check), scope, 062 whole at both SHAs.
