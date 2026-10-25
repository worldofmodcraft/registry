# Pipeline trigger: a merge to `main` starts the build pipeline

Contract for edge **E15** (`N2 -> N5`, registry-data (merge to main) to build-pipeline) in
`docs/architecture/depgraph.md` (platform repository). The graph has already settled the
*mechanism* (mission log Q4=A): the build pipeline is a workflow in this repository, started by a
same-repository `push` to `main`. This document does not re-open that choice. It states which
events may start the workflow, which runs may reach the signing key and the write-back identity,
which registry state a run reads and which versions it builds, how runs queue, why the
push, write-back, push chain ends, what the pipeline may assume about a merged entry, and what it
does for each exit code of 008a's build tool. Task 008b writes `.github/workflows/pipeline.yml`
from this document and its verify script checks the workflow against the normative block below.

## Scope: one edge, and not E12

This document governs the signal that tells the registry's own pipeline workflow "a merge may have
added a version, build it". It does not govern the cross-repository `repository_dispatch` that tells
the site to rebuild after a merge: that is edge **E12**, `contracts/rebuild-trigger.md`. The two
are unrelated mechanisms that both happen after a merge, and they must not be confused: E15 is a
same-repository `push` workflow that builds, E12 is a cross-repository dispatch that does not.

It does not govern the job split and secret handling inside the workflow (008b design 8; the
environment configuration itself is Ludwig's manual step M11), release and asset naming (E7,
`contracts/artifact-naming.md`), the shape of the transitions the pipeline writes back (E4,
`contracts/append-only.rules.md`), who may carry a T1 or T3 transition (the E16 carve-out in
`contracts/ownership.md`), the site dispatch (E12, task 055), or the command-line tools. How the
merged PR that appended a version is found, for the failure comment of PT10, is 008b's: if none is
found, no comment is posted, the T3 PR still opens, and the log says so.

## How to read this document: rule ids

Every requirement is a numbered rule, `PT1` to `PT12`, at the start of its own paragraph. Each rule
ends with a `Source:` line naming where its content was decided. Statements about GitHub's
behaviour that nobody has observed in this repository carry `[unverified]` and stand as the rule
regardless: the rule is what the pipeline does, the marker says the platform behaviour behind it
is not yet confirmed. `docs/tasks/082-verify.sh` pins every sentence of `PT1`-`PT12` by its full
text, so any edit to a sentence turns the check red until a human edits the pin.

## Rules

**PT1 Trigger set (closed).** The workflow's triggers are exactly two: `push` to `main`, filtered as
PT2 states, and `workflow_dispatch`. It never uses `pull_request`, `pull_request_target`,
`workflow_run`, `repository_dispatch`, `schedule` or any other event. Adding a trigger amends this
contract. The reason is that no secret may be reachable from a run triggered from a fork: GitHub
withholds repository secrets from runs triggered by a fork pull request `[unverified]`, and 008b
criterion 8 tests this live. A `workflow_dispatch` can be started only by an account with write
access to the registry `[unverified]`, and PT3 states which of its runs may reach a key.
Source: C17 (closed trigger list); 008b design 1; task 039 section 1.

**PT2 Path filter.** The `push` trigger carries `paths: ['mods/*/entry.json']`. A push that changes
only a `page.json`, or nothing under `mods/`, starts no run. The filter only saves cost, and
correctness never depends on it, because PT4 reads state and not the diff. In a GitHub path filter
`*` does not match `/` `[unverified]`, so the filter is meant to match
`mods/<namespace>.<name>/entry.json` and no deeper path. GitHub may run a path-filtered workflow
anyway when it cannot compute the diff `[unverified]`, and such a run is correct because of PT4 and
PT5.
Source: task 039 section 3; 008b design 1.

