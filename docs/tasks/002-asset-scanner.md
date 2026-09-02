# Task 002: Asset scanner — file typing by magic bytes, whitelist enforcement, GLB payload walk

- **Mission:** SITE-V1 — **Status:** spec-approved (M1 landed 2026-09-02; the registry repo exists)
- **Agent / model:** implementer / sonnet  (escalation path: implementer-strong, two-strike rule only)
- **Budget:** medium (≤ 3 agent-sessions)
- **Branch / worktree:** task/002-asset-scanner / /home/ludwig/wt/registry-task-002 (repo: worldofmodcraft/registry)
- **Graph:** implements node **N4** (`validation-core`), asset-scanning half only. Declares edges
  **E5/E6** (`contracts/validation-report.schema.json`). Touches no other edge.

## Objective
A standalone, offline-runnable scanner exists that walks a directory tree, identifies every
file's real type by **magic bytes**, accepts only whitelisted types, and rejects Blizzard formats
by name — including payloads embedded inside GLB containers. It emits a machine-readable report
against the E5/E6 contract and exits non-zero on any rejection. It is the component that makes
ADR-0004 ("never a single byte of Blizzard data") mechanical rather than aspirational, so it is
written and tested before anything that calls it.

## Context to load (exhaustive)
- ADRs: **0004** (own assets only; whitelist; magic bytes not extensions), **0040** §3 (validation
  order; look inside GLB), **0041** (what the pipeline promises), **0061** (AI-generated assets are
  permitted — the scanner must not try to judge provenance), **0116** (why this becomes a gate),
  **0103** (boring, restartable), **0115** §1 (measure outcomes: counters read reality)
- Files: `docs/architecture/depgraph.md` (N4, E5/E6), `docs/tasks/MISSION-worldofmodcraft-site-v1.md`
  §3 key facts, §4 D2 step 3, §5.2 forbidden shortcuts, §7.1 acceptance
- Survey docs: none required (no existing code to survey)

## File scope (declared)
Inside the registry working copy only:
- `tools/validation/scan_assets.py` (or `.mjs` — the agent picks one runtime and states why in the log)
- `tools/validation/magic.py` — the signature table, data-driven, one row per format
- `contracts/validation-report.schema.json`
- `tests/validation/**` — fixtures and tests
- `docs/validation/asset-scanner.md` — what it accepts, what it rejects, how to run it
Anything outside this list = stop and report.

## Acceptance criteria
Each is demonstrated by a command whose output is pasted into the task log.

1. **Whitelist accepted.** A tree containing valid PNG, OGG, glTF (`.gltf` JSON), GLB, `.md`,
   `.json`, `.lua`, `.txt` scans clean, exit code 0.
2. **Blizzard formats rejected by magic bytes, under innocent extensions.** Files carrying
   DBC (`WDBC`), MPQ (`MPQ\x1a`), BLP (`BLP2`), M2 (`MD20`/`MD21`) and WMO (`MVER`+`MOHD`)
   signatures, each named `screenshot.png`, are every one rejected, and the report names the
   detected format (not merely "unknown"). Exit code non-zero.
3. **GLB interior is walked.** A structurally valid GLB whose BIN chunk embeds a BLP payload is
   rejected with the embedded format named and the chunk offset reported. A GLB whose embedded
   payloads are all whitelisted passes. *(Mission §5.2 forbids skipping this; a scanner that
   passes criterion 2 but not this one is not done.)*
4. **Extension is never trusted, in both directions.** A real PNG named `data.dbc` is
   **accepted** (content is what counts); a real DBC named `art.png` is rejected. Both demonstrated.
5. **Truncated and hostile input fails closed.** Empty file, 3-byte file, a GLB with a chunk
   length exceeding the file size, a GLB with a chunk length that overflows when summed, and a
   deeply nested directory are each handled with a named error and a non-zero exit — never a
   traceback, never a silent pass, never an unbounded read. No `except: pass` anywhere.
6. **Report matches the contract.** Output validates against `contracts/validation-report.schema.json`
   and includes, per rejected file: path, detected format, matched signature offset, and reason.
   The summary counts **files actually inspected** (ADR-0115 §1 — a counter that reads reality),
   and any file skipped for any reason is counted with its reason, never silently dropped.
7. **Runs offline and deterministically.** No network access; same input tree → byte-identical
   report. Demonstrated by two consecutive runs diffed.

