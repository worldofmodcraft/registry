"""Tests for tools/validation/scan_assets.py, one section per task acceptance
criterion (docs/tasks/002-asset-scanner.md). Run with:

    python3 -m unittest discover -s tests/validation -v

Stdlib `unittest` only -- no pytest is installed in this environment and the
task requires the tool stay dependency-free and offline (ADR-0103).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent.parent / "tools" / "validation"
_CONTRACTS = _HERE.parent.parent / "contracts"
sys.path.insert(0, str(_TOOLS))
sys.path.insert(0, str(_HERE))

import fixture_builder as fb  # noqa: E402
import magic  # noqa: E402
import scan_assets as sa  # noqa: E402
import schema_check  # noqa: E402

SCANNER = str(_TOOLS / "scan_assets.py")
REPORT_SCHEMA = json.loads((_CONTRACTS / "validation-report.schema.json").read_text())


def run_scanner(root: Path) -> tuple[int, dict]:
    proc = subprocess.run(
        [sys.executable, SCANNER, str(root)],
        capture_output=True, text=True, timeout=30,
    )
    # Never a traceback: stderr must be empty on every invocation this suite makes.
    assert proc.stderr == "", f"scanner wrote to stderr:\n{proc.stderr}"
    report = json.loads(proc.stdout)
    return proc.returncode, report


def write(root: Path, rel: str, data: bytes) -> Path:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(data)
    return p


def find_magic_import(source: str):
    """Return a description of the first import statement in `source` that binds
    tools/validation/magic.py, or None if there is none.

    Round-3 criterion 18: the original version of this check looked only at
    `ImportFrom.module`, so `from tools.validation import magic` -- which binds the
    real module -- passed undetected. The fix is to check the *imported symbols*
    (`node.names`) as well as the module path, for both statement forms.
    """
    import ast

    def hit(name: str) -> bool:
        # Match the module by path segment, so `magic`, `tools.validation.magic` and
        # `magic.foo` all count while `magical_thinking` does not.
        return "magic" in name.split(".")

    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if hit(alias.name):
                    return f"import {alias.name}"
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ""
            if module and hit(module):
                return f"from {module} import ..."
            for alias in node.names:
                # `from tools.validation import magic` -- the module name is in the
                # *symbol*, not in node.module. This is the case criterion 18 names.
                if hit(alias.name):
                    return f"from {'.' * node.level}{module} import {alias.name}"
    return None


class Criterion1WhitelistAccepted(unittest.TestCase):
    """A tree with valid PNG, OGG, glTF (.gltf JSON), GLB, .md, .json, .lua, .txt
    scans clean, exit code 0."""

    def test_whitelist_tree_scans_clean(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "textures/icon.png", fb.build_png())
            write(root, "sounds/hit.ogg", fb.build_ogg())
            write(root, "models/thing.gltf", fb.build_gltf_json())
            write(root, "models/thing.glb", fb.build_glb(fb.build_gltf_json()))
            write(root, "README.md", b"# My Mod\n\nDescription.\n")
            write(root, "mod.json", b'{"id": "test:hello", "version": "1.0.0"}\n')
            write(root, "scripts/init.lua", b"local mod = {}\nreturn mod\n")
            write(root, "notes.txt", b"plain notes\n")

            code, report = run_scanner(root)
            self.assertEqual(code, 0, msg=json.dumps(report, indent=2))
            self.assertEqual(report["rejected"], [])
            self.assertEqual(report["scan_errors"], [])
            self.assertEqual(report["summary"]["files_inspected"], 8)
            self.assertEqual(report["summary"]["files_accepted"], 8)
            self.assertEqual(report["summary"]["files_rejected"], 0)
            formats = {a["format"] for a in report["accepted"]}
            self.assertEqual(formats, {"PNG", "OGG", "GLB", "TEXT"})


class Criterion2BlizzardFormatsRejected(unittest.TestCase):
    """DBC/MPQ/BLP/M2/WMO under an innocent screenshot.png name are all rejected,
    by magic bytes, and the report names the detected format (not 'unknown')."""

    def test_each_blizzard_format_named_and_rejected(self):
        cases = {
            "dbc": (fb.build_dbc(), "DBC"),
            "mpq": (fb.build_mpq(), "MPQ"),
            "blp": (fb.build_blp(), "BLP"),
            "m2": (fb.build_m2(), "M2"),
            "wmo": (fb.build_wmo_reversed(), "WMO"),  # the on-disk-verified byte order (round-2 finding 4)
        }
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for name, (data, _) in cases.items():
                write(root, f"{name}/screenshot.png", data)

            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            self.assertEqual(len(report["rejected"]), 5)
            by_path = {r["path"]: r for r in report["rejected"]}
            for name, (_, expected_format) in cases.items():
                r = by_path[f"{name}/screenshot.png"]
                self.assertEqual(r["detected_format"], expected_format)
                self.assertNotEqual(r["detected_format"], "UNKNOWN")
                self.assertEqual(r["signature_offset"], 0)
                self.assertIn("Blizzard", r["reason"])


class Criterion3GlbInteriorWalked(unittest.TestCase):
    """A structurally valid GLB whose BIN chunk embeds a BLP payload is rejected
    with the embedded format named and the chunk offset reported. A GLB whose
    embedded payloads are all whitelisted passes."""

    def test_glb_with_embedded_blp_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            blp = fb.build_blp()
            glb = fb.build_glb_with_embedded_image(blp, "image/x-blp")
            write(root, "models/trap.glb", glb)

            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            self.assertEqual(len(report["rejected"]), 1)
            r = report["rejected"][0]
            self.assertEqual(r["path"], "models/trap.glb")
            self.assertEqual(r["detected_format"], "BLP")
            self.assertIsInstance(r["signature_offset"], int)
            self.assertGreater(r["signature_offset"], 0)  # inside the file, past the GLB+JSON-chunk header
            self.assertIn("BLP2", r["reason"])
            self.assertIn("BIN chunk", r["reason"])

    def test_glb_with_only_whitelisted_embedded_payload_passes(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            png = fb.build_png()
            glb = fb.build_glb_with_embedded_image(png, "image/png")
            write(root, "models/ok.glb", glb)

            code, report = run_scanner(root)
            self.assertEqual(code, 0, msg=json.dumps(report, indent=2))
            self.assertEqual(report["rejected"], [])
            self.assertEqual([a["format"] for a in report["accepted"]], ["GLB"])

    def test_glb_with_embedded_blp_via_data_uri_is_rejected(self):
        """Same violation, reached through the *other* glTF embedding mechanism:
        a base64 data: URI inside the JSON chunk rather than a BIN-chunk
        bufferView. Proves the interior walk is not limited to one mechanism."""
        import base64

        blp = fb.build_blp()
        b64 = base64.b64encode(blp).decode("ascii")
        gltf = {
            "asset": {"version": "2.0"},
            "images": [{"uri": f"data:image/x-blp;base64,{b64}"}],
        }
        glb = fb.build_glb(json.dumps(gltf).encode("utf-8"))
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "models/trap2.glb", glb)
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            self.assertEqual(len(report["rejected"]), 1)
            r = report["rejected"][0]
            self.assertEqual(r["detected_format"], "BLP")
            self.assertIn("data URI", r["reason"])


class Criterion4ExtensionNeverTrusted(unittest.TestCase):
    """A real PNG named data.dbc is accepted; a real DBC named art.png is
    rejected. Both directions demonstrated."""

    def test_real_png_under_dbc_extension_is_accepted(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "data.dbc", fb.build_png())
            code, report = run_scanner(root)
            self.assertEqual(code, 0, msg=json.dumps(report, indent=2))
            self.assertEqual(report["accepted"], [{"path": "data.dbc", "format": "PNG"}])

    def test_real_dbc_under_png_extension_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "art.png", fb.build_dbc())
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            self.assertEqual(len(report["rejected"]), 1)
            self.assertEqual(report["rejected"][0]["path"], "art.png")
            self.assertEqual(report["rejected"][0]["detected_format"], "DBC")


class Criterion5HostileInputFailsClosed(unittest.TestCase):
    """Empty file, 3-byte file, GLB chunk length exceeding file size, GLB chunk
    length overflow on sum, and deep nesting are each handled with a named
    error and non-zero exit -- never a traceback, never a silent pass."""

    def test_empty_file(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "empty.txt", b"")
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            r = report["rejected"][0]
            self.assertEqual(r["detected_format"], "MALFORMED")
            self.assertIn("empty", r["reason"])
            self.assertIsNone(r["signature_offset"])

    def test_three_byte_file(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "tiny.bin", fb.build_unknown_binary_too_short())
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            r = report["rejected"][0]
            self.assertEqual(r["detected_format"], "UNKNOWN")

    def test_glb_chunk_length_exceeds_file_size(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "bad.glb", fb.build_glb_bad_chunk_length_exceeds_file())
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            r = report["rejected"][0]
            self.assertEqual(r["detected_format"], "MALFORMED")
            self.assertIn("past the file/region's actual size", r["reason"])

    def test_glb_chunk_length_overflow_on_sum(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "overflow.glb", fb.build_glb_bad_chunk_length_overflow())
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            r = report["rejected"][0]
            self.assertEqual(r["detected_format"], "MALFORMED")
            self.assertIn("4294967295", r["reason"])  # 0xFFFFFFFF, proves no 32-bit wraparound occurred

    def test_deeply_nested_directory(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            deep = root
            for i in range(sa.MAX_DEPTH + 10):
                deep = deep / f"lvl{i}"
            deep.mkdir(parents=True)
            (deep / "buried.txt").write_bytes(b"hello\n")

            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            self.assertGreaterEqual(len(report["scan_errors"]), 1)
            self.assertTrue(any("maximum depth" in e["reason"] for e in report["scan_errors"]))
            self.assertGreater(report["summary"]["scan_errors"], 0)

    def test_no_traceback_and_no_bare_except_pass_in_source(self):
        source = (_TOOLS / "scan_assets.py").read_text()
        self.assertNotIn("except:\n", source)
        self.assertNotIn("except: pass", source)
        # every `except ... :` block must not be immediately followed by a bare `pass`
        import re
        for m in re.finditer(r"except[^\n:]*:\n(\s*)pass\b", source):
            self.fail(f"bare except-pass found: {m.group(0)!r}")


class Criterion6ReportMatchesContract(unittest.TestCase):
    """Output validates against contracts/validation-report.schema.json and
    includes, per rejected file, path/detected_format/signature_offset/reason.
    The summary counts files actually inspected; anything skipped is counted
    with its reason, never silently dropped."""

    def test_report_validates_against_schema_mixed_tree(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "ok.png", fb.build_png())
            write(root, "bad.dbc_named_png.png", fb.build_dbc())
            write(root, "readme.md", b"# hi\n")
            # a symlink, deliberately: must be skipped (counted), never followed
            (root / "link.png").symlink_to(root / "ok.png")

            code, report = run_scanner(root)
            schema_check.validate(report, REPORT_SCHEMA)  # raises on any violation

            self.assertEqual(report["summary"]["files_inspected"],
                              report["summary"]["files_accepted"] + report["summary"]["files_rejected"])
            self.assertEqual(report["summary"]["files_skipped"], 1)
            self.assertIn("symlink not followed (not read for safety)", report["summary"]["skipped_reasons"])
            self.assertEqual(report["summary"]["skipped_reasons"]["symlink not followed (not read for safety)"], 1)
            # sum of skipped_reasons values equals files_skipped
            self.assertEqual(sum(report["summary"]["skipped_reasons"].values()), report["summary"]["files_skipped"])

            rejected_paths = {r["path"] for r in report["rejected"]}
            self.assertIn("bad.dbc_named_png.png", rejected_paths)
            r = next(r for r in report["rejected"] if r["path"] == "bad.dbc_named_png.png")
            for key in ("path", "detected_format", "signature_offset", "reason"):
                self.assertIn(key, r)

    def test_full_schema_object_validated_standalone(self):
        # Validate the schema file itself is well-formed JSON and the validator
        # accepts a hand-built minimal valid report (belt-and-braces on the
        # schema_check tool, independent of the scanner).
        minimal = {
            "schema_version": "1.0.0",
            "root": ".",
            "summary": {
                "files_inspected": 0, "files_accepted": 0, "files_rejected": 0,
                "files_skipped": 0, "skipped_reasons": {}, "scan_errors": 0,
            },
            "accepted": [], "rejected": [], "scan_errors": [],
        }
        schema_check.validate(minimal, REPORT_SCHEMA)

        broken = dict(minimal)
        broken["summary"] = dict(minimal["summary"])
        del broken["summary"]["files_inspected"]
        with self.assertRaises(schema_check.SchemaValidationError):
            schema_check.validate(broken, REPORT_SCHEMA)


class Criterion7OfflineAndDeterministic(unittest.TestCase):
    """No network access; same input tree -> byte-identical report across two
    consecutive runs."""

    def test_two_runs_are_byte_identical(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "a.png", fb.build_png())
            write(root, "b/bad.dbc", fb.build_dbc())
            write(root, "c.md", b"# doc\n")

            out1 = subprocess.run([sys.executable, SCANNER, str(root)], capture_output=True, text=True, timeout=30)
            out2 = subprocess.run([sys.executable, SCANNER, str(root)], capture_output=True, text=True, timeout=30)
            self.assertEqual(out1.stdout, out2.stdout)
            self.assertEqual(out1.returncode, out2.returncode)

    def test_no_networking_imports_in_scanner_or_magic_table(self):
        # Static proof the scanner cannot reach the network: none of the
        # networking-capable stdlib modules are imported anywhere in the tool.
        forbidden = ("socket", "urllib", "http.client", "ftplib", "smtplib", "requests")
        for fname in ("scan_assets.py", "magic.py"):
            source = (_TOOLS / fname).read_text()
            for mod in forbidden:
                self.assertNotIn(f"import {mod}", source, f"{fname} imports {mod}")

    def test_runs_with_network_namespace_unshared(self):
        # Dynamic proof, not just static grep: run the scanner inside a Linux
        # network namespace with no interfaces at all (unshare -n). If this
        # environment's sandbox does not permit unprivileged unshare, skip
        # rather than fail closed on an environment limitation unrelated to
        # the scanner itself.
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "a.png", fb.build_png())
            probe = subprocess.run(["unshare", "-n", "true"], capture_output=True)
            if probe.returncode != 0:
                self.skipTest(f"unshare -n not permitted in this environment: {probe.stderr!r}")
            proc = subprocess.run(
                ["unshare", "-n", sys.executable, SCANNER, str(root)],
                capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(proc.returncode, 0, msg=proc.stderr)
            report = json.loads(proc.stdout)
            self.assertEqual(report["accepted"], [{"path": "a.png", "format": "PNG"}])


class Criterion8NoUnvalidatedTail(unittest.TestCase):
    """For each accepted format, parsing reaches the structural end of the file
    and the file ends there. A valid file of that type with an appended DBC
    payload is rejected, naming trailing data as the reason."""

    def test_png_with_trailing_dbc_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "x.png", fb.build_png_with_trailing_data(fb.build_dbc()))
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            r = report["rejected"][0]
            self.assertEqual(r["detected_format"], "MALFORMED")
            self.assertIn("trailing data", r["reason"])
            self.assertIn("IEND", r["reason"])

    def test_ogg_with_trailing_dbc_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "x.ogg", fb.build_ogg_with_trailing_data(fb.build_dbc()))
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            r = report["rejected"][0]
            self.assertEqual(r["detected_format"], "MALFORMED")
            # The DBC bytes do not form a second valid Ogg page, so the walk
            # fails trying to parse them as one -- also a legitimate, honest
            # rejection reason (not silently accepted either way).
            self.assertTrue(
                "trailing data" in r["reason"] or "truncated" in r["reason"] or "OggS" in r["reason"],
                r["reason"],
            )

    def test_gltf_text_with_trailing_dbc_is_rejected_small_file(self):
        """Small-file variant: the DBC bytes are already inside the cheap
        first-guess probe, so this is caught immediately (as UNKNOWN) rather
        than via the full text validator. Still a real, non-zero-exit rejection
        -- the bypass is closed either way. See the padded variant below for the
        case that specifically exercises full-file validation."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "x.gltf", fb.build_gltf_json_with_trailing_data(fb.build_dbc()))
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            self.assertEqual(len(report["rejected"]), 1)
            self.assertNotIn("x.gltf", [a["path"] for a in report["accepted"]])

    def test_gltf_text_padded_past_probe_then_dbc_is_rejected_via_full_validator(self):
        """The padded variant: with the DBC bytes pushed past HEADER_PROBE_SIZE,
        only genuine full-file validation catches this -- proving criterion 8's
        'no unvalidated tail' guarantee for the TEXT/glTF case specifically,
        not just for the binary container formats."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "x.gltf", fb.build_gltf_padded_then_dbc())
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            r = report["rejected"][0]
            self.assertEqual(r["detected_format"], "MALFORMED")
            self.assertIn("binary byte", r["reason"])
            self.assertGreater(r["signature_offset"], magic.HEADER_PROBE_SIZE)

    def test_glb_with_trailing_dbc_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "x.glb", fb.build_glb_with_trailing_data(fb.build_dbc()))
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            r = report["rejected"][0]
            self.assertEqual(r["detected_format"], "MALFORMED")
            self.assertIn("declares total length", r["reason"])


class Criterion9TruncatedValidPrefixRejected(unittest.TestCase):
    """A file consisting only of a whitelisted signature and nothing else is
    rejected, not accepted."""

    def test_png_signature_only_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "x.png", fb.build_png_signature_only())
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            self.assertEqual(report["accepted"], [])
            self.assertEqual(report["rejected"][0]["detected_format"], "MALFORMED")

    def test_ogg_capture_pattern_only_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "x.ogg", fb.build_ogg_capture_pattern_only())
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            self.assertEqual(report["accepted"], [])
            self.assertEqual(report["rejected"][0]["detected_format"], "MALFORMED")

    def test_glb_header_only_no_chunks_is_rejected(self):
        """The GLB analogue: header alone, no JSON chunk at all."""
        import struct as _struct
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "x.glb", _struct.pack("<4sII", b"glTF", 2, 12))
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            self.assertEqual(report["accepted"], [])
            self.assertIn("no JSON chunk", report["rejected"][0]["reason"])


class Criterion10TextBucketBoundedButFull(unittest.TestCase):
    """A text-classified file is inspected in full, not by a bounded prefix. A
    file of benign text followed at any offset by binary content is rejected.
    The full-validation size ceiling is stated and enforced: reject rather than
    accept beyond it."""

    def test_padding_past_old_probe_window_then_dbc_is_rejected(self):
        """Reproduces round-2 finding 1 exactly: this fixture would have been
        wrongly accepted as TEXT by the round-1 scanner, which only inspected a
        4096-byte prefix."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "script.lua", fb.build_text_padding_then_dbc())
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            self.assertEqual(report["accepted"], [])
            r = report["rejected"][0]
            self.assertEqual(r["detected_format"], "MALFORMED")
            self.assertGreater(r["signature_offset"], magic.HEADER_PROBE_SIZE)

    def test_size_ceiling_is_a_named_constant_and_enforced(self):
        self.assertGreater(sa.MAX_FULL_SCAN_BYTES, 0)
        # A file over the ceiling is rejected outright, not truncated-and-accepted.
        # Proven cheaply with a sparse file rather than actually allocating the
        # ceiling's worth of real bytes.
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            p = Path(root) / "huge.txt"
            with open(p, "wb") as f:
                f.seek(sa.MAX_FULL_SCAN_BYTES + 1)
                f.write(b"\x00")
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            r = report["rejected"][0]
            self.assertEqual(r["detected_format"], "MALFORMED")
            self.assertIn("full-validation ceiling", r["reason"])
            self.assertIn(str(sa.MAX_FULL_SCAN_BYTES), r["reason"])


