# Task 062: Registry verify scripts stay green on later branches and stop pinning the superseded born-`removed` rule

- **Mission:** SITE-V1 (keeps D1's verification trustworthy) — **Status:** spec-approved (manager, 2026-10-15, SPEC-CHECKLIST 1–8 verified solo; review by an independent reviewer)
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
None at spec time.

---
# Task 062 log
- 2026-10-15 manager: spec drafted (session 9) from task 057's hand-back items 2–4.
