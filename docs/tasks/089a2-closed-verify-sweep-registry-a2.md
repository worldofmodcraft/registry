# Task 089a2: registry closed scripts — part A2 (finding 6, S2, S3)

- **Mission:** SITE-V1 (verification integrity) — **Status:** in-progress 2026-10-28 (cut from umbrella 089 at dispatch, session 14; umbrella spec-approved 2026-10-26, parts per Q5 ★ A)
- **Agent / model:** qa-engineer (model per frontmatter) — **Budget:** small (one agent-session)
- **Branch / worktree:** `task/089a2-closed-verify-sweep-registry-a2` / `~/wt/registry-task-089a2`, from registry main `32c641b`
- **Umbrella (authoritative for findings, pins, criteria, forbidden list, Q1-Q6):** `docs/tasks/089-closed-verify-sweep-registry.md` (copied
  into this branch from platform main `4321d07`; read-only here — do not edit it).

## Scope of this part
Source files: `docs/tasks/057-verify.sh`, `docs/tasks/057-textchecks.py`, `docs/tasks/070-verify.sh` (header text only) (3), plus `docs/tasks/062-verify.sh` (the 057 mutation literals in its AC4 block ONLY; scope extension by the manager, session 14, 2026-10-28, after review finding F1) (4 source files, within the cap of 5). New: `docs/tasks/089a2-verify.sh`. Log: this file. Anything else = stop and report.

## Acceptance criteria
The umbrella criteria 1-5, 7, 9 and 11, restricted to finding 6, S2 and S3. Q4 is decided ★ A (manager, session 14, overnight ruling): read ADR-0121 at a pinned commit of a history the script can reach without a hard-coded working-copy path; if no such history is reachable from the registry clone, use a committed fixture blob (Q4 option B) and log why. Shipped as `docs/tasks/089a2-verify.sh`. Quiet machine (criterion 9) is mandatory: one script at a time, `ps` logged before each run.
Same pattern as part B (`origin/task/089b-closed-verify-sweep-registry-b`, file `docs/tasks/089b-verify.sh`) and the 084/087 reference pattern.

## Questions  (agent-maintained; see MANAGER.md 8b)
- Q1: where the ADR-0121 fixture lives (S2, Q4 option B) | options: A) inline heredoc inside `057-verify.sh` (in File scope); B) a separate fixture file under `docs/tasks/` (outside the declared scope: needs a scope extension) | assumed: A ★ | built on assumption: `057-verify.sh` A1 block
- Q2: how much of the ADR the fixture holds | options: A) title line + Status line (2 lines); the platform commit and the ADR blob SHA are recorded in the header and the log, but the excerpt cannot be hash-checked against the blob; B) the whole ADR (12.8 kB) embedded, so `git hash-object` can be compared with the recorded blob `16064b511c42...` (tamper-evident, heavy) | assumed: A ★ | built on assumption: the 2-line fixture
- Q3: criterion 9 for this part: which whole-script runs | options: A) `057-verify.sh` whole on HEAD and on HEAD + later branch (`--later-clone`), and `070-verify.sh` whole once on HEAD (it runs all 12 closed scripts on a later branch itself; hours), no `070 --mutate` (header text only); B) A plus `070-verify.sh --mutate` | assumed: A ★ | built on assumption: the phase-2 command list in the log
- Q4: stale mentions of `PLATFORM_REPO` / "reads platform main" in closed task records `docs/tasks/057-version-lifecycle-contract.md:220` and `docs/tasks/062-registry-test-maintenance.md:337` | options: A) leave (closed history, outside File scope); B) a doc fix in a later task | assumed: A ★ | built on assumption: not touched
- Q5: AC1.2a runs the OLD 057-verify.sh with `PLATFORM_REPO=<nonexistent>` to show the defect on a machine with no platform checkout (the OLD script has no other way to be shown red); the NEW script is run with the same variable and must ignore it | options: A) accept (an env var on the OLD blob only, never a pin override); B) drop AC1.2a and rely on the grep (AC0.7) | assumed: A ★ | built on assumption: AC1.2a/AC1.2b in `089a2-verify.sh`

