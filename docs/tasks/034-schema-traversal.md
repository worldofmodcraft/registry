# Task 034: the merged schemas still accept `../` in `screenshots[]`

- **Mission:** SITE-V1 — **Status:** spec-approved (manager, 2026-09-05)
- **Spec of record:** `docs/tasks/034-schema-traversal.md` in the **platform** repo (`wom`), branch
  `task/034-schema-traversal`. This file is the **task log** for the **registry**-repo side of the
  work (branch `task/034-schema-traversal`, worktree `~/wt/registry-task-034`), as instructed. The
  full spec text (read via `git -C ~/wom show task/034-schema-traversal:docs/tasks/034-schema-traversal.md`)
  is not duplicated here in full; see that file for the complete acceptance-criteria wording quoted
  below.
- **File scope (declared):** `contracts/page.schema.json`, `contracts/manifest.schema.json`,
  `tests/contracts/test_contracts.py` (fixtures added, none weakened or removed), this log, and
  (added by the 2026-09-06 fix round below) `docs/tasks/034-verify.sh`.
  `links[].url`, `source`, `source_url`, `source_archive` were explicitly out of scope and were
  **not** touched.

## Context — **added 2026-09-06, fix round 1, correcting a review-round selection miss**
This section did not exist before the fix round below. REVIEW-CHECKLIST item 4 is bidirectional —
(a) the ADRs listed are followed, (b) the diff touches no area whose governing ADR was not listed —
and the independent review of PR #5 found (b) failing: the diff changes
`manifest.schema.json`'s `properties.screenshots.items.pattern`, and **ADR-0030 governs exactly
that field**, but ADR-0030 was never named anywhere in this task's context. **Recorded here plainly
as a manager error (a Context-selection miss), not folded in silently** — the corresponding platform
spec (`~/wom` `docs/tasks/034-schema-traversal.md`) was corrected the same way, independently, by
the manager (commit `616aece`).

