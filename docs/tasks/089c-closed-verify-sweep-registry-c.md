# Task 089c: registry closed scripts — part C (S1: 069 branch-tip pin)

- **Mission:** SITE-V1 (verification integrity) — **Status:** in-progress 2026-10-28 (cut from umbrella 089 at dispatch, session 14; umbrella spec-approved 2026-10-26, parts per Q5 ★ A)
- **Agent / model:** qa-engineer (model per frontmatter) — **Budget:** small (one agent-session)
- **Branch / worktree:** `task/089c-closed-verify-sweep-registry-c` / `~/wt/registry-task-089c`, from registry main `32c641b`
- **Umbrella (authoritative for findings, pins, criteria, forbidden list, Q1-Q6):** `docs/tasks/089-closed-verify-sweep-registry.md` (copied
  into this branch from platform main `4321d07`; read-only here — do not edit it).

## Scope of this part
Source files: `docs/tasks/069-verify.sh` (1). New: `docs/tasks/089c-verify.sh`. Log: this file. Anything else = stop and report.

## Acceptance criteria
The umbrella criteria 1-3, 6, 9 and 11, restricted to S1. Shipped as `docs/tasks/089c-verify.sh`. Quiet machine (criterion 9) is mandatory: one script at a time, `ps` logged before each run.
Same pattern as part B (`origin/task/089b-closed-verify-sweep-registry-b`, file `docs/tasks/089b-verify.sh`) and the 084/087 reference pattern.

## Questions  (agent-maintained; see MANAGER.md 8b)
- Q1: criterion 5's positive control ("the same merge makes the unfixed script exit non-zero") cannot hold for S1: the unfixed 069 reads the
  BRANCH, not HEAD, so no later merge reddens it; its defect is a silent skip when the branch is deleted (exit 0, "not evaluated", no AC5.3
  verdict). | options: A) red-first = "OLD with the branch deleted exits 0, prints 'not evaluated', has no AC5.3 verdict line" (asserted in
  089c-verify.sh AC1.b, with the branch-present control AC1.a); B) additionally require a non-zero exit, which would need editing the old
  script (forbidden); C) drop criterion 5's positive control for S1 | assumed: A | built on assumption: AC1.b / AC1.e of 089c-verify.sh
- Q2: AC5.3 reachability (criterion 6) shows reachability from `refs/remotes/origin/main`, which exists only in a clone with a remote. | options:
  A) FAIL when that ref is absent (run in a fresh clone; no skip) ; B) fall back to `refs/heads/main` | assumed: A | built on assumption: AC0.4
- Q3: the no-flag and --mutate modes run 069-verify.sh TRUNCATED to its preamble plus AC5 (the S1 check); the complete 069 (default and
  --mutate, hours-scale) is run by the separate `--full` flag, as phase-2 step 3. | options: A) as built; B) always run the complete 069
  (three to four complete runs per mode) | assumed: A | built on assumption: AC1/AC3/AC4 use the truncated copy

