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
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from typing import Optional, Protocol

import magic

SCHEMA_VERSION = "1.0.0"

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

# PNG chunk structure, per the W3C PNG specification (section "Chunk layout"): a
# 4-byte big-endian length, a 4-byte type, `length` bytes of data, then a 4-byte
# big-endian CRC. IHDR must be the first chunk and is always exactly 13 bytes of
# data; IEND marks the end. See docs/validation/asset-scanner.md for the citation
# and for what this scanner deliberately does *not* verify (the CRC itself).
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_CHUNK_HEADER_SIZE = 8  # 4-byte length + 4-byte type
PNG_CRC_SIZE = 4

# Ogg page structure, per RFC 3533 section 6: a 27-byte fixed header (4-byte
# capture pattern "OggS", 1-byte version, 1-byte header type, 8-byte granule
# position, 4-byte serial number, 4-byte page sequence number, 4-byte CRC
# checksum, 1-byte segment count) followed by that many segment-table bytes, then
# a payload whose length is the sum of the segment-table (lacing) values. All
# multi-byte fields are little-endian.
OGG_FIXED_HEADER_SIZE = 27


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


# --- PNG: full chunk-stream validation, to EOF ------------------------------------


def validate_png_fully(window: Window) -> tuple[bool, str, Optional[int]]:
    """Walk the entire PNG chunk stream (never reading chunk *data* payload bytes
    -- only each chunk's 8-byte header is read, and the data + CRC region is
    skipped over via bounds-checked arithmetic) and require it to consume exactly
    `window.length` bytes, ending on IEND. Returns (ok, reason, offset);
    `offset` is an absolute file offset, meaningful only when ok is False.

    Deliberately not verified (see docs/validation/asset-scanner.md, Known
    Limitations): the CRC of each chunk, and any pixel/palette semantics. This is
    a container-framing validator, not an image decoder -- but framing is exactly
    what closes the "arbitrary trailing bytes" bypass, since any trailing content
    that is not itself a well-formed continuation of the chunk stream is caught by
    the final "ends exactly at IEND" check.
    """
    length = window.length
    sig = window.read_at(0, len(PNG_SIGNATURE))
    if sig != PNG_SIGNATURE:
        return False, "PNG signature mismatch on full validation", window.start
    offset = len(PNG_SIGNATURE)
    chunk_index = 0
    while offset < length:
        if chunk_index >= MAX_CHUNK_COUNT:
            return False, f"more than {MAX_CHUNK_COUNT} PNG chunks (possible pathological input); refused", window.start + offset
        if offset + PNG_CHUNK_HEADER_SIZE > length:
            return False, (
                f"PNG chunk {chunk_index} header truncated at offset {window.start + offset} "
                f"({length - offset} byte(s) remain, need {PNG_CHUNK_HEADER_SIZE})"
            ), window.start + offset
        hdr = window.read_at(offset, PNG_CHUNK_HEADER_SIZE)
        data_len, ctype = struct.unpack(">I4s", hdr)  # PNG: big-endian length field
        data_start = offset + PNG_CHUNK_HEADER_SIZE

        if chunk_index == 0 and ctype != b"IHDR":
            return False, f"first PNG chunk must be IHDR, found {ctype!r} at offset {window.start + offset}", window.start + offset
        if chunk_index == 0 and data_len != 13:
            return False, (
                f"IHDR chunk must be exactly 13 bytes of data per the PNG spec, "
                f"found {data_len} at offset {window.start + offset}"
            ), window.start + offset

        end = data_start + data_len + PNG_CRC_SIZE  # exact Python int arithmetic, never wraps
        if end > length:
            return False, (
                f"PNG chunk {chunk_index} ({ctype!r}) declares {data_len} data byte(s) at offset "
                f"{window.start + data_start}, which with its CRC would end at byte "
                f"{window.start + end} -- past the end of the file/region "
                f"({window.start + length} byte(s) total)"
            ), window.start + offset

        if ctype == b"IEND":
            offset = end
            if offset != length:
                trailing = length - offset
                return False, (
                    f"{trailing} byte(s) of trailing data after the PNG stream's IEND chunk "
                    f"(offset {window.start + offset}) -- a well-formed PNG must end exactly at IEND"
                ), window.start + offset
            return True, "well-formed PNG: full chunk stream parsed to IEND with no trailing data", None

        offset = end
        chunk_index += 1

    return False, f"PNG stream ends at offset {window.start + offset} without an IEND chunk (truncated)", window.start + offset


# --- OGG: full page-stream validation, to EOF -------------------------------------


