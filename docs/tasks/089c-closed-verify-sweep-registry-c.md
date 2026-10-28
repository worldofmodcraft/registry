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
- Q1: criterion 5's positive control ("the same merge makes the unfixed script exit non-zero") cannot hold for S1: the unfixed 069 reads the
  BRANCH, not HEAD, so no later merge reddens it; its defect is a silent skip when the branch is deleted (exit 0, "not evaluated", no AC5.3
  verdict). | options: A) red-first = "OLD with the branch deleted exits 0, prints 'not evaluated', has no AC5.3 verdict line" (asserted in
  089c-verify.sh AC1.b, with the branch-present control AC1.a); B) additionally require a non-zero exit, which would need editing the old
  script (forbidden); C) drop criterion 5's positive control for S1 | assumed: A | built on assumption: AC1.b / AC1.e of 089c-verify.sh
- Q2: AC5.3 reachability (criterion 6) shows reachability from `refs/remotes/origin/main`, which exists only in a clone with a remote. | options:
  A) FAIL when that ref is absent (run in a fresh clone; no skip) ; B) fall back to `refs/heads/main` | assumed: A | built on assumption: AC0.4
- Q3: the no-flag and --mutate modes run 069-verify.sh TRUNCATED to its preamble plus AC5 (the S1 check); the complete 069 (default and
  --mutate, hours-scale) is run by the separate `--full` flag, as phase-2 step 3. | options: A) as built; B) always run the complete 069
  (three to four complete runs per mode) | assumed: A | built on assumption: AC1/AC3/AC4 use the truncated copy

---
# Task 089c log  (append-only)
- 2026-10-28 manager (session 14): cut from umbrella 089 and dispatched for phase 1 (no verify runs while 089b's long driver holds the machine);
  base registry main `32c641b` (087, 082, 039b, 092, 008c merged).
- 2026-10-28 qa-engineer (phase 1, started): read the task, umbrella (S1, criteria 1-3, 6, 9, 11, forbidden list), 089b-verify.sh (read-only
  reference), 069-verify.sh. HARD CONSTRAINT kept: no `*-verify.sh` executed (not 069, not 089c, no --mutate); only git read commands,
  `bash -n`, and a throw-away `awk` run over blobs to check the truncation. `ps` at start showed 31 lines matching `verify.sh` (the other task's
  long driver); nothing of mine started.
- 2026-10-28 qa-engineer: **pin derived.** `git ls-remote origin refs/heads/task/064-schema-check-end-anchor` = `5002b4624abf0c09a6a1e1a94856e138ed5775f6`
  (the branch still exists). `git rev-parse 79d5377^2` (79d5377 = "Merge pull request #13 from worldofmodcraft/task/064-schema-check-end-anchor",
  the only such first-parent merge on main) = `5002b4624abf0c09a6a1e1a94856e138ed5775f6`, i.e. the branch tip IS PR #13's FINAL.
  `git merge-base --is-ancestor 5002b4624abf0c09a6a1e1a94856e138ed5775f6 origin/main` -> exit 0 (reachable from main `32c641b`). So no fixture
  blob is needed (umbrella S1). `docs/tasks/034-verify.sh` at the pin is byte-identical to main's (same sha1 6daabb4d...), written as an observation only.
- 2026-10-28 qa-engineer: **fix** (`docs/tasks/069-verify.sh`, +8/-5): `PIN064="5002b46...(40)"` added beside `BASE062`; AC5.3 now reads
  `git show "$PIN064:docs/tasks/034-verify.sh"`; an unreadable pin (commit missing, file missing, empty blob) is
  `FAIL AC5.3 pinned commit <pin> (task 064's FINAL) or its docs/tasks/034-verify.sh cannot be read in this clone`; the "note: ... not evaluated"
  branch is gone. No environment override. Classification of the touched check: AC5.3 is own-change of 064 (the file 064 changed), hence
  pinned. Everything else in 069 (AC1-AC4, AC5.1/5.2 on generated variants, AC7) untouched. `bash -n` OK.
- 2026-10-28 qa-engineer: **089c-verify.sh written, NOT RUN** (399 lines, executable, `bash -n` OK). Modes: no flag (AC0 pin/reachability/no-branch-ref greps
  with positive controls, AC1 red-first with the branch deleted + branch-present control + item-12 later-branch merge, AC3 four bad pins incl.
  `deadbee` + no-skip grep with positive controls, AC11 scope on fixed SHAs), `--mutate` (AC4: pin widened to the branch ref red/green control,
  widened to HEAD red on the later-branch merge, silent skip restored and detected), `--own-only` (AC11), `--full` (AC9: complete 069 default on HEAD and
  on the later-branch merge, then 069 --mutate, one at a time). Every child run is preceded by a quiet-machine wait that logs the `ps` lines
  it saw (stderr). Criteria status: 1 (S1) written-not-run; 2 (pin = `M^2`, no branch read) written-not-run; 3 (deadbee FAIL, 0 skip words, positive
  control) written-not-run; 4 (mutate) written-not-run; 5 (item 12) written-not-run, see Q1; 6 (reachability, deleted branch passes, bad pin fails)
  written-not-run; 9 (quiet machine, complete 069 one at a time) written-not-run; 11 (scope) written-not-run. NOTHING IS DONE UNTIL PHASE 2.

