# Task 089e: registry closed scripts — part E (008c-verify.sh own-change scope check re-pinned to 008c's merged range)

- **Mission:** SITE-V1 (verification integrity) — **Status:** review 2026-10-29 (phase 2 green; was in-progress 2026-10-28 (cut from umbrella 089 at dispatch, session 14; umbrella spec-approved 2026-10-26, parts per Q5 ★ A; part E cut by the manager in session 14 from the finding booked in the umbrella log (094 spec review), spec-approved solo under MANAGER.md §2b as a small, mechanical one-file task of the umbrella pattern)
- **Agent / model:** qa-engineer (model per frontmatter) — **Budget:** small (one agent-session)
- **Branch / worktree:** `task/089e-closed-verify-sweep-registry-e` / `~/wt/registry-task-089e`, from registry main `32c641b`
- **Umbrella (authoritative for findings, pins, criteria, forbidden list, Q1-Q6):** `docs/tasks/089-closed-verify-sweep-registry.md` (copied
  into this branch from platform main `4321d07`; read-only here — do not edit it).

## Scope of this part
Source files: `docs/tasks/008c-verify.sh` (the own-change scope check and its pins only) (1). New: `docs/tasks/089e-verify.sh`. Log: this file. Anything else = stop and report.

## Acceptance criteria
Re-pin `008c-verify.sh`'s own-change scope check from "merge-base with current origin/main" to 008c's merged range: BASE = `git merge-base M^1 M^2`, FINAL = `M^2`, M = `32c641b` (the merge of registry PR #27; the agent re-derives all three as full 40-character SHAs and records them). Criteria, mirroring the umbrella 1-5, 9, 11 for this one check: (1) red first: the unfixed script FAILs on registry main (observed "no changes since base") and on a later synthetic branch that touches another file; the fixed one passes both; (2) pins are full SHAs, recomputed and asserted in `089e-verify.sh`; (3) a `deadbee` pin is FAIL, never skip; (4) `--mutate`: widening the check back to the merge-base with origin/main reddens it, only it; the existing 008c mutations still all go red; (5) item-12 control: fixed `008c-verify.sh` exits 0 on HEAD and on a merge with a later synthetic branch; (9) quiet machine; (11) scope: only `008c-verify.sh` (that check and its pins), `089e-verify.sh`, this file. Shipped as `docs/tasks/089e-verify.sh`. Quiet machine (criterion 9) is mandatory: one script at a time, `ps` logged before each run.
Same pattern as part B (`origin/task/089b-closed-verify-sweep-registry-b`, file `docs/tasks/089b-verify.sh`) and the 084/087 reference pattern.

## Questions  (agent-maintained; see MANAGER.md 8b)
- Q1: how the scope self-test proves the fix without a main ref | options: A) keep `scope_violations` exercising throwaway repos, with PIN_BASE/PIN_FINAL assigned INSIDE each scenario's subshell (a script-internal assignment, no environment override); B) pass base/final as function arguments; C) drop the self-test and rely on 089e-verify.sh | assumed: A (smallest diff to the existing scenarios A-D, keeps every assertion; the live check and the self-test call the same function) | built on assumption: the scenarios in `008c-verify.sh` `scope_selftest`
- Q2: 089e-verify.sh's own-change pins E_FIX/E_FINAL/E_TIP | options: A) FIX = FINAL = the one content commit (the only commit touching 008c-verify.sh), TIP = the same commit, pin commit changes only the three pin lines of 089e-verify.sh, later commits only the task file (asserted by AC11.5); B) a separate red commit as in 089b | assumed: A (there is no red commit to pin: the OLD script is the blob at M, which is registry main) | built on assumption: AC11 of `089e-verify.sh`
- Q3: the umbrella copy in the branch is outside the part's declared scope | options: A) allow it in AC11 as the cut copy-in only (one commit, before the fix, unchanged by 089e); B) add it to this part's scope list; C) drop it from the branch before merge | assumed: A | built on assumption: AC11.4/4c of `089e-verify.sh`

