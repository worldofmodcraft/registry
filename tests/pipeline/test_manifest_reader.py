"""AC5: the restricted static reader. Hostile inputs beside positive controls."""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools", "validation"))
import manifest as m  # noqa: E402


class ManifestReader(unittest.TestCase):
    def rule_of(self, src: str) -> str:
        with self.assertRaises(m.ManifestError) as cm:
            m.read_manifest(src.encode())
        return cm.exception.rule

    # --- positive controls -------------------------------------------------
    def test_ac5_accepts_literal_table_with_comments_and_nested_tables(self):
        src = (
            "-- line comment\n--[[ block\ncomment ]]\n--[==[ level-2 ]==]\n"
            'return {\n  id = "test:hello", ["name"] = "He\\"llo\\n", version = \'1.0.0\',\n'
            '  api_version = "1", license = [[MIT]], source = "https://e.invalid/x.git", type = "mod",\n'
            '  description = "d", tags = { "a", "b", }, screenshots = {}, ai_assisted = false;\n'
            '  depends = { { id = "mc:core", version = ">=1.0" }, n = -3, f = 1.5e3 },\n'
            "}\n"
        )
        out = m.read_manifest(src.encode())
        self.assertEqual(out["id"], "test:hello")
        self.assertEqual(out["name"], 'He"llo\n')
        self.assertEqual(out["license"], "MIT")
        self.assertEqual(out["tags"], ["a", "b"])
        self.assertEqual(out["screenshots"], [])
        self.assertIs(out["ai_assisted"], False)

    def test_ac5_kernel_only_keys_are_accepted_and_ignored(self):
        out = m.read_manifest(b'return { id="a:b", depends={ {"x"} }, permissions={ fs=true }, server=nil, data_version=3 }')
        self.assertEqual(out, {"id": "a:b"})

    # --- hostile inputs: each named ----------------------------------------
    def test_ac5_rejects_function_call(self):
        self.assertEqual(self.rule_of('return { id = tostring("x") }'), "function-call")

    def test_ac5_rejects_call_with_string_argument_sugar(self):
        self.assertEqual(self.rule_of('return { id = f"x" }'), "function-call")

    def test_ac5_rejects_call_with_table_argument_sugar(self):
        self.assertEqual(self.rule_of('return { id = f{1} }'), "function-call")

    def test_ac5_rejects_method_or_field_call(self):
        self.assertEqual(self.rule_of('return { id = ("x"):rep(3) }'), "function-call")
        self.assertEqual(self.rule_of('return { id = string.rep("a", 3) }'), "function-call")

    def test_ac5_rejects_string_concatenation(self):
        self.assertEqual(self.rule_of('return { id = "a" .. "b" }'), "concatenation")

    def test_ac5_rejects_require(self):
        self.assertEqual(self.rule_of('require("os")\nreturn {}'), "forbidden-call")
        self.assertEqual(self.rule_of('return { id = require("os") }'), "forbidden-call")

    def test_ac5_rejects_dofile(self):
        self.assertEqual(self.rule_of('dofile("/etc/passwd")\nreturn {}'), "forbidden-call")
        self.assertEqual(self.rule_of('return { id = dofile("x") }'), "forbidden-call")

    def test_ac5_rejects_unterminated_string(self):
        self.assertEqual(self.rule_of('return { id = "abc }'), "unterminated-string")
        self.assertEqual(self.rule_of('return { id = [[abc }'), "unterminated-string")

    def test_ac5_rejects_file_that_does_not_return_a_table(self):
        self.assertEqual(self.rule_of('local t = { id = "a:b" }\nreturn t'), "no-return")
        self.assertEqual(self.rule_of('return "just a string"'), "not-a-table")
        self.assertEqual(self.rule_of('x = 1'), "no-return")
        self.assertEqual(self.rule_of(''), "no-return")

    def test_ac5_rejects_bare_identifier_and_operators_and_trailing_code(self):
        self.assertEqual(self.rule_of('return { id = foo }'), "variable")
        self.assertEqual(self.rule_of('return { n = 1 + 2 }'), "operator")
        self.assertEqual(self.rule_of('return {} os.execute("x")'), "trailing-content")

    def test_ac5_rejects_duplicate_keys_and_unterminated_table_and_bad_utf8(self):
        self.assertEqual(self.rule_of('return { id = "a", id = "b" }'), "duplicate-key")
        self.assertEqual(self.rule_of('return { a = { b = 1 }'), "unterminated-table")
        with self.assertRaises(m.ManifestError) as cm:
            m.read_manifest(b'return { id = "\xff" }')
        self.assertEqual(cm.exception.rule, "not-utf8")

    def test_ac5_comment_cannot_hide_code(self):
        # a call after a comment marker is a comment; a call BEFORE one is still a call
        self.assertEqual(m.read_manifest(b'return { id = "a:b" } -- os.execute("x")'), {"id": "a:b"})
        self.assertEqual(self.rule_of('return { id = f("x") --[[ ]] }'), "function-call")


if __name__ == "__main__":
    unittest.main()
