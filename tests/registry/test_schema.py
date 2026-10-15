"""schema: each changed JSON file validated against the schema its path implies (criterion 2 of the
umbrella 'Forbidden' list: the repository's own validator, no reimplementation)."""

import json
import unittest
from unittest import mock

import support
from support import attacker_entry, entry, pending, published, report, schema, schema_check

ENTRY = "mods/kelsi.housing/entry.json"
PAGE = "mods/kelsi.housing/page.json"
GOOD_PAGE = {"description": "d", "screenshots": [], "tags": [], "links": [], "deprecated": False}


class PathImpliesSchema(unittest.TestCase):
    def test_valid_entry_and_page_are_accepted_positive_control(self):
        v = schema.check({ENTRY: entry(pending()), PAGE: GOOD_PAGE})
        self.assertEqual(v["verdict"], "accepted")
        self.assertEqual({r["path"]: r["schema"] for r in v["results"]},
                         {ENTRY: "entry.schema.json", PAGE: "page.schema.json"})

    def test_an_entry_document_at_a_page_path_is_validated_against_the_page_schema_and_rejected(self):
        v = schema.check({PAGE: entry(pending())})
        self.assertEqual(v["verdict"], "rejected")
        self.assertEqual(v["findings"][0]["rules"], ["schema:page"])

    def test_a_page_document_at_an_entry_path_is_validated_against_the_entry_schema_and_rejected(self):
        v = schema.check({ENTRY: GOOD_PAGE})
        self.assertEqual(v["findings"][0]["rules"], ["schema:entry"])

    def test_invalid_documents_are_rejected_with_the_validator_message(self):
        bad_entry = entry(pending())
        bad_entry["owner"]["id"] = "kelsi"  # a username string: the ADR-0058 capture vector
        bad_page = dict(GOOD_PAGE, screenshots=["../../etc/passwd"])
        for path, doc in ((ENTRY, bad_entry), (PAGE, bad_page)):
            with self.subTest(path=path):
                v = schema.check({path: doc})
                self.assertEqual(v["verdict"], "rejected")
                self.assertIn("To fix:", v["findings"][0]["message"])
                self.assertIn(path, v["findings"][0]["message"])

    def test_every_published_example_validates_and_every_invalid_example_is_rejected(self):
        for kind, fname in (("entry", ENTRY), ("page", PAGE)):
            for verdict, group in (("accepted", "valid"), ("rejected", "invalid")):
                files = sorted((support.REPO / "contracts" / "examples" / kind / group).glob("*.json"))
                self.assertTrue(files)
                for f in files:
                    with self.subTest(example=f.name):
                        doc = json.loads(f.read_text())["example"]
                        self.assertEqual(schema.check({fname: doc})["verdict"], verdict)

    def test_the_attacker_four_element_entry_is_schema_rejected(self):
        v = schema.check({"mods/attacker.mod/entry.json": attacker_entry()})
        self.assertEqual(v["verdict"], "rejected")
        self.assertIn("versions[2]", v["findings"][0]["message"])

    def test_the_attacker_three_element_variant_is_schema_valid(self):
        self.assertEqual(schema.check({"mods/attacker.mod/entry.json": attacker_entry((0, 1, 3))})["verdict"],
                         "accepted")

    def test_a_published_born_element_is_schema_valid_which_is_why_append_only_exists(self):
        self.assertEqual(schema.check({ENTRY: entry(published())})["verdict"], "accepted")


class FailClosed(unittest.TestCase):
    def test_a_path_with_no_implied_schema_is_rejected(self):
        for p in ("mods/kelsi.housing/notes.json", "reserved-namespaces.json", "mods/x/entry.json"):
            with self.subTest(path=p):
                v = schema.check({p: {}})
                self.assertEqual((v["verdict"], v["findings"][0]["rules"]), ("rejected", ["no-schema"]))

    def test_raw_text_that_is_not_json_is_a_rejection_not_a_tool_error(self):
        v = schema.check({ENTRY: "{not json"})
        self.assertEqual((v["verdict"], v["findings"][0]["rules"]), ("rejected", ["json-syntax"]))

    def test_raw_text_that_is_json_is_parsed_and_validated(self):
        self.assertEqual(schema.check({ENTRY: json.dumps(entry(pending()))})["verdict"], "accepted")

    def test_a_deleted_file_has_nothing_to_validate_here(self):
        v = schema.check({ENTRY: None})
        self.assertEqual((v["verdict"], v["results"][0]["result"]), ("accepted", "deleted-not-validated"))

    def test_an_unsupported_schema_keyword_is_a_tool_error_never_a_silent_pass(self):
        with mock.patch.object(schema_check, "validate", side_effect=NotImplementedError("keyword x")):
            with self.assertRaises(report.ToolError):
                schema.check({ENTRY: entry(pending())})


if __name__ == "__main__":
    unittest.main()
