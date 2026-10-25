# Task 065: `entry.schema.json` enforces the `key_id` format that `signature-format.md` defines

- **Mission:** SITE-V1 (D1/D2 contract consistency) — **Status:** spec-approved (independent spec review round 1 FAIL, round 2 PASS with three fixes folded in, 2026-10-17)
  (signing-adjacent contract; SPEC-CHECKLIST preamble) — written 2026-10-15, session 10. Not dispatchable before 064
  and 007b merge.
- **Repos:** registry (contract), then site (re-sync). **Agent / model:** implementer / sonnet. **Budget:** small–medium
  (≤ 2 agent-sessions: one per repo)
- **Branches / worktrees:** registry `task/065-entry-schema-key-id` / `~/wt/registry-task-065`; site
  `task/065-resync-entry-schema` / `~/wt/site-task-065`, both cut from their `origin/main` at dispatch.
- **Graph:** edges E8 (pipeline write-back) and E10 (site read side) via `entry.schema.json`; E9 (`signature-format.md`)
  is the source of the rule and is **not** changed. No new edges.

## Objective
`contracts/signature-format.md` ("Deriving `key_id`", lines 128–168 at `ac22c8f`) says `entry.json`'s `key_id` holds
exactly 16 uppercase hexadecimal characters (the reversed key-id bytes). `contracts/entry.schema.json` (line ~85–88)
only requires a non-empty string and its description defers the encoding. Found in task 007a's fix round 1
(2026-10-15): `key_id = "platform-2026-01\n"` is contract-valid today. After this task:
1. `entry.schema.json`'s `key_id` carries `"pattern": "^[0-9A-F]{16}$"` and its description cites
   `signature-format.md` "Deriving `key_id`" instead of deferring.
2. Every example and fixture that is meant to be valid uses a conforming `key_id`; every fixture meant to be invalid
   still fails, now for the reason it was written for. Known non-conforming values at `ac22c8f` (measured at the gate):
   `tests/registry/support.py` lines 34 and 93 (`"platform-2026-01"`, used as valid), `tests/contracts/test_contracts.py`
   line 337 (`"k"`), `tests/registry/test_append_only.py` line 216 (`""`, meant invalid — stays); the worked-example JSON
   in `contracts/append-only.rules.md` lines 360, 481, 498, 522 (`"platform-2026-01"`), which is also embedded in the
   T1 text pin `docs/tasks/057-pinned-sections.json`; site `fixtures/registry/mods/fixture.campfire-tales/entry.json`
   (3×) and `fixture.lantern-quests/entry.json` (1×) (`"FIXTURE0000000A"`, 15 characters, not hex). 66 occurrences of
   `E7A1B2C3D4E5F607` already conform. Pipeline code conforms (`tools/pipeline/signing.py` `pubkey_key_id`).
   **Manager's decision (spec review round 1, finding 3):** the four rules-document examples are updated (value only) and
   057's pin refreshed to match, because a contract document whose examples fail its own schema is a contradiction; this is
   the only edit to `append-only.rules.md`, and no rule text changes.
