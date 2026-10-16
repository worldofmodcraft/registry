# Task 070: no closed task's verify script measures its own change against `HEAD` (audit + re-pin), and every script finds the pinned ajv

- **Mission:** SITE-V1 (verification integrity) — **Status:** spec-approved (manager, solo gate, 2026-10-16, session 10;
  test-artefact maintenance, the shape of tasks 062, 067, 069)
- **Repo:** registry. **Agent / model:** qa-engineer / sonnet (§3.5: changing closed tasks' verify scripts is its own
  reviewed task). **Budget:** small–medium (≤ 2 agent-sessions)
- **Branch / worktree:** `task/070-closed-verify-head-audit` / `~/wt/registry-task-070`, cut from registry `origin/main`
  (`2347ffb`, after 069)
- **Graph:** verification tooling only; no node or edge.

## Objective
1. **The defect class, closed for good.** On 2026-10-16 the manager's merge gate for task 007b found `067-verify.sh`
   AC2.4 red: it checks `git diff "$BASE" HEAD -- docs/contracts/README.md` is empty, so any later task that legitimately
   edits that README (007b does, in scope) turns 067 red. AC2.1–AC2.3 measure `"$BASE" HEAD` on `032-verify.sh` the same
   way. This is the fourth instance of one class in two days (062: 006/008a/032/057; 069: 007a, 067 AC5.1). After this task,
   **every** check in every closed task's verify script that is meant to describe *that task's own change* measures the
   task's pinned range `BASE..FINAL` (FINAL = the last commit of its PR, `<merge commit>^2`), never `HEAD` or the working
   tree. Checks that are meant to hold on the live tree (e.g. 067 AC2.5 "the README states the sentence", 032 N5b) stay
   live — the audit classifies each, with a one-line reason.
2. **Audit artefact.** `docs/tasks/070-audit.md` lists, for every closed verify script on `main` (`006, 007a, 008a, 032,
   034, 057, 062, 066, 067, 069`), every git-diff / file-scope / size / "unchanged" check: line, what it compares, and
   the verdict *own-change → re-pin* or *live property → stays*, with the reason. A script with zero such checks is listed
   with "none found" and the grep that proved it, plus that grep's positive control (§2c rule 1).
3. **ajv default everywhere.** `067-verify.sh` and `069-verify.sh` (and any other closed script that needs ajv) resolve
   it like 057/062 after task 066: argument → `WOM_NODE_MODULES` → `<repo root>/tools/dev/node_modules`, failing (never
   skipping) with a message naming `npm ci --prefix tools/dev`.

## Context to load (exhaustive)
This file; registry `docs/tasks/*-verify.sh` (the ten above), `docs/tasks/062-registry-test-maintenance.md` (D-1),
`docs/tasks/069-closed-verify-maintenance.md` (the pinning pattern and how PR pins were derived), `tools/dev/README.md`;
platform `docs/manager/MANAGER.md` §2c, §3.5, `docs/manager/OPERATIONS.md`.

