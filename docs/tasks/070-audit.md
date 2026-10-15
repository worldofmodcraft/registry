# Task 070 audit: every git-diff / file-scope / size / "unchanged" check in the ten closed verify scripts

Rule applied (spec Objective 1): a check that is meant to describe *that task's own change* must measure the task's pinned PR
range `BASE..FINAL` (`FINAL` = `<merge commit>^2`, `BASE` = `git merge-base <merge>^1 <merge>^2`), never `HEAD` or the working
tree. A check that is meant to hold on the live tree stays live. Line numbers are the final state on this branch.

Verdicts: **already pinned** (own-change, measured over the pinned range before this task), **RE-PIN** (own-change, measured
against `HEAD` before this task; changed here), **LIVE** (property of the tree as it stands; stays).

## Re-pinned in this task

| Script:line | What it compares | Verdict | Reason |
|---|---|---|---|
| 067-verify.sh:69 (AC2.1, AC2.2, AC2.3) | `git diff -U0 "$BASE" "$FINAL" -- docs/tasks/032-verify.sh` (was `"$BASE" HEAD`) | RE-PIN | "Only N5b's pattern changed" is a claim about 067's own change. Any later task that edits `032-verify.sh` made it red. |
| 067-verify.sh:80 (AC2.4) | `git diff --quiet "$BASE" "$FINAL" -- docs/contracts/README.md` (was `"$BASE" HEAD`) | RE-PIN | "067 did not bring the old phrase back" is about 067's own change. 007b legitimately edits the README: this was the trigger. |
| 062-verify.sh:354-368 (AC6.006, AC6.008a, AC6.032, AC6.057) | check ids of `$BASE062:docs/tasks/N-verify.sh` vs the script (was the working-tree file, now `$FINAL062:...`) | RE-PIN | "062 removed no check beyond the four retirements" is about 062's own change. |
| 062-verify.sh:372-374 (AC6.034) | `git diff -U0 "$BASE062" "$FINAL062" -- docs/tasks/034-verify.sh` (was `"$BASE062" HEAD`) | RE-PIN | "062 left 034 alone" is about 062's change; the task-069 allowance for 064's C3.3 edit existed only because the range ended at HEAD. The c33 judge is kept unchanged (069 AC5 still exercises it). |
| 062-verify.sh:378-384 (AC6.006.count) | evaluated-check count of 006 at base vs a clone at `$FINAL062` (was the HEAD run `h.006`) | RE-PIN | "006 evaluates exactly 4 fewer checks" is about 062's change; a later task adding a 006 check broke it. |
| 062-verify.sh:388-393 (AC7.1) | `contracts/ownership.md` at `$BASE062` vs `$FINAL062`, and the diff between them (was the working-tree file and `"$BASE062" HEAD`) | RE-PIN | "Only the two quoting sentences of ownership.md changed" is 062's change. Any later edit of ownership.md made it red. |
| 062-verify.sh:403-405 (SELF.1) | files touched by commits whose subject starts `Task 062` in `$BASE062..$FINAL062` (was `..HEAD`) | RE-PIN | Same claim as the scope checks of the other scripts; a later commit with a `Task 062` subject (a follow-up) would have counted as 062 scope. |
| 062-verify.sh:356 (new AC6.0) | `merge-base --is-ancestor "$FINAL062" HEAD` | new | An unreachable pin FAILS naming the commit; AC6.034, AC6.006.count, AC7.1 and the AC6.* ids also fail (their git reads fail), none skips. |
| 067-verify.sh:21, 069-verify.sh:24 | ajv location | ajv default | argument, then `WOM_NODE_MODULES`, then `<repo root>/tools/dev/node_modules` (as 057/062 after 066). 067 AC3.2 and 069 AC4.0/AC7.0 fail naming `npm ci --prefix tools/dev` when ajv is absent. |

## Already pinned (own-change, range `BASE..FINAL` since tasks 062, 069)

| Script:line | What it compares | Verdict |
|---|---|---|
| 006-verify.sh:269-290 (C9.3-C9.7) | `ROUND3_BASE..ROUND3_FINAL` file set, test diff, pin reachability | already pinned |
| 007a-verify.sh:102-130 | size (`ls-tree FINAL`) and scope over `BASE..FINAL` | already pinned (task 069) |
| 008a-verify.sh:93-103 | scope and "untouched" over `BASE..FINAL` | already pinned (task 062) |
| 032-verify.sh:1669-1690 (S3a, S3, S4) | scope over `SCOPE_BASE..SCOPE_FINAL` | already pinned (task 062) |
| 057-verify.sh:43, 109-119 (P0, S1, S2, S4) | scope, test-deletion and example checks over `BASE_COMMIT..FINAL_COMMIT` | already pinned (task 062) |
| 067-verify.sh:98-103 (AC5.1) | scope over `BASE..FINAL` | already pinned (task 069 amendment 1) |

## Live properties (stay live)

| Script:line | What it checks | Reason it stays live |
|---|---|---|
| 067-verify.sh:83 (AC2.5) | the README states the sentence | content of the tree as it stands; the point is that N5b has something to find. AC4.m1 in 070 deletes the sentence (committed) and 067 AC2.5 goes red. |
| 067-verify.sh AC3.1/AC3.2 | 032 and 062 pass at HEAD | green-at-HEAD is a live property of the suite |
| 062-verify.sh:326 (AC2.moving) | scope checks of 032/057 contain no moving-base term | lexical property of the scripts as they stand |
| 062-verify.sh AC3, AC5, AC7.2/7.3 | the closed scripts pass on HEAD and on a later branch; retirement blocks complete; 032 passes on HEAD | live suite properties; AC5.1 is shown live by 070 AC4.m2 (a committed edit of a 006 retirement block reddens it) |
| 057-verify.sh:59 (F1) | committed fixtures equal the generator's output | consistency of two files in the tree |
| 057-verify.sh:116 (S3), 008a:77, 82 | no `.pyc` / key-like file tracked | hygiene of the tree as it stands |
| 007a-verify.sh:45, 008a-verify.sh:26 | `git status --porcelain` clean before `--mutate` | precondition of the mutation runner, not a claim about a task's change |
| 034-verify.sh (C5 `sha256sum` before/after, C6 example counts, ADR-0030.1) | mutation leaves schemas untouched (intra-run); example directories non-empty; `manifest.schema.json` still requires `screenshots` | intra-run integrity and live content of the schemas; none compares against a base |
| 066-verify.sh:133 (C7), C1, C6a-d | `git status` clean after `npm ci`; ajv pinned in `package.json`/lock; no `ajv`/`node` under `tools/registry` | live properties of the dev-tool layout and of the runtime path (ADR-level: ajv stays a dev tool) |
| 069-verify.sh AC1-AC5, AC7 | clones of `HEAD` run the scripts; judge variants of 034 against `$BASE062` blobs | the script builds its own fixtures; every range it uses is pinned or a fixture |

## Scripts with no git-diff / scope check, and the proof

- **034-verify.sh**: `grep -nE 'diff|ls-files|porcelain|ls-tree|--is-ancestor' docs/tasks/034-verify.sh` finds nothing (it uses
  `git show` of a pinned commit and `sha256sum`, classified above). Positive control: the same grep on `007a-verify.sh` finds
  lines 45, 102, 108, 129.
- **066-verify.sh**: no diff or range check; the same grep finds only the two `status --porcelain` lines (133, 153). Same positive
  control.
- **069-verify.sh**: no scope check of its own change; the same grep finds `diff --no-index` (126, a fixture judge) and
  `diff --stat` (321, a log line). Same positive control.