2b. **One deliberate assertion reversal (manager's sign-off, spec review round 1, finding 2):**
   `tests/registry/test_hardening.py` lines 48–53,
   `test_f1_signature_and_key_id_carry_no_pattern_so_a_trailing_newline_is_contract_valid`, asserts that `key_id =
   "platform-2026-01\n"` is accepted, because at the time no rule existed. This task creates that rule from
   `signature-format.md`, so the test is split: `signature` keeps its accepted assertion unchanged; `key_id` moves to a new
   test asserting rejection, citing task 065 and `signature-format.md` "Deriving `key_id`". This is a contract change, not a
   weakening (the resulting suite rejects strictly more), and it is the only assertion that changes direction.
3. The site's vendored `schemas/entry.schema.json` equals the registry's after the change, via the site's own
   `npm run sync-schemas -- <registry checkout>` (task 041's mechanism), and `npm run check-schemas` passes.
   **Measured at the gate:** the site copy already differs from registry `main` (task 057 changed the registry copy
   after 041's sync), so this re-sync also carries 057's version-object states to the site.
4. `signature` (multi-line minisign text): assessed, not invented. If `signature-format.md` states a shape a JSON Schema
   pattern can express exactly, propose it in the log as a question for the manager; do not add it in this task.

## Context to load (exhaustive)
This file; registry `contracts/entry.schema.json`, `contracts/signature-format.md` ("Deriving `key_id`" and the
verification rules list), `contracts/examples/entry/`, `tests/contracts/test_contracts.py`, `tests/registry/support.py`,
`tests/registry/test_append_only.py`, `docs/tasks/057-corpus.py` + `057-verify.sh` (V1 Ajv agreement);
site `scripts/sync-schemas.mjs`, `schemas/README.md`; platform `docs/manager/MANAGER.md` §2c, §3.5, `OPERATIONS.md`.

## Acceptance criteria — `docs/tasks/065-verify.sh` (registry), whose output the log pastes
1. **Red first:** a test asserting `"platform-2026-01"`, `"e7a1b2c3d4e5f607"` (lowercase), `"E7A1B2C3D4E5F60"` (15),
   `"E7A1B2C3D4E5F6071"` (17) and `"E7A1B2C3D4E5F607\n"` are rejected for a `published` and a `removed` version — committed
   before the schema change and shown failing on that commit.
2. On HEAD those are rejected by `tests/contracts/schema_check.py`, 007a's strict check and Ajv (057 V1 corpus extended);
   `E7A1B2C3D4E5F607` accepted by all three.
   The trailing-newline value is asserted explicitly against **both** `tests/contracts/schema_check.py` and 007a's
   strict check, so a regression of task 064 shows red here.
3. Fixture and example value changes are value substitutions only; the single assertion reversal is objective item 2b.
   No other assertion is removed, weakened or reversed (§3.5); the diff of each test file is shown in the log.
4. Every closed verify script passes on the merge result of the PR branch and current `main` (one at a time, quiet
   machine): 006 via 062, 007a, 007b, 008a, 032, 034, 057 (including its T1 pin, refreshed), 062, 064, 066, 067, 069, 070,
   071 — whatever is closed on `main` at dispatch.
5. Every JSON example embedded in `contracts/append-only.rules.md` that is meant to be a valid `entry.json` validates
   against the schema: if no such check exists, `065-verify.sh` adds one (extract, validate, count > 0 — a zero count fails).
6. `--mutate`: the pattern removed; lowercase allowed; `{16}` loosened to `{16,}` — each reddens a criterion-1 test.
7. Site PR: the synced `schemas/entry.schema.json` contains the `key_id` pattern (checked); the site's own Ajv 2020
   `strict:true` rejects every criterion-1 value and accepts `E7A1B2C3D4E5F607` against the synced schema;
   `npm run check-schemas -- <registry checkout at the merged commit>` passes and against registry `main` before 065
   fails (shown); `scripts/validate-fixtures.mjs` and `npm run build` pass with the updated site fixtures, and no site test,
   snapshot or verify script still asserts `FIXTURE0000000A` (searched, with the search's positive control shown before the
   change).

## File scope (declared)
Registry: `contracts/entry.schema.json`, `contracts/examples/entry/*` (only if a value must change),
`contracts/append-only.rules.md` (the four example values only), `docs/tasks/057-pinned-sections.json` (pin refresh for
that change only), `tests/contracts/test_contracts.py`, `tests/registry/support.py`, `tests/registry/test_hardening.py`
(item 2b only), new tests under `tests/`, `docs/tasks/057-corpus.py` (new cases), `docs/tasks/065-*.md`, `065-verify.sh`.
`docs/contracts/README.md` (line 27 lists `signature-format.md`) needs no edit unless it describes `key_id`'s shape —
check and log.
Site: `schemas/entry.schema.json` (via the sync script, no hand edit), `schemas/README.md` ("taken on" line),
`fixtures/registry/mods/*/entry.json` (`key_id` value substitution only).

## Forbidden here
Changing `signature-format.md` or any rule text (in any contract) other than `key_id`'s shape in the schema; adding a
`signature` pattern (objective item 4); hand-editing the site's schema copy; touching signing keys or secrets (CLAUDE.md
rule 11); weakening any test; any assertion reversal other than item 2b; renaming or deleting any check in a closed
task's verify script (062's live id guards, task 070, would — rightly — turn red).

## Before dispatch (manager)
Cut the registry branch from `origin/main` **after 064 and 007b have merged** (064 also edits `057-corpus.py`); fetch and
fast-forward the site checkout first (`/home/ludwig/site` was 5 commits behind `origin/main` on 2026-10-15, and the sync
scripts exist only there); re-run the independent spec review only if anything above changes.

## Merge
Registry PR: independent review, then **Ludwig's approval** (signature/key contract — MANAGER.md §7 "signing/keys",
read conservatively). Site PR merges after the registry PR, with the manager's authority once its review passes.

