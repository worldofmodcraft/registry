# Task 069: closed tasks' verify scripts stay correct under concurrency and on later branches (008a, 007a, 062)

- **Mission:** SITE-V1 (verification integrity) — **Status:** spec-approved (manager, solo gate, 2026-10-15, session 10;
  test-artefact maintenance, the same shape as tasks 062 and 067)
- **Repo:** registry. **Agent / model:** qa-engineer / sonnet (changing a closed task's verify script is a test change and
  its own reviewed task, MANAGER.md §3.5). **Budget:** small–medium (≤ 2 agent-sessions)
- **Branch / worktree:** `task/069-closed-verify-maintenance` / `~/wt/registry-task-069`, cut from registry `origin/main`
- **Graph:** verification tooling only; no node or edge.

## Objective
Three defects in closed tasks' verify scripts, all found in session 10, are fixed so that 007b (PR #12) and 064 (PR #13)
can be measured green on their merge result:
1. **008a temp-dir race.** `docs/tasks/008a-verify.sh` lines 36 and 72–73 count every `/tmp/wom008a-*` entry on the
   machine before and after its suite and fail if the count grew. Any concurrent 008a run (another agent, another
   worktree, 062's clones) raises the count, so the check fails without a leak; on 2026-10-15 it reddened `062-verify.sh`
   on 007b's branch and at base `e009ef0` while four 008a runs were in flight (found by statically reading the script and
   watching `ps`; 064's agent saw it pass when re-run alone). After this task the suite runs with `TMPDIR` set to a fresh
   per-run directory (and the script's own stderr file lives there), and the leak check counts only inside it — so it
   still fails on a real leak and no longer on someone else's run.
2. **007a's checks that measure the working tree.** `docs/tasks/007a-verify.sh`'s source-file cap (5 files in
   `tools/registry`) and its file-scope check (`origin/main...HEAD`) are red by construction on any later branch (007b adds
   two files). They are re-based to 007a's own pinned commit range — base = the merge-base of registry PR #10, final =
   the PR's last commit (`git rev-parse <merge commit of #10>^2`) — exactly as task 062 did for 006/008a/032/057
   (062's D-1). `062-verify.sh` gains 007a in its set of closed scripts run on later branches.
3. **062 AC6.034 vs task 064.** `062-verify.sh` AC6.034 requires `034-verify.sh` unchanged since 062's base; task 064
   criterion 5 re-pins 034's C3.3. AC6.034 gets a narrow allowance for exactly that change — the C3.3 call-text line and
   its successor comment naming task 064 — the same way task 067 handled 032 N5b. C3.4 stays fully protected.

## Context to load (exhaustive)
This file; registry `docs/tasks/008a-verify.sh`, `docs/tasks/007a-verify.sh`, `docs/tasks/062-verify.sh`,
`docs/tasks/062-registry-test-maintenance.md` (D-1 and the re-basing pattern), `docs/tasks/067-repin-032-n5b.md`,
`docs/tasks/067-verify.sh`, `tests/pipeline/helpers.py` (the `mkdtemp(prefix="wom008a-")` sites), the 064 branch's
`docs/tasks/034-verify.sh` diff (`git diff origin/main origin/task/064-schema-check-end-anchor -- docs/tasks/034-verify.sh`);
platform `docs/manager/MANAGER.md` §2c, `docs/manager/OPERATIONS.md`, `docs/tasks/043-suite-is-a-shared-resource.md`.

## Acceptance criteria — `docs/tasks/069-verify.sh`, whose output the log pastes
1. **Red first (§2c rule 5), race:** a reproduction that creates a `wom008a-*` entry in the global temp dir while
   `008a-verify.sh` runs is committed before the fix and shown red on that commit; green after.
2. **Leak check still bites:** a mutation that makes one test leak a `wom008a-*` dir inside the per-run `TMPDIR` turns
   `008a-verify.sh` red after the fix (the check cannot have been made unable to fail).
3. **007a on later branches:** on a throw-away branch that adds two files under `tools/registry/` (007b's shape), the old
   `007a-verify.sh` is shown red (red first) and the new one green; a mutation that widens the pinned range to `HEAD`
   reddens it; an unreachable pin fails, never skips.
4. **062 covers 007a:** `062-verify.sh` runs `007a-verify.sh` on HEAD and on a later branch; `--mutate` shows a reddening
   mutation for that addition.
5. **AC6.034 allowance is narrow:** with the 064 branch's `034-verify.sh` change applied, AC6.034 is green; any other
   change to `034-verify.sh` (a mutation that also edits C3.4, and one that edits an unrelated line) is red.
6. **All closed scripts green on HEAD, run sequentially with nothing else running** (state the `ps` check in the log):
   006 (via 062), 007a, 008a, 032, 034, 057, 062 (with `NODE_MODULES_DIR`, or `tools/dev/node_modules` once 066 merges),
   067. And `062-verify.sh` green on the merge of this branch with each of `origin/task/007b-registry-checker-ownership` and
   `origin/task/064-schema-check-end-anchor` (in temp clones; report each result — a red that belongs to 064's open fix
   round is reported, not fixed here).

## File scope (declared)
`docs/tasks/008a-verify.sh`, `docs/tasks/007a-verify.sh`, `docs/tasks/062-verify.sh` (the three changes above only),
`docs/tasks/069-closed-verify-maintenance.md` (log), `docs/tasks/069-verify.sh` (new). Changing any test under `tests/` or
any code under `tools/` = stop and report (the per-run `TMPDIR` is set by the verify script, not by the suite).

## Size
Verify scripts only; excluded from the size counts. Reading list: 10 platform+registry files, at the cap.

## Forbidden here
Removing or loosening any check beyond the three named changes; a skip that yields green; widening AC6.034 beyond 064's
C3.3 line and comment; running suites concurrently with other agents' suites while measuring.

## Dependencies
Before 007b (PR #12) and 064 (PR #13) merge; both rebase/merge `main` after this lands. File-disjoint from 066 except
`062-verify.sh`, which 066 also edits (ajv resolution only): **whichever merges second rebases and re-runs** — the manager
sequences 066 first if it is ready.

---
# Task 069 log
- 2026-10-15 manager (session 10): written and approved (solo gate, SPEC-CHECKLIST 1–8). Sources: 007b's report (007a scope
  and size checks red on its branch; 062 008a reds), the static diagnosis of the 008a race (008a-verify.sh lines 36, 72–73),
  064's report Q2 (062 AC6.034) and its note that 008a passes when re-run alone.
- 2026-10-15 manager: worktree `~/wt/registry-task-069` cut from registry origin/main `ac22c8f`; dispatched. check-log-entry baseline = 2.
- 2026-10-15 qa-engineer: red-first commits (each shown red on its commit, run from the worktree): 8e04c13 (AC1 race: AC1.4/AC1.5 FAIL
  against the old 008a, "suite left 2 wom008a-* temp dir(s)"); d0370d5 (AC3.4, AC4.1, AC4.2 FAIL: old 007a size 7>5 and scope
  "docs/tasks/008a-verify.sh"; 062 had no 007a lines); 46d722b (AC5.1, AC5.2 and all AC5.m* FAIL: helper has no c33 command).
  Fixes: ffa2359 (008a per-run TMPDIR), 727bce2 (007a pinned BASE=e009ef0/FINAL=aaf4260; 062 SCRIPTS_LATER + 007a mutations + c33),
  later 069-verify.sh refinements 08b7649, 7c6041b. 008a messages unchanged, so 062 AC6.008a label comparison stays green.
- 2026-10-15 qa-engineer: coordinator course correction received: 064's C3.3 changed again (tip fc3a524, call text
  `re.search(_ecma_pattern(schema["pattern"]), instance)`, 3-line comment). Re-read `git diff origin/main origin/task/064-...`
  after fetch. The allowance was written as: exactly 1 hunk; removed lines == [old C3.3 call text]; first added line matches
  `re\.search\(.*schema\["pattern"\].*instance.*\)' "$CHECK_FILE"`; 1-8 further added lines, all comments, one naming "task 064".
  So it already accepted this form; 069-verify.sh's embedded variant was updated to the current text and AC5.3 judges the real
  branch file (accepted, fc3a524). Brittleness note: if 064 changes the call text so it no longer contains
  re.search( ... schema["pattern"] ... instance ...), AC6.034 goes red and the regex needs a one-line update.
- 2026-10-15 qa-engineer: criterion 6, sequential, `ps` showed 0 other suite processes before each run (log: /tmp/w069/c6.out). On HEAD 08b7649:
  007a, 008a, 032, 034, 006, 057, 062 all exit 0 (062: 45 PASS 0 FAIL). 062 on merge(HEAD, 007b 9bec938): exit 0, 45 PASS.
  062 on merge(HEAD, 064 fc3a524): exit 0, 45 PASS (AC6.034 green via the allowance). 067-verify.sh exit 1 with NODE_MODULES_DIR:
  AC5.1 "out-of-scope files changed" (it diffs from its base 3c94cf2 to HEAD, red by construction on any later branch, same
  defect class as 007a). Out of this task's file scope; booked below.
- 2026-10-15 qa-engineer: deviation: 062 AC1 reproduces the OLD 008a at BASE062 by design, so its probe-branch inventory
  ("changed,paths") can still pick up "suite" when another 008a runs concurrently (seen once, with 064/066 suites running; green
  when quiet). Not fixed (would loosen AC1); measuring runs were made quiet.
- 2026-10-15 qa-engineer: final 069-verify.sh output (quiet machine, ps others=0) normal: exit 0, ALL CHECKS PASSED (AC1.1-5, AC3.1-4,
  AC3.head/later.007a, AC4.1-3, AC5.1-3). --mutate: ALL CHECKS PASSED (AC5.m1-m7, AC3.m1-m5, AC4.007a.drop-path/bad-pin/restored,
  AC4.m.*, AC2.1 "suite left 16 wom008a-* temp dir(s)"). Full text returned in the report to the manager.

## Questions
- Q1 (for the manager): 067-verify.sh AC5.1 (scope vs 3c94cf2..HEAD) is red on every later branch, including this one. Options:
  A) a follow-up task re-bases it to 067's own PR range (as 062 did) ★; B) accept it red and exclude 067 from "all closed scripts green".
- Q2: 062 AC1 vs concurrent 008a (see deviation above): A) leave, measure quietly ★; B) allow optional "suite" id for 008a in AC1.
- 2026-10-15 qa-engineer: coordinator update applied: 066 merged (198dc98, PR #14; touched 057-verify.sh and 062-verify.sh, ajv
  resolution only). Merged origin/main into this branch (merge commit 82d0aa2, no conflicts, my 062 edits and 066's both kept; no
  force-push). Measured with NODE_MODULES_DIR=/tmp/fc041/node_modules passed explicitly (the argument outranks tools/dev, so no
  npm ci was needed; nothing installed). Re-ran everything on HEAD 82d0aa2 with 0 other suite processes (ps) before each run:
  007a, 008a, 032, 034, 006, 057, 062 exit 0; 062 on merge(HEAD, 007b head a3f04a1, the F1 fix) exit 0, 45 PASS; 062 on
  merge(HEAD, 064 fc3a524) exit 0, 45 PASS; 067 exit 1 only on AC5.1 (see Q1). 069-verify.sh normal and --mutate: ALL CHECKS PASSED.

