"""Builds real-byte fixture files for the asset scanner's tests.

Every fixture here carries genuine magic bytes for the format it claims to be --
never a placeholder that only "looks right" to a human reading the test. Binary
containers (PNG, GLB) are built programmatically with correct internal structure
(checksums, chunk lengths) using stdlib `zlib`/`struct` rather than hand-typed
byte literals, so their correctness does not depend on anyone's memory.

## Round-2 rule: fixtures are independently derived, never from the implementation

Independent adversarial review (2026-09-02) found that `tools/validation/magic.py`'s
WMO matcher compared on-disk bytes against the literal string "MVER", when the
cited source (wow.export) actually reads the tag as a little-endian integer equal
to 0x4D564552 -- which unpacks to on-disk bytes b"REVM", not b"MVER". The bug
survived a 21-test green suite because this file's `build_wmo()` reproduced the
exact same (wrong) hand-derivation of the byte order, so the test only proved the
matcher agreed with itself, not with reality.

The fix applied here, per the amended task spec's criterion 13: every Blizzard
signature fixture below is derived **mechanically**, via `struct.pack("<I", ...)`
on the exact hex integer constant named in the format's cited source (the same
citations as tools/validation/magic.py, re-stated independently below -- this
module never imports from magic.py, so there is no code path by which a bug in one
could be silently mirrored by the other). Nothing here is a hand-typed ASCII
literal whose byte order depends on a human getting it right by eye.
"""

from __future__ import annotations

import struct
import zlib

# --- Independently-cited hex constants (see module docstring) --------------------
# Re-stated here, not imported from tools/validation/magic.py, precisely so that a
# byte-order bug in one file cannot be invisibly mirrored by the other.

_WDBC_HEX = 0x43424457   # AzerothCore src/common/DataStores/DBCFileLoader.cpp, comment "// 'WDBC'"
_MPQ_HEX = 0x1A51504D    # StormLib src/StormCommon.h, MPQ header signature constant
_BLP2_HEX = 0x32504C42   # wow.export src/js/casc/blp.js, `BLP_MAGIC`
_MD20_HEX = 0x3032444D   # wow.export src/js/constants.js, `MAGIC.MD20`
_MD21_HEX = 0x3132444D   # wow.export src/js/constants.js, `MAGIC.MD21`
_WMO_MVER_HEX = 0x4D564552  # wow.export src/js/3D/loaders/WMOLoader.js, MVER tag compared via readUInt32LE
_WMO_MOHD_HEX = 0x4D4F4844  # wow.export src/js/3D/loaders/WMOLoader.js, MOHD tag compared via readUInt32LE


def build_png(width: int = 1, height: int = 1) -> bytes:
    """A genuinely valid, decodable 1x1 PNG (greyscale, 8-bit), built from
    scratch with correct chunk CRCs -- not copied from anywhere."""

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)  # 8-bit greyscale, no interlace
    raw_scanlines = b"".join(b"\x00" + bytes([0]) * width for _ in range(height))  # filter byte 0 + black pixels
    idat = zlib.compress(raw_scanlines)
    return signature + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


def build_png_signature_only() -> bytes:
    """Just the 8-byte PNG signature and nothing else -- a truncated-but-valid
    prefix that must be rejected, not accepted (round-2 criterion 9)."""
    return b"\x89PNG\r\n\x1a\n"


def build_png_with_trailing_data(extra: bytes) -> bytes:
    """A genuinely valid PNG with `extra` bytes glued on after IEND -- the
    round-2 finding-2 bypass ("whitelisted header, arbitrary tail"), now expected
    to be rejected (criterion 8)."""
    return build_png() + extra


def build_ogg() -> bytes:
    """A single, structurally complete, well-formed Ogg page: real 27-byte fixed
    header, a segment table, and a payload of exactly the length that table
    declares. Deliberately not decodable audio (this scanner does not decode
    audio, only page framing) but a genuinely well-formed Ogg page nonetheless."""
    capture_pattern = b"OggS"
    version = b"\x00"
    header_type = b"\x02"  # beginning-of-stream
    granule_position = struct.pack("<q", 0)
    serial_number = struct.pack("<I", 1)
    page_sequence = struct.pack("<I", 0)
    checksum = struct.pack("<I", 0)  # not verified by this scanner -- see docs, Known Limitations
    payload = b"\x00" * 5
    segment_table = bytes([len(payload)])  # one lacing value describing the whole payload
    return (
        capture_pattern + version + header_type + granule_position + serial_number
        + page_sequence + checksum + bytes([1]) + segment_table + payload
    )


def build_ogg_capture_pattern_only() -> bytes:
    """Just the 4-byte 'OggS' capture pattern -- a truncated-but-valid prefix that
    must be rejected, not accepted (round-2 criterion 9)."""
    return b"OggS"