**PT3 Ref and key binding.** The signing and write-back jobs act only when `github.ref ==
'refs/heads/main'`, for both triggers. The ref condition protects only the unmodified workflow file:
a `workflow_dispatch` runs the workflow file of the ref selected at dispatch `[unverified]`, so a
modified file on another branch runs without the condition. The signing key is bound to `main` only
by a GitHub Actions environment named `signing` on the signing job, with deployment branches limited
to `main` and `MINISIGN_SECRET_KEY` stored as that environment's secret, and the App key is bound
only by an environment named `write-back` configured the same way for `PIPELINE_APP_PRIVATE_KEY`.
Ludwig's manual step M11 creates both environments and deletes the repo-level copies of both
secrets, because an environment copy protects nothing while a repo-level copy exists, and the
environment mechanics are `[unverified]`. Until M11 is done, the trust boundary of
`MINISIGN_SECRET_KEY` and `PIPELINE_APP_PRIVATE_KEY` is every account with write access to the
registry. The dry-run job references neither environment.
Source: C14 (which dispatches reach the key); C20 as extended in spec review round 2, N1 (both keys,
  repo-level copies deleted); 008b design 8 (follow-up booked).

**PT4 Input snapshot.** A run reads `mods/*/entry.json` at the head of `main` as fetched at plan
time, and logs that SHA. The commit range of the push payload, and the push's `github.sha`, are
never the authority for what to build. A run that starts after a later merge has landed therefore
sees the state that merge produced.
Source: C12 (input snapshot); 008b design 2.

