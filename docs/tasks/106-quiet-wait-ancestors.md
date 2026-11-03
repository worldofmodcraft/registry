# Task 106: 089a1-verify.sh and 089a2-verify.sh must not count their own ancestors (039a deadlocks on registry main)

- **Mission:** SITE-V1 (verification integrity) — **Status:** spec-approved 2026-11-03 (manager, session 14; repair of two scripts the manager merged; small, solo §2b)
- **Agent / model:** qa-engineer — **Budget:** small (plus one whole 039a run, hours)
- **Branch / worktree:** `task/106-quiet-wait-ancestors` / `~/wt/registry-task-106`, from registry main `2939bef`

## Objective
A whole `039a-verify.sh` on registry main (2026-11-03, manager) hung ~9 h inside its child `089a1-verify.sh`: 089a1's `others()` (line ~119:
`ps -eo pid,args | grep -E '[0-9A-Za-z]+-verify\.sh' | grep -v -e '089a1-verify\.sh' -e 'grep -E'`) counts its parent `039a-verify.sh` as another verify run, waits 6 h,
times out and repeats in its nested run. `089a2-verify.sh`'s `others_list()` has the same shape (excludes only its own name). 089b, 089c and 089e already exclude
their ancestor chain and pass inside 039a. Fix both scripts: exclude this process, its descendants and its ancestors by PID/PPID (089e's `others()` shape:
`git show HEAD:docs/tasks/089e-verify.sh`); an unrelated, independently started verify run must still count as "not quiet". Change only those functions.

## File scope
`docs/tasks/089a1-verify.sh` and `docs/tasks/089a2-verify.sh` (the quiet-wait function only), `docs/tasks/106-verify.sh` (new), this file.

## Acceptance criteria (106-verify.sh; fixed SHAs only)
1. Red first: each OLD script (blob at `2939bef`), started as a child of a stub parent process whose command line contains `docs/tasks/zz-verify.sh`, reports
   not-quiet (shown with a short, bounded wait or by calling the extracted function); each NEW script reports quiet in the same setup.
2. Control: with an unrelated sibling process whose command line contains `docs/tasks/yy-verify.sh` (not an ancestor), the NEW function reports not-quiet.
3. The scripts' own checks are otherwise unchanged: diff limited to the quiet-wait function; `089a1-verify.sh --own-only` and `089a2-verify.sh --own-only` exit 0.
4. The whole standalone `039a-verify.sh` on this branch exits 0 (npm ci, absolute node_modules), with no child waiting on its parent — the real proof.
5. Quiet machine, `ps` logged.

---
# Task 106 log
- 2026-11-03 manager (session 14): created after the hung 039a on main (stopped by the manager with TaskStop).
- 2026-11-03/04 qa-engineer (phases 1+2): commits 41c1b06 (106-verify.sh, red first: OLD predicates list the ancestor zz-verify.sh, NEW not pinned -> 7 FAIL), f10a00a (fix: 089a1 `others()` and 089a2 `others_list()` now use 089e's PID/PPID shape; diff limited to those two functions, checked by AC3), b8fce76 (PIN_FIX=f10a00a recorded). Fresh non-shallow clone at b8fce76, `npm ci --prefix tools/dev`, absolute node_modules, PYTHONDONTWRITEBYTECODE=1, `ps` showed no verify/npm/node/pytest process before each run.
  - `106-verify.sh`: exit 0 (8 checks: AC1 OLD red x2 / NEW quiet x2, AC2 control yy-verify.sh listed x2, AC3 x2).
  - `089a1-verify.sh --own-only`: exit 0. `089a2-verify.sh --own-only`: exit 0.
  - whole standalone `039a-verify.sh <NM>`: exit 0, ALL CHECKS PASSED; AC12 children (one at a time) all exit 0 on HEAD: 006 007a 007b 008a 008b1 008c 032 034 039b(--no-closed) 057 062 064 065 066 067 069 070 071 075 082 084 087 089a1 089a2 089b 089c 089d 089e 092 101 103 106. No child waited on its parent; the run finished in under the 7 h cap (spanned the date change).
  - Note: a second concurrent run of 089a1/089a2 now counts as "other" (089e shape); previously excluded by name.
