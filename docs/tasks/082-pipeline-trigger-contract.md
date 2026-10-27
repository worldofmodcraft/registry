# Task 082: The pipeline-trigger contract (E15) — `contracts/pipeline-trigger.md`

- **Mission:** SITE-V1, deliverable **D2** (unblocks 008b; umbrella `docs/tasks/008-build-pipeline.md` finding F2) —
  **Status:** spec-approved (manager, 2026-10-25 night; drafted by a Plan agent; Q1-Q7 decided under Ludwig's standing ★ approval as
  C11-C17; spec review round 1 FAIL, folded in, C20-C22 decided by the manager; round 2 FAIL on N1 (both keys), fixed by the manager; **spec-approved**). Decides when the signing
  key can be reached → **independent spec review before dispatch.**
- **Merge:** needs **Ludwig's written approval** (adds a contract, ADR-0117; fixes which runs reach `MINISIGN_SECRET_KEY`,
  MANAGER.md §7). The standing ★ approval does not cover this merge. Ludwig's manual step **M11** (C20) is separate and
  booked in the runbook.
- **Repo:** registry. This file lives in platform `docs/tasks/` and is copied to the registry branch's `docs/tasks/` as the log
  (as 057 did).
- **Agent / model:** doc-writer / sonnet — the deliverable is prose recording decisions already made (008b design 1-9,
  ADR-0121, 039 §3, C11-C17, C20-C22); precedent 032 (E16 contract) was doc-writer; the verify artefact is contract-text checks
  only.
- **Budget:** 3 agent-sessions (rule set grew to cover the signing-key boundary, dry runs and write-back sequencing).
- **Branch / worktree:** `task/082-pipeline-trigger-contract` / `~/wt/registry-task-082`, cut from registry `origin/main` (actual
  cut SHA = `BASE` in the log and `082-verify.sh`).
- **Graph:** edge **E15** (`N2 (merge to main) → N5`); nodes N2 `registry-data`, N5 `build-pipeline`. `depgraph.md` already
  names `contracts/pipeline-trigger.md` for E15 (`depgraph.json` `"status": "to-write"`). No graph amendment needed first.

## Objective
`contracts/pipeline-trigger.md` exists on registry `main`; 008b's workflow can be written from it and checked against it. It
states, as numbered rules each naming its source: the exact trigger set and path filter; which ref may reach the signing and
write-back steps and what actually binds the signing key to `main` (the `signing` environment, C20); which registry state a run
reads and which versions it builds (pending only); the concurrency rule (two merges in a row; re-runs; head-of-line); why the
push → write-back → push chain ends; what the pipeline may and may not assume about a merged entry; the outcome for each of
008a's exit codes including the T3 `pending → rejected` write-back; the dry-run key rule; and one normative YAML block that
008b's verify script compares, on parsed keys, against `.github/workflows/pipeline.yml`. `docs/contracts/README.md` lists the
file as the E15 contract. Every rule sentence is pinned by `docs/tasks/082-verify.sh`.

## Context to load (reading list, 11)
Justification: each entry is the source of at least one rule PT1-PT12 or is the style model; none is optional. INDEX.json
lookup: by the manager before approval.
1. Platform `docs/tasks/008b-pipeline-workflow.md`: Objective, Environmental facts, Design 1-9, criteria 1, 6, 9, 10, 12, 17, 18.
2. Platform `docs/tasks/008-build-pipeline.md`: F2, F5, Decisions Q-B, Q-D, Q-J.
3. Platform `docs/decisions/0121-version-lifecycle-pending.md` (Decision, Q-J, Consequences).
4. Platform `docs/architecture/depgraph.md`, row E15 and the Q4=A rationale.
5. Platform `docs/tasks/039-registry-ci-workflow.md` (revised): §1 trust model, §3, Dependencies.
6. Registry `contracts/rebuild-trigger.md` (E12): the style model.
7. Registry `contracts/append-only.rules.md`: T1, T3, "Coexistence" only.
8. Registry `contracts/ownership.md`: header, "How to read this document: rule ids", fail-closed status of T1/T3.
9. Registry `contracts/artifact-naming.md`: "never overwrite an existing tag", "What this document does not cover".
10. Registry `docs/contracts/README.md`.
11. Platform `docs/manager/OPERATIONS.md` ("Consequences of branch protection that bite later").

