"""Tests for the registry data contracts (task 006).

Proves acceptance criteria 1-8 of docs/tasks/006-contracts.md: every worked
example under contracts/examples/ validates (or fails to validate) against
its schema as its filename and `_comment` claim, reserved-namespaces.json
matches its own shape and ADR-0119's two required entries, and the whole
suite runs offline with the standard library only (no imports beyond
`json`, `os`, `unittest`, `pathlib`, and this task's own schema_check.py).

Run with:
    python3 -m unittest discover -s tests/contracts -v
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from schema_check import SchemaValidationError, validate

REPO_ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = REPO_ROOT / "contracts"
EXAMPLES = CONTRACTS / "examples"

SCHEMAS = {
    "entry": json.loads((CONTRACTS / "entry.schema.json").read_text()),
    "page": json.loads((CONTRACTS / "page.schema.json").read_text()),
    "manifest": json.loads((CONTRACTS / "manifest.schema.json").read_text()),
}


def _load_examples(schema_name: str, kind: str) -> list[tuple[Path, dict]]:
    """kind is 'valid' or 'invalid'."""
    directory = EXAMPLES / schema_name / kind
    files = sorted(directory.glob("*.json"))
    return [(f, json.loads(f.read_text())) for f in files]


class SchemaWellFormedTests(unittest.TestCase):
    """The schemas themselves are valid JSON with the expected top-level shape --
    checked once so a broken schema file fails loudly here, not as a confusing
    cascade of every example test failing for an unrelated reason."""

    def test_schemas_are_objects_with_required_keywords(self) -> None:
        for name, schema in SCHEMAS.items():
            with self.subTest(schema=name):
                self.assertEqual(schema.get("type"), "object")
                self.assertIn("$id", schema)
                self.assertIn("properties", schema)
                self.assertIs(schema.get("additionalProperties"), False)


class _ExampleTestMixin:
    """Generates one subTest per example file, so a single failure names the
    exact file rather than only the schema."""

    schema_name: str

    def _run(self, kind: str, must_be_valid: bool) -> None:
        examples = _load_examples(self.schema_name, kind)
        self.assertGreater(
            len(examples), 0, f"no {kind} examples found for {self.schema_name}"
        )
        schema = SCHEMAS[self.schema_name]
        for path, doc in examples:
            with self.subTest(file=path.name):
                self.assertIn("_comment", doc, f"{path} is missing the required '_comment' key")
                self.assertTrue(doc["_comment"].strip(), f"{path}'s '_comment' is empty")
                self.assertIn("example", doc, f"{path} is missing the 'example' key")
                if must_be_valid:
                    try:
                        validate(doc["example"], schema)
                    except SchemaValidationError as exc:
                        self.fail(f"{path} was expected to be VALID but failed: {exc}")
                else:
                    with self.assertRaises(
                        SchemaValidationError,
                        msg=f"{path} was expected to be INVALID but validated cleanly",
                    ):
                        validate(doc["example"], schema)

    def test_valid_examples_validate(self) -> None:
        self._run("valid", must_be_valid=True)

    def test_invalid_examples_are_rejected(self) -> None:
        self._run("invalid", must_be_valid=False)


class EntryExampleTests(_ExampleTestMixin, unittest.TestCase):
    schema_name = "entry"


class PageExampleTests(_ExampleTestMixin, unittest.TestCase):
    schema_name = "page"


class ManifestExampleTests(_ExampleTestMixin, unittest.TestCase):
    schema_name = "manifest"


class ProviderNeutralityTests(unittest.TestCase):
    """Acceptance criterion 2, isolated as its own explicit assertion (not just
    "this example happens to validate") so a future schema change that
    accidentally reintroduces a GitHub-specific constraint is caught here
    even if no one edits the example files."""

    def test_non_github_provider_and_source_url_validate(self) -> None:
        doc = json.loads(
            (EXAMPLES / "entry" / "valid" / "non-github-provider.json").read_text()
        )
        example = doc["example"]
        self.assertNotEqual(example["owner"]["provider"], "github")
        self.assertNotIn("github.com", example["versions"][0]["source_url"])
        validate(example, SCHEMAS["entry"])  # must not raise

    def test_schema_text_never_hardcodes_github(self) -> None:
        # ADR-0058 Section 4: nothing in the schema requires provider to be
        # "github". Grep the raw schema text for a literal "github" outside
        # of prose description strings that merely *mention* it as an
        # example provider name would be a false positive, so this check is
        # deliberately structural instead: no `"enum"` or `"const"` keyword
        # anywhere under `owner.provider` or `versions[].source_url`.
        schema = SCHEMAS["entry"]
        provider_schema = schema["properties"]["owner"]["properties"]["provider"]
        source_url_schema = schema["properties"]["versions"]["items"]["properties"]["source_url"]
        self.assertNotIn("enum", provider_schema)
        self.assertNotIn("const", provider_schema)
        self.assertNotIn("enum", source_url_schema)
        self.assertNotIn("const", source_url_schema)


class OwnerIdIsNumericTests(unittest.TestCase):
    """Acceptance criterion 1's named trap, isolated as its own assertion for
    the same reason as ProviderNeutralityTests above."""

    def test_owner_id_schema_type_is_integer_not_string(self) -> None:
        owner_id_schema = SCHEMAS["entry"]["properties"]["owner"]["properties"]["id"]
        self.assertEqual(owner_id_schema["type"], "integer")

    def test_string_owner_id_is_rejected(self) -> None:
        doc = json.loads(
            (EXAMPLES / "entry" / "invalid" / "owner-id-as-string.json").read_text()
        )
        self.assertIsInstance(doc["example"]["owner"]["id"], str)
        with self.assertRaises(SchemaValidationError):
            validate(doc["example"], SCHEMAS["entry"])


class LicenseListTests(unittest.TestCase):
    """Acceptance criterion 4: MIT passes; LicenseRef-Proprietary and
    NOASSERTION fail. Also proves the vendored list has real provenance
    recorded and is not a hand-written handful of entries."""

    def test_mit_is_osi_approved(self) -> None:
        self.assertIn("MIT", SCHEMAS["manifest"]["properties"]["license"]["enum"])

    def test_licenseref_proprietary_and_noassertion_are_not_osi_approved(self) -> None:
        enum = SCHEMAS["manifest"]["properties"]["license"]["enum"]
        self.assertNotIn("LicenseRef-Proprietary", enum)
        self.assertNotIn("NOASSERTION", enum)

    def test_license_list_has_recorded_provenance(self) -> None:
        comment = SCHEMAS["manifest"]["properties"]["license"]["$comment"]
        self.assertIn("spdx", comment.lower())
        self.assertIn("Fetched", comment)
        self.assertIn("licenseListVersion", comment)

    def test_license_list_is_not_a_hand_written_handful(self) -> None:
        # A partial, hand-written list would plausibly be under 30 entries;
        # the real vendored OSI-approved SPDX set is well over 100.
        self.assertGreater(len(SCHEMAS["manifest"]["properties"]["license"]["enum"]), 100)


class ScreenshotPathTests(unittest.TestCase):
    """Acceptance criterion 3, isolated as its own assertion."""

    def test_absolute_url_screenshot_rejected_in_page_schema(self) -> None:
        doc = json.loads(
            (EXAMPLES / "page" / "invalid" / "screenshot-absolute-url.json").read_text()
        )
        self.assertTrue(doc["example"]["screenshots"][0].startswith("https://"))
        with self.assertRaises(SchemaValidationError):
            validate(doc["example"], SCHEMAS["page"])

    def test_absolute_url_screenshot_rejected_in_manifest_schema(self) -> None:
        doc = json.loads(
            (EXAMPLES / "manifest" / "invalid" / "screenshot-absolute-url.json").read_text()
        )
        self.assertTrue(doc["example"]["screenshots"][0].startswith("https://"))
        with self.assertRaises(SchemaValidationError):
            validate(doc["example"], SCHEMAS["manifest"])

    def test_relative_screenshot_accepted(self) -> None:
        doc = json.loads((EXAMPLES / "page" / "valid" / "basic.json").read_text())
        validate(doc["example"], SCHEMAS["page"])  # must not raise


class ReservedNamespacesTests(unittest.TestCase):
    """Acceptance criterion 5."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.schema = json.loads(
            (REPO_ROOT / "tests" / "contracts" / "reserved-namespaces.schema.json").read_text()
        )
        cls.data = json.loads((REPO_ROOT / "reserved-namespaces.json").read_text())

    def test_validates_against_its_schema(self) -> None:
        validate(self.data, self.schema)  # must not raise

    def test_contains_mc_and_test(self) -> None:
        self.assertIn("mc", self.data["namespaces"])
        self.assertIn("test", self.data["namespaces"])

    def test_org_numeric_id_is_324218296(self) -> None:
        for name in ("mc", "test"):
            with self.subTest(namespace=name):
                owner = self.data["namespaces"][name]["owner"]
                self.assertEqual(owner["id"], 324218296)
                self.assertIsInstance(owner["id"], int)

    def test_each_namespace_has_a_written_reason(self) -> None:
        for name, entry in self.data["namespaces"].items():
            with self.subTest(namespace=name):
                self.assertTrue(entry["reason"].strip())


class DeterminismTests(unittest.TestCase):
    """Acceptance criterion 8: two runs produce identical results. Re-runs
    validation over every example in this process and checks the pass/fail
    outcome is stable -- the harness-level "run the suite twice" proof is in
    the task log (two full `unittest discover` invocations, output diffed)."""

    def test_repeated_validation_is_stable(self) -> None:
        for schema_name in SCHEMAS:
            for kind, must_be_valid in (("valid", True), ("invalid", False)):
                for path, doc in _load_examples(schema_name, kind):
                    outcomes = []
                    for _ in range(2):
                        try:
                            validate(doc["example"], SCHEMAS[schema_name])
                            outcomes.append("valid")
                        except SchemaValidationError:
                            outcomes.append("invalid")
                    self.assertEqual(outcomes[0], outcomes[1], f"{path} was not stable across repeated runs")


if __name__ == "__main__":
    unittest.main()
