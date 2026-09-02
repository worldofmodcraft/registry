#!/usr/bin/env python3
"""World of Modcraft asset scanner.

Walks a directory tree and accepts a file only if **the entire file, to the last
byte, is a well-formed instance of a whitelisted format** (PNG, OGG, glTF/GLB, or
the text bucket covering plain text/JSON/Lua/Markdown) — not merely "starts with
the right bytes". Named Blizzard formats (DBC/MPQ/BLP/M2/WMO) are rejected outright
on a magic-byte match, including payloads embedded inside GLB containers, which are
validated recursively rather than sniffed. Emits a JSON report matching
contracts/validation-report.schema.json (edges E5/E6 of the registry's dependency
graph) and exits non-zero on any rejection or scan error.

## Spec amendment — round 2 (see docs/tasks/002-asset-scanner.md)

Round 1 built exactly what round 1's spec asked for -- "identify every file's real
type by magic bytes" -- which a signature-at-offset-0 sniffer satisfies completely
while still letting three real bypasses through: padding past the probe window,
arbitrary bytes after a whitelisted header, and a shallow (non-recursive) GLB
interior check. The spec was wrong, not the code; this file is the fix. The
guarantee this scanner now makes, precisely:

    A file is accepted only if the entire file is a well-formed instance of a
    whitelisted format -- parsing reaches the format's real structural end, and
    the file ends exactly there. Never "the first N bytes look right".

This is deliberately not "scan the whole file for forbidden byte sequences": that
approach both false-positives (compressed pixel/audio data legitimately contains
arbitrary bytes) and false-negatives (trivially defeated by compression or an
offset). Proving well-formedness is stricter and quieter -- a PNG with a DBC glued
on after IEND is rejected because it is not a valid PNG, not because we went
looking for the DBC inside it.

Runtime choice: Python 3 (stdlib only — `struct`, `json`, `base64`, `codecs`, `os`).
See docs/validation/asset-scanner.md for the full behaviour writeup, the size/depth
ceilings this file enforces and why, and the residual limitations that are
deliberately disclosed rather than silently left out (round-2 criterion 14).
"""

from __future__ import annotations

import argparse
import base64
import codecs
import json
import os
import struct
import sys
import zlib
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from typing import Optional, Protocol

import magic

# 1.1.0 adds the required per-rejection `remedy` field (round-3 criterion 17 /
# ADR-0120 clause 3). Additive: every 1.0.0 field keeps its name and meaning.
SCHEMA_VERSION = "1.1.0"

# How deep the directory walker will descend before refusing to go further. This is
# what makes "a deeply nested directory" (acceptance criterion 5) fail closed with a
# named error instead of hitting a filesystem path-length limit or a recursion
# error. 40 is generous for any real mod's asset tree.
MAX_DEPTH = 40

# --- Round-2 ceilings ------------------------------------------------------------
#
# Proving a whole file is well-formed (round-2's core requirement) means the TEXT
# validator must genuinely read every byte of a text file, and the chunk-walking
# validators (PNG/OGG/GLB) must genuinely visit every chunk/page. Both are bounded
# work, but "bounded" needs an actual number:
#
# MAX_FULL_SCAN_BYTES: the largest file this scanner will fully validate. 256 MiB
# is generous for any real WotLK-era mod asset (a texture, a short music track, a
# modest model) while keeping the guaranteed-worst-case cost of a full read (the
# TEXT path; PNG/OGG/GLB never read chunk *payload* bytes, only headers -- see
# below) bounded and predictable. A file over this ceiling is rejected outright
# with a named reason ("too large to fully validate") -- never silently truncated
# and accepted on a partial scan, which round-2 explicitly forbids (criterion 10).
MAX_FULL_SCAN_BYTES = 256 * 1024 * 1024

# MAX_CHUNK_COUNT: PNG chunks, Ogg pages and GLB chunks are each skipped over via a
# seek (their payload bytes are never read into memory -- only the small fixed
# header of each one is), so MAX_FULL_SCAN_BYTES alone does not bound how many
# chunks a pathological file could declare (e.g. millions of zero-length PNG
# chunks). This bounds the iteration count independently of file size.
MAX_CHUNK_COUNT = 100_000

# MAX_GLB_NESTING_DEPTH: a GLB can embed another GLB (via a bufferView or a data:
# URI); this bounds how deep that recursion is followed before refusing, guarding
# against pathological/adversarial nesting.
MAX_GLB_NESTING_DEPTH = 8

# Streaming block size for the full-file TEXT validator (bounded memory: never more
# than one block resident at a time, however large the file).
TEXT_BLOCK_SIZE = 64 * 1024

# GLB container structure, per the Khronos glTF 2.0 Specification (see the citation
# in magic.py's GLB signature row for the exact source and section).
GLB_HEADER_SIZE = 12  # uint32 magic + uint32 version + uint32 length
CHUNK_HEADER_SIZE = 8  # uint32 chunkLength + uint32 chunkType
CHUNK_TYPE_JSON = b"JSON"
CHUNK_TYPE_BIN = b"BIN\x00"

# A GLB JSON chunk holding many megabytes of JSON is implausible for a mod asset
# and is refused outright rather than parsed.
MAX_JSON_CHUNK_BYTES = 32 * 1024 * 1024


# --- Byte windows: the shared abstraction that makes GLB recursion real ----------
#
# Every full-file validator below (`validate_png_fully`, `validate_ogg_fully`,
# `validate_text_fully`, `validate_glb_fully`) operates on a "window" rather than
# directly on a file: a bounded, seekable [start, start+length) view that answers
# `read_at(rel_offset, n)` and knows its own `length`. A top-level file is one
# window over the whole file. An embedded GLB payload (a bufferView's slice of the
# BIN chunk, or a base64-decoded data: URI) is *also* just a window -- over the
# same open file at a different offset, or over an in-memory buffer. Because every
# validator only ever talks to this interface, an embedded payload that is itself a
# GLB is validated by literally the same recursive call as a top-level GLB file
# (round-2 criterion 11) -- there is no separate, weaker "embedded payload" code
# path to accidentally under-validate.


class Window(Protocol):
    start: int
    length: int

    def read_at(self, rel_offset: int, n: int) -> bytes: ...
    def sub_window(self, rel_offset: int, length: int) -> "Window": ...


class ByteWindow:
    """A bounded view into part of an open file on disk: file bytes
    [start, start + length). `start` is an absolute file offset, so offsets
    reported by validators using this window are real, seekable file positions."""

    def __init__(self, fh, start: int, length: int):
        self.fh = fh
        self.start = start
        self.length = length

    def read_at(self, rel_offset: int, n: int) -> bytes:
        if rel_offset < 0 or n < 0:
            raise ValueError("negative offset/length")
        avail = self.length - rel_offset
        if avail <= 0:
            return b""
        to_read = min(n, avail)
        self.fh.seek(self.start + rel_offset)
        return self.fh.read(to_read)

    def sub_window(self, rel_offset: int, length: int) -> "ByteWindow":
        return ByteWindow(self.fh, self.start + rel_offset, length)


class MemoryByteWindow:
    """Same interface as ByteWindow, backed by an in-memory buffer. Used only for
    base64-decoded `data:` URI payloads, which have no addressable position in the
    original file -- there is nothing to seek to, only decoded bytes to hold.
    `start` is always 0 here: offsets reported from within a MemoryByteWindow are
    positions within the decoded payload, not file positions, and are reported as
    such (see `_walk_embedded_images`)."""

    def __init__(self, data: bytes):
        self.data = data
        self.start = 0
        self.length = len(data)

    def read_at(self, rel_offset: int, n: int) -> bytes:
        if rel_offset < 0 or n < 0:
            raise ValueError("negative offset/length")
        return self.data[rel_offset: rel_offset + n]

    def sub_window(self, rel_offset: int, length: int) -> "MemoryByteWindow":
        return MemoryByteWindow(self.data[rel_offset: rel_offset + length])


# --- Report data model -------------------------------------------------------


@dataclass
class Rejection:
    path: str
    detected_format: str
    signature_offset: Optional[int]
    reason: str
    # Round-3 criterion 17 / ADR-0120 clause 3: a rejection an author cannot act on
    # is a defect, not a security measure. Every rejection carries the concrete next
    # step, as a separate report field so callers can surface it in a PR comment
    # without re-parsing prose. Never empty -- asserted by the CLI and by tests.
    remedy: str


@dataclass
class Accepted:
    path: str
    format: str


@dataclass
class ScanError:
    path: str
    reason: str


@dataclass
class Counters:
    files_inspected: int = 0
    files_accepted: int = 0
    files_rejected: int = 0
    files_skipped: int = 0
    skipped_reasons: dict = field(default_factory=dict)

    def skip(self, reason: str) -> None:
        self.files_skipped += 1
        self.skipped_reasons[reason] = self.skipped_reasons.get(reason, 0) + 1


@dataclass
class ClassifyResult:
    accepted: bool
    format_id: str
    offset: Optional[int]
    reason: str
    remedy: str = ""


