# Task 006: The registry contracts — entry, page, manifest, append-only, reserved namespaces

- **Mission:** SITE-V1 — **Status:** spec-approved (manager, 2026-09-03)
- **Agent / model:** implementer / sonnet
- **Budget:** medium (≤ 3 agent-sessions)
- **Branch / worktree:** task/006-contracts / /home/ludwig/wt/registry-task-006
- **Graph:** the **root** of the SITE-V1 dependency graph. Defines edges **E1, E2, E3, E4, E8, E10**
  (`docs/architecture/depgraph.md` in the platform repo). Every later task codes against these.

## Objective
The data contracts of the registry exist as JSON Schema files with worked examples and tests, so
that the registry side (CI, pipeline) and the site side can be built in parallel against a written
agreement instead of against each other. Nothing here is executable policy — that is task 007's
job. This task defines the shapes.

## Why this is worth doing carefully
This is the last cheap moment. Once CI, the pipeline and the site all read these schemas, changing
a field name means changing four things at once. Two earlier tasks in this mission were lost to
specifications that sounded right; a schema that sounds right has the same failure mode.

## Context to load (exhaustive — read before writing)
- **ADR-0058** §2 (entry shape, `owner = {provider, id, name_at_registration}`), §3 (namespace
  creation and its confirmation text), §4 (provider neutrality — the format is not GitHub-specific)
