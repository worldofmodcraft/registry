# Task 062: Registry verify scripts stay green on later branches and stop pinning the superseded born-`removed` rule

- **Mission:** SITE-V1 (keeps D1's verification trustworthy) — **Status:** review (qa-engineer, 2026-10-15; spec-approved by manager, SPEC-CHECKLIST 1–8 verified solo; review by an independent reviewer)
- **Repo:** registry (`worldofmodcraft/registry`); this file lives in the platform repository's `docs/tasks/` and is
  copied to the registry branch's `docs/tasks/` as that task's log.
- **Agent / model:** qa-engineer / sonnet (frontmatter). Independent reviewer required: this changes existing
  checks, which MANAGER.md §3.5 makes its own reviewed task.
- **Budget:** medium (≤ 3 agent-sessions; six verify scripts inventoried, four scope checks re-pinned and mutation-tested)
- **Branch / worktree:** `task/062-registry-test-maintenance` / `~/wt/registry-task-062` (cut from registry
  `origin/main`, `e009ef0` when written)
- **Graph:** no node or edge changes. Touches only the verification artefacts of closed tasks on node N3's
  contracts, plus one stale cross-reference sentence in `contracts/ownership.md` (E16). Introduces no new edges.

## Objective
On registry `main`, and on any later task branch that does not touch the files a closed task owned, every
committed `docs/tasks/*-verify.sh` of a closed task passes. Today they do not: task 057's log (registry
`docs/tasks/057-version-lifecycle-contract.md`, entries 2–4 under the 2026-10-15 hand-back) records that

1. `006-verify.sh` C9.4 and C9.6 already fail on pristine `a50daac` (scope checks against a pinned base `be82c19`);
2. `006-verify.sh` C1.5b, C8.2, C8.3a and C8.3b assert the born-`removed`-needs-a-reason rule and the premise that
   `entry.schema.json` accepts a born-`removed` entry. ADR-0121 (Q-L: born-`pending` only) and task 057 replaced
   that rule; these four checks are now red because they assert superseded text, not because anything is wrong;
3. `032-verify.sh` S4 and `008a-verify.sh`'s declared-scope check fire on every later branch by design (both
   diff from a base to `HEAD`, so a later task's files count as out of scope); `057-verify.sh` S1 has the same
   shape and will do the same;
4. `contracts/ownership.md` quotes `append-only.rules.md`'s old heading "The one permitted in-place mutation"
   (lines ~980 and ~1027), which task 057 renamed to "The permitted in-place mutations".

After this task none of these four statements is true, and nothing was made green by weakening what a check
proves.

