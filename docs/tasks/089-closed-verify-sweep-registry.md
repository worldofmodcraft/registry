# Task 089: registry closed scripts — move every own-change check from HEAD to its pinned FINAL (the 084/087 shape, one sweep)

- **Mission:** SITE-V1 (verification integrity) — **Status:** spec-approved 2026-10-26 (manager, after independent spec review; fixes mechanical); dispatch after the open PRs merge
- **Agent / model:** qa-engineer / sonnet (§3.5; model per its agent frontmatter)
- **Budget:** large (13 findings, about 10 scripts; see Size — splitting is the default and is proposed)
- **Branch / worktree:** `task/089-closed-verify-sweep-registry` / `~/wt/registry-task-089`, cut from registry `origin/main` after the open PRs below merge. The task file is drafted in the platform repo (session/12) and is copied to the registry branch at cut.
- **Repo:** registry. **Graph:** verification tooling only.

## Objective
After this task no closed registry verify script and no registry test file reads a file at `HEAD`, `origin/main` or the worktree as evidence of **that task's own change**. Each such check reads the file with `git show FINAL:path` (or `git diff BASE..FINAL`), with BASE/FINAL = the script's merged PR range (merge commit M: BASE = `git merge-base M^1 M^2`, FINAL = `M^2`; reuse pins the script already defines). A pin that cannot be resolved is a `FAIL`, never a skip. Live-property checks stay on HEAD. Each script gets a `--mutate` case (or extends its existing one) that widens the fixed check back to HEAD and must redden, and a control that merges a later synthetic branch editing the same file and must stay green (REVIEW-CHECKLIST item 12). Source: inventory `docs/research/closed-verify-sweep-088.md` (read at registry `4268735`); Ludwig's decision 2026-10-26 ("A star on the above one").

## Context to load (exhaustive)
- ADRs: none new. Doctrine: MANAGER.md §2b (size), §2c rules 1-5; REVIEW-CHECKLIST.md item 12; SPEC-CHECKLIST.md 5b.
- Files: the inventory above; registry tasks 084 (`084-repin-075-verify.md`, `084-verify.sh`) and 087 (`087-repin-032-067-readme.md`, `087-verify.sh`) as the reference pattern; the scripts and tests in File scope; `docs/tasks/070-verify.sh` header.
- Survey docs: `docs/research/closed-verify-sweep-088.md`.

