# Task 034: the merged schemas still accept `../` in `screenshots[]`

- **Mission:** SITE-V1 — **Status:** spec-approved (manager, 2026-09-05)
- **Spec of record:** `docs/tasks/034-schema-traversal.md` in the **platform** repo (`wom`), branch
  `task/034-schema-traversal`. This file is the **task log** for the **registry**-repo side of the
  work (branch `task/034-schema-traversal`, worktree `~/wt/registry-task-034`), as instructed. The
  full spec text (read via `git -C ~/wom show task/034-schema-traversal:docs/tasks/034-schema-traversal.md`)
  is not duplicated here in full; see that file for the complete acceptance-criteria wording quoted
  below.
- **File scope (declared):** `contracts/page.schema.json`, `contracts/manifest.schema.json`,
  `tests/contracts/test_contracts.py` (fixtures added, none weakened or removed), this log.
  `links[].url`, `source`, `source_url`, `source_archive` were explicitly out of scope and were
  **not** touched.

## The hole (as proven, task 009 review; reproduced independently by the manager)

Both `contracts/page.schema.json` and `contracts/manifest.schema.json` validated
`screenshots[].items` with:

```
^(?!/)(?!.*://)(?!.*\\).+$
```

This blocks a leading `/`, a URL scheme, and a backslash — but never `../`.

## Validator used (criterion 3)

The repository ships no `jsonschema` package (confirmed: `grep -rl jsonschema . --include=*.py`
finds only `tests/validation/schema_check.py` and `tests/contracts/schema_check.py`, the two
stdlib-only hand-rolled validators, plus prose in `docs/validation/asset-scanner.md` and
`docs/tasks/002-asset-scanner.md` that only *mentions* the package as not installed). The existing
schema test suite (`tests/contracts/test_contracts.py`) imports `validate` /
`SchemaValidationError` from `tests/contracts/schema_check.py`. That is the validator used for
every command below — the same one that will run in CI (`python3 -m unittest discover -s
tests/contracts`). `schema_check.py`'s own docstring records that it matches `pattern` with
`re.search`, not `re.fullmatch`, so every pattern in this repo (old and new) is written anchored
(`^...$`) — the new pattern follows the same convention.

## Step 0 — read the vulnerable pattern and the existing suite

```
$ grep -n "pattern" contracts/page.schema.json contracts/manifest.schema.json
contracts/manifest.schema.json:219:        "pattern": "^(?!/)(?!.*://)(?!.*\\\\).+$",
contracts/page.schema.json:27:        "pattern": "^(?!/)(?!.*://)(?!.*\\\\).+$",
```

Baseline suite, before any change:

```
$ python3 -m unittest discover -s tests/contracts -v 2>&1 | tail -5
----------------------------------------------------------------------
Ran 23 tests in 0.008s

OK
```

Baseline example counts (criterion 6, "before"):

```
$ ls contracts/examples/page/valid/*.json | wc -l      -> 2
$ ls contracts/examples/page/invalid/*.json | wc -l    -> 5
$ ls contracts/examples/manifest/valid/*.json | wc -l  -> 3
$ ls contracts/examples/manifest/invalid/*.json | wc -l -> 6
```

## Order of work followed (Ludwig's rule: fixtures before fix, shown failing first)

### Step 1 — write the fixtures, run them against the still-vulnerable pattern (criterion 4)

Added `ScreenshotTraversalTests` to `tests/contracts/test_contracts.py`, validating directly
against `SCHEMAS["page"]["properties"]["screenshots"]["items"]` and the equivalent manifest
subschema (no full document needed — the field under test is the item schema itself):

```python
TRAVERSAL_PATHS = [
    "../etc/passwd",
    "a/../../etc/passwd",
    "./../x",
    "a/..",
    "..",
    "../../../../../../../../etc/passwd",  # the clamping-trap case, see below
]

LEGITIMATE_PATHS = [
    "assets/screenshots/shop.png",
    "docs/img/a.b/c.png",
    "screenshots/v1.2.3.png",
    "a..b/c.png",
]
```

