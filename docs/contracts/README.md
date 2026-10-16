# Registry data contracts

The JSON Schemas and prose rules documents in `contracts/` are the written agreement between the
registry side (CI, the build pipeline), the artifact store, and the site side of World of Modcraft:
the shapes and boundary agreements every side codes against, decided once, here, instead of
against each other's code. Task 006 defined the first four (the ones that block everything); task
025 wrote the remaining six that the dependency graph (`docs/architecture/depgraph.md` in the
platform repository) already named but nobody had written yet; task 032 wrote the eleventh, for
edge E16 — added to the graph by amendment after task 006's review found it had no contract at
all. None of the three tasks implements checking logic —
task 007a (built) wrote the shape checkers in `tools/registry/` (see "The registry shape checkers"
below), task 007b the ownership checker, task 008 the build pipeline, task 009 the site
build, all reading these files. Task 008a's pipeline core is built: see `docs/pipeline/build-pipeline.md` (E7 naming,
E9 signing, E11 archive interior) and `docs/validation/manifest-reader.md` (E1). See `docs/tasks/006-contracts.md`, `docs/tasks/
025-boundary-contracts.md` and `docs/tasks/032-ownership-contract.md` for the full task logs.

## Files

| File | What it is | Governing ADR | Depgraph edge(s) |
|---|---|---|---|
| `contracts/entry.schema.json` | The registry entry for one mod: `{ id, owner, versions[] }`, stored at `mods/<namespace>.<name>/entry.json`. Task 057: a version object is in one of four states (`pending`, `published`, `removed`, `rejected`), each with an exact key set, enforced by a four-branch `oneOf`. | ADR-0058 Section 2 (owner shape, numeric account id), ADR-0041 (version fields, hashes, signature), ADR-0121 (version lifecycle), ADR-0119 (reserved namespaces reuse this shape unchanged) | E2, E8, E10 |
| `contracts/page.schema.json` | The editable page content for one mod: description, screenshots, tags, links, deprecated. Stored at `mods/<namespace>.<name>/page.json`. **Not** append-only — see the file's own description. | ADR-0059 Section 2-3 | E3, E10 |
| `contracts/manifest.schema.json` | The subset of `mod.lua`'s fields meaningful to the registry/site without a kernel. | ADR-0030 (subset named in this task's acceptance criterion 4), ADR-0049 (licence) | E1 |
| `contracts/append-only.rules.md` | Field-level rules for what a PR may change in `entry.json`, precise enough for task 007 to implement a diff checker directly from it. Task 057: versions are born `pending` only; three permitted in-place transitions, T1 `pending -> published` (pipeline write-back), T2 `published -> removed` (takedown) and T3 `pending -> rejected`, each with exact key sets; T1 and T3 are rejected by every checker until `ownership.md` carries the pipeline carve-out (fail closed). | ADR-0041, ADR-0121 | E4 |
| `contracts/ownership.md` | Who may touch each namespace a PR modifies, as eleven numbered verdict rules (`R1`-`R11`) with one rejection-taxonomy row each, plus eight checker rules (`I1`-`I8`): PR author's numeric `(provider, id)` compared against `old.owner`, never a username, never `new.owner`; the directory path as the single authoritative source for a namespace, with `entry.json`'s `id` required to agree; what a first publish binds (ADR-0058 Section 3's confirmation text, quoted) including the case-insensitive namespace/username comparison; the reserved-namespace authorisation path (org membership, not id-equality, with a mandatory `302` arm) for `mc`/`test`; `page.json` PRs, including the namespace that has no `entry.json`; who may open a legally-mandated takedown PR, and the precedence that makes that ruling operative rather than merely stated (`R11` authorises the platform's own identity against **any** namespace, owned or not — a GitHub organisation is not a member of itself, so `R7` rejects that identity for `mc:`/`test:` and the lift is what makes the platform's own takedown possible there — and it lifts `R3`/`R7` for the takedown mutation and for nothing else, declared at both ends in the `Precedence: Rx over Ry` form the document's `T10`-`T16` checks enforce; opening is all `R11` decides, MANAGER.md §7's written approval still gates the merge); the required regression fixture (matching username, differing id) for task 007. | ADR-0030, ADR-0039, ADR-0041, ADR-0058 Section 2-3, ADR-0059 Section 3, ADR-0119 | E16 |
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
import of it, and what extra JSON Schema keywords it supports (`enum`, `minLength`, `maxLength`, `oneOf` (task 057),
`minItems`) that task 002's contract never needed.

## The registry shape checkers (task 007a)

`tools/registry/` holds the offline checkers that implement `contracts/append-only.rules.md` (E4),
`entry.schema.json` / `page.schema.json` (E2, E3) and `ownership.md` R1's path form (E16, path half),
with a shared verdict shape and exit codes in `tools/registry/report.py` (also used by 007b):

```
python3 tools/registry/cli.py classify    --reserved-file MERGE_BASE/reserved-namespaces.json PATH...
python3 tools/registry/cli.py schema      --root PR_CHECKOUT PATH...
python3 tools/registry/cli.py append-only --old-root MERGE_BASE_CHECKOUT --new-root PR_CHECKOUT PATH...
```

The caller must build the changed-path list with `git diff --no-renames` (task 039 wires it): a rename
then appears as a deletion plus a creation, which append-only rejects. Symlinked `entry.json`/`page.json`
files are rejected, never read through, and duplicate JSON object keys are rejected. String patterns use
ECMA-262 end-of-input `$` (a trailing newline never matches), enforced in `tools/registry/schema.py`.

Exit `0` accepted, `1` rejected, `2` usage or internal error (never a rejection). The verdict is JSON on
stdout. `classify` yields one class: `entry`, `page-only`, `reserved-namespace` or `other` (always a
rejection). `append-only` classifies **each** `versions[]` element (`unchanged`, `appended`, `T1`, `T2`,
`T3`, `violation` with the list of rule ids) and returns `authority_required`, the transitions present.
**An `append-only` exit 0 with a non-empty `authority_required` is not a merge signal**: T1/T3 are
shape-legal here and rejected at the authority layer (007b, fail closed until the pipeline carve-out
exists); a T2 needs the R11 takedown authority. Tests: `python3 -m unittest discover -s tests/registry`;
the verification artefact is `docs/tasks/007a-verify.sh` (`--mutate` for the mutation proof).

## Provider neutrality (ADR-0058 Section 4)

None of these schemas require `owner.provider` or any URL field to be GitHub-specific. Every
provider-facing field (`owner.provider`, `versions[].source_url`, `manifest.source`) is a
free-form string or a generic URL pattern, never an enum naming specific hosts —
`tests/contracts/test_contracts.py`'s `ProviderNeutralityTests` asserts this structurally (no
`enum`/`const` under those properties) as well as by example (a working GitLab/sourcehut entry).

## What is deliberately not here

- **No checking logic in the contracts themselves.** Task 006, task 025 and task 032 are
  prose-and-schema only (the live `gh api` / `curl` commands pasted in `contracts/ownership.md` are
  one-off verification of environmental facts made *while writing* the document). The checking logic
  lives elsewhere: **built** (task 007a) are the PR classifier, schema validation and append-only
  checkers in `tools/registry/`; **built** (task 007b) is the ownership checker
  (`tools/registry/ownership.py`, CLI `ownership_cli.py`: R1-R11, the checker-constraining invariants, and the
  fail-closed rejection of every T1/T3 for every author until task 008b adds the pipeline carve-out). Its R11
  takedown authority is injected configuration that defaults to *nobody* (which `pulls.user.id` the platform's
  own takedown PRs carry is an open question for Ludwig and task 039); **still to come** are the GitHub Actions
  workflow that composes the shape and ownership verdicts, PR comments and the one live org-membership API call
  (task 039), the pipeline carve-out in `ownership.md` (task 008b), the build pipeline's remaining parts (task
  008) and the site build (task 009: archive extraction, rendering, deploy). The checkers call no forge API
  and reach no network; they take parsed files, paths and an injected membership answer as input.
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
