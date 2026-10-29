# Task 089b: registry closed scripts — part B (contract and R11 pins; findings 8-12, S4)

- **Mission:** SITE-V1 (verification integrity) — **Status:** in-progress 2026-10-28 (cut from umbrella 089 at dispatch, session 13; umbrella spec-approved 2026-10-26, parts per Q5 ★ A)
- **Agent / model:** qa-engineer (model per frontmatter) — **Budget:** medium (≤ 3 agent-sessions)
- **Branch / worktree:** `task/089b-closed-verify-sweep-registry-b` / `~/wt/registry-task-089b`, from registry main `e2f7fe3`
- **Umbrella (authoritative for findings, pins, criteria, forbidden list, Q1-Q6):** `docs/tasks/089-closed-verify-sweep-registry.md` (copied
  into this branch from platform `session/13` `5c59f34`; read-only here except nothing — do not edit it).

## Scope of this part
Findings **8, 9, 10, 11, 12** and side finding **S4** of the umbrella table. Source files (4): `docs/tasks/065-verify.sh`,
`docs/tasks/075-verify.sh`, `docs/tasks/039a-verify.sh`, `tests/registry/test_ci_gate.py`. New: `docs/tasks/089b-verify.sh`.
Log: this file. Anything else = stop and report.
Decisions already taken (umbrella): Q1 assumed A (document the double run in the 039a header; S4); Q2 ★ B (move AC9ProductionR11Unconfigured
into `039a-verify.sh` at the pin, delete the unit test, show the preserved assertion).

## Acceptance criteria
The umbrella's criteria 1-5, 8, 9, 10 and 11, restricted to findings 8-12 and S4, shipped as `docs/tasks/089b-verify.sh`.
Criterion 9 (quiet machine) is mandatory: one script at a time, `ps` logged before each run.

## Questions  (agent-maintained; see MANAGER.md 8b)
- Q7: S4 is not only a doubled run, it is a deadlock. `039a-verify.sh`'s sweep runs `039b-verify.sh` with no flag; 039b then runs its own AC12 sweep and its
  `others_running` predicate (`grep -v '039b-verify\.sh'`) counts the parent `039a-verify.sh`, so 039b waits for its parent (up to 21600 s) and then FAILs every
  script. Observed with a fixture process list (089b-verify.sh AC8.1/AC8.1b). | options: A) document the double run only (Q1 assumed A; leaves 039a red or six hours
  slower on every standalone run); B) 039a passes `--no-closed` to 039b in its sweep (039b's own checks still run; only its AC12 sweep, which duplicates 039a's loop
  minus 039a and 039b themselves, is skipped; 039b prints `AC12 NOT RUN`, already a documented opt-in); C) 039a skips `039b-verify.sh` (loses 039b's own checks in the suite) |
  assumed: B (★) | built on assumption: `039a-verify.sh` sweep call and header only; criterion 8 (each script once) is demonstrated with the invocation count.
  Supersedes Q1's assumed A with evidence; Q1 itself was never answered by the manager.
- Q8: finding 12 is fixed, not recorded live: with the counts taken at HEAD a test added to a counted class reddens 039a (observed: `expected 7 ok tests, ran 8`). The fix reads
  the test names from `tests/registry/test_ci_gate.py` at `$FINAL`; every pinned test must be ok at HEAD, extra tests are allowed, a missing or renamed pinned test FAILs.
  | options: A) names from the pinned blob, extras allowed (assumed, ★); B) exact counts from the pinned blob run in isolation (would also run HEAD's tools against the old tests and
  redden on legitimate later composer changes) | assumed: A | built on assumption: the `class_check` function of 039a only.
- Q9: criterion 5/9 for 039a: the merged-branch controls run 039a-verify.sh TRUNCATED before its AC12 section (everything before it is where all fixed checks live; AC12 is the
  hours-long sweep of the other scripts). The whole 039a is run once, alone, at the end on HEAD (task log). | options: A) as built; B) also run the whole 039a on a merge (hours) |
  assumed: A | built on assumption: none beyond the evidence shape.

---
# Task 089b log  (append-only)
- 2026-10-28 manager (session 13): cut from umbrella 089 and dispatched; base registry main `e2f7fe3` (087, 082, 039b, 092 merged). Machine quiet.
- 2026-10-28 qa-engineer: read the task, the umbrella, 084/087 (pattern), the four sources. Pins re-derived (git, full SHAs): merge of PR #18 (task 075) `4356583fb2360592a680f40bee396f9f23df35a4`,
  ^1 `79d537779c9fe717657aed9c4c85f90ba71fcd14` = merge-base = 075 BASE, ^2 `7d91a3d54d19431f4e3eff2dbed409cf00320887` = 075 FINAL; merge of PR #19 (task 065) `208c6d1ae63ff56ccac85c6fc9a200ac77259fda`,
  ^2 `e87498b47eced6fe388ec798ce31fbb6db09c16f` = 065 FINAL (identical to the pinned fix commit `e9b121e` for test_hardening.py: `git diff e9b121e e87498b -- tests` is empty);
  merge of PR #21 (task 039a) `426873502a150ef746063c1b55c2cfbfeed31566`, merge-base `4356583fb2360592a680f40bee396f9f23df35a4` = 039a BASE; 039a FINAL `ceb0458346ecf9f68454d1e3f2f1dafc1ea301c4`
  is NOT ^2 (`18e8041836fee606dee486cd243caa2ac16dfe6f`): it is its ancestor, and `git diff --quiet ceb0458 18e8041 -- tools/registry config tests/registry contracts` is clean (only log/script commits follow).
  The 8 other umbrella pins (e87498b, 7d91a3d, ceb0458) match the umbrella table exactly.