ADRs cited (ADR-0116 layer 2): 0041, 0058 §1 (as amended), 0117, 0121. None is edited.

## Decisions (C11-C17, C20-C22, mission log; reversible there)
- **Q1 (C11) scope of a push run:** every `pending` version on `main` (008b design 9: "Pushes to `main` still plan all pending
  versions"; survives cancelled waiting runs). Cost accepted: a version that keeps faulting with exit 2 is retried on every push
  and ends that run red, naming it; it does not block other versions (PT5). A `workflow_dispatch` with an empty `version` plans
  all pending versions like a push, so a waiting push run replaced by a waiting dispatch run loses nothing (PT6).
- **Q2 (C12) input snapshot:** `main`'s head fetched at plan time, SHA logged (not the push's `github.sha`).
- **Q3 (C13) in-flight versions:** a run holds the `pipeline` group until each PR it opened has reached a terminal state:
  **merged / failed / closed unmerged / deadline** (C22). The planner skips any pending version with an existing
  `pipeline/<ns>.<name>-<version>` branch, and the skip is not silent: it makes the run conclusion non-green (or raises an error
  annotation) naming the version. Recovery is manual: close the PR, delete the `pipeline/` branch, dispatch (PT8).
- **Q4 (C14) which dispatches reach the key:** signing and write-back jobs run only when `github.ref == 'refs/heads/main'`; 008b's
  Objective wording is corrected to "on `push` to `main`, or a `workflow_dispatch` on `main` by an account with write access
  [unverified]; never from a fork". The ref condition alone is not the binding; see C20.
- **Q5 (C15) an entry on `main` failing the entry schema:** a pipeline fault — no build, no T3, the run fails naming the file.
- **Q6 (C16) checking:** text checks now (this task); the workflow comparison lives in 008b-verify against the normative block.
- **Q7 (C17) trigger list:** closed — exactly `push` and `workflow_dispatch`.
- **C20 (manager, 2026-10-25) key binding:** the signing key is bound to `main` by a GitHub Actions **environment** named
  `signing` on the signing job, deployment branches limited to `main`, the key stored as that environment's secret. Ludwig's
  manual step, booked as runbook **M11** [unverified mechanics]. The ref condition (C14) protects only the unmodified workflow
  file. **Extended (review round 2, N1):** the `signing` environment holds `MINISIGN_SECRET_KEY` and a `write-back` environment
  holds `PIPELINE_APP_PRIVATE_KEY`, each limited to deployment branch `main`; **M11 deletes the repo-level copies of both
  secrets** (an environment copy protects nothing while a repo-level copy exists). Until M11 is done, the trust boundary of both
  keys is every account with write access to the registry. The dry-run job references neither environment.
  008b design 8 follow-up booked.
- **C21 (manager, 2026-10-25) dry runs never use the production key:** a `dry_run=true` run signs with an ephemeral key generated
  inside the run and discarded; its artifacts say so. Amends 008b criterion 10 (booked follow-up). The dry run's source is only a
  `pending` version on `main` or an input set that 008b names and this contract reviews.
- **C22 (manager, 2026-10-25) write-back sequencing:** write-back PRs are opened and merged one at a time, each branched from a
  `main` head fetched after the previous merge. The GitHub App merges each once `gate` is green (008b design 4; 039's "no
  auto-merge" means no auto-merge by the 039 workflow). A PR closed unmerged, or not merged within 30 minutes, fails the run and
  releases the group. The signing/write-back job has `timeout-minutes`. C13's terminal states are: merged / failed / closed
  unmerged / deadline.

## Approach (the contract's outline; everything is decided — quote sources, do not re-argue)
House header: "Contract for edge **E15** (`N2 -> N5`, registry-data (merge to main) to build-pipeline) in
`docs/architecture/depgraph.md`…". Scope separates E15 (same-repository `push` workflow that builds) from E12 (cross-repository
`repository_dispatch` to the site). Rule ids `PT1`-`PT12`; each starts its own paragraph and ends with a `Source:` line.
- **PT1 Trigger set (closed).** Exactly `push` to `main` with the PT2 filter, and `workflow_dispatch`. Never `pull_request`,
  `pull_request_target`, `workflow_run`, `repository_dispatch`, `schedule` or any other event. Adding a trigger amends this
  contract. Reason: secrets never reachable from a fork-triggered run.
