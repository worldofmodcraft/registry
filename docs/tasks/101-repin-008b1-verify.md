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
- 2026-10-29 qa-engineer (phase 1, session 14): re-derived the pins from git (read-only), git 2.53.0: M = `dd7da2d79fc278597762cce862b48cc48434f816`
  (`git log --merges --first-parent` finds "Merge pull request #29 from worldofmodcraft/task/008b1-pipeline-plan" as the only match);
  BASE = `git merge-base M^1 M^2` = `32c641b5f56139a86c820f0b16d522c0f991d207`; FINAL = `M^2` = `2f179d08a9786ba94cb2f6c6fc2da4bf0ba5ffca`.
  `git diff --name-only BASE FINAL` = build-pipeline.md, 008b1-pipeline-plan.md, 008b1-verify.sh, test_plan_pending.py, plan_pending.py: all five inside
  008b1's SCOPE_RE (green by construction). Reference read: task 089e (`089e-verify.sh`, the 008c re-pin diff, its log); 101-verify.sh is adapted from it.
- 2026-10-29 qa-engineer: DESIGN of 101-verify.sh (Ludwig: "fixed SHAs only"). Deviation from 089e, deliberate: 089e's AC11 used `TIP..HEAD` and
  `UMB` range checks; here AC11 reads only BASE..TIP and FINAL..TIP with fixed pins E_BASE (= M), E_FIX = E_FINAL (the one commit touching
  008b1-verify.sh), E_TIP (the pin commit, recorded by one later commit). Commits: (1) 101-verify.sh red-first with `unpinned` pins, (2) the 008b1-verify.sh fix,
  (3) pin commit (E_FIX/E_FINAL lines only), (4) E_TIP line + log. AC11.3c asserts (1) precedes the fix. Commits after TIP (the E_TIP line, log entries)
  are not range-checked by this script (a TIP..HEAD check is forbidden by the decision); the only HEAD read besides the item-12 controls is blob
  equality `008b1-verify.sh at HEAD == FINAL` (a fixed-pin comparison, not a scope diff). The reviewer's diff covers the tail.
- 2026-10-29 qa-engineer: EDIT `docs/tasks/008b1-verify.sh` (scope check, pins and scope self-test only; diff +68/-48, identical in size to the 089e re-pin of 008c).
  Removed `scope_base`; added PIN_M/PIN_BASE/PIN_FINAL (full SHAs, unconditional, no env override), `pin_full`, and `scope_violations` = `git diff --name-only
  PIN_BASE PIN_FINAL` minus SCOPE_RE (returns 1 on an unusable pin or non-ancestor). Live check: three pin_full FAILs, BASE/FINAL re-derived from M, non-empty
  range, no violations; unusable pins -> FAIL. SELF-TEST MAP old -> new (no assertion dropped; PIN_BASE/PIN_FINAL assigned inside each scenario subshell):
  A merge-from-main: new check green (kept, now with a pinned range; the sensitivity proof `git diff first...HEAD` became `git diff first HEAD`, the HEAD-ended formula);
  B stray-commit: unchanged intent, the stray commit is the pinned FINAL; C stray-plus-merge: unchanged intent, main merged AFTER the pin, flags only stray.txt;
  D no-main-ref -> bad-pin (no main ref exists in the design; "cannot compute the base must FAIL" is now: 7-char, `deadbee`, nonexistent full SHA, reversed pins all FAIL, plus a valid-pin control).
  `--mutate`: old `scope-fixed-base` replaced by `scope-right-side-head` (-> merge-from-main red) and `scope-unusable-pin-passes` (-> bad-pin red); all 24 `run_mut`
  and the c12 mutation untouched (byte-identical, asserted by 101-verify.sh AC11.6). Expected `ok mutation` count 24+2+1 = 27 (was 26).
- 2026-10-29 qa-engineer: COMMITS (full SHAs). red-first 101-verify.sh `d9650ccd61646c075033165bce4ae630a0cea0ca`; fix (the only commit touching 008b1-verify.sh)
  `fbd384c8ee0edc5da50038ab8f74d2c988333c81` = E_FIX = E_FINAL; pin commit (E_FIX/E_FINAL lines) `5fe5cfa12c36d6fc6dc4b3ea2e006b1a79f0c4eb` = E_TIP; E_BASE = M = `dd7da2d79fc278597762cce862b48cc48434f816`.
  The next commit records E_TIP (one line) and this log entry. Phase 1 done; phase 2 follows (machine released by the manager).
