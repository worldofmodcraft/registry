# Task 084: `075-verify.sh` measures 075's own change on its pinned range (it is a closed task)

- **Mission:** SITE-V1 (verification integrity) — **Status:** spec-approved (manager, solo gate, 2026-10-26 night; the 071 shape)
- **Repo:** registry. **Agent / model:** qa-engineer (§3.5). **Budget:** small (≤ 1 agent-session)
- **Branch / worktree:** `task/084-repin-075-verify` / `~/wt/registry-task-084`, cut from registry `origin/main` (`4356583`)
- **Graph:** verification tooling only.

## Source
Task 065 (registry PR #19) report: `075-verify.sh` line ~47 checks `BASE..HEAD` (a moving frame, REVIEW-CHECKLIST item 12) and
turns red as soon as a later branch touches `contracts/append-only.rules.md`, which 065's spec orders. 075 merged as registry PR
#18 (`4356583`) before item 12 existed. Choice C25 (mission log).

## Objective
Every own-change check in `075-verify.sh` measures 075's PR range — BASE = `git merge-base 4356583^1 4356583^2`, FINAL =
`4356583^2` (verify both resolve; record them) — exactly as 071 did for 007b; live-property checks stay on HEAD (classify each,
one line why, in the log). 075 is added to `070-verify.sh`'s closed list (later-branch run) if 070's list is the closed-list
mechanism on registry main.

## Acceptance criteria — `docs/tasks/084-verify.sh`, whose output the log pastes
1. Red first: on a throw-away later branch that edits `contracts/append-only.rules.md` and `tools/registry/schema.py`, the old
   `075-verify.sh` fails (shown on a commit before the fix); after the fix it passes.
2. Mutations red: range widened back to HEAD; unreachable BASE and FINAL pins fail, never skip.
3. Quiet machine (`ps` logged; wait for no other `*-verify.sh`), one script at a time: every closed script green on HEAD;
   `075-verify.sh` green on the merge with `origin/task/065-entry-schema-key-id` (fetched from GitHub, current tip).
4. 084-verify.sh's own-change checks on fixed SHAs (item 12); passes in a fresh clone (item 8).

## File scope
`docs/tasks/075-verify.sh`, `docs/tasks/070-verify.sh` (closed list only), `docs/tasks/084-repin-075-verify.md` (log),
`docs/tasks/084-verify.sh` (new). Anything else = stop and report.

## Forbidden
Loosening any check beyond moving an own-change check to the pinned range; pinning a live-property check; skips.

---
# Task 084 log
- 2026-10-26 manager (session 11 night): written and approved (solo gate). Source: 065's report.