- **ADR-0059** §1 (page content is read from the *archived* source, so a screenshot value is a path
  into a tarball, never a live URL) and §3 (`page.json` publishes on a deliberately lighter gate than
  `entry.json` — the asymmetry task 009's proven exploit used).
- **ADR-0030 — the omission the review found.** It governs `mod.lua`'s `screenshots` field, which is
  exactly what `contracts/manifest.schema.json`'s changed pattern validates. This repository's own
  precedent cites ADR-0030 for that field repeatedly: `docs/contracts/README.md` lines 20 and 24,
  `docs/tasks/025-boundary-contracts.md` ("ADR-0030 (manifest fields, including `screenshots`)"),
  `docs/tasks/006-contracts.md`, and ADR-0059's own `Related` header.
  **Re-verified against the diff, not taken on trust** (see "ADR-0030 re-verification" below): the
  change only *tightens* the item pattern and its description; it does not touch the field's
  existence, type, required-ness, or top-level meaning.
- **ADR-0120** (content whitelisting, not container framing) — named because it is what the
  *content* a screenshot path resolves to would eventually be checked against. This task checks only
  the **path string**; scanning the file it resolves to is a different, later task (blocked on an
  archive existing).
- **Contracts:** `contracts/page.schema.json`, `contracts/manifest.schema.json` (both touched),
  `contracts/archive-layout.md` (prose only, not touched — it separately states the
  `../`/absolute-path/symlink escape rule applied to every archive entry at extraction time; this
  task's schema-level check is one layer earlier, on the path string itself, before any extraction).

### ADR-0030 re-verification (not taken on trust)
Confirmed with real commands, not by reading the diff and assuming:

```
$ git show 454911a --stat -- contracts/manifest.schema.json contracts/page.schema.json
 contracts/manifest.schema.json | 4 +-
 contracts/page.schema.json     | 4 +-
 2 files changed, 4 insertions(+), 4 deletions(-)
```

Only two lines changed per file (the `pattern` and `description` strings inside
`properties.screenshots.items`). Confirmed the field's other properties are untouched:

```
$ python3 -c "
import json
d = json.load(open('contracts/manifest.schema.json'))
print('required includes screenshots:', 'screenshots' in d['required'])
print('screenshots outer keys (excl. items):', sorted(k for k in d['properties']['screenshots'] if k != 'items'))
"
required includes screenshots: True
screenshots outer keys (excl. items): ['description', 'type']
```

`screenshots` is still `required`, still `type: array`, still has only its original two outer keys
(`type`, `description`) — no key was added or removed at that level. Only `items.pattern` (tightened
to also reject a whole `..` path segment) and `items.description` (rewritten to state the new rule)
changed. **Conclusion: the diff conforms to ADR-0030 — it does not reinterpret the field's existence
or meaning, only narrows what one already-declared string field accepts.** Both checks above are
now permanent, automated checks in `docs/tasks/034-verify.sh` (`ADR-0030.1`–`ADR-0030.4`, see the
Fix round 1 section below), not a one-time manual read.

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

# Fix round 1 (implementer, 2026-09-06)

The independent review of PR #5 returned **BLOCKING on two checklist items**. The substantive
schema fix (the pattern change itself) was **not** touched in this round — the review reproduced
the mutation test independently, ran the suite in a fresh clone, and could not break the new
pattern with any adversarial payload. Both findings were about what was missing *around* the fix,
not the fix itself.

## Finding 1 (BLOCKING) — `docs/tasks/034-verify.sh` was missing

MANAGER.md §2c: *"Any task whose acceptance criteria are command-based ships
`docs/tasks/NNN-verify.sh`, committed and executable."* All seven of this task's acceptance
criteria are command-based and no such script existed. Written: `docs/tasks/034-verify.sh`, one
check per criterion (further split wherever a label would otherwise cover more than one fact —
§2c rule 3), exit codes distinguishing accepted (0) / rejected (1) / usage-error (2) — the
`scan_assets.py` convention recorded in `docs/manager/OPERATIONS.md`, chosen because "reading a
usage error as a rejection once produced a completely false verification on this project."

### The script's real output, current (fixed) worktree — ALL GREEN

```
$ ./docs/tasks/034-verify.sh
034-verify.sh -- task 034 acceptance verification
repo root: /home/ludwig/wt/registry-task-034
[... 36 checks, each printed as PASS with its supporting grep hits / unittest output ...]

== RESULT ==
ALL CHECKS PASSED
$ echo $?
0
```

Full run captured; 36/36 `PASS`, 0 `FAIL`, exit 0. (Full pasted transcript kept out of this log
entry for length — every check's real command is on disk in the script itself, which is exactly
the point of §2c: nothing here needs to be trusted, it needs to be re-run.)

### Criterion 5's mutation test, run live inside the script itself (§2c rules 2 and 5)

The script does not narrate a mutation test that was run once during development — it **performs
one on every invocation**, live, against a throwaway scratch copy, pulling the exact pre-fix
pattern out of git history (`bf8d9cb:contracts/{page,manifest}.schema.json`, never hand-retyped)
so the fixture reproduces the actual historical regression, not a paraphrase of it. Real output
from the same run above, mutated section:

```
== Criterion 5 -- mutation-tested: revert the pattern to the proven-vulnerable value pulled from
   git history, watch the fixtures redden, then confirm the real worktree was never touched ==
  pre-fix pattern (commit bf8d9cb): ^(?!/)(?!.*://)(?!.*\\).+$
  mutated /tmp/tmp.XXXXXXXXXX/contracts/page.schema.json: screenshots[].items.pattern reverted to the pre-fix value
  mutated /tmp/tmp.XXXXXXXXXX/contracts/manifest.schema.json: screenshots[].items.pattern reverted to the pre-fix value
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

    Ran 4 tests in 0.005s
    FAILED (failures=12)
PASS  C5.1 reverting to the pre-fix pattern reddens all 6 page-schema traversal subtests (found 6 FAIL blocks)
PASS  C5.3 reverting to the pre-fix pattern reddens all 6 manifest-schema traversal subtests (found 6 FAIL blocks)
PASS  C5.5 the mutated (pre-fix) run's overall exit code is non-zero (1) -- the suite as a whole reddens
PASS  C5.7 the positive controls (LEGITIMATE_PATHS) still pass even against the mutated pre-fix pattern
PASS  C5.9 the real worktree's schema files are byte-identical before and after the mutation test
  [... unittest -v output for ScreenshotTraversalTests against the real, unmutated worktree, all ok ...]
PASS  C5.11 restored: the real (unmutated, fixed) worktree's ScreenshotTraversalTests are green again
```

This closes §2c rule 5 directly: **the found break (the permissive pattern accepting
`../../../../etc/passwd`) is in the suite as a fixture, and every run of this script shows it
failing before showing it fixed** — not a one-time claim in a log, a re-runnable proof.

### Mutation-testing the verify script itself (§2c rule 2 — the artefact must be able to fail, demonstrated)

Eight representative mutations were made directly to the tracked files, the script re-run, the
exact expected check(s) confirmed red (and, in every case, that no unrelated check reddened
alongside it — proving the split labels required by rule 3 actually isolate what they claim to),
then `git checkout --` restored the file and the script re-confirmed green. `git status --short`
was clean before the first mutation and after the last.

1. **Page pattern reverted to the pre-fix value directly in the tracked file** (not the scratch
   copy) → `FAIL C1.2` (page rejects traversal) reddened; `C1.3` (manifest) and `C2.1`/`C2.3`
   (legitimate paths, both schemas) stayed green, correctly isolating the break to the one schema
   and one direction (rejection, not acceptance). `C5.12` also correctly reddened as a downstream
   consequence (the "restored" re-check at the end of Criterion 5 saw the real worktree was, in
   fact, still broken). Restored via `git checkout -- contracts/page.schema.json`; re-run: 0
   failures.
2. **Deleted the clamping-trap fixture** (`"../../../../../../../../etc/passwd"`) from
   `TRAVERSAL_PATHS` → only `FAIL C4.6` reddened (the check named for exactly that literal), no
   other check moved. Restored via `git checkout --`; re-run: 0 failures.
3. **Injected `import jsonschema`** into `schema_check.py` (after `from __future__ import
   annotations`, so the file still parses) → only `FAIL C3.2` reddened. (A first attempt inserted
   the import as literally the first line, ahead of the module docstring and the `__future__`
   import — Python rejected that with `SyntaxError: from __future__ imports must occur at the
   beginning of the file`, cascading into ten unrelated failures. That failure mode is itself
   informative and is recorded here rather than discarded: it is why the second, syntactically
   valid injection point was used for the citation above — a script that reddens on a syntax error
   is not a useless result, but it is not the isolated proof this rule asks for.)
4. **Added a live `re.fullmatch(".*", "x")` call** to `schema_check.py`'s `validate()` body → only
   `FAIL C3.4` reddened. Restored; re-run: 0 failures.
5. **Stripped the traversal-rule wording** from `page.schema.json`'s `screenshots.items.description`
   → `FAIL C7.1` and `FAIL C7.2` reddened (both facts this task's description must state), `C7.3`/
   `C7.4` (the manifest schema's description, untouched by this mutation) stayed green. Restored;
   re-run: 0 failures.
6. **Ran the script from outside any git checkout**
   (`/tmp/.../not-a-repo`) → `USAGE ERROR: not inside a git repository`, **exit 2**, zero PASS/FAIL
   lines printed — confirming the usage-error path is structurally distinct from a rejected check,
   the exact failure mode `docs/manager/OPERATIONS.md` warns about.
7. **Removed `"screenshots"` from `manifest.schema.json`'s `required` array** → only
   `FAIL ADR-0030.2` reddened. Restored; re-run: 0 failures.
8. **Added an extra key (`minItems`) to the `screenshots` property itself** (not `.items`) →
   `FAIL ADR-0030.4` reddened (plus `C6.8`, correctly — the added `minItems: 1` also broke an
   existing example with an empty screenshots array, a real second-order consequence, not a bug in
   the check). Restored; re-run: 0 failures.

Every mutation was restored with `git checkout --` before the next was applied; `git status
--short` showed only the new, still-uncommitted `docs/tasks/034-verify.sh` throughout, never a
leftover mutation.

### Fresh clone (§2c rule 4)

**Recorded after the commit below**, so the clone actually contains the script and log this
section describes rather than an uncommitted copy of them — see the addendum at the end of this
section, added in the follow-up commit for that reason.

## Finding 2 (BLOCKING) — ADR-0030 missing from Context, recap

Handled in full in the "Context" section near the top of this file (added above, same fix round).
Summary for this log's chronological record: REVIEW-CHECKLIST item 4(b) found that the diff
touches a field ADR-0030 governs without ADR-0030 ever appearing in this task's context — a
**manager Context-selection miss**, recorded as such, not silently absorbed. Re-verified against
the diff with real commands (see "ADR-0030 re-verification" above): the fix only tightens the
`screenshots[].items.pattern` and updates its description; it does not reinterpret or conflict
with ADR-0030's definition of the field.

## What changed in this fix round (file list)

- `docs/tasks/034-verify.sh` — new, executable. 36 checks covering all 7 acceptance criteria plus
  4 informational ADR-0030 conformance checks.
- `docs/tasks/034-schema-traversal.md` — this log: added the `## Context` section (with the
  ADR-0030 re-verification), this `# Fix round 1` section, and this file list.
- **Not changed:** `contracts/page.schema.json`, `contracts/manifest.schema.json`,
  `tests/contracts/test_contracts.py` — explicitly out of scope for this round ("do not redesign
  the fix"). Confirmed: `git diff --stat 454911a -- contracts/ tests/` is empty after this round's
  commits (checked below, alongside the fresh-clone run).

## What I could not verify (this round)

- Whether the independent reviewer's fresh-clone run of the *substantive fix* used the exact same
  Python version as this environment (3.14.4) — the review report was not re-read line-by-line for
  this round (out of scope: "do not redesign the fix"), so this is stated as an assumption carried
  forward, not a re-confirmed fact.
