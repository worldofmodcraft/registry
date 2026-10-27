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
`docs/tasks/087-verify.sh` (new), `docs/tasks/070-verify.sh` (the AC4.m1 mutation only; manager's scope extension, session 11, see log).
Anything else = stop and report.

## Forbidden
Loosening any check beyond moving an own-change check to its pinned FINAL; pinning a live property; skips.

---
# Task 087 log
- 2026-10-26 manager: written and approved (solo gate) from 082's final-run finding.
- 2026-10-26 qa-engineer: executed. Commits (all on `task/087-repin-032-067-readme`, cut from registry `origin/main` 208c6d1):
  red `5e5b107` (087-verify.sh + this file), fix `bb10820` (032, 067), pin commit `c10ced8` (SHAs in 087-verify.sh), log commit after it.

  **Pins.** 032: new `README_PIN_FINAL="76af1bb"` = `git rev-parse 4d4a204^2` = the existing `SCOPE_FINAL` (reused: same commit, same
  PR #4; the README at 76af1bb contains both "eight prose" and "None of the three tasks implements checking logic", checked).
  067: its existing `FINAL="06c721c"` (= `ac22c8f^2`, PR #11; `BASE="3c94cf2"` = its merge-base), README has the sentence once.

  **Classification (one line why).**
  - 032 N5 ("eight prose documents"): OWN-CHANGE (032 added ownership.md, making it eight) -> now read at 76af1bb via `git show` into
    `$BLOBDIR`; `$CONTRACTS_README` is now that pinned copy, `$CONTRACTS_README_PATH` is the path. The N5/N5b call lines are
    byte-identical (patterns and the `"$CONTRACTS_README"` argument), which keeps 070's AC5.m2 anchor valid.
  - 032 N5b (the "None of the three tasks ..." sentence): OWN-CHANGE (032 wrote the paragraph; 067 only re-pinned the pattern) -> same pin.
  - 032 new `N5pin`: fails (not skips) when the pin or the file at it is unreadable; N5 and N5b then fail on the empty copy as well.
  - 032 every other check (N4 executable, S3/S4 scope over its pinned range, S5 lexical, E stderr, all `contracts/ownership.md` checks):
    unchanged; they read contracts/ownership.md or the script itself, not the README (the ownership.md checks are a separate question: no
    later task has edited it so far; not in this task's scope).
  - 067 AC2.1-AC2.4, AC5.1: already pinned (task 070); unchanged. AC2.5: OWN-CHANGE (its subject is the sentence N5b pins, which a later
    task may reword), so it is no longer "live" as 070 had labelled it -> `git show "$FINAL:docs/contracts/README.md"`; unreachable
    FINAL fails it. AC2.6 (032 at HEAD: N5b line still pins the full sentence): LIVE property of the script, unchanged and still green
    (the N5b call stays two lines and keeps the pattern). AC3.1/AC3.2 (032 and 062 green at HEAD): LIVE. AC5.2: LIVE. AC4 mutations: operate on HEAD's
    README in a temp clone by design (they mutate the live copy to prove the checks bite): unchanged, still green.

  **FINDING (needs a scope decision, not fixed here): `070-verify.sh --mutate` AC4.m1 is now stale.** Line 205: "README sentence
  deleted (committed) reddens 067's live AC2.5". With AC2.5 on the pinned FINAL, deleting the sentence at HEAD no longer reddens it
  (shown: clone of c10ced8 with the sentence reworded, committed; `067-verify.sh /nonexistent` still prints `PASS  AC2.5 the README at
  067's pinned FINAL 06c721c states the sentence`). So 070 --mutate would report "AC4.m1 ... stayed green" (1 failure). That is
  inherent to the requested change (AC2.5 cannot stay live: 082 rewords the sentence), and 070-verify.sh is outside 087's file
  scope. Proposed follow-up (one line in 070-verify.sh): retarget AC4.m1 at a check that is still live, e.g. mutate 067's AC2.6
  pattern, or drop AC4.m1 with a note. 070's default run is unaffected (its AC2 loop only needs AC2.1-AC2.6 PASS on the later branch;
  checked statically, AC2.6 and AC2.5 stay PASS there). 070's other mutation AC5.m2 is unaffected (anchor string kept byte-identical).

  **Other closed scripts that pin README sentences at HEAD (found by grep; NOT fixed here, booked).** All still green on the merge with
  082 (checked: every pinned phrase is still present in the merged README), so none is red today; each is the same latent shape:
  - 007a-verify.sh:117-118 (README mentions "tools/registry" and "task 039"; no "task 007$" line): own-change of 007a, read at HEAD.
  - 007b-verify.sh:100-101 (README mentions "ownership" and "task 039"; no "still to come" on the ownership-checker line): own-change of 007b, HEAD.
  - 008a-verify.sh:74 (README points at `build-pipeline.md`): own-change of 008a, HEAD.
  - 057-textchecks.py:180 (README names "task 057", run by 057-verify.sh): own-change of 057, HEAD.
  - tests/registry/test_hardening.py:153 (README contains `--no-renames`): a live-property unit test, HEAD (not a verify script).
  - 007b-verify.sh:101 note: `grep -n "ownership checker (task 007b" README | grep -qi "still to come"` matches nothing in the README today, so its "no longer still to come" branch passes vacuously (not a README-sentence pin that can go red; a weak check).
  - 062-verify.sh:469/486/494 only mutate the declared-scope lists of other scripts; not README pins.
  - 070-verify.sh:205: the stale mutation above.
  Recommend one follow-up task "re-pin 007a/007b/008a/057 README own-change checks" (the 071/084 shape) plus the 070 line.

  **Demonstrations (087-verify.sh, run from fresh clones, PYTHONDONTWRITEBYTECODE=1, ajv from the worktree's tools/dev/node_modules).**
  - RED, run at red commit `5e5b107` (6 checks failed, exit 6): AC1.1 PASS (old 032 exits 2 on the merge of 082's tip `65f3979` onto
    the base: N5 and N5b FAIL), AC1.2 PASS (old 067 exits 3: AC2.5 and AC3.1 FAIL), AC1.3 PASS (control: old 032 exits 0 on the plain
    base); the fix assertions AC0.1/AC0.5/AC0.7 and AC1.4/AC1.5 (new pair on the merge) and AC4.0 FAILED, as they must before the fix.
  - GREEN, run at `c10ced8` in a fresh clone (ALL CHECKS PASSED, exit 0, 7m26s): AC0.1-0.7, AC1.1-AC1.5 (new 032 exits 0 and new 067
    exits 0 on the merge with 082, including 062 inside 067), AC4.1-AC4.10.
  - MUTATIONS, `--mutate` (ALL CHECKS PASSED, exit 0, 1m25s): controls c1/c2; m1 N5 widened to HEAD red (N5 only; N5b stays PASS);
    m2 N5b widened red (N5b only); m3 pin block reading HEAD red (both); m4 unreachable `README_PIN_FINAL` red (`FAIL N5pin ... deadbee`
    plus N5, N5b); m5 067 AC2.5 widened to the HEAD clone red (AC2.4 stays PASS); m6 067 unreachable FINAL red (AC2.5 and AC5.1).
    No pin check skips: an unreachable pin is a FAIL line in every case.

  **Acceptance criterion 3 (every closed script green on HEAD and on the merge with 082, one at a time, quiet machine): PENDING.**
  The machine was not quiet: `ps` showed orphaned verify processes from an earlier run (064/065/070/069/067/062/008a, finished on
  their own after ~25 min), then, while this task waited, another agent's `039b-verify.sh` chain (pid 3672584 and children, which
  runs 064 etc.) for more than an hour. Per the brief (not quiet after 60 min) the fix was committed with the red/green/mutation
  demonstration on 032 and 067 only. The full sequential run (006 007a 007b 008a 032 034 057 062 064 065 066 067 069 070 071 075 084
  on HEAD and on the merge with 082's tip) still has to be done on a quiet machine before merge.
  Not run separately: 032 alone on the unmerged HEAD (the AC2.c1 control runs it on the merge; 067's AC3.1 runs it at HEAD).
- 2026-10-26 manager (scope extension, on the qa-engineer's 070 finding): 087's file scope is extended by `docs/tasks/070-verify.sh`, the
  AC4.m1 mutation only. Criterion 3 stays required before merge; the five latent README-at-HEAD reads (007a, 007b, 008a,
  057-textchecks, test_hardening) are NOT touched here and are booked for a sweep task.
- 2026-10-26 qa-engineer: 070 AC4.m1 re-targeted (commit `5da249b`). New mechanism: in the throw-away later-branch clone, a replacement
  commit X (tree of 067's pinned FINAL with the README sentence reworded, parent FINAL) is made an ancestor of the clone's HEAD
  (`merge -s ours`) and 067's `FINAL` pin is pointed at X; AC2.5 must then read X's README and FAIL (AC2.4 reddens too, as it must).
  Single hunk replacing the single AC4.m1 line; 087-verify.sh AC4.7 scope now includes 070-verify.sh and AC4.11-AC4.13 check that the
  070 commit (pinned `PIN087_070`) is exactly that.
  Booked for a sweep task (NOT touched): 007a-verify.sh:117-118, 007b-verify.sh:100-101, 008a-verify.sh:74, 057-textchecks.py:180,
  tests/registry/test_hardening.py:153 (README-at-HEAD reads; all green on the merge with 082 today).
- 2026-10-26 qa-engineer (round 2, after the manager's scope extension):
  - 070 AC4.m1 mechanism demonstrated in isolation (the same steps as the new 070 block, on a clone of `7c648c3`): replacement commit X
    (067's FINAL tree with the sentence reworded, parent 06c721c) merged `-s ours` into the clone's HEAD, 067's `FINAL` pointed at X;
    `067-verify.sh` then prints `FAIL  AC2.5 the README at 067's pinned FINAL 2060450c... lacks the sentence` (plus AC2.4 and AC5.1
    red, as expected for a changed README at the pin; AC2.6, AC3.1, AC3.2 stay PASS).
  - 087-verify.sh at the PR head in a fresh clone: ALL CHECKS PASSED (exit 0), including AC4.11-AC4.13 (the 070 commit `5da249b` is
    a single hunk replacing the single AC4.m1 line; its parent `489bd26` is pinned as `PIN087_PIN`). One earlier run of the same script
    reported `FAIL AC1.5` because 062 inside the new 067 exited 1 on the merge; that did not reproduce (062 alone on the merge: exit 0;
    the whole script again: exit 0). Cause unknown: its output was not captured; it coincided with ~10 other verify processes
    running at once on the machine (another agent's 039b chain). Not attributed to anything; if it recurs on a quiet machine it is a
    finding against 062.
  - **PENDING, not run:** `070-verify.sh --mutate` (and the 070 default run) with the new AC4.m1, and criterion 3 (every closed
    script on HEAD and on the merge with 082, one at a time). The machine was never quiet during the 2 h of polling every 10 min:
    a 039b-verify.sh parent (pid 3672584, up for 3 h 55 min at the last check) keeps spawning children (064, 065, 066, 057 ...). I did not
    kill it. These two runs must be done on a quiet machine before merge.
- 2026-10-26 manager (session 12): quiet-machine runs at 30942ec: `087-verify.sh <nm>` ALL CHECKS PASSED (27 PASS, 0 FAIL); `087-verify.sh --mutate <nm>`
  ALL CHECKS PASSED (8: controls c1 c2; m1-m6 each red, none skipped). **Independent review (read-only): PASS-WITH-AMENDMENTS.** (A) File scope now
  lists 070-verify.sh (AC4.m1 only), matching the session-11 extension — done in this commit. (1, MED, blocks merge) 070 default and `--mutate`
  not yet demonstrated end to end for the AC4.m1 rewrite: the manager runs both on the local merge main 4268735 + 087 + 082 (070 default is part
  of the `082-verify.sh --full` sweep there; `--mutate` queued after it) and pastes results here before merge. (2, MED) AC3 all closed scripts on
  the merge with 082: the same sweep. (3, LOW) the earlier one-off `FAIL AC1.5` (062 inside 067) stays an open observation; a finding against 062
  if it recurs. (4, LOW) the latent README-at-HEAD reads (007a, 007b, 008a, 057, test_hardening) belong to sweep tasks 089/090 (inventory 088).
- 2026-10-27 implementer (item-12 fix round; defect found by the manager): **087's own verify script had the defect it fixes elsewhere.**
  `087-verify.sh` AC4.7 measured "base..HEAD stays inside the declared file scope" with HEAD as the frame. Red-before-fix evidence
  (`082-verify.sh --full` on the local merge main 4268735 + 087 + 082 at ed4588e, file `/home/ludwig/.claude/jobs/8bf3d47c/tmp/q/082-full-main-087-082.out`):
  `FAIL  AC4.7 out-of-scope files changed in base..HEAD: config/r11-identity.json contracts/pipeline-trigger.md docs/contracts/README.md docs/tasks/039-registry-ci-workflow.md docs/tasks/039a-verify.sh docs/tasks/082-pipeline-trigger-contract.md docs/tasks/082-verify.sh tests/registry/fixtures/ci/README.md ... tests/registry/test_ci_gate.py tools/registry/ci_gate.py`
  - Audit of every own-change check that read HEAD or the working tree: AC4.7 (range to HEAD) -> BASE..TIP, and a range that cannot be computed now FAILS
    (before, an empty list passed); AC4.4 and AC4.12 (ancestor of HEAD) -> ancestor of TIP; AC0.1-AC0.7 and AC4.10 (read 032/067 from the working tree)
    -> read from `git show TIP:<file>` snapshots (AC0.0 fails if unreadable). Already on fixed SHAs: AC4.2, AC4.3, AC4.5, AC4.6, AC4.8, AC4.9, AC4.11, AC4.13.
    Deliberately still HEAD (live guards, not own-change): AC1.4/AC1.5 (new 032/067 pass on the merge of 082 onto HEAD), all of `--mutate` (mutates HEAD's scripts), new AC4.15 (TIP reachable from HEAD).
  - Pins, all full 40-char SHAs: BASE `208c6d1ae63ff56ccac85c6fc9a200ac77259fda`; FINAL `abede5d2223a6271e3e2424ce4f5d9b581323039` (last commit touching 032/067/070/087-verify.sh in BASE..TIP);
    TIP `49988fd827d2e7ea85f4a24c5b73a137dc26663a` (last branch commit before this round); RED `5e5b107a32a8223b9ea0b8a7fc49e207b64b663f`, FIX `bb1082039f3d59ce5d918035be863b5a41c6b238`,
    PIN `489bd264c90557fba0d3b7bd799423501aa11993`, 070 `5da249bc6e380d99ba65752a4da5a7820e8501c4`. New AC4.14 (FINAL is the last script-touching commit; FINAL..TIP touches only docs/tasks/087-*; verified with git: only the task file) and AC4.15.
  - Controls (new `--own-only` flag runs AC4 alone; `--mutate` AC2.o1-o6 on a clone of HEAD): o1 clean green; o2 a synthetic later-branch commit outside scope leaves AC4.7 green;
    o3 range widened back to BASE..HEAD is red on that commit; o4 FINAL=BASE red (AC4.14); o5 unreachable TIP red; o6 unreachable FINAL red. Order: controls commit `72911206ef0239f02e2f50bf9cbb6377f3182cac`
    (AC4 still on HEAD, so o2 fails there, o3-o6 fail because their patterns/checks do not exist yet: reasoning only), then the fix `a6e89683d8b2fea656a01aa46938e6291e9cace1`.
  - NOT RUN by me (a verification queue was running; only `bash -n` and git were allowed). **The manager runs**: `bash docs/tasks/087-verify.sh <nm>` and `bash docs/tasks/087-verify.sh --mutate <nm>`
    on the merge main 4268735 + 087 + 082 (also `--own-only` alone is quick). Unproven until then.