Four test methods: `test_traversal_paths_rejected_in_{page,manifest}_schema` (each must raise
`SchemaValidationError` for every path in `TRAVERSAL_PATHS`) and
`test_legitimate_paths_still_accepted_in_{page,manifest}_schema` (each must validate cleanly for
every path in `LEGITIMATE_PATHS`).

Ran against the still-unmodified (vulnerable) schemas:

```
$ python3 -m unittest discover -s tests/contracts -k ScreenshotTraversalTests -v
test_legitimate_paths_still_accepted_in_manifest_schema ... ok
test_legitimate_paths_still_accepted_in_page_schema ... ok
test_traversal_paths_rejected_in_manifest_schema ...
  (path='../etc/passwd') ... FAIL
  (path='a/../../etc/passwd') ... FAIL
  (path='./../x') ... FAIL
  (path='a/..') ... FAIL
  (path='..') ... FAIL
  (path='../../../../../../../../etc/passwd') ... FAIL
test_traversal_paths_rejected_in_page_schema ...
  (path='../etc/passwd') ... FAIL
  (path='a/../../etc/passwd') ... FAIL
  (path='./../x') ... FAIL
  (path='a/..') ... FAIL
  (path='..') ... FAIL
  (path='../../../../../../../../etc/passwd') ... FAIL

----------------------------------------------------------------------
Ran 4 tests in 0.003s

FAILED (failures=12)
```

Full-suite run at this point (fixtures present, pattern still vulnerable):

```
$ python3 -m unittest discover -s tests/contracts -v 2>&1 | tail -6
----------------------------------------------------------------------
Ran 27 tests in 0.012s

FAILED (failures=12)
```

27 = 23 pre-existing + 4 new test methods; all 12 sub-test failures are the traversal fixtures, on
both schemas; the 8 legitimate-path and existing-example sub-tests are unaffected. This is the
"green suite, red fixture" state criterion 4 requires before the fix — confirmed with real command
output, not narrated.

### Step 2 — change the pattern, update descriptions (criteria 1, 2, 7)

New pattern, both schemas:

```
^(?!/)(?!.*://)(?!.*\\)(?!.*(?:^|/)\.\.(?:/|$)).+$
```

Reasoning verified by running the real regex (not by inspection): the added negative lookahead
`(?!.*(?:^|/)\.\.(?:/|$))` matches only when a **whole path segment** equals `..` — bounded by
`^` or `/` on the left and `/` or `$` on the right — so `a..b` (no `/` or string-boundary directly
around the `..`) never matches it, while `..`, `../x`, `a/..`, `a/../b` all do. Confirmed:

```
$ python3 /tmp/claude-1000/-home-ludwig-wom/e511e5f9-16f3-4c50-8dc1-f45555c96f42/scratchpad/test_pattern.py
REJECT? ../etc/passwd                              -> REJECTED (pattern search=None)
REJECT? a/../../etc/passwd                          -> REJECTED (pattern search=None)
REJECT? ./../x                                      -> REJECTED (pattern search=None)
REJECT? a/..                                        -> REJECTED (pattern search=None)
REJECT? ..                                          -> REJECTED (pattern search=None)
REJECT? ../../../../../../../../etc/passwd          -> REJECTED (pattern search=None)
ACCEPT? assets/screenshots/shop.png                 -> MATCH (good)
ACCEPT? docs/img/a.b/c.png                          -> MATCH (good)
ACCEPT? screenshots/v1.2.3.png                      -> MATCH (good)
ACCEPT? a..b/c.png                                  -> MATCH (good)
```

