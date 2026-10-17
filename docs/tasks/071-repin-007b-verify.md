# Task 071: `007b-verify.sh` measures 007b's own change on its pinned range (it is a closed task now)

- **Mission:** SITE-V1 (verification integrity) — **Status:** spec-approved (manager, solo gate, 2026-10-17; the 069/070 shape)
- **Repo:** registry. **Agent / model:** qa-engineer / sonnet (§3.5). **Budget:** small (≤ 1 agent-session)
- **Branch / worktree:** `task/071-repin-007b-verify` / `~/wt/registry-task-071`, cut from registry `origin/main` (`70cedca`)
- **Graph:** verification tooling only.

## Objective
007b merged as registry PR #12 (`70cedca`) and is now a closed task. Its verify script's file-scope check
(`git diff origin/main...HEAD`, ~lines 104-107) and its "007a modules unchanged" check measure HEAD, so task 064 (which
legitimately edits `tools/registry/schema.py`) makes `007b-verify.sh` exit 2. After this task those own-change checks
measure 007b's PR range — BASE = `git merge-base 70cedca^1 70cedca^2`, FINAL = `70cedca^2` — exactly as task 070 did for
067/062, and any live-property check in 007b-verify stays live (classify each, one line why, in the log). 007b is added to
`070-verify.sh`'s closed list (later-branch run) so the class cannot return for it.

## Acceptance criteria — `docs/tasks/071-verify.sh`, whose output the log pastes
1. Red first: on a throw-away later branch that edits `tools/registry/schema.py` and `.gitignore`, the old
   `007b-verify.sh` fails (shown on a commit before the fix); after the fix it passes.
2. Mutations red: range widened back to HEAD; unreachable BASE and FINAL pins fail, never skip.
3. Quiet machine (`ps` logged), one script at a time: every closed script green on HEAD (006 via 062, 007a, 007b, 008a,
   032, 034, 057, 062, 066, 067, 069, 070); `007b-verify.sh` and `062-verify.sh` green on the merge with
   `origin/task/064-schema-check-end-anchor` (fetched from GitHub, current tip).

## File scope
`docs/tasks/007b-verify.sh`, `docs/tasks/070-verify.sh` (closed list only), `docs/tasks/071-repin-007b-verify.md` (log),
`docs/tasks/071-verify.sh` (new). Anything else = stop and report.

## Forbidden
Loosening any check beyond moving an own-change check to the pinned range; pinning a live-property check; skips.

---
# Task 071 log
- 2026-10-17 manager: written and approved (solo gate). Source: 064's R1 report (007b-verify exit 2 on 064's branch).
