# Task 008c: Pipeline write-back — `apply_write_back`, the `source_archive` URL, and the write-back view of the result

- **Mission:** SITE-V1, deliverable **D2** (the part of 008a that depends on contracts not yet written; umbrella `docs/tasks/008-build-pipeline.md`) — **Status:** in-progress (2026-10-28, session 13) — updated 2026-10-26 (session 12) for task 092's URL contract; spec review rounds 1-2 PASS-WITH-AMENDMENTS folded in. **spec-approved** 2026-10-26 (manager, after independent spec review rounds 1-2); dispatch after 092 merges. (Split out of 008a on spec review, 2026-10-14, task 054.) 057, 058 and 008a are merged; **not dispatchable until task 092 (registry PR #25, the `artifact-naming.md` amendment) has merged.** Touches the shape of the registry's append-only record; independent review required.
- **Agent / model:** implementer / sonnet
- **Budget:** small (≤ 2 agent-sessions)
- **Branch / worktree:** `task/008c-pipeline-write-back` / `~/wt/registry-task-008c` — **registry** repo

## Why this is its own task
008a was written to build and sign a tarball from nothing but a git repository, a commit and a key. Three of its parts were not independent of that: they need the `pending → published` shape that task 057 defines (decision Q-B, Ludwig 2026-10-14) and the project-owned `source_archive` URL whose shape task 058 must discover (decision Q-G). Keeping them in 008a made the core wait for contract work it does not use. They are separated here; 008a (core) can proceed without 057 or 058.

## Objective
Given 008a's `result.json` and an `entry.json` containing a `pending` version, pure functions produce (a) the five write-back values `source_archive`, `source_sha256`, `signature`, `key_id`, `published_at`, (b) the project-owned `source_archive` URL, and (c) the new `entry.json` in which that version has gone `pending → published` — changing **exactly** what task 057's contract permits and nothing else — and each function is demonstrated against 057's fixture corpus.

## Context to load (exhaustive)
- Task 057 as merged: `contracts/entry.schema.json`, `contracts/append-only.rules.md` (T1: `pending → published`, the exact key sets), `docs/tasks/057-transition-fixtures.json` (the shared corpus) and `docs/tasks/057-oracle.py` (the reference oracle used by criterion 1(c)).
- `contracts/artifact-naming.md` section "The archived-source URL (`source_archive`)" **as merged by task 092**: the formula, the host constant, the two worked examples, path safety and injectivity, and the consumer rules (which bind 008b, not this task).
- 008a as merged: `tools/pipeline/naming.py` (`release_tag`, `check_namespace`, `split_id`) and `tools/pipeline/build_version.py` (the `result.json` shape: `id`, `version`, `artifact.{source_sha256, signature, key_id}`, `built_at`, `tag`, `assets`; the id and semver patterns).
- `contracts/signature-format.md` ("What `entry.json`'s `signature` field holds").
- ADRs: 0041 (integrity chain), 0121 (version lifecycle: `pending`, T1, T3 `rejected` terminal). Doctrine: MANAGER.md §2c, §3.6b, §3.6c, §3.7; CLAUDE.md rules 5, 11.
- Graph: nodes **N5**, **N2**; edge **E8** (the write-back fields). No new edge.

