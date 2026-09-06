# Registry data contracts

The JSON Schemas and prose rules documents in `contracts/` are the written agreement between the
registry side (CI, the build pipeline), the artifact store, and the site side of World of Modcraft:
the shapes and boundary agreements every side codes against, decided once, here, instead of
against each other's code. Task 006 defined the first four (the ones that block everything); task
025 wrote the remaining six that the dependency graph (`docs/architecture/depgraph.md` in the
platform repository) already named but nobody had written yet; task 032 wrote the eleventh, for
edge E16 — added to the graph by amendment after task 006's review found it had no contract at
all. None of the three tasks implements checking logic —
task 007 builds the CI gates and diff checker, task 008 the build pipeline, task 009 the site
build, all reading these files. See `docs/tasks/006-contracts.md`, `docs/tasks/
025-boundary-contracts.md` and `docs/tasks/032-ownership-contract.md` for the full task logs.

## Files

| File | What it is | Governing ADR | Depgraph edge(s) |
|---|---|---|---|
| `contracts/entry.schema.json` | The registry entry for one mod: `{ id, owner, versions[] }`, stored at `mods/<namespace>.<name>/entry.json`. | ADR-0058 Section 2 (owner shape, numeric account id), ADR-0041 (version fields, hashes, signature), ADR-0119 (reserved namespaces reuse this shape unchanged) | E2, E8, E10 |
| `contracts/page.schema.json` | The editable page content for one mod: description, screenshots, tags, links, deprecated. Stored at `mods/<namespace>.<name>/page.json`. **Not** append-only — see the file's own description. | ADR-0059 Section 2-3 | E3, E10 |
| `contracts/manifest.schema.json` | The subset of `mod.lua`'s fields meaningful to the registry/site without a kernel. | ADR-0030 (subset named in this task's acceptance criterion 4), ADR-0049 (licence) | E1 |
| `contracts/append-only.rules.md` | Field-level rules for what a PR may change in `entry.json`, precise enough for task 007 to implement a diff checker directly from it. | ADR-0041 | E4 |
| `contracts/ownership.md` | Who may touch each namespace a PR modifies: PR author's numeric `(provider, id)` compared against `old.owner`, never a username, never `new.owner`; what a first publish binds (ADR-0058 Section 3's confirmation text, quoted); the reserved-namespace authorisation path (org membership, not id-equality) for `mc`/`test`; the required regression fixture (matching username, differing id) for task 007. | ADR-0058 Section 2-3, ADR-0119 | E16 |
| `contracts/artifact-naming.md` | Deterministic release tag and asset filename scheme for the archived source tarball and its signature, in the org's artifact-store repository. Fixes the `namespace:name` id's `:` (illegal in a git ref) as `.` for naming, and rejects Windows-reserved-device-name namespaces outright. | ADR-0041 | E7 |
| `contracts/signature-format.md` | The exact minisign/Ed25519 detached-signature byte layout: the four-line file format, this project's trusted-comment grammar (`format=1;id=...;version=...;sha256=...`), what `entry.json`'s `signature` field actually stores, `key_id` derivation, and the full verifier rejection list. | ADR-0041 | E9 |
| `contracts/archive-layout.md` | The archived source tarball's interior: the single-top-level-directory root convention, how a manifest/page screenshot path resolves to an archive entry, missing-file behaviour, and the `../`/absolute-path/symlink escape rule applied to every entry during extraction. | ADR-0059 Section 1, ADR-0030 | E11 |
| `contracts/rebuild-trigger.md` | The exact `repository_dispatch` event type (`registry-updated`) and two-field payload (`commit`, `triggered_at`) a registry merge sends to the site repository, and the malformed/absent-payload degrade. | — | E12 |
| `contracts/site-output.md` | What a valid site build output is: the full `dist/` tree published verbatim, `CNAME`'s exact content, and the `.nojekyll` requirement (without it, GitHub Pages' Jekyll processing silently drops Astro's `_astro/` assets). | — | E13 |
| `contracts/url-scheme.md` | The public URL scheme: `https://worldofmodcraft.com`, `/mods/<namespace>/<name>` with no trailing slash as canonical, and why escaping is unreachable under the current `id` pattern. | — | E14 |
| `reserved-namespaces.json` (repo root) | The platform-owned namespace list (`mc`, `test`), each bound to the organisation's numeric account id. | ADR-0119 Section 1 | — (read by registry-ci, not itself a depgraph edge) |
| `contracts/validation-report.schema.json` | The asset scanner's report shape (task 002, unrelated to this task except as a style precedent this task's schemas follow). | ADR-0004, ADR-0120 | E5, E6 |