class Criterion11GlbWalkRecurses(unittest.TestCase):
    """An embedded payload that is itself a container (GLB/glTF) is validated as
    a container, not classified by a header sniff. A GLB whose bufferView
    payload is a fake glTF header followed by a DBC payload is rejected."""

    def test_fake_nested_glb_header_then_dbc_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "trap.glb", fb.build_glb_with_fake_nested_glb_payload())
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            self.assertEqual(report["accepted"], [])
            r = report["rejected"][0]
            # Must NOT be silently accepted as a nested GLB (the round-2 bypass);
            # the recursive validator must have actually attempted to parse the
            # DBC bytes as a GLB chunk and failed the bounds check.
            self.assertNotEqual(r["detected_format"], "GLB")
            self.assertIn("embedded payload", r["reason"])
            self.assertIn("BIN chunk", r["reason"])

    def test_genuinely_nested_well_formed_glb_would_be_walked_not_sniffed(self):
        """Regression guard on the recursion mechanism itself: a bufferView
        payload that is a well-formed GLB-shaped container but whose own JSON
        chunk is invalid must fail for *that* reason (proving the recursive
        parser actually ran), not be waved through on a shallow magic check."""
        import struct as _struct
        # A "container" with the right magic/version/length but a JSON chunk
        # that isn't valid JSON.
        bad_json_chunk = _struct.pack("<I4s", 4, b"JSON") + b"nope"
        fake = _struct.pack("<4sII", b"glTF", 2, 12 + len(bad_json_chunk)) + bad_json_chunk
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "trap2.glb", fb.build_glb_with_embedded_image(fake, "model/gltf-binary"))
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            r = report["rejected"][0]
            self.assertIn("not valid JSON", r["reason"])