- Q4: phase 2 found `quiet_wait` counts itself (see the 2026-11-02 log entry); how to ship the one-function fix without a range spanning the main merge | options: A) new content commit after the merge, re-pin FINAL/TIP, adapt AC11.5 to exclude files brought by the merge (e.g. first-parent range); B) new cut from the pre-merge base; C) follow-up task | assumed: A is not applied; nothing assumed, blocked on the manager | built on assumption: none
- A (manager, 2026-11-02, from the 089b precedent): **A**. Fix `quiet_wait` transitively; content commit after the merge; re-pin FINAL and TIP; adopt 089b's own-change scope pattern exactly (PIN_MAINMERGED, first-parent scope_files, net_files AC11.5c, AC15 fixtures).
---
# Task 089c log  (append-only)
- 2026-10-28 manager (session 14): cut from umbrella 089 and dispatched for phase 1 (no verify runs while 089b's long driver holds the machine);
  base registry main `32c641b` (087, 082, 039b, 092, 008c merged).
- 2026-10-28 qa-engineer (phase 1, started): read the task, umbrella (S1, criteria 1-3, 6, 9, 11, forbidden list), 089b-verify.sh (read-only
  reference), 069-verify.sh. HARD CONSTRAINT kept: no `*-verify.sh` executed (not 069, not 089c, no --mutate); only git read commands,
  `bash -n`, and a throw-away `awk` run over blobs to check the truncation. `ps` at start showed 31 lines matching `verify.sh` (the other task's
  long driver); nothing of mine started.
- 2026-10-28 qa-engineer: **pin derived.** `git ls-remote origin refs/heads/task/064-schema-check-end-anchor` = `5002b4624abf0c09a6a1e1a94856e138ed5775f6`
  (the branch still exists). `git rev-parse 79d5377^2` (79d5377 = "Merge pull request #13 from worldofmodcraft/task/064-schema-check-end-anchor",
  the only such first-parent merge on main) = `5002b4624abf0c09a6a1e1a94856e138ed5775f6`, i.e. the branch tip IS PR #13's FINAL.
  `git merge-base --is-ancestor 5002b4624abf0c09a6a1e1a94856e138ed5775f6 origin/main` -> exit 0 (reachable from main `32c641b`). So no fixture
  blob is needed (umbrella S1). `docs/tasks/034-verify.sh` at the pin is byte-identical to main's (same sha1 6daabb4d...), written as an observation only.
- 2026-10-28 qa-engineer: **fix** (`docs/tasks/069-verify.sh`, +8/-5): `PIN064="5002b46...(40)"` added beside `BASE062`; AC5.3 now reads
  `git show "$PIN064:docs/tasks/034-verify.sh"`; an unreadable pin (commit missing, file missing, empty blob) is
  `FAIL AC5.3 pinned commit <pin> (task 064's FINAL) or its docs/tasks/034-verify.sh cannot be read in this clone`; the "note: ... not evaluated"
  branch is gone. No environment override. Classification of the touched check: AC5.3 is own-change of 064 (the file 064 changed), hence
  pinned. Everything else in 069 (AC1-AC4, AC5.1/5.2 on generated variants, AC7) untouched. `bash -n` OK.
- 2026-10-28 qa-engineer: **089c-verify.sh written, NOT RUN** (399 lines, executable, `bash -n` OK). Modes: no flag (AC0 pin/reachability/no-branch-ref greps
  with positive controls, AC1 red-first with the branch deleted + branch-present control + item-12 later-branch merge, AC3 four bad pins incl.
  `deadbee` + no-skip grep with positive controls, AC11 scope on fixed SHAs), `--mutate` (AC4: pin widened to the branch ref red/green control,
  widened to HEAD red on the later-branch merge, silent skip restored and detected), `--own-only` (AC11), `--full` (AC9: complete 069 default on HEAD and
  on the later-branch merge, then 069 --mutate, one at a time). Every child run is preceded by a quiet-machine wait that logs the `ps` lines
  it saw (stderr). Criteria status: 1 (S1) written-not-run; 2 (pin = `M^2`, no branch read) written-not-run; 3 (deadbee FAIL, 0 skip words, positive
  control) written-not-run; 4 (mutate) written-not-run; 5 (item 12) written-not-run, see Q1; 6 (reachability, deleted branch passes, bad pin fails)
  written-not-run; 9 (quiet machine, complete 069 one at a time) written-not-run; 11 (scope) written-not-run. NOTHING IS DONE UNTIL PHASE 2.
- 2026-10-28 qa-engineer: commits so far. RED `3b8db962327ea3f4dd82190551b0833e86e9df04` (089c-verify.sh + this file; its pins are still `__FIX__` etc.,
  so it is red by construction: AC0.0 / AC11.0 FAIL). FIX `1564ad0731ea794bcd286f6dcd08ed5d7a77b509` (069-verify.sh only). Next: this log commit (TIP),
  then the PIN commit that writes PIN_RED/PIN_FIX/PIN_FINAL/PIN_TIP into 089c-verify.sh (FINAL = the FIX commit: the last commit before the
  pin commit that touches 069-verify.sh or 089c-verify.sh), then one log line with the resulting SHAs. Nothing is run.
- 2026-10-28 qa-engineer: **PHASE-2 COMMANDS (exact, in order).** Fresh clone from GitHub, quiet machine, nothing else running. Paste each output into this log.
  ```
  # 0. fresh clone and branch (a new empty directory)
  cd "$(mktemp -d)" && git clone https://github.com/worldofmodcraft/registry registry && cd registry
  git checkout task/089c-closed-verify-sweep-registry-c && git log --oneline -3 && git --version
  export PYTHONDONTWRITEBYTECODE=1
  npm ci --prefix tools/dev
  # 1. the machine must be quiet: this must print nothing (log the output; the script also logs ps itself before every child run)
  ps -eo pid,ppid,args | grep -E '[0-9a-z]+-verify\.sh' | grep -v grep
  # 2. red first for the script itself: at the RED commit it must FAIL (pins not set) -- expected exit != 0
  git checkout -q 3b8db962327ea3f4dd82190551b0833e86e9df04 && bash docs/tasks/089c-verify.sh --own-only 2>&1 | tee /tmp/089c-0-red.log; git checkout -q task/089c-closed-verify-sweep-registry-c
  # 3. AC11 only (fast)
  bash docs/tasks/089c-verify.sh --own-only 2>&1 | tee /tmp/089c-1-own.log
  # 4. AC0 / AC1 / AC3 / AC11 (default; truncated 069 runs, minutes)
  bash docs/tasks/089c-verify.sh 2>&1 | tee /tmp/089c-2-default.log
  # 5. AC4 mutations
  bash docs/tasks/089c-verify.sh --mutate 2>&1 | tee /tmp/089c-3-mutate.log
  # 6. AC9: complete NEW 069 on HEAD, on the later-branch merge, and 069 --mutate, one at a time (hours-scale; one script at a time)
  bash docs/tasks/089c-verify.sh --full tools/dev/node_modules 2>&1 | tee /tmp/089c-4-full.log
  # 7. nothing left over, nothing modified
  git status --short; ps -eo pid,ppid,args | grep -E '[0-9a-z]+-verify\.sh' | grep -v grep
  ```
  Expected: step 2 exit != 0 with `FAIL  AC0.0` and `FAIL  AC11.0`; steps 3-6 end with `ALL CHECKS PASSED` and exit 0. If `FAIL  AC1.5` (062 inside 067) appears in
  step 6, the script prints the full output: paste it and open S5 as a finding against 062. A failing step is a finding to report, not something to adjust.
- 2026-10-28 qa-engineer: untested assumptions to watch in phase 2 (script written without being run): (1) `ps -eo pid=,ppid=,args=` and the awk filter in
  `quiet_wait` behave as intended under WSL; (2) the truncated 069 copy (preamble + AC5) parses (checked with `bash -n` on a throw-away awk run over the
  blobs: OLD 160 lines, NEW 163 lines, both parse); (3) `git clone` of the verifying clone carries HEAD's detached commit and the 034-verify.sh pattern
  `C4.1 TRAVERSAL_PATHS contains` occurs once at HEAD (checked with grep: 1); (4) 069's AC5 output contains no "skip" word (069 prints
  "never skip" only in --mutate labels, which the no-skip grep does not read).
