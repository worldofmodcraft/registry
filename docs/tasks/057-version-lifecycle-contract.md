# Task 057: The version lifecycle contract — `pending → published` in `entry.schema.json` and `append-only.rules.md`

- **Mission:** SITE-V1 (unblocks deliverables D1 and D2) — **Status:** spec-approved (manager, 2026-10-15, after independent spec review rounds 1–2: PASS) 
- **Repo:** registry (`worldofmodcraft/registry`); this file is kept in the platform repository's `docs/tasks/` with the other 054 specs and copied to the registry branch's `docs/tasks/` as that task's log.
- **Agent / model:** doc-writer / sonnet for the contract text; implementer / sonnet for the schema, the `oneOf` support in the test validator, and the verify artefact (one branch, sequenced). Independent reviewer required: this amends two accepted contracts.
- **Budget:** medium (≤ 3 agent-sessions)
- **Branch / worktree:** `task/057-version-lifecycle` / `~/wt/registry-task-057`
- **Decided by:** ADR-0121 (`docs/decisions/0121-version-lifecycle-pending.md`, Accepted by Ludwig 2026-10-15, "Stjärna på allt"), which records Q-B (Ludwig, 2026-10-14), "Stjärna på allt" (mission log on `session/8-status`), Q-B — the author PR adds a version with only `version`, `commit`, `source_url` and `status: "pending"`; the pipeline's write-back PR fills in the rest and sets `published`; this is the second permitted in-place transition, beside the takedown; "it is written into the contracts by its own reviewed task (057)"; and the two follow-on rulings Q-L and Q-J (2026-10-15), folded in below as decided requirements.

## Objective
The two accepted contracts stop contradicting the pipeline. Today `entry.schema.json` requires nine
fields on every version object although the author can supply only three, and `append-only.rules.md`
forbids the write-back that would add the rest. After this task: a version object has four
states (`pending`, `published`, `removed`, `rejected`), each with an exact key set; a version is born
`pending` only; exactly three transitions exist on an existing element (T1 `pending → published`,
T2 `published → removed`, the existing takedown, T3 `pending → rejected`); the fields each party supplies
are named; nothing else may change; and every statement is demonstrated by a fixture corpus that
fails when the contract is weakened.

## Authority: ADR-0121 (closes the former blocker B1)
Task 057's first draft (2026-10-14) found that no ADR defined `pending` and that ADR-0041 ("Versions
are immutable"; the status list) and ADR-0058 §1 (build before merge; rejections in the PR) strained
against Q-B. **ADR-0121 resolves it:** `docs/decisions/0121-version-lifecycle-pending.md`, status
Accepted, merged to platform `main` (`git log --oneline -3` in the platform worktree shows
`59aa8f6 Merge pull request #48 … proposal/adr-0121-version-lifecycle`). It amends ADR-0041 (immutability
wording, status set) and ADR-0058 §1 (sequence, rejections). This task implements that ADR in the
contracts; it does not interpret it further. Where this file and ADR-0121 disagree, the ADR wins and the
disagreement is a stop-and-report.

Decided requirements taken from ADR-0121 (Ludwig, 2026-10-15):
- **Q-L:** newly appended versions are born `pending` only, with exactly the four keys `version`, `commit`, `source_url`, `status`. Born-`published` and born-`removed` are shape violations. There are no registry entries to migrate (see D-2).
- **Q-J:** a third transition T3, `pending → rejected`, performed by the pipeline's PR. It sets `status: "rejected"` and adds `reason` (non-empty after trimming) and `build_log_url` (a link to the full build log). The version is never deleted and its version string stays occupied; `rejected` is terminal and never installable or resolvable.
- The ADR leaves three things to this task: the schema form, the validator support it needs, and the exact rule text. Who may carry T1/T3 is `ownership.md`'s; **until that carve-out exists a checker must reject every T1 or T3 mutation, whoever authors it (fail closed)** (ADR-0121 Decision).