class Criterion12WmoByteOrder(unittest.TestCase):
    """Signature constants are verified against on-disk byte order. Both byte
    orders are accepted where a format is genuinely ambiguous, and the report
    says which is which."""

    def test_reversed_on_disk_order_is_named_and_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "screenshot.png", fb.build_wmo_reversed())
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            r = report["rejected"][0]
            self.assertEqual(r["detected_format"], "WMO")
            self.assertIn("reversed", r["reason"])

    def test_forward_order_is_also_named_and_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "screenshot.png", fb.build_wmo_forward())
            code, report = run_scanner(root)
            self.assertNotEqual(code, 0)
            r = report["rejected"][0]
            self.assertEqual(r["detected_format"], "WMO")
            self.assertIn("forward", r["reason"])

    def test_wmo_fixture_bytes_are_actually_reversed_on_disk(self):
        """Guards against reintroducing round-2 finding 4: proves, independently
        of magic.py, that build_wmo_reversed()'s on-disk bytes really are the
        byte-reversed tag (not the ASCII string a human would type by hand)."""
        data = fb.build_wmo_reversed()
        self.assertEqual(data[0:4], b"REVM")
        self.assertNotEqual(data[0:4], b"MVER")


class Criterion13FixturesIndependentlyDerived(unittest.TestCase):
    """Fixtures must not be derived from the implementation under test."""

    def test_fixture_builder_does_not_import_magic_module(self):
        # AST-based, not a text grep: fixture_builder.py's own docstrings
        # legitimately *talk about* not importing magic.py in prose (e.g. "this
        # module never imports from magic.py"), which a naive substring check on
        # "from magic" would misfire on. Checking actual import statements is
        # both correct and immune to that.
        offender = find_magic_import((_HERE / "fixture_builder.py").read_text())
        self.assertIsNone(offender, f"unexpected import binding magic.py: {offender}")

    def test_the_import_check_itself_catches_a_from_package_import(self):
        # Round-3 criterion 18. The previous version of the check above inspected
        # only ImportFrom.module, so `from tools.validation import magic` -- which
        # binds the real module under the plain name `magic` -- sailed straight
        # through it. The bug was in the test, so the demonstration has to be a
        # mutated *source*, not a mutated fixture file: each form below really does
        # bind tools/validation/magic.py, and each must be caught.
        for source, label in [
            ("import magic\n", "import magic"),
            ("import magic as m\n", "aliased import"),
            ("from magic import SIGNATURES\n", "from magic import ..."),
            ("from tools.validation import magic\n", "from-package import (criterion 18)"),
            ("from tools.validation import magic as m\n", "from-package aliased import"),
            ("from ..tools.validation import magic\n", "relative from-package import"),
            ("if True:\n    from tools.validation import magic\n", "nested from-package import"),
        ]:
            with self.subTest(label):
                self.assertIsNotNone(find_magic_import(source), f"{label} was not detected")

    def test_the_import_check_does_not_misfire_on_prose_or_unrelated_names(self):
        for source, label in [
            ('"""this module never imports from magic.py"""\n', "prose in a docstring"),
            ("import struct\nimport zlib\n", "unrelated imports"),
            ("magic = 3\n", "a local variable called magic"),
            ("from pathlib import Path  # not magic\n", "a comment mentioning magic"),
        ]:
            with self.subTest(label):
                self.assertIsNone(find_magic_import(source), f"{label} was wrongly flagged")

    def test_fixture_builder_states_its_own_independent_citations(self):
        source = (_HERE / "fixture_builder.py").read_text()
        for needle in ("AzerothCore", "StormLib", "wow.export"):
            self.assertIn(needle, source)