## Forbidden here
Beyond MANAGER.md §3.7, task-specific traps:
- Deciding file type from the extension anywhere in the code path (mission §5.2).
- Skipping or stubbing the GLB-internal scan.
- A blacklist-shaped design: the accept set is a **whitelist** (ADR-0004); unknown formats are
  rejected, and "unknown" is a rejection reason, not a pass.
- Reading whole files into memory to find a signature at offset 0 — read the header only; the
  scanner must survive a large file without exhausting memory.
- Judging asset provenance or "AI-ness" — out of scope and contrary to ADR-0061.
- Inventing magic-byte values from memory: every signature row cites its source in a comment. If
  a signature cannot be verified from a real sample or a citable specification, it is marked in
  the log as an assumption, not quietly shipped.

## Deliverables
Scanner + signature table + contract schema + tests/fixtures + `docs/validation/asset-scanner.md`
+ this file's log section current.

## Questions  (agent-maintained; MANAGER.md §8b)
- **Q1 — how is the `text/JSON/Lua/Markdown` whitelist bucket identified, given none of
  those formats has a magic byte?** No ADR defines one (there isn't one to define — the
  files are plain UTF-8 text by construction). I assumed a content-based heuristic: accept
  as `TEXT` iff the sampled header contains no NUL/disallowed-control byte and decodes as
  UTF-8. This still never touches the extension (a `.dbc` file containing readable text
  would pass identically to a `.txt` file). Documented in
  `docs/validation/asset-scanner.md` under "The text bucket" / "Known limitations". If
  Ludwig wants per-format syntax validation (real JSON parsing for `.json`, real Lua
  parsing for `.lua`) that is a scope increase for a follow-up task, not a gap in the
  whitelist/blacklist mechanism ADR-0004 asks for. **Lean: ★ proceed as built** — it is the
  literal, defensible reading of "text/JSON/Lua/Markdown" as one whitelist bucket, and
  matches acceptance criterion 1's fixture set exactly.
- **Q2 — "chunk offset reported" for an embedded GLB rejection (criterion 3): chunk-relative
  or absolute file offset?** I report the absolute file byte offset (e.g. `216`), and the
  `reason` string additionally names the embedding mechanism (`BIN chunk` /
  `data URI`, image index, bufferView index). Absolute offset is what a human or a follow-up
  tool can actually seek to; I judged it a superset of "the chunk offset" rather than a
  deviation from it. **Lean: ★ proceed as built.**
- **Q3 — wowdev.wiki (the canonical wiki for these formats) returned HTTP 403 to every
  automated fetch attempt.** All five Blizzard signatures were instead verified against
  real independent open-source implementations (AzerothCore — our own server fork's
  upstream — for DBC; StormLib for MPQ; wow.export for BLP/M2/WMO), each fetched directly
  and cited in `tools/validation/magic.py`. Every byte value matches exactly what the task
  spec itself named (`WDBC`, `MPQ\x1a`, `BLP2`, `MD20`/`MD21`, `MVER`+`MOHD`), so this is
  independent *confirmation* of already-specified values, not a guess. Flagging in case
  Ludwig later gets wowdev.wiki access and wants a direct citation swapped in — the values
  will not change, only the citation source would.

---
# Task 002 log  (append-only, by the executing agent)
- (not started — awaiting spec approval)
- 2026-09-02 spec approved; worktree created from registry `main`. NOTE: this repository cannot be
  pushed to yet — the WSL `gh` token (account `mbmludric`) has `push: false` on
  `worldofmodcraft/registry`. Commit locally; the push happens once Ludwig resolves the org access.