## Dependencies
**Order (2026-10-17):** 007b merged (registry #12); dispatch after **064** merges. After **064** (the trailing-newline case relies on ECMA `$` in the Python validators) and **007b** (its tests likely
reuse `tests/registry/support.py`, whose `key_id` value this task changes). Before merging: run `062-verify.sh` and
007b's tests on the PR branch merged onto `main` (OPERATIONS.md, session 9).

---
# Task 065 log
- 2026-10-15 manager (session 9): booked from 007a fix round 1.
- 2026-10-15 manager (session 10): spec written; facts measured at the gate (non-conforming fixture values; site copy
  already stale after 057). Awaiting independent spec review; dispatch after 064 and 007b merge.
- 2026-10-15 manager: independent spec review round 1: FAIL, 7 findings (site fixtures `FIXTURE0000000A`; the
  `test_hardening.py` assertion that must reverse; `append-only.rules.md` examples + 057 pin; sequencing and site fetch;
  site-side Ajv negatives; explicit `\n` assertions on both validators; 006 coverage). All addressed in the spec: findings
  2 and 3 decided by the manager as recorded in objective items 2 and 2b; finding 7 answered — 006's checks run through
  `062-verify.sh` over their pinned ranges (task 062). Round 2 pending.
- 2026-10-17 manager: independent spec review round 2 PASS; three fixes folded in (criterion 4 = every closed script on the merge result; Forbidden: no rename/delete of closed checks; status and order updated). spec-approved; dispatch after 064 merges.
- 2026-10-25 implementer (sonnet): dispatched. Registry worktree `~/wt/registry-task-065` cut from `origin/main` `4356583`
  (after 064, 007b and 075 merged); site worktree `~/wt/site-task-065` cut from `origin/main` `8bbee21`. Spec copied here.
  Verify frame (REVIEW-CHECKLIST item 12): BASE `4356583`, RED `3b53628`, FIX `e9b121e`; own-change checks measure
  BASE..FIX, live guards run on HEAD.
- 2026-10-25 implementer: **red commit `3b53628`** (tests only: `tests/registry/test_key_id_format.py` new,
  `tests/registry/test_hardening.py` +1 test). On that commit `entry.schema.json` still has no `key_id` pattern:
  `python3 -m unittest discover -s tests/registry -p test_key_id_format.py` -> `FAILED (failures=32)` (the five bad values x
  published/removed x three validator paths, the explicit trailing-newline test on schema_check.py and 007a's strict check,
  the schema-carries-the-pattern test); `test_hardening.py` -> 2 failing subtests of
  `test_f1_key_id_with_trailing_newline_is_rejected_task_065`. 065-verify.sh AC1 re-shows this from the committed red commit.