class Criterion14LimitationsDisclosed(unittest.TestCase):
    """docs/validation/asset-scanner.md states the real residual limits."""

    def test_known_limitations_section_exists_and_is_non_trivial(self):
        doc = (_HERE.parent.parent / "docs" / "validation" / "asset-scanner.md").read_text()
        self.assertIn("Known limitations", doc)
        section = doc.split("Known limitations", 1)[1]
        self.assertGreater(len(section), 200, "Known Limitations section looks too thin to be real disclosure")

    def test_limitations_mention_checksum_and_ceiling_gaps(self):
        doc = (_HERE.parent.parent / "docs" / "validation" / "asset-scanner.md").read_text()
        for needle in ("CRC", "checksum", str(sa.MAX_FULL_SCAN_BYTES)):
            self.assertIn(needle, doc, f"Known Limitations should disclose: {needle}")


class Criterion15PngChunkTypeWhitelist(unittest.TestCase):
    """ADR-0120 clause 1: only IHDR/PLTE/IDAT/IEND plus a short named safe list.
    Unknown, private and unlisted chunks are rejected, including ancillary chunks
    that are harmless elsewhere."""

    def _scan_one(self, name: str, data: bytes):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, name, data)
            code, report = run_scanner(root)
        return code, report

    def test_reviewers_zblz_png_is_rejected_and_names_the_chunk(self):
        # The exact round-3 finding: a valid PNG (signature, IHDR, IDAT, IEND,
        # correct CRCs, no trailing bytes) whose private ancillary chunk carries a
        # complete magic-intact DBC. Round 2 accepted this with exit code 0.
        payload = fb.build_dbc()
        code, report = self._scan_one("art.png", fb.build_png_with_extra_chunk(b"zBLZ", payload))
        self.assertEqual(code, 1)
        self.assertEqual(report["summary"]["files_accepted"], 0)
        rej = report["rejected"][0]
        self.assertIn("zBLZ", rej["reason"], "the rejection must name the offending chunk")
        self.assertIn("ancillary", rej["reason"])
        self.assertTrue(rej["remedy"])

    def test_a_plain_png_is_still_accepted(self):
        # A scanner that rejects everything is not a win.
        code, report = self._scan_one("plain.png", fb.build_png())
        self.assertEqual(code, 0, report)
        self.assertEqual([a["format"] for a in report["accepted"]], ["PNG"])

    def test_every_safe_list_chunk_is_accepted_at_its_spec_fixed_length(self):
        cases = {
            b"gAMA": (45455).to_bytes(4, "big"),
            b"sRGB": bytes([0]),
            b"pHYs": (2835).to_bytes(4, "big") + (2835).to_bytes(4, "big") + bytes([1]),
        }
        self.assertEqual(set(cases) | {b"tRNS"}, set(sa.PNG_SAFE_LIST_REASONS),
                         "a safe-list entry exists that this test does not exercise")
        for tag, data in cases.items():
            with self.subTest(tag.decode()):
                code, report = self._scan_one("a.png", fb.build_png_with_extra_chunk(tag, data))
                self.assertEqual(code, 0, report)

    def test_safe_list_chunks_are_rejected_at_any_other_length(self):
        # The safe list admits *types at a fixed length*, never types as containers.
        for tag, data in [
            (b"gAMA", b"\x00" * 40),
            (b"sRGB", b"\x00" * 40),
            (b"pHYs", b"\x00" * 40),
            (b"tRNS", b"\x00" * 40),  # colour type 0 fixes tRNS at 2 bytes
        ]:
            with self.subTest(tag.decode()):
                code, report = self._scan_one("a.png", fb.build_png_with_extra_chunk(tag, data))
                self.assertEqual(code, 1, report)
                self.assertIn(tag.decode(), report["rejected"][0]["reason"])

    def test_unlisted_public_ancillary_chunks_are_rejected(self):
        # ADR-0120 clause 4 accepts this cost explicitly: colour profiles, text
        # metadata and unusual-but-valid chunks are refused, and the author re-exports.
        for tag, data in [
            (b"tEXt", b"Comment\x00hello"),
            (b"iTXt", b"Comment\x00\x00\x00\x00\x00hello"),
            (b"zTXt", b"Comment\x00\x00xxxx"),
            (b"iCCP", b"p\x00\x00" + b"\x00" * 40),
            (b"eXIf", b"MM\x00*" + b"\x00" * 20),
            (b"tIME", b"\x07\xe6\x09\x03\x00\x00\x00"),
            (b"bKGD", b"\x00\x00"),
        ]:
            with self.subTest(tag.decode()):
                code, report = self._scan_one("a.png", fb.build_png_with_extra_chunk(tag, data))
                self.assertEqual(code, 1, report)
                self.assertIn(tag.decode(), report["rejected"][0]["reason"])

    def test_idat_cannot_be_used_as_the_container_instead(self):
        # Closing the private-chunk route only moves the payload if IDAT -- the one
        # permitted chunk whose length the spec does not fix -- is left uninspected.
        dbc = fb.build_dbc()
        with self.subTest("surplus inside the zlib stream"):
            code, report = self._scan_one("a.png", fb.build_png_with_idat_payload(b"\x00\x00" + dbc))
            self.assertEqual(code, 1, report)
            self.assertIn("inflates to more than", report["rejected"][0]["reason"])
        with self.subTest("raw bytes after the zlib stream, inside the chunk"):
            code, report = self._scan_one("a.png", fb.build_png_with_bytes_after_zlib_stream(dbc))
            self.assertEqual(code, 1, report)
            self.assertIn("follow the end of the PNG's IDAT zlib stream", report["rejected"][0]["reason"])

    def test_a_decompression_bomb_is_rejected_without_materialising_it(self):
        import resource
        data = fb.build_png_decompression_bomb(64 * 1024 * 1024)
        self.assertLess(len(data), 100 * 1024, "the fixture itself must stay tiny")
        code, report = self._scan_one("bomb.png", data)
        self.assertEqual(code, 1, report)
        self.assertIn("inflates to more than", report["rejected"][0]["reason"])
        # The scanner runs in a subprocess, so its peak memory is visible as the
        # children's high-water mark (KiB on Linux). Had the 64 MiB raster been
        # materialised to reject it, this would be far above the bound.
        child_peak_kib = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        self.assertLess(child_peak_kib, 200 * 1024,
                        f"scanner subprocess peaked at {child_peak_kib} KiB -- the IDAT "
                        f"decompression bound is not holding")

    def test_a_second_copy_of_a_single_occurrence_chunk_is_rejected(self):
        code, report = self._scan_one("a.png", fb.build_png_with_extra_chunk(b"IHDR", b"\x00" * 13))
        self.assertEqual(code, 1, report)
        self.assertIn("second 'IHDR'", report["rejected"][0]["reason"])

    def test_safe_list_reasons_are_documented(self):
        # ADR-0120 clause 1: "every entry on that list carries a written reason for
        # its inclusion". The reason strings live in the code; this asserts the doc
        # carries them verbatim, so the two cannot drift apart.
        doc = (_HERE.parent.parent / "docs" / "validation" / "asset-scanner.md").read_text()
        for tag, reason in sa.PNG_SAFE_LIST_REASONS.items():
            with self.subTest(tag.decode()):
                self.assertIn(tag.decode(), doc)
                self.assertIn(reason, doc, f"{tag.decode()}'s written reason is not in the docs")

    def test_permitted_set_is_exactly_the_core_four_plus_the_safe_list(self):
        self.assertEqual(
            sa.PNG_PERMITTED_CHUNKS,
            {b"IHDR", b"PLTE", b"IDAT", b"IEND", b"tRNS", b"gAMA", b"sRGB", b"pHYs"},
        )
        self.assertLessEqual(len(sa.PNG_SAFE_LIST_REASONS), 6, "the safe list is supposed to be short")


    def test_the_content_whitelist_applies_inside_a_glb_too(self):
        # The whole point of the shared classify_window dispatcher: a rule added at
        # the top level must not be missing one layer down. A GLB whose embedded
        # texture is the zBLZ PNG is rejected, naming the chunk, at depth.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "model.glb", fb.build_glb_with_embedded_image(
                fb.build_png_with_extra_chunk(b"zBLZ", fb.build_dbc())))
            code, report = run_scanner(root)
        self.assertEqual(code, 1, report)
        rej = report["rejected"][0]
        self.assertIn("zBLZ", rej["reason"])
        self.assertIn("embedded payload in GLB", rej["reason"])
        self.assertTrue(rej["remedy"])

    def test_a_glb_with_a_plain_embedded_png_is_still_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "model.glb", fb.build_glb_with_embedded_image(fb.build_png()))
            code, report = run_scanner(root)
        self.assertEqual(code, 0, report)