def build_ogg_with_trailing_data(extra: bytes) -> bytes:
    """A well-formed Ogg page with `extra` bytes glued on after it, where `extra`
    does not itself begin with a valid 'OggS' capture pattern -- rejected as
    trailing data (criterion 8)."""
    assert extra[:4] != b"OggS", "fixture bug: trailing data must not itself look like a page"
    return build_ogg() + extra


def build_gltf_json() -> bytes:
    return (
        b'{"asset":{"version":"2.0","generator":"World of Modcraft fixture builder"},'
        b'"scenes":[],"nodes":[]}'
    )


def build_gltf_json_with_trailing_data(extra: bytes) -> bytes:
    """Valid glTF JSON text with `extra` binary bytes appended -- exercises the
    TEXT bucket's full-file (not prefix) validation (criterion 8, using glTF's
    plain-text .gltf representation as the concrete example criterion 8 names)."""
    return build_gltf_json() + extra


def build_text_padding_then_dbc(padding_bytes: int = 4096) -> bytes:
    """Reproduces round-2 finding 1 exactly: a run of harmless Lua-comment text
    well past the old 4096-byte probe window, followed directly by a real DBC
    payload with no separator. `padding_bytes` defaults to 4096 (the old
    HEADER_PROBE_SIZE) so the DBC bytes land firmly outside where a prefix-only
    scanner would ever look; the caller may pass more to be doubly sure."""
    line = b"-- padding line to push real content past a bounded prefix scan\n"
    padding = (line * (padding_bytes // len(line) + 1))[:padding_bytes]
    return padding + build_dbc()


def build_gltf_padded_then_dbc(padding_bytes: int = 4096) -> bytes:
    """Valid glTF JSON text, padded well past the old 4096-byte probe window with
    harmless whitespace, then a real DBC payload glued on directly. Demonstrates
    criterion 8 for the glTF/TEXT case specifically via the *full* text
    validator's trailing-data path: with this much padding, the cheap first-guess
    probe (which only samples the first HEADER_PROBE_SIZE bytes) never even sees
    the DBC bytes, so only genuine full-file validation catches it. (Contrast
    `build_gltf_json_with_trailing_data`, a small file where the DBC bytes are
    already inside the first probe and get caught immediately as UNKNOWN --
    also a valid rejection, just via a different, earlier code path.)"""
    base = build_gltf_json()
    padding = b" " * max(0, padding_bytes - len(base))
    return base + padding + build_dbc()


def _glb_chunk(chunk_type: bytes, data: bytes) -> bytes:
    assert len(chunk_type) == 4
    pad_byte = b" " if chunk_type == b"JSON" else b"\x00"
    padded = data + pad_byte * ((4 - len(data) % 4) % 4)
    return struct.pack("<I4s", len(padded), chunk_type) + padded


def build_glb(json_bytes: bytes, bin_bytes: bytes | None = None) -> bytes:
    """A structurally correct GLB: header + JSON chunk (+ optional BIN chunk),
    per the Khronos glTF 2.0 binary container layout (see the citation on the
    GLB row of tools/validation/magic.py)."""
    body = _glb_chunk(b"JSON", json_bytes)
    if bin_bytes is not None:
        body += _glb_chunk(b"BIN\x00", bin_bytes)
    total_length = 12 + len(body)
    header = struct.pack("<4sII", b"glTF", 2, total_length)
    return header + body


def build_glb_with_trailing_data(extra: bytes) -> bytes:
    """A structurally valid GLB (header.length matches the *real* original size)
    with `extra` bytes glued on after it, so the file's actual size no longer
    matches the header's declared length -- rejected as trailing data
    (criterion 8)."""
    return build_glb(build_gltf_json()) + extra


def build_glb_with_embedded_image(image_bytes: bytes, mime_type: str = "image/png") -> bytes:
    """A valid GLB whose BIN chunk holds exactly one embedded image, referenced
    the standard glTF way: images[0].bufferView -> bufferViews[0] -> buffers[0]
    (buffer 0, no uri => backed by the GLB BIN chunk, per spec)."""
    import json as _json

    gltf = {
        "asset": {"version": "2.0"},
        "images": [{"bufferView": 0, "mimeType": mime_type}],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(image_bytes)}],
        "buffers": [{"byteLength": len(image_bytes)}],
    }
    return build_glb(_json.dumps(gltf).encode("utf-8"), image_bytes)


def build_glb_with_fake_nested_glb_payload() -> bytes:
    """Round-2 criterion 11's exact demonstrated case: a GLB whose bufferView
    payload is a *fake* glTF container header (correct magic, version, and a
    declared length that matches the fake sub-container's real size) immediately
    followed by a real DBC payload standing in for "chunk 0". A scanner that only
    header-sniffs an embedded payload (checks for the 'glTF' magic and stops) would
    wrongly accept this as a nested GLB; a scanner that recursively validates it as
    a real container must attempt to parse the DBC bytes as a GLB chunk header,
    fail the bounds check (WDBC's bytes as a little-endian chunk length are far
    larger than the tiny fake container), and reject it."""
    dbc_bytes = build_dbc()
    fake_inner_total_length = 12 + len(dbc_bytes)  # 12-byte GLB header + the "chunk" bytes
    fake_glb_header = struct.pack("<4sII", b"glTF", 2, fake_inner_total_length)
    fake_nested_payload = fake_glb_header + dbc_bytes
    return build_glb_with_embedded_image(fake_nested_payload, mime_type="model/gltf-binary")


