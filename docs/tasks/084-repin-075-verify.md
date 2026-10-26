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
- 2026-10-26 qa-engineer (task branch `task/084-repin-075-verify`, cut from `4356583`): **pins.** `git merge-base 4356583^1 4356583^2` = `79d5377` (= the script's existing `BASE`, so BASE did not change), `git rev-parse 4356583^2` = `7d91a3d` (new `FINAL=7d91a3d`). Both resolve (`cat-file -e`), verified by 084-verify.sh AC0.1/AC0.2.
- 2026-10-26 qa-engineer: **classification of every check in 075-verify.sh** (spec Objective). Own-change = describes 075's PR #18 change; live = property of the tree as it stands.

  | Check | Verdict | One line why |
  |---|---|---|
  | `out-of-scope files in base..HEAD` (was `diff --name-only "$BASE" HEAD`, line 47) | RE-PIN to `BASE..FINAL` | the claim "075 touched only its declared files" is about 075's own diff; a later task (065 edits `append-only.rules.md`, `entry.schema.json`, tests) made it red |
  | pins exist (BASE, RED, FIX) | pinned already; FINAL added | SHAs, not a frame |
  | RED parent = BASE; FIX follows RED; red commit touches only `test_ownership.py`; fix commit stays in scope (`BASE..RED`, `RED..FIX`) | pinned already (own-change on fixed SHAs) | explicit SHAs, never HEAD |
  | FIX is an ancestor of HEAD | LIVE (unchanged) | history reachability of the fix on the current line; stays true for any descendant |
  | new: FIX is an ancestor of FINAL | new | ties the pinned range to the fix commit |
  | new: scope diff failing or empty (unreachable pin) | new | the diff is no longer allowed to error into an empty "bad" list: it FAILS naming the pins (never skip) |
  | red clone: ownership tests fail on RED, pass on FIX | pinned already | tests run at fixed commits |
  | AC2 at HEAD: eleven named R11 cases + ownership test file + full `tests/registry` suite | LIVE (13) | behaviour of the checker as it stands; later tasks must keep 075's cases green |
  | AC3: the three b7 mutations red at HEAD; mutation named in the list | LIVE (2) | live property of the mutation runner |
  | AC4: contract text of `contracts/ownership.md` (R11 sentence, ADR-0041, R3/R7/R11/Attempt 8/9/table row) | LIVE (1) | content of the contract as it stands: a later edit that unsays R11 should turn it red |
  | 032-verify.sh exits 0 on HEAD | LIVE (1) | the ownership contract's own verifier at HEAD |

  Counts: 1 RE-PIN, 2 new, 1 FINAL pin added, 17 LIVE, the rest already pinned. Nothing live was pinned. Also: `075-verify.sh` header gained a comment; the success line for the scope check now reads `pinned range 79d5377..7d91a3d touches only ...`.
- 2026-10-26 qa-engineer: **machine state.** Another agent's `039a-verify.sh` chain (pid 2045613, running 064 -> 070 -> 062/067/069/008a/007a ... nested) kept the machine busy from 00:49 UTC; I polled `ps -eo args | grep -E 'docs/tasks/.*-verify\.sh'` every 10 s in ten-minute rounds (00:49-03:05 UTC; counts seen 5-12, e.g. at 01:39 `039a, 064, 062, 067, 070`; at 02:28 `039a, 007b, 070`) and ran nothing until it showed 0 (03:05 UTC). No verify script of mine overlapped any other. `npm ci` in `tools/dev` of this worktree (the 064 node_modules path did not exist; 065's did, not used).
- 2026-10-26 qa-engineer: **red first** (AC1). Commit `0932119` (084-verify.sh + this task file only; 075-verify.sh unfixed), ps count 0, exit 8, `PYTHONDONTWRITEBYTECODE=1`:
  ```
  == AC0 -- the pins in 075-verify.sh are PR #18's own fork point and last commit ==
  FAIL  AC0.1 cannot read BASE / FINAL from docs/tasks/075-verify.sh (a search that finds nothing is broken)
  FAIL  AC0.3 docs/tasks/075-verify.sh still measures BASE..HEAD outside comments: 47:bad="$(G diff --name-only "$BASE" HEAD | grep -v -E "$allowed")"|
  FAIL  AC0.4 docs/tasks/075-verify.sh has no "$BASE" "$FINAL" diff
  == AC1 -- on a later branch (append-only.rules.md + schema.py edited) the OLD script fails its scope check, the new one passes ==
  FAIL  AC1.1 the OLD script did not fail as expected on the later branch (exit 1): FAIL  out-of-scope files in base..HEAD: contracts/append-only.rules.md|
  FAIL  AC1.2 the current script exit 1 on the later branch: FAIL  out-of-scope files in base..HEAD: contracts/append-only.rules.md|
  PASS  AC1.3 the current script reports a passing 'pin .* exists' line
  FAIL  AC1.3 no passing 'range .* touches only the task' line in the current script's output
  FAIL  AC1.3 no passing 'ALL CHECKS PASSED' line in the current script's output
  == AC4 -- 084's own change, measured on fixed SHAs (never HEAD) ==
  FAIL  AC4.0 the 084 red/fix SHAs are not pinned yet
  == RESULT ==
  8 CHECK(S) FAILED
  ```
  Disclosure: AC1.1 failed on `0932119` for a defect in the red script itself (it demanded `grep -x` on a path that sits on the FAIL line of the multi-line message), not only for the missing fix. The old script did fail its scope check there (`FAIL  out-of-scope files in base..HEAD: contracts/append-only.rules.md`); the assertion was corrected in the commit that pins the SHAs. AC0.1, AC0.3, AC0.4, AC1.2, AC1.3 (x2) and AC4.0 are red for the genuine reason (no pinned range).