class Criterion16OggPayloadsMustBeVorbisOrOpus(unittest.TestCase):
    """ADR-0120 clause 2: a page whose payload is not a recognised codec stream is
    rejected."""

    def _scan_one(self, name: str, data: bytes):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, name, data)
            code, report = run_scanner(root)
        return code, report

    def test_reviewers_dbc_payload_ogg_is_rejected(self):
        # The exact round-3 finding: a structurally perfect Ogg page (RFC 3533
        # section 6) whose lacing-declared payload is a complete DBC. Round 2
        # accepted this with exit code 0.
        code, report = self._scan_one("hit.ogg", fb.build_ogg_page_with_payload(fb.build_dbc()))
        self.assertEqual(code, 1)
        rej = report["rejected"][0]
        self.assertIn("neither a Vorbis identification header", rej["reason"])
        self.assertIn("WDBC", rej["reason"])
        self.assertTrue(rej["remedy"])

    def test_an_arbitrary_payload_page_is_rejected(self):
        code, report = self._scan_one("hit.ogg", fb.build_ogg_arbitrary_payload_page())
        self.assertEqual(code, 1, report)

    def test_a_real_vorbis_file_is_accepted(self):
        code, report = self._scan_one("real.ogg", fb.build_ogg())
        self.assertEqual(code, 0, report)
        self.assertEqual([a["format"] for a in report["accepted"]], ["OGG"])

    def test_a_real_opus_file_is_accepted(self):
        code, report = self._scan_one("real.opus", fb.build_ogg_opus())
        self.assertEqual(code, 0, report)
        self.assertEqual([a["format"] for a in report["accepted"]], ["OGG"])

    def test_the_real_fixtures_are_the_third_party_bytes_they_claim_to_be(self):
        # Criterion 13's rule applied to files rather than to code: if either fixture
        # is ever regenerated locally it stops being independent evidence, so the
        # digests recorded alongside them are asserted here.
        import hashlib
        expected = {}
        for line in (_HERE / "fixtures" / "sha256sums.txt").read_text().split("\n"):
            if line.strip():
                digest, name = line.split()
                expected[name] = digest
        self.assertEqual(len(expected), 2)
        for name, digest in expected.items():
            with self.subTest(name):
                actual = hashlib.sha256((_HERE / "fixtures" / name).read_bytes()).hexdigest()
                self.assertEqual(actual, digest)

    def test_binary_content_in_a_comment_tag_is_rejected(self):
        # Vorbis comments and Opus tags are the one variable-length, author-supplied
        # region of a codec header. They must be text, or they are just another
        # private chunk with a different name.
        import struct as _struct
        real = fb.build_ogg_opus()
        good_tag = b"TITLE=hello"
        bad_tag = fb.build_dbc()
        tags_packet = (b"OpusTags" + _struct.pack("<I", 5) + b"Lavf5"
                       + _struct.pack("<I", 1) + _struct.pack("<I", len(bad_tag)) + bad_tag)
        # rebuild page 1 (the tags page) of the real file with a binary tag
        head_end = 27 + real[26] + sum(real[27:27 + real[26]])
        page1 = real[head_end:]
        nseg1 = page1[26]
        body_start = 27 + nseg1
        segs = []
        remaining = len(tags_packet)
        while remaining > 255:
            segs.append(255)
            remaining -= 255
        segs.append(remaining)
        rebuilt = page1[:26] + bytes([len(segs)]) + bytes(segs) + tags_packet
        tail_start = body_start + sum(page1[27:27 + nseg1])
        code, report = self._scan_one("t.opus", real[:head_end] + rebuilt + page1[tail_start:])
        self.assertEqual(code, 1, report)
        self.assertIn("not printable UTF-8 text", report["rejected"][0]["reason"])
        # sanity: the same surgery with a *text* tag is still accepted, so the test
        # above is detecting the binary content and not the surgery itself.
        ok_packet = (b"OpusTags" + _struct.pack("<I", 5) + b"Lavf5"
                     + _struct.pack("<I", 1) + _struct.pack("<I", len(good_tag)) + good_tag)
        rebuilt_ok = page1[:26] + bytes([1]) + bytes([len(ok_packet)]) + ok_packet
        code, report = self._scan_one("t.opus", real[:head_end] + rebuilt_ok + page1[tail_start:])
        self.assertEqual(code, 0, report)