# --- PNG: content whitelist + full chunk-stream validation, to EOF ----------------
#
# ADR-0120: the guarantee is *content whitelisting*, not container framing. Round 2
# validated PNG framing to EOF; review then smuggled a complete DBC through a valid
# private ancillary chunk (`zBLZ`) inside an otherwise perfect PNG. Framing was
# never the question -- "what may this file contain?" is. So:
#
#   * only the chunk types named below may appear at all (unknown, private and
#     unlisted chunks are rejected, including ones harmless in other contexts);
#   * every permitted chunk's length is constrained by the spec or by IHDR, so a
#     whitelisted *type* cannot be reused as an arbitrary-length container; and
#   * the IDAT zlib stream is decompressed and its inflated size checked against the
#     exact byte count IHDR implies, so the one genuinely variable-length chunk
#     cannot carry a payload either.
#
# Chunk layout is per the W3C PNG specification, section "Chunk layout"
# (https://www.w3.org/TR/png/#5Chunk-layout, verified 2026-09-02): 4-byte big-endian
# length, 4-byte type, `length` data bytes, 4-byte CRC.
#
# CRCs are deliberately NOT verified. ADR-0120 states why: an attacker computes the
# correct CRC over their own payload, so a CRC detects corruption, never smuggling.

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_CHUNK_HEADER_SIZE = 8  # 4-byte length + 4-byte type
PNG_CRC_SIZE = 4

# Structural chunks: the image itself. These are what a PNG *is*.
PNG_CORE_CHUNKS = (b"IHDR", b"PLTE", b"IDAT", b"IEND")

# The safe list (ADR-0120 clause 1: "a short named safe list ... every entry carries
# a written reason"). The reasons below are reproduced verbatim in
# docs/validation/asset-scanner.md so a reader can evaluate each one. The shared test
# `test_safe_list_reasons_are_documented` fails if the two drift apart.
#
# The admission rule every entry satisfies, both halves required:
#
#   (a) the PNG specification fixes the chunk's length at a handful of bytes, *and*
#       this scanner enforces that exact length -- so a whitelisted type cannot be
#       reused as a general-purpose container; and
#   (b) either the chunk changes how the image renders, or refusing it would reject
#       the unconditional default output of ordinary image editors.
#
# Half (b)'s second branch is why pHYs is here and, say, tIME is not. It is a
# measured claim, not a guess: see docs/validation/asset-scanner.md for the survey
# of 91 real-world PNGs this scanner was checked against, chunk type by chunk type.
# "Harmless" on its own is never sufficient -- ADR-0120 rejects ancillary chunks that
# are harmless in other contexts.
PNG_SAFE_LIST_REASONS = {
    b"tRNS": (
        "Transparency. For an indexed-colour image this is the only place alpha "
        "exists at all, and for greyscale/truecolour it carries the single "
        "colour-key value; dropping it visibly changes the image, and no re-export "
        "preserves the art without it. The spec fixes its length exactly from IHDR's "
        "colour type (2 bytes greyscale, 6 bytes truecolour, at most one byte per "
        "palette entry for indexed), and this scanner enforces that length, so the "
        "chunk cannot be reused as a general-purpose container."
    ),
    b"gAMA": (
        "Image gamma: one 4-byte unsigned integer, length fixed by the spec and "
        "enforced here. Four bytes cannot carry smuggled content, and without it an "
        "image authored on a non-2.2 pipeline renders at the wrong brightness in the "
        "client."
    ),
    b"sRGB": (
        "sRGB rendering intent: one enumerated byte (0-3), length fixed by the spec "
        "and enforced here, value range enforced here. One byte cannot carry "
        "smuggled content. It is on the list because it is the small, fixed-length "
        "alternative to iCCP -- authors who need to declare colour intent can do so "
        "without an embedded profile."
    ),
    b"pHYs": (
        "Physical pixel dimensions: two 4-byte unsigned integers and a one-byte unit "
        "specifier, 9 bytes, length fixed by the spec and enforced here, unit value "
        "range enforced here. This one is admitted under half (b)'s second branch: it "
        "does not affect how the client renders a texture, but essentially every "
        "image editor writes it unconditionally (9% of a 91-file real-world corpus, "
        "66% of the World of Warcraft add-on PNGs surveyed), and a rule that rejects "
        "an editor's default export teaches authors to reach for byte-stripping tools "
        "rather than to comply. The price is 9 spec-fixed bytes per file."
    ),
}
PNG_PERMITTED_CHUNKS = set(PNG_CORE_CHUNKS) | set(PNG_SAFE_LIST_REASONS)

# Chunks that may appear at most once (PNG spec, "Chunk ordering rules"). IDAT is the
# only chunk this scanner allows to repeat, and only in one consecutive run.
PNG_SINGLE_OCCURRENCE = PNG_PERMITTED_CHUNKS - {b"IDAT"}

# Channels per colour type (PNG spec, Table "Colour types and values") and the bit
# depths each colour type permits.
PNG_COLOUR_TYPES = {
    0: (1, (1, 2, 4, 8, 16)),   # greyscale
    2: (3, (8, 16)),            # truecolour
    3: (1, (1, 2, 4, 8)),       # indexed-colour
    4: (2, (8, 16)),            # greyscale + alpha
    6: (4, (8, 16)),            # truecolour + alpha
}

# Ceiling on the *decompressed* size of a PNG's pixel data. IHDR's width and height
# are 32-bit, so a small file can declare an enormous raster; we refuse rather than
# inflate towards it. 512 MiB is far above any realistic WotLK-era texture (a 4096 x
# 4096 RGBA image is 64 MiB of raw scanlines) and bounds the decompression work.
MAX_PNG_RAW_BYTES = 512 * 1024 * 1024

