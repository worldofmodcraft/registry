"""Magic-byte signature table for the World of Modcraft asset scanner.

ADR-0004 requires that file type is decided by real content (magic bytes), never by
extension, and that the accept set is a **whitelist**: unknown formats are rejected,
"unknown" is a rejection reason, not a pass.

Every row below cites the source the signature was verified against. Per the task's
"Forbidden" list, no signature is shipped from unverified memory: each was checked
against either a real independent-source-code reference or an official specification
document (see the comment on each row).

This module answers exactly one question: given a bounded prefix of a file's bytes
("header"), what real format does it *look like the start of*? That answer is only
ever used by scan_assets.py to decide which full, to-EOF structural validator to run
(see "Spec amendment — round 2" in docs/tasks/002-asset-scanner.md, and
docs/validation/asset-scanner.md) — a signature match here is a **candidate**, never
by itself a verdict. A Blizzard-format signature match *is* a verdict (any file
starting with a real Blizzard magic is rejected outright; no amount of well-formed
structure afterwards would make it acceptable), but a whitelist-format signature
match is only the start of validation, not the end of it.

## Round-2 correction: on-disk byte order (ADR-0004 "verify, don't invent" applied to
## byte order, not just byte value)

Independent adversarial review (2026-09-02) found that `_mver_mohd()`'s previous
implementation compared the on-disk bytes against the literal ASCII strings "MVER"
and "MOHD" — but the cited source (wow.export's WMOLoader.js) reads the tag with
`readUInt32LE()` and compares the *integer* against `0x4D564552` / `0x4D4F4844`.
Converting those integers back to on-disk bytes via little-endian unpacking gives
`b"REVM"` / `b"DHOM"` — WoW's chunked formats (WMO, ADT, WDT) store the four-character
chunk tag **byte-reversed** on disk relative to how it is conventionally written in
documentation and tools. The previous code matched a string that can never appear in
a real WMO file, so criterion 2's WMO case was passing for the wrong reason (it still
failed closed, as UNKNOWN, but never *named* the format — a real, if less severe,
defect).

Every one of the five Blizzard signatures below is therefore now derived
*mechanically* from the exact hex integer constant found in its cited source, via
`struct.pack("<I", ...)`, rather than by a human transcribing or reversing an ASCII
string by eye. This does not change DBC/MPQ/BLP/M2 (their on-disk bytes were already
the forward ASCII form — confirmed by running the same derivation on all five and
observing only WMO differs) but removes the entire class of "the source uses
little-endian numeric comparison and a human silently re-derived the wrong on-disk
string" bug for all of them, not just the one that was caught. Because it is not
certain that *every* on-disk chunk tag in the wild follows the reversed convention
(the "MVER"/"MOHD" spelling is extremely common informally, including in some tools
and mods), the WMO matcher accepts **both** orderings and names which one matched —
a false negative here (missing a real WMO) is a worse failure than an unnecessary
extra branch.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import Callable, Optional

# How many leading bytes of a file we look at to decide which full validator to run.
# This is a *candidate* signal only (see module docstring) — it never by itself
# accepts a whitelisted format. It still needs to be generous enough to hold every
# matcher's minimum requirement, including the two-chunk WMO check.
HEADER_PROBE_SIZE = 4096


@dataclass(frozen=True)
class Signature:
    """One row of the signature table."""

    format_id: str          # short machine name, e.g. "PNG", "DBC"
    whitelisted: bool       # True = candidate for a whitelisted format (see module docstring)
    min_bytes: int          # minimum header length this matcher needs to answer
    match: Callable[[bytes], bool]
    source: str             # citation: where this signature was verified
    description: str        # human-readable name used in report reasons
    blizzard: bool = False  # True if this is a real Blizzard client format


# --- Blizzard on-disk byte derivation (see module docstring) ---------------------
# Each constant below is the exact hex integer named in its cited source, converted
# to on-disk bytes the same way that source's own reader does (a little-endian
# 32-bit read). Nothing here is a hand-typed ASCII string.

_WDBC_LE = struct.pack("<I", 0x43424457)  # AzerothCore DBCFileLoader.cpp -> b'WDBC'
_MPQ_LE = struct.pack("<I", 0x1A51504D)   # StormLib MPQ header signature -> b'MPQ\x1a'
_BLP2_LE = struct.pack("<I", 0x32504C42)  # wow.export BLP_MAGIC -> b'BLP2'
_MD20_LE = struct.pack("<I", 0x3032444D)  # wow.export MAGIC.MD20 -> b'MD20'
_MD21_LE = struct.pack("<I", 0x3132444D)  # wow.export MAGIC.MD21 -> b'MD21'
_WMO_MVER_REVERSED = struct.pack("<I", 0x4D564552)  # wow.export MVER, readUInt32LE -> b'REVM'
_WMO_MOHD_REVERSED = struct.pack("<I", 0x4D4F4844)  # wow.export MOHD, readUInt32LE -> b'DHOM'
_WMO_MVER_FORWARD = b"MVER"  # accepted defensively too -- see module docstring
_WMO_MOHD_FORWARD = b"MOHD"


def _mver_mohd(header: bytes) -> bool:
    """WMO root files: chunked (IFF-like) format. First chunk is a 4-byte tag +
    4-byte little-endian chunk size + chunk data; the WMO root file's second chunk
    is the header chunk. Tries the on-disk-verified reversed tag order first
    (`REVM`/`DHOM`, mechanically derived from wow.export's cited integer constants —
    see module docstring), then the forward spelling (`MVER`/`MOHD`) as a defensive
    fallback so a real WMO is never missed because of byte-order uncertainty.
    """
    return _mver_mohd_orientation(header) is not None


def _mver_mohd_orientation(header: bytes) -> Optional[str]:
    """Returns which tag orientation matched ("reversed" or "forward"), or None."""
    if len(header) < 12:
        return None
    for mver_tag, mohd_tag, name in (
        (_WMO_MVER_REVERSED, _WMO_MOHD_REVERSED, "reversed"),
        (_WMO_MVER_FORWARD, _WMO_MOHD_FORWARD, "forward"),
    ):
        if header[0:4] != mver_tag:
            continue
        chunk_size = int.from_bytes(header[4:8], "little", signed=False)
        # A version chunk is 4 bytes in every real WMO; bound the jump so a hostile
        # or truncated file can never make us index past what we were handed.
        if chunk_size > HEADER_PROBE_SIZE:
            continue
        next_chunk_start = 8 + chunk_size
        next_chunk_end = next_chunk_start + 4
        if next_chunk_end > len(header):
            continue
        if header[next_chunk_start:next_chunk_end] == mohd_tag:
            return name
    return None


# Ordered: whitelist rows first (accept-candidate set), then blacklist rows (named
# Blizzard rejections). Order does not affect correctness (every matcher is
# exclusive by construction) but keeps the table readable top-to-bottom.
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
        match=lambda h: h[:4] == _WDBC_LE,
        source=(
            "AzerothCore (our own server fork's upstream), "
            "src/common/DataStores/DBCFileLoader.cpp: the loaded header dword is "
            "compared against 0x43424457 with the source comment \"// 'WDBC'\". "
            "On-disk bytes derived mechanically via struct.pack('<I', 0x43424457) "
            "= b'WDBC' (forward -- confirmed, not assumed, after the round-2 WMO "
            "byte-order finding prompted re-deriving all five this way). "
            "Verified 2026-09-02 via `gh api` against azerothcore/azerothcore-wotlk."
        ),
        description="WoW client database (DBC) format",
        blizzard=True,
    ),
    Signature(
        format_id="MPQ",
        whitelisted=False,
        min_bytes=4,
        match=lambda h: h[:4] == _MPQ_LE,
        source=(
            "StormLib (ladislav-zezula/StormLib), the reference MPQ archive "
            "library: MPQ header signature constant 0x1A51504D. On-disk bytes "
            "derived mechanically via struct.pack('<I', 0x1A51504D) = b'MPQ\\x1a' "
            "(forward -- confirmed by the same re-derivation as above). "
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
        match=lambda h: h[:4] == _BLP2_LE,
        source=(
            "wow.export (Kruithne/wow.export), src/js/casc/blp.js: "
            "`BLP_MAGIC = 0x32504c42`. On-disk bytes derived mechanically via "
            "struct.pack('<I', 0x32504c42) = b'BLP2' (forward -- confirmed). "
            "Verified 2026-09-02 by fetching blp.js from the wow.export "
            "repository."
        ),
        description="BLP2 texture format",
        blizzard=True,
    ),
    Signature(
        format_id="M2",
        whitelisted=False,
        min_bytes=4,
        match=lambda h: h[:4] in (_MD20_LE, _MD21_LE),
        source=(
            "wow.export (Kruithne/wow.export), src/js/constants.js: "
            "`MAGIC.MD20 = 0x3032444D` and `MAGIC.MD21 = 0x3132444D`. On-disk "
            "bytes derived mechanically via struct.pack('<I', ...) = b'MD20' / "
            "b'MD21' respectively (forward -- confirmed). Verified 2026-09-02 by "
            "fetching constants.js from the wow.export repository. (MD21 is the "
            "Legion+ chunked-M2 wrapper; MD20 is the classic/WotLK form. Both are "
            "named per the task's explicit 'MD20/MD21' requirement.)"
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
            "chunk header is a 4-byte tag read via `readUInt32LE()` followed by a "
            "little-endian 4-byte size; MVER tag compared against integer "
            "0x4D564552, MOHD tag against 0x4D4F4844. **Round-2 correction**: "
            "converting those integers to on-disk bytes via "
            "struct.pack('<I', ...) gives b'REVM' / b'DHOM', not the ASCII "
            "strings 'MVER'/'MOHD' -- WMO's chunk tags are stored byte-reversed "
            "on disk (a documented quirk of WoW's chunked WMO/ADT/WDT formats). "
            "This matcher accepts the on-disk-verified reversed order first and "
            "the forward spelling as a defensive fallback, and reports which one "
            "matched (see `_mver_mohd_orientation`). Verified 2026-09-02 by "
            "fetching WMOLoader.js from the wow.export repository."
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
    """Return the Signature whose pattern this header prefix matches, or None.
    `header` must be a bounded prefix (see HEADER_PROBE_SIZE) — this function never
    looks past what it is given and never asks for more.

    IMPORTANT: for a whitelisted format, this is only a *candidate* match — the
    caller (scan_assets.py) must still run that format's full structural validator
    over the entire file before accepting it (see the module docstring and
    docs/tasks/002-asset-scanner.md, "Spec amendment — round 2"). For a Blizzard
    (blacklisted) format, a match here is already a full verdict: any file starting
    with a real Blizzard magic is rejected regardless of what follows.
    """
    for sig in SIGNATURES:
        if len(header) >= sig.min_bytes and sig.match(header):
            return sig
    return None


def wmo_match_orientation(header: bytes) -> Optional[str]:
    """Public wrapper so scan_assets.py can report which tag orientation ("reversed"
    or "forward") a WMO match used, for the report reason text (criterion 12: "say
    which is which")."""
    return _mver_mohd_orientation(header)


# --- Text bucket -----------------------------------------------------------------
#
# The whitelist also covers plain text / JSON / Lua / Markdown (mission §3 key
# facts; task acceptance criterion 1). None of these formats has a magic-byte
# signature — they are exactly the set of files that are *not* claimed by any
# binary signature above and that decode as plain text, over their **entire**
# content (round-2 criterion 10 — the previous version sampled only a bounded
# header prefix, which is the exact bug independent review's finding 1 exploited).
# This is a deliberate design decision (not sourced from an ADR — none defines a
# JSON/Lua/Markdown magic byte, because there isn't one): the scanner treats
# text/JSON/Lua/Markdown as one "TEXT" whitelist bucket, identified by content
# (valid UTF-8, no NUL bytes, no disallowed control bytes anywhere in the file, up
# to the size ceiling documented in scan_assets.py), never by the
# `.md`/`.json`/`.lua`/`.txt` extension. See scan_assets.py's `validate_text_fully`
# for the full-file, bounded-memory streaming check that actually applies this.

TEXT_FORMAT_ID = "TEXT"

# Control bytes that are never valid inside program/markup source text. Tab (0x09),
# LF (0x0a) and CR (0x0d) are legitimate whitespace and excluded from this set.
_DISALLOWED_CONTROL_BYTES = frozenset(
    b for b in range(0x00, 0x20) if b not in (0x09, 0x0A, 0x0D)
) | {0x7F}


def find_disallowed_control_byte(chunk: bytes) -> Optional[int]:
    """Index within `chunk` (any slice of a file, not necessarily the whole file)
    of the first byte that disqualifies the TEXT bucket, or None if there is none.
    Used by scan_assets.py's streaming full-file text validator, one bounded block
    at a time, to report a precise, honest offset rather than merely "somewhere in
    here"."""
    for i, b in enumerate(chunk):
        if b in _DISALLOWED_CONTROL_BYTES:
            return i
    return None


def has_disallowed_control_byte(chunk: bytes) -> bool:
    """True if `chunk` contains a byte that disqualifies the TEXT bucket."""
    return find_disallowed_control_byte(chunk) is not None


def looks_like_text(header: bytes) -> bool:
    """Cheap, bounded, content-based *first guess* for the TEXT whitelist bucket,
    used only to decide whether to attempt the full-file validator in
    scan_assets.py — this function alone never accepts a file (round-2 fix: the
    previous version's verdict from this function alone was the bug). `header` is
    a bounded prefix (at most HEADER_PROBE_SIZE bytes).
    """
    if has_disallowed_control_byte(header):
        return False
    try:
        header.decode("utf-8")
        return True
    except UnicodeDecodeError as exc:
        # If the failure starts within the last 3 bytes of our probe window, it may
        # simply be a multi-byte UTF-8 character sliced by the bounded read rather
        # than genuinely invalid text. Retry on the safely-complete prefix. (The
        # full-file validator re-checks this properly, in whole blocks, with no
        # such boundary ambiguity.)
        if exc.start >= len(header) - 3:
            try:
                header[: exc.start].decode("utf-8")
                return True
            except UnicodeDecodeError:
                return False
        return False