## Worked examples

`contracts/examples/<schema-name>/{valid,invalid}/*.json`, one directory per **JSON Schema** file
above (`entry.schema.json`, `page.schema.json`, `manifest.schema.json`,
`validation-report.schema.json`) minus `reserved-namespaces.json` (its examples are the one real
file plus the schema in `tests/contracts/`, not a separate examples directory). **None of the
eight prose `.md` documents** — `append-only.rules.md`, task 025's six (`artifact-naming.md`,
`signature-format.md`, `archive-layout.md`, `rebuild-trigger.md`, `site-output.md`,
`url-scheme.md`), and task 032's `ownership.md` — **have a schema of their own to validate
examples against**, so none has an
examples directory; each states its own worked examples and counter-examples inline instead,
where one is useful.

Every example file is `{ "_comment": "<why this file exists>", "example": { ... } }` — the
`_comment` states in prose what the example demonstrates (a valid case) or which rule/ADR clause
it violates (an invalid case), and only the `example` object is validated against the schema.
This wrapper keeps the comment colocated and machine-checkable (every example's `_comment` is
asserted non-empty in the test suite) without JSON's lack of native comments contaminating the
object actually being validated.

## Running the tests

```
python3 -m unittest discover -s tests/contracts -v
```

Offline, standard-library only — see `tests/contracts/schema_check.py`'s module docstring for
why this is a separate copy of task 002's `tests/validation/schema_check.py` rather than an
import of it, and what extra JSON Schema keywords it supports (`enum`, `minLength`, `maxLength`,
`minItems`) that task 002's contract never needed.

## Provider neutrality (ADR-0058 Section 4)

None of these schemas require `owner.provider` or any URL field to be GitHub-specific. Every
provider-facing field (`owner.provider`, `versions[].source_url`, `manifest.source`) is a
free-form string or a generic URL pattern, never an enum naming specific hosts —
`tests/contracts/test_contracts.py`'s `ProviderNeutralityTests` asserts this structurally (no
`enum`/`const` under those properties) as well as by example (a working GitLab/sourcehut entry).

## What is deliberately not here

- **No checking logic, in any of the three tasks.** No file here reads a PR diff, calls a git
  host's API, extracts a real archive, verifies a real signature, or enforces anything at merge or
  build time. Task 006, task 025 and task 032 are all prose-and-schema only (the live `gh api` /
  `curl` commands pasted in `contracts/ownership.md` are one-off verification of environmental
  facts made *while writing* the document, not checking logic the document itself runs); task 007
  builds the registry CI gates and diff checker, task 008 the build pipeline (archiving, signing),
  task 009 the site build (archive extraction, rendering, deploy) — all of them coding against the
  contracts indexed above.
- **No full `mod.lua` manifest.** `manifest.schema.json` is deliberately the ADR-0030 subset this
  task's acceptance criterion 4 names — fields meaningful only with a kernel (`declares`,
  `depends`, `permissions`, `server`/`client` blocks, …) are future work, once the kernel exists.
- **No real key material, token, or secret anywhere**, in `contracts/signature-format.md` or
  otherwise — every example value in that file is fabricated placeholder data, explicitly marked
  as such.
- **`contracts/pipeline-trigger.md` (E15) is not part of either task** and does not exist yet —
  it governs a different edge (registry merge to the registry's own build pipeline, a
  same-repository `push` trigger, not a cross-repository `repository_dispatch`) and is named in
  `contracts/rebuild-trigger.md` only to head off confusing the two.
