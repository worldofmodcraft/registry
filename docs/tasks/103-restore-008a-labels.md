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