- 2026-10-28 qa-engineer: classification (own-change vs live), one line each. 065 AC3.5 (test_hardening split): OWN-CHANGE, moved to blob at FINAL. 065 AC1/AC3.1-4/AC1.5: already on BASE/RED/FIX (pinned);
  065 AC2, AC4, AC5, AC6: LIVE (tests, validators, closed scripts, mutations) stay on HEAD. 075 AC4 (ownership.md sentences): OWN-CHANGE, moved to blob at FINAL; 075 AC6/AC1 scope: already pinned (084);
  075 AC2/AC3 (tests, b7 mutations), 032-verify.sh: LIVE. 039a `HEAD:config/r11-identity.json`: OWN-CHANGE, moved to blob at FINAL; 039a per-class counts: OWN-CHANGE (counts of 039a's own test file), moved to
  names read from the blob at FINAL; 039a AC11 own_change_checks, AC8 independent scan of ci_gate.py (reads the HEAD clone's ci_gate.py: LIVE property, composer must stay free of network/env/shell), AC12: LIVE.
- 2026-10-28 qa-engineer: finding 8 diagnosis (the 039b agent's 065 failure). Observed, not inferred: (1) `git diff e87498b HEAD -- tests/registry/test_hardening.py` is EMPTY, and no commit between touches it
  (`git log e87498b..HEAD -- tests/registry/test_hardening.py` empty), so AC3.5 cannot have failed from a later edit of that file on 039b's base; (2) the UNFIXED 065-verify.sh `--mutate` (which includes AC3.5, skips only
  AC4) run on a clone detached at 039b's merge `e9091748bec659ee574b25db02e45152236a2ae0`: exit 0, ALL CHECKS PASSED (output /tmp/w089b/065-unfixed-on-039b.out); (3) the 039b task log (039-registry-ci-workflow.md
  lines 456-482) names the failing check as AC4.2 (070 exit 2 via 067/069/062) at a time other agents' verify scripts ran, and the manager's quiet run was green: concurrency. So the suspicion "AC3.5 is the cause" is
  REFUTED by observation; AC3.5 is nonetheless an own-change-at-HEAD read and is fixed on its merits (red fixture below). The full non-mutate 065 on 039b's merge is run at the end (criterion 10).
- 2026-10-28 qa-engineer: S4 finding while reading 039b-verify.sh:192: `others_running` excludes only `039b-verify.sh`, so under 039a's sweep (which runs 039b with no flag) 039b waits for its parent 039a. Booked as Q7.
- 2026-10-28 qa-engineer: RED FIRST. Harness `docs/tasks/089b-verify.sh` written; run (machine quiet: `ps` showed no *-verify.sh process; PYTHONDONTWRITEBYTECODE=1) with a temporary copy whose PIN_FIX is the OLD ref (so NEW = unfixed):
  19 FAIL, all of them the expected ones. OLD-script red evidence (the point of the fixtures), pasted:
      PASS  AC0.1 exactly one merge commit for task/075-takedown-only-removal: 4356583fb2360592a680f40bee396f9f23df35a4
      PASS  AC0.1 exactly one merge commit for task/065-entry-schema-key-id: 208c6d1ae63ff56ccac85c6fc9a200ac77259fda
      PASS  AC0.1 exactly one merge commit for task/039-registry-ci-workflow: 426873502a150ef746063c1b55c2cfbfeed31566
      FAIL  AC0.2 cannot read a pin or find a merge (075 FINAL='7d91a3d' 065 FINAL='' 039a FINAL='ceb0458'): a search that finds nothing is broken
      FAIL  AC0.8 065 AC3.5 still reads the HEAD clone (or does not read the pin)
      FAIL  AC0.9 075 AC4 still reads the HEAD clone (or does not read the pin)
      FAIL  AC0.10 039a still reads r11-identity.json at HEAD (or does not read the pin)
      FAIL  AC0.11 039a does not read the test file at $FINAL, or still counts the AC9 class
      FAIL  AC0.12 the AC9 unit test is still in tests/registry/test_ci_gate.py, or its condition is not asserted in 039a-verify.sh
      PASS  AC1.8a the OLD 065-verify.sh on OLD + a later test_hardening.py edit: exit 1, FAIL  AC3.5 test_hardening split is not as specified
      PASS  AC1.8b control: the OLD 065-verify.sh on plain OLD (the later branch is the cause): exit 0
      FAIL  AC1.8c the NEW 065-verify.sh on HEAD + the same later edit: wanted green, got exit 1 /^PASS  AC3\.5 / /!^FAIL/: FAIL  AC3.5 test_hardening split is not as specified|
      PASS  AC1.9a the OLD 075-verify.sh on OLD + a later ownership.md edit: exit 1, FAILMSG R3 does not state that R11 rejects (pattern '`R11` rejects it as well')
      PASS  AC1.9b control: the OLD 075-verify.sh on plain OLD: exit 0
      FAIL  AC1.9c the NEW 075-verify.sh on HEAD + the same later edit: wanted green, got exit 1 /^PASS  R11.s mixed-PR sentence is amended/ /!^FAIL/: FAILMSG R3 does not state that
      PASS  AC1.10.00 positive control: both truncated copies are non-empty (176 / 176 lines)
      PASS  AC1.10a the OLD 039a-verify.sh on OLD + R11 configured: exit 3, FAIL  test_ci_gate.py red (exit 1)
      PASS  AC1.10b control: the OLD 039a-verify.sh (truncated) on plain OLD: exit 0
      FAIL  AC1.10c the NEW 039a-verify.sh on HEAD + R11 configured: wanted green, got exit 3 /^PASS  AC9 config/r11-identity.json at FINAL/ /!^FAIL/: FAIL  test_ci_gate.py red (exi
      FAIL  AC1.11 the moved assertion is red when config/r11-identity.json at the pin is non-null: wanted red, got exit 3 /^FAIL  AC9 config/r11-identity.json at FINAL .* is not th
      PASS  AC1.12a the OLD 039a-verify.sh on OLD + a test added to AC2PositiveControls: exit 1, FAIL  AC2 positive controls: expected 7 ok tests, ran 8, ok 8
      FAIL  AC1.12b the NEW 039a-verify.sh on HEAD + the same added test: wanted green, got exit 1 /^PASS  AC2 positive controls/ /!^FAIL/: FAIL  AC2 positive controls: expected 7 o
      FAIL  AC1.12c positive control: the NEW 039a-verify.sh still fails when a pinned test disappears from a counted class: wanted red, got exit 0 /^FAIL  AC4 identity source/: 
  Also in that run: AC1.8c/1.9c/1.10c/1.12b FAIL (NEW = unfixed: the same scripts redden on the merges), AC1.12c FAIL (the unfixed 039a stays GREEN when a pinned test is renamed: counts alone cannot see it), AC3.x FAIL
  (the unfixed 075/065 do not turn red on `deadbee`), AC8.3 FAIL (no `--no-closed`). Full text: the run is reproducible with `docs/tasks/089b-verify.sh` and PIN_FIX = e2f7fe383d7b2231e1d37a73e474bca7ed56af46.
- 2026-10-28 qa-engineer: FIX commit `0f7f5b0bb9a54d6afcc519974dd4c1fe1dd1cc5e` (4 files, +60/-27: 065-verify.sh AC3.5 + FINAL pin; 075-verify.sh AC4 + full-SHA pins; 039a-verify.sh r11 config at FINAL, class_check from the
  test names at FINAL, 039b called with `--no-closed`, header paragraph, full-SHA pins; test_ci_gate.py -6 lines: class AC9ProductionR11Unconfigured deleted, nothing added). Harness fixes: `979c3dfc5bbbe1fa91185a098e117649905d0ddf`.
  Finding 11, the assertion is preserved: the deleted test asserted `json.loads(config/r11-identity.json) == {"schema_version": "1.0.0", "r11_identity": None}` on the live file; 039a-verify.sh now asserts
  `d=={"schema_version":"1.0.0","r11_identity":None}` on `G show "$FINAL:config/r11-identity.json"` ("AC9 config/r11-identity.json at FINAL ... parses with r11_identity null"); AC0.12 asserts both halves.
  Finding 12 outcome: FIXED (not recorded live): the unfixed 039a reddened when a later branch added a test to AC2PositiveControls (AC1.12a: `expected 7 ok tests, ran 8`); the fixed one stays green (AC1.12b), still
  fails when a pinned test is renamed/removed (AC1.12c), and the widened-back-to-exact-counts mutation is red (AC4.m12). Q8 booked.
  GREEN run of the harness (PIN_FIX = the fix commit; machine quiet, `ps` empty before; PYTHONDONTWRITEBYTECODE=1) after the fix, red/green per finding (AC0/AC1/AC3/AC5/AC8 lines):
      PASS  AC1.8a the OLD 065-verify.sh on OLD + a later test_hardening.py edit: exit 1, FAIL  AC3.5 test_hardening split is not as specified
      PASS  AC1.8b control: the OLD 065-verify.sh on plain OLD (the later branch is the cause): exit 0
      PASS  AC1.8c the NEW 065-verify.sh on HEAD + the same later edit: exit 0
      PASS  AC1.9a the OLD 075-verify.sh on OLD + a later ownership.md edit: exit 1, FAILMSG R3 does not state that R11 rejects (pattern '`R11` rejects it as well')
      PASS  AC1.9b control: the OLD 075-verify.sh on plain OLD: exit 0
      PASS  AC1.9c the NEW 075-verify.sh on HEAD + the same later edit: exit 0
      PASS  AC1.10.00 positive control: both truncated copies are non-empty (176 / 203 lines)
      PASS  AC1.10a the OLD 039a-verify.sh on OLD + R11 configured: exit 3, FAIL  test_ci_gate.py red (exit 1)
      PASS  AC1.10b control: the OLD 039a-verify.sh (truncated) on plain OLD: exit 0
      PASS  AC1.10c the NEW 039a-verify.sh on HEAD + R11 configured: exit 0
      PASS  AC1.11 the moved assertion is red when config/r11-identity.json at the pin is non-null: exit 4, FAIL  FINAL is not an ancestor of TIP
      PASS  AC1.12a the OLD 039a-verify.sh on OLD + a test added to AC2PositiveControls: exit 1, FAIL  AC2 positive controls: expected 7 ok tests, ran 8, ok 8
      PASS  AC1.12b the NEW 039a-verify.sh on HEAD + the same added test: exit 0
      PASS  AC1.12c positive control: the NEW 039a-verify.sh still fails when a pinned test disappears from a counted class: exit 1, FAIL  AC4 identity source: pinned test(s) not ok at HEAD: test_actor_env_and_commit
      PASS  AC5.1 NEW 065-verify.sh --mutate on HEAD: exit 0
      PASS  AC5.2 NEW 075-verify.sh on HEAD: exit 0
      PASS  AC5.3 NEW 039a-verify.sh (truncated before AC12) on HEAD: exit 0
      PASS  AC3.1 065 with FINAL=deadbee: exit 1, FAIL  AC3.5 test_hardening split is not as specified at FINAL deadbee (or the pin is unreadable)
      PASS  AC3.2 075 with FINAL=deadbee: exit 4, FAIL  pin deadbee does not exist
      PASS  AC3.3 039a with FINAL=deadbee: exit 17, FAIL  pin deadbee does not exist
      PASS  AC3.4a positive control: the skip-word grep matches a sample line
      PASS  AC3.4 'skip' / 'not evaluated' occur 0 times in the outputs of the deadbee and HEAD runs
  MUTATIONS (--mutate, same conditions; each widened check red AND the only FAIL line of its run):
      PASS  AC4.m8 065 AC3.5 widened back to the HEAD clone's test_hardening.py turns red, and only that check: exit 1, FAIL  AC3.5 test_hardening split is not as specified at FINAL e87498b47eced6fe388ec798ce31fbb6db
      PASS  AC4.m9 075 AC4 widened back to the HEAD clone's ownership.md turns red, and only that check: exit 1, FAILMSG R3 does not state that R11 rejects (pattern '`R11` rejects it as well')
      PASS  AC4.m10 039a r11-identity.json widened back to HEAD turns red, and only that check: exit 1, FAIL  AC9 config/r11-identity.json at FINAL ceb0458346ecf9f68454d1e3f2f1dafc1ea301c4 is not the null configurati
      PASS  AC4.m11 039a moved AC9 assertion: the same line, widened (finding 11 is this check) turns red, and only that check: exit 1, FAIL  AC9 config/r11-identity.json at FINAL ceb0458346ecf9f68454d1e3f2f1dafc1ea3
      PASS  AC4.m12 039a class_check widened back to exact counts at HEAD turns red, and only that check: exit 1, FAIL  AC2 positive controls: pinned test(s) not ok at HEAD: 
  The remaining AC11 lines of that run (scope, hunk limits, ancestry) pass once the pins are committed (pin commit follows). Finding 8 is 065 AC3.5; 9 is 075 AC4; 10/11 are the 039a config line (m10/m11 are one line, mutated once
  under two labels); 12 is class_check; S4 is the sweep call (AC8: NEW sweep invoked each of the 22 other scripts once, 039b with `--no-closed`; the OLD sweep ran 039b with no flag, whose predicate waits for a parent 039a: AC8.1/AC8.1b).
- 2026-10-28 qa-engineer: found by running the harness under its REAL name (earlier runs used a renamed copy): AC8's stubbed whole-039a run deadlocked in principle, because 039a's AC12 quiet-wait counts the
  parent `089b-verify.sh` process as another running verify script (same class of defect as S4). The stub run now puts a `ps` shim on PATH for that one child that hides only `089b-verify.sh`; nothing else is hidden.
  Whole harness (default mode, real name, quiet machine: `ps` empty at 2026-10-28T10:23:33Z), 13 minutes: every check PASS (AC0 x13, AC1 x15, AC5 x3, AC3 x6, AC8 x9) except AC11.9 (hunk-limit regex too narrow for the
  replaced old lines of class_check and the sweep call: a harness bug, not a source finding), widened in commit 9ec482278f58eb94c0fe8e8a057f3fe752ea30ad. Mutation mode (`--mutate`) 5/5 PASS (above).
- 2026-10-28 qa-engineer: pins re-set (FINAL `9ec482278f58eb94c0fe8e8a057f3fe752ea30ad`, TIP `7d195338ee6ad07df8db224e380a27ac48033808`; the re-pin commit follows TIP and changes only 089b-verify.sh);
  `089b-verify.sh --own-only` ALL CHECKS PASSED (AC11.1-11.11). Branch pushed (no PR). LONG RUNS (criteria 9 and 10) started 2026-10-28T10:36:05Z by a sequential driver
  (`/tmp/w089b/long-driver.sh`, not a *-verify.sh name; ps logged before each step in `/tmp/w089b/long/status.txt`; outputs `/tmp/w089b/long/*.out`), HEAD under test `2383177c00d0c4546979f08dd5f94310f3369b83`:
  L1 065 unfixed then fixed on 039b's merge `e9091748...` (criterion 10); L2 whole `039a-verify.sh` on plain HEAD (every closed script one at a time); L3 whole `039a-verify.sh` on HEAD + four synthetic
  later branches (ownership sentence, test_hardening test name, R11 configured, test added to test_ci_gate.py). Resume: `cat /tmp/w089b/long/status.txt`; a step missing its `exit` line has not finished.
- 2026-10-28 manager (session 13): the qa-engineer run stopped at its 80-turn cap (§8 turn caps: handled as a budget stop, no silent retry). State verified from disk: commits up to `2d8063c` pushed; log check `check ... 1` exit 0; the long-run driver `/tmp/w089b/long-driver.sh` (PID 3956671, detached) is one sequential chain, still in L1-065-unfixed (started 10:36:05Z); L1-fixed, L2, L3 remain (est. 12-16 h in total). Manager lets it finish, watches `/tmp/w089b/long/status.txt`, and dispatches a fresh qa-engineer afterwards only to read the outputs into this log and finish criteria 9/10.
- 2026-10-29 qa-engineer (readout of the finished long runs; READ-ONLY analysis, no verify script was run, no script changed). Driver `/tmp/w089b/long-driver.sh`, HEAD0 `2383177c00d0c4546979f08dd5f94310f3369b83`.
  Timeline from `/tmp/w089b/long/status.txt` (each step's `ps` list before it was empty): L1-unfixed 2026-10-28T10:36:05Z-13:14:19Z exit 0; L1-fixed 13:14:19Z-15:57:48Z exit 0;
  L2 15:57:49Z-21:22:05Z exit 0; L3 21:22:06Z-2026-10-29T02:40:59Z **exit 2**. What each step ran (driver): L1 = clone detached at the 039b merge `e9091748bec659ee574b25db02e45152236a2ae0`, `bash docs/tasks/065-verify.sh $NM`
  (no flag, i.e. the full non-mutate 065) first as committed there (unfixed), then with `065-verify.sh` replaced by the blob from HEAD0 (fixed); L2 = plain clone at HEAD0, `bash docs/tasks/039a-verify.sh $NM` (whole, incl. AC12 sweep); L3 = clone at HEAD0 plus four
  `--no-ff` merged synthetic branches (b1 ownership.md `and \`R11\` rejects it as well` -> `and \`R11\` also rejects it`; b2 test_hardening.py `test_f1_key_id_with_trailing_newline_is_rejected_task_065` -> `test_f1_key_id_trailing_newline_is_rejected_task_065`;
  b3 config/r11-identity.json `"r11_identity": null` -> `{"provider": "github", "id": 1, "name": "later-identity"}`; b4 a test `test_synthetic_later_addition` added to `AC2PositiveControls` in test_ci_gate.py), then the same whole 039a.
  Frame check: `git diff 2383177 HEAD --stat` in L3.R9Uo = exactly those four files (6+/3-).

  RESULTS, trimmed (full files in `/tmp/w089b/long/`):
      L1-065-unfixed-on-039b-merge.out (88 lines): `PASS  AC4.3 006-verify.sh exits 0 at HEAD ...` / `PASS  AC5.1 every extracted example validates` / `== RESULT == ALL CHECKS PASSED`   (exit 0)
      L1-065-fixed-on-039b-merge.out   (88 lines): same last lines, `ALL CHECKS PASSED`   (exit 0)
      L2-039a-full-on-HEAD.out (99 lines): `PASS  full tests/registry suite: Ran 373 tests in 30.051s`, every `PASS  NNN-verify.sh exits 0 on HEAD` incl. `089b-verify.sh`, `092-verify.sh`; `ALL CHECKS PASSED`   (exit 0)
      L3-039a-full-on-merged-HEAD.out (82 lines): `PASS  AC2 positive controls: all 7 tests the file has at FINAL are ok at HEAD (HEAD runs 8 in the class, 8 ok)` ; `PASS  AC9 config/r11-identity.json at FINAL ceb0458346ecf9f68454d1e3f2f1dafc1ea301c4 parses with r11_identity null` ;
        `PASS  full tests/registry suite: Ran 374 tests in 29.847s` ; `PASS  065-verify.sh exits 0 on HEAD` ; `PASS  075-verify.sh exits 0 on HEAD` ; `PASS  062/066/067/069/070/071/082/084/087/092 ... exits 0 on HEAD` ;
        line 67: `FAIL  064-verify.sh exit 1 on HEAD: FAIL  AC4.2 070-verify.sh exits 1 at HEAD; failing: FAIL  AC2.066 066-verify.sh exit 1 on the later branch; FAIL  C3b 062-verify.sh | `
        line 78: `FAIL  089b-verify.sh exit 3 on HEAD: FAIL  AC1.8.1 cannot build the later-branch merge on HEAD FAIL  AC1.9.1 cannot build the later-branch merge on HEAD FAIL  AC1.10.2 cannot build the config-later-branch merge on HEAD `
        `== RESULT == 2 CHECK(S) FAILED`   (exit 2). No other FAIL line in L1, L2 or L3; no `AC1.5` line at all in L2 or L3.

  (b) 089b-verify.sh in L3 = WRONG-REASON failure, explained (confirmed from the files, not inferred). `089b-verify.sh` builds its "NEW on HEAD + later edit" fixtures with `mk_later "$TMP/n8" "$HEADREV" FILE OLD NEW`, whose `edit_file` demands exactly one occurrence of OLD
  (089b-verify.sh:85 "exactly one occurrence", anchors at :145-148 and CFG_OLD at :149): `OWN_OLD='and \`R11\` rejects it as well'` (AC1.9.1), `HARD_OLD='def test_f1_key_id_with_trailing_newline_is_rejected_task_065('` (AC1.8.1), `CFG_OLD='"r11_identity": null'` (AC1.10.2).
  L3's frame already applied the inverse of exactly those anchors: in L3.R9Uo `contracts/ownership.md:126` reads `and \`R11\` also rejects it` (no `rejects it as well` anywhere in contracts/), `tests/registry/test_hardening.py:57` reads `def test_f1_key_id_trailing_newline_is_rejected_task_065(`
  (the old name has 0 hits), `config/r11-identity.json:1` is already `{"schema_version": "1.0.0", "r11_identity": {"provider": "github", "id": 1, "name": "later-identity"}}`. So OLD occurs 0 times, `edit_file` fails, `mk_later` returns non-zero, and the harness prints
  its "cannot build the later-branch merge on HEAD" FAIL. AC1.12 did NOT fail for the same reason: its anchor `class AC2PositiveControls(Base):\n` is still present once in the frame (b4 inserted a test after it), so the fixture built and the NEW 039a stayed green on a class with 8 tests
  (the line above). Verdict: the 089b harness, run on a frame that already contains its own fixtures' edits, cannot work; this is a property of L3's frame (my own driver's choice from the manager brief), not a defect in 089b's fixes. 089b-verify.sh passes on plain HEAD (L2: `PASS 089b-verify.sh exits 0 on HEAD`).
  Consequence for criterion 9 on the merge: on L3, 065 (AC3.5 reads blob at FINAL), 075 (AC4 reads blob), and 039a's own part (r11 config at FINAL; per-class counts from names at FINAL; 8 tests in the extended class ok) were all GREEN with real later edits merged. 089b-verify.sh is the only closed script that cannot be judged on L3.

  (a) 064 -> 070 -> 066 -> 062 C3b on L3: NOT attributable to any of the four synthetic edits by what is on disk; classification INCONCLUSIVE, leaning to a non-deterministic (load/concurrency) failure, NOT a new own-change finding. Evidence, quoted:
   1. The failing chain is 039a's sweep -> `064-verify.sh` AC4.2 (064-verify.sh:149, "for s in 007a 007b 008a 062 066 067 069 070", run in 064's own clone `$TMP/head`) -> `070-verify.sh` AC2 (070-verify.sh:144 `AC2.$n ... exit $rc on the later branch`, which builds `mk_later` = HEAD plus a 070-made later commit
      (README sentence, probe files, 032/034 annotations, ownership.md `<!-- a later task annotates this contract -->`, a check added to 006, and a commit "Task 062 follow-up")) -> `066-verify.sh` run on that branch -> its check C3b (066-verify.sh:98: `{ [ "$rc62" = 0 ] && ... grep -q 'ALL CHECKS PASSED'; } && pass "C3b 062-verify.sh reports ALL CHECKS PASSED by default" || fail "C3b 062-verify.sh exit $rc62, no ALL CHECKS PASSED"`),
      i.e. 062-verify.sh, run with no node-modules argument inside 066's `npm ci` install of the later branch. The only FAIL line 064 prints is 070's single line (cut at 80 characters by 064-verify.sh:149); inside it the only red items are AC2.066 and, within it, C3b. Which 062 check went red was not captured (066 prints only `tail -n 3` of 062).
   2. The same 062, 066 and 070 scripts, on the same L3 frame, in the same L3 run, were GREEN when the sweep ran them directly: `PASS  062-verify.sh exits 0 on HEAD` (line 66), `PASS  066-verify.sh exits 0 on HEAD` (69), `PASS  070-verify.sh exits 0 on HEAD` (73). 070 run directly builds the identical `mk_later` from `$HEADREV` and runs the identical 066 on it. Identical code on identical bytes went red once (inside 064) and green once.
   3. No script in the chain references any of the four edited places: `grep` for `rejects it as well|also rejects it` hits only 075-verify.sh:121 and 089b-verify.sh; for `test_f1_key_id` only 065-verify.sh:96,217 and 089b; for `AC2PositiveControls|r11-identity` in 006/007*/032/034/057/062/066/067/069/070 only 007b-verify.sh:113 (`--r11-identity bogus`, a CLI flag). 062 reads ownership.md at `HEAD` only for
      the heading text (062-verify.sh:417-420, AC7.4); AC7.4 was green at HEAD in line 66 with the edited sentence. So no own-change read of any of the four edited blobs exists in 062/066/070 (nor in 064); the four edits cannot redden C3b by any read I can find.
   4. L2 (same 064 path, no synthetic edits) was green. Together with 2 this leaves two hypotheses I cannot separate without a run: H1 an interaction of the nested later-branch path with the merge-shaped history/commits of the L3 frame (e.g. a git-history-sensitive step in 062's AC3/AC6 ranges that the direct runs do not hit); H2 a transient/load failure, the signature seen on 2026-10-28 in the 039b
      agent's AC4.2 (070 failing "via 067/069/062" at a time other agents' verify scripts ran, task 089b finding 8 diagnosis (3)) and S5's one-off `FAIL AC1.5` (062 inside 067). The manager used the machine for other phase-2 runs during L3 (21:22Z-02:40Z): the driver logged `ps` only BEFORE each step, so concurrency DURING L3 is neither shown nor excluded.
   Outcome: NOT a legitimate-live-guard verdict and NOT an own-change finding; no new umbrella part is justified by this evidence. It IS a reproducibility observation to carry (S5-like): 062 inside 066 inside 070 inside 064 failed once in nine-plus hours of quiet-machine runs and cannot be reproduced from the output.

  CRITERIA AND FINDINGS (what is demonstrated, what is not):
   - Finding 8 (the 039b agent's 065 failure) is NOT reproduced: unfixed 065 on the 039b merge `e909174`, full non-mutate run, exit 0 `ALL CHECKS PASSED` (L1-unfixed); the earlier `--mutate` run (log, 2026-10-28) is also exit 0. Together with the 039b log's own naming of AC4.2 (070 exit 2), the suspected cause (065 AC3.5) is REFUTED by observation twice;
     AC3.5 is nonetheless fixed on its merits (red fixture AC1.8a/c). Criterion 10: DEMONSTRATED as far as it can be: fixed 065 passes on the same merge (L1-fixed exit 0), unfixed also passes, so "the failing check named" is "none: not reproduced".
   - Criterion 9 (quiet machine, ps logged, each closed script one at a time): DEMONSTRATED on plain HEAD (L2: whole 039a incl. every closed script one at a time, exit 0, 373 tests) and on a merge for the three fixed scripts' own checks (L3: 065, 075 and 039a's own part green with real later edits merged).
     NOT demonstrated: "every closed script green on the merge with the later synthetic branch": on L3 two scripts were red (064 chain, inconclusive cause; 089b, wrong-reason from the frame). So criterion 9 is half met: HEAD fully, merge not fully. The L3 run also leaves the quiet-machine claim during the run unproven (ps before each step only).
   - S5 (`FAIL AC1.5` of 062 inside 067): did NOT recur: no `AC1.5` text in L2 or L3 output; 067-verify.sh was green in both. Not elevated to a finding. The 064/070/066/062 C3b failure above is a different, unattributed one-off of the same kind.

  QUESTIONS booked (assumed option marked star; nothing built on them yet):
   - Q10: how to close criterion 9 on the merge. | A) re-run only what failed on a frame built the same way: `064-verify.sh` alone on L3's frame (twice, machine quiet, ps before and after each, 062 output kept in full); `089b-verify.sh` is judged on plain HEAD (L2) and excluded from L3 by design (its own AC1 fixtures ARE the later branches)
     and NOT rebuilt; | B) rebuild L3 with branches that do not collide with the 089b anchors (e.g. different sentence/test/config edits, so the old anchors still exist) and re-run the whole 039a (another ~5 h); | C) accept criterion 9 as met on HEAD plus the three fixed scripts' own checks on the merge, record the 064 one-off as S5-like, and close | assumed: A (★) | built on assumption: none.
   - Q11: the 064/070/066/062 C3b one-off. | A) no new umbrella part; a failure that occurred once, did not recur when 062/066/070 ran directly on the same frame, and has no read of any edited blob in its path is an observation to keep with S5, with Q10-A's two re-runs as the test (if it recurs, 062 C3b gets a finding, outputs pasted, and a part is cut then); | B) cut a part now for 062 (C3b capture of the failing check
     inside 066: print more than `tail -n 3`) and 066 (no change expected), since the failure cannot be explained from the output | C) treat it as a finding against 066 C3b now | assumed: A (★) | built on assumption: none. (B's small ask is worth doing whichever is chosen: 066 prints `tail -n 3` of 062, so a red C3b names no check.)
   - Q12: should `089b-verify.sh` guard its own fixtures against a frame that already contains their edits? Today the failure reads "cannot build the later-branch merge on HEAD" and names no cause. | A) leave (it is correct on every real HEAD: the anchors exist unless a real later branch edited them, in which case the fixture needs re-anchoring, which is the loud outcome we want) (★) | B) print which anchor has 0 occurrences | assumed: A | built on assumption: none.
