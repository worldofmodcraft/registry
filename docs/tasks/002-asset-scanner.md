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

---
# Spec amendment — round 2 (manager, 2026-09-02)

Independent adversarial review got Blizzard payloads **accepted** three ways, all reproduced by
the manager. Root cause is a **defect in this spec**, not in the implementation: round 1 asked for
"identify every file's real type by magic bytes", and a magic-byte-at-offset-0 sniffer is exactly
what was built. The spec never said what the scanner must actually guarantee. It does now.

## The guarantee, stated properly
A file is accepted only if **the entire file is a well-formed instance of a whitelisted format**.
Not "its first bytes look right" — the whole file, to EOF, with nothing left over.

This is deliberately *not* "scan the file for forbidden signatures". Byte-scanning produces false
positives (compressed pixel data legitimately contains arbitrary byte sequences) and false
negatives (trivially defeated by compressing or offsetting the payload). Proving well-formedness
is both stricter and quieter: a PNG with a DBC glued after IEND fails because it is not a valid
PNG, not because we recognised the DBC.

## Additional acceptance criteria (round 1's seven still stand)

8. **No unvalidated tail.** For each accepted format, parsing reaches the structural end of the
   file and the file ends there. Demonstrated for each of PNG, OGG, glTF, GLB: a valid file of
   that type with an appended DBC payload is **rejected**, naming trailing data as the reason.
9. **Truncated-but-valid-prefix is rejected.** A file consisting only of a whitelisted signature
   and nothing else — 8 bytes of PNG header, 4 bytes of `OggS` — is rejected, not accepted.
10. **The text bucket is bounded by the same rule.** A text-classified file is inspected in full,
    not by a 4096-byte prefix. A file of benign text followed at any offset by binary content is
    rejected. State the size ceiling above which full inspection is refused, and reject rather
    than accept beyond it.
11. **The GLB walk recurses.** An embedded payload that is itself a container (GLB/glTF) is
    validated as a container, not classified by a header sniff. Demonstrated: a GLB whose
    bufferView payload is a fake glTF header followed by a DBC payload is rejected.
12. **Signature constants are verified against on-disk byte order.** WoW's chunked formats
    (WMO, ADT, WDT) store chunk tags **byte-reversed**: wow.export compares `readUInt32LE()`
    against `0x4D564552`, so the bytes on disk are `REVM`, not `MVER`. The current
    `_mver_mohd()` compares the forward string and therefore can never match a real WMO.
    Fix it, and rebuild `build_wmo()` from the corrected sequence — the fixture currently
    reproduces the same wrong convention, which is why 21 passing tests never caught it.
    Accept **both** byte orders where a format is genuinely ambiguous, and say which is which.
13. **Fixtures must not be derived from the implementation.** Every rejection fixture is built
    from an independently cited byte sequence. A test whose expected value comes from the code it
    tests proves only self-consistency — that is how finding 4 survived a green suite.
14. **`docs/validation/asset-scanner.md` states the real limits.** Whatever residual gap remains
    after the above (size ceilings, formats not fully parsed) is disclosed in Known Limitations.
    A security document that omits the bypasses is worse than none, because it stops people looking.

## Also forbidden here (added)
- Classifying any file, at any nesting depth, from a bounded prefix when the file is small enough
  to inspect fully.
- Reporting a criterion as met on fixtures the implementation itself generated.

---
# Round-2 remediation log (2026-09-03, implementer/sonnet)

## Summary of what was wrong and what changed

Independent adversarial review found three real bypasses (padding past the 4096-byte probe
window; a whitelisted header followed by an arbitrary tail, including a bare signature with
nothing else; a GLB embedded-payload check that header-sniffed instead of recursively
validating) plus a fourth defect (the WMO matcher compared on-disk bytes against the forward
ASCII string `"MVER"`/`"MOHD"`, but the cited source reads the tag as a little-endian integer
that unpacks to the byte-reversed `"REVM"`/`"DHOM"` — so the matcher could never match a real
WMO file; it still failed closed as `UNKNOWN`, but never named the format, and the fixture
builder reproduced the identical wrong byte order, which is why the bug survived a 21-test green
suite).

Root cause of the first three (per the manager's amendment, which I agree with after reviewing
it against the original spec text): round 1's spec said "identify every file's real type by
magic bytes" and never stated a guarantee beyond that — a signature-at-offset-0 sniffer satisfies
the letter of that spec completely. The amendment fixes the spec; this entry documents the fix
to the implementation.

**New guarantee (implemented in full):** a file is accepted only if the *entire* file is a
well-formed instance of a whitelisted format — parsing reaches that format's true structural end
and the file ends exactly there, never "the first N bytes look right".

## Architecture change

- **`tools/validation/scan_assets.py`** gained a `Window`/`ByteWindow`/`MemoryByteWindow`
  abstraction: a bounded, seekable `[start, start+length)` view that answers `read_at` and
  `sub_window`. Every full-file validator (`validate_png_fully`, `validate_ogg_fully`,
  `validate_text_fully`, `validate_glb_fully`) operates on a window, not directly on a file. A
  top-level file is one window over the whole file; an embedded GLB payload (a bufferView slice
  of the BIN chunk, or a base64-decoded `data:` URI) is *also* just a window. The single dispatch
  function `classify_window(window, depth)` is used for both top-level files and every embedded
  payload at every nesting depth — this is what makes GLB recursion real (round-2 criterion 11)
  rather than a second, weaker code path.
