# Task 087: closed scripts 032 and 067 pin `docs/contracts/README.md` sentences on HEAD — re-pin to their own PR ranges

- **Mission:** SITE-V1 (verification integrity) — **Status:** spec-approved (manager, solo gate, 2026-10-26; the 071/084 shape)
- **Repo:** registry. **Agent / model:** qa-engineer (§3.5). **Budget:** small (≤ 1 agent-session)
- **Branch / worktree:** `task/087-repin-032-067-readme` / `~/wt/registry-task-087`, cut from registry `origin/main`
- **Graph:** verification tooling only.

## Source
Final run of task 082 (registry PR #20) on a merge with registry main, 2026-10-26: 082 legitimately edits
`docs/contracts/README.md` ("eight prose documents" → "nine"; "None of the three tasks implements checking logic" → "four"),
and the already-merged `032-verify.sh` (N5, N5b) and `067-verify.sh` pin the old sentences at HEAD — own-change checks on a
moving frame (REVIEW-CHECKLIST item 12). Everything that runs them reddens with them (062, 064, 065, 066, 069, 070, 084).

## Objective
Every check in `032-verify.sh` and `067-verify.sh` that reads `docs/contracts/README.md` (and any other file a later task may
legitimately edit) as evidence of **that task's own change** reads it at the task's pinned FINAL (`git show FINAL:path`), with
BASE/FINAL = the task's merged PR range (merge commit M: BASE = `git merge-base M^1 M^2`, FINAL = `M^2`; find M with
`git log --merges --grep`; 032 may already define pins — reuse them). Live-property checks stay on HEAD; classify each, one line
why, in the log. Check every other closed script for README-sentence pins too and list any found (fix only 032 and 067 here;
book the rest).

## Acceptance criteria — `docs/tasks/087-verify.sh`, whose output the log pastes
1. Red first: in a temp clone, merge `origin/task/082-pipeline-trigger-contract` onto this task's base; the old 032 and 067 fail
   (shown); after the fix both pass on the same merge.
2. Mutations red: each re-pinned check widened back to HEAD; unreachable pins fail, never skip.
3. Quiet machine (`ps` logged; wait until no other `*-verify.sh`), one at a time: every closed script green on HEAD and on the
   merge with 082's branch.
4. Own-change checks of 087-verify.sh on fixed SHAs; passes in a fresh clone.

## File scope
`docs/tasks/032-verify.sh`, `docs/tasks/067-verify.sh` (README-pin checks only), `docs/tasks/087-repin-032-067-readme.md` (log),
`docs/tasks/087-verify.sh` (new). Anything else = stop and report.

## Forbidden
Loosening any check beyond moving an own-change check to its pinned FINAL; pinning a live property; skips.

---
# Task 087 log
- 2026-10-26 manager: written and approved (solo gate) from 082's final-run finding.
