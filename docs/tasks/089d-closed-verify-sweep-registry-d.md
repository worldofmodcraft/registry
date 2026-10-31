# Task 089d: registry closed scripts — part D (post-TIP merge-into-branch defect in 092-verify.sh)

- **Mission:** SITE-V1 (verification integrity) — **Status:** in-progress 2026-10-28 (cut from umbrella 089 at dispatch, session 14; umbrella spec-approved 2026-10-26, parts per Q5 ★ A; part D spec-approved 2026-10-28 after independent spec review)
- **Agent / model:** qa-engineer (model per frontmatter) — **Budget:** small (one agent-session)
- **Branch / worktree:** `task/089d-closed-verify-sweep-registry-d` / `~/wt/registry-task-089d`, from registry main `32c641b`
- **Umbrella (authoritative for findings, pins, criteria, forbidden list, Q1-Q6):** `docs/tasks/089-closed-verify-sweep-registry.md` (copied
  into this branch from platform main `4321d07`; read-only here — do not edit it).

## Scope of this part
Source files: `docs/tasks/092-verify.sh` (AC9 post-TIP only, per umbrella part D (f)) (1). New: `docs/tasks/089d-verify.sh`. Log: this file. Anything else = stop and report.

## Acceptance criteria
The umbrella part D criteria (a)-(f) and forbidden list, verbatim; Q6 answered (★ A). Shipped as `docs/tasks/089d-verify.sh`. Quiet machine (criterion 9) is mandatory: one script at a time, `ps` logged before each run.
Same pattern as part B (`origin/task/089b-closed-verify-sweep-registry-b`, file `docs/tasks/089b-verify.sh`) and the 084/087 reference pattern.

## Questions  (agent-maintained; see MANAGER.md 8b)
- Q1: "no remote" in the Q6 definition | options: A) literal: `git remote` empty -> refs/heads/main; any remote -> refs/remotes/origin/main only, so a remote with origin/main deleted is "no main ref" = RED even if a stale local main exists; B) origin/main, falling back to refs/heads/main when origin/main is absent | assumed: A (stricter; B would let a stale or hand-moved local `main` vouch for a merge) | built on assumption: `post_tip_check` main-ref lookup; control b5 (local main deliberately moved to contain the merge) and b5b
- Q2: `--no-renames` on every listing in the fixed function (spec silent) | options: A) add it, so a non-092 file renamed into a docs/tasks/092-* path is seen by its old name too; B) keep git's default rename detection | assumed: A (only ever lists more files, never fewer) | built on assumption: the three `--no-renames` flags in `post_tip_check`
- Q3: new in-script controls inside 092-verify.sh | options: A) none; the merge scenarios live in `089d-verify.sh` and the existing AC9 controls stay byte-identical; B) also add a main-merge control to 092's own default run | assumed: A (smaller hunk, (c) byte-for-byte is trivial to prove) | built on assumption: 092-verify.sh diff is the comment and the function only
- Q4: (a) second form, "resolved to main's version" | options: A) a merge with `--no-commit` followed by `git checkout origin/main -- <file>` (explicit resolution, result equals main's version); B) a real conflict | assumed: A (a branch that touches only 092 files cannot conflict with a main commit on a non-092 file, so B has no fixture that is also GREEN-correct) | built on assumption: scenario a2
- Q5: (f) range | options: A) pin 089d's own start at the dispatch commit 75eb9b0 (it adds the umbrella copy and the task file, which are not part of D's work) and require `git diff --name-only PIN_START PIN_TIP` to equal the three files, plus byte-identity of everything in 092-verify.sh outside the post-TIP region; B) use the registry main 32c641b as start (then the diff also contains the umbrella copy) | assumed: A | built on assumption: PIN_START/PIN_TIP in `089d-verify.sh`