## Design (manager decisions, with reasons)
- **D-1. A closed task's scope check measures that task's own commit range, pinned at both ends.** The check
  exists to prove MANAGER.md §3.3 held *for that task*. The faithful, deterministic form is
  `git diff --name-only <task-base> <task-final-commit>`, a subset test against the declared scope, where both
  hashes are the task's own (its fork point and the last commit on its branch before the merge). That range never
  moves, so the check gives the same answer on main, on any later branch and in any fresh clone, and it can still
  go red (mutation below). Rejected alternatives: *merge-base with `origin/main`* (green on main but red on every
  later branch, which is the defect); *skip when not on the task branch* (a check that silently does not run is
  §2c rule 1's broken search). If either pinned commit is not reachable from `HEAD`, the check **fails** with a
  message naming the missing commit; it never skips.
- **D-2. The four superseded 006 checks are retired, not rewritten to the new rule.** Task 006 is closed history;
  the new rule is proved by `057-verify.sh`. Each retired check is replaced in `006-verify.sh` by a comment block
  naming: the check id, the sentence or premise it pinned, ADR-0121 and task 057 as the reason, and the exact
  `057-verify.sh` check id(s) that now prove the replacing rule. A retirement without a named successor check is
  a review failure. The scripts' totals change accordingly and the log states the before/after counts.
- **D-3. `ownership.md`'s quote is updated to the current heading text verbatim** and nothing else in that file
  changes. If `032-verify.sh` pins the old quote, that pin is updated to the new text in the same commit, and its
  existing mutation for that pin is shown to still redden.

## Context to load (exhaustive)
- ADR-0121 (`docs/decisions/0121-version-lifecycle-pending.md` in the platform repo).
- Registry: `docs/tasks/057-version-lifecycle-contract.md` (the log section dated 2026-10-15, items 2–4 and 6);
  `docs/tasks/006-verify.sh`; `docs/tasks/032-verify.sh` (the scope-check block around line 1637 and any pin on the
  heading quote); `docs/tasks/008a-verify.sh` (lines 76–90); `docs/tasks/057-verify.sh` (criterion 8 block);
  `docs/tasks/034-verify.sh`; `contracts/ownership.md` (the two quoting sentences);
  `contracts/append-only.rules.md` (the heading "The permitted in-place mutations" only).
- Doctrine: `docs/manager/MANAGER.md` §2c (all five rules), §3.3, §3.5; `docs/manager/OPERATIONS.md`
  ("Tool interfaces that are easy to get wrong").

## File scope (declared; anything else = stop and report)
- `docs/tasks/006-verify.sh`, `docs/tasks/032-verify.sh`, `docs/tasks/008a-verify.sh`, `docs/tasks/057-verify.sh`,
  and `docs/tasks/034-verify.sh` only if the inventory (AC1) shows it has the same defect.
- `contracts/ownership.md` — the stale quote only (D-3).
- `docs/tasks/062-registry-test-maintenance.md` (this file as the log) and `docs/tasks/062-verify.sh` (new).
- Not in scope: any `tests/` file, any schema, any other contract text, any checker code.

## Acceptance criteria — all demonstrated by `docs/tasks/062-verify.sh`
1. **Inventory before change.** The log records, for every `docs/tasks/*-verify.sh` on registry `origin/main`,
   its result on `origin/main` and on a throwaway branch that adds one unrelated file (`probe.txt`), with the
   failing check ids. This is the red evidence, captured before any edit (§2c rule 5).
2. **Scope checks re-pinned (D-1).** Each closed task's scope check uses its own pinned range; the log names both
   hashes per task and how each was found (`git log --first-parent`, the merge commit's second parent, etc.).
3. **Later-branch property.** `062-verify.sh` runs every closed task's verify script on (a) `HEAD`, and (b) a
   temporary branch it creates from `HEAD` adding an unrelated file, and requires all to pass in both. The
   temporary branch is created in a temporary clone, never in the caller's worktree, and is removed afterwards.
4. **The scope checks can still fail.** Mutation, run by `062-verify.sh --mutate` in a temporary clone: for each
   re-pinned check, drop one path that the task really changed from its declared-scope list and show that check
   turn red; restore and show green. A re-pinned check that stays green under its mutation fails this criterion.
5. **Retirements are complete and traceable (D-2).** For C1.5b, C8.2, C8.3a, C8.3b: the check no longer runs;
   the comment block exists with a named successor id; `062-verify.sh` asserts each named successor id exists in
   `057-verify.sh` and that `057-verify.sh` passes. A successor id that does not exist reddens the check
   (mutation: rename one successor id in the comment).
6. **No other check was removed or weakened.** `062-verify.sh` compares, per modified verify script, the set of
   check ids that can print PASS/FAIL before and after (from `origin/main`'s blob and `HEAD`'s); the only
   differences allowed are the four retired 006 ids. Any other id missing fails.
7. **ownership.md (D-3).** `git diff` of `contracts/ownership.md` touches only the quoting lines;
   `grep -c "one permitted in-place mutation" contracts/ownership.md` prints 0 and the new heading text is found;
   `032-verify.sh` passes.
8. **Fresh clone.** `062-verify.sh` (with and without `--mutate`) passes in a fresh clone of the branch; output
   pasted in the log.

## Forbidden here (beyond MANAGER.md §3.7)
- Deleting a scope check, or turning it into a skip, warning or `|| true`.
- Re-pinning a scope check to a base other than its own task's fork point, or widening a declared-scope list.
- Rewriting a retired 006 check to assert the new rule (that is 057's job and is already done) or retiring any
  check not named in D-2. Finding another stale check is a stop-and-report, not a licence.
- Editing any contract text other than the two quoting sentences in `ownership.md`.
- Running any verify script's mutation mode inside the authoring worktree if it edits files in place; use a
  temporary clone.

## Dependencies and sequencing
- After task 057 (merged, registry PR #8). Independent of task 007 in file scope (007 creates `tools/registry/`
  and `tests/registry/` and edits `docs/contracts/README.md`), so the two may run in parallel; 007's own verify
  script benefits from 062 landing first because its branch then has green neighbours.
- The sibling task that adds the T1/T3 pipeline carve-out to `ownership.md` (not yet booked) will also edit
  `ownership.md`; 062 lands first and touches only the quote.

## Verification artefact (MANAGER.md §2c)
Declared: `docs/tasks/062-verify.sh`, executable, deterministic, no network; the log pastes its output. This is a
fix round in substance: the breaks it closes are AC1's red inventory, captured before the fix.

## Questions
1. **057-verify.sh V1 needs ajv, which is not in the registry repo.** `057-verify.sh [NODE_MODULES_DIR]` counts a
   missing ajv as a FAILURE by its own rule ("a skip never yields green"), so 057-verify.sh is red in any
   environment without a node_modules holding ajv 8, independent of this task. `062-verify.sh` therefore
   requires `NODE_MODULES_DIR` (or env `WOM_NODE_MODULES`) and fails at AC0 without it. This run used
   `/tmp/fc041/node_modules` (ajv 8.20.0), the only ajv 8 on this machine; the site repo has no `node_modules`
   checked out. Not changed (outside scope, and weakening it is forbidden). Manager: should a registry
   dev-dependency location be named, or should closed-task scripts take V1 from the site repo's CI instead?
2. **057-verify.sh T2 and S4 were also red on pristine main, beyond the S1 the spec names.** They read the same
   moving `git merge-base HEAD origin/main` as S1 (on main it is HEAD itself, so T2's "pre-change blobs" are the
   post-change blobs and S4 diffs nothing). I fixed all of T2, S1, S2, S4 with the same D-1 pin, because they
   share one variable and re-pinning only S1 would leave the script red. No check was retired or weakened; flagged
   for the reviewer because the spec text names only S1.
3. **ownership.md line ~980 was not a heading quote.** It reads "that one permitted in-place mutation" (a
   description, not a quotation of the heading), and the spec lists it among the "quoting sentences". I changed
   it minimally to "that permitted in-place mutation (T2)" so the stale "one" is gone, and edited the true quote at
   ~1027 to the heading text verbatim ("The permitted in-place mutations"). Reviewer to confirm that reading.
4. **The spec's AC7 `grep -c "one permitted in-place mutation"` printing 0 is vacuous** (both sentences wrap
   across a line break, so it printed 0 on the pre-change file too: a search that finds nothing, section 2c rule 1).
   `062-verify.sh` AC7 uses a whitespace-normalised search with a positive control (old blob: 2 hits, now: 0).
5. **Check identity in AC6.** The spec's "C8.2" is the FAIL label of the premise check whose PASS label is C8.1
   (one `if`). Retiring it removes the pair; AC6 therefore allows the five labels C1.5b, C8.1, C8.2, C8.3a, C8.3b
   to be missing, which is four retired checks. Evaluated checks in 006: 43 (37 PASS, 6 FAIL) before, 39 (all
   PASS) after.

---
# Task 062 log
- 2026-10-15 manager: spec drafted (session 9) from task 057's hand-back items 2–4.

- 2026-10-15 qa-engineer: **AC1 red inventory, captured before any edit** (clone of the registry at `e009ef0`;
  `main` = `origin/main` = `e009ef0`; probe = one commit adding `probe.txt`; 057 run with ajv 8.20.0). Failing
  check ids (column-0 `FAIL` lines), exit code in brackets:

  | script | on main (e009ef0) | on probe branch |
  |---|---|---|
  | 006-verify.sh | C1.5b, C8.2, C8.3a, C8.3b, C9.4, C9.6 [6] | same six [6] |
  | 008a-verify.sh | the declared-scope check ("paths outside the declared scope") and "changed or unverifiable: contracts" [2] | same two [2] |
  | 032-verify.sh | none [0] (172 PASS) | S4 [1] |
  | 034-verify.sh | none [0] (36 PASS) | none [0] |
  | 057-verify.sh | T2, S4 [2] (V1 also fails without an ajv path, by design) | S1, S4, T2 [3] |

  034 has no defect (green on both), so it was not touched. `062-verify.sh` AC1 re-derives this table at `e009ef0`
  in a temporary clone and requires the exact id sets, so the red evidence is reproducible, not asserted.
- 2026-10-15 qa-engineer: **Done (D-3, ownership.md).** `contracts/ownership.md`: two hunks, the quote at ~1027 now
  reads `"The permitted in-place mutations"`, ~980 reads "that permitted in-place mutation (T2)". 032-verify.sh pins
  no quote, so there was nothing to update there and no pin mutation to re-show (AC7.3 asserts that). 032-verify.sh
  stays green (172 PASS, same as before).
- 2026-10-15 qa-engineer: **Done (D-1, pins; AC2).** Pinned hashes per task and how found
  (`git log --first-parent` on main lists the merge commits; the tip is `git rev-parse <merge>^2`, the fork point is
  `git merge-base <merge>^1 <merge>^2`; `062-verify.sh` AC2 re-derives all of them):

  | task | merge commit (PR) | base pin | final pin (merge^2) | script variables |
  |---|---|---|---|---|
  | 006 | 497af6f (#2) | be82c19 (kept: the escalation round 3 start, inside the task range 6a14f9b..2241923) | 2241923 | ROUND3_BASE, ROUND3_FINAL |
  | 008a | a50daac (#7) | 4d4a204 (fork point, unchanged) | 9ccb3ec | BASE, FINAL |
  | 032 | 4d4a204 (#4) | e449e26 (fork point; replaces the computed merge-base) | 76af1bb | SCOPE_BASE, SCOPE_FINAL |
  | 057 | e009ef0 (#8) | a50daac (fork point; replaces the moving merge-base) | 3ab8f43 | BASE_COMMIT, FINAL_COMMIT |

  Each script diffs `base final`, never includes untracked files, and FAILS naming the commit when a pin is not an
  ancestor of HEAD (006 C9.7, 008a "pinned commit ... is not an ancestor", 032 S3a, 057 P0 and T2). 006 keeps its
  existing base (be82c19) and only gains the pinned end, so no base was changed to one other than a fork point of
  the task. 006's C9.5 (no tests/schemas touched) and 008a's "untouched: contracts ..." loop use the same range.
- 2026-10-15 qa-engineer: **Done (D-2, retirements; AC5, AC6).** `006-verify.sh` now has `# RETIRED <id>` blocks
  for C1.5b, C8.2 (with its PASS sibling C8.1), C8.3a, C8.3b, each stating the pinned sentence/premise, ADR-0121 Q-L
  and task 057 as the reason, and `successor:` lines naming 057-verify.sh ids (T1 for the three text checks, O1 and O2
  for the premise) plus the sub-ids inside 057's helpers (`required/born-pending`, `old-gone/rule2-*`,
  fixture `first-publish-born-removed`, oracle mutation `allow_born_removed`). Counts: 006 evaluated 43 checks
  (37 PASS + 6 FAIL) before, 39 (39 PASS + 0 FAIL) after = exactly 4 fewer. No other check in 006/008a/032/057
  disappeared (AC6 id comparison against the `e009ef0` blobs; 008a has no ids, so its 29 messages are compared
  after three explicit renames of the re-pinned messages). 057-verify.sh gained one id (P0).
- 2026-10-15 qa-engineer: **Decisions with reasons.** (a) 062's own scope check measures files changed by
  commits whose subject starts "Task 062" (no pin possible for an unmerged task, and a base..HEAD range would go red
  on later branches, the very defect being fixed). Commits therefore must keep that prefix. (b) The id extractor for
  AC6 only counts digit-bearing tokens at the start of a quoted string, because the retired checks' regex arguments
  produced a spurious "newly". (c) 062-verify.sh tests the COMMITTED HEAD (clones), never the caller's worktree, so
  commit before running. (d) The temporary branches and mutations live in `mktemp -d` clones that the EXIT trap removes.
- 2026-10-15 qa-engineer: **Mutation findings during authoring (fixed in the script, not the targets).** The first
  AC5 mutation did not apply (the successor line occurs three times) and the second stayed green because the renamed
  id survived in the `fail` twin of the same line; the helper now refuses a mutation that does not apply and the
  mutations rename every occurrence. The first AC6 run was red on a spurious id; see decision (b).
- 2026-10-15 qa-engineer: **Fresh-clone proof (AC8)** at `9305a37` (the last script change; later commits only touch
  this log), nested clone of the branch with no local `main`, run as `./docs/tasks/062-verify.sh
  /tmp/fc041/node_modules`. Normal mode, exit 0, 43 PASS, 0 FAIL:

```

== AC1 -- the red inventory, reproduced at the task's base (e009ef0), on main and on a probe branch ==
  main  006   exit=6 failing: C1.5b,C8.2,C8.3a,C8.3b,C9.4,C9.6
PASS  AC1.main.006 failing check ids at e009ef0 are exactly [C1.5b,C8.2,C8.3a,C8.3b,C9.4,C9.6]
  main  008a  exit=2 failing: changed,paths
PASS  AC1.main.008a failing check ids at e009ef0 are exactly [changed,paths]
  main  032   exit=0 failing: -
PASS  AC1.main.032 failing check ids at e009ef0 are exactly [-]
  main  034   exit=0 failing: -
PASS  AC1.main.034 failing check ids at e009ef0 are exactly [-]
  main  057   exit=2 failing: S4,T2
PASS  AC1.main.057 failing check ids at e009ef0 are exactly [S4,T2]
  probe 006   exit=6 failing: C1.5b,C8.2,C8.3a,C8.3b,C9.4,C9.6
PASS  AC1.probe.006 failing check ids on the probe branch at e009ef0 are exactly [C1.5b,C8.2,C8.3a,C8.3b,C9.4,C9.6]
  probe 008a  exit=2 failing: changed,paths
PASS  AC1.probe.008a failing check ids on the probe branch at e009ef0 are exactly [changed,paths]
  probe 032   exit=1 failing: S4
PASS  AC1.probe.032 failing check ids on the probe branch at e009ef0 are exactly [S4]
  probe 034   exit=0 failing: -
PASS  AC1.probe.034 failing check ids on the probe branch at e009ef0 are exactly [-]
  probe 057   exit=3 failing: S1,S4,T2
PASS  AC1.probe.057 failing check ids on the probe branch at e009ef0 are exactly [S1,S4,T2]

== AC2 -- each closed task's scope check is pinned at both ends, and the pins are the task's own ==
  006   merge 497af6f: second parent (tip) 2241923, fork point 6a14f9b; script pins ROUND3_BASE=be82c19 ROUND3_FINAL=2241923
PASS  AC2.006.final ROUND3_FINAL=2241923 is the last commit on the task branch (git rev-parse 497af6f^2)
PASS  AC2.006.base ROUND3_BASE=be82c19 is the round-3 base (the check's existing base, kept) and lies inside the task's range 6a14f9b..2241923
  008a  merge a50daac: second parent (tip) 9ccb3ec, fork point 4d4a204; script pins BASE=4d4a204 FINAL=9ccb3ec
PASS  AC2.008a.final FINAL=9ccb3ec is the last commit on the task branch (git rev-parse a50daac^2)
PASS  AC2.008a.base BASE=4d4a204 is the task's fork point (git merge-base a50daac^1 a50daac^2)
  032   merge 4d4a204: second parent (tip) 76af1bb, fork point e449e26; script pins SCOPE_BASE=e449e26 SCOPE_FINAL=76af1bb
PASS  AC2.032.final SCOPE_FINAL=76af1bb is the last commit on the task branch (git rev-parse 4d4a204^2)
PASS  AC2.032.base SCOPE_BASE=e449e26 is the task's fork point (git merge-base 4d4a204^1 4d4a204^2)
  057   merge e009ef0: second parent (tip) 3ab8f43, fork point a50daac; script pins BASE_COMMIT=a50daac FINAL_COMMIT=3ab8f43
PASS  AC2.057.final FINAL_COMMIT=3ab8f43 is the last commit on the task branch (git rev-parse e009ef0^2)
PASS  AC2.057.base BASE_COMMIT=a50daac is the task's fork point (git merge-base e009ef0^1 e009ef0^2)
PASS  AC2.032.moving no moving merge-base, BASE_REF or untracked-file term remains in the scope checks
PASS  AC2.057.moving no moving merge-base, BASE_REF or untracked-file term remains in the scope checks

== AC3 -- every closed task's verify script passes on HEAD and on a later branch (an unrelated file added) ==
PASS  AC3.head.006 006-verify.sh exits 0 on HEAD
PASS  AC3.head.008a 008a-verify.sh exits 0 on HEAD
PASS  AC3.head.032 032-verify.sh exits 0 on HEAD
PASS  AC3.head.034 034-verify.sh exits 0 on HEAD
PASS  AC3.head.057 057-verify.sh exits 0 on HEAD
PASS  AC3.later.006 006-verify.sh exits 0 on a later branch
PASS  AC3.later.008a 008a-verify.sh exits 0 on a later branch
PASS  AC3.later.032 032-verify.sh exits 0 on a later branch
PASS  AC3.later.034 034-verify.sh exits 0 on a later branch
PASS  AC3.later.057 057-verify.sh exits 0 on a later branch

== AC5 -- the four retirements are complete and traceable (D-2) ==
   C1.5b -> 057-verify.sh T1: exists
   C1.5b -> 057-textchecks.py old-gone/rule2-creation-removed: exists
   C1.5b -> 057-textchecks.py required/born-pending: exists
   C8.2 -> 057-verify.sh O1: exists
   C8.2 -> 057-verify.sh O2: exists
   C8.2 -> 057-gen-fixtures.py first-publish-born-removed: exists
   C8.2 -> 057-oracle.py allow_born_removed: exists
   C8.3a -> 057-verify.sh T1: exists
   C8.3a -> 057-textchecks.py old-gone/rule2-born-removed: exists
   C8.3a -> 057-textchecks.py required/born-pending: exists
   C8.3b -> 057-verify.sh T1: exists
   C8.3b -> 057-textchecks.py old-gone/rule2-creation-removed: exists
   C8.3b -> 057-textchecks.py required/born-pending: exists
PASS  AC5.1 C1.5b, C8.2, C8.3a, C8.3b: no live label remains, each comment block names successors, and every named successor exists
PASS  AC5.2 057-verify.sh (the named successor script) passes on HEAD

== AC6 -- no other check was removed or weakened: check ids before (e009ef0) and after (HEAD) ==
  006: 50 check ids before, 46 after; missing now: ['C1.5b', 'C8.1', 'C8.2', 'C8.3a', 'C8.3b']; allowed to be missing: ['C1.5b', 'C8.1', 'C8.2', 'C8.3a', 'C8.3b']
PASS  AC6.006 only the allowed ids are missing from 006-verify.sh
  008a: 29 check labels before, 29 after; missing now: none; allowed to be missing: none
PASS  AC6.008a only the allowed ids are missing from 008a-verify.sh
  032: 195 check ids before, 195 after; missing now: none; allowed to be missing: none
PASS  AC6.032 only the allowed ids are missing from 032-verify.sh
  057: 16 check ids before, 17 after; missing now: none; allowed to be missing: none
PASS  AC6.057 only the allowed ids are missing from 057-verify.sh
  note: C8.1 is the PASS sibling of C8.2 (one 'if' printed C8.1 or C8.2): retiring C8.2 retires the pair, not a fifth check.
PASS  AC6.034 034-verify.sh is untouched (the inventory showed it green on main and on the probe branch)
  006-verify.sh evaluated checks: before 43 (37 PASS, 6 FAIL), after 39 (39 PASS, 0 FAIL)
PASS  AC6.006.count 006-verify.sh evaluates exactly 4 fewer checks than before (the four retired)

== AC7 -- contracts/ownership.md: only the stale quoting sentences changed (D-3) ==
  the literal grep from the spec: grep -c "one permitted in-place mutation" -> 0 (vacuous: both quotes wrap across a line break, so it prints 0 before and after)
   whitespace-normalised count of 'one permitted in-place mutation': before 2, after 0
   whitespace-normalised count of 'The permitted in-place mutations': before 0, after 1
   hunks in the diff: 2
PASS  AC7.1 whitespace-normalised: old quote 2 -> 0, new heading text found, exactly two hunks, both on the quoting sentences
PASS  AC7.2 032-verify.sh passes on HEAD with the edited ownership.md
PASS  AC7.3 032-verify.sh holds no pin on the old quote (nothing to update; there is no pin mutation to re-show)

== Scope of task 062 itself: files changed by commits whose subject starts 'Task 062' (no pin needed, immune to later branches) ==
  contracts/ownership.md
  docs/tasks/006-verify.sh
  docs/tasks/008a-verify.sh
  docs/tasks/032-verify.sh
  docs/tasks/057-verify.sh
  docs/tasks/062-registry-test-maintenance.md
  docs/tasks/062-verify.sh
PASS  SELF.1 every file task 062 changed is inside its declared file scope
PASS  SELF.2 062-verify.sh is executable

== RESULT ==
ALL CHECKS PASSED
```

  `--mutate`, exit 0, 18 PASS, 0 FAIL:

```

== AC4 / AC5 / AC6 mutations (temporary clone of HEAD; each mutation must turn the named check red, the restore green) ==
PASS  AC4.006.drop-path (C9.3 equality list loses docs/tasks/006-verify.sh) turns red: exit 1, failing [C9.4]
PASS  AC4.006.widen-range (range widened to the task fork point: tests/schemas now in range) turns red: exit 2, failing [C9.4,C9.6]
PASS  AC4.006.bad-pin (unreachable pin must FAIL, never skip) turns red: exit 3, failing [C9.4,C9.6,C9.7]
PASS  AC4.006 restored: exit 0
PASS  AC4.008a.drop-path (declared-scope regex loses docs/contracts/README.md) turns red: exit 1, failing [paths]
PASS  AC4.008a.bad-pin (unreachable pin must FAIL, never skip) turns red: exit 5, failing [changed,changed,changed,changed,pinned]
PASS  AC4.008a restored: exit 0
PASS  AC4.032.drop-path (declared-scope list loses contracts/ownership.md) turns red: exit 1, failing [S4]
PASS  AC4.032.bad-pin (unreachable pin must FAIL, never skip) turns red: exit 1, failing [S3a]
PASS  AC4.032 restored: exit 0
PASS  AC4.057.drop-path (S1 declared-scope regex loses docs/contracts/README.md) turns red: exit 1, failing [S1]
PASS  AC4.057.swap-pins (range reversed: T2 positive control, S2 additions-only and S4 all see the wrong side) turns red: exit 3, failing [S2,S4,T2]
PASS  AC4.057.bad-pin (unreachable pin must FAIL, never skip) turns red: exit 2, failing [P0,T2]
PASS  AC4.057 restored: exit 0
PASS  AC5.mut1 renaming one successor id (057-textchecks.py) reddens the retirement check: FAILED: C1.5b: successor 057-textchecks.py required/born-pendingX does not exist (or does not pass)
PASS  AC5.mut2 renaming the 057-verify.sh id O1 reddens the retirement check: FAILED: C8.2: successor 057-verify.sh O1 does not exist (or does not pass)
PASS  AC5.mut.restore the restored tree passes the retirement check
PASS  AC6.mut removing check id S5 reddens the id comparison: 032: 195 check ids before, 195 after; missing now: ['S5']; allowed to be missing: none

== RESULT ==
ALL CHECKS PASSED
```

- 2026-10-15 qa-engineer: **Remaining:** nothing in scope. Open for the reviewer: Questions 1, 2, 3 above. Status set
  to review. Not pushed, not merged.
- 2026-10-15 manager: fresh-clone re-run at the branch HEAD: `062-verify.sh /tmp/fc041/node_modules` and `--mutate` both
  ALL CHECKS PASSED. Independent review: PASS, five non-blocking notes (006 base kept at round-3 `be82c19`, a recorded
  deviation from D-1, accepted because the exact four-file list only fits that range; the "Task 062" subject filter can miss
  an unprefixed commit, so the merge gate compares the real diff; `057-verify.sh` also needs `PLATFORM_REPO`; ownership.md
  ~1027 reads slightly looser; closed tasks' scope checks no longer count untracked files). Questions triaged: Q2 (057 T2/S2/S4
  re-pinned with S1, one shared base variable) — correct per D-1; Q3 (ownership.md ~980) — accepted; Q4 (vacuous grep) —
  the whitespace-normalised check is the right fix; Q5 — accepted. Q1 (no canonical ajv 8 location; only
  `/tmp/fc041/node_modules`) — booked for Ludwig. Merge: PR opened; held for Ludwig because the branch edits a contract
  sentence (`contracts/ownership.md`).