- 2026-10-26 qa-engineer: **fix** commit `ec3f258` (075-verify.sh re-pinned; `CLOSED` in 070-verify.sh gains 075; nothing else). `docs/tasks/084-verify.sh` on the final commit, ps count 0, exit 0:
  ```
  == AC0 -- the pins in 075-verify.sh are PR #18's own fork point and last commit ==
  PASS  AC0.1 BASE=79d5377 is PR #18's fork point (git merge-base 4356583^1 4356583^2)
  PASS  AC0.2 FINAL=7d91a3d is the last commit of PR #18 (git rev-parse 4356583^2)
  PASS  AC0.3 docs/tasks/075-verify.sh no longer diffs the BASE against HEAD (outside comments)
  PASS  AC0.4 docs/tasks/075-verify.sh diffs "$BASE" "$FINAL"
  == AC1 -- on a later branch (append-only.rules.md + schema.py edited) the OLD script fails its scope check, the new one passes ==
  PASS  AC1.1 the OLD 075-verify.sh (from 4356583) exits 1 on the later branch: scope check red, naming both files
  PASS  AC1.2 the current 075-verify.sh exits 0 on the later branch
  PASS  AC1.3 the current script reports a passing 'pin .* exists' line
  PASS  AC1.3 the current script reports a passing 'range .* touches only the task' line
  PASS  AC1.3 the current script reports a passing 'ALL CHECKS PASSED' line
  == AC4 -- 084's own change, measured on fixed SHAs (never HEAD) ==
  PASS  AC4.1 pin 4356583 exists
  PASS  AC4.1 pin 0932119 exists
  PASS  AC4.1 pin ec3f258 exists
  PASS  AC4.2 the red commit's parent is the base
  PASS  AC4.3 the fix commit follows the red commit directly
  PASS  AC4.4 the fix commit is an ancestor of HEAD
  PASS  AC4.5 the red commit touches only 084-verify.sh and the task file
  PASS  AC4.6 the fix commit touches only 075-verify.sh and 070-verify.sh
  PASS  AC4.7 in 070-verify.sh only the CLOSED= line changed
  PASS  AC4.8 070-verify.sh's CLOSED list gains 075
  == RESULT ==
  ALL CHECKS PASSED
  ```
  `docs/tasks/084-verify.sh --mutate`, ps count 0, exit 0:
  ```
  == AC2 mutations (a throw-away later branch; each mutation is committed in the clone, run, and reverted) ==
  PASS  AC2.m1 FINAL widened to HEAD (the later branch's edits come into range) turns red: exit 1, FAIL  out-of-scope files in pinned range 79d5377..HEAD: contracts/append-only.rules.md
  PASS  AC2.m2 the scope check's range text widened back to BASE..HEAD turns red: exit 1, FAIL  out-of-scope files in pinned range 79d5377..7d91a3d: contracts/append-only.rules.md
  PASS  AC2.m3 unreachable BASE pin must FAIL, never skip turns red: exit 4, FAIL  pin deadbee does not exist
  PASS  AC2.m4 unreachable FINAL pin must FAIL, never skip turns red: exit 3, FAIL  pin deadbee does not exist
  == RESULT ==
  ALL CHECKS PASSED
  ```
