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

## Spec amendment — round 3: content whitelisting, not container framing

Round 2 closed "bytes after the file ends". Independent adversarial review then moved the
same violation *inside* the container and got Blizzard payloads accepted twice more:

1. **A valid PNG carrying a DBC in a private chunk.** Correct signature, `IHDR`, `IDAT`,
   `IEND`, correct CRCs on every chunk, no trailing bytes — plus one private ancillary
   chunk, `zBLZ`, whose declared-length data was a complete, magic-intact DBC file. Every
   PNG decoder in the world opens and displays it. Round 2 accepted it, exit code 0.
2. **A valid Ogg page whose payload was a DBC.** A structurally perfect page per RFC 3533
   §6, whose lacing-declared payload *was* the DBC's bytes. Accepted, exit code 0.

Neither was a bug in the round-2 implementation: both files are well-formed by their own
container specifications, because PNG and Ogg both permit arbitrary bytes inside private
chunks and codec payloads. A validator that verifies framing answers "is this a
syntactically valid container?" when the question is "does this carry only permitted
content?".

[**ADR-0120**](../decisions/0120-content-whitelist-not-container-framing.md) settles it by
decision rather than by another attempt at wording:

> An accepted asset contains only content of types the platform has explicitly permitted.

Magic-byte typing decides what a file *is*; content whitelisting decides what it may
*contain*. Both must pass.

**Verifying CRCs is not the fix, and is deliberately not implemented.** An attacker computes
the correct CRC over their own payload. CRCs detect corruption, not smuggling. This was
suggested in review; ADR-0120 rejects it explicitly.

### PNG: the permitted chunk types

Only these chunk types may appear at all. Anything else — unknown, private, or merely
unlisted — is a rejection, *including* ancillary chunks that are harmless in other contexts.

| Chunk | Role | Length constraint enforced |
|---|---|---|
| `IHDR` | Image header | Exactly 13 bytes; dimensions non-zero; colour type in {0,2,3,4,6}; bit depth legal for that colour type; compression and filter method 0; interlace 0 or 1 |
| `PLTE` | Palette | Non-empty multiple of 3, at most 768 bytes; required for colour type 3, forbidden for 0 and 4; must precede `IDAT` |
| `IDAT` | The compressed pixel data | Must be present, in one consecutive run; the concatenated zlib stream must inflate to **exactly** the byte count `IHDR` implies, and must end exactly where the last `IDAT` ends |
| `IEND` | End marker | Exactly 0 bytes; the file must end here |

Plus the **safe list**. It is short by design, and every entry is admitted under a rule with
two halves, both required:

- **(a)** the PNG specification fixes the chunk's length at a handful of bytes, *and* this
  scanner enforces that exact length — so a permitted *type* can never be reused as a
  general-purpose container; and
- **(b)** either the chunk changes how the image renders, or refusing it would reject the
  unconditional default output of ordinary image editors.

"Harmless" alone is never sufficient. Each entry's written reason follows.

### `tRNS`

Transparency. For an indexed-colour image this is the only place alpha exists at all, and for greyscale/truecolour it carries the single colour-key value; dropping it visibly changes the image, and no re-export preserves the art without it. The spec fixes its length exactly from IHDR's colour type (2 bytes greyscale, 6 bytes truecolour, at most one byte per palette entry for indexed), and this scanner enforces that length, so the chunk cannot be reused as a general-purpose container.

### `gAMA`

Image gamma: one 4-byte unsigned integer, length fixed by the spec and enforced here. Four bytes cannot carry smuggled content, and without it an image authored on a non-2.2 pipeline renders at the wrong brightness in the client.

### `pHYs`

Physical pixel dimensions: two 4-byte unsigned integers and a one-byte unit specifier, 9 bytes, length fixed by the spec and enforced here, unit value range enforced here. This one is admitted under half (b)'s second branch: it does not affect how the client renders a texture, but essentially every image editor writes it unconditionally (9% of a 91-file real-world corpus, 66% of the World of Warcraft add-on PNGs surveyed), and a rule that rejects an editor's default export teaches authors to reach for byte-stripping tools rather than to comply. The price is 9 spec-fixed bytes per file.