- **ADR-0059** §2 (page content vs version-bound content), §3 (`page.json` PRs)
- **ADR-0119** (reserved namespaces `mc` and `test`, owned by the organisation, as *data*)
- **ADR-0030** (manifest fields; only those meaningful without the kernel — see scope below)
- **ADR-0041** (append-only, hashes, signature, `key_id`), **ADR-0049** (OSI licences)
- **ADR-0013** (namespaced ids), **ADR-0042** (versioning), **ADR-0103** (boring solutions)
- Files: `contracts/validation-report.schema.json` (task 002's contract — match its conventions),
  `docs/validation/asset-scanner.md`, and the mission spec §4 D1

## File scope (declared)
- `contracts/entry.schema.json`, `contracts/page.schema.json`, `contracts/manifest.schema.json`
- `contracts/append-only.rules.md`
- `reserved-namespaces.json` (repo root — the data ADR-0119 §1 specifies)
- `contracts/examples/**` (valid and invalid worked examples)
- `tests/contracts/**`
- `docs/contracts/README.md`
- `docs/tasks/006-contracts.md` (this file's log)

## Acceptance criteria
Each demonstrated by a command actually run, output in the log.

1. **Entry schema** matches ADR-0058 §2 exactly: `owner = {provider, id, name_at_registration}`
   where `id` is the **numeric account id** (not a string username), and `versions[]` objects carry
   `{version, commit, source_url, source_archive, source_sha256, signature, key_id, published_at,
   status}`. `version` is semver; `commit` is a full 40-hex sha; `source_sha256` is 64 hex;
   `published_at` is RFC 3339; `status` is a closed enum. Demonstrated by validating the worked
   examples.
2. **Provider neutrality holds** (ADR-0058 §4): nothing in the schema requires `provider` to be
   `"github"`, and `source_url` accepts any public git URL. Demonstrated with a non-GitHub example
   that validates.
3. **Page schema** matches ADR-0059 §2: description, screenshots[], tags[], links[], deprecated.
   Screenshot paths are relative paths inside the mod, never absolute URLs — pages are built from
   the **archive**, not the live web (ADR-0059 §1). Demonstrated: an absolute-URL screenshot is
   rejected by the schema.
4. **Manifest schema** covers only the ADR-0030 fields meaningful without a kernel: `id`, `name`,
   `version`, `api_version`, `license`, `source`, `type`, `description`, `tags`, `screenshots`,
   `ai_assisted`. `id` is `namespace:name`. `license` must be an **OSI-approved SPDX identifier** —
   embed the list as data with its provenance recorded, do not hand-write a partial list from
   memory. Demonstrated: `MIT` passes, `LicenseRef-Proprietary` and `NOASSERTION` fail.
5. **Reserved namespaces exist as data**: `reserved-namespaces.json` contains `mc` and `test`, each
   with the organisation's numeric id (**324218296**) and a written reason. Schema-validated.
6. **Append-only rules are written precisely enough to implement**: `contracts/append-only.rules.md`
   states, at field level, what a PR may and may not change — new version objects may be added;
   no existing version object may be modified or removed; which entry fields outside `versions[]`
   are mutable and which are frozen; and what happens on reordering. Task 007 will implement a diff
   check directly from this document, so ambiguity here becomes a bug there.
7. **Worked examples, valid and invalid, for every schema**, each invalid one carrying a comment
   saying which rule it violates. Every example is validated in the tests — a valid example that
   fails, or an invalid one that passes, fails the suite.
8. **Tests run offline with the standard library only** (matching task 002's approach) or with a
   dependency explicitly justified in the log. Two runs produce identical results.

## Forbidden here
Beyond MANAGER.md §3.7:
- Implementing any checking logic — no CI, no diff checker. This task writes contracts; task 007
  implements them. A schema that needs code to be understood is not finished.
- Inventing field names not traceable to an ADR. Every property maps to a named ADR clause; where
  the ADRs are silent and a field is genuinely needed, add it and **book it as a question**.
- Writing the SPDX OSI list from memory. Fetch it or vendor it with provenance and a date.
- Making `owner.id` a string, or accepting a username where the numeric id belongs — that is the
  namespace-capture attack ADR-0058 §2 exists to prevent.
- Allowing screenshots to be absolute URLs anywhere.

## Questions
- **Q1 — `owner` frozen forever, with no transfer path.** `contracts/append-only.rules.md`
  declares `id` and `owner` on `entry.json` permanently frozen (no top-level mutable fields at
  all), inferred from ADR-0058 §3 ("Namespaces are never reassigned") since no ADR read for this
  task states directly that the `owner` *field* itself can never be edited by a later PR. If
  account migration (e.g. a GitHub account rename that changes nothing about the numeric id, or
  a genuine ownership transfer under some future governance process) should ever be possible,
  that needs its own ADR before task 007's checker can allow it — this document says so
  explicitly in its own text.
- **Q2 — entry-level `tier` not included.** ADR-0059 §1 lists "tier" among what the site build
  reads from "the registry entry", but this task's acceptance criterion 1 gives an exact
  version-object field list that does not include it, and no ADR says where on the entry a
  mod-wide tier value would live (per-entry? per-version?). Not added — `entry.schema.json`
  matches criterion 1 exactly. Where tier is actually stored is undecided and worth a line in a
  future ADR or task spec.
- **Q3 — version-object `reason`, optional, not in criterion 1's literal list.** ADR-0041: a
  removed version's "registry entry [is] kept with status and reason". Criterion 1's exact
  field list is 9 fields and does not name `reason`. Added it as a 10th, *optional* property
  (not in `required`) rather than either dropping ADR-0041's explicit requirement or breaking
  criterion 1's literal list — documented at length in `entry.schema.json` itself and in
  `contracts/append-only.rules.md`.
- **Q4 — `links[]` shape (`{label, url}`).** ADR-0059 §2 names `links[]` as a page-content field
  but does not specify what a link object contains. Assumed `{label, url}`, both required.
- **Q5 — `api_version` format.** ADR-0030 names the field but not its syntax (single semver? a
  range like the kernel's API-ring versioning in ADR-0020 might imply?). Kept as a non-empty
  string with no pattern, rather than inventing a format ADR-0020 doesn't actually specify for
  this field.
- **Q6 — `license` accepts one SPDX identifier, not a full SPDX expression.** ADR-0049 says "any
  OSI-approved licence" but doesn't say whether dual/multi-licensing (`"MIT OR Apache-2.0"`)
  must be representable. This task's criterion 4 only demonstrates single identifiers, so the
  schema is deliberately the simpler, boring shape (ADR-0103) rather than a full SPDX-expression
  grammar; if mods need to dual-license, that is a follow-up decision.
- **Q7 — reserved-namespaces.json's organisation login string.** The task instructions gave the
  numeric id (324218296) directly; no ADR or instruction gave the GitHub organisation's exact
  login/display string for `name_at_registration`. Used `"worldofmodcraft"`, matching the
  `worldofmodcraft/registry` repo path this file lives in. Worth Ludwig confirming this is the
  literal org login once §6 of the mission (org creation) actually happens.
- **Q8 — `reserved-namespaces.json` shape.** ADR-0119 §1 only says "one entry per namespace with
  the reason it is reserved" — array vs. object-keyed-by-namespace is unstated. Chose an object
  map (`{"namespaces": {"mc": {...}, "test": {...}}}`, plus a `schema_version` field matching
  `contracts/validation-report.schema.json`'s convention) for O(1) CI lookup; an array would
  also have satisfied the ADR's literal words.
- **Q9 — where the `reserved-namespaces.json` schema lives.** Criterion 5 requires it be
  "schema-validated" but the task's declared file scope names exactly three `contracts/*.schema.json`
  files (entry, page, manifest) and does not add a fourth for the root-level
  `reserved-namespaces.json`. Rather than write outside the declared scope, its schema lives at
  `tests/contracts/reserved-namespaces.schema.json`, inside the broad `tests/contracts/**` scope
  grant, with the `owner` sub-shape duplicated from `entry.schema.json` (no `$ref` support in
  the stdlib-only validator). Flagging in case a `contracts/reserved-namespaces.schema.json`
  file was actually intended and the file-scope list is just incomplete.
- **Q10 — mission spec D1's version-field list omits `key_id`.**
  `docs/tasks/MISSION-worldofmodcraft-site-v1.md` §4 D1 lists version fields as
  `{ version, commit, source_url, source_archive, source_sha256, signature, published_at, status }`
  — no `key_id`. This task's criterion 1, ADR-0041 ("the format carries key_id for rotation"),
  and `docs/architecture/depgraph.md` edge E8 (write-back fields explicitly including `key_id`)
  all agree `key_id` belongs. Treated the mission spec's D1 bullet as the stale/abbreviated one
  and followed criterion 1 + ADR-0041 + the depgraph, all three of which are more specific and
  mutually consistent. Not a blocking conflict, but worth a note since the instructions asked
  me to flag exactly this kind of disagreement.

---
# Task 006 log

- 2026-09-03 spec approved; worktree created from registry main.

- 2026-09-03 **Context loaded.** Read, in full: this task file; ADR-0058, 0059, 0119, 0030, 0041,
  0049, 0013, 0042, 0103; `contracts/validation-report.schema.json` (task 002's conventions);
  `docs/validation/asset-scanner.md`; `docs/architecture/depgraph.md` and
  `docs/tasks/MISSION-worldofmodcraft-site-v1.md` (both in the `wom` platform repo, read-only —
  outside this worktree's repo but not this task's declared file scope, since neither is
  written to). The depgraph gave the *exact* edge-to-contract-file mapping (E1→manifest,
  E2→entry, E3→page, E4→append-only.rules.md, E8→entry write-back fields named explicitly,
  E10→entry+page read side) which resolved several shape questions before they became guesses —
  in particular, edge E8's write-back field list is verbatim the pipeline-written subset of
  criterion 1's version-object fields, confirming the version object correctly mixes
  author-submitted (`version`, `commit`, `source_url`) and pipeline-written
  (`source_archive`, `source_sha256`, `signature`, `key_id`, `published_at`, `status`) fields
  in one object rather than needing two.

- 2026-09-03 **SPDX OSI license list fetched, not hand-written.**
  `curl https://raw.githubusercontent.com/spdx/license-list-data/main/json/licenses.json` (HTTP
  200, 338776 bytes) — the SPDX license-list-data project's own canonical machine-readable list.
  Filtered in Python to `isOsiApproved: true` and `isDeprecatedLicenseId: false`: **139**
  identifiers, upstream `licenseListVersion` "7661985", `releaseDate` "2026-09-02T00:00:00Z".
  Provenance (source URL, fetch date, upstream version/release date, filter applied) is recorded
  in `contracts/manifest.schema.json`'s `license` property as a `$comment`, per this task's
  instruction to record provenance rather than just paste the list in silently. Confirmed `MIT`
  is in the filtered set and `NOASSERTION`/`LicenseRef-Proprietary` are not (both real SPDX
  tokens, neither an OSI-approved license id) before writing the schema, matching acceptance
  criterion 4's exact demonstration.

- 2026-09-03 **Schemas, examples, rules doc and tests written.** All files in the declared scope
  now exist: `contracts/{entry,page,manifest}.schema.json`, `contracts/append-only.rules.md`,
  `reserved-namespaces.json`, 27 worked examples under `contracts/examples/**` (entry: 3 valid /
  8 invalid; page: 2 valid / 5 invalid; manifest: 3 valid / 6 invalid), a stdlib-only schema
  validator + test suite under `tests/contracts/**`, and `docs/contracts/README.md`. No
  checking/diff logic was written anywhere — every rule in `append-only.rules.md` is prose, not
  code, per the task's explicit "Forbidden" list.

- 2026-09-03 **Bug caught by the tests themselves, fixed.** The first draft of the entry
  examples hand-typed `commit`/`source_sha256` hex strings and two were the wrong length (39
  and 38 hex characters instead of 40/64) — caught immediately by
  `test_valid_examples_validate` failing on files that were supposed to be valid. Fixed by
  generating every `commit`/`source_sha256` value in worked examples via
  `hashlib.sha1(label).hexdigest()` / `hashlib.sha256(label).hexdigest()` on a readable label,
  asserting the length mechanically, instead of hand-typing hex — the exact class of mistake
  ADR-0004/asset-scanner's own "derived mechanically, never hand-typed" precedent warns about,
  just showing up in test fixtures instead of production code this time. Also normalised every
  other *invalid* example's incidental `commit`/`source_sha256` fields to be independently
  valid, so each invalid example demonstrates exactly the one violation its `_comment` names
  (verified: `contracts/examples/entry/invalid/*.json` — every file's `commit`/`source_sha256`
  is well-formed except the one file whose `_comment` says otherwise).

## Acceptance criteria — demonstrated

All commands below were run from `/home/ludwig/wt/registry-task-006`.

**1. Entry schema matches ADR-0058 §2 exactly.**
```
$ python3 -c "
import json
s = json.load(open('contracts/entry.schema.json'))
print(s['properties']['versions']['items']['required'])
print('owner required:', s['properties']['owner']['required'])
print('owner.id type:', s['properties']['owner']['properties']['id']['type'])
"
['version', 'commit', 'source_url', 'source_archive', 'source_sha256', 'signature', 'key_id', 'published_at', 'status']
owner required: ['provider', 'id', 'name_at_registration']
owner.id type: integer
```
```
$ python3 -m unittest discover -s tests/contracts -k EntryExampleTests -k OwnerIdIsNumericTests -v
test_invalid_examples_are_rejected (test_contracts.EntryExampleTests.test_invalid_examples_are_rejected) ... ok
test_valid_examples_validate (test_contracts.EntryExampleTests.test_valid_examples_validate) ... ok
test_owner_id_schema_type_is_integer_not_string (test_contracts.OwnerIdIsNumericTests.test_owner_id_schema_type_is_integer_not_string) ... ok
test_string_owner_id_is_rejected (test_contracts.OwnerIdIsNumericTests.test_string_owner_id_is_rejected) ... ok
Ran 4 tests in 0.002s
OK
```
`contracts/examples/entry/invalid/owner-id-as-string.json` is the named trap made concrete: a
string `owner.id` is rejected because the schema types it `integer`.

**2. Provider neutrality holds (ADR-0058 §4).**
```
$ python3 -m unittest discover -s tests/contracts -k ProviderNeutralityTests -v
test_non_github_provider_and_source_url_validate ... ok
test_schema_text_never_hardcodes_github ... ok
Ran 2 tests in 0.001s
OK
```
`contracts/examples/entry/valid/non-github-provider.json` uses `provider: "sourcehut"` and a
`git.sr.ht` source URL, and validates. The second test asserts structurally that neither
`owner.provider` nor `versions[].source_url` carries an `enum`/`const` keyword in the schema —
nothing *could* require "github" even by accident.

**3. Page schema matches ADR-0059 §2; absolute-URL screenshots rejected.**
```
$ python3 -m unittest discover -s tests/contracts -k ScreenshotPathTests -v
test_absolute_url_screenshot_rejected_in_manifest_schema ... ok
test_absolute_url_screenshot_rejected_in_page_schema ... ok
test_relative_screenshot_accepted ... ok
Ran 3 tests in 0.001s
OK
```
Two independent invalid examples cover this: an absolute URL
(`contracts/examples/page/invalid/screenshot-absolute-url.json`) and an absolute filesystem
path (`contracts/examples/page/invalid/screenshot-absolute-filesystem-path.json`) — both
rejected, and the same relative-path rule is proven again on `manifest.schema.json`'s
`screenshots`.

**4. Manifest schema covers only the named ADR-0030 subset; licence is OSI-approved SPDX.**
```
$ python3 -m unittest discover -s tests/contracts -k LicenseListTests -k ManifestExampleTests -v
test_license_list_has_recorded_provenance ... ok
test_license_list_is_not_a_hand_written_handful ... ok
test_licenseref_proprietary_and_noassertion_are_not_osi_approved ... ok
test_mit_is_osi_approved ... ok
test_invalid_examples_are_rejected ... ok
test_valid_examples_validate ... ok
Ran 6 tests in 0.002s
OK
```
`contracts/examples/manifest/valid/mit-mod.json` (`license: "MIT"`) validates;
`contracts/examples/manifest/invalid/license-licenseref-proprietary.json` and
`.../license-noassertion.json` are both rejected — the exact three cases criterion 4 names.

**5. Reserved namespaces exist as data, schema-validated.**
```
$ python3 -m unittest discover -s tests/contracts -k ReservedNamespacesTests -v
test_contains_mc_and_test ... ok
test_each_namespace_has_a_written_reason ... ok
test_org_numeric_id_is_324218296 ... ok
test_validates_against_its_schema ... ok
Ran 4 tests in 0.001s
OK
```
`reserved-namespaces.json` contains exactly `mc` and `test`, each owned by numeric id
`324218296` with a written reason, validated against
`tests/contracts/reserved-namespaces.schema.json` (see Q9 for why this schema file lives under
`tests/contracts/` rather than `contracts/`).

**6. Append-only rules precise enough to implement.** `contracts/append-only.rules.md` — no
command to run (it is prose, deliberately no checking logic per this task's "Forbidden"
section). States at field level: `id`/`owner` are frozen with no mutable top-level fields;
`versions[]` is compared as `new.versions[0:n] == old.versions[0:n]` (a positional prefix
equality, not a set/content comparison); reordering existing elements is a violation under that
same rule (stated explicitly, with the mechanism shown); a version removed and re-added
identically is *also* a violation under the same rule, for the same reason, not a special case
(stated explicitly, with a worked 5-element/index-2 example); JSON object key order and
whitespace are never meaningful; `page.json` is explicitly out of scope for this document
(ADR-0059 §2-3: it is not append-only at all) — a scoping note task 007 needs, since both files
live in the same mod directory.

**7. Worked examples, valid and invalid, for every schema, each carrying a comment.**
```
$ find contracts/examples -name "*.json" | wc -l
27
$ python3 -c "
import json, glob
missing = [f for f in glob.glob('contracts/examples/**/*.json', recursive=True)
           if not json.load(open(f)).get('_comment','').strip()]
print('missing/empty comment:', missing)
"
missing/empty comment: []
```
27 examples: entry 3 valid / 8 invalid, page 2 valid / 5 invalid, manifest 3 valid / 6 invalid.
Every file is `{"_comment": "...", "example": {...}}`; only `example` is schema-validated, so
the comment never contaminates the object under test. Every invalid example's incidental fields
(besides the one under test) were normalised to be independently valid, so each demonstrates
exactly the violation its comment names (see the "Bug caught by the tests themselves" log entry
above).

**8. Tests run offline, standard library only; two runs identical.**
```
$ python3 -m unittest discover -s tests/contracts -v 2>&1 | tail -6
Ran 23 tests in 0.007s
OK
$ python3 -m unittest discover -s tests/contracts -v > /tmp/run1.txt 2>&1; echo "exit1=$?"
exit1=0
$ python3 -m unittest discover -s tests/contracts -v > /tmp/run2.txt 2>&1; echo "exit2=$?"
exit2=0
$ diff /tmp/run1.txt /tmp/run2.txt && echo IDENTICAL
IDENTICAL
```
`tests/contracts/schema_check.py` and `tests/contracts/test_contracts.py` import only `re`,
`json`, `unittest`, `pathlib` and each other — no third-party package, no network access at test
time (the SPDX fetch happened once, at authoring time, into the schema's vendored `enum`+
`$comment`, not at test time). The two full-suite runs above produced byte-identical stdout,
including the (in this instance, coincidentally equal) elapsed-time line — the pass/fail outcome
per test is what's guaranteed stable; the timing line is unittest's own report text, not a
determinism claim this suite makes about itself.

## Scope note

Files touched, all inside the declared scope: `contracts/entry.schema.json`,
`contracts/page.schema.json`, `contracts/manifest.schema.json`,
`contracts/append-only.rules.md`, `reserved-namespaces.json`, `contracts/examples/**`,
`tests/contracts/**` (including a new `reserved-namespaces.schema.json`, inside the
`tests/contracts/**` grant — see Q9), `docs/contracts/README.md`, and this file.
`contracts/validation-report.schema.json` (task 002) was read for convention only, never
written to. `tests/contracts/__pycache__/` was generated by running the suite and deliberately
not committed (same call task 002 made for its own `__pycache__` directories — a root
`.gitignore` is outside this task's declared file scope).

**Status: criteria 1-8 demonstrated above. Ready for review.** No checking/diff logic was
implemented anywhere in this task (task 007's job). Nine questions booked above (Q1-Q9) plus one
spec-inconsistency note (Q10, mission D1 vs. this task/ADR-0041/depgraph over `key_id`) — none
blocking, all worth Ludwig's eyes per the standing instruction to book rather than silently
assume.

---
# Review verdict — 2026-09-03: BLOCKING (2 findings). Recorded, not fixed.
Reviewed independently. Everything except `append-only.rules.md` passed and was verified rather
than re-read: 23/23 tests deterministic across two runs; **all 19 invalid worked examples proven
load-bearing** (each was re-validated against a schema copy with exactly its own rule removed, and
failed only for the reason its `_comment` names); the vendored SPDX enum re-fetched and confirmed
byte-for-byte equal to upstream's `isOsiApproved && !isDeprecatedLicenseId` filter; the stdlib
validator's `NotImplementedError` refusal confirmed real for ten unsupported keywords; no checking
logic present; Q1–Q9 reasonable and correctly booked.

Both blocking findings are in `contracts/append-only.rules.md` — the document task 007 will
implement a diff checker directly from, which is exactly why it was the review's primary target.

**F1 — the rules forbid the takedown ADR-0041 mandates.**
`append-only.rules.md:77-82` states an unconditional deep-equal prefix rule, and `:145-153` says an
in-place field rewrite on an existing `versions[i]` is a violation "exactly the same way a shorter
array is", with no carve-outs. But ADR-0041 requires that legal grounds lead to **removed**:
"artefacts pulled, registry entry kept with status and reason" — a legitimate later mutation of
`status` (and addition of `reason`) on an **already-published** version object. The document
reserves an explicit escape hatch for `id`/`owner` (`:66-71`) but none for `versions[i].status`.
The one `status: "removed"` example shows a version *born* removed at write-back time, not a
transition, so it cannot stand in for the ADR-0041 scenario. A task 007 checker built faithfully
from this prose would make the platform's only legal-takedown mechanism impossible to implement.

**F2 — uniqueness is only checked against history, not within the PR.**
Rule 4 (`:89-98`) forbids a new version whose `version` equals an **existing** one, where
"existing" is defined against `old.versions` throughout. Two version objects both labelled `2.0.0`
added in the *same* PR violate neither the schema (cross-item uniqueness is correctly left to the
checker) nor rule 4's literal wording — defeating the rule's own stated rationale, "which build is
'the' 1.2.0?".

**Required before merge:** amend `append-only.rules.md` to state (a) whether and how an existing
version's `status` may transition to `removed`, and if permitted exactly which fields may change on
that element (presumably `status` and `reason` only, everything else still frozen); and (b) that
newly added version objects must be pairwise-unique on `version` among themselves as well as
against history.

**Status: in review, blocking findings recorded.** Not fixed in this session — the manager reached
the 40 % context hard threshold (MANAGER.md §5) and handed over. The next session fixes these two
points, re-verifies, and re-reviews before merging.

---
# Review round 1 — fix brief (manager, 2026-09-03)

Scope: `contracts/append-only.rules.md` and, if it restates any changed rule,
`docs/contracts/README.md`. Nothing else. No checking logic anywhere — this task still writes
contracts; task 007 implements them.

## Ludwig's decision, 2026-09-03 — what authorises a takedown

F1 exposes a question no ADR answers: a field-level diff checker cannot distinguish an authorised
legal takedown from an attacker editing someone else's entry. Three options were put to Ludwig
(shape-only check with the merge gate as the authorisation; forbid in-place edits entirely and do
takedowns by loudly lifting branch protection; shape check plus a separate signed takedown record).

**His answer: option 1 — the merge gate IS the authorisation.** `main` on `registry` is protected
and only Ludwig can merge, so the human merge decision is the authorisation, and the `reason` text
stays in git history forever as the audit record. This is the boring solution (ADR-0103) working as
designed: no new file format, no new machinery, existing controls carrying the weight.

**Revisit condition, recorded for the future:** *if merge rights ever extend beyond Ludwig* —
external moderators, phase 3 — this decision must be revisited, and **option 3 (a separate signed
takedown record in the same PR, which the checker requires before accepting the mutation) is the
named candidate.** The moment the merge gate stops being one trusted person, it stops being an
authorisation mechanism, and the carve-out below becomes an unguarded hole.

## F1 — the one permitted in-place mutation

The document must stop being unconditional and instead state, at field level, exactly one carve-out
to rule 1, in terms a checker implements without inference:

- For `i < n`, `new.versions[i]` must be deep-equal to `old.versions[i]` **except** for a single
  permitted transition: `old.versions[i].status == "published"` and
  `new.versions[i].status == "removed"`.
- On that transition the **only** other permitted difference is `reason`: it must be present and a
  non-empty string in `new.versions[i]`. A takedown transition without a non-empty `reason` is a
  violation (ADR-0041: "registry entry kept with status **and reason**").
- **Every other field of that element stays deep-equal** — `version`, `commit`, `source_url`,
  `source_archive`, `source_sha256`, `signature`, `key_id`, `published_at`. Changing any of them
  alongside the transition is a violation, and the checker reports it as such rather than accepting
  the element because its `status` changed legitimately.
- **The transition is one-way and terminal.** `removed → published` is a violation. Once an element
  is `removed`, it is frozen completely, `reason` included: editing the reason text of an
  already-removed version is a violation. (Boring and conservative: a correction is a decision we
  have not made, not a hole we leave open by default.)
- Array length and ordering rules are untouched: this carve-out never permits removing, adding at a
  non-final position, or reordering elements.
- State explicitly that **this document defines the shape of a legal takedown, not who may perform
  one** — record Ludwig's decision above as the authorisation, with the revisit condition, so task
  007 does not invent an authorisation check and does not leave the mechanism unimplementable.

The document must carry a **worked example of the permitted transition** (the element before, the
element after, field by field) and a **worked counter-example** (the same transition with one other
field also changed → violation), matching the concreteness of the existing reordering and
remove-and-re-add examples.

## F2 — uniqueness within the PR, not only against history

Rule 4 currently compares a new version's `version` only against `old.versions`, so two objects
both labelled `2.0.0` added in one PR pass. Amend it to state that `version` must be unique across
**`new.versions` as a whole** — pairwise-unique among newly added elements as well as distinct from
every existing one — which is the rule its own stated rationale ("which build is 'the' 1.2.0?")
already implies.

State the comparison used: **exact string equality on the `version` field**, not semver-normalised
comparison. Note explicitly that two textually different but semver-equivalent strings (e.g. build
metadata, `1.0.0` vs `1.0.0+build.2`) are therefore *not* caught by this rule, and book that as a
question rather than inventing normalisation semantics no ADR specifies.

## Consistency sweep (part of the fix, not optional)

Both findings change what the document claims globally. Every sentence that still says or implies
*all* in-place edits are violations must be brought into line — at minimum the "Malformed edits
that are not simple truncation or prefix mismatch" section (`:145-153`), which today says an
in-place field rewrite is a violation "exactly the same way a shorter array is" with no carve-out,
and the framing in "The comparison model" and rule 1 itself. A reader must not be able to find two
sentences in this document that disagree about whether `versions[i]` can ever change.

## Acceptance criteria for this round

1. F1 addressed exactly as specified above, including the one-way/terminal rule, the required
   non-empty `reason`, the frozen-everything-else rule, the authorisation statement with Ludwig's
   decision and the revisit condition, and both worked examples.
2. F2 addressed, with the exact-string-equality comparison stated and the semver-equivalence gap
   booked as a question.
3. Consistency sweep done: quote, in the log, every sentence changed and why, and state how you
   checked no contradictory sentence remains.
4. `docs/contracts/README.md` updated if it restates any changed rule; if it does not, say so in
   the log with the command that showed it.
5. The existing suite still passes unchanged — `python3 -m unittest discover -s tests/contracts -v`
   — two runs, identical results, output in the log. No test weakened or deleted (MANAGER.md §3.5).
6. No checking logic written anywhere (still forbidden this task).
7. Task log updated so a fresh agent could resume from it alone.

**Budget:** small (<= 1 agent-session). **Status: in-progress (fix round).**
