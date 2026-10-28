# Task 089a1: registry closed scripts — part A1 (README and namespace pins; findings 1-5, 7, 13)

- **Mission:** SITE-V1 (verification integrity) — **Status:** in-progress 2026-10-28 (cut from umbrella 089 at dispatch, session 14; umbrella spec-approved 2026-10-26, parts per Q5 ★ A)
- **Agent / model:** qa-engineer (model per frontmatter) — **Budget:** medium (≤ 3 agent-sessions)
- **Branch / worktree:** `task/089a1-closed-verify-sweep-registry-a1` / `~/wt/registry-task-089a1`, from registry main `32c641b`
- **Umbrella (authoritative for findings, pins, criteria, forbidden list, Q1-Q6):** `docs/tasks/089-closed-verify-sweep-registry.md` (copied
  into this branch from platform main `4321d07`; read-only here — do not edit it).

## Scope of this part
Source files: `docs/tasks/007a-verify.sh`, `docs/tasks/007b-verify.sh`, `docs/tasks/008a-verify.sh`, `tests/registry/test_hardening.py`, `tests/registry/test_classify.py` (5). New: `docs/tasks/089a1-verify.sh`. Log: this file. Anything else = stop and report.

## Acceptance criteria
The umbrella criteria 1-5, 9 and 11, restricted to findings 1-5, 7 and 13 (Q3 answered: A, consequence accepted). Shipped as `docs/tasks/089a1-verify.sh`. Quiet machine (criterion 9) is mandatory: one script at a time, `ps` logged before each run.
Same pattern as part B (`origin/task/089b-closed-verify-sweep-registry-b`, file `docs/tasks/089b-verify.sh`) and the 084/087 reference pattern.

## Questions  (agent-maintained; see MANAGER.md 8b)

