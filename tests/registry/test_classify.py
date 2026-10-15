"""classify: criterion 8 (exhaustive, fail closed), R1 path form, merge-base reserved list, positive controls."""

import json
import unittest

import support
from support import RESERVED, classify, report


def cls(paths, reserved=RESERVED):
    return classify.classify(paths, reserved)


class PositiveControls(unittest.TestCase):
    def test_entry_only_pr_is_entry_class(self):
        v = cls(["mods/kelsi.housing/entry.json"])
        self.assertEqual((v["verdict"], v["class"]), ("accepted", "entry"))

    def test_page_only_pr_is_page_only_class(self):
        v = cls(["mods/kelsi.housing/page.json"])
        self.assertEqual((v["verdict"], v["class"]), ("accepted", "page-only"))

    def test_several_pages_of_several_mods_are_still_page_only(self):
        v = cls(["mods/kelsi.housing/page.json", "mods/bob.thing/page.json"])
        self.assertEqual(v["class"], "page-only")

    def test_reserved_namespace_pr_is_reserved_class_even_for_page_json(self):
        for p in ("mods/mc.core/entry.json", "mods/test.hello-world/page.json"):
            with self.subTest(path=p):
                self.assertEqual(cls([p])["class"], "reserved-namespace")

    def test_reserved_wins_over_entry_in_a_mixed_pr(self):
        self.assertEqual(cls(["mods/kelsi.housing/entry.json", "mods/mc.core/page.json"])["class"],
                         "reserved-namespace")

    def test_names_with_dashes_underscores_digits_are_accepted(self):
        self.assertEqual(cls(["mods/k-1_x.my_mod-2/entry.json"])["verdict"], "accepted")


class MixedPrs(unittest.TestCase):
    def test_page_plus_entry_does_not_get_the_light_page_gate(self):
        v = cls(["mods/kelsi.housing/page.json", "mods/kelsi.housing/entry.json"])
        self.assertEqual(v["class"], "entry")
        self.assertNotEqual(v["class"], "page-only")

    def test_page_of_one_mod_plus_entry_of_another_is_entry_class(self):
        self.assertEqual(cls(["mods/a.b/page.json", "mods/c.d/entry.json"])["class"], "entry")


class R1PathForm(unittest.TestCase):
    BAD = [
        "mods/entry.json", "mods/a.b/c/entry.json", "mods/a.b/entry.json.bak", "mods/a.b/ENTRY.json",
        "mods/a.b/readme.md", "mods/a.b.c/entry.json", "mods/a/entry.json", "mods/.b/entry.json",
        "mods/a./entry.json", "mods/A.b/entry.json", "mods/a.B/entry.json", "mods/-a.b/entry.json",
        "mods/a.b/entry.json\n", " mods/a.b/entry.json", "mods//a.b/entry.json", "mods/a.b//entry.json",
        "mods/../a.b/entry.json", "mods/a.b/../c.d/entry.json", "mods/a b.c/entry.json",
        "mods/a.b/page.json/", "mods/", "mods/a.b/", "mods/a.b",
        "mods/а.b/entry.json",  # Cyrillic a
    ]

    def test_every_malformed_path_under_mods_is_rejected_citing_r1(self):
        for p in self.BAD:
            if not p.startswith("mods/"):
                continue
            with self.subTest(path=p):
                v = cls([p])
                self.assertEqual((v["verdict"], v["class"]), ("rejected", "other"))
                self.assertEqual(v["findings"][0]["rules"], ["R1"])
                self.assertIn("ownership.md R1", v["findings"][0]["message"])
                self.assertIn("To fix:", v["findings"][0]["message"])

    def test_malformed_paths_not_under_mods_are_rejected_not_skipped(self):
        for p in (" mods/a.b/entry.json", "Mods/a.b/entry.json", "./mods/a.b/entry.json",
                  "/mods/a.b/entry.json", "mods\\a.b\\entry.json"):
            with self.subTest(path=p):
                self.assertEqual(cls([p])["verdict"], "rejected")

    def test_one_bad_path_poisons_an_otherwise_good_pr(self):
        v = cls(["mods/kelsi.housing/entry.json", "mods/kelsi.housing/notes.txt"])
        self.assertEqual((v["verdict"], v["class"]), ("rejected", "other"))
        self.assertEqual([f["path"] for f in v["findings"]], ["mods/kelsi.housing/notes.txt"])


class FailClosed(unittest.TestCase):
    def test_paths_outside_mods_are_unrecognised_and_rejected(self):
        for p in ("README.md", "tools/registry/cli.py", ".github/workflows/ci.yml", "contracts/entry.schema.json"):
            with self.subTest(path=p):
                v = cls([p])
                self.assertEqual((v["verdict"], v["class"]), ("rejected", "other"))
                self.assertIn("To fix:", v["findings"][0]["message"])

    def test_empty_path_set_is_rejected(self):
        v = cls([])
        self.assertEqual((v["verdict"], v["class"]), ("rejected", "other"))

    def test_good_plus_outside_path_is_other_never_a_silent_pass(self):
        self.assertEqual(cls(["mods/a.b/page.json", "README.md"])["verdict"], "rejected")

    def test_every_result_has_exactly_one_known_class(self):
        known = {"entry", "page-only", "reserved-namespace", "other"}
        for paths in ([], ["README.md"], ["mods/a.b/entry.json"], ["mods/a.b/page.json"], ["mods/mc.x/entry.json"],
                      ["mods/a.b/page.json", "mods/a.b/entry.json"], ["mods/x"]):
            with self.subTest(paths=paths):
                self.assertIn(cls(paths)["class"], known)

    def test_bad_inputs_are_tool_errors_not_rejections(self):
        for paths, reserved in (("mods/a.b/entry.json", RESERVED), ([1], RESERVED), (["x"], None), (["x"], {}),
                                (["x"], {"namespaces": []})):
            with self.subTest(paths=paths, reserved=reserved):
                with self.assertRaises(report.ToolError):
                    classify.classify(paths, reserved)


class ReservedListIsMergeBaseData(unittest.TestCase):
    def test_the_list_is_what_the_caller_passes_so_the_class_follows_it(self):
        with_mc = {"namespaces": {"mc": {}}}
        without_mc = {"namespaces": {}}
        self.assertEqual(cls(["mods/mc.core/entry.json"], with_mc)["class"], "reserved-namespace")
        self.assertEqual(cls(["mods/mc.core/entry.json"], without_mc)["class"], "entry")

    def test_a_pr_editing_reserved_namespaces_json_is_rejected_and_cannot_unreserve_mc(self):
        """The PR removes mc from the list and first-publishes mc:core. The merge-base list (with mc) is
        what classify receives; the edited file is an unrecognised path, so the PR is rejected outright and
        its own copy of the list is never an input."""
        merge_base = {"namespaces": {"mc": {}, "test": {}}}
        v = cls(["reserved-namespaces.json", "mods/mc.core/entry.json"], merge_base)
        self.assertEqual((v["verdict"], v["class"]), ("rejected", "other"))
        self.assertEqual([f["path"] for f in v["findings"]], ["reserved-namespaces.json"])
        # and the mod path on its own is still reserved under the merge-base list
        self.assertEqual(cls(["mods/mc.core/entry.json"], merge_base)["class"], "reserved-namespace")

    def test_the_real_reserved_list_in_this_repo_has_mc_and_test(self):
        data = json.loads((support.REPO / "reserved-namespaces.json").read_text())
        self.assertEqual(classify.reserved_names(data), {"mc", "test"})


if __name__ == "__main__":
    unittest.main()
