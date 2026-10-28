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