### `sRGB`

sRGB rendering intent: one enumerated byte (0-3), length fixed by the spec and enforced here, value range enforced here. One byte cannot carry smuggled content. It is on the list because it is the small, fixed-length alternative to iCCP -- authors who need to declare colour intent can do so without an embedded profile.

Prevalence figures in those reasons come from a survey of every PNG on the development
machine (91 files that parse as PNG) plus the World of Warcraft add-on corpus at
`/mnt/e/wow-ebonhold` (9 files), counted by chunk type. The survey is reproduced in the task
log; the headline numbers are `IHDR`/`IDAT`/`IEND` 100%, `PLTE` 67%, `tRNS` 59%, `pHYs` 9%
(66% in the add-on corpus), `iTXt` 4%, `iCCP` 4%, `eXIf`/`tEXt` 3%, `tIME`/`sBIT` 2%.

**Deliberately *not* on the list**, with the reason:

| Chunk | Why not |
|---|---|
| `iCCP` | An embedded ICC profile is an arbitrary-length compressed blob — exactly the shape of the `zBLZ` attack, with a respectable name. ADR-0120 §4 names colour profiles as an accepted cost. |
| `tEXt`, `zTXt`, `iTXt` | Free-form (and, for two of them, compressed) text of unbounded length. Text metadata is named in ADR-0120 §4 as an accepted cost. |
| `eXIf` | An arbitrary TIFF-structured metadata blob with its own nested container inside it. |
| `bKGD`, `hIST`, `sBIT`, `tIME`, `cHRM`, `cICP`, `sPLT` | Fixed or bounded length, and genuinely harmless — but half (b) fails: the client does not render differently without them and they are not written unconditionally by ordinary exporters. ADR-0120 is explicit that harmless-elsewhere is not a qualification. |
| `acTL`, `fcTL`, `fdAT` | APNG animation. Out of scope for this platform's textures; adding them means deciding what an animation frame may contain, which is a separate decision. |
| `iDOT` | An undocumented Apple extension seen in 3% of the corpus. Undocumented means its permitted contents cannot be stated, so it cannot be permitted. |
| anything else | Private, unregistered, or simply not listed. |

### Ogg: the payload must be Vorbis or Opus

Page framing (RFC 3533 §6) is still validated exactly as in round 2 — it is what bounds the
file and catches trailing data. On top of it, every logical bitstream must now identify
itself as a codec this platform permits:

- The **first packet** of each logical bitstream (assembled across pages from the segment
  table's lacing values, so a header packet that spans pages is handled) must be either a
  Vorbis identification header (`\x01vorbis`, 30 bytes, version 0, non-zero channels and
  sample rate, in-range block sizes, framing bit set) or an Opus one (`OpusHead`, RFC 7845
  §5.1, major version 0, non-zero channels, length fixed by the channel mapping family).
- The **comment header** must follow (`\x03vorbis` / `OpusTags`), and is parsed in full:
  vendor string and every tag must be printable UTF-8 text, tag count at most 1024, and the
  packet must be consumed exactly. Opus permits zero-padding after the tag list (RFC 7845
  §5.2) and real encoders use it, so up to 4096 bytes of padding are allowed **only when
  every padding byte is zero** — that keeps opusenc's output working without leaving a place
  to put content.
- For Vorbis, the **setup header** (`\x05vorbis`) must be present. Its codebook bytes are
  not parsed — see "What is read and what is not".
- At end of file, every logical bitstream must have completed its headers. A stream that
  never did is rejected, naming the offset of its first page.

A page whose payload is a DBC therefore fails at the first packet: its bytes are neither
`\x01vorbis` nor `OpusHead`.

### Rejections tell the author what to do

ADR-0120 §3: a rejection the author cannot act on is a defect, not a security measure. Every
rejection in the report now carries a **`remedy`** field alongside `reason` — a separate
contract field, so a caller (a PR comment, an upload form) can surface it without re-parsing
prose. The report schema version is `1.1.0`; the field is required and never empty.

```
"reason": "... PNG contains chunk 'zBLZ' (ancillary, public-namespace) at offset 33,
           carrying 20 byte(s) of data. That chunk type is not on the permitted content
           list ...",
"remedy": "Re-export the image as a plain PNG without private chunks, embedded metadata or
           colour profiles -- in most editors that is 'export as PNG' with metadata
           disabled; from the command line, `pngcrush -rem alla -rem text in.png out.png`
           removes every ancillary chunk this scanner does not permit. ..."
```

### The accepted cost

This tightening rejects some legitimate files: colour profiles, text metadata,
unusual-but-valid chunks, and Ogg files carrying codecs other than Vorbis and Opus. Ludwig
made that trade deliberately (ADR-0120 §4): an author can re-export, whereas a smuggling
channel through the platform's own content guarantee cannot be undone once used.

Measured, not estimated. The scanner was run over 130 real third-party files gathered from
this machine and from an installed World of Warcraft add-on tree — none of them written for
this project, none of them adjusted to pass:

- **102 files named `.png`.** Two are actually JPEGs (`FF D8 FF E0 ... JFIF`) and are
  correctly rejected as `UNKNOWN` — criterion 4 working on real data, not a false rejection.
  Of the 100 genuine PNGs, **88 are accepted (88%)** and 12 are rejected: `iCCP` ×4,
  `iTXt` ×3, `tEXt` ×2, `cHRM` ×1, `tIME` ×1, `bKGD` ×1. Every one of the 12 is fixable by
  re-exporting, and the rejection says so.
- **28 files named `.ogg`.** One is actually an MP4 (`ftypisom`) and is correctly rejected.
  The other **27 are genuine Ogg Vorbis and all 27 are accepted** — including their vendor
  strings and tags, which the codec-header parser reads in full.

Reproduce with `python3 tools/validation/scan_assets.py <corpus-dir>`; the exact commands are
in the task log.

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
| PNG | 8-byte signature `89 50 4E 47 0D 0A 1A 0A` (W3C PNG spec) | Every chunk walked from the signature to `IEND`; **every chunk type must be on the permitted content list** and satisfy its length constraint; the `IDAT` zlib stream must inflate to exactly the size `IHDR` implies; the file must end exactly at `IEND`. See "Spec amendment — round 3". |
| OGG | 4-byte capture pattern `OggS` (RFC 3533 §6) | Every page walked using the RFC 3533 §6 layout until the file ends exactly on a page boundary, **and** every logical bitstream must parse as Vorbis (Vorbis I §4.2) or Opus (RFC 7845 §5) headers. See "Spec amendment — round 3". |
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

Disclosed deliberately — a security document that omits its own bypasses is worse than none,
because it stops people looking. Round-3 criterion 19 requires this section to say plainly
**which bytes are inspected and which are not, per format**, rather than describing
content-blindness as a checksum nicety.

### What is read and what is not

| Format | Bytes read and checked | Bytes never looked at |
|---|---|---|
| **PNG** | The 8-byte signature. Every chunk's 8-byte header (length + type), for every chunk to `IEND`. `IHDR`'s 13 data bytes in full. Every safe-list chunk's data in full (at most 256 bytes each). The whole `IDAT` zlib stream, decompressed and counted. | The **inflated pixel bytes themselves** — they are counted, not examined. Every chunk's 4-byte CRC. |
| **Ogg** | Every page's 27-byte header and segment table. For each logical bitstream, the identification and comment header packets **in full**, including every vendor string and tag. | The **Vorbis setup header's codebook bytes** (`\x05vorbis`; presence and marker checked, contents not parsed). Every **audio packet** on every page after the headers — the page framing around them is checked, the payload bytes are not read at all. Every page's CRC. |
| **GLB** | The 12-byte header and every chunk header. The JSON chunk in full (parsed as JSON). Every embedded image payload, recursively, by exactly these same rules. | Buffer bytes that no `images[]` entry references — accessor/mesh/animation data is bounds-checked as part of the BIN chunk but its contents are not interpreted. |
| **TEXT** (`.md`/`.json`/`.lua`/`.txt`/`.gltf`) | Every byte, streamed: valid UTF-8, no disallowed control bytes. | Nothing is skipped — but nothing is understood either: there is no JSON, Lua or glTF **grammar** check, so any valid-UTF-8 text is accepted whatever it says. |

The two rows in the right-hand column that matter most:

- **PNG pixel data.** The `IDAT` stream must inflate to exactly the byte count `IHDR`
  implies and must end exactly where the last `IDAT` chunk ends, so it cannot carry surplus
  bytes *alongside* an image. It can still carry data *as* the image: an attacker can make a
  picture whose pixel values happen to be another file's bytes. Nothing short of re-encoding
  distinguishes that from a picture, because it **is** a picture.
- **Ogg audio packets and Vorbis codebooks.** Their bytes are compressed audio and codec
  tables; there is no way to tell "unusual audio" from "a payload" without a decoder. The
  headers around them are fully validated, so a file must at least be a real Vorbis or Opus
  stream to reach that point.

**The stronger guarantee that is deliberately not built: re-encoding on ingest.** Decoding
every asset and re-emitting it, discarding anything that is not pixel or sample data, is the
only thing that closes the two rows above. ADR-0120 considered it (option B) and did not
adopt it now, because it conflicts with authors shipping their own assets untouched
(ADR-0004). It is recorded there as the available hardening if the whitelist proves leaky. So
the whitelist is not airtight, and this document does not claim it is.

### Checksums

Chunk and page CRCs are **not** verified, and this is not the residual gap — it is not a gap
at all. Whoever writes a chunk computes its CRC, so an attacker's payload carries a perfectly
correct one; the two accepted attacks that produced ADR-0120 both had valid CRCs throughout.
CRCs **detect corruption, not smuggling** (ADR-0120, "Context"). Implementing them would add
a checksum algorithm's polynomial and variant to the code — the same class of
verified-from-memory risk that produced the round-2 WMO byte-order bug — and buy nothing
against this threat model. If the platform later wants corruption detection as a
*separate*, non-security feature, that is a different decision.

### Ceilings

All named constants in `tools/validation/scan_assets.py`, all refusing rather than hanging or
exhausting memory. See "Ceilings" above for the reasoning behind each number.

- Files over `MAX_FULL_SCAN_BYTES` = 268435456 bytes (256 MiB) are **rejected outright**, not
  partially scanned and accepted.
- `MAX_PNG_RAW_BYTES` = 536870912 (512 MiB): a PNG whose `IHDR` declares a raster larger than
  this is refused before any decompression is attempted.
- `MAX_CHUNK_COUNT` = 100000 chunks/pages per container.
- `MAX_GLB_NESTING_DEPTH` = 8 levels of container-inside-container.
- `MAX_OGG_LOGICAL_STREAMS` = 16, `MAX_OGG_HEADER_PACKET_BYTES` = 262144,
  `MAX_OGG_COMMENT_COUNT` = 1024, `MAX_OGG_TAG_PADDING_BYTES` = 4096.

A legitimate asset over any of these would need the ceiling raised deliberately, not worked
around.

### Other disclosed gaps

- **`data:` URI images that are not base64-encoded are not sniffed** (rare in practice) —
  they cannot carry an arbitrary binary payload the way a base64 URI or a `BIN`-chunk
  bufferView can.
- **Ogg logical-stream continuity beyond the headers is not verified.** Page sequence numbers
  and granule positions are not checked for monotonicity. A file whose pages are validly
  framed, whose streams all carry real Vorbis/Opus headers, but whose page order is nonsense
  would be accepted; it would also be an unplayable file, not a carrier.
- **Formats are accepted as whole categories, not per-feature.** A permitted format's future
  extensions are not automatically permitted — ADR-0120's consequence: no format is accepted
  until its permitted interior content is defined. Adding one means deciding what may be
  *inside* it, not just its signature.
- The scanner does not judge asset provenance, originality, or "AI-ness" — explicitly out of
  scope per ADR-0061, and not attempted anywhere in this tool.