- 2026-10-28 qa-engineer: PIN commit `406e51f66b1948e0ba67c9236ab2fb4b32815e93` (089c-verify.sh only) wrote PIN_RED=`3b8db96...`, PIN_FIX=PIN_FINAL=`1564ad0731ea794bcd286f6dcd08ed5d7a77b509`,
  PIN_TIP=`2f4495902b7c71a89c2fa5d97cab302689819006`; BASE=`32c641b5f56139a86c820f0b16d522c0f991d207`. Phase 1 complete; branch pushed, no PR. Awaiting phase 2.

- 2026-10-28 manager (session 14): phase 1 accepted for phase 2 (log check exit 0; head `b6c39ed`). Triage (★, overnight ruling; §8b 3a):
  Q1 ★ A: for S1 the unfixed script's red is the silent skip (exit 0, "not evaluated", no AC5.3 verdict), asserted in AC1.b with control AC1.a;
  criterion 5's non-zero-exit positive control does not apply to a defect whose symptom is a skip (same reasoning as 090's AC5 triage).
  Q2 ★ A: absent `refs/remotes/origin/main` = FAIL; phase 2 runs in a fresh GitHub clone. Q3 ★ A: as built (matches 089b Q9).
- 2026-10-28 qa-engineer (phase 1, fix round after static review PASS-WITH-NOTES; still no *-verify.sh executed, `bash -n` only): 
  (1) AC4.m3 replaced (`7f30d95831678dc8da9f4a66f39e6325e35c3415`): it now mutates 069's AC5.3 `fail` line to `:` and, for three unreadable pins (`deadbee`, a well-formed absent 40-hex SHA,
  the root commit), asserts exit 0 and that the expected `FAIL AC5.3` is ABSENT, i.e. the AC3.1-3.3 detectors redden when the guard is removed. The old
  m3 inserted the very words its grep looked for and could not fail for a 069 reason. Written-not-run.
  (2) AC11.9a/b added: TIP..HEAD touches only 089c-verify.sh and this task file, and 089c-verify.sh changes only its `PIN_*` lines after TIP.
  Consequence: the fix round is a source-touching commit, so the pins move: PIN_RED and PIN_FIX unchanged; PIN_FINAL = `7f30d95831678dc8da9f4a66f39e6325e35c3415` (the m3/AC11.9 content commit);
  PIN_TIP = the log commit that follows it; a final pin commit rewrites only PIN_FINAL and PIN_TIP.
  (3) Note for phase 2: step 2 (the RED commit run) is red BY PLACEHOLDERS (PIN_FIX etc. are `__FIX__`); it proves only that the script cannot pass unpinned.
  The S1 red-first evidence is AC1.b (OLD 069 with the branch deleted: exit 0, 'not evaluated', no AC5.3 verdict) against AC1.c (NEW passes AC5.3).