## Design (decisions made in this spec)
1. `write_back_values(result, source_archive)` → `{source_archive, source_sha256, signature, key_id, published_at}`; `published_at` is `result.built_at` (RFC 3339 UTC; the pipeline's own clock, recorded once). `source_archive` is checked for shape only (`^https://\S+$` via the schema); **equality with the derived URL is not checked here** (092 decision Q2, a separate CI task).
2. `source_archive_url(namespace, name, version)` → the project-owned URL (decision Q-G; shape fixed by task 092):
   `"https://archive.worldofmodcraft.com/" + tag + "/" + tag + ".tar.gz"`, where `tag` is 008a's naming-scheme tag (`ns.nm-v`,
   computed by 008a's `naming` module, imported, never re-implemented). The host is one named constant whose value is taken from
   the contract; no percent-encoding (`+` is written literally; `%2B` is a different string); invalid triples are refused before any string is built, by exactly
   these checks: the `id` pattern and the semver `version` pattern of `contracts/entry.schema.json` (the same patterns 008a's
   `build_version` applies), and `naming.check_namespace` (reserved device names). A version with build metadata (`+`) still yields its URL
   here — holding such versions back from publication is 008b's (092 decision Q10), not this function's. The redirect target
   and every consumer rule (hops, cap, hash-and-signature-before-use) are out of scope here.
3. `apply_write_back(entry, result, source_archive)` is pure (decision, manager ★ at spec review round 1, 2026-10-26: one entry point, so the mod/version comparison has the data it needs): it computes the values with `write_back_values(result, source_archive)`, returns a new entry and never mutates its inputs. It refuses by raising `WriteBackRefused` (a subclass of 008a's `PipelineError` in `tools/pipeline/pipeline_errors.py`: a refusal means the pipeline is inconsistent, exit 2, never a PR rejection), carrying a `reason` code per refusal below, when `result.id` differs from the entry's `id`, when no version equals `result.version`, when more than one does, when that version's status is not `pending` (`published`, `removed` or `rejected`; ADR-0121), when `result` lacks a field the five values need (`artifact.source_sha256`, `artifact.signature`, `artifact.key_id`, `built_at`), when the computed values do not have exactly the five keys (a guard on `write_back_values`' output), or when a value fails its `entry.schema.json` pattern. The entry's `commit` and every other existing field of the version are never taken from `result`.
4. Authority is not decided here: this task changes no workflow and no ownership rule. Who may *commit* the output is 008b plus the ownership carve-out.

## Acceptance criteria
All command-based; demonstrated by `docs/tasks/008c-verify.sh`.
1. **Exactly the permitted transition.** For a fixture entry with one `pending` version, `apply_write_back` returns an entry that (a) validates against `entry.schema.json` as merged by 057, (b) differs from the input in precisely the five added keys and the `status` change — shown by a field-level diff the test computes independently (a generic recursive diff, not the function's own logic), and (c) is classified **accept** by 057's reference oracle when run as `(old=input, new=output)`.
2. **Refusals.** Each named refusal of design 3 is a separate fixture and each raises `WriteBackRefused` with its specific `reason` code: absent version, duplicate matching version, `published`, `removed`, `rejected`, missing key (a `result` without `artifact.signature`, and one without `artifact.key_id`), extra key (the key-set guard tested directly with a `write_back_values` return value replaced in the test by one with a sixth key), bad `source_sha256` length, `http://` `source_archive`, `published_at` not RFC 3339, `result` from another mod, `result` for another version; and for `source_archive_url`: a bad version, a bad name, a reserved namespace. The input object is byte-identical after every call (no mutation).
3. **Shared corpus.** Every `accept` row of 057's `057-transition-fixtures.json` that is a T1 is reproduced by `apply_write_back` from its `old` plus a synthetic `result` built **from the fixture's `new` element** (never from `write_back_values`' output): `id` and `version` from the entry and version, `built_at` = `published_at`, `artifact.{source_sha256, signature, key_id}` from the same fields, and `source_archive` passed as the argument. Rows whose single T1 is accompanied by another changed element (e.g. `t1-two-elements-two-transitions`) are run once per T1 element in order, each call on the previous output; the test states which rows took that path; and for every T1 `reject` row whose `old` contains a `pending` version (the selection rule; the verify script enumerates these rows and asserts their count is above zero, so the test cannot go vacuous) the function either cannot produce it or refuses — the test asserts which. A fixture file that has changed since this task started is re-read, not cached.
4. **Mutation.** Make `apply_write_back` also copy `commit` (or another non-pipeline field) from `result` into the version (057 T1: `commit` is frozen), drop the status change, mutate its input, accept a `published` target, accept a `rejected` target, skip the mod/version comparison: each reddens a named check. Restored byte-identically.
5. **`source_archive_url`**: output equals, byte for byte, the contract's two worked examples, typed literally in the test
   (`https://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz` for `mc`, `hello-world`, `1.0.0`;
   `https://archive.worldofmodcraft.com/a.b-1.0.0-rc.1+build.5/a.b-1.0.0-rc.1+build.5.tar.gz` for `a`, `b`, `1.0.0-rc.1+build.5`);
   every generated URL matches `^https://archive\.worldofmodcraft\.com/[0-9A-Za-z._+-]+/[0-9A-Za-z._+-]+\.tar\.gz$` and contains
   no `%`, `..`, `//` after the scheme, `?` or `#`; two different `(namespace, name, version)` triples never produce the same URL
   (property test over a generated set, including the Windows-reserved-name rejections inherited from 008a); the hostname comes
   from one named constant, and a grep asserts no other module under `tools/` hard-codes it (with a positive control file that
   does, which must be found). `008c-verify.sh` greps the merged `contracts/artifact-naming.md` for the host and both worked-example
   strings and compares them with the constant and the test's typed literals (a contract change reddens it).
6. **No secret, no network:** the module imports neither `subprocess` nor a network library (grep, with a positive control file); the canary test of 008a criterion 11 is extended to `write_back_values`'s output.
7. `docs/tasks/008c-verify.sh` exists, is executable, mutation-tested (criteria 1, 2, 4, 5; for 5: host changed, `+` encoded as `%2B`, tag not repeated as the asset stem, a trailing slash added, the reserved-name check dropped — each reddens a named check), run in a fresh clone; output pasted in the log. `docs/pipeline/build-pipeline.md` gains the write-back section (what is computed, what is refused); the file also records, as `[unverified]`, that nothing here checks a hash against a tarball (that is the E9 verifiers').

## Explicitly OUT of scope
- Opening, committing or merging the write-back PR; the workflow; the ownership carve-out (008b and sibling contract work).
- Changing any contract, `entry.json`, or 057's fixtures (a needed change is a stop-and-report to 057).
- The archive tool itself (008a).
- Checking `source_archive` for equality with the derived URL in CI (092 decision Q2, booked as its own task); `apply_write_back` checks its shape only.

## File scope (declared; anything else = stop and report)
In the **registry** repo: `tools/pipeline/write_back.py` (new), `tests/pipeline/test_write_back.py` and fixtures (new), `docs/pipeline/build-pipeline.md` (the write-back section only), `docs/tasks/008c-pipeline-write-back.md` (log), `docs/tasks/008c-verify.sh` (new, executable). 008a's files are read-only here, except importing them.

## Forbidden here (beyond MANAGER.md §3.7)
- Writing the `source_archive` hostname or path anywhere but the one constant, or deriving it from anything but the merged contract.
- Deriving the test's expected output from the function under test (the project's recurring signature failure).
- Weakening a 057 fixture, or skipping the shared corpus because it is inconvenient.
- Any real key, token or `gh` credential command (CLAUDE.md rule 11).

## Size
Source files: 1 (`tools/pipeline/write_back.py`), estimated ≤ 250 changed lines. Reading list: 10 files (the four 057 files, the
092 contract, `naming.py`, `build_version.py`, `signature-format.md`, ADR-0041, ADR-0121). Within the §2b soft cap.

## Dependencies and sequencing
`032` → `045` → `057` merged; `058` merged (platform #79); `008a` merged; **`092` merged (registry #25)** → **008c** → 008b (the workflow calls these functions). 007's append-only checker, when merged, must also accept the output; criterion 1(c) uses the 057 oracle until then. File overlap with 008a: none (`write_back.py` is new; 008a is read-only here).

## Verification artefact (MANAGER.md §2c)
Declared: `docs/tasks/008c-verify.sh`; every criterion is command-based.

## Deliverables
Module, tests, docs section, verify script, this file's log current.

## Questions  (agent-maintained; see MANAGER.md 8b)
- ~~Blocked on 058 for the URL shape (decision Q-G).~~ Resolved: 058 probed (option C, Ludwig 2026-10-26), 092 fixed the shape in the contract (session 12 update). Q-J is decided (ADR-0121, 2026-10-15): `rejected` is a fourth state reached by T3. `apply_write_back` must refuse a non-`pending` version, including a `rejected` one; building the T3 diff (`reason`, `build_log_url`) is 008b's, using 057's oracle shape, not this task's.

---
# Task 008c log  (append-only, updated continuously by the executing agent)
- 2026-10-14 split out of 008a on spec review; nothing started.

## Decision recorded 2026-10-15 (Ludwig, in session: "Kör på A")
**Build logs live in `worldofmodcraft/archive` at `logs/<namespace>.<name>/<version>.log`**, committed by the
pipeline. `build_log_url` is that file's permanent https URL in a repo the project owns (ADR-0041: nothing
unpublished). The Actions run log is not used as the permanent reference (retention believed ~90 days,
[unverified]). Depends on M7 (archive repo exists).
- 2026-10-26 manager (session 12): spec updated for task 092 (URL formula, host constant from the contract, AC5 pinned to the
  contract's two worked examples, dependencies 057/058/008a merged, 092 must merge first, Q10 noted as 008b's). Out of scope and
  booked elsewhere: CI equality of `source_archive` against the derived URL (092 decision Q2). Next: independent spec review.
- 2026-10-26 manager (session 12): independent spec review round 1 **PASS-WITH-AMENDMENTS**, all folded in: (1 HIGH) `rejected` refused
  (design 3, AC2 fixture, AC4 mutation; ADR-0121); (2 HIGH) the values-vs-mod/version contradiction resolved by one entry point
  `apply_write_back(entry, result, source_archive)` (manager ★); (3 HIGH) reading list cut to 10 and a Size section added; (4 MED) the
  naming checks named exactly; (5 MED) oracle listed, ADR-0121 named; (6 MED) AC5 mutations + a command-checkable contract citation +
  positive control; (7 LOW) CI equality stated out of scope; (8 LOW) AC3 selection rule with a non-zero count, duplicate versions
  refused; (9 LOW) status line. Next: spec review round 2.
- 2026-10-26 manager (session 12): spec review round 2 **PASS-WITH-AMENDMENTS**, folded in: (1 MED) missing/extra-key fixtures grounded
  (missing via an incomplete `result`; extra via the key-set guard with a replaced `write_back_values` return); (2 MED) AC4's commit mutation
  reworded to copying from `result` (057 T1: `commit` frozen); (3 MED) AC3 builds a synthetic `result` from the fixture's `new`, never from the
  function under test; multi-element rows run once per T1 element; (4 LOW) error named `WriteBackRefused(PipelineError)` with `reason` codes;
  (5 LOW) status. **spec-approved** (manager, after two independent rounds; mechanical round-2 fixes, no decision changed). Dispatch after 092.
- 2026-10-28 manager (session 13): dispatched. 092 merged (registry #25, `e2f7fe3`); worktree `~/wt/registry-task-008c` on `task/008c-pipeline-write-back` from registry main `e2f7fe3`. Task file copied from platform main `4446f87`. Agent: implementer. Machine quiet (no verify scripts running).
- 2026-10-28 manager (session 13): first implementer run ended BLOCKED with no change (HEAD `a7498b6`); `check-log-entry.sh check ... 5` exit 1 (no entry; expected). Cause is the manager's: it entered a harness-isolated session worktree after dispatch, and the harness then refused every agent shell command outside it. The agent tried three ways in, stopped without bypassing (no sandbox override), and reported. Not a credential matter (rule 11). Manager left the isolated worktree; re-dispatched as a fresh run.