---
# Task 089a2 log  (append-only)
- 2026-10-28 manager (session 14): cut from umbrella 089 and dispatched for phase 1 (no verify runs while 089b's long driver holds the machine);
  base registry main `32c641b` (087, 082, 039b, 092, 008c merged).
- 2026-10-28 qa-engineer (phase 1, session 14): PHASE 1 ONLY. Nothing below was RUN: no `*-verify.sh` (old, new, own, `--mutate`), no
  `057-textchecks.py` against the repo, no long process (another task's detached driver holds the machine). Only `git show/log/diff/
  merge-base/rev-parse`, `bash -n`, `python3 -I -c ast.parse` on blobs, and pure grep/sed/awk pipelines on extracted text. EVERY criterion
  below is WRITTEN-BUT-NOT-RUN; nothing is done until phase 2.
- 2026-10-28 qa-engineer: commits on `task/089a2-closed-verify-sweep-registry-a2` (base registry main `32c641b5f56139a86c820f0b16d522c0f991d207`):
  RED `42d7d46c9081c11f217e50c4be21f93f3b5e022e` (089a2-verify.sh only, pins placeholders); FIX/FINAL `672edcd971fdf74e0a827fa4255f87cfcbb02cbe`
  (057-verify.sh, 057-textchecks.py, 070-verify.sh); TIP = the commit of this log entry; the pin commit after it fills PIN_RED/FIX/FINAL/TIP in the script.
- 2026-10-28 qa-engineer: PINS RE-DERIVED (read-only git): 057's merge on main is `e009ef0b28413700f0c41470f6e45905bf627cda` (registry PR #8, found with
  `git log --first-parent --merges -E --grep='^Merge pull request #[0-9]+ from worldofmodcraft/task/057-version-lifecycle$' 32c641b`, exactly one hit).
  `git rev-parse e009ef0^2` = `3ab8f43d96013889a48e2005c57a75731b3d655f` (FINAL); `git merge-base e009ef0^1 e009ef0^2` =
  `a50daacd7e26235d1acdeadc7d19265f1b2d04e3` (BASE). The old script's short pins `a50daac` / `3ab8f43` rev-parse to exactly these: the range did not move.
  `git show 3ab8f43:docs/contracts/README.md | grep -ci 'task 057'` = 3 (the check passes at the pin). Replaced in `057-verify.sh` by the full 40-character SHAs.
- 2026-10-28 qa-engineer: Q4 DECISION APPLIED (manager ruled A, "else fixture B and log why"): option A is impossible. `git log --all -- docs/decisions` on the
  registry returns no commit (the registry never held an ADR; `git log --all -- docs/tasks` finds hundreds: control). The ADR lives only in the PLATFORM
  repo, which no clone of the registry reaches. So option B: a fixture blob. Derivation (platform repo, read-only): ADR-0121 was accepted by
  commit `84064c9cf1c858844477701f32f42adea438bc6b` (2026-10-15); `git rev-parse 84064c9:docs/decisions/0121-version-lifecycle-pending.md` =
  `git hash-object` of the file at platform main `4321d07` = `16064b511c422acca2d3f628bdfa7614c85440e6` (the blob is identical at acceptance and now).
  The fixture is lines 1 and 3 of that blob (title and `**Status:** Accepted ...`), embedded as a quoted heredoc in 057-verify.sh A1. The check requires
  both lines (title and Status) so an empty fixture cannot pass. `PLATFORM_REPO`, the path `/home/ludwig/wom` and `git -C` are gone from the code lines.
- 2026-10-28 qa-engineer: S3 count DERIVED, not copied: `070-verify.sh` line 41 `CLOSED="006 007a 007b 008a 032 034 057 062 066 067 069 075"` = 12 words; the loop
  `for n in $CLOSED; do` (line 142) iterates them. The header said "ten" twice (lines 11 and 20). Both now say "twelve". The count is asserted by `s3_check` in
  089a2-verify.sh (word table, header lines 1-25, every count mention must be the right word, at least two mentions, the loop must iterate $CLOSED).
- 2026-10-28 qa-engineer: classification per touched check (one line each; own-change = reads 057's/070's own change, live = a property that must hold on HEAD):
  - 057 T1 text checks: README-names-task-057 half = OWN-CHANGE of 057 -> now the README blob at FINAL via `--readme` (finding 6); the rest of T1 (old sentences gone, new
    present, sections equal pins, schema/example text) = LIVE contract prose pinned on purpose, stays on HEAD (the textchecks default paths stay for live use, also read by 062's retire check).
  - 057 A1 ADR status: external authority, neither own nor live; hard-coded working-copy read (S2) -> fixture blob.
  - 057 A2 (task file cites ADR-0121): own file of 057, only 057 edits it; stable, left unchanged (not named in the table).
  - 057 T2, S1-S4, P0: already pinned BASE..FINAL (own-change, correct); only the pins widened from 7 to 40 characters, no logic change.
  - 057 T3, F1, O1, O2, U1, U2, V1: live (mutation runner, committed fixtures = generator output, tests/schema agreement); untouched.
  - 070 header: text only, no check.
  - 057-textchecks.py: code unchanged; the docstring gained the `--readme` live-vs-pinned note (asserted by AC11.8 via AST equality without the docstring).
- 2026-10-28 qa-engineer: 089a2-verify.sh criteria coverage (all WRITTEN, NOT RUN): AC0.1-0.12 pins re-derived from the merge, static greps with positive controls (criterion 2);
  AC1.6a-d red first for finding 6 (a synthetic later branch rewrites every "task 057" in docs/contracts/README.md; OLD truncated 057 must print FAIL required/readme-names-057 and FAIL T1;
  plain-OLD control; NEW on HEAD+later green; fixture-is-real check) (criterion 1); AC1.2a/b S2 (OLD red with PLATFORM_REPO=nonexistent, NEW green with the same variable);
  AC1.S3a-d (OLD header wrong, NEW right, diff header-comment-only, ten->twelve); AC3.1-3.2 deadbee is FAIL naming T1/P0 and 'skip|not evaluated' = 0 hits with a positive control (criterion 3);
  --mutate AC4.m6 (T1 widened to the working-copy README), m6b (pin deadbee), m2 (fixture says Proposed), m2b (fixture title line changed), m-S3a..e (CLOSED grows / shrinks / vanishes / loop broken / one header line back to ten)
  each red and only that check (criterion 4); AC5.1 NEW on plain HEAD plus AC1.6c on the later-branch merge = item-12 control, OLD red on the same merge = positive control (criterion 5);
  AC11.1-11.12 scope on fixed SHAs incl. ancestry RED<FIX<=FINAL<=TIP, red commit = script only, fix commit = the 3 sources, BASE..TIP inside scope, FINAL = last source-touching commit, FINAL..TIP = task file only,
  057-verify.sh hunk limits, textchecks AST equality, check ids and count not reduced, modes, no /home path in the script (criterion 11); the S3 assertion is AC1.S3b + AC1.S3c (criterion 7).
  Quiet machine (criterion 9, mechanism): `run_in` calls `wait_quiet` before EVERY child run (logs `ps[label]: N other *-verify.sh process(es)`, waits up to 6 h, timeout = FAIL).
  The truncated-057 shape (cut before "-- text mutations", exactly one marker asserted) is borrowed from 089b's 039a truncation; the hours-long part is run by hand (below).
- 2026-10-28 qa-engineer: self-checks done in phase 1 (none executes a verify script): `bash -n` on 089a2-verify.sh, 057-verify.sh, 070-verify.sh, the truncated 057 copy; `ast.parse` of 057-textchecks.py;
  `pin_of`, the S3 helper (`s3_check`: OLD red "header names that number 0 time(s) of 2", NEW green, five mutants all red) and the AC11.7 allowlist (real diff leaves 0 unmatched lines; a sample unrelated line leaves 1) were
  exercised as extracted pipelines on the real blobs. `git diff --stat OLD..FINAL`: see the report. The end-to-end behaviour of 089a2-verify.sh is UNPROVEN until phase 2; expect a fix round.
- 2026-10-28 qa-engineer: PHASE-2 COMMANDS, in order (fresh clone, quiet machine; one command at a time; wait for each to finish; never run two):
  1. `cd "$(mktemp -d)" && git clone https://github.com/worldofmodcraft/registry registry && cd registry && git checkout task/089a2-closed-verify-sweep-registry-a2 && git rev-parse HEAD` (HEAD must be the pin commit pushed last)
  2. `export PYTHONDONTWRITEBYTECODE=1; npm ci --prefix tools/dev` (anonymous, public npm registry; needed only for the whole 057/070 runs; the node_modules path is then `$PWD/tools/dev/node_modules`)
  3. before EVERY run below: `ps -eo pid,args | grep -E 'docs/tasks/[^ ]*-verify\.sh' | grep -v grep` must print nothing (log the output); if it does not, wait (the script waits by itself for its own children, the manual runs do not).
  4. `bash docs/tasks/089a2-verify.sh --own-only; echo rc=$?` (static: pins, AC11)
  5. `bash docs/tasks/089a2-verify.sh; echo rc=$?` (red-first fixtures, deadbee, item-12 control, AC11); paste the output
  6. `bash docs/tasks/089a2-verify.sh --mutate; echo rc=$?`; paste the output
  7. `bash docs/tasks/089a2-verify.sh --later-clone /tmp/089a2-later` (builds HEAD + a later branch rewriting the README; prints the path)
  8. `bash docs/tasks/057-verify.sh "$PWD/tools/dev/node_modules"; echo rc=$?` on the fresh clone HEAD (whole script)
  9. `(cd /tmp/089a2-later && bash docs/tasks/057-verify.sh "<fresh-clone>/tools/dev/node_modules"; echo rc=$?)` (whole script on the later-branch merge; must be 0; its T1 must PASS)
  10. `bash docs/tasks/070-verify.sh "$PWD/tools/dev/node_modules"; echo rc=$?` once on HEAD (hours; runs the 12 closed scripts on a later branch; this is where the S5 one-off `FAIL AC1.5` (062 inside 067) is watched: paste the full output if it recurs). See Q3 for `070 --mutate`.
  11. Positive-control record for criterion 1: the OLD script's red on the same merge is in the output of step 5 (AC1.6a, AC1.2a, AC1.S3a); paste those lines.
  12. Only then: mark criteria done, append the outputs, push; no PR from the agent.
- 2026-10-28 qa-engineer: PIN COMMIT `7ff6fe792b03674b8969c3d28921b9fcb6b78fc9` (089a2-verify.sh only: PIN_RED=42d7d46c9081c11f217e50c4be21f93f3b5e022e, PIN_FIX=PIN_FINAL=672edcd971fdf74e0a827fa4255f87cfcbb02cbe, PIN_TIP=3d989b5b871032b44acf38eefe15a2d7f133dc41). Phase 1 ends here; phase 2 starts at step 1 of the command list above and must check that `git rev-parse HEAD` of the fresh clone equals the last pushed commit.
- 2026-10-28 qa-engineer: found while re-reading (not run): AC11.12 would have failed on the script own grep patterns (they contained the literal path). Patterns now use a bracket (`/ho[m]e/`); the script is committed after the pin commit; its pins are unchanged (TIP stays 3d989b5, outside this commit).
- 2026-10-28 manager (session 14): phase 1 accepted for phase 2 (log check exit 0; head `a4891ed`). Triage (★, overnight ruling; §8b 3a):
  Q4 outcome B (fixture blob) accepted: registry history has no `docs/decisions`, so option A is impossible, which the task's ★ allowed for.
  Q1 ★ inline (in scope). Q2 ★ excerpt: what 057 asserts is the ADR's title and Status line; the platform blob id `16064b5` is recorded beside it
  for provenance. Q3 ★ as proposed. Q4 ★ leave (closed task records are history). Q5 ★ accept: the variable is set only on the OLD blob to
  exhibit its defect; the NEW script must ignore it (asserted). Expect a fix round after phase 2 (agent's own warning).
- 2026-10-28 manager (session 14): SCOPE EXTENDED by `docs/tasks/062-verify.sh`, the 057 mutation literals in its AC4 block only (update them to the full-SHA lines; no other change). Reason: review finding F1.
- 2026-10-28 qa-engineer (fix round 1, still phase 1: nothing run; only git read, bash -n, extracted-pipeline tests): finding -> commit mapping:
  - F1 BLOCKING (confirmed by reading 062-verify.sh:496-498: `mutate $f 'BASE_COMMIT="a50daac"'` ... `'FINAL_COMMIT="3ab8f43"'` x2; widening 057's pins to 40 characters leaves those literals 0 times, "the mutation did not apply" -> 062 red on HEAD and inside 070 AC2).
    FIXTURE first: `4b8151b4ac68ec6131217623561b827af800228b` (089a2-verify.sh only: AC1.Xa-e cross-check; extraction pipeline tested by hand: OLD 062 vs OLD 057 = all literals once, OLD 062 vs NEW 057 = 3 of 5 literals missing, rc 1). FIX: `becccdedd9b5b6f9aed930fcb4018be79c086aea` (062-verify.sh, 4 lines = 2 removed + 2 added, the 057 BASE/FINAL_COMMIT mutation lines; NEW 062 vs NEW 057 rc 0).
  - Other references to 057's pin literals or labels (grep over 062/006/067/069/070 and every `*-verify.sh`): 062 `EXP_MAIN_057="S4,T2"`/`EXP_PROBE_057` are failing-id sets measured in a clone at BASE062 (a historic frame running the historic 057 script): unaffected. 062 `check_pins 057 e009ef0 BASE_COMMIT FINAL_COMMIT` parses with 7+ hex digits and rev-parses: full SHAs pass. 062 AC5.mut2 mutates the label `"O1 ` (kept) and 006 successor lines name ids T1/O1/O2 (kept). 070:91 renames `"O1 ` (kept). 067/069: no reference. Only 062:496 and :498 named the short literals; AC1.Xe asserts 0 hits over all `docs/tasks/*-verify.sh` at FINAL (with a positive control).
    062's AC4.057 expectations still hold with full pins: swap-pins expects T2,S2,S4 (reversed range), bad-pin expects P0,T2 (T1 now also fails; expect_red demands only that the listed ids fail). UNPROVEN until phase 2 step 11.
  - F2 minor: AC11.7 keyword allowlist replaced by an exact recorded list (27 sorted non-comment hunk lines of 057-verify.sh, compared with `diff`, empty actual = fail): commit 4b8151b. AC11.13 pins 062's change to exactly 4 lines of the anchored shape `mutate $f '(BASE|FINAL)_COMMIT="<hex>"' '...' one`.
  - F3 minor, stated plainly: the A1 ADR-status check is TAUTOLOGICAL BY CONSTRUCTION under Q4 option B. It greps a constant embedded in the same script, so it can never redden because the real ADR changes. AC4.m2 / m2b only prove the check reads the fixture (a changed fixture reddens it). Its value is that the script no longer depends on a machine path; the authority claim rests on the recorded platform commit and blob SHA, not on a runtime check (Q2 option B would make it tamper-evident).
  - F4 minor: the truncated 057 covers A1, A2, T1, P0, T2 only (cut before "-- text mutations"); T3, F1, O1, O2, U1, U2, V1, S1-S4 run only in the whole-script steps (8, 9) of the phase-2 list; 062 whole added as step 11.
  - Pins for the script after this round: PIN_RED=42d7d46c9081c11f217e50c4be21f93f3b5e022e, PIN_FIX=672edcd971fdf74e0a827fa4255f87cfcbb02cbe, PIN_RED2=4b8151b4ac68ec6131217623561b827af800228b, PIN_FIX2=PIN_FINAL=becccdedd9b5b6f9aed930fcb4018be79c086aea, PIN_TIP = the commit of this log entry (set by the pin commit that follows).
  - PHASE-2 COMMANDS, updated (replaces the earlier list from step 10 on; steps 1-9 unchanged; one at a time, ps check before each):
    10. `bash docs/tasks/062-verify.sh "$PWD/tools/dev/node_modules"; echo rc=$?` on HEAD (whole; its AC4.057.swap-pins and AC4.057.bad-pin must PASS, not "the mutation did not apply"); paste the output
    11. `bash docs/tasks/070-verify.sh "$PWD/tools/dev/node_modules"; echo rc=$?` once on HEAD (hours; runs the 12 closed scripts on a later branch; S5 `FAIL AC1.5` watched; paste the full output if it recurs; see Q3 for `--mutate`)
    12. paste the OLD-script red lines from step 5 (AC1.6a, AC1.2a, AC1.S3a, AC1.Xb); mark criteria done only then; push; no PR.
- 2026-10-28 qa-engineer: fix-round pin commit `9cc2834e26ef7d62f2ddb1bd2eb08edc3e931c98` (089a2-verify.sh pins only: PIN_TIP = the scope/mapping log commit above). Static checks of the range: last source-or-script-touching commit in BASE..TIP is becccde (FINAL); FINAL..TIP touches the task file only.
