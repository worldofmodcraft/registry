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
- 2026-10-17 qa-engineer (task branch `task/071-repin-007b-verify`): **classification of every check in 007b-verify.sh** (spec Objective). Own-change = describes 007b's PR #12 change; live = property of the tree as it stands.

  | Check | Verdict | One line why |
  |---|---|---|
  | file-scope check (was `git diff --name-only origin/main...HEAD`, line ~105) | RE-PIN to `BASE007B..FINAL007B` | the claim "007b touched only its declared files" is about 007b's own change; any later task (064 edits `schema.py`, `.gitignore`) made it red |
  | "007a modules unchanged" (was `origin/main...HEAD -- tools/registry`, line ~107) | RE-PIN | same: it is 007b's claim about its own diff |
  | size cap "<= 2 ownership source files" (was `ls tools/registry/ownership*.py`, HEAD tree) | RE-PIN to `ls-tree FINAL007B` | the cap is 007b's spec Size claim; a later task adding an `ownership_*.py` is not 007b's growth (007a-verify.sh pins its size the same way) |
  | pin reachability of both pins (new) | new | an unreachable pin FAILS naming the commit; scope and 007a-unchanged then also FAIL (never skip) |
  | git/python3 present (2); whole registry suite; fresh-clone suite; 15 `crit` acceptance lines (umbrella 4/5/6/9/10/14, B1-B6, I1-I8, R1-R10, CLI) | LIVE (19) | suite behaviour of the tree as it stands; later tasks must keep 007b's tests green |
  | no real account id; no I/O import in ownership.py; no actor/credential reach in ownership*.py | LIVE (3) | content properties of the ownership source at HEAD |
  | CLI `--help` documents I8 / exit codes / R11 default (3); CLI real exit codes owner/stranger/usage = 0 1 2 | LIVE (4) | behaviour of the built CLI |
  | README names ownership checker as built, task 039 owed; README no longer says "still to come" | LIVE (2) | content of the README as it stands (this is why 007b is not "README unchanged") |
  | `--mutate`: clean tree precondition, mutation table floor 45, every mutation red | LIVE (3) | precondition and live properties of the mutation runner |

  Counts: 3 RE-PIN, 1 new, 31 LIVE (28 default mode + 3 `--mutate`). Pins: `BASE007B="fb76ee5"` = `git merge-base 70cedca^1 70cedca^2`, `FINAL007B="17555d9"` = `70cedca^2` (verified by 071-verify.sh AC0). The script no longer reads `origin/main` at all (AC0.3), so a clone without `origin/main` no longer fails the scope check.
- 2026-10-17 qa-engineer: **red first.** Commit `7ceedaa` (071-verify.sh only, before the fix). Quiet machine (`ps aux | grep -E "verify.sh|unittest"` empty). Output on `7ceedaa`, exit 7:
  ```
  FAIL  AC0.1 cannot read BASE007B / FINAL007B from docs/tasks/007b-verify.sh (a search that finds nothing is broken)
  FAIL  AC0.3 docs/tasks/007b-verify.sh still refers to origin/main outside comments: 104:if git rev-parse -q --verify origin/main ...
  PASS  AC1.1 the OLD 007b-verify.sh (from 70cedca) exits 3 on the later branch: scope, 007a-unchanged and size checks red
  FAIL  AC1.2 the current script exit 3 on the later branch: FAIL  size: 3 ownership source files (cap 2)|FAIL  files outside the declared scope: .gitignore|FAIL  007a modules changed: tools/registry/schema.py|
  FAIL  AC1.3 (x4) no passing pinned-range / size line in the current script's output
  7 CHECK(S) FAILED
  ```
- 2026-10-17 qa-engineer: **fix** commit `2b303e3` (007b-verify.sh pinned; `CLOSED` in 070-verify.sh gains 007b). `docs/tasks/071-verify.sh`, exit 0:
  ```
  PASS  AC0.1 BASE007B=fb76ee5 is PR #12's fork point (git merge-base 70cedca^1 70cedca^2)
  PASS  AC0.2 FINAL007B=17555d9 is the last commit of PR #12 (git rev-parse 70cedca^2)
  PASS  AC0.3 docs/tasks/007b-verify.sh no longer depends on origin/main (outside comments)
  PASS  AC1.1 the OLD 007b-verify.sh (from 70cedca) exits 3 on the later branch: scope, 007a-unchanged and size checks red
  PASS  AC1.2 the current 007b-verify.sh exits 0 on the later branch
  PASS  AC1.3 (x4) the current script reports passing pinned-reachable / pinned-range scope / 007a-untouched / size lines
  ALL CHECKS PASSED
  ```
  `docs/tasks/071-verify.sh --mutate`, exit 0:
  ```
  PASS  AC2.m1 FINAL007B widened to HEAD turns red: exit 3, FAIL  files outside the declared scope: .gitignore
  PASS  AC2.m2 the size pin widened to HEAD turns red: exit 1, FAIL  size: 3 ownership source files at 17555d9 (cap 2)
  PASS  AC2.m3 unreachable BASE007B pin must FAIL, never skip turns red: exit 4, FAIL  pinned commit deadbee is not reachable from HEAD ...
  PASS  AC2.m4 unreachable FINAL007B pin must FAIL, never skip turns red: exit 4, FAIL  pinned commit deadbee is not reachable from HEAD ...
  ```
- 2026-10-17 qa-engineer: **criterion 3, closed scripts on HEAD (`2b303e3`), sequential, one at a time, quiet machine (ps empty before the batch; the runner logged any foreign verify/unittest process before each script, none).** Exit codes: 007a 0, 007b 0, 008a 0, 032 0, 034 0, 057 0, 062 0 (runs 006), 066 0, 067 0, 069 0, 070 0 (now includes 007b in its later-branch run), 071 0. Final lines: 007a/007b/008a `SUMMARY failed=0`; 034/062/066/069/070/071 `ALL CHECKS PASSED`; 057 `RESULT: 0 check(s) failed`; 067 `ALL CHECKS PASSED`; 032 exit 0 (its advisory block is informational by design).
- 2026-10-17 qa-engineer: **criterion 3, merge with 064.** `git fetch origin` against GitHub; `git ls-remote origin refs/heads/task/064-schema-check-end-anchor` = `69f74a1d0c34367757814daaa7c019be08d13481` = `origin/task/064-schema-check-end-anchor` (current tip). Throw-away clone of this branch, merged with that tip (merge `9934ef5`, clean, `schema.py` +68/-: the edit that used to break 007b). Quiet machine, one script at a time: `007b-verify.sh` exit 0 (`ok pinned commit fb76ee5 is reachable`, `ok size: 2 ownership source files at 17555d9`, `ok changed files in the pinned range fb76ee5..17555d9 all inside the declared scope`, `ok 007a's modules are untouched in the pinned range`, `SUMMARY failed=0`); `062-verify.sh` exit 0 (`ALL CHECKS PASSED`, 52 PASS lines).
- 2026-10-17 qa-engineer: scope note: 070-verify.sh header comment still says "ten closed scripts" (closed-list-only scope; not edited). Findings: none against production code.
- 2026-10-17 manager: review PASS (static). Merge gate on the branch (contains main 70cedca), fresh GitHub clone, quiet machine, sequential: 007b, 007a, 008a (ran=114), 032 failed=0; 034, 057, 062, 066, 067, 069, 070, 071 ALL CHECKS PASSED / 0 failed. Merged (prerequisite of 064 in the chain Ludwig approved; reviewed test-maintenance change).