- **PNG**: full chunk-stream walk from the signature to `IEND` (length/type/data/CRC per the W3C
  PNG spec's chunk layout, verified 2026-09-02 by fetching `https://www.w3.org/TR/png/#5Chunk-layout`);
  first chunk must be `IHDR` of exactly 13 bytes; the file must end exactly at `IEND`. Chunk
  *payload* bytes are never read (only 8-byte headers), so this is fast and bounded-memory
  regardless of image size (measured: a 1 MB incompressible-content PNG scans in ~56 ms).
- **OGG**: full page-stream walk using RFC 3533 §6's exact 27-byte fixed header + segment table +
  lacing-value payload-length layout (re-verified 2026-09-02 by fetching the RFC directly for the
  precise field layout, not just the capture pattern this time); the file must end exactly on a
  page boundary. Page payload bytes are never read either.
- **TEXT**: `validate_text_fully` streams the *entire* file through an incremental UTF-8 decoder
  (`codecs.getincrementaldecoder`) in bounded 64 KiB blocks, checking every byte for disallowed
  control characters — not a 4096-byte prefix. This is the direct fix for finding 1.
- **GLB**: `validate_glb_fully` is structurally the same bounds-checked chunk walk as round 1
  (kept — the manager confirmed this part was exact and well-tested), but
  `_walk_embedded_images` now recurses into `classify_window` for every embedded payload instead
  of calling the old prefix-only `classify_header`. An embedded GLB-shaped payload is therefore
  fully re-parsed as a container (including its *own* embedded payloads, bounded by
  `MAX_GLB_NESTING_DEPTH = 8`), not waved through on a magic-byte match.
- **New named ceilings** (all disclosed in `docs/validation/asset-scanner.md`): `MAX_FULL_SCAN_BYTES`
  = 256 MiB (files over this are rejected outright, never partially scanned and accepted — this
  is round-2 criterion 10's explicit requirement); `MAX_CHUNK_COUNT` = 100,000 (bounds
  chunk/page iteration count independently of file size, since chunk-skipping means the byte
  ceiling alone doesn't bound a pathological zero-length-chunk file); `MAX_GLB_NESTING_DEPTH` = 8.
- **`tools/validation/magic.py`**: every one of the five Blizzard signatures is now derived
  mechanically via `struct.pack("<I", hex_constant)` from the exact integer named in its cited
  source, rather than a hand-typed ASCII literal — this is the direct fix for finding 4, applied
  to all five (not just WMO) since the same class of error could recur elsewhere. Confirmed by
  running the derivation on all five: only WMO's on-disk bytes differ from the forward ASCII
  spelling (`REVM`/`DHOM` vs `MVER`/`MOHD`); DBC/MPQ/BLP/M2 were already correct. The WMO matcher
  now accepts both the on-disk-verified reversed order and the forward spelling defensively, and
  reports which one matched (`wmo_match_orientation`).
- **`tests/validation/fixture_builder.py`**: every Blizzard-format fixture is now built the same
  way — `struct.pack("<I", ...)` on an independently re-stated hex constant, with its own
  citation comment, and the module **never imports `tools/validation/magic.py`** (enforced by a
  new test, `Criterion13FixturesIndependentlyDerived`, using AST inspection rather than a naive
  text grep after that grep produced its own false positive on this file's prose). `build_wmo()`
  is replaced by `build_wmo_reversed()` (the on-disk-verified form) and `build_wmo_forward()` (the
  defensive-fallback form), plus a dedicated regression test
  (`test_wmo_fixture_bytes_are_actually_reversed_on_disk`) asserting the reversed fixture's first
  4 bytes are literally `b"REVM"`, not `b"MVER"`.

## What was deliberately kept unchanged (per the manager's explicit instruction)

GLB structural bounds checking (declared length vs. real size, the `0xFFFFFFFF` overflow
fixture, truncated chunk headers) — logic untouched, only re-parented onto the `Window`
abstraction. The counters (`files_inspected == accepted + rejected`, skips counted with
reasons, no silent drops). The stdlib `schema_check.py` validator. The legitimately-skipped
`test_runs_with_network_namespace_unshared` test and its honest skip reason. All of round 1's
21 tests still pass unchanged in intent (one assertion's expected substring was updated from
"file's actual size" to "file/region's actual size" — a wording change only, to cover embedded
sub-regions using the same message, not a behaviour change; verified by re-running all of round
1's original `/tmp/wom-scan-demo` fixture trees against the new scanner and confirming identical
accept/reject/exit-code/counter output, including a byte-identical SHA-256 on the criterion-1
whitelist tree's report both before and after this change).

## Round-2 acceptance criteria — each demonstrated by a command actually run

All commands below were run from `/home/ludwig/wt/registry-task-002`. Fixtures built via
`tools/validation/fixture_builder.py` (imported directly) into `/tmp/wom-scan-demo2/`.

8. **No unvalidated tail.** `python3 tools/validation/scan_assets.py /tmp/wom-scan-demo2/c8_trailing`
   → exit 1, all 4 rejected as `MALFORMED`: PNG+DBC → "20 byte(s) of trailing data after the PNG
   stream's IEND chunk"; OGG+DBC → fails parsing the DBC bytes as a second page ("header
   truncated"), a legitimate rejection since DBC bytes never form a valid `OggS` page; glTF
   text padded past 4096 bytes then DBC → "disallowed binary byte 0x00 found at offset 4100"
   (proving the *full* validator caught it, not the cheap probe: offset 4100 > `HEADER_PROBE_SIZE`
   4096); GLB+DBC → "GLB header declares total length 120 but the file/region is 140 byte(s)".
   Also the exact bypass-2 wording ("8-byte PNG signature + full DBC payload") demonstrated
   separately: `/tmp/wom-scan-demo2/c_bypass2/data.png` → rejected, "first PNG chunk must be
   IHDR, found b'\x00\x00\x00\x00'". Also `Criterion8NoUnvalidatedTail` (5 tests).
9. **Truncated-but-valid-prefix rejected.** `.../c9_truncated` (8-byte PNG signature only,
   4-byte `OggS` only) → exit 1, both rejected as `MALFORMED` ("PNG stream ends ... without an
   IEND chunk"; "shorter than a minimal Ogg page header"). Also `Criterion9TruncatedValidPrefixRejected`
   (3 tests, including a GLB analogue: header only, no JSON chunk).
10. **Text bucket bounded but full.** `.../c10_padding` (exact finding-1 repro: 4096 bytes of Lua
    comments then raw DBC) → exit 1, rejected at offset 4100, past the old probe window — this
    fixture would have been silently accepted by the round-1 scanner. Ceiling stated
    (`MAX_FULL_SCAN_BYTES = 268435456` bytes / 256 MiB, named constant in `scan_assets.py` and in
    `docs/validation/asset-scanner.md`) and enforced (`Criterion10TextBucketBoundedButFull.
    test_size_ceiling_is_a_named_constant_and_enforced`: a sparse file one byte over the ceiling
    is rejected outright with the ceiling named in the reason, not truncated-and-accepted).
11. **GLB walk recurses.** `.../c11_nested/trap.glb` (bufferView payload = fake `glTF` header,
    correctly sized, containing DBC bytes as "chunk 0") → exit 1, rejected: "embedded payload in
    GLB BIN chunk (image[0], bufferView[0]) at file offset 224: GLB chunk 0 declares length
    1128416343 byte(s) ... past the file/region's actual size of 256 byte(s)". 1128416343 decimal
    = `0x43424457` = the `WDBC` magic reinterpreted as a little-endian chunk length — direct proof
    the recursive parser actually attempted to parse the DBC bytes as a GLB chunk (not merely
    checked the fake outer magic and stopped). Also `Criterion11GlbWalkRecurses` (2 tests).
12. **WMO byte order.** `.../c12_wmo` (both `reversed_screenshot.png` and `forward_screenshot.png`)
    → exit 1, both named `WMO` (not `UNKNOWN`), each reason stating which orientation matched
    ("matched the on-disk chunk-tag byte order: reversed." / "...: forward."). Also
    `Criterion12WmoByteOrder` (3 tests, including the fixture-bytes-are-really-reversed regression
    guard).
13. **Fixtures independently derived.** `Criterion13FixturesIndependentlyDerived` (2 tests): AST
    inspection proves `fixture_builder.py` contains no `import`/`from` statement naming `magic`
    (a naive text-substring check was tried first and produced a false positive on this file's
    own prose describing the independence rule — fixed to use `ast.walk`); a second test confirms
    the file states its own citations (AzerothCore, StormLib, wow.export) rather than only citing
    magic.py.
14. **Limitations disclosed.** `docs/validation/asset-scanner.md`'s "Known limitations" section
    states, in the log's own words, the residual gaps: chunk/page checksums not verified (and
    why that specific gap doesn't reopen the trailing-data bypass this round closed); OGG
    logical-stream continuity not verified; PNG pixel/palette semantics not decoded; the TEXT
    bucket is format-agnostic (no JSON/Lua grammar check); non-base64 `data:` URIs not sniffed;
    the 256 MiB / 100,000-chunk / 8-level-nesting ceilings named explicitly. Also
    `Criterion14LimitationsDisclosed` (2 tests) checking the section exists, is non-trivial
    (>200 chars), and actually mentions "CRC", "checksum", and the numeric ceiling value.

Round 1's criteria 1–7 re-verified end-to-end against the rewritten scanner using the original
`/tmp/wom-scan-demo/` fixture trees: identical accept/reject/exit-code/counter output in every
case, including a byte-identical SHA-256 (`50eb3478...09cdabe3`) on the criterion-1 whitelist
tree's report, both before and after this change.

## Test suite

`python3 -m unittest discover -s tests/validation -v` → **40 tests, 39 passed, 1 skipped**
(`test_runs_with_network_namespace_unshared`, same legitimate sandbox limitation as round 1 —
kept, not touched). Full output tail:
```
Ran 40 tests in 1.613s
OK (skipped=1)
```

## New design decisions (booked, not silently shipped)

- **`MAX_FULL_SCAN_BYTES = 256 MiB`, `MAX_CHUNK_COUNT = 100,000`, `MAX_GLB_NESTING_DEPTH = 8`**:
  none of these numbers come from an ADR or the task spec (which only says "state the size
  ceiling" without naming one) — they are my engineering judgement, documented with reasoning in
  both `scan_assets.py`'s comments and `docs/validation/asset-scanner.md`. Flagging in case
  Ludwig wants a different ceiling for a specific real asset class (e.g. a longer music track).
  **Lean: ★ proceed as built** — generous for any realistic WotLK-era mod asset, and the ceiling
  is a named, visible, easily-changed constant, not a buried magic number.
- **PNG/OGG checksum verification was deliberately NOT added.** I considered computing PNG chunk
  CRCs and Ogg page checksums for extra rigor, but concluded the specific bypass this round closes
  (arbitrary trailing bytes) is fully closed by framing-to-EOF validation alone — CRC checking
  would not have stopped a well-crafted attack (which would simply compute a correct CRC for its
  wrapper) and adds real implementation risk (getting a checksum algorithm's polynomial/variant
  wrong is exactly the kind of "invented from memory" mistake this task already had one instance
  of, with WMO's byte order). Disclosed explicitly in Known Limitations rather than silently
  scoped out. **Lean: ★ proceed as built**, but flagging since it's a scope judgement call, not a
  requirement from the amendment text.
- **Data-URI embedded payload offsets are reported relative to the decoded buffer, not as a file
  offset** (there isn't one — the bytes only exist after decoding base64 text). The reason string
  says so explicitly ("this payload is decoded from base64 text and has no single file byte
  offset of its own"). Same category as round-1's Q2; **lean: ★ proceed as built**.

## File scope

Same declared scope as round 1: `tools/validation/{scan_assets.py,magic.py}`,
`contracts/validation-report.schema.json` (untouched this round — the report *shape* did not
change, only what triggers which verdict), `tests/validation/**`,
`docs/validation/asset-scanner.md`, and this task file's log. No file outside that scope was
touched.

**Status: round-2 criteria 8–14 all demonstrated; round-1 criteria 1–7 re-verified unaffected.
Ready for re-review.**

---
# Spec amendment — round 3 (manager, 2026-09-03; decided by Ludwig)

Round 2 closed "bytes after the file ends". Review then demonstrated the same violation moved
inside the container: a **valid PNG** (signature, IHDR, IDAT, IEND, no trailing bytes) carrying a
private `zBLZ` chunk whose declared-length data is a complete magic-intact DBC, and a **valid Ogg
page** whose lacing-declared payload *is* a DBC. Both accepted, exit 0.

The guarantee is now fixed by decision, not by another attempt at wording: **ADR-0120** (accepted
2026-09-03, amending ADR-0004) — *an accepted asset contains only content of types the platform has
explicitly permitted.* Read it before starting; it is the authority for everything below.

**Do not implement CRC verification as the fix.** A CRC is computed by whoever writes the chunk; an
attacker computes the correct one over their payload. CRCs detect corruption, not smuggling. This
was suggested in review and is explicitly rejected in ADR-0120.

## Additional acceptance criteria (rounds 1–2 criteria all still stand)

15. **PNG chunk-type whitelist.** Accept only `IHDR`, `PLTE`, `IDAT`, `IEND`, plus a short named
    safe list. **Every entry on that list carries a written reason for its inclusion** in
    `docs/validation/asset-scanner.md`. Unknown, private or unlisted chunks are rejected — including
    ancillary chunks that are harmless elsewhere. Demonstrated: the reviewer's `zBLZ` PNG is
    rejected, naming the chunk; a plain IHDR/IDAT/IEND PNG still passes.
16. **Ogg payloads must parse as Vorbis or Opus headers.** A page whose payload is not a recognised
    codec stream is rejected. Demonstrated: the reviewer's DBC-payload Ogg is rejected; a real
    Vorbis or Opus file still passes. *(If constructing a genuine Vorbis/Opus fixture is
    disproportionate, say so in the log with what you tried — do not fake one.)*
17. **Rejection messages are actionable.** Each names the offending element and the remedy, e.g.
    "PNG contains a private chunk `zBLZ`; re-export without private chunks or embedded metadata."
    A rejection an author cannot act on is a defect, not a security measure (ADR-0120 §3).
18. **The criterion-13 AST test must check imported symbols, not module names.**
    `tests/validation/test_scan_assets.py` currently inspects only `node.module`, so
    `from tools.validation import magic` passes undetected while binding the real module. Check
    `node.names` too, or resolve the fully-qualified path. Demonstrated: a mutated copy using that
    import form fails the test.
19. **Known Limitations states plainly what is not read.** Not "a corrupted CRC would still be
    accepted", which frames content-blindness as a checksum nicety. State which bytes are inspected
    and which are not, for each accepted format. Criterion 14 forbids the softer framing.

## Note on what is deliberately still open
Re-encoding on ingest (decode and re-emit, discarding everything that is not pixel or sample data)
is the stronger guarantee and is **not** being built: it conflicts with authors shipping their own
assets untouched. ADR-0120 records it as the available hardening if the whitelist proves leaky.
Say so in Known Limitations rather than implying the whitelist is airtight.

## Accepted cost
This will reject some legitimate files — colour profiles, text metadata, unusual-but-valid chunks.
That trade was made deliberately by Ludwig: an author can re-export, whereas a smuggling channel
through the platform's own content guarantee cannot be undone once used.

---
# Round-3 remediation log (2026-09-03, implementer-strong)

## What I did differently from rounds 1 and 2

Both prior rounds failed on the same criterion because each spec wording was satisfiable by a
file that still carried a Blizzard payload. I did not try to satisfy a third wording. ADR-0120
states the guarantee positively — *an accepted asset contains only content of types the platform
has explicitly permitted* — so the implementation now enumerates permitted interior content per
format and rejects everything else, including things that are harmless elsewhere.

Concretely, the change of shape: round 2's validators answered "is this a syntactically valid
container, and does it end where it says?". They now answer "is every element inside it one this
platform has named, at the length the specification fixes for it?". Framing checks are kept
underneath, untouched — they are what bounds the file and catches trailing data.

I also went one step past the literal text of criterion 15, deliberately. A chunk-*type*
whitelist alone does not close PNG: `IDAT` is the one permitted chunk whose length the spec does
not fix, so the same payload simply moves there (as deflate-stored bytes after the real
scanlines, or as raw bytes after the zlib stream's end inside the chunk). Both constructions are
built as fixtures below and both are rejected, because the concatenated IDAT stream must now
inflate to *exactly* the byte count IHDR implies and end exactly where the last IDAT chunk ends.
Had I stopped at the chunk-type list, round 4 would have been a repeat of rounds 1 and 2.

**CRC verification was not implemented.** ADR-0120 rejects it and the reasoning holds: the two
accepted attacks both had perfectly correct CRCs, computed by whoever wrote the chunk. It is
documented as irrelevant, not as a gap.

## Criteria 15-19, each with the command actually run

All commands from `/home/ludwig/wt/registry-task-002`. Fixture trees under `/tmp/wom-scan-demo3`,
`/tmp/wom-regress`, `/tmp/wom-rw2`, `/tmp/wom-perf`, built by the script recorded in each section.

### 15. PNG chunk-type whitelist — the reviewer's `zBLZ` PNG rejected, a plain PNG accepted

```
$ python3 tools/validation/scan_assets.py /tmp/wom-scan-demo3/c15_png ; echo "exit=$?"
exit=1   -- 5 inspected, 0 accepted, 5 rejected:
  zblz_attack.png    PNG contains chunk 'zBLZ' (ancillary, public-namespace) at offset 33,
                     carrying 20 byte(s) of data. That chunk type is not on the permitted
                     content list, so its bytes are never inspected by anything and could carry
                     any payload at all (ADR-0120 ...)
  text_metadata.png  ... chunk 'tEXt' ... at offset 33, carrying 13 byte(s) ...
  icc_profile.png    ... chunk 'iCCP' ... at offset 33, carrying 43 byte(s) ...
  idat_surplus.png   the PNG's IDAT pixel data inflates to more than the 2 byte(s) its 1x1 IHDR
                     declares; the surplus is data an image viewer never reads ...
  idat_tail.png      20 byte(s) follow the end of the PNG's IDAT zlib stream but are still
                     inside the IDAT chunk data ...

$ python3 tools/validation/scan_assets.py /tmp/wom-scan-demo3/c15_png_ok ; echo "exit=$?"
exit=0   -- plain.png ACCEPT PNG, with_gama_srgb.png ACCEPT PNG
```

`zblz_attack.png` is `fb.build_png_with_extra_chunk(b"zBLZ", fb.build_dbc())`: signature, IHDR,
the private chunk, IDAT, IEND, correct CRC on every chunk, no trailing bytes — the reviewer's
construction exactly.

**The safe list, and why each entry is on it.** Admission needs both halves: (a) the PNG spec
fixes the chunk's length at a handful of bytes *and* this scanner enforces that exact length, so
a permitted type can never be a container; and (b) either the chunk changes how the image
renders, or refusing it would reject the unconditional default output of ordinary image editors.
"Harmless" alone is not sufficient — ADR-0120 says so explicitly.

| Chunk | Enforced length | Why it is on the list |
|---|---|---|
| `tRNS` | 2 (greyscale), 6 (truecolour), <= palette size (indexed); forbidden for colour types 4/6 | The only place alpha exists at all for an indexed image. 59% of a 91-file real-world corpus carries it. No re-export preserves the art without it. |
| `gAMA` | exactly 4 | One 4-byte gamma value. Four bytes cannot carry content, and without it an image authored on a non-2.2 pipeline renders at the wrong brightness. |
| `sRGB` | exactly 1, value 0-3 | One enumerated byte. It is the small, fixed-length alternative to `iCCP`, so authors who need to declare colour intent can without an embedded profile. |
| `pHYs` | exactly 9, unit specifier 0 or 1 | Admitted under half (b)'s second branch only: it does not change rendering, but essentially every editor writes it unconditionally (9% of the machine corpus, 66% of the WoW add-on PNGs), and rejecting an editor's default export teaches authors to reach for byte-stripping tools instead of complying. Price: 9 spec-fixed bytes. |

Not on the list, each with its reason in `docs/validation/asset-scanner.md`: `iCCP` (arbitrary
compressed blob — the `zBLZ` shape with a respectable name), `tEXt`/`zTXt`/`iTXt` (free-form,
unbounded), `eXIf` (nested container), `bKGD`/`hIST`/`sBIT`/`tIME`/`cHRM`/`cICP`/`sPLT` (bounded
and harmless, but half (b) fails), `acTL`/`fcTL`/`fdAT` (APNG — needs its own decision),
`iDOT` (undocumented Apple extension: undocumented means its permitted contents cannot be
stated), and everything else.

The reason strings live in `scan_assets.py`'s `PNG_SAFE_LIST_REASONS` and the docs carry them
verbatim; `test_safe_list_reasons_are_documented` fails if the two ever drift apart.

### 16. Ogg payloads must parse as Vorbis or Opus headers

```
$ python3 tools/validation/scan_assets.py /tmp/wom-scan-demo3/c16_ogg ; echo "exit=$?"
exit=1   -- 4 inspected, 2 accepted, 2 rejected:
  ACCEPT real_opus.opus   OGG
  ACCEPT real_vorbis.ogg  OGG
  REJECT dbc_payload.ogg  the first packet of this Ogg logical bitstream begins
                          b'WDBC\x00\x00\x00\x00', which is neither a Vorbis identification
                          header ('\x01vorbis') nor an Opus one ('OpusHead'); its payload is
                          therefore not audio of a codec this platform permits (ADR-0120)
  REJECT zeros_payload.ogg  (same rejection, payload b'\x00\x00\x00\x00\x00')
```

`dbc_payload.ogg` is `fb.build_ogg_page_with_payload(fb.build_dbc())`: a structurally perfect
RFC 3533 §6 page whose lacing-declared payload is a complete DBC — the reviewer's construction.

**Yes, I got real Vorbis and Opus fixtures, and they are third-party encoder output.** What I
tried, in order: `ffmpeg`, `oggenc`, `opusenc`, `sox`, `opusdec` — none installed; `mutagen`,
`soundfile`, `pyogg`, `numpy` — not importable; `libopus`/`libvorbis`/`libogg` via `ldconfig -p`
— absent, so no ctypes route; `pip` — no `pip` module; `apt` — no non-interactive sudo. So
nothing on this machine can encode Ogg audio. I did **not** hand-build one: a stream I wrote from
RFC 7845 would share this repository's reading of the spec with the parser it is supposed to
test, which is exactly the self-consistency trap criterion 13 exists to stop. Instead I fetched
two files from established open-source test corpora and committed them unmodified:

| File | Bytes | Origin | Licence |
|---|---|---|---|
| `tests/validation/fixtures/real-vorbis-sound_0.oga` | 4239 | web-platform-tests `media/sound_0.oga` | BSD-3-Clause / W3C test-suite licence |
| `tests/validation/fixtures/real-opus-opus-test.opus` | 14128 | Chromium `media/test/data/opus-test.opus` | BSD-3-Clause |

Provenance, licences and SHA-256 digests are in `tests/validation/fixtures/README.md` and
`sha256sums.txt`; `test_the_real_fixtures_are_the_third_party_bytes_they_claim_to_be` asserts the
digests so neither can be quietly regenerated locally. The Vorbis one is genuinely useful rather
than decorative: its setup header spans 16 lacing values of 255, so accepting it exercises the
cross-page packet-reassembly path rather than a one-packet-per-page happy case.

Header validation implemented: Vorbis identification header (`\x01vorbis`, 30 bytes, version 0,
non-zero channels/rate, in-range block sizes, framing bit), comment header (`\x03vorbis`, vendor
and every tag parsed and required to be printable UTF-8, framing bit, packet consumed exactly),
setup header (`\x05vorbis`) present; Opus `OpusHead` per RFC 7845 §5.1 (major version 0, non-zero
channels, length fixed by channel mapping family) and `OpusTags` per §5.2, with post-tag padding
allowed only when every padding byte is zero and at most 4096 of them — real encoders emit that
padding, and refusing it would reject ordinary `opusenc` output for no gain.

### 17. Rejection messages name the offending element and the remedy

`remedy` is now a required, non-empty field of the report contract
(`contracts/validation-report.schema.json`, `schema_version` 1.1.0), kept separate from `reason`
so a caller can surface it in a PR comment without re-parsing prose.

```
$ python3 -c "... schema_check.validate(report, schema) ..."
report validates OK; schema_version = 1.1.0
a rejection without remedy is refused by the contract: $.rejected[0]: missing required property 'remedy'
```

`test_every_rejection_carries_a_remedy` builds a 15-file tree covering every rejection class
(PNG chunk, PNG IDAT, Ogg codec, Ogg framing, all five Blizzard formats, empty, tiny, unknown
binary, text-with-binary-tail) and asserts every one carries a remedy over 40 characters that is
not the `_MISSING_REMEDY` placeholder. Example pair, verbatim from the report:

```
reason: "... PNG contains chunk 'zBLZ' (ancillary, public-namespace) at offset 33, carrying 20
         byte(s) of data. That chunk type is not on the permitted content list ..."
remedy: "Re-export the image as a plain PNG without private chunks, embedded metadata or colour
         profiles -- in most editors that is 'export as PNG' with metadata disabled; from the
         command line, `pngcrush -rem alla -rem text in.png out.png` removes every ancillary
         chunk this scanner does not permit. Permitted chunks are IDAT, IEND, IHDR, PLTE, gAMA,
         pHYs, sRGB, tRNS."
```

A Blizzard-format rejection says what to supply instead rather than only what is forbidden
(`test_a_blizzard_format_rejection_says_what_to_supply_instead`).

### 18. The criterion-13 AST test checks imported symbols, not module names

The old check inspected only `ImportFrom.module`. Demonstrated on a mutated copy of the tree at
`/tmp/c18demo` with `from tools.validation import magic` inserted into `fixture_builder.py`:

```
$ python3 -m unittest discover -s /tmp/c18demo/tests/validation \
      -k test_fixture_builder_does_not_import_magic_module
AssertionError: 'from tools.validation import magic' is not None :
    unexpected import binding magic.py: from tools.validation import magic
FAILED (failures=1)

$ (round-2's node.module-only check, run against the identical mutated source)
round-2 check caught the mutation: False
```

The check is now a module-level helper, `find_magic_import(source)`, which matches by path
segment (`magic`, `tools.validation.magic`, `magic.foo` all count; `magical_thinking` does not)
across `Import` aliases, `ImportFrom.module` and `ImportFrom.names`. Seven mutation forms are
asserted caught (plain, aliased, from-module, from-package, from-package-aliased, relative,
nested-in-a-block) and four non-imports asserted *not* flagged (prose in a docstring, unrelated
imports, a local variable named `magic`, a comment) — the false-positive direction matters too,
since a naive text grep already misfired once on this file's own prose.

### 19. Known Limitations states plainly what is not read, per format

`docs/validation/asset-scanner.md` now opens its limitations with a per-format table, "What is
read and what is not", instead of the round-2 bullet that framed content-blindness as a checksum
nicety. Summary of the right-hand column:

- **PNG** — the inflated pixel bytes are *counted, not examined*. An attacker can still make a
  picture whose pixel values are another file's bytes; nothing short of re-encoding tells that
  from a picture, because it is one. Chunk CRCs are not read.
- **Ogg** — the Vorbis setup header's codebook bytes (marker checked, contents not parsed) and
  every audio packet after the headers. Page CRCs are not read.
- **GLB** — buffer bytes no `images[]` entry references are bounds-checked but not interpreted.
- **TEXT** — every byte is read, but no JSON/Lua/glTF grammar is checked.

The section states explicitly that re-encoding on ingest is the stronger guarantee, is
deliberately not built (ADR-0120 option B, conflicts with ADR-0004's authors-own-their-assets),
and therefore that the whitelist is not airtight. Checksums get their own subsection saying they
are not the residual gap at all: both accepted attacks had valid CRCs, and CRCs detect corruption,
not smuggling.

## Rounds 1 and 2 not regressed

```
$ python3 tools/validation/scan_assets.py /tmp/wom-regress ; echo "exit=$?"
exit=1   -- 20 inspected, 6 accepted, 14 rejected
ACCEPTED: ok/README.md TEXT, ok/init.lua TEXT, ok/mod.json TEXT, ok/plain.png PNG,
          ok/real.ogg OGG, ok/real.opus OGG
REJECTED: r1_c2/{a..f}_screenshot.png -> DBC, MPQ, BLP, M2, WMO (reversed), WMO (forward)
          r2_attacks/padding.lua      -> disallowed binary byte 0x00 at offset 4100 (finding 1)
          r2_attacks/hdr_plus_dbc.png -> MALFORMED (finding 2: PNG header + DBC tail)
          r2_attacks/bare.ogg         -> MALFORMED (criterion 9: bare OggS)
          r2_attacks/png_tail.png / ogg_tail.ogg / glb_tail.glb -> MALFORMED (criterion 8)
          r3_attacks/zblz.png / dbc_payload.ogg -> MALFORMED (this round)
```

The three ceilings and the recursion behaviour still hold, and the content whitelist reaches
inside GLB too — `test_the_content_whitelist_applies_inside_a_glb_too` puts the `zBLZ` PNG in a
GLB's BIN chunk and gets "embedded payload in GLB ... chunk 'zBLZ' ...", because embedded payloads
go through the same `classify_window` dispatcher rather than a second, weaker path.

Determinism (criterion 7), two consecutive runs over the same tree:

```
$ python3 tools/validation/scan_assets.py /tmp/wom-regress -o /tmp/det1.json
$ python3 tools/validation/scan_assets.py /tmp/wom-regress -o /tmp/det2.json
$ diff /tmp/det1.json /tmp/det2.json && sha256sum /tmp/det1.json /tmp/det2.json
byte-identical: yes
ba6ac2ef628023e3edfa0d2f0d07a226c41b42b9866f831476abe53e5b78f816  /tmp/det1.json
ba6ac2ef628023e3edfa0d2f0d07a226c41b42b9866f831476abe53e5b78f816  /tmp/det2.json
```

## Measured against real third-party assets — because rejecting everything is not a win

130 files gathered from this machine and from an installed WoW add-on tree, none written for this
project, none adjusted to pass:

```
$ python3 tools/validation/scan_assets.py /tmp/wom-rw2 -o /tmp/rw2.json
130 inspected, 115 accepted, 15 rejected
```

- **102 files named `.png`** — two are actually JPEGs (`FF D8 FF E0 ... JFIF`), correctly rejected
  as `UNKNOWN` (criterion 4 on real data, not a false rejection). Of the 100 genuine PNGs,
  **88 accepted (88%)**; the 12 rejections are `iCCP` x4, `iTXt` x3, `tEXt` x2, `cHRM` x1,
  `tIME` x1, `bKGD` x1 — every one fixable by re-exporting, and the remedy says how.
- **28 files named `.ogg`** — one is actually an MP4 (`ftypisom`), correctly rejected. The other
  **27 are genuine Ogg Vorbis and all 27 are accepted**, vendor strings and tags parsed in full.

Chunk-type prevalence used to justify the safe list (91 machine PNGs): `IHDR`/`IDAT`/`IEND` 100%,
`PLTE` 67%, `tRNS` 59%, `pHYs` 9%, `iTXt` 4%, `iCCP` 4%, `iDOT` 3%, `eXIf` 3%, `tEXt` 3%,
`tIME` 2%, `sBIT` 2%, `cICP`/`cHRM`/`bKGD`/`sRGB` 1%. Add-on corpus (9 PNGs): `pHYs` 66%,
`sRGB` 33%, `gAMA` 33%, `iTXt` 33%.

## Cost of the IDAT check (it is not free, and it is bounded)

```
$ /usr/bin/time -v python3 tools/validation/scan_assets.py /tmp/wom-perf
Elapsed (wall clock) time: 0:00.06
Maximum resident set size: 19692 KiB
```

The tree holds a real 2048x2048 RGBA PNG (16.7 MB of raw scanlines) which is accepted, and a
decompression bomb (a 102 KB file whose IDAT inflates to 100 MB) which is rejected. Peak RSS is
19.7 MB against a ~15 MB bare-interpreter baseline because decompression is capped at
`max_length=TEXT_BLOCK_SIZE` per call and aborts the moment output passes what IHDR implies — the
first draft of this function used a whole-raster cap and peaked at 37 MB; the per-block bound is
what brought it down. `test_a_decompression_bomb_is_rejected_without_materialising_it` asserts the
scanner subprocess's peak stays under 200 MiB.

## Test suite

```
$ python3 -m unittest discover -s tests/validation
Ran 66 tests in 3.74s
OK (skipped=1)
```

26 new tests this round; all 40 of rounds 1-2's tests pass unchanged in intent. The one skip is
`test_runs_with_network_namespace_unshared`, the same honest sandbox limitation as rounds 1 and 2
— not touched. No existing test was weakened or deleted. Two round-1 fixtures changed *premise*
rather than being weakened: `build_ogg()` now returns the genuine third-party Vorbis file, because
since ADR-0120 a hand-built page with arbitrary payload bytes is no longer "a valid Ogg fixture" —
it is the attack, and it moved to `build_ogg_page_with_payload()` / `build_ogg_arbitrary_payload_page()`
as rejection fixtures.

## For Ludwig

- **Q3 — `pHYs` on the PNG safe list.** It is the one entry that does not change how an image
  renders; it is there because two-thirds of the add-on PNGs carry it and rejecting an editor's
  default export pushes authors toward byte-stripping tools. Cost is 9 spec-fixed bytes per file.
  **A** keep it (★ my lean, and what is built) · **B** drop it and accept ~10-60% more rejections
  on default exports · **C** drop it and publish a one-line `pngcrush` recipe in the author docs.
- **Q4 — the 12% PNG rejection rate is real.** Colour profiles and text metadata are the bulk of
  it. ADR-0120 §4 accepts this cost explicitly, so I have not treated it as a defect, but it is
  the number Ludwig should see before the upload form goes live.
- **Q5 — Ogg is restricted to Vorbis and Opus.** FLAC-in-Ogg, Speex and Theora are rejected. That
  follows ADR-0120 clause 2 literally. If mods should be able to ship Ogg FLAC, that is a new
  decision (and needs its "what may be inside it" answer, per ADR-0120's consequences).

## Scope note

Files touched, all inside the declared scope: `tools/validation/scan_assets.py`,
`contracts/validation-report.schema.json`, `tests/validation/**` (including the new
`fixtures/` directory), `docs/validation/asset-scanner.md`, and this file.
`tools/validation/magic.py` was not touched this round — the signature table was correct and
this round's work is about what is *inside* an identified format, not about identification.

One thing I wanted and did not do: `tests/validation/__pycache__/` and
`tools/validation/__pycache__/` are untracked noise in `git status` (they were already there
before this round). A root `.gitignore` would fix it, but the repository root is outside this
task's declared file scope, so I removed the one I had briefly added rather than improvise past
the scope rule. Recommend a two-line `.gitignore` as its own trivial task.

## Nothing in ADR-0120 or the round-3 spec looked wrong to me

I went looking, given the history. The one place the spec's literal text would not have been
enough is criterion 15: a chunk-type whitelist alone leaves `IDAT` as an unbounded container, so I
implemented the inflated-size check as well and said so above. That is an addition, not a
disagreement. ADR-0120's rejection of CRC verification is correct and I did not implement it.

**Status: criteria 15-19 demonstrated; rounds 1-2 criteria re-verified unaffected. Ready for
re-review.**