- 2026-10-29 qa-engineer (PHASE 2, first run, UNEXPECTED RED, stopped and reported as required): fresh non-shallow clone of
  https://github.com/worldofmodcraft/registry at `65964e877c7ac9809341d2a0d0c62ee71f6b5185` (git 2.53.0, PYTHONDONTWRITEBYTECODE=1, ps printed 0 verify processes).
  `101-verify.sh --own-only` rc=0 (all PASS). `101-verify.sh` (default) rc=1: AC1 (OLD red on f1/f2/f3 with exactly the predicted lines; NEW exit 0 on all),
  AC3 (three deadbee runs exit 2 with the expected FAIL lines), AC5 (exit 0 on HEAD and HEAD+later branch), AC11 all PASS; ONE FAIL: `AC3.4 30 skip/not-evaluated line(s)`
  (101-verify.sh line 234). Cause: a defect in MY test, not in 008b1-verify.sh: the grep for the words skip/not-evaluated, copied from 089e, was run over the whole
  output of the 008b1 script, whose planner legitimately has a "skip" plan category (`C17aSkip`, `skip=0`, "Recovering a skipped version"; 008c had no such word).
  Repair (my own file, test-side only; the intent "an unusable pin is never skipped silently" is kept and made precise): the grep now reads only scope-check lines
  (`scope|pin`), with a positive control that matches `scope pin PIN_M skipped` and a negative control that ignores a planner skip line. Because this edits 101-verify.sh
  after the fix commit, AC11.5b now compares from a new fixed pin E_SCRIPT (the repair commit) to TIP and allows the three pin lines E_FIX/E_FINAL/E_SCRIPT; AC11.5a
  (FINAL..TIP files only 101-verify.sh and the task file) is unchanged. 008b1-verify.sh is untouched by the repair (still FIX = FINAL). The 5fe5cfa/65964e8 E_TIP is superseded.
- 2026-10-29 qa-engineer: re-pinned. Final pins (full SHAs): M = E_BASE = `dd7da2d79fc278597762cce862b48cc48434f816`; BASE = `32c641b5f56139a86c820f0b16d522c0f991d207`;
  FINAL(M^2) = `2f179d08a9786ba94cb2f6c6fc2da4bf0ba5ffca`; E_FIX = E_FINAL = `fbd384c8ee0edc5da50038ab8f74d2c988333c81`; E_SCRIPT = `8dc4f9bd597b4d05d7aa78830a55e613c3d04608`; E_TIP (pin commit) = `8952591f671894d4009e9ebf20a3c4dc521e1fe4`.
- 2026-10-29 qa-engineer (PHASE 2, all criteria demonstrated): fresh non-shallow clone of https://github.com/worldofmodcraft/registry at branch head
  `3d9494bb06f882c15cb9671946bec820bacd2732` (is-shallow false), git 2.53.0, PYTHONDONTWRITEBYTECODE=1, outputs under `/tmp/p2-101b.bPXNXU`. Before each run
  `ps -eo pid,args | grep -E 'docs/tasks/[^ ]*-verify\.sh'` printed nothing; inside 101 every `wait_quiet` logged "no other *-verify.sh process running (waited 0s)" (11 of 11).
  Exit codes: `101-verify.sh` default rc=0 (57 PASS: AC1 OLD exit 1 on f1 "FAIL  no changes since base (broken search)", f2 "FAIL  out of scope: docs/101-synthetic-later.md",
  f3 "no changes since base", NEW exit 0 on all three; AC3 deadbee PIN_M/PIN_BASE/PIN_FINAL each exit 2; AC3.4 skip-word count 0 with positive+negative control; AC5 exit 0 on HEAD and HEAD+later branch;
  AC11 on fixed SHAs); `101-verify.sh --mutate` rc=0 (1m33s: control green; m1 merge-base-with-origin/main exit 1 with exactly one FAIL; m2 right side HEAD exit 2, scope check + self-test only;
  m3 `008b1-verify.sh --mutate` exit 0, 27 mutations red = expected 27); plain `008b1-verify.sh` rc=0 (SUMMARY failed=0, "changed files in 32c641b..2f179d0: 5", all in scope, self-test A-D ok);
  `008b1-verify.sh --mutate` rc=0 (27 `ok mutation`, both scope mutations named, SUMMARY mutate failed=0, worktree clean after). (The first default run was red once, AC3.4, repaired above; no other red.)
  Criteria 1-7: demonstrated. Item 7 scope: `git diff --name-only dd7da2d 8952591f671894d4009e9ebf20a3c4dc521e1fe4` (E_BASE..E_TIP) is asserted by AC11.4 = 008b1-verify.sh, 101-verify.sh, this file. Status: review.
- 2026-10-29 qa-engineer (follow-up, manager message, decision A "fixed SHAs only"): finding on my own head `0c67d6eb7eae922fbc6b4d9304fda82feea771f4`: AC11.5d (`008b1-verify.sh` at HEAD == FINAL) and AC5.0/AC5.1/AC5.2
  (HEAD's copy of the script, run on HEAD) read HEAD for an own-change property and redden the day a later task edits 008b1-verify.sh. RED FIRST commit: AC12 added (pin OLD101 = that head): a clone of
  OLD101 plus ONE later commit appending a comment to 008b1-verify.sh must make the OLD `--own-only` FAIL `AC11.5d` (a later new file must stay green), and the same later commit on the current HEAD must be green.
  Until the fix commit follows, AC12 is red on the fixed side by construction.
