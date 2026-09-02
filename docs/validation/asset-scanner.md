# Asset scanner

`tools/validation/scan_assets.py` walks a directory tree, identifies every regular
file's real type by **magic bytes** (never by extension), accepts only whitelisted
formats, and rejects everything else — naming Blizzard formats explicitly when it
finds them, including payloads embedded inside GLB containers. It is the mechanical
enforcement of [ADR-0004](../decisions/0004-own-assets-only.md) ("own assets only;
never Blizzard data") and implements node **N4** (`validation-core`, asset-scanning
half) of the registry's dependency graph, against contract edges **E5**/**E6**
(`contracts/validation-report.schema.json`).

It has two callers today (why N4 is its own component rather than folded into the
build pipeline): the registry PR gate (N3, edge E5) and the build pipeline (N5,
edge E6). Both invoke it the same way and get the same report shape back.

## Why Python, stdlib only

The task allowed either Python or a `.mjs` (Node) runtime. Python was chosen because:

- This environment has Python 3 available and no Node.js runtime was found at
  authoring time.
- `struct.unpack` gives explicit, precise control over endianness and bounds for
  every integer field the GLB binary format defines — exactly what a fail-closed
  container parser needs.
- No third-party dependency is required for anything the scanner does (binary
  parsing: `struct`; JSON: `json`; base64 data-URI decoding: `base64`). Stdlib-only
  means nothing to install, ever, to run this tool — the boring, predictable
  choice (ADR-0103), and a precondition for the "runs offline" acceptance
  criterion (nothing to fetch from a package index either).

## Running it

```
python3 tools/validation/scan_assets.py <path-to-scan> [-o report.json]
```

Without `-o`, the JSON report is printed to stdout. Exit code:

- `0` — every file was inspected and accepted; no scan errors.
- `1` — at least one file was rejected, or a scan error occurred (e.g. a
  directory nested past the depth limit).
- `2` — usage error (the given path does not exist or is not a directory).

## What is accepted (the whitelist)

Format is decided **only** by the real bytes at the start of a file (and, for GLB,
by parsing its container structure) — the filename and extension are never
consulted anywhere in the classification path.

| Format | How it is recognised | Source of the signature |
|---|---|---|
| PNG | 8-byte signature `89 50 4E 47 0D 0A 1A 0A` | W3C PNG spec, §"PNG file signature" |
| OGG | 4-byte capture pattern `OggS` | RFC 3533 §6 |
| GLB | 4-byte magic `glTF` + valid container structure (see below) | Khronos glTF 2.0 Specification, "Binary glTF Layout" |
| Text (`.md`/`.json`/`.lua`/`.txt`/`.gltf` JSON/…) | content decodes as UTF-8, no NUL or other disallowed control byte in the sampled header | design decision — see "The text bucket" below |

Every signature row lives in `tools/validation/magic.py`, one row per format, each
with a comment citing exactly where it was verified (a real independent
implementation's source code, or an official specification document — see
"Signature provenance" below). No signature was shipped from unverified memory.

## What is rejected, by name (the Blizzard formats)

