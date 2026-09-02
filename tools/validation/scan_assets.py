#!/usr/bin/env python3
"""World of Modcraft asset scanner.

Walks a directory tree, identifies every regular file's real type by magic bytes
(never by extension — ADR-0004), accepts only whitelisted formats (PNG, OGG,
glTF/GLB, plus a text bucket covering plain text / JSON / Lua / Markdown), and
rejects everything else — naming Blizzard formats explicitly when found, including
payloads embedded inside GLB containers. Emits a JSON report matching
contracts/validation-report.schema.json (edges E5/E6 of the registry's dependency
graph) and exits non-zero on any rejection or scan error.

Runtime choice: Python 3 (stdlib only — `struct`, `json`, `base64`, `os`). No
third-party dependency is needed: `struct` parses the GLB binary container exactly
as well as any binary-parsing library would for this scope, and stdlib-only keeps
the tool runnable offline with nothing to install (ADR-0103: boring, predictable).
Node/.mjs was the other option the task allowed; Python was chosen because this
environment already has Python 3.14 available and no Node.js runtime was found
(checked at authoring time), and because `struct.unpack` gives precise, explicit
control over endianness and bounds for every integer field the GLB format defines
-- exactly the control this scanner's fail-closed requirements need.

See docs/validation/asset-scanner.md for the full behaviour writeup.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from typing import Optional

import magic

SCHEMA_VERSION = "1.0.0"

# How deep the walker will descend before refusing to go further. This is what
# makes "a deeply nested directory" (acceptance criterion 5) fail closed with a
# named error instead of hitting a filesystem path-length limit or a recursion
# error. 40 is generous for any real mod's asset tree (a handful of levels in
# practice) and small enough to guarantee termination well before OS path limits.
MAX_DEPTH = 40

# GLB container structure, per the Khronos glTF 2.0 Specification (see the
# citation in magic.py's GLB signature row for the exact source and section).
GLB_HEADER_SIZE = 12  # uint32 magic + uint32 version + uint32 length
CHUNK_HEADER_SIZE = 8  # uint32 chunkLength + uint32 chunkType
CHUNK_TYPE_JSON = b"JSON"
CHUNK_TYPE_BIN = b"BIN\x00"

# A GLB JSON chunk holding many megabytes of JSON is implausible for a mod asset
# and is refused outright rather than parsed — a cheap, explicit bound against a
# maliciously huge "valid" chunk exhausting memory (the task's "never an unbounded
# read" rule, applied to the one place this scanner must read more than a header).
MAX_JSON_CHUNK_BYTES = 32 * 1024 * 1024


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


# --- Content classification (shared by top-level files and embedded payloads) --


def classify_header(header: bytes) -> tuple[bool, str, str]:
    """Decide accept/reject for a bounded header sample. Returns
    (accepted, format_id, reason). Order matters: empty is checked first so an
    empty file can never fall through to the (trivially-true) empty-string text
    decode; named binary signatures are checked before the text heuristic so a
    truncated/garbled binary format is never miscounted as text.
    """
    if len(header) == 0:
        return False, "MALFORMED", "file is empty (0 bytes) -- nothing to identify"

    sig = magic.identify(header)
    if sig is not None:
        if sig.whitelisted:
            return True, sig.format_id, f"{sig.description} (whitelisted asset format)"
        reason = (
            f"{sig.description} is a Blizzard client format and is never "
            f"permitted on the platform, regardless of file extension (ADR-0004)."
        )
        return False, sig.format_id, reason

    if magic.looks_like_text(header):
        return True, magic.TEXT_FORMAT_ID, (
            "plain text / JSON / Lua / Markdown source (whitelisted text bucket; "
            "no extension was consulted to reach this verdict)"
        )

    return False, "UNKNOWN", (
        f"content does not match any whitelisted or named Blizzard format "
        f"({len(header)} header byte(s) sampled); unrecognised formats are "
        f"rejected -- the accept set is a whitelist, not a blacklist (ADR-0004)."
    )


# --- GLB container walk -------------------------------------------------------


class GlbRejected(Exception):
    """Raised internally to short-circuit a GLB walk on the first violation."""

    def __init__(self, detected_format: str, offset: Optional[int], reason: str):
        super().__init__(reason)
        self.detected_format = detected_format
        self.offset = offset
        self.reason = reason


def _read_exact(fh, offset: int, length: int) -> bytes:
    fh.seek(offset)
    data = fh.read(length)
    if len(data) != length:
        raise GlbRejected(
            "MALFORMED", offset,
            f"expected {length} byte(s) at file offset {offset} but only "
            f"{len(data)} were available -- truncated file.",
        )
    return data


def _scan_embedded_payload(fh, probe_offset: int, probe: bytes, where: str) -> None:
    accepted, fmt, reason = classify_header(probe)
    if not accepted:
        raise GlbRejected(
            fmt, probe_offset,
            f"embedded payload {where} at file offset {probe_offset}: {reason}",
        )


def _walk_embedded_images(fh, gltf_json, bin_chunk: Optional[tuple[int, int]], file_size: int) -> None:
    """Inspect every image glTF embeds inside this GLB container: bufferView-
    referenced images (the GLB-native embedding mechanism -- data lives in the
    BIN chunk) and data-URI images (base64-embedded directly in the JSON chunk).
    Raises GlbRejected on the first disallowed payload found. External images
    (a plain `uri` pointing outside the container) are out of scope here -- they
    are not bytes *inside* this file, so they are not this function's concern;
    if present as separate files in the tree they are scanned in their own right
    by the top-level walker.
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
                raise GlbRejected(
                    "MALFORMED", None,
                    f"image[{img_index}] references bufferView {bv_index!r}, "
                    f"which does not exist ({len(buffer_views)} declared)",
                )
            bv = buffer_views[bv_index]
            if not isinstance(bv, dict):
                raise GlbRejected("MALFORMED", None, f"bufferView[{bv_index}] is not an object")
            buf_index = bv.get("buffer", 0)
            if not isinstance(buf_index, int) or not (0 <= buf_index < len(buffers)):
                raise GlbRejected(
                    "MALFORMED", None,
                    f"bufferView[{bv_index}] references buffer {buf_index!r}, "
                    f"which does not exist ({len(buffers)} declared)",
                )
            buf = buffers[buf_index]
            if not isinstance(buf, dict):
                raise GlbRejected("MALFORMED", None, f"buffer[{buf_index}] is not an object")
            if buf_index != 0 or buf.get("uri") is not None:
                # Per the glTF 2.0 spec, only buffer[0] with an undefined `uri`
                # is backed by the GLB-embedded BIN chunk; anything else refers
                # to an external resource that is not bytes inside this file.
                continue
            if bin_chunk is None:
                raise GlbRejected(
                    "MALFORMED", None,
                    f"image[{img_index}] references the GLB-embedded buffer but "
                    f"this GLB has no BIN chunk",
                )
            byte_offset = bv.get("byteOffset", 0)
            byte_length = bv.get("byteLength")
            if (
                not isinstance(byte_offset, int) or not isinstance(byte_length, int)
                or byte_offset < 0 or byte_length <= 0
            ):
                raise GlbRejected(
                    "MALFORMED", None,
                    f"bufferView[{bv_index}] has an invalid byteOffset/byteLength",
                )
            bin_data_offset, bin_len = bin_chunk
            if byte_offset + byte_length > bin_len:
                raise GlbRejected(
                    "MALFORMED", None,
                    f"bufferView[{bv_index}] (offset {byte_offset}, length "
                    f"{byte_length}) exceeds the BIN chunk's {bin_len} byte(s)",
                )
            abs_offset = bin_data_offset + byte_offset
            probe_len = min(byte_length, magic.HEADER_PROBE_SIZE)
            probe = _read_exact(fh, abs_offset, probe_len)
            _scan_embedded_payload(
                fh, abs_offset, probe,
                f"in GLB BIN chunk (image[{img_index}], bufferView[{bv_index}])",
            )

        elif isinstance(img.get("uri"), str) and img["uri"].startswith("data:"):
            uri = img["uri"]
            comma = uri.find(",")
            if comma == -1:
                raise GlbRejected("MALFORMED", None, f"image[{img_index}] has a malformed data: URI")
            header_part = uri[:comma]
            if ";base64" not in header_part:
                # A non-base64 data URI cannot carry an arbitrary binary payload
                # of the kind this scanner exists to catch; nothing to sniff.
                continue
            b64_text = uri[comma + 1:]
            # Decode only as many leading base64 characters as needed to obtain
            # HEADER_PROBE_SIZE decoded bytes -- never decode the whole payload.
            need_chars = ((magic.HEADER_PROBE_SIZE // 3) + 1) * 4
            b64_prefix = b64_text[:need_chars]
            b64_prefix = b64_prefix[: len(b64_prefix) - (len(b64_prefix) % 4)]
            try:
                probe = base64.b64decode(b64_prefix, validate=False)
            except Exception as exc:  # noqa: BLE001 -- turned into a named rejection, never swallowed
                raise GlbRejected(
                    "MALFORMED", None,
                    f"image[{img_index}] data URI has invalid base64 content: {exc}",
                ) from exc
            _scan_embedded_payload(
                fh, None, probe,
                f"in GLB JSON chunk data URI (image[{img_index}])",
            )


def classify_glb(path: Path, file_size_bytes: int) -> tuple[bool, str, Optional[int], str]:
    """Fully parse a GLB container: header, every chunk (bounds-checked against
    the real file size using Python's arbitrary-precision integers -- there is no
    32-bit wraparound to defend against here, but the bound is asserted
    explicitly and exercised by a fixture using the maximum uint32 chunk length,
    so the guarantee is proven rather than assumed), and every embedded image
    payload reachable from the JSON chunk. Returns
    (accepted, detected_format, offset, reason).
    """
    try:
        with open(path, "rb") as fh:
            header = _read_exact(fh, 0, GLB_HEADER_SIZE)
            gtf_magic, version, declared_length = struct.unpack("<4sII", header)
            if gtf_magic != b"glTF":
                # Caller only calls us after magic.identify() already matched
                # this signature; a mismatch here would mean a logic error, not
                # bad input -- fail closed all the same rather than assume.
                raise GlbRejected("MALFORMED", 0, "GLB magic mismatch on re-read")
            if declared_length != file_size_bytes:
                raise GlbRejected(
                    "MALFORMED", 0,
                    f"GLB header declares total length {declared_length} but the "
                    f"file is {file_size_bytes} byte(s)",
                )

            offset = GLB_HEADER_SIZE
            chunk_index = 0
            gltf_json = None
            bin_chunk: Optional[tuple[int, int]] = None

            while offset < file_size_bytes:
                if offset + CHUNK_HEADER_SIZE > file_size_bytes:
                    raise GlbRejected(
                        "MALFORMED", offset,
                        f"chunk {chunk_index} header is truncated at file offset "
                        f"{offset} ({file_size_bytes - offset} byte(s) remain, "
                        f"need {CHUNK_HEADER_SIZE})",
                    )
                chunk_header = _read_exact(fh, offset, CHUNK_HEADER_SIZE)
                chunk_length, chunk_type = struct.unpack("<I4s", chunk_header)
                data_offset = offset + CHUNK_HEADER_SIZE
                end_offset = data_offset + chunk_length  # Python int: exact, never wraps
                if end_offset > file_size_bytes:
                    raise GlbRejected(
                        "MALFORMED", offset,
                        f"chunk {chunk_index} declares length {chunk_length} byte(s) "
                        f"at offset {data_offset}, which would end at byte "
                        f"{end_offset} -- past the file's actual size of "
                        f"{file_size_bytes} byte(s)",
                    )

                if chunk_index == 0:
                    if chunk_type != CHUNK_TYPE_JSON:
                        raise GlbRejected(
                            "MALFORMED", offset,
                            f"first GLB chunk must be JSON, found chunk type "
                            f"{chunk_type!r}",
                        )
                    if chunk_length > MAX_JSON_CHUNK_BYTES:
                        raise GlbRejected(
                            "MALFORMED", offset,
                            f"GLB JSON chunk is implausibly large "
                            f"({chunk_length} bytes > {MAX_JSON_CHUNK_BYTES} limit); refused",
                        )
                    raw = _read_exact(fh, data_offset, chunk_length)
                    try:
                        gltf_json = json.loads(raw.decode("utf-8"))
                    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                        raise GlbRejected(
                            "MALFORMED", data_offset, f"GLB JSON chunk is not valid JSON/UTF-8: {exc}",
                        ) from exc
                elif chunk_type == CHUNK_TYPE_BIN:
                    if bin_chunk is not None:
                        raise GlbRejected(
                            "MALFORMED", offset, "GLB declares more than one BIN chunk",
                        )
                    bin_chunk = (data_offset, chunk_length)
                # Any other chunk type is ignored per spec ("Client implementations
                # MUST ignore chunks with unknown types") -- not scanned for
                # embedded payloads because glTF defines no image-reachability
                # into such chunks; the BIN chunk and JSON data-URIs are the two
                # real embedding mechanisms this format has.

                offset = end_offset
                chunk_index += 1

            if gltf_json is None:
                raise GlbRejected("MALFORMED", GLB_HEADER_SIZE, "GLB contains no JSON chunk")

            _walk_embedded_images(fh, gltf_json, bin_chunk, file_size_bytes)

    except GlbRejected as rej:
        return False, rej.detected_format, rej.offset, rej.reason

    return True, "GLB", 0, "glTF binary container (whitelisted); interior walked, no disallowed payload found"


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
                with open(entry_path, "rb") as fh:
                    header = fh.read(min(size, magic.HEADER_PROBE_SIZE))
            except OSError as exc:
                scan_errors.append(ScanError(path=rel_path, reason=f"cannot read file: {exc}"))
                continue

            counters.files_inspected += 1
            is_accepted, fmt, reason = classify_header(header)

            if is_accepted and fmt == "GLB":
                is_accepted, fmt, offset, reason = classify_glb(entry_path, size)
                if is_accepted:
                    counters.files_accepted += 1
                    accepted.append(Accepted(path=rel_path, format=fmt))
                else:
                    counters.files_rejected += 1
                    rejected.append(Rejection(path=rel_path, detected_format=fmt, signature_offset=offset, reason=reason))
                continue

            if is_accepted:
                counters.files_accepted += 1
                accepted.append(Accepted(path=rel_path, format=fmt))
            else:
                counters.files_rejected += 1
                offset = 0 if fmt not in ("MALFORMED", "UNKNOWN") else None
                rejected.append(Rejection(path=rel_path, detected_format=fmt, signature_offset=offset, reason=reason))

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
        description="Scan a directory tree for whitelisted asset formats by magic bytes (ADR-0004).",
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
