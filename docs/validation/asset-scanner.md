# Asset scanner

`tools/validation/scan_assets.py` walks a directory tree and accepts a file only if
**the entire file, to the last byte, is a well-formed instance of a whitelisted
format** — not merely "starts with the right bytes". Named Blizzard formats
(DBC/MPQ/BLP/M2/WMO) are rejected outright on a magic-byte match, including
payloads embedded inside GLB containers, which are validated **recursively** as
real containers rather than sniffed. It is the mechanical enforcement of
[ADR-0004](../decisions/0004-own-assets-only.md) ("own assets only; never Blizzard
data") and implements node **N4** (`validation-core`, asset-scanning half) of the
registry's dependency graph, against contract edges **E5**/**E6**
(`contracts/validation-report.schema.json`).

It has two callers today (why N4 is its own component rather than folded into the
build pipeline): the registry PR gate (N3, edge E5) and the build pipeline (N5,
edge E6). Both invoke it the same way and get the same report shape back.

## Spec amendment — round 2

Independent adversarial review (2026-09-02) got real Blizzard payloads **accepted**
three ways against the round-1 version of this tool, all reproduced by the
manager:

1. **Padding past the probe window.** The scanner read only a 4096-byte prefix to
   decide a file's type; content beyond that prefix was never inspected. A text
   file padded past 4096 bytes with a raw DBC payload appended was accepted as
   TEXT.
2. **Whitelisted header, arbitrary tail.** Only the first bytes were checked;
   nothing validated the rest. An 8-byte PNG signature followed by a full DBC
   payload was accepted as PNG. A file that was *only* the signature (no
   structure at all) was likewise accepted.
3. **Non-recursive GLB walk.** An embedded payload inside a GLB's BIN chunk was
   classified by a header sniff, never by the full container validator. A
   bufferView payload consisting of a fake `glTF` header plus a DBC payload was
   accepted as a nested GLB.

A fourth finding, independent of the above: the WMO signature matcher compared
on-disk bytes against the literal ASCII string `"MVER"`, but the cited source
(wow.export) reads the tag as a little-endian integer and compares it against
`0x4D564552` — which unpacks to on-disk bytes `b"REVM"`, not `b"MVER"`. WoW's
chunked formats (WMO, ADT, WDT) store the four-character chunk tag **byte-reversed**
on disk. The old matcher could therefore never match a real WMO file. It still
failed closed (rejected as `UNKNOWN`), so no payload got through — but criterion 2
requires the format be *named*, and it wasn't. The bug survived a 21-test green
suite because the test fixture builder reproduced the exact same wrong byte order,
so the tests only proved the code agreed with itself.

Root cause of the first three: a **specification defect**, not an implementation
defect. Round 1 asked the scanner to "identify every file's real type by magic
bytes", and a magic-byte-at-offset-0 sniffer is exactly what was built — the spec
never stated what the scanner had to *guarantee*. It does now, and this file
describes the corrected design.

### The guarantee, stated properly

A file is accepted only if **the entire file is a well-formed instance of a
whitelisted format**. Parsing must reach that format's real structural end, and
the file must end exactly there — not "the first N bytes look right".

This is deliberately **not** "scan the file for forbidden byte sequences".
Byte-scanning both false-positives (compressed pixel/audio data legitimately
contains arbitrary byte sequences) and false-negatives (trivially defeated by
compressing or offsetting the payload). Proving well-formedness is both stricter
and quieter: a PNG with a DBC glued on after `IEND` is rejected because it is not
a valid PNG, not because the scanner went looking for the DBC inside it.

## Why Python, stdlib only

The task allowed either Python or a `.mjs` (Node) runtime. Python was chosen
because this environment has Python 3 available and no Node.js runtime was found
at authoring time; `struct.unpack` gives explicit, precise control over
endianness and bounds for every integer field the PNG/OGG/GLB binary formats
define; and no third-party dependency is needed for anything the scanner does
(binary parsing: `struct`; JSON: `json`; base64: `base64`; streaming UTF-8
decoding: `codecs`). Stdlib-only means nothing to install, ever — the boring,
predictable choice (ADR-0103), and a precondition for the "runs offline"
acceptance criterion.

## Running it

```
python3 tools/validation/scan_assets.py <path-to-scan> [-o report.json]
```

Without `-o`, the JSON report is printed to stdout. Exit code:

- `0` — every file was inspected and accepted; no scan errors.
- `1` — at least one file was rejected, or a scan error occurred (e.g. a
  directory nested past the depth limit).
- `2` — usage error (the given path does not exist or is not a directory).

## What is accepted (the whitelist), and how "accepted" is proven

Format is decided **only** by real content — the filename and extension are never
consulted anywhere in the classification path. A magic-byte match at the start of
a file is only ever a **candidate**; acceptance additionally requires the whole
file to pass that format's full structural validator.

| Format | Candidate signature | Full validation performed |
|---|---|---|
| PNG | 8-byte signature `89 50 4E 47 0D 0A 1A 0A` (W3C PNG spec) | Every chunk walked from the signature to `IEND` (`length`/`type`/`data`/`CRC` per the spec's chunk layout); first chunk must be `IHDR` of exactly 13 bytes; the file must end exactly at `IEND` — any trailing byte is a rejection. |
| OGG | 4-byte capture pattern `OggS` (RFC 3533 §6) | Every page walked using the RFC 3533 §6 fixed 27-byte header + segment table + payload-length-from-lacing-values layout, until the file ends exactly on a page boundary. |
| GLB | 4-byte magic `glTF` + container structure (Khronos glTF 2.0 spec) | Header length verified against the real file size; every chunk bounds-checked; the JSON chunk parsed; every embedded image payload (bufferView- or data-URI-embedded) recursively validated the same way — see "GLB" below. |
| TEXT (`.md`/`.json`/`.lua`/`.txt`/`.gltf` JSON/…) | No magic byte exists for these formats (design decision, not an ADR) | The **entire** file streamed through an incremental UTF-8 decoder in bounded blocks, checking every byte for disallowed control characters — not a prefix. |

Every binary signature row lives in `tools/validation/magic.py`, one row per
format, each with a comment citing exactly where it was verified (a real
independent implementation's source code, or an official specification
document — see "Signature provenance" below).

## What is rejected, by name (the Blizzard formats)

A Blizzard signature match is a full verdict by itself — no amount of well-formed
structure afterwards would make the file acceptable, so (unlike the whitelist)
these are not followed by further structural validation.

| Format | On-disk bytes | Source of the signature |
|---|---|---|
| DBC (client database) | `WDBC` | AzerothCore (our own server fork's upstream), `DBCFileLoader.cpp` |
| MPQ (archive) | `MPQ\x1a` | StormLib (reference MPQ implementation) |
| BLP2 (texture) | `BLP2` | wow.export (open-source WoW asset viewer), `blp.js` |
| M2 (model) | `MD20` or `MD21` | wow.export, `constants.js` |
| WMO (model, root file) | `REVM`+`DHOM` (on-disk-verified) **or** `MVER`+`MOHD` (forward fallback) | wow.export, `WMOLoader.js` — see "The WMO byte-order fix" below |

Any other binary content that matches none of the rows above is rejected as
`UNKNOWN` — **the accept set is a whitelist, not a blacklist** (ADR-0004): an
unrecognised format is a rejection reason, never a pass.

### Signature provenance

Every citation in `tools/validation/magic.py` was verified on 2026-09-02 by
fetching the named source directly (via `WebFetch` against the official spec/RFC
text for PNG, OGG and GLB; via `gh api` / `WebFetch` against the real source code
of AzerothCore, StormLib and wow.export for the five Blizzard formats —
`wowdev.wiki` itself returned HTTP 403 to automated fetches, so independent
open-source implementations that read/write these formats were used instead).
Every one of the five Blizzard byte sequences matches exactly what the task
specification itself named (`WDBC`, `MPQ\x1a`, `BLP2`, `MD20`/`MD21`,
`MVER`+`MOHD`).

**Every Blizzard on-disk byte value is derived mechanically**, via
`struct.pack("<I", hex_constant)` on the exact integer named in its cited source
— never by a human transcribing or reversing an ASCII string by eye. This is a
direct fix for the round-2 WMO finding (below) applied to all five signatures, not
just the one that was caught.

### The WMO byte-order fix

wow.export's `WMOLoader.js` reads a chunk's 4-byte tag with `readUInt32LE()` and
compares the resulting **integer** against `0x4D564552` (for `MVER`) and
`0x4D4F4844` (for `MOHD`). Converting those integers back to on-disk bytes via
`struct.pack("<I", ...)` gives `b"REVM"` and `b"DHOM"` — **not** the ASCII strings
`"MVER"`/`"MOHD"`. WoW's chunked formats (WMO, ADT, WDT) store the four-character
chunk tag byte-reversed on disk relative to how it is conventionally written in
documentation and tools. Running the same derivation on DBC/MPQ/BLP/M2 confirms
their on-disk bytes are the forward ASCII form — only WMO is affected.

Because it is not certain every real-world WMO-family file in the wild follows the
reversed convention (the forward spelling is common informally, including in some
tools), the WMO matcher accepts **both** orderings and reports which one matched
in the rejection reason (e.g. `"... (matched the on-disk chunk-tag byte order:
reversed.)"`) — a missed detection (false negative) is a worse failure for a
security-relevant blacklist entry than an extra defensive branch.

## The text bucket

None of plain text, JSON, Lua or Markdown has a magic-byte signature — there is
nothing to cite, because no such signature exists. This is a deliberate design
decision (not sourced from any ADR — none defines one): the scanner treats these
four extensions' content as one whitelist bucket, "TEXT", accepted purely on
content, checked over the **entire file**:

1. no NUL byte and no other disallowed control byte (everything in `0x00–0x1F`
   except tab/LF/CR, plus `0x7F`) anywhere in the file, and
2. the whole file decodes as UTF-8.

This still never consults the extension — a `.dbc` file containing plain text
would be accepted as TEXT exactly the same way a `.txt` file would. Round-2
finding 1 was exactly the gap this created when only a 4096-byte prefix was
checked; `validate_text_fully` (in `scan_assets.py`) now streams the whole file
through an incremental UTF-8 decoder in bounded 64 KiB blocks (bounded memory
regardless of file size), up to the size ceiling below.

Full per-format syntax validation (actually parsing `.json` as JSON, or `.lua` as
Lua) remains out of scope and is disclosed below under Known Limitations.

## GLB: the interior is walked recursively, not sniffed

A GLB is a container: a 12-byte header (`magic`, `version`, `length`) followed by
one or more length-prefixed chunks (`chunkLength`, `chunkType`, `chunkData`). The
scanner:

1. Verifies the header's declared `length` matches the file/region's real size.
2. Walks every chunk, bounds-checking `chunkLength` against the bytes actually
   remaining **before** touching that memory (Python's arbitrary-precision
   integers mean `offset + chunkLength` can never wrap around the way a
   fixed-width sum could — asserted explicitly in code and exercised by a fixture
   using the maximum possible `chunkLength`, `0xFFFFFFFF`). Any leftover bytes
   after the last chunk are not silently ignored: the loop's own invariant means
   the next iteration tries to parse them as another chunk header and fails
   loudly if they aren't one.
3. Parses the mandatory first (JSON) chunk as glTF JSON.
4. Locates every **embedded** image payload reachable from that JSON, through
   both mechanisms the glTF 2.0 spec defines for embedding binary data in a GLB:
   a `bufferView`-referenced image backed by buffer `0` with no `uri` (i.e. the
   GLB's own `BIN` chunk), and a `data:` URI (base64-encoded binary directly in
   the JSON chunk text).
5. **Each embedded payload is validated by recursing into the same top-level
   dispatcher used for real files** (`classify_window`, in `scan_assets.py`) — not
   a separate, shallower "embedded payload" check. If that payload is itself a
   GLB, it is fully, recursively parsed as one (round-2 criterion 11); if it is
   PNG/OGG/TEXT, it gets the same full-file validation a top-level file of that
   type would. If not whitelisted, the outer GLB is rejected with the embedded
   format named and the (real, seekable) file offset of the payload reported —
   or, for a data-URI payload, the offset within the decoded buffer, since a
   base64-decoded payload has no single file byte position of its own.

Recursion is bounded by `MAX_GLB_NESTING_DEPTH` (8) to guard against pathological
or adversarial nesting. A GLB whose only embedded content is whitelisted (e.g. an
embedded PNG texture) passes. Buffers with an external `uri` are not bytes inside
this file and are out of scope for the container walk — if present as separate
files in the same tree, the top-level walk inspects them in their own right.

## Ceilings: what "full validation" is bounded by

Proving a whole file is well-formed means the TEXT validator must genuinely read
every byte, and the chunk-walking validators (PNG/OGG/GLB) must genuinely visit
every chunk/page — both bounded, but "bounded" needs concrete numbers, stated here
rather than left implicit (round-2 criterion 10):

- **`MAX_FULL_SCAN_BYTES` = 256 MiB.** The largest file this scanner will fully
  validate. Generous for any real WotLK-era mod asset (a texture, a short music
  track, a modest model) while keeping the guaranteed worst case (the TEXT path —
  PNG/OGG/GLB never read chunk *payload* bytes into memory, only small fixed
  headers, seeking over the rest) bounded and predictable. **A file over this
  ceiling is rejected outright** with a named reason
  (`"... over the 268435456 byte full-validation ceiling; refused rather than
  accepted on a partial scan"`) — never silently truncated and accepted on a
  partial scan.
- **`MAX_CHUNK_COUNT` = 100,000.** PNG chunks, Ogg pages and GLB chunks are each
  skipped over via a seek rather than a full read, so the byte ceiling alone does
  not bound how many chunks a pathological file could declare (e.g. millions of
  zero-length PNG chunks). This bounds the iteration count independently of file
  size.
- **`MAX_GLB_NESTING_DEPTH` = 8.** Bounds how deep GLB-embeds-GLB recursion is
  followed before refusing.
- **`TEXT_BLOCK_SIZE` = 64 KiB.** The TEXT validator's streaming block size —
  never more than one block resident in memory at once, however large the file
  (up to the byte ceiling above).

## Hostile input — fails closed, never a traceback

| Input | What happens |
|---|---|
| Empty file | Rejected as `MALFORMED`, reason "file is empty". |
| A file that is only a whitelisted signature and nothing else (e.g. 8 bytes of PNG header, 4 bytes of `OggS`) | Rejected as `MALFORMED` — a truncated-but-valid-looking prefix is not accepted (round-2 criterion 9). |
| A well-formed PNG/OGG/GLB/TEXT file with arbitrary bytes appended after its structural end | Rejected as `MALFORMED`, naming the trailing/unparseable data (round-2 criterion 8). |
| An embedded GLB payload that is itself a fake container (correct magic/length, garbage chunk contents) | Rejected — recursively validated as a real container and found malformed, never accepted on a header sniff (round-2 criterion 11). |
| File shorter than any known signature and not valid text (e.g. 3 bytes) | Rejected as `UNKNOWN`. |
| GLB chunk length that would read past the end of the file, or that uses the maximum uint32 value | Rejected as `MALFORMED`, the offending chunk's file offset reported; the same bounds check (exact Python-integer arithmetic) catches both. |
| File over `MAX_FULL_SCAN_BYTES` | Rejected as `MALFORMED`, naming the ceiling — never partially scanned and accepted. |
| Pathological chunk/page count | Rejected once `MAX_CHUNK_COUNT` is exceeded. |
| Directory nesting past 40 levels | Not descended further; recorded as a `scan_errors` entry naming the directory and the depth limit. |
| A symlink | Never followed (not read at all); counted in `summary.skipped_reasons`. |
| Anything else the filesystem refuses to open/stat/list, or any other unanticipated error | Turned into a named `scan_errors` entry (directory-level) or a `MALFORMED` rejection carrying the exception itself (file-level, a last-resort safety net around the whole classification call) — never an unhandled traceback on stderr. There is no bare `except: pass` anywhere in the tool. |

## The report

Matches `contracts/validation-report.schema.json` (edges E5/E6). Top-level shape
(unchanged in structure from round 1 — round 2 changed what gets accepted/rejected
and why, not the report's field names):

```jsonc
{
  "schema_version": "1.0.0",
  "root": "<path argument, verbatim>",
  "summary": {
    "files_inspected": 0,   // files actually opened and classified — a counter
                             // that reads reality (ADR-0115 §1)
    "files_accepted": 0,
    "files_rejected": 0,
    "files_skipped": 0,     // benign, named skips (symlinks, non-regular files)
    "skipped_reasons": {},  // every skip reason, with its count
    "scan_errors": 0        // directory-level problems (e.g. depth exceeded)
  },
  "accepted": [ { "path": "...", "format": "PNG" }, ... ],
  "rejected": [
    { "path": "...", "detected_format": "DBC", "signature_offset": 0, "reason": "..." }
  ],
  "scan_errors": [ { "path": "...", "reason": "..." } ]
}
```

`files_inspected` always equals `files_accepted + files_rejected`. Report
generation contains no timestamp or other non-deterministic field: the same input
tree produces a byte-identical report on every run.

## Determinism and offline operation

- File lists, and every JSON array walked while validating (images/bufferViews),
  are processed in a fixed, deterministic order.
- No wall-clock value, random value, or environment-dependent value appears in the
  report.
- The tool imports only Python stdlib modules (`argparse`, `base64`, `codecs`,
  `dataclasses`, `json`, `os`, `pathlib`, `struct`, `sys`, `typing`) — none of
  which can reach the network.

## Testing

```
python3 -m unittest discover -s tests/validation -v
```

`tests/validation/fixture_builder.py` builds every fixture from real bytes (a
genuinely decodable PNG built with `zlib`, a structurally correct GLB built with
`struct`, etc.). Per round-2 criterion 13, every Blizzard-format fixture is
derived **mechanically** from an independently re-stated hex constant (via
`struct.pack`), and `fixture_builder.py` never imports `tools/validation/magic.py`
— so a byte-order bug in one cannot be silently mirrored by the other the way the
round-2 WMO bug was. `tests/validation/schema_check.py` is a small stdlib-only
JSON Schema subset validator (no `jsonschema` package is installed in this
environment, and the tool stays dependency-free) used to prove report output
actually conforms to `contracts/validation-report.schema.json`.

## Known limitations (explicit, not silent)

Disclosed deliberately, per round-2 criterion 14 — a security document that omits
its own bypasses is worse than none, because it stops people looking:

- **Chunk/page checksums are not verified.** The PNG validator does not check each
  chunk's CRC; the OGG validator does not check each page's CRC. Both verify
  *framing* only (lengths, types, and that the file ends exactly where the
  structure says it should) — which is what actually closes the "arbitrary
  trailing bytes" bypass this round-2 pass was built to fix, since a mismatched
  CRC on an otherwise well-framed chunk is a corruption/decoder concern, not a
  smuggled-payload concern (a well-crafted attack would simply compute a correct
  CRC for its wrapper anyway; the framing-to-EOF check is what actually stops it).
  A file with correct framing but a corrupted CRC would still be accepted.
- **OGG logical-stream continuity is not verified.** Serial-number consistency,
  packet-sequencing correctness, and codec-specific structure (Vorbis/Opus
  headers) are not checked — only page framing. A crafted file whose trailing
  bytes happen to form additional syntactically valid Ogg pages of an unrelated
  logical stream would still pass; a raw Blizzard payload glued on will not (its
  bytes must literally begin with `OggS` to even be considered a page, which is
  never true of any of the five cited Blizzard magic values).
- **PNG pixel/palette semantics are not decoded.** This is a container-framing
  validator, not an image decoder — `IDAT` content is never decompressed or
  interpreted.
- **The text bucket is format-agnostic.** It verifies UTF-8 + no disallowed
  control bytes, not that `.json` content is well-formed JSON or that `.lua`
  content is syntactically valid Lua.
- **`data:` URI images that are not base64-encoded are not sniffed** (rare in
  practice) — they cannot carry an arbitrary binary payload the way a base64 URI
  or a `BIN`-chunk bufferView can.
- **Files over 268435456 bytes (256 MiB) are rejected outright**, not scanned —
  see "Ceilings" above. A legitimate mod asset over this size would need this
  ceiling raised deliberately, not worked around.
- **GLB embedding nesting is bounded at 8 levels** (`MAX_GLB_NESTING_DEPTH`) and
  chunk/page counts at 100,000 (`MAX_CHUNK_COUNT`) — both named, both refuse
  rather than hang or exhaust memory on a pathological input.
- The scanner does not judge asset provenance, originality, or "AI-ness" — that is
  explicitly out of scope per ADR-0061 and is not attempted anywhere in this tool.