**PT5 What a run processes.** A push run, and a `workflow_dispatch` run with an empty `version`
input, build every `pending` version on `main`. Versions that are `published`, `removed` or
`rejected` are never built. A fault or a refusal ends that version only: the run continues with the
remaining `pending` versions and fails at the end, naming each version that failed. A version that
keeps faulting with exit 2 is therefore retried by every push run and ends each of those runs red,
without blocking other versions. A `workflow_dispatch` with `version=<namespace>.<name>@<semver>`
builds only that version, and only if it is `pending`. Otherwise, or for a malformed id or an absent
entry, it refuses with planner exit 1 and writes nothing, and that refusal is not a 008a verdict.
The `version` input is validated against the entry-id and semver patterns before use, and it reaches
scripts only through `env:`, never by interpolation into a `run:` block (task 039's injection rule).
Zero `pending` versions is a success that writes nothing.
Source: C11 (scope of a push run); 008b design 2 and 9, criteria 12 and 17; task 039 injection rule.

**PT6 Concurrency.** The workflow declares `concurrency: { group: pipeline, cancel-in-progress:
false }`, and push runs and `workflow_dispatch` runs share that one group, so at most one run builds
at a time. GitHub keeps at most one waiting run per concurrency group and cancels an older waiting
run when a newer one arrives, and a waiting push run can be replaced by a waiting dispatch run
`[unverified]`. That is why PT4 and PT5 read state and not the diff, and why a `workflow_dispatch`
with an empty `version` plans all `pending` versions exactly as a push does, so a replaced waiting
run loses nothing. A run holds the `pipeline` group until each PR it opened has reached a terminal
state: merged, failed, closed unmerged, or deadline (PT11). The planner skips any `pending` version
that already has a `pipeline/<namespace>.<name>-<version>` branch, and the skip is not silent: it
makes the run's conclusion non-green, or raises an error annotation, naming the version.
Source: C13 (in-flight versions); C22 (terminal states); 008b design 3 and 9.

**PT7 Termination.** A push to `main` caused by the pipeline itself happens only when a write-back
PR (PT11) merges, and that PR is a T1 or a T3 transition. Each such transition moves exactly one
version out of `pending`, and a `pending` version leaves that state only this way (PT9). That a
merge made by the GitHub App identity fires a `push` run is `[unverified]` (008 finding F5; 008b
criterion 9). The log commit to `worldofmodcraft/archive` is in another repository and does not
trigger E15. N pending versions therefore cause at most N + 1 runs from pipeline-caused pushes, and
the run that finds zero `pending` versions ends having written nothing (PT5).
Source: 008b design 2 (zero pending stops the loop) and criterion 9; 008 finding F5; ADR-0121.

**PT8 Re-runs and idempotency.** If a published release with the tag already exists in
`worldofmodcraft/archive`, the run fails for that version with `artifact-naming.md`'s
never-overwrite rule (a pre-existing tag of this name is an error, never something to overwrite),
writes nothing else, and leaves the version `pending`; recovery is manual. If only a draft release
with the tag exists, it is deleted and recreated. A version that is no longer `pending` is never
rebuilt. The log commit is append-only per version: if `logs/<namespace>.<name>/<version>.log`
already exists in `worldofmodcraft/archive`, the run fails for that version naming the path,
overwrites nothing, and recovery is by hand. A version skipped under PT6 is recovered by closing its
PR, deleting its `pipeline/` branch and dispatching. A re-run of a workflow run uses the workflow
file of the original commit `[unverified]`, and its inputs are still the state PT4 reads, not the
original run's.
Source: 008b design 5 and criteria 6 and 18; `contracts/artifact-naming.md` (uniqueness rule, "What
  this document does not cover"); C13.

**PT9 What the pipeline may assume.** The pipeline may assume that the entry is on `main`, and that
its `pending` version's `version`, `commit` and `source_url` are frozen by the conditions of T1 and
T3 in `contracts/append-only.rules.md`. It may assume that only the pipeline identity can move a
version out of `pending`, through the pipeline carve-out that E16 adds to `contracts/ownership.md`;
until that carve-out merges, a checker implementing T1 or T3 rejects every PR containing one
(`append-only.rules.md`, "Coexistence of T1, T2 and T3"), so no T1 or T3 PR can merge. It may not
assume anything from `gate`: a PR passing `gate` (task 039; required only after M9) shows liveness
and not safety, and 008a re-validates everything. It may not assume the author's repository still
exists, because a failed clone is exit 2. An entry on `main` that fails the entry schema is a
pipeline fault: no build, no T3 transition, and the run fails naming the file.
Source: `contracts/append-only.rules.md` (T1, T3, Coexistence); `contracts/ownership.md` (E16
  carve-out); task 039 section 1; C15 (entry failing the schema); ADR-0121.

**PT10 Outcomes per 008a exit code.** The codes are those of 008a's `build_version.py`: 0 built, 1
rejected, 2 pipeline fault. Exit 0: the run opens one T1 write-back PR for that version. Exit 1: the
run commits the build log to `worldofmodcraft/archive` at `logs/<namespace>.<name>/<version>.log`,
the log commit precedes the T3 PR, and an existing log at that path fails that version (PT8). It
then comments the full `build.log` on the merged PR that appended the version, and opens one T3 PR
with a `reason` that is non-empty after trimming and a `build_log_url` that begins with `https://`.
It never blocks or reverts a merge and never deletes the version. Exit 2: that version's run fails,
with no comment, no T3 PR, no release and nothing written, and the version stays `pending` and is
retried by the next push or by a dispatch (PT5).
Source: 008b design 7; ADR-0121 decision Q-J; `contracts/append-only.rules.md` (T1, T3).

**PT11 Write-back PRs.** Write-back is one PR per version, and its diff is exactly one T1 or one T3
transition. It goes through `gate` like any PR, with no bypass and no lifted rule. It is opened with
the GitHub App identity (Q-D), never with `GITHUB_TOKEN`. PRs are opened and merged one at a time,
each branched from a `main` head fetched after the previous merge. The GitHub App merges each PR
once `gate` is green; task 039's "no auto-merge" means no auto-merge by the 039 workflow. If `gate`
is red, a PR is closed unmerged, or a PR is not merged within 30 minutes, the run fails and stops,
and the group is released. The remaining `pending` versions wait for the next push or for a
`workflow_dispatch` with an empty `version`. The signing and write-back job's `timeout-minutes` is
sized from the pending count (N x 30 minutes plus build time), or the per-PR steps carry their own
timeouts.
Source: C22 (write-back sequencing); 008b design 4, Forbidden and criterion 9; Q-D (App identity);
  task 039 Dependencies.

**PT12 Dry run.** A `workflow_dispatch` with `dry_run=true` writes only workflow artifacts: no
release, no branch, no PR, no archive commit and no comment. It never uses the production key: it
signs with an ephemeral key generated inside the run and discarded, and its artifacts say so. Its
source is only a `pending` version on `main`, or an input set that 008b names and this contract
reviews. The `version` input is validated and passed as PT5 states. Other dry-run inputs are 008b's.
Source: 008b criterion 10; C21 (dry runs never use the production key; 008b criterion 10 follow-up
  booked).

## Normative trigger block

This block is the contract's own text. `docs/tasks/082-verify.sh` compares it byte for byte. Task
008b's verify script compares it with `.github/workflows/pipeline.yml` on parsed keys, not bytes:
the `on` keys are exactly {`push`, `workflow_dispatch`} (the comparer handles PyYAML reading `on`
as `True`); `push` and `concurrency` equal the block's; the `workflow_dispatch` inputs are a
superset of {`dry_run`, `version`}. The input names are stated in PT5 and PT12 and not in the
block; 008b may add inputs and may not remove these two.

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

## Attack attempts against this contract

- **A fork PR adds a `pull_request` trigger to reach a secret.** Answer: PT1 closes the trigger
  list, and secret withholding for fork-triggered runs is `[unverified]`, so 008b criterion 8 tests
  it live (PT1, PT3).
- **Two merges land while a run is in progress, and the waiting run is cancelled or replaced by a
  dispatch run.** Answer: every run reads state, not the diff, and an empty-`version` dispatch
  plans all `pending` versions like a push (PT4, PT5, PT6).
- **A stale snapshot rebuilds a published version.** Answer: the snapshot is `main`'s head at plan
  time, only `pending` versions are built, and an existing tag is never overwritten (PT4, PT8).
- **A user with write access dispatches from a branch whose modified workflow removes the ref
  condition.** The ref condition does not stop this, because it lives in the modified file. Only the
  deployment-branch limits of the `signing` and `write-back` environments, with the repo-level
  copies deleted (C20, M11), keep both keys away from that run; a stolen App key would forge a T1
  PR's hash and signature as surely as a stolen signing key. Until M11 is done, every account with
  write access is inside the trust boundary of both keys (PT3).
- **A page-only push starves a pending version.** Liveness only: the next push that touches an
  `entry.json`, or a dispatch, plans it (PT5).
- **An author squats versions that never publish.** Cost only (ADR-0121 consequences); a version
  rejected by 008a leaves `pending` through PT10 exit 1.
- **One faulting version stalls the others.** Answer: PT5, a fault ends that version only.
- **A crafted `version` dispatch input injects into a script.** Answer: PT5, the input is
  validated and reaches scripts through `env:` only.
- **A dry run signs with the production key.** Answer: PT12, an ephemeral key only, and the dry-run
  job references neither environment (PT3).
- **A write-back PR is left open and holds the group indefinitely.** Answer: PT11, the 30-minute
  deadline and `timeout-minutes`.
- **A re-run overwrites an archive log.** Answer: PT8 and PT10, the log is append-only.

## What this document does not cover

- **The job split and secret handling inside the workflow** (008b design 8). The environment
  configuration itself is M11, Ludwig's manual step; this document states only what it must achieve
  (PT3).
- **Naming** of tags and assets: `contracts/artifact-naming.md` (E7).
- **The shape of the T1 and T3 transitions**: `contracts/append-only.rules.md` (E4).
- **Who may carry a T1 or T3 transition**: the E16 carve-out in `contracts/ownership.md`.
- **The site dispatch after a merge**: `contracts/rebuild-trigger.md` (E12), task 055.
- **The command-line tools** (`tools/pipeline/`) and the workflow file itself (008b).
- **How the merged PR that appended a version is found**, for the failure comment of PT10 (008b).

## Questions

- (none: every decision this contract needed was made before it was written, C11-C17 and C20-C22
  in the mission log.)
