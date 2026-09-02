"""Builds real-byte fixture files for the asset scanner's tests.

Every fixture here carries genuine magic bytes for the format it claims to be --
never a placeholder that only "looks right" to a human reading the test. Binary
containers (PNG, GLB) are built programmatically with correct internal structure
(checksums, chunk lengths) using stdlib `zlib`/`struct` rather than hand-typed
byte literals, so their correctness does not depend on anyone's memory.

The five Blizzard-format fixtures use only the magic-byte prefix documented and
cited in tools/validation/magic.py -- this scanner only ever inspects a bounded
header, so a magic-correct prefix plus arbitrary filler is a faithful test of
what the scanner actually does, without needing (or claiming) a byte-for-byte
reproduction of any real Blizzard file structure.
"""

from __future__ import annotations

import struct
import zlib


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


def build_ogg() -> bytes:
    """A structurally plausible Ogg page header. Only the 'OggS' capture pattern
    at offset 0 is what this scanner inspects; the rest is a well-formed-looking
    page header (version/type/granule/serial/sequence/checksum/segment table) so
    the fixture is not a bare 4-byte stub."""
    capture_pattern = b"OggS"
    version = b"\x00"
    header_type = b"\x02"  # beginning-of-stream
    granule_position = struct.pack("<q", 0)
    serial_number = struct.pack("<I", 1)
    page_sequence = struct.pack("<I", 0)
    checksum = struct.pack("<I", 0)  # not computed: scanner never checks it, and this fixture is not consumed by a real decoder
    segments = b"\x01\x00"  # one lacing byte, zero-length segment
    return capture_pattern + version + header_type + granule_position + serial_number + page_sequence + checksum + segments


def build_gltf_json() -> bytes:
    return (
        b'{"asset":{"version":"2.0","generator":"World of Modcraft fixture builder"},'
        b'"scenes":[],"nodes":[]}'
    )


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


# --- Blizzard-format fixtures (magic-byte prefix + filler) ---------------------

def build_dbc() -> bytes:
    # AzerothCore DBCFileLoader.cpp header layout: magic(4) + record_count(4) +
    # field_count(4) + record_size(4) + string_block_size(4); filled with
    # plausible-looking zero/small values after the real "WDBC" magic.
    return b"WDBC" + struct.pack("<IIII", 0, 0, 0, 0)


def build_mpq() -> bytes:
    return b"MPQ\x1a" + b"\x00" * 28  # StormLib-documented MPQ header is 32 bytes; magic + zero filler


def build_blp() -> bytes:
    return b"BLP2" + struct.pack("<I", 1) + b"\x00" * 20  # magic + compression type + filler


def build_m2(variant: bytes = b"MD20") -> bytes:
    assert variant in (b"MD20", b"MD21")
    return variant + b"\x00" * 28


def build_wmo() -> bytes:
    """MVER chunk (magic + 4-byte LE size=4 + 4-byte version) followed by the
    MOHD chunk's magic, per the wow.export-cited chunk format."""
    mver = b"MVER" + struct.pack("<I", 4) + struct.pack("<I", 17)
    mohd_start = b"MOHD" + struct.pack("<I", 64) + b"\x00" * 16  # header chunk magic + size + partial filler
    return mver + mohd_start


# --- Hostile / non-binary-format fixtures --------------------------------------

def build_unknown_binary_too_short() -> bytes:
    """3 bytes: shorter than any signature in the table (min 4) and containing a
    NUL byte, so it also fails the text heuristic. Neither an accident nor a
    crash risk -- deliberately hostile per acceptance criterion 5."""
    return b"\xff\xfe\x00"