- **PT2 Path filter.** `paths: ['mods/*/entry.json']`; a push changing only `page.json`, or nothing under `mods/`, starts no run
  (039 §3). The filter only saves cost; correctness never depends on it (PT4 reads state, not the diff). `[unverified]`: `*`
  does not match `/`; GitHub may run a path-filtered workflow anyway when it cannot compute the diff.
- **PT3 Ref and key binding.** Signing and write-back jobs act only when `github.ref == 'refs/heads/main'`, for both triggers
  (C14). The ref condition protects only the unmodified file; the key is bound to `main` only by the `signing` environment
  (C20) and the App key only by the `write-back` environment; M11 deletes both repo-level copies. Until M11 is done, the trust
  boundary of `MINISIGN_SECRET_KEY` and `PIPELINE_APP_PRIVATE_KEY` is every account with write access to the registry. The dry-run
  job references neither environment.
  `[unverified]`: a `workflow_dispatch` runs the workflow file of the ref selected at dispatch, so a modified file on another
  branch runs without the condition; the environment's deployment-branch limit is what stops it from reaching the key.
- **PT4 Input snapshot.** The run reads `mods/*/entry.json` at `main`'s head fetched at plan time and logs that SHA; the push
  payload's range is never the authority (008b design 2).
- **PT5 What a run processes.** A push run, and a dispatch with an empty `version`, build every `pending` version on `main`;
  `published`, `removed`, `rejected` are never built. A fault or refusal ends that version only; the run continues with the
  remaining pending versions and fails at the end, naming each. A dispatch with `version=<namespace>.<name>@<semver>` builds
  only that version, only if `pending`; otherwise (or a malformed id, or an absent entry) it refuses with planner exit 1 and
  writes nothing — not a 008a verdict (008b design 9, criterion 17). The `version` input is validated against the entry-id and
  semver patterns before use and reaches scripts only via `env:` (039's injection rule). Zero pending versions → success,
  nothing written (008b design 2, criterion 12).
- **PT6 Concurrency.** `concurrency: { group: pipeline, cancel-in-progress: false }`, shared by push and dispatch runs; at most
  one run builds at a time. GitHub's waiting-run replacement (a group keeps at most one waiting run; a newer one cancels it) is
  stated `[unverified]`, including that a waiting push run can be replaced by a waiting dispatch run; the consequence is why
  PT4/PT5 read state and why an empty-`version` dispatch plans all pending versions like a push. In-flight rule per C13.
- **PT7 Termination.** A pipeline-caused push to `main` happens only when a T1 or T3 PR merges; each moves exactly one version
  out of `pending`, and a pending version leaves that state only this way (PT9). That a merge by the GitHub App identity fires
  `push` is `[unverified]` (008 F5; 008b criterion 9). The archive-repo log commit is in another repository and does not trigger
  E15. N pending versions → at most N + 1 runs from pipeline-caused pushes.
- **PT8 Re-runs and idempotency.** A published release with the tag exists → fail with `artifact-naming.md`'s never-overwrite
  wording, nothing else written, the version stays `pending` (manual recovery, `docs/pipeline/build-pipeline.md`; 008b design 5,
  criteria 6, 18). A draft release exists → delete and recreate. A version no longer `pending` is never rebuilt. The log commit
  is append-only per version: if `logs/<namespace>.<name>/<version>.log` already exists in `worldofmodcraft/archive`, the run
  fails for that version naming the path, nothing is overwritten, and recovery is by hand. A version skipped under C13 is
  recovered by closing its PR, deleting its `pipeline/` branch and dispatching. A re-run of a workflow run uses the workflow file
  of the original commit `[unverified]`; its inputs are still PT4's state, not the original run's.
- **PT9 What the pipeline may assume.** The entry is on `main`; its pending version's `version`, `commit`, `source_url` are frozen
  (T1/T3 conditions); only the pipeline identity can move it out of `pending` (the E16 ownership carve-out, fail-closed until
  then — so until that merges no T1/T3 PR can merge); passing `gate` (039; required only after M9) gives liveness, not safety —
  008a re-validates everything; nothing about the author's repository still existing (a failed clone is exit 2); an entry
  failing the schema → C15.
- **PT10 Outcomes per 008a exit code** (008b design 7; ADR-0121 Q-J). **0:** one T1 PR. **1:** commit the build log to
  `worldofmodcraft/archive` at `logs/<namespace>.<name>/<version>.log` (PT8: append-only; an existing log fails that version);
  the log commit precedes the T3 PR; comment the full `build.log` on the merged PR that appended the version; open one T3 PR
  with `reason` (non-empty after trimming) and `build_log_url` (`https://`); never block or revert a merge, never delete the
  version. **2:** that version's run fails — no comment, no T3 PR, no release, nothing written; the version stays `pending` and
  is retried by the next push or by dispatch (PT5).
- **PT11 Write-back PRs.** One PR per version; its diff is exactly one T1 or one T3 transition (008b design 4); it goes through
  `gate` like any PR, no bypass, no lifted rule; opened with the GitHub App identity (Q-D), never `GITHUB_TOKEN`. PRs are opened
  and merged one at a time, each branched from a `main` head fetched after the previous merge; the GitHub App merges each once
  `gate` is green (C22). `gate` red, a PR closed unmerged, or a PR not merged within 30 minutes → the run fails and stops, and
  the group is released (008b Forbidden; criterion 9). Remaining pending versions wait for the next push or an empty-`version`
  dispatch. The signing/write-back job's `timeout-minutes` is sized from the pending count (N × 30 minutes plus build time), or
  the per-PR steps carry their own timeouts.
- **PT12 Dry run.** `workflow_dispatch` with `dry_run=true` writes only workflow artifacts — no release, branch, PR, archive
  commit or comment (criterion 10). It never uses the production key: it signs with an ephemeral key generated inside the run
  and discarded, and its artifacts say so (C21). Its source is only a `pending` version on `main` or an input set 008b names and
  this contract reviews. The `version` input is validated and passed as in PT5. Other dry-run inputs are 008b's.

**Normative block** — exactly one fenced `yaml` block under the heading "Normative trigger block", byte-exact, checked by AC3:
```yaml
on:
  push:
    branches: [main]
    paths: ['mods/*/entry.json']
  workflow_dispatch:
concurrency:
  group: pipeline
  cancel-in-progress: false
```
The block is the contract's own text and AC3 compares it byte for byte. 008b's comparison with `pipeline.yml` (008b criterion 1) is
on parsed keys, not bytes: the `on` keys are exactly {`push`, `workflow_dispatch`} (the comparer handles PyYAML reading `on` as
`True`); `push` and `concurrency` are equal to the block's; the dispatch inputs are a superset of {`dry_run`, `version`}. Input
names are named in PT5/PT12 prose, not in the block; 008b may add inputs, not remove these two.

**Attack attempts** (house style, each answered by a rule): a fork PR adds a `pull_request` trigger (`[unverified]` secret
withholding; 008b criterion 8 tests live; PT1, PT3); two merges land while a run is in progress and the waiting run is
cancelled or replaced by a dispatch run (PT4, PT5, PT6); a stale snapshot rebuilds a published version (PT4, PT8); a
write-access user dispatches from a branch with a modified workflow that removes the ref condition — the ref condition does not
stop this, since it lives in the modified file; only the `signing` and `write-back` environments' deployment-branch limits, with
the repo-level copies deleted (C20, M11), keep both keys away from that run (a stolen App key would forge a T1 PR's hash and
signature as surely as a stolen signing key); until M11 is done every account with write access is inside both keys' trust boundary
(PT3); a page-only push starves a pending version (liveness only; PT5); an author squats versions that never build (cost only;
ADR-0121 Consequences; PT10 code 1); one faulting version stalls the others (PT5: it ends that version only); a crafted `version`
dispatch input injects into a script (PT5: validated, `env:` only); a dry run signs with the production key (PT12: ephemeral key
only); a write-back PR is left open and holds the group indefinitely (PT11: 30-minute deadline, `timeout-minutes`); a re-run
overwrites an archive log (PT8, PT10: append-only).

**Not covered:** job split and secret handling (008b design 8; the environment configuration itself is M11, Ludwig's); naming
(E7); transition shapes (E4); who may carry T1/T3 (E16 carve-out); the site dispatch (E12, task 055); the CLIs; how the merged PR
that appended a version is found (008b — if none is found: no comment, the T3 PR still opens, the log says so).

## Acceptance criteria → `docs/tasks/082-verify.sh` (the log pastes its output)
Deterministic, offline, stdlib; exit code = number of failures; anything needing the platform checkout is ADVISORY.
1. **Exists, header right:** the file exists at `FINAL`; its first paragraph names `E15`, `N2 -> N5`, `docs/architecture/depgraph.md`.
   Control: absent at `BASE` → red.
2. **Rule ids:** `PT1`-`PT12` each start exactly one paragraph; no other `PT<n>`; each has a `Source:` line.
3. **Normative block:** exactly one block after "Normative trigger block", byte-identical to the script's literal. Mutations red:
   `paths` → `mods/**`; `cancel-in-progress: true`; `pull_request:` added; group renamed.
4. **Forbidden triggers:** PT1 names the closed list and the forbidden names; mutation: delete that sentence → red.
5. **Pending only and no-op:** PT5 has "`pending`", the fault-ends-that-version-only sentence, the zero-pending sentence, the
   dispatch-refusal sentence ("planner exit 1", "not a 008a verdict"), the `env:` sentence; PT7 the termination argument.
   Mutations (drop "pending"; delete zero-pending) → red.
6. **Failure semantics:** PT10 names exit codes 0, 1, 2 with the outcomes above incl. `reason`, `build_log_url`, `https://`,
   "stays `pending`", the log-commit-precedes-T3-PR sentence and the append-only/existing-log sentence. Mutation: exit 2 opens a
   T3 PR → red.
7. **Full-sentence pins:** every sentence of PT1-PT12 pinned by its full text (032 round-6 lesson); a tail-append mutation (one
   permissive sentence added to PT3) → red. Named mutations, each red: PT3 widen the ref (e.g. `refs/heads/main` →
   `refs/heads/*`, or drop the `signing`-environment/write-access sentences; drop the `write-back` environment or the "repo-level copies deleted"
   sentence); PT11 allow `GITHUB_TOKEN`; PT12 dry run uses the
   production key. Each AC3-AC7 mutation red then restored byte-identically; positive control passes.
8. **Index:** `docs/contracts/README.md` has a row for `contracts/pipeline-trigger.md` naming E15; its "does not exist yet" bullet
   is gone (grep 0 at `FINAL`, ≥ 1 at `BASE`).
9. **No other contract changes:** `git diff --name-only BASE FINAL -- contracts/` lists only the new file.
10. **Pinned own-change scope** (REVIEW-CHECKLIST item 12): `BASE`/`FINAL` recorded; diff inside the file scope; control
    `FINAL=BASE` → exit ≥ 1.
11. **Unverified markers:** the nine GitHub-behaviour statements each carry `[unverified]` or a command: fork secret withholding;
    waiting-run replacement (incl. a push run replaced by a dispatch run); `*` vs `/`; diff fallback; who may dispatch; a
    dispatch runs the selected ref's workflow file; a merge by the App-token identity fires `push` (008 F5, 008b criterion 9); a
    re-run reuses the original commit's workflow file; the environment mechanics of C20/M11.
12. **ADVISORY:** with `--platform DIR`, prints 008b design 1 and 3 next to the normative block.
13. **Fresh clone** (item 8) and every closed verify script green on HEAD, one at a time. Needs the network (clone); offline
    runs report this criterion as not run, not green.

## File scope
Registry: `contracts/pipeline-trigger.md` (new); `docs/contracts/README.md` (one row, the "not here" bullet, the intro count);
`docs/tasks/082-pipeline-trigger-contract.md` (log); `docs/tasks/082-verify.sh` (new). Platform: this spec file only.

## Size
0 source files; reading list 11; contract ~170-280 lines of prose.

## Forbidden (beyond MANAGER.md §3.7)
Changing anything 008b, ADR-0121 or 039 decided; deciding anything beyond C11-C17 and C20-C22 by assumption (stop and ask);
editing `rebuild-trigger.md` (its E15 wording slip is booked), `ownership.md`, `append-only.rules.md`, `artifact-naming.md`,
`entry.schema.json`; writing or sketching `pipeline.yml` or any tool (008b); GitHub behaviour without a command or
`[unverified]`; presenting `gate` as a safety precondition; any credential use (rule 11; unauthenticated docs reads allowed).

## Dependencies / sequencing
Upstream: none blocking (057 merged `e009ef0`, ADR-0121 accepted, E15 row exists). If 039's §1/§3 change in review, re-check
PT2, PT9, PT11 before merge. File overlap: the E16 carve-out task and the `artifact-naming.md` URL amendment also edit
`docs/contracts/README.md` — sequence the three. Downstream: 008b approval; 008b criterion 1 amended by the manager to compare
the normative block with `pipeline.yml` on parsed keys (PT block paragraph), not bytes. Follow-ups booked by the manager:
- platform `depgraph.json` E15 status; `system-overview.md` E15 row and State item 2; the `rebuild-trigger.md` wording slip;
- 008b Objective wording (PT3);
- 008b design 2's first sentence ("the workflow diffs the pushed range…") contradicts PT4 (state at `main`'s head, not the range);
- 008b design 8: the `signing` environment on the signing job (C20); runbook **M11**, Ludwig's manual step [unverified mechanics];
- 008b criterion 10: dry runs sign with an ephemeral key, never the production key (C21);
- 008b design 4: one-at-a-time write-back PRs, App merges once `gate` is green, 30-minute deadline, `timeout-minutes` (C22);
  039's "no auto-merge" clarified as "by the 039 workflow".

---
# Task 082 log
- 2026-10-25 manager (session 11 night): spec drafted by a Plan agent from 008, 008b, ADR-0121, depgraph E15 and 039 (revised).
  Findings: `docs/contracts/README.md` says E15's contract "does not exist yet"; `rebuild-trigger.md` calls E15
  "`repository_dispatch`-shaped" then says it is not (booked); 008b's Objective conflicts with its signing dispatch runs (C14);
  GitHub's waiting-run replacement [unverified] makes range-only planning lossy (C11). Q1-Q7 decided as C11-C17. Awaiting
  independent spec review. Merge needs Ludwig.
- 2026-10-25 manager: spec review round 1 FAIL (4 HIGH, 3 MED, 2 LOW); folded in; C20-C22 decided; round 2 pending.
- 2026-10-25 manager: spec review round 2 FAIL on N1 (HIGH: the App key needs the same binding; repo-level copies must be deleted), N2/N3 LOW — all three fixed by the manager (C20 extended). **spec-approved** (manager, 2026-10-25 night).
- 2026-10-25 doc-writer (opus 5.5, session 11c): executed. Worktree `~/wt/registry-task-082`, branch `task/082-pipeline-trigger-contract`,
  cut from registry `origin/main`; **BASE = `4356583fb2360592a680f40bee396f9f23df35a4`** (merge of PR #18, task 075).
  **FINAL = `afa48f20756c2fca793a0732cf7834e924663c3b`** (contract + README row + this log's spec copy); the verify script is
  the next commit (`405695a`), this log entry the one after it.
  - Delivered: `contracts/pipeline-trigger.md` (236 lines: house header, scope vs E12, rule-id explainer, PT1-PT12 each ending
    in a `Source:` line, the normative trigger block, attack attempts, not-covered, questions); `docs/contracts/README.md` (E15
    row in the file table, the intro now says four tasks / twelfth contract, the prose-document count is nine, the "does not
    exist yet" bullet is gone); `docs/tasks/082-verify.sh`. Nothing else in the registry was touched.
  - `082-verify.sh` (no flags), run 2026-10-25 on the committed state: exit **0**, 58 PASS, 0 FAIL. It covers AC1-AC11:
    BASE/FINAL pins and ancestry, scope (`git diff --name-only BASE FINAL -- contracts/` = only the new file), control
    FINAL=BASE red, file absent at BASE, header, rule ids, the normative block byte-compared with the script's literal,
    every sentence of PT1-PT12 plus heading and Source line pinned by full text (a paragraph must equal the pinned pieces
    joined, so a tail append is red), the nine `[unverified]` statements, the README row and bullet (control: bullet present at
    BASE). 26 mutations, each applied to a copy of the FINAL blob, shown red, the copy restored from the blob and shown
    sha256-identical and green: block `paths` -> `mods/**`, `cancel-in-progress: true`, `pull_request:` added, group renamed;
    PT1 closed-list sentence deleted; PT5 "pending" dropped, zero-pending deleted, fault-ends-that-version deleted, `env:`
    clause dropped; PT7 termination sentence deleted; PT10 exit 2 opens a T3 PR, log commit after the T3 PR; PT3 tail-append,
    `refs/heads/*`, write-access sentence dropped, `signing` environment dropped, `write-back` environment dropped, "repo-level
    copies deleted" dropped; PT11 `GITHUB_TOKEN` allowed, 30-minute deadline dropped; PT12 production key; PT6
    `cancel-in-progress` edited; PT7 `[unverified]` dropped; a `PT13` id added; README bullet re-added and README row deleted.
    Every one was red on the check named for it.
  - AC12 (advisory): `--platform /home/ludwig/wt/session-11c` prints the normative block next to 008b design 1 and 3.
  - Spec points the executor met and resolved without deciding anything (reported to the manager):
    1. PT8's source line in the spec cites `docs/pipeline/build-pipeline.md` for "manual recovery". That file has no recovery
       text (grep for re-run, retry, recover, already, exists finds nothing relevant), so the contract says "recovery is manual" and
       "by hand" and does not cite that file. 008b is where the recovery procedure gets written.
    2. PT7 as specified says "N pending versions -> at most N + 1 runs from pipeline-caused pushes". The tight bound is N runs
       from pipeline-caused pushes (N + 1 counting the author's own merge). The spec's number is a valid upper bound, so it is
       kept verbatim; the manager may want to tighten it.
    3. PT9 cites "fail-closed" from `append-only.rules.md` "Coexistence" rather than `ownership.md`, because `ownership.md`
       itself does not state the T1/T3 fail-closed default (the 007b checker does).
    4. The spec's "Size" says ~170-280 lines; the contract is 236 lines.
  - **AC13 NOT RUN.** The rule is one closed verify script at a time, and for about 70 minutes (23:20-00:30 CET) other agents'
    verify scripts (065, 064, 070, 069, 062, 067, 039a, 008a) were running without a quiet moment, so `docs/tasks/082-verify.sh
    --full` (fresh clone of HEAD, every other `*-verify.sh` one at a time) was not started. It is not claimed green. Run it
    before merge when the machine is quiet: `PYTHONDONTWRITEBYTECODE=1 bash docs/tasks/082-verify.sh --full`.
- 2026-10-26 doc-writer (opus 5.5): review of PR #20 found two blocking points in the verify script; fixed. (1) AC10.head diffed
  BASE..HEAD; it is now AC10.tip, BASE..TIP with the pinned `TIP=2e521ee227606c59cd30121c87eb4ae525b0fe5c`, inside the file scope; no own-change check uses HEAD
  or origin/main (only AC13's `--full` clones HEAD, which is not an own-change check). (2) New AC10.bytes: `git diff FINAL TIP --
  contracts/pipeline-trigger.md docs/contracts/README.md` is empty, so the merged bytes equal the verified bytes. (3) AC2 now also
  fails on any paragraph in the Rules section that does not start with a PT rule id (an unnumbered "Exception:" paragraph).
  Mutations red then restored green: out-of-scope file committed on top of TIP, post-FINAL edit of the contract, post-FINAL edit of
  the README (all three as commits in a throw-away clone made by the script), and an inserted unnumbered paragraph after PT3.
  **TIP = `2e521ee227606c59cd30121c87eb4ae525b0fe5c` is the last content commit.** The commits after it touch only `docs/tasks/082-verify.sh` (the TIP constant) and
  this log: that TIP-recording commit and anything after it. Commit chain: `afa48f2` (FINAL, contract+README), `405695a` script,
  two log commits, `2e521ee227606c59cd30121c87eb4ae525b0fe5c` (TIP, script fix), then the TIP-recording commit. AC13 stays NOT RUN (see above).