---
# Task 089d log  (append-only)
- 2026-10-28 manager (session 14): cut from umbrella 089 and dispatched for phase 1 (no verify runs while 089b's long driver holds the machine);
  base registry main `32c641b` (087, 082, 039b, 092, 008c merged).
- 2026-10-28 qa-engineer (phase 1; NO `*-verify.sh` was executed: another task's long driver holds the machine). Worktree
  `~/wt/registry-task-089d`, branch `task/089d-closed-verify-sweep-registry-d`, base registry main `32c641b5f56139a86c820f0b16d522c0f991d207`,
  dispatch commit `75eb9b0ce7ccddd8400eecd06f1a64eec0a1e753`. `git --version` = 2.53.0.
- 2026-10-28 qa-engineer: **git behaviour checked in throwaway repos** (seconds, deleted; scripts outside the repo): upstream `main`
  (other.txt, docs/tasks/092-x.md), clone, branch `task` with a TIP commit, `git merge --no-ff origin/main` after main changed other.txt.
  (1) `git log --first-parent --name-only --format= TIP..HEAD` prints `other.txt` (the defect reproduced; A2's old comment is wrong).
  (2) `git log --first-parent --no-merges --name-only --format= --no-renames TIP..HEAD` prints nothing for that merge.
  (3) `git diff-tree --cc --name-only -r --no-commit-id --no-renames HEAD` on a plain merge prints nothing; after `merge --no-commit` plus
  a new file `evil.txt` it prints `evil.txt`; after appending to the main-supplied `other.txt` it prints `other.txt`.
  (4) `git rev-list --parents -n 1 <octopus>` prints 4 words (commit + 3 parents); a 2-parent merge prints 3. `git merge s1 s2` prints
  "Fast-forwarding to: s1 / Trying simple merge with s2" but still makes a 3-parent commit.
- 2026-10-28 qa-engineer: **fix commit `8eb35c228e429343a323943f6dc059fcec5f04a4`** (`092-verify.sh` only, 29 insertions, 6 deletions; hunks
  `@@ -657,4 +657,10 @@` the comment, `@@ -662 +668 @@` the `local` line, `@@ -670 +676,18 @@` the body of `post_tip_check`). Red commit for the
  pin = registry main `32c641b5...` (the unfixed file). Design: non-merge first-parent commits listed; for every merge on `TIP..HEAD`
  first-parent chain: octopus (`rev-list --parents` > 3 words) is RED; `diff-tree --cc` files added; if no main ref or `C^2` is not an
  ancestor of the main ref, `git diff C^1 C^2` files added too. Main ref: `refs/remotes/origin/main` when `git remote` is non-empty, else
  `refs/heads/main` (Q1). Every git failure is a FAIL (no silent empty list). Pins, `own_change_checks`, the call site and all AC9
  controls are untouched; the PASS/FAIL/NA message texts the controls grep for are unchanged.
- 2026-10-28 qa-engineer: **`docs/tasks/089d-verify.sh`** written (about 330 lines), `bash -n` OK, **not run**. Layout: AC0 pins (full SHA,
  reachable, temp clone, blobs read from the clone); `--own-only` = (f) only; extraction (sed range `^post_tip_check() {` to `^section "AC9 -- pinned
  own-change checks`, end excluded, each marker exactly once, non-empty and starts-at-function positive controls, red has the old pattern, fixed
  does not, exactly two `return 0` lines in the fixed function = no skip path); 11 synthetic scenarios, each run against the unfixed and fixed
  function; (c) controls with 092's real pins; (f); `--mutate` = (e).
  Scenario table (fixed verdict / unfixed verdict): g0 no merge PASS/PASS; **a1** auto merge of main PASS/FAIL; **a2** main merge resolved to main's
  version PASS/FAIL; **a3** no remote, `refs/heads/main` merged PASS/FAIL; **b1** post-TIP commit on a non-092 file FAIL; **b2i** merge then edit a
  main-supplied file FAIL (names other.txt); **b2ii** merge plus a new file FAIL (names evil.txt, must NOT name main's other.txt); **b3** `--no-ff` side
  branch FAIL (names side.txt); **b4** octopus FAIL (message names "octopus"); **b5** remote exists, `origin/main` deleted, local `main` moved to contain the
  merge FAIL; **b5b** no remote and no `main` FAIL. On (a) the unfixed output must also name `other.txt` (red for the right reason).
- 2026-10-28 qa-engineer: **development harness (NOT criteria evidence)**: to catch bugs in the script I sourced only its `BEGIN-LIB`..`END-LIB`
  block plus extracted functions in a throwaway shell file under /tmp (not a `*-verify.sh`, a few seconds, no other process counted). Result: all 11
  scenarios gave exactly the verdicts of the table above for the fixed and unfixed functions, and the mutant (old pattern restored) gave FAIL on a1/a2/a3
  and the fixed verdict on every other case. The real-pin controls with the fixed function gave: BASE..FINAL FAIL (lists 16 contract/README files),
  FINAL..BASE FAIL (non-ancestor), unreachable HEAD FAIL. Bug found and fixed in my own script: `REG_END_RE` contained `/`, which broke the sed
  address; its positive control (non-empty region) would have caught it; the marker is now `^for p in tools` (occurs once in 092-verify.sh).
  After that fix the red/fixed `mid` (30 lines) and `ctrl` (19 lines) slices are byte-identical. Everything is still **written-but-not-run**.
- 2026-10-28 qa-engineer: **criteria status (all written, none run; nothing is done until phase 2)**: (a) written (a1, a2, a3 + g0); (b1) b1; (b2) b2i, b2ii;
  (b3) b3; (b4) b4; (b5) b5, b5b; (c) written (real-pin controls + byte-identity of the control block); (d) NOT in the script, manual, listed
  below; (e) written (`--mutate`); (f) written (`--own-only` and default). Open: PIN_TIP in the script is a placeholder until the pin commit.
- 2026-10-28 qa-engineer: **PHASE-2 COMMANDS, in this order** (fresh clone, quiet machine; wait until the first command prints nothing; run each line
  alone; paste each output here). `<NM>` = a node_modules directory with ajv (e.g. `<repo>/tools/dev/node_modules` after `npm ci` there, or the
  existing one from the manager's queue).
  ```
  D=$(mktemp -d) && git clone https://github.com/worldofmodcraft/registry "$D/registry" && cd "$D/registry" && git checkout task/089d-closed-verify-sweep-registry-d && git rev-parse HEAD && git --version
  export PYTHONDONTWRITEBYTECODE=1
  ps -eo pid,etime,args | grep -E '[-]verify\.sh' ; echo "ps-done"          # must print only ps-done
  bash docs/tasks/089d-verify.sh            2>&1 | tee "$D/089d-default.out"; echo "exit=${PIPESTATUS[0]}"
  ps -eo pid,etime,args | grep -E '[-]verify\.sh' ; echo "ps-done"
  bash docs/tasks/089d-verify.sh --mutate   2>&1 | tee "$D/089d-mutate.out";  echo "exit=${PIPESTATUS[0]}"
  bash docs/tasks/089d-verify.sh --own-only 2>&1 | tee "$D/089d-own.out";     echo "exit=${PIPESTATUS[0]}"
  ps -eo pid,etime,args | grep -E '[-]verify\.sh' ; echo "ps-done"
  bash docs/tasks/092-verify.sh             2>&1 | tee "$D/092-default.out";  echo "exit=${PIPESTATUS[0]}"
  ps -eo pid,etime,args | grep -E '[-]verify\.sh' ; echo "ps-done"
  bash docs/tasks/092-verify.sh --live-selftest 2>&1 | tee "$D/092-selftest.out"; echo "exit=${PIPESTATUS[0]}"
  ps -eo pid,etime,args | grep -E '[-]verify\.sh' ; echo "ps-done"
  bash docs/tasks/039a-verify.sh <NM>       2>&1 | tee "$D/039a.out";         echo "exit=${PIPESTATUS[0]}"      # hours; alone on the machine
  grep -c -E '^FAIL|SUMMARY failed=[1-9]' "$D"/*.out
  ```
  Expected: 089d default `SUMMARY failed=0`; `--mutate` `SUMMARY failed=0` with every (a) case reddened and all others unchanged; `--own-only` `failed=0`;
  092 default and `--live-selftest` exit 0, `SUMMARY failed=0`, the post-TIP line `NOT-APPLICABLE (merged)` on main or `PASS ... post-TIP` on the branch; 039a
  `ALL CHECKS PASSED`. `--live` is not required. Note: on a branch that is not main the 092 post-TIP check is applicable; the 092 default run must
  also be shown green on this branch HEAD, whose commits after TIP touch more than docs/tasks/092-* ... see the open point below.
  Open point for phase 2 (found while writing, not yet resolved): 092's TIP pin is `ab31a88...`; on THIS branch the commits after TIP include
  089d's own, which touch `docs/tasks/089d-*` and the umbrella copy; but on a fresh clone of the branch `ab31a88` is not on HEAD's first-parent chain
  (092 was merged into main, so TIP is reachable only through the merge), hence the check prints NOT-APPLICABLE (merged), as on main. Phase 2 must
  confirm this in the 092 default output; if it instead prints a FAIL, that is a finding for the manager, not something to adjust.
- 2026-10-28 qa-engineer: scope: files changed so far = `docs/tasks/092-verify.sh`, `docs/tasks/089d-verify.sh`, this task file; nothing else.
- 2026-10-28 qa-engineer: **pins final**: PIN_RED=32c641b5f56139a86c820f0b16d522c0f991d207, PIN_FIX=8eb35c228e429343a323943f6dc059fcec5f04a4, PIN_START=75eb9b0ce7ccddd8400eecd06f1a64eec0a1e753,
  PIN_TIP=d065a8643eaf095488c944c7fda2efa64e0cdd95 (set by pin commit c41a9c47eea88f3c92c5c74f53f72159b23b5a0c, which touches only 089d-verify.sh). Verified by plain git (not by running the
  script): `git diff --name-only PIN_START PIN_TIP` = the three own files. Correction to the entry above: the muddled sentence about "commits after TIP
  touching more than 092 files" is moot; the open point is only whether the fresh-clone 092 default run prints NOT-APPLICABLE (merged) (expected) or a FAIL.
  Phase 1 ends here; everything is written-but-not-run; phase 2 awaits the quiet machine.
- 2026-10-28 manager (session 14): phase 1 accepted for phase 2 (log check exit 0; head `8b12f72`). Triage (★, overnight ruling; §8b 3a):
  Q1 ★ A (is the umbrella's Q6 ★ A wording: `refs/heads/main` only when there is no remote; a stale local main never vouches). Q2 ★ A
  (`--no-renames`, consistent with the registry's existing rename handling; a rename into a 092 path must not hide its source). Q3 ★ A
  (scenarios in 089d-verify.sh; 092's diff stays minimal, per (f)). Q4 ★ A (a real conflict cannot arise for a 092-only branch; the forced
  resolution is the faithful form). Q5 ★ A. The phase-2 open point (092 default expected NOT-APPLICABLE (merged) on this branch) is a
  prediction to check, not an adjustment; a FAIL there is a finding.
- 2026-10-28 qa-engineer (phase 1 fix round after static review PASS-WITH-NOTES; still no `*-verify.sh` run). Finding -> commit:
  **(4)** `post_tip_check` now reads `git rev-list --parents -n 1 C` into a variable with `|| fail` before counting words, and a parent count below 3 words
  is also RED, so a git failure cannot give np=0 and skip the octopus check: commit `becb41802d95fc776000f381a45728d08826b3b2` (092-verify.sh only, one hunk
  `@@ -684 +684,3 @@` inside the function; this is the NEW PIN_FIX; the old 8eb35c2 is superseded; hunk limits of (f) unchanged).
  **(2)** second mutant in `--mutate` (the forbidden `--no-merges`-alone variant: merge handling removed) and **(1)** scenario `a2b` (merge, edit
  other.txt, then restore main's version; unfixed FAIL, fixed PASS): commit `a05a4d773357e0c3957d7344c2a971aa5fb30036` (089d-verify.sh only).
  **Deviation from the review's expected set, found with the development harness (throwaway shell outside the repo, sourcing only BEGIN-LIB..END-LIB; mutant
  python blocks extracted verbatim from the script):** the `--no-merges`-alone mutant flips **b2i, b2ii, b3, b4 AND b5, b5b** to PASS, not only the first four.
  Reason: b5/b5b are merges from "main" with no main ref; with merge handling removed they are invisible. The assertion is therefore the exact set
  `b2i b2ii b3 b4 b5 b5b`; (a) cases (a1, a2, a2b, a3), g0 and b1 keep the fixed verdicts (PASS, PASS, PASS, PASS, PASS, FAIL). Harness result, all 12 cases:
  fixed = PASS on g0 a1 a2 a2b a3, FAIL on b1 b2i b2ii b3 b4 b5 b5b; mutant 1 (old pattern) = FAIL on every case except g0; mutant 2 as stated.
  **(1) note:** a2 is tree-equivalent to a1 (same resulting tree and same `diff-tree --cc` result); only the procedure differs (explicit `checkout origin/main -- file`), as the
  spec text asks. a2b is the tree-equivalent variant that edits the merge first and then restores main's version.
  **Note on Q6:** the implementation's "C^2 is an ancestor of the main ref" equals the spec's "every commit in C^1..C^2 is reachable from main" except for an empty
  range (C^2 already an ancestor of C^1): there the spec is vacuously true while the implementation also needs C^2 itself on main; stricter, fail-safe (such a merge is then
  diffed C^1 vs C^2 and its files counted, never skipped).
  **(3) not done (optional):** a deterministic mid-function git failure (grafted/replaced object) was judged not simple enough; the failure paths are covered by the
  `|| fail` guards and by the existing unreachable-pin controls only. Booked as a possible follow-up, no decision needed.
  Pins re-derived next (PIN_FIX above; PIN_TIP by the pin commit that follows this entry).
- 2026-10-28 qa-engineer: re-pinned: PIN_FIX=becb41802d95fc776000f381a45728d08826b3b2, PIN_TIP=8a8eb472f9fc6d61434b1ca23cc00c245bae3084 (pin commit 7c658c97146d031cfe9d3c38723e47420bc5f4b5 touches only 089d-verify.sh). `git diff --name-only PIN_START PIN_TIP` = the three own files (plain git). Phase-2 commands unchanged. Still written-but-not-run.
- 2026-10-29 qa-engineer (phase 2, first run, head 70c3ead, fresh clone, git 2.53.0): `ps` before the run listed 22 shells whose args contain `pgrep` (started 2026-10-19,
  the stale `while pgrep ... 070-verify.sh` loops; the coordinator expected ten) plus my own current shell; no verify script was running. Run 1 of
  `089d-verify.sh` (default) exit 36: **defect in my script, not in 092**: `run_cases` is called twice (unfixed, then fixed) and built each scenario in the same
  directory name, so the second build failed (`fatal: destination path ... already exists`; 12 "scenario could not be built" plus 24 dependent FAILs; the 41 PASS lines
  before that, pins/extraction/positive controls, were fine). My phase-1 harness built each scenario once, so it never saw this. Fix: a per-build sequence number in the
  scenario directory name (`SC_SEQ`). This is a fix to a verification script's own harness, not a weakening: no assertion was changed. Run 1's output is discarded; all
  steps are re-run from a fresh clone of the new head.
- 2026-10-29 qa-engineer (phase 2, run 2: fresh clone of head d288b54b6a38d4fe189149b631aaa964b5f4ecff, git 2.53.0, PYTHONDONTWRITEBYTECODE=1, quiet machine: no verify script
  running; `ps` showed only pgrep loops and shells). Outputs in `/tmp/tmp.IS0EPfMlyN/*.out` (temp dir, not committed). Results, each a separate invocation:
  - `bash docs/tasks/089d-verify.sh`: **exit 0, SUMMARY failed=0, 65 PASS.** Trimmed: pins 6 PASS; extraction positive controls 6 PASS (red 15 lines, fixed 34 lines);
    case table (unfixed / fixed): g0 PASS/PASS; a1 FAIL/PASS; a2 FAIL/PASS; a2b FAIL/PASS; a3 FAIL/PASS; b1 FAIL/FAIL (other.txt); b2i FAIL/FAIL (other.txt); b2ii FAIL/FAIL (evil.txt);
    b3 FAIL/FAIL (side.txt); b4 FAIL/FAIL (octopus message); b5 FAIL/FAIL (other.txt); b5b FAIL/FAIL (other.txt). (c): BASE..FINAL red, unreachable HEAD/TIP pin red, non-ancestor TIP red,
    merged case NOT-APPLICABLE (merged) not PASS, control block byte-identical. (f): PIN_START..PIN_TIP = exactly the three files; 092 pins equal; outside the region diff lines 0.
  - `--mutate`: **exit 0, failed=0.** Mutant 1 (old pattern) reddens exactly a1 a2 a2b a3, others unchanged; mutant 2 (`--no-merges` alone) flips exactly b2i b2ii b3 b4 b5 b5b to PASS.
  - `--own-only`: **exit 0, failed=0.**
  - `bash docs/tasks/092-verify.sh`: **exit 0, SUMMARY failed=0, 188 PASS**; post-TIP line `NA post-TIP NOT-APPLICABLE (merged): ab31a88... is an ancestor of d288b54... but not on its first-parent chain`
    (the open point of phase 1 resolved as expected). `--live-selftest`: **exit 0, SUMMARY failed=0, 205 PASS**, same NA line.
  - `bash docs/tasks/039a-verify.sh <clone>/tools/dev/node_modules` (started 2026-10-29T05:29:47Z after `npm ci --prefix tools/dev`, exit 0): **RED, stopped by me.** At AC12 it printed
    `FAIL  another *-verify.sh kept running for six hours` (its wait_quiet at line 186 waited 21600 s). Cause, found with `ps`: pid 2864176, started 2026-10-29 04:52:34, a tool shell
    `/bin/bash -c ... eval 'O=$(cat /tmp/p2dir); (until false; do sleep 1000; done) >/dev/null 2>&1 & disown; nohup $O/run.sh $O/c s3 bash docs/tasks/090-verify.sh --sweep ...'` (task 090's
    sweep launcher; it has a child `sleep 1000` and never exits). Its command line contains `docs/tasks/090-verify.sh` and no "grep", so 039a's filter
    `ps -eo args | grep -E 'docs/tasks/[^ ]*-verify\.sh' | grep -v grep | grep -v 039a-verify\.sh` matches it for as long as it lives. It is not a verify run (no verify script process); not mine; **not killed**.
    I killed only my own 039a (pid 3846492). The pgrep loops from 2026-10-19 do NOT match (they contain "pgrep"). **Criterion (d)'s standalone 039a run is therefore NOT done**; (a)(b)(c)(e)(f) and 092 default/selftest are done and green.
  - Earlier in this phase: run 1 of 089d-verify.sh (head 70c3ead) exit 36 from my harness defect (reused scenario directory), fixed in d288b54 (entry above); pins re-derived: PIN_TIP=70c75139513654818b0d1768f902ccf4cd9fa989.
  Status stays in-progress: needs a quiet machine without pid 2864176 (or Ludwig/manager decision) to run 039a.
- 2026-10-29 qa-engineer (phase 2, step 9 re-run after Ludwig's cleanup): fresh clone at head ac8a998adad35dded3bc29216cb1322b5dcd70c2, `ps` before the run: 0 processes matching
  `docs/tasks/[^ ]*-verify\.sh`; `npm ci --prefix tools/dev` exit 0; `PYTHONDONTWRITEBYTECODE=1 bash docs/tasks/039a-verify.sh <clone>/tools/dev/node_modules` started 2026-10-29T19:43:55Z, output
  in `/tmp/tmp.uFOqoSGPFs/039a.out` (temp dir). The quiet-wait now passes (the earlier blocker is gone). **First red, run stopped by me (my own background task only) after 57 PASS:**
  `FAIL  008c-verify.sh exit 1 on HEAD: FAIL  out of scope: docs/tasks/089-closed-verify-sweep-registry.md`
  008a, 032 and 034 pass in the same sweep. This is exactly the finding booked in the umbrella log (2026-10-28, from 094's spec review): `008c-verify.sh` computes its own-change scope against the
  merge-base with the CURRENT main (`scope_base`, lines ~223-227 on main), so every later branch that adds files fails it. This branch adds the umbrella copy and part D's files, so it trips it.
  It is not caused by 089d's change and not fixable inside 089d's file scope (008c-verify.sh is not in it; the fix is the booked re-pin of 008c to its merged range). 039a has therefore NOT
  completed green on this branch; it was not run to the end, so any later script is unobserved. Criterion (d)'s 039a run remains OPEN. Status stays in-progress.
- 2026-10-29 qa-engineer (fix round, Ludwig's decision "A: fixed SHAs only"; WRITE ONLY, no verify script run, `bash -n` and throwaway repos only). Audit of every own-change check in
  `089d-verify.sh` (grep for HEAD, origin/main, merge-base, `..`): **none reads HEAD, a branch name or a range ending in HEAD.** Own-change checks were already on fixed SHAs:
  (f) `git diff --name-only PIN_START PIN_TIP` (PIN_START = dispatch commit, PIN_TIP = last commit before the pin commit), the blobs of PIN_RED and PIN_FIX, and 092's typed BASE/FINAL/TIP; all
  `HEAD` uses are inside synthetic scenario repos or the temp merged clone, and `ROOT` is only cloned to reach the pinned objects. So there is nothing to replace (old -> new: none), and the
  requested red-first cell ("current script on a clone with a later commit must fail its own-change check") **cannot be produced: the script has no HEAD-relative own-change check.** I report
  that instead of inventing a failure. In place of a red cell I made the property explicit and self-proving: new `later_commit_checks` (commit ae4ed0e5d8a0af3b1f93866796e317812a496bb7, 089d-verify.sh only; runs in default and
  `--own-only`): (1) a temp clone detached at PIN_TIP with one extra later commit still gives `PIN_START..PIN_TIP` = exactly the three own files; (2) positive control: the HEAD-relative form
  (`diff PIN_START HEAD`) on that same clone is different (includes the extra file), so the control distinguishes the two; (3) a grep over `scope_checks` and `extract` finds >0 pin names
  and 0 occurrences of HEAD / origin/main / merge-base. Development harness (sourced just that function, throwaway clone, seconds): all three PASS. Written-but-not-run as a script.
  092-verify.sh untouched (its post-TIP check is correct by design). Assertion intent unchanged; nothing weakened. The 039a red on the booked 008c scope finding is separate (008c-verify.sh is outside this file scope).
  Pins: PIN_RED, PIN_FIX, PIN_START unchanged; PIN_TIP re-pinned by the next commit.
- 2026-10-31 qa-engineer (phase 2 on the merged head): merged `origin/main` (f30dfbd, task 089e) into the branch without conflict (merge commit ea2567e75d252737eacb1a2220eb3916b2d8c1d4; the umbrella file had no diff against main's), pushed; fresh
  non-shallow clone at that head (`rev-parse --is-shallow-repository` false), `npm ci --prefix tools/dev` exit 0, `PYTHONDONTWRITEBYTECODE=1`, `ps` match count 0 before every run. Results, separate invocations:
  `089d-verify.sh` exit 0, 68 PASS, `SUMMARY failed=0` (including the new later-commit checks: `PASS (f) with a later commit on top, PIN_START..PIN_TIP is still exactly the three own files`,
  `PASS (f) positive control: the HEAD-relative form of the check WOULD be red on that clone (4 files)`, `PASS (f) the own-change code (scope_checks, extract) names pins and reads no HEAD, origin/main or merge-base`);
  `--mutate` exit 0, 30 PASS, `failed=0`; `--own-only` exit 0, 23 PASS, `failed=0`; `092-verify.sh` exit 0, 188 PASS, `failed=0`, `NA post-TIP NOT-APPLICABLE (merged): ab31a88... is an ancestor of ea2567e...`;
  `092-verify.sh --live-selftest` exit 0, 205 PASS, `failed=0`.
  **Standalone `039a-verify.sh <clone>/tools/dev/node_modules` (started 2026-10-29T20:23:39Z): criterion (d)'s 039a run is BLOCKED, not red.** Output at the stop: 59 PASS, 0 FAIL; in the AC12 sweep these scripts
  exited 0 on HEAD, in order: 006, 007a, 007b, 008a, 008b1, 008c, 032, 034 (last lines `PASS  008c-verify.sh exits 0 on HEAD`, `PASS  032-verify.sh exits 0 on HEAD`, `PASS  034-verify.sh exits 0 on HEAD`). It then
  hung at the next script (039b) for about 20 hours: the known S4/Q7 deadlock (on main, 039a runs 039b without `--no-closed`, so 039b's own AC12 sweep waits for its parent 039a forever; fixed in task 089b's branch,
  not yet merged). Stopped by the coordinator's instruction on 2026-10-31 with TaskStop on my own two background jobs (no kill/pkill); `ps` afterwards shows no verify process of mine. Raw output was in `/tmp/tmp.rukX60UIhi/039a.out` (temp dir, not committed).
  **Status: in-progress, (d) blocked on 089b's merge (S4 fix); re-run the standalone 039a after 089b merges.** (a), (b), (c), (e), (f) and the 092 default/selftest runs are green on the merged head. Idle until re-dispatched.