Recorded consequence, now answered: a `pending` version occupies its `version` string
(`append-only.rules.md` rule 4) and cannot be deleted (rule 3); T3 turns a build that will never succeed
into a recorded, explained terminal state. The squat itself remains possible (ADR-0121 Consequences).

## Context to load (exhaustive)
- ADRs: 0121 in full; 0041, 0058 as quoted in it; 0119 (the `owner` freeze). See Size. Task 054 finding F1 (umbrella `docs/tasks/008-build-pipeline.md`).
- Registry `origin/main` (ec56e9f when read): `contracts/entry.schema.json`, `contracts/append-only.rules.md` (all of it, esp. "File-level existence", rules 1-5, "The one permitted in-place mutation: takedown"), `contracts/examples/entry/**`, `tests/contracts/test_contracts.py`, `tests/contracts/schema_check.py` (supported keywords: `type pattern minimum minLength maxLength minItems enum required properties additionalProperties items` plus annotation keywords; **no `oneOf`, `anyOf`, `if`, `const`, `$ref`** — read 2026-10-14; unsupported keywords raise `NotImplementedError`), `docs/contracts/README.md`.
- ADR-0121 (read in full), plus the ADRs it amends: 0041, 0058.
- `contracts/ownership.md` on registry `origin/main` (task 032, merged as PR #4): rule `R11` ("takedown exception"; precedence over `R3` and `R7`; one authorised takedown PR may carry any number of takedown mutations provided the diff contains nothing else). Verified 2026-10-15: `git -C /home/ludwig/registry show origin/main:contracts/ownership.md | grep -c R11` prints a non-zero count (the 2026-10-14 draft could not find it on the then-unmerged branch). The pipeline carve-out for T1/T3 is **not** in that file (`grep -n -i carve` finds only the takedown carve-out discussion); it is a sibling task.
- Task 045 (merged as PR #6, `ec56e9f`): its takedown-shape text in `append-only.rules.md` is the base 057 edits; the anchors in the edit map were re-checked against `origin/main` on 2026-10-15 (`git show origin/main:contracts/append-only.rules.md | grep -n "only status transition\|one permitted\|two-branch"` finds lines 185-191, 266, 274, 484).
- Site repo `src/lib/validate.mjs`: uses Ajv 2020 with `strict: true` (read 2026-10-14) — relevant to D-1.
- Registry `origin/main` 2026-10-15: `a50daac` (008a merged, PR #7). `tests/contracts/schema_check.py` still has no `oneOf` (`git show origin/main:tests/contracts/schema_check.py | grep -c oneOf` prints 0); `ls-tree origin/main mods` prints nothing; `contracts/entry.schema.json` still lists only `published` in its status enum and nine `required` keys.

## Design (decisions made in this draft; D-2 is Ludwig's)

### The version object has four states, each an exact key set
| status | exact keys (no others) | who creates / changes it |
|---|---|---|
| `pending` | `version`, `commit`, `source_url`, `status` | the author's PR (E2), as a newly appended element only |
| `published` | the above plus `source_archive`, `source_sha256`, `signature`, `key_id`, `published_at` (nine keys) | only by transition T1 |
| `removed` | the nine keys plus `reason` (non-empty after trimming) | only by the takedown, transition T2 |
| `rejected` | the four `pending` keys plus `reason` (non-empty after trimming) and `build_log_url` (an `https://` URL); **no** `source_archive`, `source_sha256`, `signature`, `key_id`, `published_at` | only by transition T3 |

### T1, the `pending → published` transition (the second permitted in-place mutation)
For an index `i < n`, `new.versions[i]` may differ from `old.versions[i]` under T1 if, and only if, **all** hold:
1. `old.versions[i].status == "pending"` and `new.versions[i].status == "published"`.
2. **Author-supplied fields, frozen:** `version`, `commit` and `source_url` are deep-equal to the old values.
3. **Pipeline-written fields, each present in `new` and absent in `old`:** `source_archive`, `source_sha256`, `signature`, `key_id`, `published_at`. Each satisfies its `entry.schema.json` pattern. (Shape only: this contract cannot check that a hash matches an archive or a signature verifies — no checker here has the tarball or the key. That is E9's verifiers' job (`signature-format.md`; task 055's site verifier; the launcher). See Attack 2.)
4. `new.versions[i]` has no key outside the nine, and no `reason`.
5. The array is otherwise untouched: rules 1-3 and "Ordering of `versions[]`" apply to every other element.

**Exactly once, structurally.** T1 requires `old.status == "pending"`, and a `pending` object has none of the five fields (shape table). After T1 the status is `published`, and a `published` element is covered by plain deep-equality (rule 1) — the five fields can never be rewritten. No `published → pending` (reverting) and no `pending → pending` change exist: both are rule-1 violations.

**Nothing else may change:** `id` and `owner` stay frozen; `page.json` is untouched by a T1 or T3 diff at this layer; no element is added, removed or reordered by T1 or T3.

### T3, the `pending → rejected` transition (Q-J, ADR-0121)
For an index `i < n`, `new.versions[i]` may differ from `old.versions[i]` under T3 if, and only if, **all** hold:
1. `old.versions[i].status == "pending"` and `new.versions[i].status == "rejected"`.
2. `version`, `commit` and `source_url` are deep-equal to the old values.
3. `reason` is present in `new`, absent in `old`, a string, and non-empty after trimming; `build_log_url` is present in `new`, absent in `old`, and matches `^https://\S+$`.
4. `new.versions[i]` has exactly the keys of the `rejected` row of the shape table: none of the five pipeline-written T1 fields, and nothing else.
5. The array is otherwise untouched (rules 1-3 and ordering apply to every other element).
`rejected` is terminal and one-way: `rejected → anything` is a rule-1 violation, as is `rejected → rejected` with any change (a changed `reason` is not a correction mechanism; a new version is). A rejected version is never deleted (rule 3) and its string stays occupied (rule 4). Consumers (launcher, site, resolver) treat `pending` and `rejected` as not resolvable and say "exists but is not yet published" rather than "not found" (ADR-0121 Consequences); that behaviour is those tasks', recorded here as a dependency, not implemented here. T3 is shape-only, like T1: whether the build really failed, and whether `build_log_url` is true, cannot be checked by this contract.

### Coexistence of T1, T2 and T3
- T1, T2 and T3 start from only two `old` states (`pending` for T1 and T3, `published` for T2) and each ends in a different state, so **one element cannot undergo two of them in one PR**. `pending → removed` is a violation (nothing was archived; there is nothing to pull). `published → rejected` is a violation. A T1 element carrying a `reason` or `build_log_url` is a violation, as is a T3 element carrying any of the five pipeline-written fields (key sets above).
- The takedown section's sentence *"This is the only status transition this document permits on an existing element"* becomes false and is amended to *"the only status transition permitted on an element whose old status is `published`"*; the "one-way and terminal" paragraph is unchanged in substance.
- **Three exceptions, not one.** Rule 1 is rewritten as four branches (unchanged / T1 / T2 / T3). The section heading "The one permitted in-place mutation: takedown" becomes "The permitted in-place mutations" with T1, T2 and T3 as sibling subsections.
- **Shape layer versus authority layer.** `append-only.rules.md` classifies each element independently, so a PR holding a T1 on one version and a T2 or T3 on another is *shape-legal*. Who may carry which is `ownership.md`'s (E16): R11's takedown PR must contain nothing but takedown mutations, which excludes T1 and T3 in the same PR; the pipeline's carve-out (sibling task, umbrella 008 "Dependencies") must be keyed on the pipeline identity and on T1 or T3 mutations only. **Fail-closed default written into this contract (ADR-0121):** *until `ownership.md` carries that carve-out, a checker implementing T1 or T3 must reject every PR containing a T1 or T3 mutation, whoever its author is.* Without it, an author could write their own "published" or "rejected" fields.
- Authority for T1 and T3 is therefore **not** defined here (as the takedown section says of T2: shape, not who).

### D-1 Schema representation (made here; reviewer may overturn)
`entry.schema.json`'s version-item `required` list of nine cannot stay, and `if/then` is unsupported by the repository's validator. Options:
- **S1★ `oneOf`, one branch per status (four).** Item-level `properties` keep every pattern once; each branch is `{type: "object", required: [...], properties: {<its keys>: {}, status: {enum: [<its status>]}}, additionalProperties: false}`; `removed` and `rejected` require `reason`, `rejected` requires `build_log_url`. Needs `oneOf` added to `tests/contracts/schema_check.py` (and nothing else; unsupported keywords must still fail loudly) and a check that the site's Ajv 2020 in strict mode accepts the same schema (**unverified**; criterion 4). Exactly one branch must match: branches are mutually exclusive by their `status` enum, and a test shows an object matching two branches (impossible by construction) would fail `oneOf`. Keeps the schema strict: a `published` version without `key_id` (the existing invalid example `missing-key-id.json`) stays invalid, a `pending` object carrying `signature` is schema-invalid, and a `rejected` object without `build_log_url` is schema-invalid.
- **S2 relax `required` to the four author fields, enforce status-by-shape only in task 007's checker.** Simpler validator; but `missing-key-id.json` would then *validate*, so that invalid example would have to be moved out of the schema tests — a weakened test by another name (CLAUDE.md rule 5) — and every schema consumer (site, launcher) would have to re-implement the status-by-shape rule.
Chosen: **S1** (ADR-0121 Consequences leaves the form to this task: "three or four key sets by status"). This also closes the gap `entry.schema.json` records for `reason` ("this schema does not enforce that conditional requirement"): with `oneOf`, `removed` and `rejected` require `reason` and the other branches forbid it. Trim-emptiness of `reason` stays the checker's (rule 2/T2/T3).

### D-2 Born states — DECIDED (Q-L, ADR-0121, Ludwig 2026-10-15)
Today rule 2 lets any PR append an element already `published` (with nine fields it invents) or already `removed`. Under Q-B that would let an author skip the pipeline by writing a forged `published` object. **Every newly appended element must be `pending` with exactly the four keys.** That tightens rule 2's "born removed" clause and the creation case; there are no entries in the registry to migrate (`git ls-tree origin/main mods` prints nothing, re-run 2026-10-15). Born-`rejected` is likewise a violation: `rejected` is reached only by T3.

### D-3 What does *not* change
`id`, `owner` freeze; `deprecated` (a mod-level flag, not a version status); rules 3-5 (length, uniqueness by exact string, no monotonicity); the takedown's field-level shape and one-way terminal rule (045's precision work lands first and is not redone here); `page.json`.

## Size (5b)
Medium (≤ 3 agent-sessions), one branch, sequenced: contract text, then schema plus the `oneOf` keyword, then fixtures, oracle and verify script. The reading list is longer than ten items because this task amends two accepted contracts, but it is bounded: required in full are ADR-0121, `append-only.rules.md`, `entry.schema.json`, `schema_check.py` and `test_contracts.py`; the rest is skimmed for one fact each — ADR-0041 and 0058 §1 (quoted in ADR-0121, so not re-read), ADR-0119 (the `owner` freeze), `ownership.md` R11 (the takedown precedence), the site's `validate.mjs` (Ajv strict mode, criterion 4 only), and `docs/contracts/README.md` (two table rows). ADRs 0039, 0103 and 0117 are dropped from the required list. Split trigger: if the schema/validator/Ajv-agreement work (criteria 3-4) is not green after session 2, it becomes its own task and the text, fixtures and oracle (criteria 2, 5-7) land first.

## Edit map (so the diff is reviewable against anchors that exist today)
`contracts/append-only.rules.md`, quoted anchors verified 2026-10-14 on `origin/main`:
| anchor (text today) | change |
|---|---|
| Rule 1: "with exactly one permitted exception: the takedown transition" | four-branch statement: unchanged / T1 / T2 / T3 |
| Rule 2 and the creation case ("any element whose `status` is `"removed"` must carry a `reason`") | newly added elements must be `pending` with exactly the four keys (D-2, Q-L); the born-removed pairing sentence is replaced, not duplicated |
| Rule 2: "`entry.schema.json` cannot express this conditional requirement" | false after S1; rewritten |
| "The one permitted in-place mutation: takedown (ADR-0041)" and bullet "This is the only status transition this document permits on an existing element" | heading and bullet amended as above |
| "Fields outside `versions[]`": "whose permitted changes (appending, and the one takedown transition below)" | "appending, T1, T2 and T3" |
| New sections "T1: `pending → published`" and "T3: `pending → rejected`" | the numbered conditions, the "exactly once" argument, the fail-closed sentence, worked examples, attack attempts |
| Section "What this document does not cover" and any sentence saying "one permitted in-place mutation" (ADR-0121: wording becomes plural) | updated to the plural; `grep -n "one permitted\|only status transition"` returns zero afterwards (positive control on the pre-change blob) |
`contracts/entry.schema.json`: items `required`, `status` enum (+`pending`, +`rejected`), new property `build_log_url` (pattern `^https://\S+$`), the item and field descriptions that say "required-9-field", "starts published", "Every element is a single published version", and `source_archive`'s "absent until the pipeline runs" (the sentence that contradicted `required`). `docs/contracts/README.md`: rows for both files updated, task 057 named.
Examples: `contracts/examples/entry/valid/pending-first-publish.json`, `…/valid/removed-version-with-reason.json` kept; `valid/rejected-version.json`; `invalid/pending-with-signature.json`, `invalid/published-with-reason.json`, `invalid/rejected-without-reason.json`, `invalid/rejected-without-build-log-url.json`, `invalid/rejected-with-signature.json`, `invalid/rejected-empty-reason.json` (whitespace only; shape-valid for the schema, caught by the checker/oracle, so it lives in the transition fixtures instead if the schema cannot express trimming); the existing `invalid/status-not-in-enum.json` stays unchanged (its value is `"yanked"`, still outside the enum; checked on `origin/main` 2026-10-15), and its `_comment` is the one text to update ("one of published or removed"). the existing `invalid/missing-key-id.json` must stay invalid.

## Acceptance criteria
1. **The authority is on record:** this file cites ADR-0121 (Accepted) as above; the verify script greps `docs/decisions/0121-version-lifecycle-pending.md` on the base commit for `Status:** Accepted` and fails on zero matches.
2. `append-only.rules.md` states T1 as the five numbered conditions above, T3 as its five, the "exactly once" argument, the T1/T2/T3 coexistence paragraph, the born-`pending` rule, the fail-closed sentence (covering T1 and T3) and the shape-versus-authority split. Every anchor in the edit map is changed; a grep for each *old* sentence in the table returns zero (with a positive control that the grep finds them in the pre-change blob).
3. `entry.schema.json` is S1 with four `oneOf` branches (or, if the reviewer overturns D-1, the alternative with its consequences stated). The registry's own tests pass: `python3 -m unittest` over `tests/contracts` exits 0, and `missing-key-id.json` is still rejected by name.
4. **Both validators agree.** The same entry corpus (all `examples/entry/**` plus the shape cases of the fixture file) is run through `tests/contracts/schema_check.py` and through Ajv 2020 with `strict: true` using the site repo's `node_modules` (path passed as an argument; if Node/Ajv is unavailable the verify script reports SKIPPED loudly and the criterion is not met — a skip never yields green). Any disagreement is a failure.
5. **Append-only rules with mutation fixtures (Q-L, Q-J):** the corpus covers born-`pending`, born-`published`, born-`removed`, born-`rejected`, every T3 condition and every T1/T3 cross-transition. **Fixture corpus** `docs/tasks/057-transition-fixtures.json` (below) is complete and a reference oracle `docs/tasks/057-oracle.py` classifies every fixture as recorded. The oracle is **not** the checker and is not placed under `tools/`; task 007 must pass the same fixtures. Positive controls sit beside the hostile cases.
6. **Mutation (§2c rules 2, 5):** each of the oracle mutations listed below turns at least one fixture red, named; each contract-text mutation turns at least one text check red; each was shown red *before* the fix where a fix is involved, and restored byte-identically.
7. **No unpinned sentence:** the new "T1" and "T3" sections' sentences are all pinned in the verify script by full text (not 70-character prefixes — task 032's round-6 lesson); a sentence appended to the section turns a check red (the tail-append fixture, shown red first).
8. `docs/tasks/057-verify.sh` is committed, executable, deterministic (no network in the verdict), its scope check is merge-base-relative (task 045 criterion 6), and was run in a **fresh clone**; output pasted in the log.
9. Guardrail 6b/6c: every environmental statement made in the contract (e.g. about Ajv's strict mode) carries its command or an inline `[unverified]`.
10. The sibling contract gaps are named in the log but not done: `pipeline-trigger.md` (E15), the `ownership.md` carve-out (E16), the `artifact-naming.md` URL amendment (after task 058).

## Verification artefact (MANAGER.md §2c) — declared: `docs/tasks/057-verify.sh`
House style of `docs/tasks/032-verify.sh`: deterministic checks only decide the verdict; anything needing the network or another repo's checkout is labelled ADVISORY and cannot gate; an exit code reflects the failure count.

**Fixtures** (`057-transition-fixtures.json`; each has `name`, `old` (null for a first publish), `new`, `expect` = `accept`/`reject`, `rule`). Minimum set:
| name | expect | what it proves |
|---|---|---|
| first-publish-one-pending | accept | the author's PR is legal |
| first-publish-born-published | reject | D-2: forged published object |
| first-publish-born-removed | reject | D-2 |
| append-second-pending-after-published | accept | later versions |
| t1-exact | accept | the transition |
| t1-two-elements-two-transitions | accept (shape layer) | per-element classification |
| t1-extra-changed-field-commit | reject | frozen author fields |
| t1-source-url-changed | reject | frozen author fields |
| t1-missing-one-of-five (each of five, five fixtures) | reject | all five required |
| t1-extra-key | reject | key set |
| t1-with-reason | reject | key set / coexistence |
| t1-published-at-not-rfc3339, t1-sha256-wrong-length, t1-source-archive-http | reject | patterns |
| pending-with-partial-writeback (pending carrying `signature`) | reject | shape table |
| pending-to-pending-changed-commit | reject | frozen |
| pending-to-removed | reject | coexistence |
| published-to-pending | reject | one-way |
| published-rewritten-hashes (second write-back) | reject | exactly once |
| t2-takedown-exact | accept | existing behaviour unchanged |
| t2-with-t1-same-element | reject | coexistence (impossible start state) |
| t1-plus-whitespace-only-change-elsewhere | accept | comparison over parsed values (whitespace carries no meaning) |
| t1-plus-owner-change | reject | `owner` frozen |
| t1-reorders-versions | reject | ordering |
| first-publish-pending-with-reason (born `pending` with a fifth key `reason`) | reject | Q-L: exactly four keys |
| first-publish-pending-with-build-log-url (fifth key `build_log_url`) | reject | Q-L: exactly four keys |
| t1-version-changed | reject | frozen author fields |
| t3-version-changed | reject | frozen author fields |
| t3-reason-not-a-string (number; null; object: three fixtures) | reject | Q-J: reason is a string |
| t3-exact | accept | the rejection transition |
| t3-missing-reason | reject | Q-J: reason required |
| t3-whitespace-only-reason | reject | Q-J: non-empty after trimming |
| t3-missing-build-log-url | reject | Q-J: link required |
| t3-build-log-url-http | reject | pattern `^https://\S+$` |
| t3-carries-signature (any of the five T1 fields, five fixtures) | reject | key set |
| t3-extra-key | reject | key set |
| t3-commit-changed | reject | frozen author fields |
| t3-source-url-changed | reject | frozen author fields |
| published-to-rejected | reject | coexistence |
| rejected-to-pending | reject | terminal |
| rejected-to-published | reject | terminal |
| rejected-reason-rewritten | reject | terminal, no correction by rewrite |
| rejected-deleted | reject | never deletion (Q-J), rule 3 |
| rejected-version-reappended-as-pending | reject | string stays occupied, rule 4 |
| first-publish-born-rejected | reject | D-2: rejected only via T3 |
| append-second-pending-after-rejected | accept | a new version after a rejection |
| t1-and-t3-different-elements | accept (shape layer) | per-element classification |
| delete-pending-version | reject | rule 3 |

**Oracle mutations (each must redden a named fixture):** skip all pattern checks (reddens `t1-published-at-not-rfc3339`, `t1-sha256-wrong-length`, `t1-source-archive-http`); T3 key set "at least" instead of "exactly" (reddens `t3-extra-key` and the five `t3-carries-signature` fixtures); accept an `http://` `build_log_url` (reddens `t3-build-log-url-http`); accept a whitespace-only `reason` (reddens `t3-whitespace-only-reason`); accept a fifth key on a born-`pending` element (reddens both `first-publish-pending-with-*` fixtures); skip the `version` frozen check (reddens `t1-version-changed`, `t3-version-changed`); accept a non-string `reason` (reddens the three `t3-reason-not-a-string` fixtures); also drop the frozen-author-field check; allow `pending → removed`; stop requiring all five; allow `reason` on T1; allow born-published; allow born-rejected; allow `pending → removed`-style skips (`published → rejected`); allow `rejected → pending`; allow T3 without `reason` or without `build_log_url`; allow deletion of a `rejected` element; allow `published → pending`; compare raw text instead of parsed values; treat the T1 key set as "at least" instead of "exactly".
**Text mutations:** delete the fail-closed sentence (and, separately, the words "or T3" from it); delete the born-`pending` sentence; delete the T3 "terminal" sentence; delete the "exactly once" paragraph; change "exactly" to "at least" in condition 4; append a permissive sentence to the T1 section (tail-append); restore a stale takedown sentence.
**Positive controls** are the `accept` rows; a suite that rejects everything must fail here.

## Attack attempts the contract must answer (recorded in the new section, each against this document's own rule)
1. **Author self-publishes:** a PR appends a version already `published` with invented hashes. Answer: D-2 / shape table (rejected as born-published); and if D-2 were refused, only `ownership.md` + E9 verification would stand between a forged object and users.
2. **Garbage write-back by the pipeline identity:** a compromised or buggy pipeline PR writes a valid-shaped but wrong `source_sha256`. This contract **cannot** reject it (shape only). Defences: the carve-out keyed on the App's id and on "exactly T1"; the site's and launcher's fresh hashing and signature verification (`signature-format.md` rule 9-11); the fact that a wrong hash cannot be corrected (frozen) — so the remedy is a new version or a takedown. Stated as a known limit, not hidden.
3. **Splice a takedown into the pipeline PR** so a version vanishes unnoticed: shape-legal per element, rejected at the authority layer (R11 "nothing but takedown mutations"; the carve-out "exactly T1"). Test lives in the sibling tasks; this contract records the dependency.
4. **Pending squatting:** an author appends `pending` versions that will never build, burning version strings. Rule 4 makes the squat permanent; T3 turns each such version into a recorded, explained terminal state but does not prevent the squat (ADR-0121 Consequences). The cost falls on the squatter's own namespace only. No further rule here.
5. **Forged rejection:** an author marks their *own* `pending` version `rejected` with a self-chosen reason to skip the pipeline and retry the same string. Answer: shape-legal at this layer (T3 is shape-only), rejected by the fail-closed rule and later by the ownership carve-out keyed on the pipeline identity; recorded as the reason the carve-out covers T3 as well as T1.

## File scope (declared; anything else = stop and report)
Registry repo: `contracts/entry.schema.json`, `contracts/append-only.rules.md`, `contracts/examples/entry/**`, `tests/contracts/schema_check.py` (adding `oneOf` only), `tests/contracts/test_contracts.py` (only if a new test must be added for `oneOf` and the three-branch cases), `docs/contracts/README.md`, `docs/tasks/057-*` (this file as log, fixtures, oracle, verify script).
Out: `contracts/ownership.md` (task 032's; sibling task), `docs/decisions/` (Ludwig's), any checker under `tools/` (task 007), the site's vendored schema copies (task 041's sync; re-run after this merges — booked by the manager).

## Forbidden here (beyond MANAGER.md §3.7)
- Adding any state beyond the four (`pending`, `published`, `removed`, `rejected`), e.g. `withdrawn`; any author-initiated way to remove or retract a version (ADR-0121 adds none).
- Moving `missing-key-id.json` or any invalid example out of the schema tests to make them pass.
- Implementing authority for T1 (who may perform it) or any checker.
- Stating Ajv/GitHub behaviour without a command or an `[unverified]` marker.
- Editing the ADRs, or reinterpreting ADR-0121 (disagreement is a stop-and-report).

## Dependencies and sequencing
Checked against registry `origin/main` on 2026-10-15 (`git -C /home/ludwig/registry fetch -q origin; git -C /home/ludwig/registry log --oneline origin/main | head`): `a50daac` is the head; 032 (PR #4), 045 (PR #6) and 008a (PR #7) are merged. **All upstream dependencies of this task are met:** `032 merged` → `045 merged` → ADR-0121 accepted (platform `59aa8f6`) → **spec-approval by Ludwig** → **057** → `007` (not yet on registry `main`: `ls-tree origin/main tools` shows only `tools/pipeline`; 007 re-checks its spec against the amended schema), `008c` (needs 057) and `008b` (needs 008a, 008c, 057) → site vendored-schema re-sync (task 041's procedure; blocks 055). 008a is merged and does not depend on 057. Sibling contract tasks (E15 `pipeline-trigger.md`; `ownership.md` carve-out for T1 and T3; `artifact-naming.md` URL amendment after 058) are independent files but 008b needs all of them. No sibling is required before 057 can start.
Graph: no new node or edge. E2 and E8 already name `contracts/entry.schema.json`; E4 names `append-only.rules.md`. (Verified in `docs/architecture/depgraph.md` rows E2, E4, E8, 2026-10-14; not re-read 2026-10-15.)

## Questions  (agent-maintained; see MANAGER.md 8b)
- **B1, Q-L, Q-J: closed.** Decided by ADR-0121 (Ludwig, 2026-10-15). Nothing here is built on an assumption about them.
- **Open, for the reviewer (not blocking):** D-1 chooses S1 (`oneOf`). The reviewer may overturn; the consequences of S2 are stated above.
- **Open, for Ludwig (not blocking 057):** the pipeline-identity carve-out in `ownership.md` for T1 and T3 is a sibling task that does not exist yet as a file; the manager books it. Until it lands, T1/T3 PRs are rejected by every checker (fail closed), so no write-back can merge.

---
# Task 057 log  (append-only, updated continuously by the executing agent)
- 2026-10-14 spec written under task 054 from Ludwig's Q-B decision; nothing started; blocked on B1.
- 2026-10-15 finalised: ADR-0121 accepted (Q-L, Q-J folded in as decided requirements: born `pending` only; T3 `pending → rejected` with `reason` and `build_log_url`; four-branch `oneOf`; append-only rules and mutation fixtures extended); B1 closed; sequencing re-checked against registry `a50daac` (032, 045, 008a merged). Spec-gate ready; awaiting Ludwig's spec-approval.