## Amendment 1 (manager, 2026-10-15, session 10)
- **Scope extended:** `docs/tasks/067-verify.sh` — its AC5.1 scope check measures `3c94cf2..HEAD` and is red on every later branch (registry `main` itself has been red on it since task 066 merged, `198dc98`). Re-base AC5.1 to 067's own pinned PR #11 range (base = merge-base, final = `<merge commit of #11>^2`), exactly as for 007a; red first (old script red on a later branch), widen-to-HEAD and unreachable-pin mutations red; `062-verify.sh` runs 067 on HEAD and a later branch (if not already).
- **Q1:** A (above, folded into this task instead of a new one). **Q2:** A — 062 AC1 keeps running the old 008a at its base by design; measurements are taken on a quiet machine; no loosening.
- **Trailer deviation:** accepted as logged; pushed commits stay unchanged.
- 2026-10-15 manager: amendment 1 appended; sent back to the agent. Log baseline recounted below.
- 2026-10-15 qa-engineer (amendment 1): 067-verify.sh AC5.1 re-based to PR #11's range, BASE=3c94cf2 (fork point, also AC1's frame),
  FINAL=06c721c (`git rev-parse ac22c8f^2`); unreachable pin is a FAIL naming the commit. Red first: 8e651f2 added 069-verify.sh AC7;
  run on that commit: AC7.1-3 PASS (pins correct, old 067 red on a later branch: "FAIL  AC5.1 out-of-scope files changed: .gitignore
  docs/tasks/007a-verify.sh ..."), AC7.4 FAIL (067 unchanged, exit 1). Fix: 403280f. Decision: 062-verify.sh does NOT run 067, because
  067-verify.sh AC3.2 runs 062 (a cycle); 067 is covered by 069-verify.sh AC7 and criterion 6 instead (deviation from "if not already").
  Q2 answered A: no loosening. Quiet machine (ps others=0 before every run), HEAD 403280f, 064 tip 942211c, 007b tip a3f04a1:
  criterion 6 (/tmp/w069/c6c.out): 007a, 008a, 032, 034, 067, 006, 057, 062 all exit 0 (062: 45 PASS 0 FAIL); 062 on merge with 007b:
  exit 0, 45 PASS; 062 on merge with 064: exit 0, 45 PASS. 069-verify.sh normal: ALL CHECKS PASSED (incl. AC7.1-4); --mutate: ALL CHECKS
  PASSED, incl. "AC7.m1 range widened to HEAD turns red", "AC7.m2 ... FAIL  AC5.1 pinned commit deadbee is not an ancestor of HEAD",
  "AC7.m3 ... FAIL  P0 base deadbee is reachable".
