# Task 008b-3a: Ownership carve-out for the pipeline identity

- **Mission:** SITE-V1, deliverable **D2** (umbrella `docs/tasks/008b-pipeline-workflow.md`, which keeps the decisions, design and history; design numbers below refer to it) — **Status:** spec-approved 2026-10-26 (manager, after independent spec review rounds 1-2 of the split; round-2 fixes mechanical). **Needs Ludwig's approval before merge: CI security check**
- **Agent / model:** implementer / sonnet
- **Budget:** small
- **Branch / worktree:** `task/008b3a-ownership-carve-out` / `~/wt/registry-task-008b3a` — **registry** repo
- **Sequence:** merges **before** 008b-3b. It needs only tasks 032 (merged), 057 and 007 (the ownership module), so it can run in parallel with 008b-1 and 008b-2. **Needs Ludwig's approval: CI security check** (the carve-out widens what the ownership gate accepts).

## Objective
`tools/registry/ownership.py` accepts the pipeline identity's numeric account id — and only that id — for a pull request whose entire diff is exactly one T1 (`pending -> published`) or exactly one T3 (`pending -> rejected`) transition, as `contracts/ownership.md` (E16, R11) specifies, and rejects it for everything else. Tests show both directions on hand-written fixture diffs taken from task 057's oracle (not built by 008c or by the pipeline), so this part has no dependence on the write-back code.