class Criterion17RejectionsAreActionable(unittest.TestCase):
    """ADR-0120 clause 3: every rejection names the offending element and the remedy."""

    def test_every_rejection_carries_a_remedy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "zblz.png", fb.build_png_with_extra_chunk(b"zBLZ", fb.build_dbc()))
            write(root, "text.png", fb.build_png_with_extra_chunk(b"tEXt", b"a\x00b"))
            write(root, "idat.png", fb.build_png_with_idat_payload(b"\x00\x00" + fb.build_dbc()))
            write(root, "dbcpayload.ogg", fb.build_ogg_page_with_payload(fb.build_dbc()))
            write(root, "bare.ogg", fb.build_ogg_capture_pattern_only())
            write(root, "tail.ogg", fb.build_ogg_with_trailing_data(fb.build_dbc()))
            write(root, "real.dbc", fb.build_dbc())
            write(root, "real_mpq.png", fb.build_mpq())
            write(root, "real_blp.png", fb.build_blp())
            write(root, "real_m2.png", fb.build_m2())
            write(root, "real_wmo.png", fb.build_wmo_reversed())
            write(root, "empty.png", b"")
            write(root, "tiny.bin", b"\x01\x02\x03")
            write(root, "mystery.bin", b"\x00\xff" * 64)
            write(root, "padded.lua", fb.build_text_padding_then_dbc())
            code, report = run_scanner(root)
        self.assertEqual(code, 1)
        self.assertGreaterEqual(len(report["rejected"]), 15)
        for rej in report["rejected"]:
            with self.subTest(rej["path"]):
                self.assertTrue(rej["remedy"].strip(), "empty remedy")
                self.assertNotIn("BUG:", rej["remedy"], sa._MISSING_REMEDY)
                self.assertGreater(len(rej["remedy"]), 40, "a remedy has to say what to do")

    def test_the_remedy_is_a_separate_contract_field(self):
        # So a caller (a PR comment, an upload form) can surface it without
        # re-parsing prose out of `reason`.
        item = REPORT_SCHEMA["properties"]["rejected"]["items"]
        self.assertIn("remedy", item["required"])
        self.assertEqual(item["properties"]["remedy"]["minLength"], 1)

    def test_a_blizzard_format_rejection_says_what_to_supply_instead(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "screenshot.png", fb.build_blp())
            code, report = run_scanner(root)
        self.assertEqual(code, 1)
        rej = report["rejected"][0]
        self.assertEqual(rej["detected_format"], "BLP")
        self.assertIn("supply your own asset", rej["remedy"])