def validate_ogg_fully(window: Window) -> tuple[bool, str, Optional[int]]:
    """Walk the entire Ogg page stream (never reading page *payload* bytes -- only
    each page's fixed 27-byte header and segment table, at most 27+255=282 bytes,
    are read) and require it to consume exactly `window.length` bytes.

    Deliberately not verified (see docs/validation/asset-scanner.md, Known
    Limitations): each page's CRC checksum, and cross-page logical-stream
    consistency (e.g. serial-number continuity). A crafted file whose trailing
    bytes happen to form additional syntactically valid Ogg pages of a different
    logical stream would still pass -- but a raw Blizzard payload glued on will not
    (its bytes must begin with the literal 'OggS' capture pattern to even be
    considered a page at all, which is astronomically unlikely by construction and
    never true of any real DBC/MPQ/BLP/M2/WMO magic).
    """
    length = window.length
    if length < OGG_FIXED_HEADER_SIZE:
        return False, (
            f"file/region is only {length} byte(s), shorter than a minimal Ogg page "
            f"header ({OGG_FIXED_HEADER_SIZE} bytes, RFC 3533 section 6)"
        ), window.start
    offset = 0
    page_index = 0
    while offset < length:
        if page_index >= MAX_CHUNK_COUNT:
            return False, f"more than {MAX_CHUNK_COUNT} Ogg pages (possible pathological input); refused", window.start + offset
        if offset + OGG_FIXED_HEADER_SIZE > length:
            return False, f"Ogg page {page_index} header truncated at offset {window.start + offset}", window.start + offset
        hdr = window.read_at(offset, OGG_FIXED_HEADER_SIZE)
        capture = hdr[0:4]
        if capture != b"OggS":
            return False, (
                f"expected the 'OggS' capture pattern at offset {window.start + offset} "
                f"(start of page {page_index}), found {capture!r} instead"
            ), window.start + offset
        version = hdr[4]
        if version != 0:
            return False, f"Ogg stream structure version {version} at offset {window.start + offset} -- only version 0 is defined (RFC 3533)", window.start + offset
        num_segments = hdr[26]
        seg_table_offset = offset + OGG_FIXED_HEADER_SIZE
        seg_table_end = seg_table_offset + num_segments
        if seg_table_end > length:
            return False, f"Ogg page {page_index} segment table truncated at offset {window.start + seg_table_offset}", window.start + seg_table_offset
        seg_table = window.read_at(seg_table_offset, num_segments)
        payload_len = sum(seg_table)
        payload_end = seg_table_end + payload_len
        if payload_end > length:
            return False, (
                f"Ogg page {page_index} declares a payload of {payload_len} byte(s) starting at "
                f"offset {window.start + seg_table_end}, which would end at byte "
                f"{window.start + payload_end} -- past the end of the file/region "
                f"({window.start + length} byte(s) total)"
            ), window.start + offset
        offset = payload_end
        page_index += 1

    return True, f"well-formed Ogg bitstream: {page_index} page(s) parsed to end of file with no trailing data", None


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


class GlbRejected(Exception):
    """Raised internally to short-circuit a GLB walk on the first violation found,
    anywhere in the structure or in any embedded payload at any nesting depth."""

    def __init__(self, detected_format: str, offset: Optional[int], reason: str):
        super().__init__(reason)
        self.detected_format = detected_format
        self.offset = offset
        self.reason = reason


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
        return ClassifyResult(False, "MALFORMED", None, f"container nesting exceeds the maximum depth of {MAX_GLB_NESTING_DEPTH} (possible pathological/adversarial nesting)")

    length = window.length
    if length == 0:
        return ClassifyResult(False, "MALFORMED", None, "file is empty (0 bytes) -- nothing to identify")
    if length > MAX_FULL_SCAN_BYTES:
        return ClassifyResult(
            False, "MALFORMED", None,
            f"file/region is {length} byte(s), over the {MAX_FULL_SCAN_BYTES} byte full-validation "
            f"ceiling; refused rather than accepted on a partial scan (round-2 criterion 10)",
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
        return ClassifyResult(False, sig.format_id, window.start + 0, reason)

    if sig is not None and sig.whitelisted:
        if sig.format_id == "PNG":
            ok, reason, offset = validate_png_fully(window)
        elif sig.format_id == "OGG":
            ok, reason, offset = validate_ogg_fully(window)
        elif sig.format_id == "GLB":
            try:
                validate_glb_fully(window, depth)
                ok, reason, offset = True, (
                    "glTF binary container (whitelisted); full interior recursively "
                    "validated to EOF, no disallowed or malformed payload found"
                ), None
            except GlbRejected as rej:
                # A GLB failure may itself be a *named* rejection bubbled up from a
                # nested payload (e.g. "BLP" found inside the BIN chunk) -- report
                # that specific format, not a generic MALFORMED, so criterion 3's
                # "the embedded format named" requirement holds at any depth.
                return ClassifyResult(False, rej.detected_format, rej.offset, rej.reason)
        else:  # pragma: no cover - defensive; every whitelisted format_id is handled above
            raise AssertionError(f"unhandled whitelisted signature format_id {sig.format_id!r}")

        if ok:
            return ClassifyResult(True, sig.format_id, None, reason)
        return ClassifyResult(
            False, "MALFORMED", offset,
            f"claims to be {sig.description} (matched the format's signature at the start of the "
            f"file/region) but is not well-formed: {reason}",
        )

    if magic.looks_like_text(probe):
        ok, reason, offset = validate_text_fully(window)
        if ok:
            return ClassifyResult(True, magic.TEXT_FORMAT_ID, None, reason)
        return ClassifyResult(False, "MALFORMED", offset, f"looked like text but is not well-formed: {reason}")

    return ClassifyResult(
        False, "UNKNOWN", None,
        f"content does not match any whitelisted or named Blizzard format "
        f"({len(probe)} header byte(s) sampled); unrecognised formats are rejected -- "
        f"the accept set is a whitelist, not a blacklist (ADR-0004).",
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
                ))

    walk(root, 0)
    accepted.sort(key=lambda a: a.path)
    rejected.sort(key=lambda r: r.path)
    scan_errors.sort(key=lambda e: e.path)
    return accepted, rejected, scan_errors


# --- Report assembly and CLI ---------------------------------------------------


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