- 2026-10-25 implementer: **fix commit `e9b121e`**. Schema: `key_id` now `type`, `pattern: "^[0-9A-F]{16}$"` and a description
  citing `signature-format.md` "Deriving `key_id`" (the `minLength` is dropped: the pattern implies it; the `signature` field
  is untouched, no pattern invented, objective item 4). Value substitutions to `E7A1B2C3D4E5F607`: `tests/registry/support.py`
  (2), `tests/contracts/test_contracts.py` line 337 (`"k"`), `contracts/append-only.rules.md` (4 example values, no rule
  text), `docs/tasks/057-pinned-sections.json` (1, refreshed with `057-textchecks.py --bless`; diff is exactly that one
  substitution). `contracts/examples/entry/*` needed no change (all 66 conforming values already; `test_append_only.py`
  line 216 `""` stays and is still rejected). `docs/contracts/README.md` line 27 and the schema's row do not describe
  `key_id`'s shape: no edit. 057 corpus: +12 cases (`pattern065:key_id:{published,removed}:{ok,label,lowercase,len15,len17,newline}`),
  Python and Ajv 2020 strict agree on all 180 cases.
  Intermediate evidence: with only the schema changed (before the substitutions) `tests/registry` failed 15 tests and
  errored 22 subtests (support.py's `platform-2026-01`, the 064 `test_pattern_semantics` samples, the rules-document example
  block with the 62-character hash, the old `test_hardening` assertion), i.e. exactly the places listed in the spec plus the
  two booked under Questions 1 and 2.
- 2026-10-25 implementer: **test-file diffs (acceptance criterion 3).** Lines removed under `tests/` between BASE and FIX are
  exactly eight, all asserted by 065-verify.sh AC3.4: `test_contracts.py` `"key_id": "k",` (valid-intended, value substituted);
  `support.py` `"key_id": "platform-2026-01",` twice (value substituted); `test_hardening.py` the old test's `def` line,
  two docstring lines and its `for k, val in (("signature", ...), ("key_id", "platform-2026-01\n")):` line (objective item
  2b: the test is split, `signature` keeps its `accepted` assertion unchanged in
  `test_f1_signature_carries_no_pattern_so_a_trailing_newline_is_contract_valid`, `key_id` moves to
  `test_f1_key_id_with_trailing_newline_is_rejected_task_065`, which cites task 065 and signature-format.md);
  `test_pattern_semantics.py` `self.assertEqual(len(SUBS), 15)` -> `16` (see Questions 1). No other assertion is removed,
  weakened or reversed. `git diff 4356583 e9b121e -- tests` shows the rest as additions.