(This was a scratch script run with `python3`'s own `re` module — the identical engine
`schema_check.py` uses, since `schema_check.py`'s `pattern` check is `re.search(schema["pattern"],
instance)`. It was a sanity check before editing the JSON files, superseded by the real
`unittest` run below which is the actual acceptance evidence.)

Edited `contracts/page.schema.json` and `contracts/manifest.schema.json`:
`properties.screenshots.items.pattern` changed to the new pattern in both files;
`properties.screenshots.items.description` in both files rewritten to state the traversal rule
explicitly (a whole `..` path segment is rejected anywhere in the path; two dots inside a longer
segment such as `a..b/c.png` or `screenshots/v1.2.3.png` are explicitly called out as still valid)
— criterion 7.

Both files re-checked as parseable JSON immediately after editing:

```
$ python3 -c "import json; json.load(open('contracts/page.schema.json')); json.load(open('contracts/manifest.schema.json')); print('both schemas parse as valid JSON')"
both schemas parse as valid JSON
```

### Step 3 — full suite after the fix (criteria 1, 2, 4)

```
$ python3 -m unittest discover -s tests/contracts -v 2>&1 | tail -10
test_legitimate_paths_still_accepted_in_manifest_schema ... ok
test_legitimate_paths_still_accepted_in_page_schema ... ok
test_traversal_paths_rejected_in_manifest_schema ... ok
test_traversal_paths_rejected_in_page_schema ... ok

----------------------------------------------------------------------
Ran 27 tests in 0.009s