# Adam7 interlacing pass origins and strides (PNG spec, "Interlaced data order").
PNG_ADAM7 = ((0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
             (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2))

PNG_REMEDY_STRIP = (
    "Re-export the image as a plain PNG without private chunks, embedded metadata "
    "or colour profiles -- in most editors that is 'export as PNG' with metadata "
    "disabled; from the command line, `pngcrush -rem alla -rem text in.png out.png` "
    "removes every ancillary chunk this scanner does not permit. Permitted chunks "
    "are " + ", ".join(sorted(c.decode("ascii") for c in PNG_PERMITTED_CHUNKS)) + "."
)


def _png_chunk_class(ctype: bytes) -> str:
    """Describe a chunk type using PNG's own property bits (spec, "Chunk naming
    conventions"): bit 5 of each byte. Byte 0 lowercase = ancillary, byte 1
    lowercase = private (unregistered). Used only to make rejection messages tell
    the author what kind of thing they are being asked to remove."""
    if len(ctype) != 4:
        return "malformed chunk type"
    ancillary = bool(ctype[0] & 0x20)
    private = bool(ctype[1] & 0x20)
    return "{}, {}".format(
        "ancillary" if ancillary else "critical",
        "private/unregistered" if private else "public-namespace",
    )


def _png_raw_scanline_bytes(width: int, height: int, bits_per_pixel: int, interlace: int) -> int:
    """Exact number of bytes the IDAT zlib stream must inflate to: for each pass,
    one filter byte per scanline plus ceil(pixels * bpp / 8) bytes of pixel data
    (PNG spec, "Filtering" and "Interlaced data order")."""
    if interlace == 0:
        return height * (1 + (width * bits_per_pixel + 7) // 8)
    total = 0
    for x0, y0, xstep, ystep in PNG_ADAM7:
        pw = (width - x0 + xstep - 1) // xstep if width > x0 else 0
        ph = (height - y0 + ystep - 1) // ystep if height > y0 else 0
        if pw > 0 and ph > 0:
            total += ph * (1 + (pw * bits_per_pixel + 7) // 8)
    return total


def validate_png_fully(window: Window) -> tuple[bool, str, Optional[int], str]:
    """Validate one PNG completely: chunk-type whitelist (ADR-0120), per-chunk length
    constraints, chunk ordering, framing to EOF with nothing left over, and the
    inflated size of the IDAT stream against what IHDR implies.

    Returns (ok, reason, offset, remedy). `offset` is an absolute file offset and
    `remedy` is what the author should do; both are meaningful only when ok is False.

    Chunk *data* bytes are read only for IHDR (13 bytes), for the safe-list chunks
    (at most 256 bytes each) and for IDAT (streamed in bounded blocks and discarded
    after decompression); everything else is skipped by bounds-checked arithmetic, so
    memory stays bounded regardless of image size.
    """
    length = window.length
    sig = window.read_at(0, len(PNG_SIGNATURE))
    if sig != PNG_SIGNATURE:
        return False, "PNG signature mismatch on full validation", window.start, \
            "Supply a real PNG file; this one does not start with the PNG signature."

    offset = len(PNG_SIGNATURE)
    chunk_index = 0
    seen: dict[bytes, int] = {}
    idat_regions: list[tuple[int, int]] = []   # (absolute-in-window data offset, length)
    idat_run_closed = False
    ihdr: Optional[dict] = None

    while offset < length:
        if chunk_index >= MAX_CHUNK_COUNT:
            return False, f"more than {MAX_CHUNK_COUNT} PNG chunks (possible pathological input); refused", \
                window.start + offset, "Re-export the image; a normal PNG has a handful of chunks, not thousands."
        if offset + PNG_CHUNK_HEADER_SIZE > length:
            return False, (
                f"PNG chunk {chunk_index} header truncated at offset {window.start + offset} "
                f"({length - offset} byte(s) remain, need {PNG_CHUNK_HEADER_SIZE})"
            ), window.start + offset, "The file is truncated -- re-upload the complete PNG."
        hdr = window.read_at(offset, PNG_CHUNK_HEADER_SIZE)
        data_len, ctype = struct.unpack(">I4s", hdr)  # PNG: big-endian length field
        data_start = offset + PNG_CHUNK_HEADER_SIZE
        end = data_start + data_len + PNG_CRC_SIZE  # exact Python int arithmetic, never wraps

        if end > length:
            return False, (
                f"PNG chunk {chunk_index} ({ctype!r}) declares {data_len} data byte(s) at offset "
                f"{window.start + data_start}, which with its CRC would end at byte "
                f"{window.start + end} -- past the end of the file/region "
                f"({window.start + length} byte(s) total)"
            ), window.start + offset, "The file is truncated or corrupt -- re-export and re-upload it."

        # --- the content whitelist (ADR-0120 clause 1) ---------------------------
        if ctype not in PNG_PERMITTED_CHUNKS:
            printable = ctype.decode("ascii", "replace")
            return False, (
                f"PNG contains chunk '{printable}' ({_png_chunk_class(ctype)}) at offset "
                f"{window.start + offset}, carrying {data_len} byte(s) of data. That chunk type is "
                f"not on the permitted content list, so its bytes are never inspected by anything "
                f"and could carry any payload at all (ADR-0120: an accepted asset contains only "
                f"content of types the platform has explicitly permitted)."
            ), window.start + offset, PNG_REMEDY_STRIP

        if ctype in PNG_SINGLE_OCCURRENCE and ctype in seen:
            printable = ctype.decode("ascii", "replace")
            return False, (
                f"PNG contains a second '{printable}' chunk at offset {window.start + offset}; the "
                f"PNG specification permits only one, and a duplicate is a place to hide bytes."
            ), window.start + offset, PNG_REMEDY_STRIP
        seen[ctype] = seen.get(ctype, 0) + 1

        if chunk_index == 0 and ctype != b"IHDR":
            return False, f"first PNG chunk must be IHDR, found {ctype!r} at offset {window.start + offset}", \
                window.start + offset, "Re-export the image; its header chunk is missing or displaced."

        # --- per-chunk-type content rules ---------------------------------------
        if ctype == b"IHDR":
            if data_len != 13:
                return False, (
                    f"IHDR chunk must be exactly 13 bytes of data per the PNG spec, "
                    f"found {data_len} at offset {window.start + offset}"
                ), window.start + offset, "Re-export the image; its header chunk is malformed."
            w, h, depth, colour, comp, filt, interlace = struct.unpack(">IIBBBBB", window.read_at(data_start, 13))
            if w == 0 or h == 0:
                return False, f"IHDR declares a {w}x{h} image; both dimensions must be non-zero", \
                    window.start + offset, "Re-export a non-empty image."
            if colour not in PNG_COLOUR_TYPES:
                return False, f"IHDR declares colour type {colour}, which is not one of the PNG spec's 0/2/3/4/6", \
                    window.start + offset, "Re-export the image from an editor that writes standard PNG colour types."
            channels, allowed_depths = PNG_COLOUR_TYPES[colour]
            if depth not in allowed_depths:
                return False, (
                    f"IHDR declares bit depth {depth} for colour type {colour}; the PNG spec allows "
                    f"only {allowed_depths} for that colour type"
                ), window.start + offset, "Re-export the image at a standard bit depth (8 or 16 bits per channel)."
            if comp != 0 or filt != 0:
                return False, (
                    f"IHDR declares compression method {comp} and filter method {filt}; the PNG spec "
                    f"defines only 0 for both"
                ), window.start + offset, "Re-export the image; only standard PNG compression is accepted."
            if interlace not in (0, 1):
                return False, f"IHDR declares interlace method {interlace}; the PNG spec defines only 0 and 1", \
                    window.start + offset, "Re-export the image without interlacing."
            bits_per_pixel = depth * channels
            raw_bytes = _png_raw_scanline_bytes(w, h, bits_per_pixel, interlace)
            if raw_bytes > MAX_PNG_RAW_BYTES:
                return False, (
                    f"IHDR declares a {w}x{h} image whose uncompressed pixel data would be {raw_bytes} "
                    f"byte(s), over the {MAX_PNG_RAW_BYTES} byte ceiling; refused rather than decompressed"
                ), window.start + offset, "Use a smaller image; textures this large are not accepted."
            ihdr = {"w": w, "h": h, "depth": depth, "colour": colour, "raw_bytes": raw_bytes}

        elif ctype == b"PLTE":
            if data_len == 0 or data_len % 3 != 0 or data_len > 768:
                return False, (
                    f"PLTE chunk at offset {window.start + offset} is {data_len} byte(s); a palette "
                    f"must be a non-empty multiple of 3 and at most 768 bytes (256 RGB entries)"
                ), window.start + offset, "Re-export the image; its palette chunk is malformed."
            if ihdr and ihdr["colour"] in (0, 4):
                return False, (
                    f"PLTE chunk present at offset {window.start + offset} but IHDR declares colour "
                    f"type {ihdr['colour']} (greyscale), which the PNG spec forbids a palette for"
                ), window.start + offset, PNG_REMEDY_STRIP
            if b"IDAT" in seen:
                return False, f"PLTE chunk at offset {window.start + offset} appears after the pixel data; the PNG spec requires it before IDAT", \
                    window.start + offset, PNG_REMEDY_STRIP
            ihdr and ihdr.update({"palette_entries": data_len // 3})

        elif ctype == b"tRNS":
            if ihdr is None:
                return False, "tRNS chunk before IHDR", window.start + offset, PNG_REMEDY_STRIP
            colour = ihdr["colour"]
            if colour in (4, 6):
                return False, (
                    f"tRNS chunk present at offset {window.start + offset} but IHDR declares colour "
                    f"type {colour}, which already carries a full alpha channel; the PNG spec forbids "
                    f"tRNS there, so this chunk's bytes have no defined meaning"
                ), window.start + offset, PNG_REMEDY_STRIP
            expected = {0: 2, 2: 6}.get(colour)
            if expected is not None and data_len != expected:
                return False, (
                    f"tRNS chunk at offset {window.start + offset} is {data_len} byte(s); for colour "
                    f"type {colour} the PNG spec fixes it at exactly {expected}"
                ), window.start + offset, PNG_REMEDY_STRIP
            if colour == 3:
                limit = ihdr.get("palette_entries", 256)
                if data_len == 0 or data_len > limit:
                    return False, (
                        f"tRNS chunk at offset {window.start + offset} carries {data_len} alpha "
                        f"value(s) for a palette of {limit} entry/entries; the PNG spec allows at "
                        f"most one per palette entry"
                    ), window.start + offset, PNG_REMEDY_STRIP
            if b"IDAT" in seen:
                return False, f"tRNS chunk at offset {window.start + offset} appears after the pixel data; the PNG spec requires it before IDAT", \
                    window.start + offset, PNG_REMEDY_STRIP

        elif ctype == b"pHYs":
            if data_len != 9:
                return False, (
                    f"pHYs chunk at offset {window.start + offset} is {data_len} byte(s); the PNG spec "
                    f"fixes it at exactly 9, and it is on the permitted list only because of that fixed size"
                ), window.start + offset, PNG_REMEDY_STRIP
            unit = window.read_at(data_start, 9)[8]
            if unit > 1:
                return False, (
                    f"pHYs chunk at offset {window.start + offset} declares unit specifier {unit}; "
                    f"the PNG spec defines only 0 (unknown) and 1 (metre)"
                ), window.start + offset, PNG_REMEDY_STRIP

        elif ctype == b"gAMA":
            if data_len != 4:
                return False, (
                    f"gAMA chunk at offset {window.start + offset} is {data_len} byte(s); the PNG spec "
                    f"fixes it at exactly 4, and it is on the permitted list only because of that fixed size"
                ), window.start + offset, PNG_REMEDY_STRIP

        elif ctype == b"sRGB":
            if data_len != 1:
                return False, (
                    f"sRGB chunk at offset {window.start + offset} is {data_len} byte(s); the PNG spec "
                    f"fixes it at exactly 1, and it is on the permitted list only because of that fixed size"
                ), window.start + offset, PNG_REMEDY_STRIP
            intent = window.read_at(data_start, 1)[0]
            if intent > 3:
                return False, (
                    f"sRGB chunk at offset {window.start + offset} declares rendering intent {intent}; "
                    f"the PNG spec defines only 0-3"
                ), window.start + offset, PNG_REMEDY_STRIP

        elif ctype == b"IDAT":
            if ihdr is None:
                return False, "IDAT chunk before IHDR", window.start + offset, "Re-export the image."
            if idat_run_closed:
                return False, (
                    f"IDAT chunk at offset {window.start + offset} follows a non-IDAT chunk; the PNG "
                    f"spec requires all IDAT chunks to be consecutive, and a split run is a place to "
                    f"hide bytes between them"
                ), window.start + offset, PNG_REMEDY_STRIP
            idat_regions.append((data_start, data_len))

        elif ctype == b"IEND":
            if data_len != 0:
                return False, (
                    f"IEND chunk at offset {window.start + offset} declares {data_len} byte(s) of data; "
                    f"the PNG spec fixes IEND at exactly 0 bytes, so those bytes are pure payload"
                ), window.start + offset, PNG_REMEDY_STRIP
            if b"IDAT" not in seen:
                return False, "PNG contains no IDAT chunk: there is no image data in this file", \
                    window.start + offset, "Re-export the image; this file carries no pixels."
            if ihdr is not None and ihdr["colour"] == 3 and b"PLTE" not in seen:
                return False, "PNG declares indexed colour (type 3) but carries no PLTE palette chunk", \
                    window.start + offset, "Re-export the image; its palette is missing."
            offset = end
            if offset != length:
                trailing = length - offset
                return False, (
                    f"{trailing} byte(s) of trailing data after the PNG stream's IEND chunk "
                    f"(offset {window.start + offset}) -- a well-formed PNG must end exactly at IEND"
                ), window.start + offset, "Remove everything appended after the image; re-export it."
            ok, reason, off, remedy = _png_check_idat_stream(window, idat_regions, ihdr)
            if not ok:
                return False, reason, off, remedy
            return True, (
                f"well-formed PNG: {chunk_index + 1} chunk(s), every type on the permitted content "
                f"list, IDAT inflating to exactly the {ihdr['raw_bytes']} byte(s) IHDR implies, "
                f"stream ending at IEND with no trailing data"
            ), None, ""

        if ctype != b"IDAT" and idat_regions:
            idat_run_closed = True

        offset = end
        chunk_index += 1

    return False, f"PNG stream ends at offset {window.start + offset} without an IEND chunk (truncated)", \
        window.start + offset, "The file is truncated -- re-upload the complete PNG."


def _png_check_idat_stream(window: Window, regions: list[tuple[int, int]], ihdr: dict) -> tuple[bool, str, Optional[int], str]:
    """Decompress the concatenated IDAT chunk data and require it to inflate to
    exactly the byte count IHDR implies, ending exactly where the last IDAT chunk
    ends.

    This is what stops IDAT -- the one permitted chunk whose length the spec does not
    fix -- from being the smuggling channel the private-chunk route was. Without it,
    a valid PNG can carry an arbitrary payload as deflate-stored bytes after the real
    scanlines and every framing check still passes. Output is counted and discarded,
    never accumulated, and inflation aborts the moment it exceeds what IHDR implies,
    which also bounds a decompression bomb.
    """
    expected = ihdr["raw_bytes"]
    dec = zlib.decompressobj()
    produced = 0
    surplus = 0
    first_offset = window.start + regions[0][0] if regions else window.start
    for data_start, data_len in regions:
        pos = 0
        while pos < data_len:
            block = window.read_at(data_start + pos, min(TEXT_BLOCK_SIZE, data_len - pos))
            if not block:
                return False, "the PNG's IDAT chunk data ended unexpectedly while being read", \
                    first_offset, "The file is truncated -- re-upload the complete PNG."
            pos += len(block)
            if dec.eof:
                # The zlib stream already ended; anything still inside the IDAT
                # chunks is bytes no decoder reads. Counted, not decompressed.
                surplus += len(block)
                continue
            feed = block
            while feed:
                try:
                    # max_length bounds *output* per call, so peak memory is one
                    # block in and one block out regardless of the image's size or
                    # of how compressible the payload is (this is also the
                    # decompression-bomb guard: a bomb trips the ceiling below long
                    # before it can be materialised).
                    out = dec.decompress(feed, max_length=TEXT_BLOCK_SIZE)
                except zlib.error as exc:
                    return False, f"the PNG's IDAT pixel data is not a valid zlib stream ({exc})", \
                        first_offset, "Re-export the image; its compressed pixel data is corrupt."
                produced += len(out)
                if produced > expected:
                    return False, (
                        f"the PNG's IDAT pixel data inflates to more than the {expected} byte(s) its "
                        f"{ihdr['w']}x{ihdr['h']} IHDR declares; the surplus is data an image viewer "
                        f"never reads and this platform does not accept"
                    ), first_offset, PNG_REMEDY_STRIP
                feed = dec.unconsumed_tail
    try:
        produced += len(dec.flush())
    except zlib.error as exc:
        return False, f"the PNG's IDAT pixel data is not a valid zlib stream ({exc})", \
            first_offset, "Re-export the image; its compressed pixel data is corrupt."
    if not dec.eof:
        return False, (
            "the PNG's IDAT zlib stream is truncated: it does not reach its own end marker within "
            "the IDAT chunks"
        ), first_offset, "The file is truncated or corrupt -- re-export and re-upload it."
    surplus += len(dec.unused_data)
    if surplus:
        return False, (
            f"{surplus} byte(s) follow the end of the PNG's IDAT zlib stream but are still inside "
            f"the IDAT chunk data; an image viewer never reads them, so they are pure payload"
        ), first_offset, PNG_REMEDY_STRIP
    if produced != expected:
        return False, (
            f"the PNG's IDAT pixel data inflates to {produced} byte(s) but its {ihdr['w']}x{ihdr['h']} "
            f"IHDR implies exactly {expected}"
        ), first_offset, "Re-export the image; its declared size and its pixel data disagree."
    return True, "", None, ""


# --- OGG: codec-header whitelist + full page-stream validation, to EOF ------------
#
# ADR-0120 clause 2: "the payload must parse as Vorbis or Opus headers. A page whose
# payload is not a recognised codec stream is rejected." Round 2 validated Ogg page
# framing; review then smuggled a complete DBC through as a page's lacing-declared
# payload, which is perfectly legal Ogg. So the page walk below is kept exactly as it
# was (it is what bounds the file and catches trailing data), and on top of it every
# logical bitstream must now identify itself as Vorbis or Opus in its first packet and
# produce structurally valid header packets.
#
# Page layout is per RFC 3533 section 6 (verified 2026-09-02): a 27-byte fixed header
# (capture pattern "OggS", version, header type, granule position, serial number, page
# sequence number, CRC, segment count), a segment table of that many lacing values,
# then a payload whose length is their sum. Packets are delimited by lacing values
# below 255 and may span pages. Codec headers are per the Vorbis I specification
# section 4.2 and RFC 7845 sections 5.1-5.2.

OGG_FIXED_HEADER_SIZE = 27
OGG_FLAG_CONTINUED = 0x01
OGG_FLAG_BOS = 0x02
OGG_FLAG_EOS = 0x04

# Ceilings for the header phase only; audio pages are never read.
MAX_OGG_LOGICAL_STREAMS = 16
MAX_OGG_HEADER_PACKET_BYTES = 256 * 1024
MAX_OGG_COMMENT_COUNT = 1024
# Opus permits zero-padding after the tag list (RFC 7845 section 5.2). Real encoders
# use it to reserve room for later tag edits, so refusing it outright would reject
# ordinary opusenc output; allowing it only when every padding byte is zero keeps the
# convenience without leaving a place to put content.
MAX_OGG_TAG_PADDING_BYTES = 4096

VORBIS_MARKER = b"vorbis"
OGG_REMEDY_REENCODE = (
    "Re-encode the audio to Ogg Vorbis or Ogg Opus with a standard encoder "
    "(`oggenc in.wav -o out.ogg`, or `opusenc in.wav out.opus`) and upload that file. "
    "Ogg is accepted as a carrier for those two codecs only -- an Ogg page whose "
    "payload is anything else is not audio this platform can play."
)


class _OggStream:
    """Header-phase state for one logical bitstream (one serial number)."""

    def __init__(self, serial: int, first_page_offset: int):
        self.serial = serial
        self.first_page_offset = first_page_offset
        self.codec: Optional[str] = None
        self.headers_done = False
        self.headers_seen = 0
        self.pending = bytearray()
        self.pending_bytes = 0


def _ogg_text_ok(raw: bytes) -> bool:
    """A Vorbis comment / Opus tag string must be UTF-8 text, not a byte container:
    same rule the TEXT bucket applies (printable UTF-8 plus tab/newline/carriage
    return). A Blizzard file's bytes fail this immediately."""
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return all(ch in "\t\n\r" or ord(ch) >= 0x20 for ch in text)


def _ogg_parse_comment_block(packet: bytes, pos: int, codec: str, allow_zero_padding: bool) -> tuple[bool, str]:
    """Parse a Vorbis/Opus comment block: vendor string, comment count, then that many
    length-prefixed UTF-8 comments. Returns (ok, reason)."""
    total = len(packet)
    if pos + 4 > total:
        return False, f"{codec} comment header is truncated before its vendor-string length"
    (vlen,) = struct.unpack_from("<I", packet, pos)
    pos += 4
    if pos + vlen > total:
        return False, f"{codec} comment header declares a {vlen}-byte vendor string that runs past the packet"
    if not _ogg_text_ok(packet[pos:pos + vlen]):
        return False, f"{codec} comment header's vendor string is not printable UTF-8 text"
    pos += vlen
    if pos + 4 > total:
        return False, f"{codec} comment header is truncated before its comment count"
    (count,) = struct.unpack_from("<I", packet, pos)
    pos += 4
    if count > MAX_OGG_COMMENT_COUNT:
        return False, f"{codec} comment header declares {count} tags, over the {MAX_OGG_COMMENT_COUNT} limit"
    for i in range(count):
        if pos + 4 > total:
            return False, f"{codec} comment header is truncated before tag {i}'s length"
        (clen,) = struct.unpack_from("<I", packet, pos)
        pos += 4
        if pos + clen > total:
            return False, f"{codec} comment header declares a {clen}-byte tag {i} that runs past the packet"
        if not _ogg_text_ok(packet[pos:pos + clen]):
            return False, (
                f"{codec} comment header's tag {i} is not printable UTF-8 text; tags are metadata "
                f"text, not a place for binary content"
            )
        pos += clen
    if codec == "Vorbis":
        # Vorbis I section 4.2.3: the comment header ends with a framing bit.
        if pos >= total:
            return False, "Vorbis comment header is missing its framing bit"
        if not packet[pos] & 0x01:
            return False, "Vorbis comment header's framing bit is not set"
        pos += 1
    if pos != total:
        trailing = total - pos
        if allow_zero_padding and trailing <= MAX_OGG_TAG_PADDING_BYTES and not any(packet[pos:]):
            return True, ""
        return False, (
            f"{trailing} byte(s) follow the end of the {codec} comment list inside the same header "
            f"packet; no decoder reads them, so they are pure payload"
        )
    return True, ""


def _ogg_identify(packet: bytes) -> tuple[Optional[str], str]:
    """Classify a logical stream's first packet. Returns (codec or None, reason)."""
    if packet[:7] == b"\x01" + VORBIS_MARKER:
        if len(packet) != 30:
            return None, f"Vorbis identification header is {len(packet)} bytes; the Vorbis I specification fixes it at 30"
        version, channels, rate = struct.unpack_from("<IBI", packet, 7)
        if version != 0:
            return None, f"Vorbis identification header declares stream version {version}; only 0 is defined"
        if channels == 0:
            return None, "Vorbis identification header declares 0 audio channels"
        if rate == 0:
            return None, "Vorbis identification header declares a sample rate of 0"
        blocksizes = packet[28]
        bs0, bs1 = blocksizes & 0x0F, blocksizes >> 4
        if not (6 <= bs0 <= 13 and 6 <= bs1 <= 13 and bs0 <= bs1):
            return None, f"Vorbis identification header declares out-of-range block sizes (2^{bs0}, 2^{bs1})"
        if not packet[29] & 0x01:
            return None, "Vorbis identification header's framing bit is not set"
        return "Vorbis", ""
    if packet[:8] == b"OpusHead":
        if len(packet) < 19:
            return None, f"Opus identification header is {len(packet)} bytes; RFC 7845 requires at least 19"
        version = packet[8]
        if version >> 4 != 0:
            return None, f"Opus identification header declares major version {version >> 4}; RFC 7845 defines 0"
        channels = packet[9]
        if channels == 0:
            return None, "Opus identification header declares 0 audio channels"
        family = packet[18]
        if family == 0:
            if channels > 2:
                return None, f"Opus channel mapping family 0 allows 1-2 channels, header declares {channels}"
            if len(packet) != 19:
                return None, (
                    f"Opus identification header is {len(packet)} bytes; for channel mapping family 0 "
                    f"RFC 7845 fixes it at 19, so the surplus is unread payload"
                )
        else:
            if len(packet) != 21 + channels:
                return None, (
                    f"Opus identification header is {len(packet)} bytes; for channel mapping family "
                    f"{family} with {channels} channels RFC 7845 fixes it at {21 + channels}"
                )
        return "Opus", ""
    preview = bytes(packet[:8])
    return None, (
        f"the first packet of this Ogg logical bitstream begins {preview!r}, which is neither a "
        f"Vorbis identification header ('\\x01vorbis') nor an Opus one ('OpusHead'); its payload is "
        f"therefore not audio of a codec this platform permits (ADR-0120)"
    )


def _ogg_consume_header_packet(stream: _OggStream, packet: bytes) -> tuple[bool, str]:
    """Feed one complete packet to a stream still in its header phase."""
    if stream.codec is None:
        codec, reason = _ogg_identify(packet)
        if codec is None:
            return False, reason
        stream.codec = codec
        stream.headers_seen = 1
        if codec == "Opus":
            return True, ""
        return True, ""
    if stream.codec == "Vorbis":
        if stream.headers_seen == 1:
            if packet[:7] != b"\x03" + VORBIS_MARKER:
                return False, (
                    f"the second Vorbis header packet begins {bytes(packet[:7])!r}; the Vorbis I "
                    f"specification requires the comment header ('\\x03vorbis')"
                )
            ok, reason = _ogg_parse_comment_block(packet, 7, "Vorbis", allow_zero_padding=False)
            if not ok:
                return False, reason
            stream.headers_seen = 2
            return True, ""
        if packet[:7] != b"\x05" + VORBIS_MARKER:
            return False, (
                f"the third Vorbis header packet begins {bytes(packet[:7])!r}; the Vorbis I "
                f"specification requires the setup header ('\\x05vorbis')"
            )
        stream.headers_seen = 3
        stream.headers_done = True
        return True, ""
    # Opus
    if packet[:8] != b"OpusTags":
        return False, (
            f"the second Opus header packet begins {bytes(packet[:8])!r}; RFC 7845 requires the "
            f"comment header ('OpusTags')"
        )
    ok, reason = _ogg_parse_comment_block(packet, 8, "Opus", allow_zero_padding=True)
    if not ok:
        return False, reason
    stream.headers_seen = 2
    stream.headers_done = True
    return True, ""


def validate_ogg_fully(window: Window) -> tuple[bool, str, Optional[int], str]:
    """Walk the entire Ogg page stream and require (a) that it consumes exactly
    `window.length` bytes ending on a page boundary, and (b) that every logical
    bitstream in it identifies as Vorbis or Opus and produces structurally valid
    codec header packets (ADR-0120 clause 2).

    Page payload bytes are read only while a stream is still in its header phase
    (bounded by MAX_OGG_HEADER_PACKET_BYTES); audio pages are skipped by arithmetic,
    so memory and I/O stay bounded regardless of track length.

    Deliberately not verified -- see docs/validation/asset-scanner.md, "What is read
    and what is not": each page's CRC (ADR-0120: a CRC detects corruption, not
    smuggling), the Vorbis setup header's codebook bytes, and every audio packet.
    """
    length = window.length
    if length < OGG_FIXED_HEADER_SIZE:
        return False, (
            f"file/region is only {length} byte(s), shorter than a minimal Ogg page "
            f"header ({OGG_FIXED_HEADER_SIZE} bytes, RFC 3533 section 6)"
        ), window.start, "The file is truncated -- re-upload the complete audio file."
    offset = 0
    page_index = 0
    streams: dict[int, _OggStream] = {}
    order: list[_OggStream] = []
    while offset < length:
        if page_index >= MAX_CHUNK_COUNT:
            return False, f"more than {MAX_CHUNK_COUNT} Ogg pages (possible pathological input); refused", \
                window.start + offset, "Upload a shorter audio file."
        if offset + OGG_FIXED_HEADER_SIZE > length:
            return False, f"Ogg page {page_index} header truncated at offset {window.start + offset}", \
                window.start + offset, "The file is truncated -- re-upload the complete audio file."
        hdr = window.read_at(offset, OGG_FIXED_HEADER_SIZE)
        capture = hdr[0:4]
        if capture != b"OggS":
            return False, (
                f"expected the 'OggS' capture pattern at offset {window.start + offset} "
                f"(start of page {page_index}), found {capture!r} instead"
            ), window.start + offset, "Remove anything appended after the audio stream and re-upload it."
        version = hdr[4]
        if version != 0:
            return False, f"Ogg stream structure version {version} at offset {window.start + offset} -- only version 0 is defined (RFC 3533)", \
                window.start + offset, OGG_REMEDY_REENCODE
        header_type = hdr[5]
        (serial,) = struct.unpack_from("<I", hdr, 14)
        num_segments = hdr[26]
        seg_table_offset = offset + OGG_FIXED_HEADER_SIZE
        seg_table_end = seg_table_offset + num_segments
        if seg_table_end > length:
            return False, f"Ogg page {page_index} segment table truncated at offset {window.start + seg_table_offset}", \
                window.start + seg_table_offset, "The file is truncated -- re-upload the complete audio file."
        seg_table = window.read_at(seg_table_offset, num_segments)
        payload_len = sum(seg_table)
        payload_end = seg_table_end + payload_len
        if payload_end > length:
            return False, (
                f"Ogg page {page_index} declares a payload of {payload_len} byte(s) starting at "
                f"offset {window.start + seg_table_end}, which would end at byte "
                f"{window.start + payload_end} -- past the end of the file/region "
                f"({window.start + length} byte(s) total)"
            ), window.start + offset, "The file is truncated or corrupt -- re-export and re-upload it."

        # --- the codec whitelist (ADR-0120 clause 2) -----------------------------
        if header_type & OGG_FLAG_BOS:
            if serial in streams:
                return False, (
                    f"Ogg page {page_index} at offset {window.start + offset} starts a logical "
                    f"bitstream with serial number {serial}, which is already in use"
                ), window.start + offset, OGG_REMEDY_REENCODE
            if len(streams) >= MAX_OGG_LOGICAL_STREAMS:
                return False, (
                    f"file declares more than {MAX_OGG_LOGICAL_STREAMS} logical bitstreams; refused"
                ), window.start + offset, "Upload a single audio track per file."
            stream = _OggStream(serial, window.start + offset)
            streams[serial] = stream
            order.append(stream)
        else:
            stream = streams.get(serial)
            if stream is None:
                return False, (
                    f"Ogg page {page_index} at offset {window.start + offset} belongs to logical "
                    f"bitstream {serial}, which never began with a beginning-of-stream page"
                ), window.start + offset, OGG_REMEDY_REENCODE

        if not stream.headers_done:
            if not (header_type & OGG_FLAG_CONTINUED) and stream.pending:
                return False, (
                    f"Ogg page {page_index} at offset {window.start + offset} abandons an incomplete "
                    f"header packet from the previous page of bitstream {serial}"
                ), window.start + offset, OGG_REMEDY_REENCODE
            payload = window.read_at(seg_table_end, payload_len)
            cursor = 0
            for lacing in seg_table:
                stream.pending += payload[cursor:cursor + lacing]
                cursor += lacing
                stream.pending_bytes += lacing
                if stream.pending_bytes > MAX_OGG_HEADER_PACKET_BYTES:
                    return False, (
                        f"a header packet of Ogg bitstream {serial} exceeds the "
                        f"{MAX_OGG_HEADER_PACKET_BYTES} byte ceiling for codec headers"
                    ), window.start + offset, OGG_REMEDY_REENCODE
                if lacing < 255:
                    packet = bytes(stream.pending)
                    stream.pending.clear()
                    stream.pending_bytes = 0
                    ok, reason = _ogg_consume_header_packet(stream, packet)
                    if not ok:
                        return False, reason, stream.first_page_offset, OGG_REMEDY_REENCODE
                    if stream.headers_done:
                        break
        offset = payload_end
        page_index += 1

    for stream in order:
        if not stream.headers_done:
            what = (
                f"its {stream.codec} header packets are incomplete"
                if stream.codec else "it never produced a complete first packet"
            )
            return False, (
                f"the Ogg logical bitstream with serial number {stream.serial} (first page at offset "
                f"{stream.first_page_offset}) is not a complete Vorbis or Opus stream: {what}"
            ), stream.first_page_offset, OGG_REMEDY_REENCODE

    codecs = sorted({s.codec for s in order if s.codec})
    return True, (
        f"well-formed Ogg bitstream: {page_index} page(s) parsed to end of file with no trailing "
        f"data, {len(order)} logical stream(s), codec(s) {', '.join(codecs)} with valid headers"
    ), None, ""


# --- TEXT: full-file streaming validation, bounded memory -------------------------


def validate_text_fully(window: Window) -> tuple[bool, str, Optional[int]]:
    """Stream the entire window through an incremental UTF-8 decoder in bounded
    blocks (never more than TEXT_BLOCK_SIZE bytes resident at once) and check every
    byte for the disallowed-control-byte rule. This is what closes round-2's
    finding 1: the previous version only inspected a 4096-byte prefix, so content
    beyond that prefix (however large) was never actually checked."""
    length = window.length
    decoder = codecs.getincrementaldecoder("utf-8")(errors="strict")
    offset = 0
    while offset < length:
        block_len = min(TEXT_BLOCK_SIZE, length - offset)
        block = window.read_at(offset, block_len)
        if len(block) != block_len:
            return False, f"file/region ended unexpectedly while reading at offset {window.start + offset}", window.start + offset

        bad_idx = magic.find_disallowed_control_byte(block)
        if bad_idx is not None:
            abs_off = window.start + offset + bad_idx
            return False, (
                f"disallowed binary byte 0x{block[bad_idx]:02x} found at offset {abs_off} "
                f"({offset + bad_idx} byte(s) of the file looked like valid text before this point) "
                f"-- a whitelisted text file may not contain binary content anywhere, including as "
                f"trailing data appended after otherwise-valid text"
            ), abs_off
        try:
            decoder.decode(block, final=(offset + block_len >= length))
        except UnicodeDecodeError as exc:
            abs_off = window.start + offset + exc.start
            return False, (
                f"content is not valid UTF-8 at offset {abs_off} "
                f"({offset + exc.start} byte(s) of the file decoded as valid text before this point)"
            ), abs_off
        offset += block_len

    return True, f"well-formed TEXT: {length} byte(s) verified as UTF-8 with no disallowed control bytes", None


# --- GLB: full recursive container validation -------------------------------------


GLB_REMEDY_DEFAULT = (
    "Re-export the model from your 3D tool as glTF 2.0 (.glb or .gltf). Every texture "
    "or buffer a GLB embeds is validated by the same rules as a standalone file, so "
    "the embedded asset named above must itself be a permitted format."
)


class GlbRejected(Exception):
    """Raised internally to short-circuit a GLB walk on the first violation found,
    anywhere in the structure or in any embedded payload at any nesting depth."""

    def __init__(self, detected_format: str, offset: Optional[int], reason: str, remedy: str = ""):
        super().__init__(reason)
        self.detected_format = detected_format
        self.offset = offset
        self.reason = reason
        self.remedy = remedy or GLB_REMEDY_DEFAULT


def _glb_read_exact(window: Window, rel_offset: int, length: int) -> bytes:
    data = window.read_at(rel_offset, length)
    if len(data) != length:
        raise GlbRejected(
            "MALFORMED", window.start + rel_offset,
            f"expected {length} byte(s) at offset {window.start + rel_offset} but only "
            f"{len(data)} were available -- truncated file/region.",
        )
    return data


def _walk_embedded_images(window: Window, gltf_json, bin_chunk: Optional[tuple[int, int]], depth: int) -> None:
    """Inspect every image glTF embeds inside this GLB: bufferView-referenced
    images (data lives in the BIN chunk -- a real, seekable region of the same
    file) and data:-URI images (base64-embedded directly in the JSON chunk text).
    Each embedded payload is validated by recursing into `classify_window` -- the
    *same* function that validates top-level files -- so an embedded payload that
    is itself a container is fully, recursively validated as one, never merely
    header-sniffed (round-2 criterion 11). Raises GlbRejected on the first
    disallowed or malformed payload found, walking images/bufferViews in their
    declared JSON array order so the result is deterministic.
    """
    if not isinstance(gltf_json, dict):
        raise GlbRejected("MALFORMED", None, "GLB JSON chunk root is not an object")

    images = gltf_json.get("images", [])
    if images is None:
        images = []
    if not isinstance(images, list):
        raise GlbRejected("MALFORMED", None, "GLB JSON 'images' is not an array")

    buffer_views = gltf_json.get("bufferViews", [])
    buffers = gltf_json.get("buffers", [])
    if not isinstance(buffer_views, list):
        buffer_views = []
    if not isinstance(buffers, list):
        buffers = []

    for img_index, img in enumerate(images):
        if not isinstance(img, dict):
            continue

        if "bufferView" in img:
            bv_index = img.get("bufferView")
            if not isinstance(bv_index, int) or not (0 <= bv_index < len(buffer_views)):
                raise GlbRejected("MALFORMED", None, f"image[{img_index}] references bufferView {bv_index!r}, which does not exist ({len(buffer_views)} declared)")
            bv = buffer_views[bv_index]
            if not isinstance(bv, dict):
                raise GlbRejected("MALFORMED", None, f"bufferView[{bv_index}] is not an object")
            buf_index = bv.get("buffer", 0)
            if not isinstance(buf_index, int) or not (0 <= buf_index < len(buffers)):
                raise GlbRejected("MALFORMED", None, f"bufferView[{bv_index}] references buffer {buf_index!r}, which does not exist ({len(buffers)} declared)")
            buf = buffers[buf_index]
            if not isinstance(buf, dict):
                raise GlbRejected("MALFORMED", None, f"buffer[{buf_index}] is not an object")
            if buf_index != 0 or buf.get("uri") is not None:
                # Only buffer[0] with no `uri` is backed by the GLB-embedded BIN
                # chunk (glTF 2.0 spec); anything else is an external resource --
                # not bytes inside this file.
                continue
            if bin_chunk is None:
                raise GlbRejected("MALFORMED", None, f"image[{img_index}] references the GLB-embedded buffer but this GLB has no BIN chunk")
            byte_offset = bv.get("byteOffset", 0)
            byte_length = bv.get("byteLength")
            if (
                not isinstance(byte_offset, int) or not isinstance(byte_length, int)
                or byte_offset < 0 or byte_length <= 0
            ):
                raise GlbRejected("MALFORMED", None, f"bufferView[{bv_index}] has an invalid byteOffset/byteLength")
            bin_data_offset, bin_len = bin_chunk
            if byte_offset + byte_length > bin_len:
                raise GlbRejected("MALFORMED", None, f"bufferView[{bv_index}] (offset {byte_offset}, length {byte_length}) exceeds the BIN chunk's {bin_len} byte(s)")

            sub_window = window.sub_window(bin_data_offset + byte_offset, byte_length)
            result = classify_window(sub_window, depth + 1)
            if not result.accepted:
                raise GlbRejected(
                    result.format_id,
                    result.offset if result.offset is not None else sub_window.start,
                    f"embedded payload in GLB BIN chunk (image[{img_index}], bufferView[{bv_index}]) "
                    f"at file offset {sub_window.start}: {result.reason}",
                    result.remedy,
                )

        elif isinstance(img.get("uri"), str) and img["uri"].startswith("data:"):
            uri = img["uri"]
            comma = uri.find(",")
            if comma == -1:
                raise GlbRejected("MALFORMED", None, f"image[{img_index}] has a malformed data: URI")
            header_part = uri[:comma]
            if ";base64" not in header_part:
                # Not base64: cannot carry an arbitrary binary payload the way a
                # BIN-chunk bufferView or a base64 data: URI can.
                continue
            b64_text = uri[comma + 1:]
            # Bound *before* decoding: base64 expands ~4/3, so reject early on
            # text length alone rather than decoding a payload we would refuse
            # anyway.
            if len(b64_text) > (MAX_FULL_SCAN_BYTES * 4 // 3 + 4):
                raise GlbRejected("MALFORMED", None, f"image[{img_index}] data URI is implausibly large; refused before decoding")
            try:
                decoded = base64.b64decode(b64_text, validate=True)
            except Exception as exc:  # noqa: BLE001 -- turned into a named rejection, never swallowed
                raise GlbRejected("MALFORMED", None, f"image[{img_index}] data URI has invalid base64 content: {exc}") from exc

            sub_window = MemoryByteWindow(decoded)
            result = classify_window(sub_window, depth + 1)
            if not result.accepted:
                offset_note = (
                    f"decoded-payload offset {result.offset}" if result.offset is not None
                    else "an unspecified offset within the decoded payload"
                )
                raise GlbRejected(
                    result.format_id, None,
                    f"embedded payload in GLB JSON chunk data URI (image[{img_index}]): "
                    f"{result.reason} (at {offset_note}; this payload is decoded from base64 "
                    f"text and has no single file byte offset of its own)",
                    result.remedy,
                )


def validate_glb_fully(window: Window, depth: int) -> None:
    """Fully parse a GLB container: header, every chunk (bounds-checked against the
    real window size using exact Python-integer arithmetic -- there is no 32-bit
    wraparound to defend against, but the bound is asserted explicitly and
    exercised by a fixture using the maximum uint32 chunk length), and every
    embedded image payload reachable from the JSON chunk, recursively (see
    `_walk_embedded_images`). Raises GlbRejected on any failure; returns normally
    (no value) on success.
    """
    length = window.length
    header = _glb_read_exact(window, 0, GLB_HEADER_SIZE)
    gtf_magic, version, declared_length = struct.unpack("<4sII", header)
    if gtf_magic != b"glTF":
        raise GlbRejected("MALFORMED", window.start, "GLB magic mismatch on full validation")
    if declared_length != length:
        raise GlbRejected(
            "MALFORMED", window.start,
            f"GLB header declares total length {declared_length} but the file/region is {length} byte(s)",
        )

    offset = GLB_HEADER_SIZE
    chunk_index = 0
    gltf_json = None
    bin_chunk: Optional[tuple[int, int]] = None

    # Invariant: every iteration either raises or sets offset to a value <= length
    # (enforced by the end_offset > length check below), so this loop can only
    # exit with offset == length exactly -- there is no way for "quiet" trailing
    # bytes to exist after the last chunk parsed without the *next* iteration's
    # attempt to read a chunk header there failing loudly instead.
    while offset < length:
        if chunk_index >= MAX_CHUNK_COUNT:
            raise GlbRejected("MALFORMED", window.start + offset, f"more than {MAX_CHUNK_COUNT} GLB chunks (possible pathological input); refused")
        if offset + CHUNK_HEADER_SIZE > length:
            raise GlbRejected("MALFORMED", window.start + offset, f"GLB chunk {chunk_index} header truncated at offset {window.start + offset}")
        chunk_header = _glb_read_exact(window, offset, CHUNK_HEADER_SIZE)
        chunk_length, chunk_type = struct.unpack("<I4s", chunk_header)
        data_offset = offset + CHUNK_HEADER_SIZE
        end_offset = data_offset + chunk_length  # exact Python int: exact, never wraps
        if end_offset > length:
            raise GlbRejected(
                "MALFORMED", window.start + offset,
                f"GLB chunk {chunk_index} declares length {chunk_length} byte(s) at offset "
                f"{window.start + data_offset}, which would end at byte {window.start + end_offset} "
                f"-- past the file/region's actual size of {window.start + length} byte(s)",
            )

        if chunk_index == 0:
            if chunk_type != CHUNK_TYPE_JSON:
                raise GlbRejected("MALFORMED", window.start + offset, f"first GLB chunk must be JSON, found chunk type {chunk_type!r}")
            if chunk_length > MAX_JSON_CHUNK_BYTES:
                raise GlbRejected("MALFORMED", window.start + offset, f"GLB JSON chunk is implausibly large ({chunk_length} bytes > {MAX_JSON_CHUNK_BYTES} limit); refused")
            raw = _glb_read_exact(window, data_offset, chunk_length)
            try:
                gltf_json = json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise GlbRejected("MALFORMED", window.start + data_offset, f"GLB JSON chunk is not valid JSON/UTF-8: {exc}") from exc
        elif chunk_type == CHUNK_TYPE_BIN:
            if bin_chunk is not None:
                raise GlbRejected("MALFORMED", window.start + offset, "GLB declares more than one BIN chunk")
            bin_chunk = (data_offset, chunk_length)
        # Any other chunk type is ignored per spec ("Client implementations MUST
        # ignore chunks with unknown types") -- not scanned for embedded payloads
        # because glTF defines no image-reachability into such chunks.

        offset = end_offset
        chunk_index += 1

    if gltf_json is None:
        raise GlbRejected("MALFORMED", window.start + GLB_HEADER_SIZE, "GLB contains no JSON chunk")

    _walk_embedded_images(window, gltf_json, bin_chunk, depth)


# --- Top-level classification dispatcher ------------------------------------------


def classify_window(window: Window, depth: int = 0) -> ClassifyResult:
    """Decide accept/reject for one window (a whole top-level file, or an embedded
    payload's own window -- see the Window/ByteWindow/MemoryByteWindow docstrings).
    This is the single function every acceptance decision in this tool goes
    through, at any nesting depth, which is what makes the round-2 guarantee
    ("well-formed to EOF") uniform rather than a rule enforced at the top level
    only and forgotten one layer down.
    """
    if depth > MAX_GLB_NESTING_DEPTH:
        return ClassifyResult(
            False, "MALFORMED", None,
            f"container nesting exceeds the maximum depth of {MAX_GLB_NESTING_DEPTH} (possible pathological/adversarial nesting)",
            "Flatten the asset: do not embed containers inside containers inside containers. "
            "One level of GLB with its own textures is what this platform expects.",
        )

    length = window.length
    if length == 0:
        return ClassifyResult(
            False, "MALFORMED", None, "file is empty (0 bytes) -- nothing to identify",
            "Delete the empty file, or upload the real content it was meant to hold.",
        )
    if length > MAX_FULL_SCAN_BYTES:
        return ClassifyResult(
            False, "MALFORMED", None,
            f"file/region is {length} byte(s), over the {MAX_FULL_SCAN_BYTES} byte full-validation "
            f"ceiling; refused rather than accepted on a partial scan (round-2 criterion 10)",
            f"Split or shrink the asset so each file is at most {MAX_FULL_SCAN_BYTES} bytes; "
            f"this scanner refuses to accept a file it has not inspected in full.",
        )

    probe = window.read_at(0, min(length, magic.HEADER_PROBE_SIZE))
    sig = magic.identify(probe)

    if sig is not None and not sig.whitelisted:
        reason = (
            f"{sig.description} is a Blizzard client format and is never permitted on the "
            f"platform, regardless of file extension (ADR-0004)."
        )
        if sig.format_id == "WMO":
            orientation = magic.wmo_match_orientation(probe)
            reason += f" (matched the on-disk chunk-tag byte order: {orientation}.)"
        return ClassifyResult(
            False, sig.format_id, window.start + 0, reason,
            f"Delete this file and supply your own asset instead: export a PNG texture, an Ogg "
            f"Vorbis/Opus sound, or a glTF/GLB model. Extracted or converted {sig.format_id} data "
            f"from the game client may never be redistributed here, under any file name.",
        )

    if sig is not None and sig.whitelisted:
        if sig.format_id == "PNG":
            ok, reason, offset, remedy = validate_png_fully(window)
        elif sig.format_id == "OGG":
            ok, reason, offset, remedy = validate_ogg_fully(window)
        elif sig.format_id == "GLB":
            try:
                validate_glb_fully(window, depth)
                ok, reason, offset, remedy = True, (
                    "glTF binary container (whitelisted); full interior recursively "
                    "validated to EOF, no disallowed or malformed payload found"
                ), None, ""
            except GlbRejected as rej:
                # A GLB failure may itself be a *named* rejection bubbled up from a
                # nested payload (e.g. "BLP" found inside the BIN chunk) -- report
                # that specific format, not a generic MALFORMED, so criterion 3's
                # "the embedded format named" requirement holds at any depth.
                return ClassifyResult(False, rej.detected_format, rej.offset, rej.reason, rej.remedy)
        else:  # pragma: no cover - defensive; every whitelisted format_id is handled above
            raise AssertionError(f"unhandled whitelisted signature format_id {sig.format_id!r}")

        if ok:
            return ClassifyResult(True, sig.format_id, None, reason)
        return ClassifyResult(
            False, "MALFORMED", offset,
            f"claims to be {sig.description} (matched the format's signature at the start of the "
            f"file/region) but does not carry only permitted content: {reason}",
            remedy,
        )

    if magic.looks_like_text(probe):
        ok, reason, offset = validate_text_fully(window)
        if ok:
            return ClassifyResult(True, magic.TEXT_FORMAT_ID, None, reason)
        return ClassifyResult(
            False, "MALFORMED", offset, f"looked like text but is not well-formed: {reason}",
            "Text assets (.md, .json, .lua, .txt) must be UTF-8 text from first byte to last. "
            "Remove the binary content this file carries, or upload it as its own file in a "
            "permitted binary format.",
        )

    return ClassifyResult(
        False, "UNKNOWN", None,
        f"content does not match any whitelisted or named Blizzard format "
        f"({len(probe)} header byte(s) sampled); unrecognised formats are rejected -- "
        f"the accept set is a whitelist, not a blacklist (ADR-0004).",
        "Convert the asset to one of the permitted formats before uploading it: PNG for images, "
        "Ogg Vorbis or Ogg Opus for audio, glTF 2.0 (.gltf/.glb) for models, or UTF-8 text for "
        "code and data (.lua, .json, .md, .txt).",
    )


# --- Directory walk ------------------------------------------------------------


def _rel(root: Path, p: Path) -> str:
    return PurePosixPath(p.relative_to(root)).as_posix()


def scan_tree(root: Path, counters: Counters) -> tuple[list[Accepted], list[Rejection], list[ScanError]]:
    accepted: list[Accepted] = []
    rejected: list[Rejection] = []
    scan_errors: list[ScanError] = []

    def walk(dir_path: Path, depth: int) -> None:
        if depth > MAX_DEPTH:
            scan_errors.append(ScanError(
                path=_rel(root, dir_path),
                reason=(
                    f"directory nesting exceeds the maximum depth of {MAX_DEPTH}; "
                    f"not descended further (possible symlink loop or pathological input)"
                ),
            ))
            return
        try:
            entries = sorted(os.scandir(dir_path), key=lambda e: e.name)
        except OSError as exc:
            scan_errors.append(ScanError(path=_rel(root, dir_path), reason=f"cannot list directory: {exc}"))
            return

        for entry in entries:
            entry_path = Path(entry.path)
            if entry.is_symlink():
                counters.skip("symlink not followed (not read for safety)")
                continue
            try:
                is_dir = entry.is_dir(follow_symlinks=False)
            except OSError as exc:
                scan_errors.append(ScanError(path=_rel(root, entry_path), reason=f"cannot stat entry: {exc}"))
                continue
            if is_dir:
                walk(entry_path, depth + 1)
                continue
            try:
                is_file = entry.is_file(follow_symlinks=False)
            except OSError as exc:
                scan_errors.append(ScanError(path=_rel(root, entry_path), reason=f"cannot stat entry: {exc}"))
                continue
            if not is_file:
                counters.skip("not a regular file (special device/socket/fifo)")
                continue

            rel_path = _rel(root, entry_path)
            try:
                size = entry.stat(follow_symlinks=False).st_size
            except OSError as exc:
                scan_errors.append(ScanError(path=rel_path, reason=f"cannot stat file: {exc}"))
                continue

            try:
                fh = open(entry_path, "rb")
            except OSError as exc:
                scan_errors.append(ScanError(path=rel_path, reason=f"cannot read file: {exc}"))
                continue

            try:
                counters.files_inspected += 1
                result = classify_window(ByteWindow(fh, 0, size))
            except Exception as exc:  # noqa: BLE001 -- last-resort fail-closed net, see note below
                # Every validator above either returns a ClassifyResult or raises
                # only GlbRejected (always caught within classify_window). Nothing
                # in this call chain is expected to escape as a bare exception. If
                # one somehow does (e.g. a filesystem error racing the stat/open
                # above), it becomes a named MALFORMED rejection carrying the
                # exception itself -- fail closed, never a silent pass, never an
                # unhandled traceback on stderr. This is not a catch-and-ignore:
                # the exception is recorded, not discarded.
                counters.files_rejected += 1
                rejected.append(Rejection(
                    path=rel_path, detected_format="MALFORMED", signature_offset=None,
                    reason=f"unexpected error while validating this file: {exc!r}",
                    remedy="Report this file to the platform maintainers: the scanner could not "
                           "finish inspecting it, and it is refused rather than accepted unchecked.",
                ))
                fh.close()
                continue
            fh.close()

            if result.accepted:
                counters.files_accepted += 1
                accepted.append(Accepted(path=rel_path, format=result.format_id))
            else:
                counters.files_rejected += 1
                rejected.append(Rejection(
                    path=rel_path, detected_format=result.format_id,
                    signature_offset=result.offset, reason=result.reason,
                    remedy=result.remedy or _MISSING_REMEDY,
                ))

    walk(root, 0)
    accepted.sort(key=lambda a: a.path)
    rejected.sort(key=lambda r: r.path)
    scan_errors.sort(key=lambda e: e.path)
    return accepted, rejected, scan_errors


# --- Report assembly and CLI ---------------------------------------------------


# A rejection with no remedy is a bug in this scanner, not a valid report. The
# placeholder makes that visible in the report itself rather than shipping an empty
# string; `test_every_rejection_carries_a_remedy` fails if it is ever emitted.
_MISSING_REMEDY = (
    "BUG: this scanner produced a rejection without a remedy. Please report it -- "
    "ADR-0120 clause 3 requires every rejection to tell the author what to do."
)


def build_report(root_arg: str, accepted, rejected, scan_errors, counters: Counters) -> dict:
    return {
        "schema_version": SCHEMA_VERSION,
        "root": root_arg,
        "summary": {
            "files_inspected": counters.files_inspected,
            "files_accepted": counters.files_accepted,
            "files_rejected": counters.files_rejected,
            "files_skipped": counters.files_skipped,
            "skipped_reasons": dict(sorted(counters.skipped_reasons.items())),
            "scan_errors": len(scan_errors),
        },
        "accepted": [{"path": a.path, "format": a.format} for a in accepted],
        "rejected": [
            {
                "path": r.path,
                "detected_format": r.detected_format,
                "signature_offset": r.signature_offset,
                "reason": r.reason,
                "remedy": r.remedy,
            }
            for r in rejected
        ],
        "scan_errors": [{"path": e.path, "reason": e.reason} for e in scan_errors],
    }


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Scan a directory tree for whitelisted asset formats, verified well-formed to EOF (ADR-0004).",
    )
    parser.add_argument("root", help="Directory to scan.")
    parser.add_argument("-o", "--output", help="Write the JSON report here instead of stdout.")
    args = parser.parse_args(argv)

    root = Path(args.root)
    if not root.exists():
        print(f"error: path does not exist: {args.root}", file=sys.stderr)
        return 2
    if not root.is_dir():
        print(f"error: not a directory: {args.root}", file=sys.stderr)
        return 2

    counters = Counters()
    accepted, rejected, scan_errors = scan_tree(root, counters)
    report = build_report(args.root, accepted, rejected, scan_errors, counters)
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"

    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)

    return 1 if (rejected or scan_errors) else 0


if __name__ == "__main__":
    sys.exit(main())