class Criterion19KnownLimitationsStatesWhatIsNotRead(unittest.TestCase):
    """The doc must say which bytes are inspected and which are not, per format --
    not frame content-blindness as a checksum nicety."""

    def setUp(self):
        self.doc = (_HERE.parent.parent / "docs" / "validation" / "asset-scanner.md").read_text()

    def test_there_is_a_per_format_read_or_not_read_section(self):
        self.assertIn("What is read and what is not", self.doc)
        section = self.doc.split("What is read and what is not", 1)[1]
        for needle in ("PNG", "Ogg", "GLB", "TEXT"):
            self.assertIn(needle, section)

    def test_the_specific_uninspected_regions_are_named(self):
        for needle in (
            "IDAT",                     # PNG pixel bytes
            "setup header",             # Vorbis codebooks
            "audio packet",             # Ogg audio payloads
            "re-encoding on ingest",    # ADR-0120's recorded stronger option
        ):
            self.assertIn(needle, self.doc, f"Known limitations should name: {needle}")

    def test_crc_is_framed_as_irrelevant_not_as_the_residual_gap(self):
        # Criterion 19 forbids the softer framing ("a corrupted CRC would still be
        # accepted"), which reads as though checksums were the missing piece. ADR-0120
        # is explicit that a CRC detects corruption, never smuggling.
        self.assertIn("detect corruption, not smuggling", self.doc)


class SignatureTableSanity(unittest.TestCase):
    """Cheap structural checks on the signature table itself, independent of the
    scanner CLI."""

    def test_header_probe_size_covers_every_signature(self):
        self.assertGreaterEqual(magic.HEADER_PROBE_SIZE, magic.max_header_bytes_needed())

    def test_every_signature_has_a_non_empty_source_citation(self):
        for sig in magic.SIGNATURES:
            self.assertTrue(sig.source.strip(), f"{sig.format_id} has no source citation")

    def test_whitelist_and_blacklist_partition(self):
        whitelisted = {s.format_id for s in magic.SIGNATURES if s.whitelisted}
        blacklisted = {s.format_id for s in magic.SIGNATURES if not s.whitelisted}
        self.assertEqual(whitelisted, {"PNG", "OGG", "GLB"})
        self.assertEqual(blacklisted, {"DBC", "MPQ", "BLP", "M2", "WMO"})
        self.assertTrue(all(s.blizzard for s in magic.SIGNATURES if not s.whitelisted))


if __name__ == "__main__":
    unittest.main()