- 2026-10-25 implementer: **site part (acceptance criterion 7)**, branch `task/065-resync-entry-schema`:
  positive control of the search first: `grep -rn "FIXTURE0000" . --exclude-dir=node_modules --exclude-dir=.git` -> 4 hits
  (`campfire-tales` 16/27/39, `lantern-quests` 16). Before: `npm run check-schemas -- <registry origin/main>` -> exit 1
  `compared=3 differ=1` (the site copy was already stale after 057); `npm run validate-fixtures` -> exit 0 on the old schema.
  `npm run sync-schemas -- ~/wt/registry-task-065` -> `copied=3`, only `schemas/entry.schema.json` differs (carries 057's
  version-object states and the `key_id` pattern). `npm run check-schemas -- ~/wt/registry-task-065` -> `compared=3 differ=0`
  exit 0; against registry `origin/main` (pre-065) -> exit 1 `differ=1` (shown). With the new schema and the old fixtures
  `validate-fixtures` fails: `/versions/0/key_id must match pattern "^[0-9A-F]{16}$"` (shown). After substituting
  `FIXTURE0000000A` -> `E7A1B2C3D4E5F607` (4 occurrences, 2 files): the same grep -> no hits (rc 1);
  `npm run validate-fixtures` -> `7 fixture file(s) validated ... All valid.`; `npm run build` -> exit 0 incl. `verify-dist`;
  `npm run test:archive-safety` -> all passed. The site's own Ajv 2020 `strict:true` (`src/lib/validate.mjs`) against the synced
  schema rejects `platform-2026-01`, `e7a1b2c3d4e5f607`, `E7A1B2C3D4E5F60`, `E7A1B2C3D4E5F6071`, `E7A1B2C3D4E5F607\n` for a
  published and a removed version and accepts `E7A1B2C3D4E5F607` for both (12 verdicts, script `/tmp/site065-ajv.mjs`, not
  committed: the site's declared file scope has no place for it).
- 2026-10-25 implementer: **AC4 finding — `075-verify.sh` is not pinned.** The first full `065-verify.sh` run on HEAD
  `7b67d1f` (about 100 minutes, because 064/069/070 run the other closed scripts again) was green for 007a, 007b, 008a, 032,
  034, 062, 064, 066, 067, 069, 070, 071, 006 (directly and through 062) and the four unittest suites, and red for exactly one
  closed check: `075-verify.sh` line 47-48, `bad="$(G diff --name-only "$BASE" HEAD | grep -v -E "$allowed")"` ->
  `FAIL out-of-scope files in base..HEAD: contracts/append-only.rules.md`. That check measures `BASE..HEAD`, a moving frame
  (REVIEW-CHECKLIST item 12); it was green on `origin/main` only because 075 was the last task to touch those files, and turns
  red the first time a later task touches `contracts/append-only.rules.md` (here: the four example values the spec orders).
  065 may not edit `075-verify.sh` (not in scope; the Forbidden list bars changing closed checks), so criterion 4 cannot be
  met by this branch alone. See Questions 3.
- 2026-10-25 implementer: the same first run also showed my own AC1.7-AC1.9 greps were wrong (they matched an inline format
  that unittest prints only for passing tests); fixed to read the `FAIL:`/`ERROR:` summary lines as 064-verify.sh does. They
  are exercised by the final run recorded below.

## Questions (booked for the manager, none blocking the PRs)
1. **File-scope gap: `tests/registry/test_pattern_semantics.py` (task 064's file).** Its completeness test pins every
   `pattern` key of `contracts/*.schema.json` to a valid sample and asserts `len(SUBS) == 15`. Adding the `key_id` pattern
   makes that suite red until the table gains `"entry.schema.json#/properties/versions/items/properties/key_id":
   "E7A1B2C3D4E5F607"` and the count becomes 16. I made exactly those two edits (an addition and a number that the
   new pattern forces, not a weakening; the file's own comment says a new pattern "turns this suite red" until a sample is
   added). The spec's file scope does not list it. Please ratify (or tell me to move it into a separate task).
2. **Pre-existing defect in `contracts/append-only.rules.md`** (not touched): the T2 worked counter-example's changed
   `source_sha256` is 62 characters (`dddd...`), so that example is not schema-valid on its own regardless of `key_id`. The
   spec limits the file to the four `key_id` values, so I left it; `test_key_id_format.py` and AC5 normalise that one field
   to 64 characters and say so. Also note rule 3 of T1 (rules.md line ~311-314) still reads "(or, for `signature` and `key_id`,
   its minimum length)": after 065 `key_id` has a pattern, not a minimum length. No rule text may change here; a follow-up
   wording task is needed if you want that sentence exact.
3. **`075-verify.sh` re-pin.** Remedy options: (A) a one-line re-pin of `docs/tasks/075-verify.sh` line 47 to measure
   `$BASE..$FIX` (precedent: tasks 067/071), done as a separate task that merges before 065, or (B) extend 065's file scope by
   `docs/tasks/075-verify.sh` for that single line. I did neither. Until one of them lands `065-verify.sh` exits 1 with
   exactly that one failing check (AC4.2 075).
4. **Stale docstring outside scope:** `tools/registry/schema.py` (module docstring, "Fields with no `pattern` in the schema
   (`signature`, `key_id`: minLength only)") now misdescribes `key_id`. Behaviour is unaffected (the check reads the schema);
   `tools/registry/schema.py` is not in 065's scope, so it is unedited. One-word fix for any later task touching that file.
5. **Objective item 4 (`signature` shape): assessed, nothing proposed.** `signature-format.md` says the field holds the
   complete four-line minisign signature file verbatim (untrusted comment line, base64 line, trusted comment line, base64
   line, newline-separated). Line lengths of the two base64 lines are fixed by the format, but the trusted comment embeds
   `id`/`version`/`sha256` and the first line carries the key-id hex, so an exact JSON Schema `pattern` would have to
   duplicate those fields' grammars; and `test_hardening` deliberately keeps a trailing newline contract-valid. I would
   propose only a structural pattern (four newline-separated lines starting `untrusted comment: `, `trusted comment: `)
   if you want one; I did not add it.
6. **Registry-commit reference for the site README.** The site's `schemas/README.md` "taken on" line names the registry branch
   tip it was synced from (the PR merge commit does not exist yet); the schema bytes are what `check-schemas` enforces.