OK
```

All 27 tests pass, including every pre-existing test unmodified. Ran twice back to back to confirm
determinism (this repo's own `DeterminismTests` convention, extended here to the whole-suite
level):

```
$ python3 -m unittest discover -s tests/contracts 2>&1 | tail -5   (run 1)
...........................
Ran 27 tests in 0.008s
OK
$ python3 -m unittest discover -s tests/contracts 2>&1 | tail -5   (run 2)
...........................
Ran 27 tests in 0.008s
OK
```

### Step 4 — mutation test (criterion 5)

Per the task's explicit instruction, copied `contracts/` and `tests/` into a scratch directory
(`/tmp/claude-1000/-home-ludwig-wom/e511e5f9-16f3-4c50-8dc1-f45555c96f42/scratchpad/mutation-034/`, **not** inside this worktree or any other worktree) and
reverted only the `screenshots[].items.pattern` string in both schema files back to the exact old
vulnerable value (`^(?!/)(?!.*://)(?!.*\\).+$`), leaving the new fixtures untouched. Confirmed the
mutated files still parse as JSON, then ran the traversal fixtures against them:

```
$ python3 -m unittest discover -s tests/contracts -k ScreenshotTraversalTests -v 2>&1 | tail -20
FAIL: test_traversal_paths_rejected_in_page_schema (path='../../../../../../../../etc/passwd')
AssertionError: SchemaValidationError not raised : '../../../../../../../../etc/passwd' should be
rejected as path traversal but validated cleanly
----------------------------------------------------------------------
Ran 4 tests in 0.004s

FAILED (failures=12)
```

All 12 traversal sub-tests redden against the reverted (vulnerable) pattern, in the identical
pattern to Step 1 — proving the new fixtures actually exercise the fix and are not vacuously
true. (A full-suite run in that same scratch copy also reported one unrelated `ERROR` in
`ReservedNamespacesTests.setUpClass` — an artifact of the scratch copy containing only `contracts/`
and `tests/`, not the full repository, so `reserved-namespaces.json` at the real repo root was
absent from the scratch tree. That error is a scratch-copy artifact, not a finding about this
task's change, and is unrelated to `ScreenshotTraversalTests`, which is what criterion 5 requires
and which produced the 12/12 red result above.)

Mutation-test artifacts (the mutated schema copies) were left in `/tmp/claude-1000/-home-ludwig-wom/e511e5f9-16f3-4c50-8dc1-f45555c96f42/scratchpad/mutation-034/`
and were never committed; the real worktree's schema files were never touched during this step —
confirmed by re-running the full suite in the real worktree immediately after (Step 3's second run,
above, plus a final re-run before commit, both `OK`).

### Step 5 — examples still validate (criterion 6)

Example counts, same command as the "before" baseline in Step 0, run again after the fix:

```
$ ls contracts/examples/page/valid/*.json | wc -l      -> 2   (unchanged)
$ ls contracts/examples/page/invalid/*.json | wc -l    -> 5   (unchanged)
$ ls contracts/examples/manifest/valid/*.json | wc -l  -> 3   (unchanged)
$ ls contracts/examples/manifest/invalid/*.json | wc -l -> 6  (unchanged)
```

No example files were added, removed, or edited by this task. `PageExampleTests` and
`ManifestExampleTests` in the Step 3 full-suite run (`OK`, all 27 passing) prove every valid
example still validates and every invalid example is still rejected against both edited schemas —
same counts before and after, all green.

## Acceptance criteria — final checklist

1. **Both schemas reject path traversal** — done. `test_traversal_paths_rejected_in_page_schema`
   and `test_traversal_paths_rejected_in_manifest_schema`, both `ok` in Step 3, covering
   `../etc/passwd`, `a/../../etc/passwd`, `./../x`, `a/..`, and bare `..` (plus the clamping-trap
   case).
2. **Legitimate paths still validate** — done. `test_legitimate_paths_still_accepted_in_page_schema`
   and the manifest equivalent, both `ok` throughout (they passed even before the fix, and still
   pass after), covering `assets/screenshots/shop.png`, `docs/img/a.b/c.png`,
   `screenshots/v1.2.3.png`, and `a..b/c.png`.
3. **Real validator, not reasoning about the regex** — done. Every claim above is a pasted
   `unittest` or `python3 -c` command run against `tests/contracts/schema_check.py`, the same
   engine the existing suite and CI use.
4. **Fixtures added before the pattern change, shown failing first** — done, Step 1: 12/27 failing
   (all in the new traversal fixtures) before the edit, 0/27 failing after.
5. **Mutation-tested** — done, Step 4: reverting to the old pattern in a scratch copy reddens the
   same 12 traversal sub-tests, using the clamping-safe deep-`../` fixture rather than a real
   filesystem lookup.
6. **`contracts/examples/` still validates, counts shown** — done, Step 5: 2/5 (page valid/invalid)
   and 3/6 (manifest valid/invalid), identical before and after, all passing per their claimed
   validity.
7. **Field descriptions updated** — done, Step 2: both schemas' `screenshots.items.description`
   now state the traversal rule and explicitly note that dots inside a segment are not a
   traversal segment.

## What changed (file list)

- `contracts/page.schema.json` — `properties.screenshots.items.pattern` and `.description`.
- `contracts/manifest.schema.json` — `properties.screenshots.items.pattern` and `.description`.
- `tests/contracts/test_contracts.py` — added `ScreenshotTraversalTests` (new class, nothing
  removed or weakened; all 23 pre-existing tests are byte-for-byte the tests that existed before
  this task, unmodified).
- `docs/tasks/034-schema-traversal.md` — this log (new file in this repo).

## Questions

None requiring Ludwig's input arose during this task — the spec's scope, acceptance criteria, and
trap were unambiguous and the fix stayed inside the declared file scope.

## What I could not verify

- Whether any **CI workflow file** actually invokes `python3 -m unittest discover -s
  tests/contracts` — no `.yml`/`.yaml` workflow file exists anywhere in this worktree
  (`find . -iname "*.yml" -o -iname "*.yaml"` returned nothing), so I could not confirm this
  against a real CI config. The task log for task 006 and the file's own docstring both name this
  exact command as the way the suite is run; I have no stronger evidence than that and am stating
  it plainly rather than presenting it as confirmed CI behaviour.
- Whether any consumer outside this repository (e.g. the site build) reads
  `page.schema.json`/`manifest.schema.json` directly at build time in a way that would need a
  cache-bust or version bump on schema change — out of this task's declared scope
  (`links[].url`, `source`, `source_url`, `source_archive` were the only explicitly-named
  out-of-scope fields; consumers of the schema files themselves were not mentioned in the spec, so
  I did not investigate further, per MANAGER.md §3.3's "stop and report, do not fix" — reporting
  it here as unverified rather than silently assuming it is fine).