## Dependencies
Starts only after these are merged into registry `main`: 087 (#24), 082 (#20), 039b (#23). Reasons: 087 fixes 032/067/070 AC4.m1 (excluded here); 082 is the later branch that edits `docs/contracts/README.md` (the red-first control for findings 1-7); 039b changes the `*-verify.sh` sweep relation to 039a (S4) and part B (039a, test_ci_gate, 065) waits for it. Registry 092 (#25) is not a dependency: no file of this task depends on it (dropped from the list in the review; if #25 is merged first, the task base simply includes it). Platform PRs #81 and #84 do not touch this task. Task 090 is independent of this one.

## Findings -> task assignment
Numbers are the inventory's. All 13 registry findings are assigned here; none is excluded.

| # | Where | Own change of | Fix |
|---|---|---|---|
| 1 | `007a-verify.sh:117` README "tools/registry" and "task 039" | 007a | README blob at pin `e009ef0b28413700f0c41470f6e45905bf627cda..aaf426060338776a4556f35c1bb5cb6a20d65ea4` |
| 2 | `007a-verify.sh:118` README lacks "task 007$" / "task 007 +builds" | 007a | same pin |
| 3 | `007b-verify.sh:100` README "ownership" and "task 039" | 007b | `fb76ee54aac413cd40fa61df31c3f11d8cbb76e3..17555d94323192eaf315c49818ff34b393f57aa2` |
| 4 | `007b-verify.sh:101` "ownership checker (task 007b" not "still to come" | 007b | same pin; also make the check non-vacuous (087 log: today the grep matches no line, so the branch passes vacuously) |
| 5 | `008a-verify.sh:74` README mentions build-pipeline.md | 008a | `4d4a204fb7368db7947d86c9f0e9abe72bf7bc96..9ccb3ec3451cc3cd18be8b393d5e734734f5bad5` |
| 6 | `057-textchecks.py:179-180` default `--readme`, called from `057-verify.sh:35` | 057 | `057-verify.sh` writes the README blob at the pin (`a50daacd7e26235d1acdeadc7d19265f1b2d04e3..3ab8f43d96013889a48e2005c57a75731b3d655f`) with `git show` and passes it via `--readme`; the default path stays for live use |
| 7 | `tests/registry/test_hardening.py:153` README contains `--no-renames` | 007a fix round | read the blob at `aaf426060338776a4556f35c1bb5cb6a20d65ea4`, or drop the README half; the CLI-help half at :152 stays live |
| 8 | `065-verify.sh:208-218` (AC3.5) `test_hardening.py` in the HEAD clone | 065 | blob at `e87498b47eced6fe388ec798ce31fbb6db09c16f` (range `4356583fb2360592a680f40bee396f9f23df35a4..e87498b47eced6fe388ec798ce31fbb6db09c16f`). Suspected cause of a 065 failure seen by the 039b agent: confirm or refute in the log with the observed output |
| 9 | `075-verify.sh:100-135` (AC4) `contracts/ownership.md` sentences in the HEAD clone | 075 | blob at `7d91a3d54d19431f4e3eff2dbed409cf00320887` (`79d537779c9fe717657aed9c4c85f90ba71fcd14..7d91a3d54d19431f4e3eff2dbed409cf00320887`). HIGH: 008b's ownership carve-out edits them |
| 10 | `039a-verify.sh:149-150` `HEAD:config/r11-identity.json` must be null | 039a | blob at `ceb0458346ecf9f68454d1e3f2f1dafc1ea301c4` (`4356583fb2360592a680f40bee396f9f23df35a4..ceb0458346ecf9f68454d1e3f2f1dafc1ea301c4`). HIGH: reddens when Ludwig configures R11 |
| 11 | `tests/registry/test_ci_gate.py:1018-1021` (AC9ProductionR11Unconfigured) | 039a | move the check into `039a-verify.sh`, which has the pins (Q2, manager ★ B); the unit test is deleted, not weakened |
| 12 | `039a-verify.sh:111-148` exact per-class test counts of `test_ci_gate.py` in the HEAD clone | 039a | counts taken from the file at `ceb0458346ecf9f68454d1e3f2f1dafc1ea301c4`. MEDIUM (inference): conditional. Either it is fixed with a red-first fixture (a later branch adds a test, old script reddens) and a mutation, or it is recorded live with the observed output showing the counts do not change under a later test addition |
| 13 | `tests/registry/test_classify.py:132-134` `reserved-namespaces.json` names == {mc, test} | 007a | blob at 007a's FINAL `aaf426060338776a4556f35c1bb5cb6a20d65ea4` (merge `3c94cf2c87f2e254cafbfe024c63525a6c686ff7`); see Q3. LOW |

Pins above are the inventory's. The agent re-derives each from the merge commit and records the derivation; where a script already defines a pin, that pin is reused.

### Side findings assigned here
- S1. `069-verify.sh:204-209` reads `origin/task/064-schema-check-end-anchor`; when the branch is deleted AC5.3 prints "not evaluated" and does not fail (silent skip). Fix: read a pinned full SHA of that branch's tip; unreachable = FAIL. The SHA must be reachable from registry `main`; if it is not, use a committed fixture blob instead.
- S2. `057-verify.sh:30` reads local `main` of `/home/ludwig/wom` (hard-coded path) for ADR-0121's status. Fix: read the ADR at a pinned commit of the history the script already knows, or take the status from a fixture blob; no hard-coded path to a working copy. Which of the two is Q4. In part A2 only.
- S3. `070-verify.sh` header still says "ten closed scripts"; correct the number to the count the script actually runs (derive it, do not copy it). Header text only.
- S4. `039a-verify.sh` sweeps every `*-verify.sh`, including `039b-verify.sh`, which skips 039a. After 039b merges the suite runs twice. Decision is Q1; nothing is decided here.
- S5. Open observation, not a task item: the one-off `FAIL AC1.5` (062 inside 067) seen once in 087's run. If the quiet-machine runs of this task reproduce it, it becomes a finding against 062 and is logged with the full output.

### Excluded, with reason
- `070-verify.sh --mutate` AC4.m1: fixed inside 087 (#24), not here.
- `032-verify.sh` N5/N5b and `067-verify.sh` AC2.5: fixed by 087.
- Live reads that correctly stay on HEAD (inventory last section): contract prose/schema pins (006, 032, 034, 057-textchecks, 065 AC5.1), two-files-agree checks, tool/CLI help and hygiene checks, mutation-runner preconditions, stable doc-presence needles. The agent classifies each touched check in the log with one line why (own-change vs live), as 087 did.

## Size
Exceeds SPEC-CHECKLIST 5b. Source files touched: `007a-verify.sh`, `007b-verify.sh`, `008a-verify.sh`, `057-verify.sh`, `057-textchecks.py`, `065-verify.sh`, `069-verify.sh`, `070-verify.sh`, `075-verify.sh`, `039a-verify.sh`, `tests/registry/test_hardening.py`, `tests/registry/test_ci_gate.py`, `tests/registry/test_classify.py`: 13 against a cap of 5 (verify scripts are not excluded from this count; only the new `089-verify.sh` and fixtures are). Changed lines are not estimated here; the agent reports them. Splitting is the default (MANAGER.md §2b). Decision (manager ★, session 12): four parts by script group. This file is the umbrella; one task file per part is cut from it at dispatch (`089a1-…`, `089a2-…`, `089b-…`, `089c-…`), each with its own `NNN-verify.sh` (named `089a1-verify.sh` etc.), one PR, same pattern, and its own file count within the cap of 5:
- A1 (README and namespace pins; findings 1-5, 7, 13): `007a-verify.sh`, `007b-verify.sh`, `008a-verify.sh`, `tests/registry/test_hardening.py`, `tests/registry/test_classify.py` - 5 source files.
- A2 (finding 6, S2, S3): `057-verify.sh`, `057-textchecks.py`, `070-verify.sh` (header only) - 3 source files.
- B (contract and R11 pins; findings 8-12, S4): `065-verify.sh`, `075-verify.sh`, `039a-verify.sh`, `tests/registry/test_ci_gate.py` - 4 source files. Goes first: items 9 and 10 are HIGH. Item 9 reddens when the 008b-3a ownership carve-out merges (it edits the ownership.md sentences `075-verify.sh` pins at HEAD); item 10 reddens when Ludwig configures R11 (`config/r11-identity.json` stops being null). B waits for 039b (#23) because it edits `039a-verify.sh` and S4 concerns the 039b relation.
- C (S1): `069-verify.sh` - 1 source file.
Why one task might still be acceptable: every change is the same mechanical move, one reference pattern, one set of pins, and one quiet-machine full sweep serves all. Why splitting is better: 13 files each need a red fixture, a mutation and a later-branch control; a single reviewer round cannot hold that, and one failure would block the HIGH items. Changed lines per part are reported by the agent. Q5 records the choice.

### Part D (added 2026-10-28, session 13; from session 12's final status): the post-TIP merge-into-branch defect
- D1. `docs/tasks/092-verify.sh:657-700` (AC9 post-TIP) lists files with `git log --first-parent --name-only TIP..HEAD`. With git >= 2.31,
  `--first-parent` implies `--diff-merges=first-parent`, so a merge of `main` INTO the task branch lists all of main's files and the check
  goes red on a correct branch (confirmed by the spec reviewer with git 2.53.0 in a throwaway repo). The trigger that makes it live is M9's
  "Require branches to be up to date" (GitHub's "Update branch" makes exactly that merge). On registry `main` today the check prints
  NOT-APPLICABLE (092 is merged) and no other script uses the pattern (`git grep`, e2f7fe3), so the risk is latent: copying (warned in
  008c's brief). The comment at `092-verify.sh:657-658` ("lists no files for merge commits") is wrong and is rewritten.
  **Definition (Q6, manager ★ A):** a merge C on the first-parent chain `TIP..HEAD` is a *merge from main* only if every commit in
  `C^1..C^2` is reachable from the local ref `refs/remotes/origin/main` (or `refs/heads/main` when there is no remote). Local read, no
  network; main advances only by merges, so a past merge from main stays an ancestor of current main. If neither ref exists, or `C^2` is
  not an ancestor of it, the merge is not from main. A merge not from main contributes every file of `git diff --name-only C^1 C^2`. For
  **every** merge, the files of `git diff-tree --cc --name-only -r C` (differing from all parents: conflict resolutions and evil-merge
  edits) are added to the set. Non-merge first-parent commits are listed as today. An octopus merge (more than two parents) is RED. A
  stale clone whose main predates the merge therefore gives RED, never a skip; this is accepted and stated in the script header. The
  log records the exact commands and `git --version`.
  Source file: `docs/tasks/092-verify.sh` (1 file). Disjoint from A1/A2/B/C, any order; dispatch only after this part's spec approval.
- D context (in addition to the umbrella list): registry `docs/tasks/092-artifact-naming-archive-url.md` (log lines 365-412),
  `docs/tasks/092-verify.sh` lines 640-720.
- D criteria (shipped as `089d-verify.sh`; mechanism: it pins the red and the fixed commit of `092-verify.sh` as full 40-character SHAs,
  extracts `post_tip_check` from each with `git show <sha>:docs/tasks/092-verify.sh` and a sed range between two marker lines named in
  the script, evaluates each with stub `G`/`pass`/`fail` in a temp clone, never reads the worktree or HEAD, and asserts every extraction
  is non-empty as a positive control):
  (a) red first: TIP + a merge of a synthetic `main` commit that changes a file outside `docs/tasks/092-*` into the branch: unfixed RED,
      fixed GREEN; and the same with a main commit that changes a file the branch does not touch, resolved to main's version: GREEN.
  (b) controls RED after the fix: (b1) a post-TIP branch commit touching a non-092 file; (b2) a merge from main whose resolution differs
      from both parents, twice: a modified main-supplied file, and a new file; (b3) a `--no-ff` merge of a non-main side branch touching
      a non-092 file; (b4) an octopus merge; (b5) main ref absent.
  (c) the existing AC9 controls (BASE..FINAL red, unreachable pin red, non-ancestor TIP red, merged case prints NOT-APPLICABLE (merged))
      pass unchanged in the fixed script; the merged-case control is kept byte-for-byte.
  (d) `092-verify.sh` default and `--live-selftest` exit 0 on registry main, and standalone `039a-verify.sh <node_modules>` passes; each
      run alone on a quiet machine (`ps` logged), `PYTHONDONTWRITEBYTECODE=1`, output pasted; `--live` (network) not required.
  (e) mutation: restoring the old `git log --first-parent --name-only` pattern in a temp copy reddens (a) and only (a).
  (f) scope: `git diff --name-only` for part D equals exactly `docs/tasks/092-verify.sh`, `docs/tasks/089d-verify.sh` and this task file;
      inside `092-verify.sh` the hunks touch only the post-TIP comment, `post_tip_check`, its controls and the one call-site line; 092's
      pins (BASE, FINAL, TIP) and `own_change_checks` are unchanged (a hunk elsewhere is a finding).
- D forbidden: skipping or relaxing the post-TIP check for any merge; replacing it with `--no-merges` alone; using `HEAD`/`origin/main`
  as a skip condition; changing or removing the existing AC9 controls.

## File scope (declared)
Exactly these, and nothing else:
`docs/tasks/007a-verify.sh`, `docs/tasks/007b-verify.sh`, `docs/tasks/008a-verify.sh`, `docs/tasks/057-verify.sh`, `docs/tasks/057-textchecks.py`, `docs/tasks/065-verify.sh`, `docs/tasks/069-verify.sh`, `docs/tasks/070-verify.sh` (header text only), `docs/tasks/075-verify.sh`, `docs/tasks/039a-verify.sh`, `tests/registry/test_hardening.py`, `tests/registry/test_ci_gate.py`, `tests/registry/test_classify.py`, `docs/tasks/092-verify.sh` (part D only, AC9 post-TIP only), `docs/tasks/089-closed-verify-sweep-registry.md` (log), `docs/tasks/089-verify.sh` (new; per part `089a1-verify.sh`, `089a2-verify.sh`, `089b-verify.sh`, `089c-verify.sh`, `089d-verify.sh`, each part touching only its own files listed under Size). In each file only the checks named in the table. Anything else = stop and report.

## Acceptance criteria
All command-based, shipped per part as `docs/tasks/089<part>-verify.sh` (below "089-verify.sh" means that part's script and criteria for that part's findings), whose output the log pastes. Pins in scripts and in `089-verify.sh` are full 40-character SHAs. It runs in a fresh clone, with `PYTHONDONTWRITEBYTECODE=1`, own-change checks on fixed SHAs.
1. Red first (§2c rule 5): for each finding 1-13 and S1, a fixture or temp-clone step that makes the later change (merge of a synthetic branch that rewords or removes the pinned sentence/file content; for 1-6 and 7 the real branch `origin/task/082-pipeline-trigger-contract` is the later branch if still reachable, else a synthetic one) is shown failing against the old script at the red commit, then passing after the fix. A fixture that passes on the unfixed script is rejected. Finding 12 is conditional: either it is fixed with a red-first fixture (the later branch adds a test to `test_ci_gate.py`) and a mutation, or it is recorded live with the observed output; the log says which. Finding 11: the moved assertion in `039a-verify.sh` is shown red when `config/r11-identity.json` at the pin is made non-null in a temp clone, and the same content is shown to be asserted (the old unit test's condition, quoted in the log).
2. Pins: each fixed check reads `git show FINAL:path` with FINAL a full 40-character reachable SHA recorded in the script; `089-verify.sh` asserts every fixed check's pin equals `git rev-parse <merge>^2` (or the merge-base for BASE) for the merge found by `git log --merges --grep`. No `HEAD`, `origin/main` or worktree read remains for a check classified own-change (a grep over the touched checks, with a non-zero count required, §2c rule 1).
3. Unreachable pin = FAIL: for each script, replacing a pin with `deadbee` turns the corresponding check red, and no check prints "skip" or "not evaluated" (grep the script output for those words, expected 0 hits, with a positive control that the grep can match).
4. `--mutate`: for each fixed check, widening it back to HEAD (in a temp clone, where a later branch has changed the file) turns that check red and only that check; one mutation per fixed finding (13 findings plus S1, minus any finding 12 recorded live, and finding 11 mutated in `039a-verify.sh`); the controls (unmutated) stay green. Mutation results are listed one per line.
5. The item-12 control: every fixed script, run on HEAD and on a merge of HEAD with a later synthetic branch that edits the same files (README sentence, ownership.md sentence, `config/r11-identity.json`, a new test in `test_ci_gate.py`, `reserved-namespaces.json`), exits 0. Positive control: the same merge makes the unfixed scripts exit non-zero.
6. S1: with `origin/task/064-schema-check-end-anchor` deleted in the temp clone, `069-verify.sh` AC5.3 still passes (pinned SHA) and with a bad pin fails. The pinned SHA is shown reachable from registry `main` (`git merge-base --is-ancestor <sha> origin/main`); if it is not, a committed fixture blob is used and the criterion shows the blob read.
7. S3: the `070-verify.sh` header count equals the number of closed scripts the script iterates, asserted by `089-verify.sh`; `git diff` of 070 shows header lines only.
8. S4: the behaviour chosen under Q1 is demonstrated: either the suite runs each script once (a count of invocations in a logged run) or the doubled run is documented in the 039a header.
9. Quiet machine (`ps` logged; wait until no other `*-verify.sh` runs, as 087 did): every closed script, one at a time, green on HEAD and on the merge with the later synthetic branch. If the one-off `FAIL AC1.5` (062 inside 067) recurs, the full output is pasted and S5 becomes a finding.
10. Finding 8: the log states whether the 039b agent's 065 failure is reproduced by merging 039b onto the base with the unfixed 065, with the failing check named; the fixed 065 passes on the same merge.
11. Scope: `git diff --name-only BASE..FINAL` for the task is a subset of File scope; 070 differs by header lines only.

## Forbidden here
Weakening any check: no looser pattern, no dropped assertion, no lowered count, no `|| true`, no skip on an unresolved pin (§3.7; MANAGER.md §2c). Pinning a live property (tests green, other closed scripts green, contract text pinned on purpose, CLI help, hygiene); each such check stays on HEAD. Editing any script or file outside File scope, including `032-verify.sh`, `067-verify.sh` (fixed by 087). Hard-coded absolute paths to a working copy in a new check. Environment-variable overrides of pins (078/085 forbid them). Deleting a check to make a sweep green. Starting before the dependency PRs are merged and the spec is approved.

## Deliverables
Fixed scripts and tests as in File scope; `089-verify.sh` (or `089a/b/c`) with red fixtures, mutations and controls; this file's log with the pins derived, the one-line own-change/live classification per touched check, the red/green/mutation output pasted, and the finding-8 and S5 outcomes; docs that mention the changed behaviour updated in the same branch.

## Questions  (agent-maintained; see MANAGER.md 8b)
- Q1: S4 - 039a sweeps every `*-verify.sh` including 039b-verify, which skips 039a, so the suite runs twice after 039b merges | options: A) leave as is and document the double run in the 039a header; B) make 039a skip `039b-verify.sh`; C) make 039a sweep only scripts older than 039a | assumed: A (conservative: changes no check) | built on assumption: 039a header text only
- Q2: finding 11 - `test_ci_gate.py:1018-1021` | options: A) read `config/r11-identity.json` at FINAL inside the test; B) move the check into `039a-verify.sh` (which has the pins) and delete the unit test; C) keep it live as a canary | assumed: B | built on assumption: `test_ci_gate.py`, `039a-verify.sh`
- A (manager ★, session 12): B. The unit test `AC9ProductionR11Unconfigured` is deleted from `test_ci_gate.py`; the assertion (production `config/r11-identity.json` is null) is preserved in `039a-verify.sh` at the pin. Reason: a unit test that reads a git blob fails permanently under CI's shallow checkout. The log shows the preserved assertion.
- Q3: finding 13 - `test_classify.py:132-134` | options: A) read the blob at the 007a pin; B) assert the property the test guards (names include mc and test) instead of equality | assumed: A (B changes what is asserted, so it needs approval) | built on assumption: `test_classify.py` only
- A (manager ★, session 12): A, with the consequence stated and accepted: the test then reads a blob and no longer guards the live `reserved-namespaces.json`; a later edit to the live list is not caught by this test.
- Q4: S2 - `057-verify.sh:30` ADR-0121 status | options: A) read the ADR at a pinned commit; B) a fixture blob in the verify script directory | assumed: A | built on assumption: line 30 only
- Q5: the split in Size | options: A) four parts A1/A2/B/C, B first; B) two tasks; C) one task | assumed: A (splitting is the default) | built on assumption: none yet; one task file per part is cut at dispatch
- A (manager ★, session 12): A.
- Q6: part D - how "a merge from main" is identified offline | options: A) local ref check: every commit of `C^1..C^2` reachable from `refs/remotes/origin/main` (else `refs/heads/main`), absent ref = not from main; B) any second parent counts as main; C) `--no-merges` | assumed: A | A (manager ★, session 13, after spec review finding 1): B and C let a side branch's non-092 files through unseen.

