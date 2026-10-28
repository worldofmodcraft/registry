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