- 2026-10-29 manager (session 14): readout accepted (log check exit 0; `c8d42e8`). **Disclosure for (a):** during L3 (21:22Z-02:40Z) the machine was NOT quiet
  in the sense of criterion 9's intent: no `*-verify.sh` ran, but the manager ran two ~40 s unit-test suites (008b-1 and 008b-2 red/green reproductions,
  ~22:00Z and ~22:20Z) and agents ran unit suites and short extracted harnesses; this load is a plausible cause of the one-off 064-chain red.
  Triage (★, overnight ruling): **Q10 ★ A** — re-run `064-verify.sh` alone on L3's frame (`/tmp/w089b/long/L3.R9Uo`), twice, quiet machine, `ps` before
  and after, 062's full output kept; 089b itself is judged on plain HEAD (L2) and excluded from the merged frame by design (its fixtures ARE the later
  branches). Queued after the current phase-2 run. **Q11 ★ A** (no new part unless it recurs) plus B booked as a small follow-up (066 C3b prints 062's full
  output instead of `tail -n 3`), whatever the re-run shows. **Q12 ★ A** (leave; the failure is loud and correct).
- 2026-10-29 qa-engineer (fix round, Ludwig's decision "A: fixed SHAs only"; WRITE ONLY: no verify script was run, only `bash -n` on 089b-verify.sh): rule = a script green on its branch stays green on registry main after merge and after any later commit.
  Audit of every HEAD / `..HEAD` / `TIP..HEAD` / current-main read in `089b-verify.sh` (own-change checks), old -> new:
   - AC0.12 (the AC9 unit-test class is gone from test_ci_gate.py): old `G show "$HEADREV:$TCG" | grep -qF 'AC9ProductionR11Unconfigured'` (a later commit re-adding any class of that name reddens it) -> `G show "$PIN_FIX:$TCG"` (the fix commit's blob). Intent kept: the deleted test's condition is asserted in 039a-verify.sh and the class was deleted by the fix.
   - AC11.2 (pin ancestry): old chain ended `TIP <= HEAD` (`merge-base --is-ancestor "$PIN_TIP" HEAD`) -> chain ends at TIP; the pins' existence is AC11.1, so HEAD is never consulted. Intent kept: BASE < RED < FIX <= FINAL <= TIP.
   - Already on fixed SHAs, unchanged: AC0.1-0.7 (merge_of from OLDREF), AC11.3-11.11 (ranges BASE..RED, RED..FIX, BASE..TIP, FINAL..TIP, RED..FIX hunks, blob at FIX). The ancestry/scope checks never used `merge-base HEAD main`.
   - Behaviour tests that run the fixed scripts on HEAD and on a later merge (AC1.8c/9c/10c/12b/12c, AC3, AC5, AC8, AC4 mutations) stay: they are the item-12 controls. One robustness change to their fixtures: `mk_later` on a frame that is not OLD and whose file ALREADY holds the later edit (OLD anchor absent, NEW text present) now uses the frame as it is and prints a note, instead of failing with "cannot build the later-branch merge on HEAD" (the wrong-reason failure of the L3 run, Q10/(b) above). An anchor present in neither form is still refused (AC13.5). On OLD the strict path is unchanged.
  Red-first cell, committed first (`7b31dd8e4d3364e08b16273acf7b067001119917`): section AC13 extracts the AC0 section (up to the `AC1 --` marker, ifs closed) of the pre-round script (`PIN_PRE=9ec482278f58eb94c0fe8e8a057f3fe752ea30ad`) and of the current script; runs them on plain HEAD (AC13.1 green control) and on HEAD plus ONE synthetic later commit that re-adds a class named AC9ProductionR11Unconfigured to test_ci_gate.py: the pre-round AC0 must FAIL on AC0.12 (AC13.2), the current must PASS (AC13.3). At the red commit the current script still read HEAD, so AC13.3 was expected red (not executed: write-only round; the manager's run confirms). AC13.4/13.5: the `mk_later` tolerance and its negative control.
  Fix commit: `de3ee3a48d4ee3399b6121c8dc828536aa4b03a2`. Umbrella copy synced byte-identical to `origin/task/089e-closed-verify-sweep-registry-e:docs/tasks/089-closed-verify-sweep-registry.md` in its own commit `bc96690fac946e72a60bb7bdb39fc97b97cd5fa7` (+4 lines). Pins re-set by the pin commit that follows this entry: FINAL = the fix commit, TIP = this log commit.
  Not demonstrated yet (needs a run, which this round forbids): 089b-verify.sh default and --mutate and --own-only all green after the re-pin; AC13.2 red / AC13.3 green. Side effect to know: the file-scope check AC11.5 allows the umbrella copy, so the sync commit is inside BASE..TIP.