- 2026-10-28 qa-engineer: re-pin commit `efd476fa62cbe54f920d54654f7c15a513ae9002` (089c-verify.sh PIN_FINAL=`7f30d95831678dc8da9f4a66f39e6325e35c3415`, PIN_TIP=`fc50c2389724caff1263c714278aad232c59953f` only). Fix round complete, pushed, awaiting phase 2.
- 2026-10-29 qa-engineer (fixed-SHAs round; Ludwig 2026-10-29 "A: fixed SHAs only": a verify script green on its branch stays green on main after merge and after any later commit; write only, no *-verify.sh executed, `bash -n` only). Content commit `d7b0edde5dc58d6797249d0c2ec2033d08719246`. Old -> new per check:
  - Fixtures AC1.a-e, AC3, AC4.m1-m4, AC9.1-3 (frames/clones): built from `HEADREV` (HEAD) -> built from `TREE=PIN_FINAL` (the content commit; task 090 pattern). A placeholder/unreachable PIN_FINAL makes every frame fail to build (FAIL, never skip). `HEADREV` is renamed `REALHEAD` and is used for the banner and for AC12.c only. The truncated 069 still clones "HEAD" inside its frame; that HEAD is the fixed frame.
  - AC0 (merge/pin derivation, OLDREF blobs, NEW blob at PIN_FIX): already fixed SHAs, unchanged. AC0.4 reads `refs/remotes/origin/main`: a live ref, but "PIN064 is an ancestor of main" is monotone (main only advances); kept, and AC0.4b shows the same against the fixed OLDREF. The M064 fallback `${M064:-HEAD}^2` -> `${M064:-$OLDREF}^2` (only reached after a FAIL).
  - AC11.2 `... <= TIP <= HEAD` -> `... <= TIP` (the `PIN_TIP is an ancestor of HEAD` link dropped; every other link was already between fixed SHAs).
  - AC11.9a (`git diff --name-only PIN_TIP HEAD` only 089c-verify.sh + task file) and AC11.9b (`PIN_TIP..HEAD` changes only PIN_* lines): REMOVED. They read HEAD and cannot be written on fixed SHAs, because the pin-recording commit cannot name itself. Intent kept as far as fixed SHAs allow: AC11.5 (BASE..TIP scope), AC11.6a/b (FINAL = last source-touching commit; FINAL..TIP only the task file) and AC11.7 (069 hunk limit) are all fixed ranges. Residual, same as task 090: the pin-recording commit(s) after TIP and any later commit are not scope-checked by the script; the reviewer checks the pin commit by hand (`git diff TIP <pin-commit>` = PIN_* lines only).
  - AC12 added (item 12 for 089c itself, red-first cell): `OLD089C=ac6a823e6cf32fa243bf63c77fb84a99b9daad3d` is the previous script (its AC11.9 read HEAD). AC12.a control: previous script `--own-only` on its own head: green. AC12.b RED FIRST: previous script on that head plus ONE synthetic later commit (adds `docs/tasks/zz-later-task.txt`): must FAIL AC11.9a. AC12.c: the current script `--own-only` on this branch's head plus one later commit: green. Written-not-run.
  - Pins: PIN_FINAL moves to `d7b0edde5dc58d6797249d0c2ec2033d08719246` (this content commit); PIN_TIP = the log commit after it; PIN_RED and PIN_FIX unchanged; a pin commit rewrites only PIN_FINAL and PIN_TIP.
  - Phase-2 command list gains no step: AC12 runs inside the default step 4. Note step 3 (`--own-only`) now needs only fixed SHAs.