## Acceptance criteria — `docs/tasks/070-verify.sh`, whose output the log pastes
1. **Red first (§2c rule 5):** before any fix, a commit adds checks to `070-verify.sh` that build a throw-away later branch
   touching `docs/contracts/README.md` (007b's shape) and every other file an own-change check guards, and run each
   closed script there; shown red on that commit for 067 AC2.4 at least, and for every other own-change check the audit
   reclassifies.
2. After the fix, every closed script is green on HEAD **and** on that later branch.
3. Mutations (`--mutate`), each red: for every re-pinned check, widening its range back to `HEAD`; an unreachable pin
   fails, never skips; for the ajv default, removing it from 067 and from 069.
4. Live-property checks are not converted: a mutation that breaks the live property (e.g. deleting the README sentence)
   still reddens the corresponding live check on HEAD.
5. Measured on a quiet machine (`ps` checked and logged before each run), run one script at a time: all ten closed
   scripts green on HEAD; `062-verify.sh`, `067-verify.sh` and `007b-verify.sh` green on the merge of this branch with
   `origin/task/007b-registry-checker-ownership`; `062-verify.sh` green on the merge with
   `origin/task/064-schema-check-end-anchor` (a red that belongs to 064's open R1 cleanup is reported, not fixed here).

## File scope (declared)
`docs/tasks/{006,007a,008a,032,034,057,062,066,067,069}-verify.sh` (re-pins and ajv resolution only),
`docs/tasks/070-closed-verify-head-audit.md` (log), `docs/tasks/070-audit.md` (new), `docs/tasks/070-verify.sh` (new).
Any change under `tests/`, `tools/` or `contracts/` = stop and report.

## Size
Verify scripts and docs only; excluded from the counts. Reading list: 13 files (ten scripts are the subject matter, not
background). Over the cap of 10; reason: the audit's whole point is completeness across all closed scripts — splitting
it per script is exactly how this class survived three earlier rounds.

## Forbidden here
Loosening any check beyond moving its comparison range from `HEAD` to the task's own pinned range; converting a
live-property check into a pinned one; a skip that yields green; running suites concurrently.

## Dependencies
After 069 (merged). Before 007b (PR #12) and 064 (PR #13) merge; both merge `main` after this lands.

---
# Task 070 log
- 2026-10-16 manager (session 10): written and approved (solo gate). Source: manager's merge gate on 007b's merge result
  (`8e0d57b`): 007b, 007a, 008a, 032, 034, 057, 062 green; `067-verify.sh` FAIL AC2.4 "docs/contracts/README.md was
  modified" (`067-verify.sh:76-78`, `git diff "$BASE" HEAD`). 067/069 needing ajv passed explicitly found in 069's gate.
- 2026-10-16 manager: worktree cut from registry origin/main `2347ffb`; dispatched. check-log-entry baseline = 2.
- 2026-10-16 qa-engineer: commits (oldest first): 98a3a30 red-first 070-verify.sh (later branch = 007b shape + edits to the 032/034/006 scripts, ownership.md, and a `Task 062` follow-up commit; runs all ten closed scripts there); f7aceef test fix (probe files must differ from 069's, else 069's own mk_later found nothing to commit); d81ccc6 062-verify.sh AC6 ids, AC6.034, AC6.006.count, AC7.1, SELF re-pinned to BASE062..FINAL062=82fa564 (= eba11b7^2) plus new AC6.0 unreachable-pin FAIL; edda1d5 067-verify.sh AC2.1-AC2.4 re-pinned to BASE..FINAL, ajv default; 3d0a818 069-verify.sh ajv default; 9ce450b docs/tasks/070-audit.md; 0447827 mutation AC4.m2 fix (unique 006 successor line).
- 2026-10-16 qa-engineer: audit summary (details in 070-audit.md): RE-PIN = 067 AC2.1-AC2.4; 062 AC6.006/008a/032/057, AC6.034, AC6.006.count, AC7.1, SELF.1. Already pinned: 006 C9.x, 007a, 008a, 032 S3, 057 S1/S2/S4, 067 AC5.1. Live (stay): 067 AC2.5/AC3, 062 AC2.moving/AC3/AC5/AC7.2, 057 F1/S3, 008a/007a hygiene and status preconditions, 034 (no diff checks; grep + positive control in the audit), 066, 069. Nothing under tests/, tools/, contracts/ touched.
- 2026-10-16 qa-engineer: red first (commit f7aceef, ps others=0): 070-verify.sh exit 12; FAIL AC1.062 (no FINAL062); 062 on the later branch exit 5 (AC6.032, AC6.034, AC6.006.count, AC7.1, SELF.1 red); 067 exit 3 (AC2.1, AC2.4 "docs/contracts/README.md was modified" red; AC3.2 no ajv default); 066 exit 2 (via 062); 069 exit 2 (ajv default). 006/007a/008a/032/034/057 green there.
- 2026-10-16 qa-engineer: 070-verify.sh normal on 9ce450b: ALL CHECKS PASSED. AC1.062, AC1.067, AC1.062.base PASS; AC2.006 ... AC2.069 all ten exit 0 on the later branch; AC2.067.AC2.1-2.5 and AC2.062.AC6.006/008a/032/057/006.count/034, AC7.1, SELF.1 PASS.
- 2026-10-16 qa-engineer: 070-verify.sh --mutate on 0447827 (ps others=0): ALL CHECKS PASSED. AC3.m1 067 FINAL->HEAD red (AC2.1 count 9); m2 067 unreachable pin red (AC2.1 count 0, AC5.1 names deadbee); m3 067 ajv default removed red (AC3.2); m4 062 FINAL062->HEAD red (AC6.032, AC6.034, AC6.006.count, AC7.1, SELF.1); m5 062 unreachable red (AC6.0 names deadbee); m6 069 ajv default removed red (AC4.0, AC7.0); AC4.m1 README sentence deleted reddens live 067 AC2.5; AC4.m2 006 retirement successor renamed reddens live 062 AC5.1.
- 2026-10-16 qa-engineer: criterion 5, one script at a time, ps others=0 before each (driver /tmp/w070/c5.sh, outputs /tmp/w070/c5/). HEAD 0447827: 006, 007a, 008a, 032, 034, 057, 062, 066, 067, 069 all end ALL CHECKS PASSED / failed=0. Merge of HEAD with origin/task/007b (local ref 3b6a5ab): 062 and 067 ALL CHECKS PASSED; with origin/task/064 (local ref 942211c): 062 ALL CHECKS PASSED. Caveat: my driver printed the exit status after a command substitution, so its "exit=" values are meaningless; verdicts are from each script's final lines (a script's exit code is its failure count). Refs are the local remote-tracking refs (no fetch made).
- 2026-10-16 qa-engineer: FINDING: 007b-verify.sh on the merge with HEAD: "FAIL files outside the declared scope: .gitignore ..." plus the 066/069 files (007b-verify.sh:104-107 diffs origin/main...HEAD, a moving base, same defect class). In my merge clone origin/main was a stale local main, so this is probably a measuring artefact; the re-run with origin/main set to this branch's tip was NOT completed. Not fixed here (007b's file, outside scope).

## Questions
- Q1: 007b-verify.sh scope check uses origin/main...HEAD; it is right only if origin/main is current. A) manager re-runs it at the merge gate with origin/main = main after 070 merges ★ B) follow-up task for 007b.
- 2026-10-16 qa-engineer: follow-up on the finding: with refs/remotes/origin/main set to this branch tip (0447827) in the 007b merge clone, 007b-verify.sh exits 0, SUMMARY failed=0, no FAIL line. So the earlier red was the stale origin/main of my clone, not a defect of the merge; Q1 stands only as a note that 007b-verify.sh needs a current origin/main.
- 2026-10-16 manager: independent review FAIL. B1 (blocking): 062 AC6.006/008a/032/057, AC6.034 and AC6.006.count were live "no closed check removed" guards; pinning them to BASE062..FINAL062 drops that protection on HEAD (070-verify.sh mk_later even renames 032 S5 and expects 062 green). Remedy proposed by the reviewer: keep the pin, add a live guard (ids at HEAD ⊇ ids at FINAL062 minus the four 006 retirements; 006 count at HEAD ≥ FINAL062's), mutation red; drop the S5 rename from mk_later. F2 (non-blocking): live check that 032 N5b still carries the full sentence. F3 (non-blocking): live check against re-introducing the stale quote in ownership.md. Budget: both budgeted agent sessions used → §8 stop-and-ask; Ludwig declined the multiple-choice question; nothing further done on 070 pending his word. PR #16 not merged.
- 2026-10-16 manager: Ludwig (in session, multiple choice): "Extend by 1 fix round" — budget extended to 3 agent-sessions for this fix round only. Fix round sent to the same agent: B1 live id-superset guard + 006 count guard with mutations, drop the S5 rename from mk_later (or expect red), F2 and F3 live checks; red first. Log baseline recounted below.
- 2026-10-16 qa-engineer (fix round, B1/F2/F3): commits 689d15d red-first expectations in 070-verify.sh (mk_later no longer renames S5; new mk_deleter branch deleting/renaming one check in each of 006/008a/032/034/057; AC5 expects AC6L.006/008a/032/034/057/006.count red there and the pinned AC6.*/AC7.1/SELF.1 green; AC2.067.AC2.6, AC2.062.AC7.4 and AC6L.* expected PASS on the additions branch; --mutate AC5.m1 guards removed, m2 F2 broken, m3 F3 broken); then fix commit (062: LIVE_IDS_SCRIPTS/LIVE_COUNT_GUARD, AC6L.* superset-of-FINAL062 id guards and HEAD>=FINAL062 count guard, AC7.4; 067: AC2.6) and audit update (pinned part + live guard per converted check). Red evidence on 689d15d (ps others=0): 070-verify.sh normal exit 14, FAIL AC2.067.AC2.6, AC2.062.AC7.4, AC2.062.AC6L.006/008a/032/034/057/006.count (no such lines), and AC5.AC6L.* x6 FAIL "a deleted/renamed check left it green" while AC5.pinned.* x8 PASS (this is the B1 loss shown). --mutate on 689d15d running; green runs follow.
- 2026-10-16 qa-engineer (fix round): red-first --mutate on 689d15d (clone, ps others=0): AC5.m0 "cannot neutralise the live guards", AC5.m2 (F2) and AC5.m3 (F3) "stayed green" (no live guard exists yet), AC3.m4 mislabelled; i.e. the new expectations are red before the fix.
- 2026-10-16 qa-engineer (fix round): commits after the red one: f872ac4 (062: LIVE_IDS_SCRIPTS="006 008a 032 034 057", AC6L.<n> every check id/label at FINAL062 still exists at HEAD; LIVE_COUNT_GUARD, AC6L.006.count HEAD count >= FINAL062 count; AC7.4 F3 stale quote absent at HEAD; 067: AC2.6 F2 N5b still pins the full sentence at HEAD) and the audit update (pinned part + live guard per converted check); 857c14b and 2358dd5 fix 070-verify.sh expectations (AC3.m4 no longer lists 032; AC5.m1 count-guard line).
- 2026-10-16 qa-engineer (fix round): 070-verify.sh normal on 857c14b (ps others=0) ALL CHECKS PASSED. AC2 additions branch: all ten scripts exit 0, pinned and live ids PASS (AC2.067.AC2.1-2.6, AC2.062.AC6.*, AC7.1, AC7.4, SELF.1, AC6L.*). AC5 deleter branch (032 S5, 034 C4.1, 057 O1 renamed, 008a label reworded, 006 C10.3 deleted): PASS AC5.AC6L.006/008a/032/034/057 red ("a check id ... that existed at 82fa564 is gone at HEAD") and AC5.AC6L.006.count red ("evaluates 38 checks at HEAD, fewer than at 82fa564 (39)"); AC5.pinned.AC6.006/008a/032/057/034/006.count/AC7.1/SELF.1 stay green.
- 2026-10-16 qa-engineer (fix round): 070-verify.sh --mutate on 2358dd5 (ps others=0) ALL CHECKS PASSED: AC3.m1-m6 as before (m4 now red on AC6.034, AC6.006.count, AC7.1, SELF.1); AC4.m1, AC4.m2; AC5.m1 "with the six live guards removed from 062, the delete/rename branch goes undetected (6 of 6 ids stay green), so AC5 turns red on such a 062"; AC5.m2 F2 broken (N5b reverted to the old phrase) red on 067 AC2.6; AC5.m3 F3 broken (stale quote re-introduced) red on 062 AC7.4.
- 2026-10-16 qa-engineer (fix round): `git fetch origin` made no change: 007b is 3b6a5ab, 064 is 942211c, main 2347ffb (the refs of the first session were already current). Criterion 5 follows with a corrected driver (real exit codes; origin/main set to the pre-merge branch tip in the merge clones).