## Context to load (exhaustive; 7 items)
- `contracts/ownership.md` (R11 and the identity rule; `GITHUB_ACTOR*` forbidden as an identity source).
- `contracts/append-only.rules.md` (T1, T3, "Coexistence of T1, T2 and T3") and `entry.schema.json` as amended by task 057; task 057's oracle fixtures (`contracts/examples/entry/**` and the T1/T3 diff fixtures).
- Task 007's `tools/registry/ownership.py` and its tests (this task edits them).
- The umbrella `008b-pipeline-workflow.md` (criteria 4 and 5 text in this part; umbrella F4 on reading the App's id after M5; manual step M6).

## Size (5b)
Within every cap. Source files: 1 (`tools/registry/ownership.py`). Changed lines: about 60 (estimate; nothing built). Reading list: 7 items. Tests, fixtures and `008b3a-verify.sh` excluded.

## Design (taken from the umbrella; decisions are recorded there)
The carve-out identifies the pipeline identity by **numeric account id**, never by username or `GITHUB_ACTOR*` (ownership.md). The real id is the App's bot user id, read from the public API after Ludwig's M5 and recorded by the manager (umbrella F4); the tests use a fixture id, so this task can be built and merged before M5. Decision carried: Q-D (the organisation-owned GitHub App is the pipeline identity; Ludwig 2026-10-14). The App-PR flow itself (opening, merging) is 008b-3b's.

## File scope (declared; anything else = stop and report)
In the **registry** repo: `tools/registry/ownership.py` (the narrow carve-out only; the file is task 007's) and its tests and fixtures in `tests/registry/`; `docs/tasks/008b3a-ownership-carve-out.md` (log); `docs/tasks/008b3a-verify.sh` (new, executable). No edits to `contracts/` (E16 is merged), to `.github/`, to `tools/pipeline/`, or to any other module.

## Acceptance criteria
Criterion numbers are the umbrella's, kept so the mapping table there can be checked. [script] = checked by this part's verify script.

4. [script] **Ownership acceptance of the permitted diffs (umbrella criterion 4, ownership clause):** the fixture T1 diff and the fixture T3 diff from 057's oracle, authored by the pipeline identity's fixture id, are **accepted** by 007's ownership checker; the same diffs authored by a different id are **rejected**, each shown. (The clause that the diffs built by 008b-3b's code are accepted by the append-only and schema checkers is 008b-3b's criterion 4.)
5. [script] **The carve-out is narrow and tested both ways:** the ownership gate accepts the
   pipeline identity's id *only* for a PR whose changes are exactly the transition in criterion 4 and
   rejects it for: a first publish, a new version, a `page.json` edit, a takedown, a mixed T1 and T3 PR, a T3 whose `reason` is blank or whose `build_log_url` is not `https://`, any change under
   `contracts/` or `.github/`. The hostile fixture from task 007 (id differs, username matches) still
   rejects. Positive control: an owner's ordinary PR still accepts. [Needs Ludwig's approval: CI
   security check.]
13. [script] **Verification script.** `docs/tasks/008b3a-verify.sh` exists, is executable, covers criteria 4 and 5, is mutation-tested (widen the carve-out to a first publish; accept the id for a `page.json` edit; drop the `https://` check on `build_log_url`; accept a username instead of the id; each shown red then restored byte-identically), is run in a fresh clone, and its output is pasted in the log. Every check fails on zero matches.
18. **Docs move with code:** no `docs/pipeline` change (the carve-out is already specified by `contracts/ownership.md`); the log records the fixture id used and states that the real id is set after M5. (Umbrella criterion 18 is split by section; this part owns none.)

## Explicitly OUT of scope
The write-back job, releases, PRs and the T3 builder (008b-3b); the planner (008b-1); the workflow (008b-2, 008b-3b); changes to `contracts/ownership.md`.

## Forbidden here (beyond MANAGER.md §3.7)
- Any use of `GITHUB_ACTOR`/`GITHUB_ACTOR_ID` as the author identity.
- Weakening or skipping task 007's hostile fixtures (id differs, username matches) to make the carve-out pass; widening the carve-out beyond the transitions of criterion 5.
- Reading or printing the App's private key or any token; the App's bot id is read from the **public** API only (CLAUDE.md rule 11).

## Dependencies and sequencing
Tasks 032 (merged, registry PR #4), 057 and 007 merged. Parallel-safe with 008b-1 and 008b-2. Blocks 008b-3b. Ludwig's manual step **M6** (join the organisation with the personal account, so an organisation-member PR is accepted) is carried here; it matters to the positive control of criterion 5 only if run live. Graph: nodes N2, N3; edge E16 (author identity -> N3).

## Verification artefact (MANAGER.md §2c)
Declared: `docs/tasks/008b3a-verify.sh` for criteria 4, 5 and 13. There are no [live] criteria in this part.

## Deliverables
Carve-out + tests + fixtures + verify script + this file's log section current.

## Questions  (agent-maintained; see MANAGER.md 8b)
- (none open.)

---
# Task 008b-3a log  (append-only, updated continuously by the executing agent)
- 2026-10-26 split from 008b-3 at the review of the 008b split (manager ★, session 12); nothing started.
- 2026-11-06 manager (session 15): delta re-check against registry main `ab5fcba`: `tools/registry/ownership.py`, `contracts/ownership.md` and `tests/registry/test_ownership.py` last changed 2026-10-25 (task 075), before this spec was approved on 2026-10-26, so the spec stands. The "Needs Ludwig's approval: CI security check" line is lifted by ADR-0125 (merge of green CI security checks); the carve-out covers T1 and T3 only, so the takedown exception (ADR-0122, T2) is untouched and stays Ludwig's. Sequenced after 111b and 094 (one quiet-waiting agent at a time).
- 2026-11-07 manager (session 15): **umbrella F4 recorded.** The pipeline App's bot user, read from the public API (`gh api 'users/worldofmodcraft-pipeline[bot]'`, as `womcraft`; the unauthenticated limit was exhausted; no key or token read): `{"id":342916936,"login":"worldofmodcraft-pipeline[bot]","type":"Bot"}`. The App itself: `{"id":5327993,"slug":"worldofmodcraft-pipeline","owner":"worldofmodcraft"}`. The carve-out identifies the pipeline by the **bot user id 342916936**, never by login. Base for this task: registry main `e213cbc` (094 merged). Merge gate: whole sweep with `tools/dev/sweep.py` on the merge result (manager).
- 2026-11-07 implementer (session 15): **carve-out built** on registry main `e213cbc`. `tools/registry/ownership.py`: new keyword `pipeline_identity` (a `(provider, id)` pair, configuration like `r11_identity`; `None` = carve-out off) and `_pipeline_shape()`. The carve-out applies only when the author equals `pipeline_identity` AND the whole diff is one path, an existing `mods/<ns>.<name>/entry.json`, same element count, exactly one element changed and 007a's `append_only.check_entry` classifies it T1 or T3 with no finding anywhere (so id/owner freeze, blank `reason`, non-`https://` `build_log_url`, extra keys are all rejected through 007a). When it applies, the ADR-0121 fail-closed finding is skipped and R3/R7 do not apply to that PR; every other PR by that id is judged as for any stranger. The verdict gains `pipeline_carve_out` (bool). It never sets `authorised_takedown`; R11/T2 is untouched.
  - **Decision: a new keyword, not re-using `pipeline_app_id`.** Task 007's tests (`test_b1_matrix_every_cell...`, whose "pipeline app id" row passes `pipeline_app_id`, and `test_b1_pipeline_app_id_equal_to_r11_identity_still_cannot_carry_t1_or_t3`) assert T1/T3 are rejected when `pipeline_app_id` is given; giving that parameter authority would have forced weakening them. `pipeline_app_id` stays accepted and ignored; all 91 pre-existing tests in `test_ownership.py` pass unchanged. The caller (task 039's CI wiring or 008b-3b) must pass `pipeline_identity`; `.github/` and `ownership_cli.py` are out of scope here, so nothing passes it yet and the gate stays fully closed in CI until that wiring lands (for the manager to book).
  - **Fixture id used by the tests: `555111`** (`PIPE_ID`, provider `github`). **The real id is set after M5**: umbrella F4 (entry above) recorded the App's bot user id `342916936`; it is configuration for the caller and is deliberately not written into `tools/registry/` (`008b3a-verify.sh` asserts it does not appear there).
  - T1/T3 fixtures come from task 057's oracle (`docs/tasks/057-transition-fixtures.json`, read at test time, not copied): `t1-exact` and `t3-exact` accepted for the pipeline id and rejected for any other; `t3-whitespace-only-reason`, `t3-build-log-url-http`, `t1-and-t3-different-elements`, `t1-plus-owner-change` and others rejected for it.
  - New tests: class `PipelineCarveOut` in `tests/registry/test_ownership.py` (17 tests).
- 2026-11-07 implementer (session 15): **verification done; branch pushed, no PR, nothing merged.** Commits: `dbbd983` (carve-out + tests + spec/log), `827c562` (TIP: adds the reserved-namespace first-publish case to the tests after mutation m1 first stayed green, see below), then the verify script.
  - **Red first** (new tests run against the unmodified `ownership.py` of `e213cbc`, before the code existed): `Ran 108 tests ... FAILED (errors=40)`; every error is `TypeError: check() got an unexpected keyword argument 'pipeline_identity'`, in `test_ownership.PipelineCarveOut` only (the 91 pre-existing tests were OK). With the carve-out: `Ran 108 tests ... OK`. Whole `tests/registry` suite at the branch tip: `Ran 431 tests ... OK`. The honest reading of the red run: it proves the new tests need the new API, not that the rejecting tests bite; the biting is shown by the mutations below.
  - **Mutation finding:** the first version of m1 (widen to a first publish) stayed green, because a first publish by the pipeline id is still caught by R4/R5/R6 (login-based) and by R3, which the carve-out does not skip. The carve-out does skip R7 membership, so the case that matters is a first publish into a reserved namespace (`mc`); that case was added to `test_e16_reject_a_first_publish` and m1 is now red.
  - **Mutation m3 lands in `tools/registry/append_only.py`** (task 007a's T3 `build_log_url` check) in a scratch clone only: the ownership gate deliberately has no second copy of the T3 field rules, it relies on 007a's `check_entry` finding nothing. If 007a's https check is dropped, the gate widens; the mutation shows the test notices.
  - `docs/tasks/008b3a-verify.sh` in a fresh clone of the pushed branch (`git clone https://github.com/worldofmodcraft/registry`, branch `task/008b3a-ownership-carve-out`, head `bd203e0`): default `ALL CHECKS PASSED (0 failures)`, exit 0; `--mutate` also `ALL CHECKS PASSED (0 failures)`, exit 0, 40 PASS lines. Mutations: m1 widen to first publish red (`test_e16_reject_a_first_publish`), m2 accept the id for a `page.json` edit red (`test_e16_reject_a_page_json_edit`), m3 drop the https check on `build_log_url` red (`test_e16_reject_a_t3_with_a_blank_reason_or_a_non_https_build_log`), m4 accept a username instead of the id red (`test_e16_reject_hostile_login_matches_but_id_differs`), m5 accept two transitions red (`test_e16_reject_a_mixed_t1_and_t3_pr`); each restored byte-identically (sha256 equal) and green after restore.
  - Not done / for the manager: nothing passes `pipeline_identity` yet (`ownership_cli.py` and `.github/` are out of this task's scope), so CI keeps rejecting T1/T3 until 008b-3b (or a task for 039's wiring) passes `("github", 342916936)`. Closed verify scripts that read `ownership.py` or its tests: 007b and 075 (by name), 071 (matches `tools/registry/ownership` without `.py`), others only mention the contract text. 007b's floor of 75 ownership tests and 075's file-scope lists are not affected by an additive change; they were not run.
