# Registry data contracts

The JSON Schemas and rules documents in `contracts/` are the written agreement between the
registry side (CI, the build pipeline) and the site side of World of Modcraft: the shapes both
sides code against, decided once, here, instead of against each other's code. This task
(006) defines the shapes; it implements no checking logic — task 007 builds the CI gates and
diff checker that read these files. See `docs/tasks/006-contracts.md` for the full task log.

## Files

| File | What it is | Governing ADR | Depgraph edge(s) |
|---|---|---|---|
| `contracts/entry.schema.json` | The registry entry for one mod: `{ id, owner, versions[] }`, stored at `mods/<namespace>.<name>/entry.json`. | ADR-0058 Section 2 (owner shape, numeric account id), ADR-0041 (version fields, hashes, signature), ADR-0119 (reserved namespaces reuse this shape unchanged) | E2, E8, E10 |
| `contracts/page.schema.json` | The editable page content for one mod: description, screenshots, tags, links, deprecated. Stored at `mods/<namespace>.<name>/page.json`. **Not** append-only — see the file's own description. | ADR-0059 Section 2-3 | E3, E10 |
| `contracts/manifest.schema.json` | The subset of `mod.lua`'s fields meaningful to the registry/site without a kernel. | ADR-0030 (subset named in this task's acceptance criterion 4), ADR-0049 (licence) | E1 |
| `contracts/append-only.rules.md` | Field-level rules for what a PR may change in `entry.json`, precise enough for task 007 to implement a diff checker directly from it. | ADR-0041 | E4 |
| `reserved-namespaces.json` (repo root) | The platform-owned namespace list (`mc`, `test`), each bound to the organisation's numeric account id. | ADR-0119 Section 1 | — (read by registry-ci, not itself a depgraph edge) |
| `contracts/validation-report.schema.json` | The asset scanner's report shape (task 002, unrelated to this task except as a style precedent this task's schemas follow). | ADR-0004, ADR-0120 | E5, E6 |

## Worked examples

`contracts/examples/<schema-name>/{valid,invalid}/*.json`, one directory per schema above minus
`validation-report` and `append-only.rules.md` (a rules document has no schema of its own to
validate examples against) and `reserved-namespaces.json` (its examples are the one real file
plus the schema in `tests/contracts/`, not a separate examples directory).

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

- **No checking logic.** No script in this task's scope reads a PR diff, calls a git host's API,
  or enforces anything at merge time. That is task 007.
- **No signature-format contract.** `entry.schema.json`'s `signature`/`key_id` fields are
  non-empty strings only; their exact encoding (minisign/Ed25519, per depgraph edge E9) belongs
  to `contracts/signature-format.md`, a different, already-decided contract outside this task's
  declared file scope.
- **No full `mod.lua` manifest.** `manifest.schema.json` is deliberately the ADR-0030 subset this
  task's acceptance criterion 4 names — fields meaningful only with a kernel (`declares`,
  `depends`, `permissions`, `server`/`client` blocks, …) are future work, once the kernel exists.