---
# Task 089 log  (append-only, updated continuously by the executing agent)
- 2026-10-26 doc-writer (session 12): drafted from the 088 inventory. Not yet reviewed. No pins re-derived; the pins in the table are the inventory's.
- 2026-10-26 manager (session 12): independent spec review PASS-WITH-AMENDMENTS folded in (mechanical). Mapping: split A -> A1/A2 with file counts (review 1); S2 only in A2 (2); B-first justified, 092 dropped as dependency (3); finding 12 conditional in AC1/AC4 (4); Q2 -> B, test AC9ProductionR11Unconfigured moved to 039a-verify (5); S1 reachability criterion (6); full 40-char SHAs in pin tables (7); Q3 consequence stated (8). Status set to spec-approved.
- 2026-10-28 manager (session 13): part D added (post-TIP merge-into-branch defect in `092-verify.sh`, booked in session 12's final status); File scope extended by `092-verify.sh` (AC9 post-TIP only) and `089d-verify.sh`. Scope change: part D needs an independent spec review before its dispatch; parts A1/A2/B/C keep their approval.
- 2026-10-28 manager (session 13): part D independent spec review PASS-WITH-AMENDMENTS (9 findings: 2 HIGH, 4 MED, 3 LOW), all folded in: (1 HIGH) definition of a merge from main, Q6 ★ A; (2 HIGH) main-file GREEN case in (a), two-form resolution control (b2); (3 MED) side-branch and octopus controls (b3, b4); (4 MED) red/fixed extraction mechanism; (5 MED) D forbidden list; (6 MED) scope (f) with hunk limits and unchanged pins, 039a run in (d); (7 LOW) quiet-machine rule in (d); (8 LOW) context lines; (9 LOW) dispatch after D's approval. Part D **spec-approved** (manager; amendments are the reviewer's text, no decision changed beyond Q6 ★).
- 2026-10-28 manager (session 13): **new finding booked for this sweep (from 094's spec review):** `008c-verify.sh`'s own-change scope check
  uses the merge-base with the current main, so after 008c merged (registry `32c641b`) it fails on main ('no changes since base') and on any later
  branch (out-of-scope files). It must be re-pinned to 008c's merged range (BASE/FINAL from merge `32c641b`) like findings 1-13. Part assignment
  at the next cut (A1-like); not dispatched yet.