- 2026-10-29 qa-engineer: re-pin commit `88a2d51aafb12651f25707f11dc7d66dbbe810e2` (PIN_FINAL=`d7b0edde5dc58d6797249d0c2ec2033d08719246`, PIN_TIP=`d74b745e23fcd61ebf608593c916d1f47770277e` only). Pushed; awaiting phase 2.
- 2026-11-02 qa-engineer (PHASE 2, STOPPED on a defect in 089c-verify.sh; no PR). Merged origin/main (903b546) into the branch with no conflict (umbrella identical): merge `5a31f6c5959eb6ef7f665e47b28586080554e029`, pushed; PIN_TIP not touched (still `d74b745e23fcd61ebf608593c916d1f47770277e`, before the merge). Fresh non-shallow clone of https://github.com/worldofmodcraft/registry at that head, `npm ci --prefix tools/dev` ok (node v24.20.0, git 2.53.0), `ps` empty before each run, PYTHONDONTWRITEBYTECODE=1.
  - Step 2, RED commit `3b8db96` `--own-only`: **exit 2**, `FAIL AC0.0 ... PIN_FIX=__FIX__` and `FAIL AC11.0 ... not pinned yet`, 2 checks failed. As expected (red by placeholders). The S1 red-first evidence is AC1.b, not this run.
  - Step 3, `--own-only` at the merged head: **exit 0**, AC11.1-11.8 all PASS, `ALL CHECKS PASSED`.
  - Step 4, default: AC0.1-0.8b all PASS, AC1.0 PASS; then **HANG** at AC1.a (first child run): `quiet_wait` reported `waiting: 1 other *-verify.sh process(es) running` for 300 s+ and the process it saw was `bash docs/tasks/089c-verify.sh` itself (pid 815285, ppid 815260). I killed the run (pkill) after ~6 minutes; nothing else was running (`ps` empty). Output: /tmp/089c-2-default.log. Steps 5 (--mutate) and 6 (--full) NOT run: they use the same `quiet_wait`.
  - **Root cause (finding, file:line `docs/tasks/089c-verify.sh` `quiet_wait`, the `others=$(ps ... | awk ...)` block):** `quiet_wait` runs inside `run_in`, which runs inside `rc=$(run_in ...)`, a command-substitution subshell R (pid != `$$`). The awk exclusion drops pids in the ancestor list and processes whose ppid is `$$` (so R is dropped), but the subshell S created by `others=$(...)` inside R has ppid = R, not `$$`, and its args are `bash docs/tasks/089c-verify.sh`, so the script counts itself as "another" verify script forever (only the 6 h timeout ends it). Expected: n=0 on a quiet machine; actual: n=1, every time. It was never run in phase 1 (rule: write only), so this is the first observation. Not a machine problem.
  - **Proposed fix (not applied, needs the manager):** make the exclusion transitive: in awk build pid->ppid from the `ps -eo pid=,ppid=,args=` lines and skip any process whose ancestor chain reaches `$$` (or is in `anc`). A one-function change in `quiet_wait`. Consequence: it changes `089c-verify.sh` after the main merge, so the own-change range cannot simply end at the existing PIN_TIP; options: (A) apply the fix as a new content commit on top of the merge and re-pin FINAL/TIP after it, accepting that FINAL..TIP spans the main merge (the 089b lesson: leaks main's files into AC11.5) unless AC11.5 is adapted; (B) re-do the branch: new content commit on a pre-merge base (rebase forbidden; would need the manager to decide a new branch/cut); (C) 089d/089e-style: a small follow-up task for the fixed script. Booked as Q4 for Ludwig/manager. Criteria remain written-but-not-run apart from AC0 and AC11, which passed above.
- 2026-11-02 qa-engineer (Q4 = A applied; write only, `bash -n` only). Content commit `4a94ee11b5972e0af5dea1b9c327fe82c4336ddb` (089c-verify.sh only):
  (1) `quiet_wait` exclusion made transitive (pid->ppid map in awk; skip every process whose ancestor chain reaches `$$`, plus the ancestor list), the 089e `others()` idea. Red-first evidence = the observed hang: in /tmp/089c-2-default.log at AC1.a `ps    21:24:33 waiting: 1 other *-verify.sh process(es) running (waited 0s)` showing `815285  815260 bash docs/tasks/089c-verify.sh` (the script's own `$(...)` subshell, ppid = the `run_in` subshell 815260, which is not `$$`), repeated at 300 s. New cell AC13 (fixed blobs): a fake `ps` tree {script, subshell R, nested subshell S, sleep}; AC13.a OLD blob `92f6700` (92f6700, the hung one) would wait (exit 7); AC13.b NEW blob (PIN_FINAL) is quiet (exit 0); AC13.c NEW still waits for a foreign `062-verify.sh` line (positive control).
  (2) Scope pattern of 089b: `PIN_MAINMERGED=903b546151ddef3e618b3478f8b3db6b99dcd85e` (= `5a31f6c^2`, the main merged into the branch); `scope_files` (first-parent chain BASE..TIP; a merge from main contributes only `diff-tree --cc` files), `net_files`; checks AC11.1b/1c (PIN_MAINMERGED is a TIP ancestor, second parent of the last first-parent merge, not on the chain), AC11.5 (first-parent scope list, replaces `git diff BASE TIP`), AC11.5c (`git diff --name-only PIN_MAINMERGED PIN_TIP` inside scope); AC15.1-15.4b synthetic fixtures incl. the take-ours merge (scope_files alone misses it, net_files sees it).
  Old -> new: AC11.5 `git diff --name-only BASE TIP` -> first-parent `scope_files`; AC11.5c new; AC11.1b/1c new. All other checks unchanged. Pins after this: PIN_FINAL = `4a94ee11b5972e0af5dea1b9c327fe82c4336ddb`; PIN_TIP = the next log commit; the pin commit rewrites only PIN_FINAL and PIN_TIP. PIN_TIP ends after the main merge by necessity now; the first-parent pattern is what keeps main's files out.

- 2026-11-02 qa-engineer (phase 2 run on head d167a38, fresh non-shallow clone, node v24.20.0, git 2.53.0, `ps` empty before each run, PYTHONDONTWRITEBYTECODE=1): step `--own-only` exit 0 (AC11.1-11.8 incl. 11.1b/1c/5/5c PASS); default exit 0 (AC0, AC1.a-e, AC3.1-3.5, AC13.a-c, AC15.1-4b, AC12.a-c, AC11 all PASS; AC1.b = OLD 069 with the branch deleted exits 0 and prints 'note: origin/task/064-schema-check-end-anchor is not available in this clone; AC5.3 ... not evaluated', AC12.b = previous script fails AC11.9a with one later commit); `--mutate` exit 2: AC4.m1, m1c, m2, m4 PASS and m3 PASS for deadbee, but **`FAIL AC4.m3 cannot build the frame` twice** (pins 2 and 3 of the loop). Cause: a defect in my own test code (089c-verify.sh AC4.m3 loop): all three iterations cloned into the same `$TMP/m3`, and `git clone` refuses a non-empty directory. Not a 069 or machine problem. Fixed in content commit `45b57f0936c4a4388f6651e29deecc3a5939a6ba` (one directory per pin); FINAL and TIP move again (the first-parent pattern keeps main's files out). `--full` not yet run.