---
# Task 089e log  (append-only)
- 2026-10-28 manager (session 14): cut from umbrella 089 and dispatched for phase 1 (no verify runs while 089b's long driver holds the machine);
  base registry main `32c641b` (087, 082, 039b, 092, 008c merged).
- 2026-10-28 qa-engineer (phase 1, session 14): re-derived the pins from git (read-only): M = `32c641b5f56139a86c820f0b16d522c0f991d207`
  (`git log --merges --first-parent --grep='Merge pull request #27 ...'` on this branch returns exactly it); BASE = `git merge-base M^1 M^2` =
  `e2f7fe383d7b2231e1d37a73e474bca7ed56af46` (= registry main when 008c was cut and the base of 089e's frame M^1); FINAL = `M^2` =
  `7810e70af50d7e2ebae1e53dccba37be1095afe7`. `git diff --name-only BASE FINAL` = build-pipeline.md, 008c task file, 008c-verify.sh,
  test_write_back.py, write_back.py: all five inside 008c's SCOPE_RE (so the fixed check is green on M by construction). git 2.53.0.
- 2026-10-28 qa-engineer: PHASE 1 HARD CONSTRAINT observed: NO `*-verify.sh` was executed (not 008c, not 089e, no --mutate); `ps` showed 34 verify
  processes (another task's driver) when I finished. Only read-only git, awk/grep over blobs (region/identity extraction, below), and `bash -n`.
- 2026-10-28 qa-engineer: EDIT `docs/tasks/008c-verify.sh` (scope check and pins only). Removed `scope_base` (merge-base with origin/main or
  refs/heads/main). Added `PIN_M`, `PIN_BASE`, `PIN_FINAL` (full SHAs, assigned unconditionally, no env override), `pin_full` (40 hex AND
  resolves), and `scope_violations` = `git diff --name-only PIN_BASE PIN_FINAL` minus SCOPE_RE; returns 1 (FAIL) when a pin is not a full SHA,
  does not resolve, or BASE is not an ancestor of FINAL. Live check: each of the three pins must be usable (FAIL otherwise), BASE/FINAL must
  equal `merge-base(M^1,M^2)` / `M^2` re-derived at run time, the range must be non-empty, and the violations list must be empty. The old
  "no origin/main or refs/heads/main" message and the "changed files since merge-base" message are gone with the code they described.
- 2026-10-28 qa-engineer: SELF-TEST decision (Q1 assumed A; no assertion dropped, each re-expressed, one strengthened). Scenario merge-from-main
  (was A): PIN_BASE/PIN_FINAL are set inside the scenario subshell to the repo's base and 'work' commits, main then advances and is merged
  into the branch; the pinned-range check must be green and the OLD formula (diff ending at HEAD, which replaces the old "diff against a fixed
  ancestor" sensitivity proof) must be red, so the scenario is shown sensitive. stray-commit (B) and stray-plus-merge (C): unchanged intent, the
  stray commit is the pinned FINAL; C still merges main afterwards and must flag only stray.txt. no-main-ref (D) is replaced by bad-pin: there is
  no main ref in the design any more, so the equivalent "cannot compute the base must FAIL" is: a 7-character pin, `deadbee`, a nonexistent full
  SHA, and FINAL not a descendant of BASE all FAIL, plus a valid-pin control that still flags stray.txt. The two `--mutate` mutations of finding 5
  (`scope-fixed-base`) are replaced by `scope-right-side-head` (pinned right side widened to HEAD -> merge-from-main red) and
  `scope-unusable-pin-passes` (`return 1` -> `return 0` on a bad pin -> bad-pin red); anchors are whole-line matches (`grep -cxF`) and must occur once.
  Not run: all of this is written-but-not-run until phase 2. Output messages avoid the words skip/not evaluated (089e AC3 greps for them).
- 2026-10-28 qa-engineer: static reads only (not executions): the 25 `run_mut` calls (the 2 `scope_mut` calls are new) and the two blocks of existing checks
  (mutation block 32 lines, normal-mode suite block 45 lines) are byte-identical OLD vs NEW (awk extraction, same extraction coded in
  089e-verify.sh AC11.6); the new scope region has 0 HEAD/origin/main/refs/heads/main lines, the OLD region has 3 (positive control).
- 2026-10-28 qa-engineer: WROTE `docs/tasks/089e-verify.sh` (executable, `bash -n` clean, NOT run). Modes: default (AC2, AC1, AC3, AC5, AC11),
  `--mutate` (AC4), `--own-only` (AC2 + AC11, runs nothing). Quiet machine: `wait_quiet` polls `ps -eo pid=,args=` for any `*-verify.sh` other than
  itself and its ancestors, logs the lines, sleeps 30 s, caps at 6 h (timeout = FAIL, run not executed); called before EVERY child run.
  CRITERIA COVERAGE (all written-but-not-run): (1) red first = AC1: OLD blob at M on frame f1 (HEAD = M, origin/main = M) must show
  `FAIL  no changes since base`; f2 (M + merge of a later branch adding a non-008c file, origin/main = M) must show `FAIL  out of scope: ...`; f3
  (main moved to the later commit and merged into HEAD) must show `no changes since base`; NEW green on all three. (2) = AC2: M found by
  `git log --merges --first-parent --grep` == pinned, BASE/FINAL recomputed, the NEW script's three pins equal them, no HEAD/main read in the
  scope region (positive control on OLD). (3) = AC3: PIN_M, PIN_BASE, PIN_FINAL each replaced with `deadbee` -> red with `FAIL  scope pin KEY='deadbee'
  ...`; skip/not-evaluated grep = 0 with positive control. (4) = AC4 in `--mutate`: m1 live check widened to merge-base(HEAD, origin/main)..HEAD
  on f2 -> exactly one FAIL (`out of scope`); m2 right side widened to HEAD -> only scope check + its self-test; m3 runs HEAD's `008c-verify.sh
  --mutate` from a clean clone and requires exit 0 and `ok mutation` count = (25 run_mut + 2 scope_mut + 1 second-module = 28) = expected,
  both scope mutations named; an unmutated control on f2 is green. (5) = AC5: the HEAD script (asserted equal to the fix commit's) exits 0 on HEAD
  and on HEAD + a merge with a later branch. (9) = wait_quiet. (11) = AC11: pins full/existing/ordered; FIX/FINAL are the first/last commits of
  BASE..TIP touching 008c-verify.sh; BASE..TIP files subset of {008c-verify.sh, 089e-verify.sh, this file}; TIP..HEAD only this file and the three
  pin lines of 089e-verify.sh; 008c-verify.sh at HEAD == FINAL; existing-check blocks byte-identical; modes 100755.
- 2026-10-28 qa-engineer: PHASE 2 COMMANDS (run by hand, in this order, quiet machine; nothing else may run any `*-verify.sh`; each prints its
  own `ps` log; paste the full output into this log):
```
rm -rf /tmp/p2-089e && git clone https://github.com/worldofmodcraft/registry /tmp/p2-089e
cd /tmp/p2-089e && git checkout task/089e-closed-verify-sweep-registry-e
export PYTHONDONTWRITEBYTECODE=1
git --version && ps -eo pid,args | grep '[v]erify.sh'      # must print nothing but the git version
bash docs/tasks/089e-verify.sh --own-only                  # 1. pins + scope on fixed SHAs, runs nothing else
bash docs/tasks/089e-verify.sh                             # 2. AC2, AC1 (red first), AC3, AC5, AC11
bash docs/tasks/089e-verify.sh --mutate                    # 3. AC4
bash docs/tasks/008c-verify.sh                             # 4. item-12 control, plain, on the branch tip (HEAD)
bash docs/tasks/008c-verify.sh --scope-selftest            # 5. the self-test alone
```
  A fresh clone has no `origin/main` problem: nothing in the fixed check reads it (089e builds its own frames with explicit refs). If a command
  fails, that is a finding: log file:line, expected vs actual, do not adjust the test. 4 and 5 are redundant with the HEAD runs inside 2/3 but are the
  plain-invocation proof.
- 2026-10-28 qa-engineer: scope note found while writing AC11: `git diff --name-only 32c641b..HEAD` also lists the umbrella
  `docs/tasks/089-closed-verify-sweep-registry.md`, because the manager's cut commit (60ba327) copied it into the branch ("copied into this branch
  from platform main", task header). It is not in this task's "Scope of this part" list. AC11.4/4c therefore allow it ONLY as that one cut
  copy-in (exactly one commit touched it, before the fix commit, never changed by 089e). Booked as Q3.
- 2026-10-28 qa-engineer: COMMITS. Content commit (the only one touching 008c-verify.sh) `c68eec7b910a29be295b1944e826497d37cac326` = E_FIX = E_FINAL = E_TIP;
  pin commit `877a1083839eaeabd7fd4878bc032b4d554d5554` (089e-verify.sh, three pin lines). Size at the pin commit vs base `32c641b`: 008c-verify.sh
  +68/-48 (116 changed), 089e-verify.sh 308 new lines, task file +85 incl. this log, umbrella copy-in 143 (cut commit, not mine).
  STATUS: phase 1 complete; NOTHING is done: every criterion above is written-but-not-run. Phase 2 (the commands listed above) is open.
- 2026-10-28 manager (session 14): phase 1 accepted for phase 2 (log check exit 0; head `903b07e`). Triage (★, overnight ruling; §8b 3a):
  Q1 ★ A (pins per scenario subshell; the real `scope_violations` is exercised). Q2 ★ A. Q3 ★ A: the umbrella copy is the manager's dispatch
  commit, the same shape as 089b; AC11 allowing it only as that single pre-fix copy-in is correct. The self-test replacement (no-main-ref ->
  bad-pin, `scope-fixed-base` -> two mutations) is accepted as equivalent-or-stronger; the reviewer is to confirm no assertion was lost.
- 2026-10-28 qa-engineer (fix round after static review PASS, six LOW notes; phase 1, no verify script run, `bash -n` only): (1) AC5.0 no longer prints
  PASS when E_FIX is not a full SHA (explicit FAIL branch first). (2) `others` now excludes only this script's PID, its descendants and its
  ancestors, by PID/PPID (awk over `ps -eo pid=,ppid=,args=`), no longer every line mentioning 089e-verify.sh, so a second concurrent 089e run
  makes the machine "not quiet"; the function was exercised alone on this machine (reads `ps` only; it listed the other driver's processes).
  (3) AC2.6d now scans the live scope-check block as well (008c-verify.sh `for p in PIN_M ...` to the "scope pins unusable" line, 11 code lines,
  0 HEAD/origin/main hits); positive control: the OLD blob's live block (`if SB=$(scope_base)` .. "cannot be checked", 6 lines) has 2 hits, and with the
  OLD scope region the control total stays >= 2; new AC2.6a2 asserts both live blocks were extracted. (4) AC4.m3 also asserts both counts equal the
  pinned literal 28. Notes 5 and 6 left as notes: phase 2 must show the AC3.4 skip-word count = 0 (with its positive control). Because this edit
  changes 089e-verify.sh beyond its pin lines, E_TIP moves to this fix commit (E_FIX/E_FINAL stay at the only commit touching 008c-verify.sh,
  `c68eec7b910a29be295b1944e826497d37cac326`, which is unchanged); AC11.5b still holds from the new TIP.
- 2026-10-29 qa-engineer (PHASE 2, all criteria demonstrated): fresh clone of https://github.com/worldofmodcraft/registry at branch head
  `d50e7d8a1772d1ce4004b6948cb8d9b203b2b369`, git 2.53.0, PYTHONDONTWRITEBYTECODE=1, separate invocations, outputs under `/tmp/tmp.6k9buHWYAH`. Before each run
  `ps -eo pid,args | grep -E 'docs/tasks/[^ ]*-verify\.sh'` printed 0 matches; inside 089e every `wait_quiet` logged "no other *-verify.sh process running (waited 0s)".
  Exit codes: (1) `089e-verify.sh --own-only` rc=0 (AC2 + AC11 all PASS; AC2.6c positive control found 5 HEAD/main reads in the OLD blob, AC2.6d 0 in the NEW);
  (2) default rc=0, 8 s, ALL CHECKS PASSED: AC1.f1 OLD exit 1 "FAIL  no changes since base", AC1.f2 OLD exit 1 "FAIL  out of scope: docs/089e-synthetic-later.md",
  AC1.f3 OLD exit 1 "no changes since base", NEW exit 0 on all three; AC3 PIN_M/PIN_BASE/PIN_FINAL=deadbee each exit 2 with "FAIL  scope pin KEY='deadbee' is not a full 40-character SHA ...";
  AC3.4a positive control PASS (skip-word grep matches a sample), AC3.4 skip/not-evaluated count = 0; AC5.0-5.2 exit 0 on HEAD and on HEAD + later-branch merge;
  (3) `--mutate` rc=0: control green; m1 (merge-base with origin/main) exit 1 with exactly the one "out of scope" FAIL; m2 (right side HEAD) exit 2, scope check + self-test only;
  m3 `008c-verify.sh --mutate` exit 0, all 28 mutations red (expected 28, pinned literal 28), both scope mutations named; (4) plain `008c-verify.sh` rc=0, 0 FAIL lines,
  "ok scope pins re-derived from the merge commit", "changed files in e2f7fe3..7810e70: 5", "all changes of 008c's merged range inside the declared file scope", SUMMARY failed=0;
  (5) `008c-verify.sh --scope-selftest` rc=0 (merge-from-main green + old formula red/sensitive, stray-commit, stray-plus-merge, bad-pin). No unexpected red; no finding.
  Note: this also fixes the symptom 089d saw ("FAIL 008c-verify.sh exit 1 on HEAD: FAIL out of scope: docs/tasks/089-closed-verify-sweep-registry.md") once this branch is merged.
  Criteria 1-5, 9, 11: DONE (demonstrated above). Status: review.
