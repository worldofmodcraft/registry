# Task 101: re-pin `008b1-verify.sh`'s own-change scope check to 008b-1's merged range (it is red on registry main)

- **Mission:** SITE-V1 (verification integrity) — **Status:** spec-approved 2026-10-29 (manager, session 14; Ludwig's decision "A: fixed SHAs only", 2026-10-29)
- **Agent / model:** qa-engineer (model per frontmatter) — **Budget:** small
- **Branch / worktree:** `task/101-repin-008b1-verify` / `~/wt/registry-task-101`, from registry main `dd7da2d`

## Objective
`docs/tasks/008b1-verify.sh` fails on registry main (fresh clone at `dd7da2d`: exit 1, `FAIL no changes since base (broken search)`): its scope check
diffs against the merge-base of HEAD with the current `origin/main`, which is empty after its own merge. Re-pin that check to 008b-1's merged range:
M = `dd7da2d` (merge of registry PR #29), BASE = `git merge-base M^1 M^2`, FINAL = `M^2` (re-derive all three as full 40-character SHAs and record
them). The reference implementation of exactly this change is task 089e for `008c-verify.sh` (branch `origin/task/089e-closed-verify-sweep-registry-e`:
`docs/tasks/089e-verify.sh`, `docs/tasks/008c-verify.sh`, the part file and its review notes) — follow it.

## File scope
`docs/tasks/008b1-verify.sh` (the scope check, its pins and its scope self-test only), `docs/tasks/101-verify.sh` (new), this file. Anything else = stop.

## Acceptance criteria (shipped as `101-verify.sh`; every own-change check of 101-verify.sh itself reads only fixed SHAs — no `..HEAD` scope checks)
1. Red first: the unfixed `008b1-verify.sh` (blob at `dd7da2d`) FAILs on registry main itself and on a later synthetic branch; the fixed one passes both.
2. Pins full SHAs, re-derived from the merge commit and asserted. 3. `deadbee` pins FAIL, never skip (skip-word grep 0 with a positive control).
4. `--mutate`: widening the check back to the merge-base with origin/main (or its right side to HEAD) reddens it, only it; `008b1-verify.sh --mutate` still
   reddens all its existing mutations. 5. Item-12: fixed `008b1-verify.sh` exits 0 on HEAD and on HEAD merged with a later branch.
6. Quiet machine, `ps` logged. 7. Scope: `git diff --name-only` of this task's fixed range = the three files above; the other 008b1 checks byte-identical.

---
# Task 101 log
- 2026-10-29 manager (session 14): created on Ludwig's decision A; dispatched (phase 1 + phase 2, the machine is quiet).