- 2026-09-02 (implementer/sonnet) — Read, in order: this task file; `/home/ludwig/wom/CLAUDE.md`;
  ADR-0004, ADR-0040, ADR-0041, ADR-0061, ADR-0116, ADR-0103, ADR-0115 (all at
  `/home/ludwig/wom/docs/decisions/`, read-only); `docs/architecture/depgraph.md` (N4, E5/E6 rows)
  and the relevant slices of `docs/tasks/MISSION-worldofmodcraft-site-v1.md` (§3 key facts, §4 D2
  step 3, §5.2 forbidden shortcuts, §7.1 acceptance) from the read-only `/home/ludwig/wom` tree.
  No contradiction found between this task's spec and any ADR it names; proceeded.

  **Runtime choice: Python 3, stdlib only.** Checked the environment (`python3 --version` →
  3.14.4 present; no `node` binary found). Chose Python: `struct` gives exact, explicit
  bounds/endianness control for the GLB binary parse; no third-party dependency is needed for
  anything the scanner does; stdlib-only means nothing to install, which is both ADR-0103
  ("boring, predictable") and a precondition of acceptance criterion 7 ("runs offline").
  Recorded in a docstring at the top of `tools/validation/scan_assets.py` and in
  `docs/validation/asset-scanner.md`.

  **Signature verification (forbidden-shortcuts rule: no magic byte from unverified memory).**
  Tried `wowdev.wiki` directly (DBC/MPQ/BLP/M2/WMO pages) — every page returned HTTP 403 to
  `WebFetch`. Fell back to real independent open-source implementations that read/write these
  formats, fetched and cited directly in `tools/validation/magic.py`:
    - **DBC → `WDBC`**: AzerothCore (our own server fork's upstream) —
      `src/common/DataStores/DBCFileLoader.cpp` — fetched via `gh api
      repos/azerothcore/azerothcore-wotlk/contents/...`; line reads
      `if (header != 0x43424457) // 'WDBC'`. **Verified, not assumed.**
    - **MPQ → `MPQ\x1a`**: StormLib (reference MPQ implementation), `StormCommon.h`, confirms
      the header signature constant `0x1A51504D` (little-endian dword = raw bytes
      `'M' 'P' 'Q' 0x1A`). **Verified.**
    - **BLP → `BLP2`**: wow.export, `blp.js`, `BLP_MAGIC = 0x32504c42` (= ASCII `BLP2`
      little-endian). **Verified.**
    - **M2 → `MD20`/`MD21`**: wow.export, `constants.js`, `MAGIC.MD20 = 0x3032444D`,
      `MAGIC.MD21 = 0x3132444D`. **Verified.**
    - **WMO → `MVER`+`MOHD`**: wow.export, `WMOLoader.js`, chunk header = 4-byte magic + 4-byte
      LE size; `MVER = 0x4D564552`, `MOHD = 0x4D4F4844`. **Verified.**
  PNG (`89 50 4E 47 0D 0A 1A 0A`) and OGG (`OggS`) were confirmed against the official W3C PNG
  spec and RFC 3533 respectively (both fetched directly). GLB (`glTF` magic, 12-byte header,
  chunk format, JSON/BIN chunk-type values `0x4E4F534A`/`0x004E4942`) was confirmed against the
  official Khronos glTF 2.0 Specification, fetched as the raw `Specification.adoc` source from
  the KhronosGroup/glTF GitHub repo (the HTML spec pages 403'd). **Every one of the eight rows
  in `tools/validation/magic.py` carries a source citation in its own comment; none was shipped
  from memory alone.** All five Blizzard byte values also independently match what the task
  spec itself stated verbatim — the fetches confirm the spec's own values rather than
  contradicting or replacing them.

  **Design decisions made and recorded:**
  1. Text whitelist bucket (`.md`/`.json`/`.lua`/`.txt`/`.gltf` JSON) has no magic byte —
     classified by content (UTF-8-decodable, no disallowed control bytes), never by extension.
     Booked as Q1.
  2. GLB interior walk follows the real glTF 2.0 embedding mechanisms: `bufferView`-referenced
     images backed by the GLB's own BIN chunk (buffer 0, no `uri`), and `data:` URI images
     embedded directly in the JSON chunk. Both are exercised by tests. External (`uri`-referenced)
     buffers are out of scope for the container walk (not bytes inside this file).
  3. GLB chunk bounds checks use Python's arbitrary-precision integers (`data_offset + chunk_length
     > file_size`) — proven, not just assumed, safe against 32-bit wraparound by a fixture using
     `chunk_length = 0xFFFFFFFF` (criterion 5's "chunk length that overflows when summed").
  4. Report schema: `rejected` entries always carry `path`/`detected_format`/`signature_offset`
     (nullable — null when no byte offset is meaningful, e.g. an empty file)/`reason`. A separate
     `scan_errors` array holds directory-level problems (depth-limit exceeded, unlistable
     directory) that aren't about one file's content; both contribute to a non-zero exit and are
     counted in `summary`.
  5. `files_inspected` counts files actually opened and read (ADR-0115 §1: measure outcome, not
     the directory listing) and always equals `files_accepted + files_rejected` — asserted in
     tests. Every skip (symlinks not followed, non-regular files) is counted with a named reason
     in `summary.skipped_reasons`; nothing is silently dropped.
  6. Determinism: no timestamp or other non-deterministic field anywhere in the report; file
     lists sorted by path; `json.dumps(..., sort_keys=True)`.

  **Built:** `tools/validation/magic.py` (signature table + `looks_like_text` heuristic),
  `tools/validation/scan_assets.py` (walker, GLB container parser, embedded-payload walk, report
  assembly, CLI), `contracts/validation-report.schema.json` (JSON Schema draft 2020-12),
  `tests/validation/fixture_builder.py` (builds every fixture from real bytes — a genuinely
  decodable PNG via `zlib`, a structurally correct GLB via `struct` — never a hand-typed literal
  whose correctness depends on memory), `tests/validation/schema_check.py` (a small stdlib-only
  JSON Schema subset validator — no `jsonschema` package is installed in this environment and the
  tool must stay dependency-free/offline), `tests/validation/test_scan_assets.py` (21 tests, one
  section per acceptance criterion plus signature-table sanity checks),
  `docs/validation/asset-scanner.md`.

  **Test run:** `python3 -m unittest discover -s tests/validation -v` → **21 tests, 20 passed, 1
  skipped** (`test_runs_with_network_namespace_unshared`: this sandbox does not permit
  unprivileged `unshare -n` — `unshare: unshare failed: Operation not permitted` — so that one
  *dynamic* network-isolation check was skipped rather than falsely reported as passing; the
  companion *static* check, `test_no_networking_imports_in_scanner_or_magic_table`, does run and
  passes, and is the basis for the criterion-7 offline claim below). Full output:
  ```
  Ran 21 tests in 0.797s
  OK (skipped=1)
  ```

  **Acceptance criteria — each demonstrated by a command actually run, output pasted:**

  1. **Whitelist accepted.** Built a tree with real PNG/OGG/.gltf(JSON)/GLB/.md/.json/.lua/.txt
     under `/tmp/wom-scan-demo/c1_whitelist` and ran:
     `python3 tools/validation/scan_assets.py /tmp/wom-scan-demo/c1_whitelist`
     → exit 0, `files_inspected: 8`, `files_accepted: 8`, `files_rejected: 0`, `rejected: []`.
     Also covered by `Criterion1WhitelistAccepted.test_whitelist_tree_scans_clean`.

  2. **Blizzard formats rejected under `screenshot.png`.** Built DBC/MPQ/BLP/M2/WMO fixtures
     (real magic bytes, verified above), each saved as `<fmt>/screenshot.png`, ran the scanner on
     `/tmp/wom-scan-demo/c2_blizzard` → exit 1, all 5 rejected, `detected_format` = `DBC`/`MPQ`/
     `BLP`/`M2`/`WMO` respectively (never `UNKNOWN`), each `signature_offset: 0`, each reason
     names "Blizzard client format ... (ADR-0004)". Also
     `Criterion2BlizzardFormatsRejected.test_each_blizzard_format_named_and_rejected`.

  3. **GLB interior walked.** Built a valid GLB with a `bufferView`-embedded BLP payload in its
     BIN chunk (`/tmp/wom-scan-demo/c3_glb_reject/trap.glb`) → exit 1, `detected_format: "BLP"`,
     `signature_offset: 216` (the real file offset of the embedded payload), reason names
     "embedded payload in GLB BIN chunk (image[0], bufferView[0]) at file offset 216: BLP2
     texture format...". A second GLB with only an embedded PNG
     (`/tmp/wom-scan-demo/c3_glb_pass/ok.glb`) → exit 0, accepted as `GLB`. A third variant
     (test-suite only) proves the same rejection via the *other* embedding mechanism — a base64
     `data:` URI inside the JSON chunk rather than a BIN-chunk bufferView — confirming the walk
     isn't limited to one path in. Also `Criterion3GlbInteriorWalked` (3 tests).

  4. **Extension never trusted, both directions.** `/tmp/wom-scan-demo/c4_extension/data.dbc`
     (real PNG bytes) and `.../art.png` (real DBC bytes) scanned together → exit 1;
     `data.dbc` → `accepted: [{"path": "data.dbc", "format": "PNG"}]`; `art.png` → rejected,
     `detected_format: "DBC"`. Both directions in one command's output. Also
     `Criterion4ExtensionNeverTrusted` (2 tests).

  5. **Hostile input fails closed.** `/tmp/wom-scan-demo/c5_hostile` (empty file, 3-byte
     non-text file, GLB with a chunk length exceeding the file's real size, GLB with chunk
     length = `0xFFFFFFFF`) → exit 1, all 4 rejected with named reasons
     (`MALFORMED`/`MALFORMED`/`MALFORMED`/`MALFORMED`... the 3-byte file is `UNKNOWN`), no
     traceback on stderr (asserted by every test helper: `assert proc.stderr == ""`). A 50-level
     nested directory (`/tmp/wom-scan-demo/c5_deep_nest`) → exit 1, one `scan_errors` entry
     naming "directory nesting exceeds the maximum depth of 40". Source-scanned for
     `except: pass` / bare `except:` — none present (also asserted by
     `test_no_traceback_and_no_bare_except_pass_in_source`). Also `Criterion5HostileInputFailsClosed`
     (6 tests).

  6. **Report matches the contract.** Ran the scanner on a mixed tree that includes a symlink
     (`/tmp/wom-scan-demo/c6_mixed`), captured stdout to a file, then validated it against
     `contracts/validation-report.schema.json` with the stdlib-only validator
     (`tests/validation/schema_check.py`) → `SCHEMA VALID`. Confirmed
     `files_inspected == files_accepted + files_rejected` (3 == 2 + 1) and that the symlink was
     counted: `files_skipped: 1`, `skipped_reasons: {"symlink not followed (not read for
     safety)": 1}` — never silently dropped. Also `Criterion6ReportMatchesContract` (2 tests).

  7. **Runs offline and deterministically.** Ran the scanner twice on the same tree, diffed
     stdout (`diff` exit 0, "IDENTICAL") and confirmed identical SHA-256 of both outputs
     (`50eb3478...09cdabe3` both times). For "no network access": attempted a dynamic proof
     (`unshare -n` / `sudo unshare -n`) — this sandbox permits neither unprivileged `unshare`
     nor passwordless `sudo`, so fell back to and ran a static proof: grepped every `import`/
     `from` line in `tools/validation/scan_assets.py` and `magic.py` — only stdlib
     `argparse`/`base64`/`dataclasses`/`json`/`os`/`pathlib`/`struct`/`sys`/`typing` are imported;
     none is network-capable. This same static check runs (not skipped) inside the automated
     suite as `test_no_networking_imports_in_scanner_or_magic_table`; the dynamic `unshare`
     variant is present as `test_runs_with_network_namespace_unshared` and skips gracefully with
     a stated reason when the sandbox forbids it, rather than being silently omitted. Also
     `Criterion7OfflineAndDeterministic.test_two_runs_are_byte_identical`.

  **Contradictions found:** none. The task spec, ADR-0004/0040/0041/0061/0103/0115/0116, the
  depgraph's N4/E5/E6 rows, and the mission's §3/§4/§5.2/§7.1 all agree on what this component
  must do; nothing required stopping to ask before proceeding.

  **File scope:** touched only `tools/validation/scan_assets.py`, `tools/validation/magic.py`,
  `contracts/validation-report.schema.json`, `tests/validation/**`,
  `docs/validation/asset-scanner.md`, and this task file's own log — exactly the declared scope.
  No `.gitignore` or other scope-adjacent file was added; `__pycache__` directories were deleted
  before committing rather than ignored, since adding a new top-level file wasn't in scope.

  **Remaining / follow-ups (not blocking, not silently skipped):**
  - Text-bucket content validation is format-agnostic (UTF-8 + no control bytes), not per-format
    syntax checking. See Q1.
  - `data:` URI images that are not base64-encoded are not sniffed (documented limitation in
    `docs/validation/asset-scanner.md`); base64 ones are handled and tested.
  - The dynamic offline proof (`unshare -n`) could not run in this sandbox; re-run
    `python3 -m unittest tests.validation.test_scan_assets.Criterion7OfflineAndDeterministic
    -v` in an environment that permits unprivileged network namespaces to get the stronger
    dynamic proof — the static import-analysis proof already ran and passed.

  **Status: acceptance criteria 1–7 all demonstrated; ready for review.** Commit follows on this
  branch (not pushed — see the pre-existing note above on `gh` token push access).
