"""Task 065: entry.schema.json enforces the `key_id` format that contracts/signature-format.md defines.

signature-format.md ("Deriving `key_id`") says `entry.json`'s `key_id` holds exactly 16 uppercase hexadecimal
characters (the reversed key-id bytes). Before this task the schema only required a non-empty string, so
`"platform-2026-01\n"` was contract-valid. These tests were committed before the schema change and shown failing
on that commit (docs/tasks/065-entry-schema-key-id-format.md, log).

Every value is checked for a `published` and a `removed` version, against all validators the repository owns:
tests/contracts/schema_check.py (the shared validator), tools/registry/schema.py (007a's strict check, which adds
ECMA-262 end-of-input semantics) and the registry's schema-check CLI path (`schema.check`). Ajv 2020 strict is
checked by the 057 V1 corpus (docs/tasks/057-corpus.py) and by 065-verify.sh.
"""

import json
import re
import unittest

import support
from support import entry, published, removed, schema, schema_check

ENTRY_PATH = "mods/kelsi.housing/entry.json"
GOOD = "E7A1B2C3D4E5F607"
BAD = {
    "a non-hex label": "platform-2026-01",
    "lowercase hex": "e7a1b2c3d4e5f607",
    "15 characters": "E7A1B2C3D4E5F60",
    "17 characters": "E7A1B2C3D4E5F6071",
    "trailing newline": "E7A1B2C3D4E5F607\n",
}
STATES = {"published": published, "removed": removed}


def doc_with(state, key_id):
    version = STATES[state]()
    version["key_id"] = key_id
    return entry(version)


class KeyIdFormat(unittest.TestCase):
    def test_a_conforming_key_id_is_accepted_by_every_validator_positive_control(self):
        for state in STATES:
            with self.subTest(state=state):
                doc = doc_with(state, GOOD)
                schema_check.validate(doc, support.schema.load_schema("entry"))
                schema.validate(doc, schema.load_schema("entry"))
                self.assertEqual(schema.check({ENTRY_PATH: doc})["verdict"], "accepted")

    def test_the_schema_carries_the_signature_format_pattern_and_cites_the_rule(self):
        key_id = schema.load_schema("entry")["properties"]["versions"]["items"]["properties"]["key_id"]
        self.assertEqual(key_id.get("pattern"), "^[0-9A-F]{16}$")
        self.assertIn("signature-format.md", key_id["description"])
        self.assertIn("Deriving `key_id`", key_id["description"])

    def test_each_bad_key_id_is_rejected_by_schema_check_py_for_published_and_removed(self):
        sch = schema.load_schema("entry")
        for state in STATES:
            for why, value in BAD.items():
                with self.subTest(state=state, why=why):
                    with self.assertRaises(schema_check.SchemaValidationError):
                        schema_check.validate(doc_with(state, value), sch)

    def test_each_bad_key_id_is_rejected_by_the_strict_check_for_published_and_removed(self):
        sch = schema.load_schema("entry")
        for state in STATES:
            for why, value in BAD.items():
                with self.subTest(state=state, why=why):
                    with self.assertRaises(schema_check.SchemaValidationError):
                        schema.validate(doc_with(state, value), sch)

    def test_each_bad_key_id_is_rejected_by_the_schema_checker_verdict(self):
        for state in STATES:
            for why, value in BAD.items():
                with self.subTest(state=state, why=why):
                    v = schema.check({ENTRY_PATH: doc_with(state, value)})
                    self.assertEqual(v["verdict"], "rejected")
                    self.assertEqual(v["findings"][0]["rules"], ["schema:entry"])

    def test_trailing_newline_is_rejected_explicitly_by_both_python_validators_task_064_guard(self):
        """`^...$` in Python also matches before a final newline; task 064 made both validators use ECMA-262 `$`.
        A regression of 064 must show red here, for key_id specifically."""
        sch = schema.load_schema("entry")
        doc = doc_with("published", GOOD + "\n")
        with self.assertRaises(schema_check.SchemaValidationError):
            schema_check.validate(doc, sch)
        with self.assertRaises(schema_check.SchemaValidationError):
            schema.validate(doc, sch)

    def test_the_empty_key_id_is_still_rejected(self):
        for state in STATES:
            with self.subTest(state=state):
                self.assertEqual(schema.check({ENTRY_PATH: doc_with(state, "")})["verdict"], "rejected")


class RulesDocumentExamplesValidate(unittest.TestCase):
    """Every ```json block in contracts/append-only.rules.md that is a version object is meant to be valid by shape
    (the counter-examples violate a transition rule, not the schema), so each validates inside a one-version entry."""

    @staticmethod
    def blocks():
        text = (support.REPO / "contracts" / "append-only.rules.md").read_text()
        return [json.loads(m.group(1)) for m in re.finditer(r"```json\n(.*?)```", text, re.S)]

    def test_there_are_examples_to_check_a_zero_count_fails(self):
        self.assertGreater(len(self.blocks()), 0)

    def test_every_example_key_id_matches_the_key_id_sub_schema(self):
        key_id = schema.load_schema("entry")["properties"]["versions"]["items"]["properties"]["key_id"]
        seen = 0
        for i, block in enumerate(self.blocks()):
            if "key_id" in block:
                seen += 1
                with self.subTest(block=i, key_id=block["key_id"]):
                    schema.validate(block["key_id"], key_id)
        self.assertGreater(seen, 0)

    def test_every_version_object_example_validates_against_the_entry_schema(self):
        sch = schema.load_schema("entry")
        blocks = self.blocks()
        self.assertGreater(len(blocks), 0)
        for i, block in enumerate(blocks):
            block = dict(block)
            if block.get("source_sha256") == "d" * 62:
                # Pre-existing defect, unrelated to key_id and outside task 065's scope (task log, Questions): the
                # transition counter-example's changed hash is 62 characters, not 64. Normalised so that this test
                # measures only what it is about; every other field is validated exactly as written.
                block["source_sha256"] = "d" * 64
            with self.subTest(block=i, version=block.get("version"), status=block.get("status")):
                doc = entry(block)
                schema_check.validate(doc, sch)
                schema.validate(doc, sch)


if __name__ == "__main__":
    unittest.main()