| Format | Magic bytes | Source of the signature |
|---|---|---|
| DBC (client database) | `WDBC` | AzerothCore (our own server fork's upstream), `DBCFileLoader.cpp` |
| MPQ (archive) | `MPQ\x1a` | StormLib (reference MPQ implementation) |
| BLP2 (texture) | `BLP2` | wow.export (open-source WoW asset viewer), `blp.js` |
| M2 (model) | `MD20` or `MD21` | wow.export, `constants.js` |
| WMO (model, root file) | `MVER` chunk followed by `MOHD` chunk | wow.export, `WMOLoader.js` |

Any other binary content that matches none of the rows above is rejected as
`UNKNOWN` — **the accept set is a whitelist, not a blacklist** (ADR-0004): an
unrecognised format is a rejection reason, never a pass.

### Signature provenance

Every citation in `tools/validation/magic.py` was verified on 2026-09-02 by
fetching the named source directly (via `WebFetch` against the official spec/RFC
text for PNG, OGG and GLB; via `gh api` / `WebFetch` against the real source code
of AzerothCore, StormLib and wow.export for the five Blizzard formats — `wowdev.wiki`
itself returned HTTP 403 to automated fetches, so independent open-source
implementations that read/write these formats were used instead). None of the five
Blizzard signatures was invented from memory; each matches the exact byte value the
task specification itself named (`WDBC`, `MPQ\x1a`, `BLP2`, `MD20`/`MD21`,
`MVER`+`MOHD`), and each is now additionally backed by a citable, independently
fetched source in the code comment.

## The text bucket

None of plain text, JSON, Lua or Markdown has a magic-byte signature — there is
nothing to cite, because no such signature exists. This is a deliberate design
decision (not sourced from any ADR — none defines one): the scanner treats these
four extensions' content as one whitelist bucket, "TEXT", accepted purely on
content:

1. no NUL byte and no other disallowed control byte (everything in `0x00–0x1F`
   except tab/LF/CR, plus `0x7F`) in the sampled header, and
2. the sampled header decodes as UTF-8.

This still never consults the extension — a `.dbc` file containing plain text
would be accepted as TEXT exactly the same way a `.txt` file would. This is
logged as a booked assumption in the task log; if stricter per-format validation
(e.g. actually parsing `.json` as JSON, or `.lua` as Lua) is wanted later, that is
a follow-up, not a gap in the current whitelist/blacklist mechanism ADR-0004 asks
for.

## GLB: the interior is walked, not skipped

A GLB is a container: a 12-byte header (`magic`, `version`, `length`) followed by
one or more length-prefixed chunks (`chunkLength`, `chunkType`, `chunkData`). The
scanner:

1. Verifies the header's declared `length` matches the file's real size.
2. Walks every chunk, bounds-checking `chunkLength` against the bytes actually
   remaining in the file **before** touching that memory (Python's
   arbitrary-precision integers mean `offset + chunkLength` can never wrap around
   the way a fixed-width sum could — this is asserted explicitly in code and
   exercised by a fixture using the maximum possible `chunkLength`,
   `0xFFFFFFFF`).
3. Parses the mandatory first (JSON) chunk as glTF JSON.
4. Locates every **embedded** image payload reachable from that JSON, through
   both mechanisms the glTF 2.0 spec defines for embedding binary data in a GLB:
   - a `bufferView`-referenced image whose buffer is buffer `0` with no `uri`
     (i.e. backed by the GLB's own `BIN` chunk — the standard mechanism), and
   - a `data:` URI (base64-encoded binary directly inside the JSON chunk).
5. For each one found, reads a bounded prefix of the payload (never the whole
   thing) at its real file offset and classifies it exactly as it would a
   top-level file. If that payload is not whitelisted, the GLB is rejected with
   the embedded format named and the file offset reported.

A GLB whose only embedded content is whitelisted (e.g. an embedded PNG texture)
passes. Buffers with an external `uri` are not bytes inside this file and are out
of scope for the container walk — if present as separate files in the same tree,
the top-level walk inspects them in their own right.

## Hostile input — fails closed, never a traceback

| Input | What happens |
|---|---|
| Empty file | Rejected as `MALFORMED`, reason "file is empty". |
| File shorter than any known signature (e.g. 3 bytes) | Rejected as `UNKNOWN` if it also isn't valid text. |
| GLB chunk length that would read past the end of the file | Rejected as `MALFORMED`, the offending chunk's file offset reported. |
| GLB chunk length at the maximum uint32 value (`0xFFFFFFFF`) | Same bounds check catches it — no special-cased "overflow" branch is needed because the arithmetic is exact. |
| Directory nesting past 40 levels | Not descended further; recorded as a `scan_errors` entry naming the directory and the depth limit. |
| A symlink | Never followed (not read at all); counted in `summary.skipped_reasons`. |
| Anything else the filesystem refuses to open/stat/list | Turned into a named `scan_errors` (directory-level) or an `UNKNOWN`/`MALFORMED` rejection (file-level) — never an unhandled exception. There is no bare `except: pass` anywhere in the tool. |

The scanner only ever reads a bounded prefix of a file to identify it
(`magic.HEADER_PROBE_SIZE`, 4096 bytes — comfortably larger than every signature
in the table, including the two-chunk WMO check) — it does not load whole files
into memory, so it survives a large file the same way it survives a tiny one.

## The report

Matches `contracts/validation-report.schema.json` (edges E5/E6). Top-level shape:

```jsonc
{
  "schema_version": "1.0.0",
  "root": "<path argument, verbatim>",
  "summary": {
    "files_inspected": 0,   // files actually opened and read — a counter that
                             // reads reality (ADR-0115 §1), not a count of paths
                             // merely listed by the walk
    "files_accepted": 0,
    "files_rejected": 0,
    "files_skipped": 0,     // benign, named skips (symlinks, non-regular files)
    "skipped_reasons": {},  // every skip reason, with its count — nothing is
                             // ever silently dropped
    "scan_errors": 0        // directory-level problems (e.g. depth exceeded)
  },
  "accepted": [ { "path": "...", "format": "PNG" }, ... ],
  "rejected": [
    { "path": "...", "detected_format": "DBC", "signature_offset": 0, "reason": "..." }
  ],
  "scan_errors": [ { "path": "...", "reason": "..." } ]
}
```

`files_inspected` always equals `files_accepted + files_rejected` — every file the
walker opens ends up in exactly one of those two buckets. Report generation
contains no timestamp or other non-deterministic field: the same input tree
produces a byte-identical report on every run (proven in the test suite by
running the CLI twice and diffing stdout, and by SHA-256 of the output).

## Determinism and offline operation

- File lists are sorted by path before being written to the report.
- No wall-clock value, random value, or environment-dependent value appears in
  the report.
- The tool imports only Python stdlib modules (`argparse`, `base64`, `dataclasses`,
  `json`, `os`, `pathlib`, `struct`, `sys`, `typing`) — none of which can reach the
  network. There is no code path in this tool that performs any network I/O.

## Testing

```
python3 -m unittest discover -s tests/validation -v
```

`tests/validation/fixture_builder.py` builds every fixture from real bytes (a
genuinely decodable PNG built with `zlib`, a structurally correct GLB built with
`struct`, etc.) rather than hand-typed literals whose correctness would depend on
memory. `tests/validation/schema_check.py` is a small stdlib-only JSON Schema
subset validator (no `jsonschema` package is installed in this environment, and
the task requires the tool stay dependency-free) used to prove report output
actually conforms to `contracts/validation-report.schema.json`.

## Known limitations (explicit, not silent)

- The text bucket does not validate that `.json` content is well-formed JSON, or
  that `.lua` content is syntactically valid Lua — it only verifies the content is
  plain UTF-8 text. Full per-format syntax validation is out of this task's scope
  (asset *type* whitelisting, not manifest/script correctness) and is not claimed.
- `data:` URI images that are **not** base64-encoded (rare in practice) are not
  sniffed, since they cannot carry an arbitrary binary payload the way a base64
  URI or a `BIN`-chunk bufferView can.
- The scanner does not judge asset provenance, originality, or "AI-ness" — that is
  explicitly out of scope per ADR-0061 and is not attempted anywhere in this tool.
