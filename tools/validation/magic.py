"""Magic-byte signature table for the World of Modcraft asset scanner.

ADR-0004 requires that file type is decided by real content (magic bytes), never by
extension, and that the accept set is a **whitelist**: unknown formats are rejected,
"unknown" is a rejection reason, not a pass.

Every row below cites the source the signature was verified against. Per the task's
"Forbidden" list, no signature is shipped from unverified memory: each was checked
against either a real independent-source-code reference or an official specification
document (see the comment on each row). Where a row's source is this project's own
research notes rather than a live fetch, that is stated explicitly.

This module has exactly one job: given a bounded prefix of a file's bytes ("header"),
say what real format it is, or that no known format claims it. It performs no
directory walking, no I/O, and holds no per-run state, so it is trivial to unit test.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Optional

# How many leading bytes of a file we ever look at to decide its type. Every matcher
# below needs far fewer bytes than this; the constant exists so callers can size a
# single bounded read (never a whole-file read) that is guaranteed sufficient for
# every signature in the table, including the two-part WMO check.
HEADER_PROBE_SIZE = 4096


@dataclass(frozen=True)
class Signature:
    """One row of the signature table."""

    format_id: str          # short machine name, e.g. "PNG", "DBC"
    whitelisted: bool       # True = accepted asset format, False = named rejection
    min_bytes: int          # minimum header length this matcher needs to answer
    match: Callable[[bytes], bool]
    source: str             # citation: where this signature was verified
    description: str        # human-readable name used in report reasons
    blizzard: bool = False  # True if this is a real Blizzard client format


def _mver_mohd(header: bytes) -> bool:
    """WMO root files: chunked (IFF-like) format. First chunk is 'MVER' (4-byte
    magic + 4-byte little-endian chunk size + chunk data); the WMO root file's
    second chunk is 'MOHD'. We check both chunk magics rather than only the first,
    per the task's explicit "MVER+MOHD" pairing, to avoid a false match on any other
    hypothetical chunked format that happens to start with a version chunk.
    Source: wow.export (Kruithne/wow.export, WMOLoader.js) — chunk header is
    `{ uint32 chunkID (LE); uint32 chunkSize (LE); }`; MVER = 0x4D564552,
    MOHD = 0x4D4F4844 (both ASCII magics read in file order, i.e. raw bytes
    b"MVER" / b"MOHD" at the start of each chunk).
    """
    if len(header) < 12 or header[0:4] != b"MVER":
        return False
    chunk_size = int.from_bytes(header[4:8], "little", signed=False)
    # A version chunk is 4 bytes in every real WMO; bound the jump so a hostile
    # or truncated file can never make us index past what we were handed.
    if chunk_size > HEADER_PROBE_SIZE:
        return False
    next_chunk_start = 8 + chunk_size
    next_chunk_end = next_chunk_start + 4
    if next_chunk_end > len(header):
        return False
    return header[next_chunk_start:next_chunk_end] == b"MOHD"


# Ordered: whitelist rows first (accept set), then blacklist rows (named Blizzard
# rejections). Order does not affect correctness (every matcher is exclusive by
# construction) but keeps the table readable top-to-bottom as "what we accept, then
# what we explicitly name and reject".
SIGNATURES: tuple[Signature, ...] = (
    Signature(
        format_id="PNG",
        whitelisted=True,
        min_bytes=8,
        match=lambda h: h[:8] == b"\x89PNG\r\n\x1a\n",
        source=(
            "W3C 'Portable Network Graphics (PNG) Specification (Third Edition)', "
            "section 'PNG file signature': the 8-byte signature "
            "89 50 4E 47 0D 0A 1A 0A. Verified 2026-09-02 by fetching "
            "https://www.w3.org/TR/png/#5PNG-file-signature."
        ),
        description="PNG image",
    ),
    Signature(
        format_id="OGG",
        whitelisted=True,
        min_bytes=4,
        match=lambda h: h[:4] == b"OggS",
        source=(
            "RFC 3533 (An Ogg Encapsulation Format), section 6: the Ogg page "
            "capture pattern is the 4 bytes 0x4f 'O', 0x67 'g', 0x67 'g', 0x53 'S' "
            "(\"OggS\"). Verified 2026-09-02 by fetching "
            "https://www.rfc-editor.org/rfc/rfc3533."
        ),
        description="Ogg container (audio)",
    ),
    Signature(
        format_id="GLB",
        whitelisted=True,
        min_bytes=12,
        match=lambda h: h[:4] == b"glTF",
        source=(
            "Khronos glTF 2.0 Specification, 'Binary glTF Layout' / glTF Header: "
            "`magic` MUST equal 0x46546C67, described as \"ASCII string `glTF`\". "
            "Verified 2026-09-02 by fetching the official spec source "
            "(github.com/KhronosGroup/glTF specification/2.0/Specification.adoc, "
            "section 'GLB File Format Specification')."
        ),
        description="glTF binary container (GLB)",
    ),
    Signature(
        format_id="DBC",
        whitelisted=False,
        min_bytes=4,
        match=lambda h: h[:4] == b"WDBC",
        source=(
            "AzerothCore (our own server fork's upstream), "
            "src/common/DataStores/DBCFileLoader.cpp: the loaded header dword is "
            "compared against 0x43424457 with the source comment \"// 'WDBC'\" "
            "(little-endian dword 0x43424457 == raw file bytes 'W' 'D' 'B' 'C'). "
            "Verified 2026-09-02 via `gh api` against "
            "azerothcore/azerothcore-wotlk."
        ),
        description="WoW client database (DBC) format",
        blizzard=True,
    ),
    Signature(
        format_id="MPQ",
        whitelisted=False,
        min_bytes=4,
        match=lambda h: h[:4] == b"MPQ\x1a",
        source=(
            "StormLib (ladislav-zezula/StormLib), the reference MPQ archive "
            "library: MPQ header signature constant 0x1A51504D, which as a "
            "little-endian dword is the raw byte sequence 'M' 'P' 'Q' 0x1A. "
            "Verified 2026-09-02 by fetching src/StormCommon.h from the "
            "StormLib repository."
        ),
        description="MPQ archive format",
        blizzard=True,
    ),
    Signature(
        format_id="BLP",
        whitelisted=False,
        min_bytes=4,
        match=lambda h: h[:4] == b"BLP2",
        source=(
            "wow.export (Kruithne/wow.export), src/js/casc/blp.js: "
            "`BLP_MAGIC = 0x32504c42`, a little-endian dword equal to the raw "
            "ASCII bytes 'B' 'L' 'P' '2'. Verified 2026-09-02 by fetching "
            "blp.js from the wow.export repository."
        ),
        description="BLP2 texture format",
        blizzard=True,
    ),
    Signature(
        format_id="M2",
        whitelisted=False,
        min_bytes=4,
        match=lambda h: h[:4] in (b"MD20", b"MD21"),
        source=(
            "wow.export (Kruithne/wow.export), src/js/constants.js: "
            "`MAGIC.MD20 = 0x3032444D` and `MAGIC.MD21 = 0x3132444D`, "
            "little-endian dwords equal to the raw ASCII bytes 'MD20' / 'MD21' "
            "respectively. Verified 2026-09-02 by fetching constants.js from "
            "the wow.export repository. (MD21 is the Legion+ chunked-M2 "
            "wrapper; MD20 is the classic/WotLK form. Both are named per the "
            "task's explicit 'MD20/MD21' requirement.)"
        ),
        description="M2 model format",
        blizzard=True,
    ),
    Signature(
        format_id="WMO",
        whitelisted=False,
        min_bytes=12,
        match=_mver_mohd,
        source=(
            "wow.export (Kruithne/wow.export), src/js/3D/loaders/WMOLoader.js: "
            "chunk header is a 4-byte magic followed by a little-endian 4-byte "
            "size; MVER (0x4D564552) is the version chunk, MOHD (0x4D4F4844) "
            "is the WMO root header chunk that follows it. Verified "
            "2026-09-02 by fetching WMOLoader.js from the wow.export "
            "repository."
        ),
        description="WMO model format (root file)",
        blizzard=True,
    ),
)


def max_header_bytes_needed() -> int:
    """Largest min_bytes across the table — informational, used by tests to prove
    HEADER_PROBE_SIZE is generous enough for every matcher."""
    return max(sig.min_bytes for sig in SIGNATURES)


def identify(header: bytes) -> Optional[Signature]:
    """Return the Signature that claims this header, or None if no known binary
    format matches. `header` must be a bounded prefix (see HEADER_PROBE_SIZE) —
    this function never looks past what it is given and never asks for more.
    """
    for sig in SIGNATURES:
        if len(header) >= sig.min_bytes and sig.match(header):
            return sig
    return None


# --- Text bucket -----------------------------------------------------------------
#
# The whitelist also covers plain text / JSON / Lua / Markdown (mission §3 key
# facts; task acceptance criterion 1). None of these formats has a magic-byte
# signature — they are exactly the set of files that are *not* claimed by any
# binary signature above and that decode as plain text. This is a deliberate
# design decision (not sourced from an ADR — none defines a JSON/Lua/Markdown
# magic byte, because there isn't one) recorded in the task log under
# "Questions"/log rather than invented silently: the scanner treats
# text/JSON/Lua/Markdown as one "TEXT" whitelist bucket, identified by content
# (valid UTF-8, no NUL bytes, no disallowed control bytes in the sampled header),
# never by the `.md`/`.json`/`.lua`/`.txt` extension.

TEXT_FORMAT_ID = "TEXT"

# Control bytes that are never valid inside program/markup source text. Tab (0x09),
# LF (0x0a) and CR (0x0d) are legitimate whitespace and excluded from this set.
_DISALLOWED_CONTROL_BYTES = bytes(
    b for b in range(0x00, 0x20) if b not in (0x09, 0x0A, 0x0D)
) + bytes([0x7F])


def looks_like_text(header: bytes) -> bool:
    """Bounded, content-based heuristic for the TEXT whitelist bucket.

    `header` is a bounded prefix (at most HEADER_PROBE_SIZE bytes — see the
    scanner, which never reads more than that to make this decision). A file
    qualifies as TEXT only if:
      1. it contains no NUL byte and no other disallowed control byte in the
         sampled prefix (the strongest cheap signal that data is binary), and
      2. the sampled prefix decodes as UTF-8 (allowing the *last* codepoint to be
         a truncated multi-byte sequence, since we may have cut off mid-character
         at the probe boundary — see NOTE below).

    This never trusts the file extension.
    """
    if any(b in header for b in _DISALLOWED_CONTROL_BYTES):
        return False
    try:
        header.decode("utf-8")
        return True
    except UnicodeDecodeError as exc:
        # NOTE: if the failure starts within the last 3 bytes of our probe window,
        # it may simply be a multi-byte UTF-8 character sliced by the bounded read
        # rather than genuinely invalid text. Retry on the safely-complete prefix.
        if exc.start >= len(header) - 3:
            try:
                header[: exc.start].decode("utf-8")
                return True
            except UnicodeDecodeError:
                return False
        return False