---
# Task 089a1 log  (append-only)
- 2026-10-28 manager (session 14): cut from umbrella 089 and dispatched for phase 1 (no verify runs while 089b's long driver holds the machine);
  base registry main `32c641b` (087, 082, 039b, 092, 008c merged).
- 2026-10-28 qa-engineer (phase 1; NO `*-verify.sh` executed, per the brief: another task's long driver holds the machine): read the task, umbrella 089,
  part B's `089b-verify.sh` (reference pattern), 087/084 files. Machine state at start (`ps`): `039a-verify.sh`, `064-verify.sh`, `062-verify.sh`, `008a-verify.sh` of other
  worktrees running, which confirms the constraint. Tooling note: `pytest` is NOT installed here (`No module named pytest`); the two test files are run with
  `python3 -m unittest discover -s tests/registry -p <file>` instead (same tests; the repo's own runner is unittest). Recorded as an assumption, see Questions.
  RED commit (next): `docs/tasks/089a1-verify.sh` only (plus this log). The source fixes follow in the FIX commit, so the script exists before the fix (§2c rule 5).
  The script is WRITTEN-BUT-NOT-RUN: every criterion is unproven until phase 2.
- 2026-10-28 qa-engineer: pins re-derived (read-only `git`, no script run). Merge commits found on registry main with `git log --first-parent --merges -E --grep="task/<branch>"`; BASE = `git merge-base M^1 M^2`, FINAL = `git rev-parse M^2`:
    007a (PR #10) M `3c94cf2c87f2e254cafbfe024c63525a6c686ff7`: BASE `e009ef0b28413700f0c41470f6e45905bf627cda`, FINAL `aaf426060338776a4556f35c1bb5cb6a20d65ea4`  (= the umbrella's pin)
    007b (PR #12) M `70cedca7eb189710b2413180cbd93a29fc25d5d2`: BASE `fb76ee54aac413cd40fa61df31c3f11d8cbb76e3`, FINAL `17555d94323192eaf315c49818ff34b393f57aa2`  (= the umbrella's pin)
    008a (PR #7)  M `a50daacd7e26235d1acdeadc7d19265f1b2d04e3`: BASE `4d4a204fb7368db7947d86c9f0e9abe72bf7bc96`, FINAL `9ccb3ec3451cc3cd18be8b393d5e734734f5bad5`  (= the umbrella's pin)
  Each script already defined these pins as 7-character SHAs; they are reused and lengthened to the full 40 characters (the short form was ambiguous-prone and the umbrella requires full SHAs). `deadbee` resolves to nothing (`git rev-parse --verify` empty).
  FIX commit content (5 source files, all in scope), one-line classification per touched check (own-change vs live):
    - 007a-verify.sh `criterion 12` (README "tools/registry" + "task 039", finding 1): OWN-CHANGE of 007a -> `git show $FINAL:docs/contracts/README.md`; unreadable pin FAILS.
    - 007a-verify.sh README-no-longer-says (finding 2): OWN-CHANGE of 007a -> same blob; an empty/unreadable README FAILS instead of passing the negative grep vacuously (new).
    - 007b-verify.sh `criterion 12` (README "ownership" + "task 039", finding 3): OWN-CHANGE of 007b -> blob at FINAL007B.
    - 007b-verify.sh "still to come" (finding 4): OWN-CHANGE of 007b -> blob at FINAL007B, and made NON-VACUOUS: the old grep matched no line at HEAD (and at FINAL007B), so the branch always passed. It now fails when (a) a line says the checker is "still to come", or (b) the README lacks the positive statement `**built** (task 007b) is the ownership checker` (exactly one line at FINAL007B, checked read-only). No assertion was dropped; one was added.
    - 008a-verify.sh README mentions build-pipeline.md (finding 5): OWN-CHANGE of 008a -> blob at FINAL. The BASE/FINAL definition block was MOVED up above section 2 (it was below, at the scope check) so the README check can use it; the scope check and its loop are unchanged. Output order of the other checks is unchanged.
    - tests/registry/test_hardening.py README half of `test_f2_help_and_readme_say_diff_with_no_renames` (finding 7): OWN-CHANGE of the 007a fix round -> blob at `aaf4260...` (007a FINAL). The CLI-help half (line above) stays LIVE (tool help, a live property). Chose "read the blob" over "drop the README half" so no assertion is lost.
    - tests/registry/test_classify.py `test_the_real_reserved_list_in_this_repo_has_mc_and_test` (finding 13, Q3 answer A): OWN-CHANGE of 007a -> blob of `reserved-namespaces.json` at `aaf4260...`; consequence accepted by Ludwig (Q3): it no longer guards the live list.
  Left on HEAD, deliberately (LIVE, not in the finding table): 008a's section-2 heading checks of `docs/pipeline/build-pipeline.md` and `docs/validation/manifest-reader.md` (own-change-looking but not named in the umbrella; recorded as an observation for the manager, not changed: "only the checks named in the table"); 007a/007b/008a suite runs, CLI-help and hygiene greps, tool checks, mutation runners (LIVE properties).
  Static checks run (no script executed): `bash -n` on 007a/007b/008a/089a1-verify.sh = OK; `python3 -m unittest discover -s tests/registry -p test_hardening.py` -> `Ran 20 tests ... OK` (0.5 s); `-p test_classify.py` -> `Ran 19 tests ... OK` (0.007 s), both with PYTHONDONTWRITEBYTECODE=1. These two runs are the only test execution; they prove the edited tests pass on the plain worktree, nothing more.
  Also checked read-only (no script executed): the fixtures of 089a1-verify.sh build (`git clone` + synthetic branch + `--no-ff` merge works for all five later branches and both finding-4 pin variants); the five mutation needles occur exactly once in the fixed files; the "worktree README read" detector counts 2/2/1 in the OLD 007a/007b/008a and 0/0/0 in the fixed ones; the finding-2 detector matches README at 007a BASE (2 lines) and none at FINAL; the finding-4 old wording matches README at 007b BASE and not at FINAL.