- 2026-10-26 qa-engineer: **criterion 3, closed scripts on HEAD (`ec3f258` + the pin commit), one at a time, a runner waited for ps count 0 before each (log: every start line said `ps count 0`), `env -u WOM_NODE_MODULES PYTHONDONTWRITEBYTECODE=1`, from the worktree root.** Exit codes: 006 0, 007a 0, 007b 0, 008a 0, 032 0, 034 0, 057 0, 062 0, 064 0, 066 0, 067 0, 069 0, 071 0, 075 0, 070 0 (now runs 075 on its later branch: `PASS  AC2.075 075-verify.sh exits 0 on the later branch`), 084 0. Final lines: 007a/007b/008a `SUMMARY failed=0`; 057 `0 check(s) failed`; all others `ALL CHECKS PASSED`.
- 2026-10-26 qa-engineer: **criterion 3, merge with 065.** `git fetch origin` against GitHub; `git ls-remote origin refs/heads/task/065-entry-schema-key-id` = `e87498b47eced6fe388ec798ce31fbb6db09c16f` = `origin/task/065-entry-schema-key-id` (current tip). Throw-away clone of this branch, merged with that tip (clean, merge `9c7b05b`; 065 edits `contracts/append-only.rules.md`, `entry.schema.json`, `057-corpus.py`, tests...). ps count 0, `075-verify.sh` exit 0: `PASS  pinned range 79d5377..7d91a3d touches only the task's declared file scope`, `ALL CHECKS PASSED`. The OLD script (from `4356583`) on the same merge: exit 1, `FAIL  out-of-scope files in base..HEAD` listing 065's files (the defect this task removes).
- 2026-10-26 qa-engineer: **classification, own-change vs live (summary for the manager).** Own-change (re-pinned): 1 (the declared-file-scope check). Live (left on HEAD): 17, plus the FIX-is-ancestor-of-HEAD check (R11 cases, ownership file, full suite, b7 mutations, contract text, 032-verify). Pinned before this task: the red/fix commit checks. In 084-verify.sh: AC0/AC1/AC2 are properties of 075-verify.sh at HEAD (live by nature) and AC4 (084's own change) is on fixed SHAs `4356583`/`0932119`/`ec3f258` (item 12).
- 2026-10-26 qa-engineer: findings: none against production code. Observation: 070-verify.sh's header still says "ten closed scripts" (closed-list-only scope, not edited); 070's `CLOSED` list gained 075 only.
- 2026-10-26 qa-engineer: **fresh clone (REVIEW-CHECKLIST item 8).** `git clone` of this branch at the log commit, ps count 0, `PYTHONDONTWRITEBYTECODE=1 bash docs/tasks/084-verify.sh` exit 0 (`ALL CHECKS PASSED`, AC0-AC4 all PASS).