def build_glb_bad_chunk_length_exceeds_file() -> bytes:
    """A GLB whose header.length matches the real (small) file size, but whose
    single JSON chunk declares a chunkLength larger than the bytes actually
    present -- 'a GLB with a chunk length exceeding the file size' (task
    acceptance criterion 5)."""
    json_bytes = b"{}  "  # 4 bytes, already 4-aligned
    fake_chunk_length = 1000
    chunk_header = struct.pack("<I4s", fake_chunk_length, b"JSON")
    body = chunk_header + json_bytes
    total_length = 12 + len(body)  # header.length matches the *actual* file size
    header = struct.pack("<4sII", b"glTF", 2, total_length)
    return header + body


def build_glb_bad_chunk_length_overflow() -> bytes:
    """A GLB whose single chunk declares the maximum possible uint32 chunk
    length (0xFFFFFFFF) -- 'a GLB with a chunk length that overflows when
    summed' (task acceptance criterion 5). Proves the bounds check uses exact
    (Python arbitrary-precision) arithmetic rather than any fixed-width sum
    that could wrap around."""
    json_bytes = b"{}  "
    max_u32 = 0xFFFFFFFF
    chunk_header = struct.pack("<I4s", max_u32, b"JSON")
    body = chunk_header + json_bytes
    total_length = 12 + len(body)
    header = struct.pack("<4sII", b"glTF", 2, total_length)
    return header + body


# --- Blizzard-format fixtures ----------------------------------------------------
# Every magic-byte prefix below is derived mechanically from the independently
# re-stated hex constant at the top of this file via struct.pack -- never a
# hand-typed ASCII literal (see module docstring: this is precisely the practice
# that would have caught the round-2 WMO byte-order bug before it shipped).

def build_dbc() -> bytes:
    # AzerothCore DBCFileLoader.cpp header layout: magic(4) + record_count(4) +
    # field_count(4) + record_size(4) + string_block_size(4); filled with
    # plausible-looking zero/small values after the real magic.
    return struct.pack("<I", _WDBC_HEX) + struct.pack("<IIII", 0, 0, 0, 0)


def build_mpq() -> bytes:
    return struct.pack("<I", _MPQ_HEX) + b"\x00" * 28  # StormLib-documented MPQ header is 32 bytes; magic + zero filler


def build_blp() -> bytes:
    return struct.pack("<I", _BLP2_HEX) + struct.pack("<I", 1) + b"\x00" * 20  # magic + compression type + filler


def build_m2(variant_hex: int = _MD20_HEX) -> bytes:
    assert variant_hex in (_MD20_HEX, _MD21_HEX)
    return struct.pack("<I", variant_hex) + b"\x00" * 28


def _build_wmo(mver_hex: int, mohd_hex: int) -> bytes:
    """MVER chunk (tag + 4-byte LE size=4 + 4-byte version) followed by the MOHD
    chunk's tag, per the wow.export-cited chunk format. `mver_hex`/`mohd_hex` are
    the exact integers wow.export compares the tag against via readUInt32LE;
    struct.pack derives the real on-disk bytes from them mechanically."""
    mver = struct.pack("<I", mver_hex) + struct.pack("<I", 4) + struct.pack("<I", 17)
    mohd_start = struct.pack("<I", mohd_hex) + struct.pack("<I", 64) + b"\x00" * 16
    return mver + mohd_start


def build_wmo_reversed() -> bytes:
    """The on-disk-verified byte order (round-2 finding 4): WoW's chunked formats
    store the four-character chunk tag byte-reversed, confirmed by converting
    wow.export's readUInt32LE-compared integer constants back to bytes. This is
    what a *real* WMO file's bytes look like."""
    return _build_wmo(_WMO_MVER_HEX, _WMO_MOHD_HEX)


def build_wmo_forward() -> bytes:
    """The forward ('MVER'/'MOHD') spelling, accepted defensively by the matcher
    even though it is not the on-disk-verified order -- see magic.py's module
    docstring for why both are accepted."""
    return b"MVER" + struct.pack("<I", 4) + struct.pack("<I", 17) + b"MOHD" + struct.pack("<I", 64) + b"\x00" * 16


# --- Hostile / non-binary-format fixtures --------------------------------------

def build_unknown_binary_too_short() -> bytes:
    """3 bytes: shorter than any signature in the table (min 4) and containing a
    NUL byte, so it also fails the text heuristic. Neither an accident nor a
    crash risk -- deliberately hostile per acceptance criterion 5."""
    return b"\xff\xfe\x00"
