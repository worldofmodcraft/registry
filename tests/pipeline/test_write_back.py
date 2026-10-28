"""Task 008c: apply_write_back, write_back_values, source_archive_url (edge E8).

Expected values are typed here or taken from 057's fixtures / the merged contract, never computed
by the functions under test. Nothing here touches the network or any key: the signature is a
placeholder string."""

import ast
import copy
import importlib.util
import json
import os
import re
import tempfile
import unittest

from helpers import REPO, TOOLS  # noqa: F401  (helpers puts tools/pipeline on sys.path)

import write_back as wb  # noqa: E402
from pipeline_errors import PipelineError  # noqa: E402

FIXTURES = os.path.join(REPO, "docs", "tasks", "057-transition-fixtures.json")
ORACLE = os.path.join(REPO, "docs", "tasks", "057-oracle.py")
SCHEMA = os.path.join(REPO, "contracts", "entry.schema.json")
NAMING = os.path.join(REPO, "contracts", "artifact-naming.md")

HOST_LITERAL = "archive.worldofmodcraft.com"
EX1 = ("mc", "hello-world", "1.0.0",
       "https://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz")
EX2 = ("a", "b", "1.0.0-rc.1+build.5",
       "https://archive.worldofmodcraft.com/a.b-1.0.0-rc.1+build.5/a.b-1.0.0-rc.1+build.5.tar.gz")

_spec = importlib.util.spec_from_file_location("wom_oracle_057", ORACLE)
oracle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(oracle)

SHA = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
SIG = "untrusted comment: placeholder\nRWQAAAAA_placeholder_signature_bytes_base64==\ntrusted comment: x\nAAAA"
KEY_ID = "E7A1B2C3D4E5F607"
BUILT_AT = "2026-10-28T10:00:00Z"
ARCHIVE = EX1[3]
OWNER = {"provider": "github", "id": 4831207, "name_at_registration": "kelsi"}
PEND = {"version": "1.0.0", "commit": "a" * 40, "source_url": "https://github.com/kelsi/housing", "status": "pending"}


def entry_with(*versions, eid="kelsi:housing"):
    return {"id": eid, "owner": dict(OWNER), "versions": [dict(v) for v in versions]}


def result_for(version="1.0.0", eid="kelsi:housing"):
    return {"id": eid, "version": version, "built_at": BUILT_AT, "tag": "x", "assets": ["x"],
            "artifact": {"source_sha256": SHA, "signature": SIG, "key_id": KEY_ID}}


def snap(*objs):
    return [json.dumps(o, sort_keys=True) for o in objs]


def generic_diff(a, b, path=""):
    """Recursive diff written here, independent of the function under test: list of (path, kind)."""
    out = []
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            p = f"{path}/{k}"
            if k not in a:
                out.append((p, "added"))
            elif k not in b:
                out.append((p, "removed"))
            else:
                out += generic_diff(a[k], b[k], p)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append((path, "length"))
        for i, (x, y) in enumerate(zip(a, b)):
            out += generic_diff(x, y, f"{path}[{i}]")
    elif a != b or type(a) is not type(b):
        out.append((path, "changed"))
    return out


def schema_validate_entry(entry):
    """Validate against entry.schema.json with the schema's own patterns (no jsonschema dependency
    is assumed): shape of a published version = exactly the nine keys, each matching its pattern."""
    s = json.load(open(SCHEMA))
    vp = s["properties"]["versions"]["items"]["properties"]
    errs = []
    if set(entry) != {"id", "owner", "versions"}:
        errs.append("top-level keys")
    if not re.fullmatch(s["properties"]["id"]["pattern"], entry["id"]):
        errs.append("id")
    for v in entry["versions"]:
        want = {"version", "commit", "source_url", "status"}
        if v["status"] == "published":
            want |= set(wb.FIVE_KEYS)
        if set(v) != want:
            errs.append(f"keys {sorted(set(v) ^ want)}")
        for k, val in v.items():
            if "pattern" in vp[k] and not re.fullmatch(vp[k]["pattern"], val):
                errs.append(k)
            if k == "status" and val not in vp[k]["enum"]:
                errs.append(k)
        if v["status"] == "published" and not v["signature"]:
            errs.append("signature empty")
    return errs


def classify(old, new):
    return oracle.classify(old, new)


def load_corpus():
    with open(FIXTURES) as f:   # re-read on every call, never cached
        return json.load(f)


def _pend_idx(old):
    return [i for i, v in enumerate(old["versions"]) if v.get("status") == "pending"]


def t1_accept_rows(rows=None):
    """Accept rows (object old/new) in which at least one element goes pending -> published.
    Selected by looking at the fixtures' data, not by asking the function."""
    out = []
    for r in rows if rows is not None else load_corpus():
        o, n = r["old"], r["new"]
        if r["expect"] != "accept" or not isinstance(o, dict) or not isinstance(n, dict):
            continue
        idx = [i for i in _pend_idx(o) if i < len(n["versions"]) and n["versions"][i].get("status") == "published"]
        if idx:
            out.append((r, idx))
    return out


def t1_reject_rows(rows=None):
    """Reject rows whose old contains a pending version and whose name marks them as T1 attempts."""
    out = []
    for r in rows if rows is not None else load_corpus():
        o = r["old"]
        if r["expect"] == "reject" and r["name"].startswith("t1-") and isinstance(o, dict) and _pend_idx(o):
            out.append(r)
    return out


def synthetic(old_entry, nv):
    """A result.json built from the fixture's NEW version element nv (never from write_back_values)."""
    art = {k: nv[k] for k in ("source_sha256", "signature", "key_id") if k in nv}
    res = {"id": old_entry["id"], "version": nv.get("version"), "artifact": art, "tag": "t", "assets": []}
    if "published_at" in nv:
        res["built_at"] = nv["published_at"]
    return res


class Ac1ExactTransition(unittest.TestCase):
    def test_ac1_transition_validates_diffs_exactly_and_oracle_accepts(self):
        old = entry_with(PEND)
        out = wb.apply_write_back(old, result_for(), ARCHIVE)
        self.assertEqual(schema_validate_entry(out), [], "(a) validates against entry.schema.json's patterns/key sets")
        self.assertEqual(schema_validate_entry(old), [])
        d = generic_diff(old, out)
        want = sorted([("/versions[0]/" + k, "added") for k in
                       ("source_archive", "source_sha256", "signature", "key_id", "published_at")]
                      + [("/versions[0]/status", "changed")])
        self.assertEqual(sorted(d), want, "(b) only the five added keys and the status change")
        self.assertEqual(out["versions"][0]["status"], "published")
        self.assertEqual(out["versions"][0]["source_sha256"], SHA)
        self.assertEqual(out["versions"][0]["published_at"], BUILT_AT)
        self.assertEqual(out["versions"][0]["source_archive"], ARCHIVE)
        verdict = classify(old, out)
        self.assertEqual(verdict[0], "accept", f"(c) oracle: {verdict}")

    def test_ac1_diff_helper_is_not_blind(self):
        # control: the independent diff really sees a changed commit and an extra key
        old = entry_with(PEND)
        out = wb.apply_write_back(old, result_for(), ARCHIVE)
        out2 = copy.deepcopy(out); out2["versions"][0]["commit"] = "b" * 40; out2["versions"][0]["x"] = 1
        self.assertIn(("/versions[0]/commit", "changed"), generic_diff(old, out2))
        self.assertIn(("/versions[0]/x", "added"), generic_diff(old, out2))
        self.assertEqual(classify(old, out2)[0], "reject", "control: oracle rejects the tampered output")

    def test_ac1_only_the_matching_version_changes_and_commit_is_never_taken_from_result(self):
        other = dict(PEND, version="1.1.0", commit="c" * 40)
        old = entry_with(dict(PEND, status="published", source_archive=ARCHIVE, source_sha256=SHA, signature=SIG,
                              key_id=KEY_ID, published_at="2026-01-01T00:00:00Z", version="0.9.0"), PEND, other)
        res = result_for()
        res["commit"] = "d" * 40
        res["artifact"]["commit"] = "e" * 40
        res["source_url"] = "https://evil.example/x"
        out = wb.apply_write_back(old, res, ARCHIVE)
        self.assertEqual(out["versions"][1]["commit"], "a" * 40)
        self.assertEqual(out["versions"][1]["source_url"], "https://github.com/kelsi/housing")
        self.assertEqual(out["versions"][0], old["versions"][0])
        self.assertEqual(out["versions"][2], old["versions"][2])
        self.assertEqual(sorted(p for p, _ in generic_diff(old, out)),
                         sorted([f"/versions[1]/{k}" for k in wb.FIVE_KEYS] + ["/versions[1]/status"]))
        self.assertEqual(classify(old, out)[0], "accept")

    def test_ac1_write_back_values_has_exactly_the_five_keys(self):
        v = wb.write_back_values(result_for(), ARCHIVE)
        self.assertEqual(v, {"source_archive": ARCHIVE, "source_sha256": SHA, "signature": SIG,
                             "key_id": KEY_ID, "published_at": BUILT_AT})


class Ac2Refusals(unittest.TestCase):
    def refused(self, reason, entry, result, archive=ARCHIVE):
        before = snap(entry, result)
        with self.assertRaises(wb.WriteBackRefused) as cm:
            wb.apply_write_back(entry, result, archive)
        self.assertEqual(cm.exception.reason, reason)
        self.assertIsInstance(cm.exception, PipelineError)
        self.assertEqual(snap(entry, result), before, "inputs byte-identical after a refusal")

    def test_ac2_absent_version(self):
        self.refused("version-absent", entry_with(dict(PEND, version="2.0.0")), result_for())

    def test_ac2_result_for_another_version(self):
        self.refused("version-absent", entry_with(PEND, dict(PEND, version="1.1.0")), result_for("1.2.0"))

    def test_ac2_duplicate_matching_version(self):
        self.refused("version-duplicate", entry_with(PEND, PEND), result_for())

    def test_ac2_status_published_removed_rejected_each_refused(self):
        pub = dict(PEND, status="published", source_archive=ARCHIVE, source_sha256=SHA, signature=SIG,
                   key_id=KEY_ID, published_at="2026-01-01T00:00:00Z")
        rem = dict(pub, status="removed", reason="takedown")
        rej = dict(PEND, status="rejected", reason="bad", build_log_url="https://example.org/log")
        for v in (pub, rem, rej):
            with self.subTest(status=v["status"]):
                self.refused("not-pending", entry_with(v), result_for())

    def test_ac2_result_missing_each_needed_field(self):
        for path in (("artifact", "signature"), ("artifact", "key_id"), ("artifact", "source_sha256"), ("built_at",)):
            r = result_for()
            d = r
            for p in path[:-1]:
                d = d[p]
            del d[path[-1]]
            with self.subTest(missing=path):
                self.refused("result-missing-field", entry_with(PEND), r)

    def test_ac2_result_without_artifact_object(self):
        r = result_for(); del r["artifact"]
        self.refused("result-missing-field", entry_with(PEND), r)

    def test_ac2_extra_key_guard_tested_directly(self):
        good = wb.write_back_values(result_for(), ARCHIVE)
        six = dict(good, commit="d" * 40)
        orig = wb.write_back_values
        wb.write_back_values = lambda result, source_archive: dict(six)
        try:
            self.refused("key-set", entry_with(PEND), result_for())
        finally:
            wb.write_back_values = orig
        # and a four-key return is refused by the same guard
        wb.write_back_values = lambda result, source_archive: {k: good[k] for k in list(good)[:4]}
        try:
            self.refused("key-set", entry_with(PEND), result_for())
        finally:
            wb.write_back_values = orig
        self.assertIs(wb.write_back_values, orig)

    def test_ac2_bad_sha256_length(self):
        for bad in (SHA[:-1], SHA + "0", SHA.upper(), ""):
            r = result_for(); r["artifact"]["source_sha256"] = bad
            with self.subTest(sha=bad):
                self.refused("bad-value", entry_with(PEND), r)

    def test_ac2_http_source_archive(self):
        self.refused("bad-value", entry_with(PEND), result_for(), "http://archive.worldofmodcraft.com/x/x.tar.gz")
        self.refused("bad-value", entry_with(PEND), result_for(), "https://has space")
        self.refused("bad-value", entry_with(PEND), result_for(), None)

    def test_ac2_published_at_not_rfc3339(self):
        for bad in ("2026-10-28", "2026-10-28 10:00:00Z", "yesterday", "2026-10-28T10:00:00", ""):
            r = result_for(); r["built_at"] = bad
            with self.subTest(built_at=bad):
                self.refused("bad-value", entry_with(PEND), r)

    def test_ac2_empty_signature_and_bad_key_id(self):
        r = result_for(); r["artifact"]["signature"] = ""
        self.refused("bad-value", entry_with(PEND), r)
        for bad in ("e7a1b2c3d4e5f607", KEY_ID[:-1], ""):
            r = result_for(); r["artifact"]["key_id"] = bad
            with self.subTest(key_id=bad):
                self.refused("bad-value", entry_with(PEND), r)

    def test_ac2_result_from_another_mod(self):
        self.refused("id-mismatch", entry_with(PEND), result_for(eid="other:mod"))

    def test_ac2_malformed_inputs(self):
        self.refused("entry-malformed", {"id": "kelsi:housing"}, result_for())
        self.refused("result-malformed", entry_with(PEND), ["not", "an", "object"])

    def test_ac2_no_mutation_on_success(self):
        old, res = entry_with(PEND), result_for()
        before = snap(old, res)
        out = wb.apply_write_back(old, res, ARCHIVE)
        self.assertEqual(snap(old, res), before)
        out["versions"][0]["status"] = "scribble"; out["owner"]["id"] = 1
        self.assertEqual(snap(old, res), before, "output shares no structure with the input")

    def test_ac2_source_archive_url_refusals(self):
        for args, reason in ((("mc", "hello", "1.0"), "bad-version"), (("mc", "hello", "v1.0.0"), "bad-version"),
                             (("mc", "hello", "1.0.0 "), "bad-version"), (("mc", "hello", "1.0.0\n"), "bad-version"),
                             (("mc", "he llo", "1.0.0"), "bad-id"), (("mc", "Hello", "1.0.0"), "bad-id"),
                             (("mc", "", "1.0.0"), "bad-id"), (("mc", "a/b", "1.0.0"), "bad-id"),
                             (("mc", "a:b", "1.0.0"), "bad-id"),
                             (("con", "hello", "1.0.0"), "reserved-namespace"), (("nul", "x", "1.0.0"), "reserved-namespace"),
                             (("com1", "x", "1.0.0"), "reserved-namespace"), (("lpt9", "x", "1.0.0"), "reserved-namespace")):
            with self.subTest(args=args):
                with self.assertRaises(wb.WriteBackRefused) as cm:
                    wb.source_archive_url(*args)
                self.assertEqual(cm.exception.reason, reason)


class Ac3SharedCorpus(unittest.TestCase):
    def test_ac3_selection_is_not_vacuous(self):
        acc, rej = t1_accept_rows(), t1_reject_rows()
        self.assertGreater(len(acc), 0)
        self.assertGreater(len(rej), 0)
        names = {r["name"] for r, _ in acc}
        self.assertIn("t1-exact", names)
        self.assertIn("t1-two-elements-two-transitions", names)

    def test_ac3_accept_rows_reproduced_per_t1_element(self):
        took_multi = []
        for row, idx in t1_accept_rows():
            old, new = row["old"], row["new"]
            cur = copy.deepcopy(old)
            for i in idx:   # once per T1 element, in order, each call on the previous output
                nv = new["versions"][i]
                res = synthetic(old, nv)
                cur = wb.apply_write_back(cur, res, nv["source_archive"])
                self.assertEqual(cur["versions"][i], nv, f"{row['name']}: element {i} reproduced")
            if len(idx) > 1 or len(new["versions"]) > 1 or old != cur:
                took_multi.append(row["name"])
            # every element that is not a T1 element is untouched by the T1 calls
            for j, v in enumerate(old["versions"]):
                if j not in idx:
                    self.assertEqual(cur["versions"][j], v, row["name"])
            if row["name"] == "t1-exact":
                self.assertEqual(cur, new)
                self.assertEqual(classify(old, cur)[0], "accept")
        self.assertIn("t1-two-elements-two-transitions", took_multi)
        self.assertIn("t1-and-t3-different-elements", took_multi)

    def test_ac3_reject_rows_are_refused_or_not_produced(self):
        refused, not_produced = [], []
        for row in t1_reject_rows():
            old, new = row["old"], row["new"]
            cands = [i for i in _pend_idx(old) if isinstance(new, dict) and i < len(new["versions"])
                     and new["versions"][i].get("status") == "published"]
            self.assertTrue(cands, f"{row['name']}: no pending->published element to try (selection is wrong)")
            for i in cands:
                nv = new["versions"][i]
                res = synthetic(old, nv)
                try:
                    out = wb.apply_write_back(copy.deepcopy(old), res, nv.get("source_archive"))
                except wb.WriteBackRefused:
                    refused.append(row["name"])
                    continue
                self.assertNotEqual(out, new, f"{row['name']}: the function reproduced a fixture 057 rejects")
                self.assertEqual(classify(old, out)[0], "accept", f"{row['name']}: what it did produce is itself legal")
                not_produced.append(row["name"])
        self.assertTrue(refused and not_produced, (refused, not_produced))
        self.assertTrue({"t1-missing-signature", "t1-source-archive-http", "t1-sha256-wrong-length",
                         "t1-published-at-not-rfc3339"} <= set(refused), refused)
        self.assertTrue({"t1-extra-changed-field-commit", "t1-plus-owner-change", "t1-extra-key"} <= set(not_produced), not_produced)


class Ac5SourceArchiveUrl(unittest.TestCase):
    URL_RE = re.compile(r"^https://archive\.worldofmodcraft\.com/[0-9A-Za-z._+-]+/[0-9A-Za-z._+-]+\.tar\.gz$")

    def test_ac5_worked_examples_byte_for_byte(self):
        for ns, nm, v, url in (EX1, EX2):
            self.assertEqual(wb.source_archive_url(ns, nm, v), url)

    def test_ac5_host_constant_and_contract_agree(self):
        self.assertEqual(wb.ARCHIVE_HOST, HOST_LITERAL)
        text = open(NAMING, encoding="utf-8").read()
        self.assertIn(f'"https://{HOST_LITERAL}/" + tag + "/" + tag + ".tar.gz"', text)
        self.assertIn(EX1[3], text)
        self.assertIn(EX2[3], text)

    def test_ac5_shape_and_forbidden_characters(self):
        vers = ["0.0.1", "1.0.0", "10.20.30", "1.0.0-rc.1", "1.0.0-RC.1", "1.0.0+b", "1.0.0-a.b-c+x.y-z", "1.2.3-0.3.7"]
        for ns in ("a", "mc", "k_1", "x-y", "9z"):
            for nm in ("b", "hello-world", "n_1", "7"):
                for v in vers:
                    u = wb.source_archive_url(ns, nm, v)
                    self.assertRegex(u, self.URL_RE)
                    rest = u[len("https://"):]
                    for bad in ("%", "..", "//", "?", "#"):
                        self.assertNotIn(bad, rest, u)
                    tag = f"{ns}.{nm}-{v}"
                    self.assertTrue(u.endswith(f"/{tag}/{tag}.tar.gz"))

    def test_ac5_injective_over_a_generated_set_and_reserved_names_refused(self):
        nss = ["a", "b", "mc", "ab", "a-b", "a_b", "x1", "con", "prn", "aux", "nul", "com0", "com9", "lpt0", "lpt9"]
        nms = ["b", "a", "b-1", "b-1-2", "hello", "hello-1", "a-b", "x", "1"]
        vers = ["1.0.0", "1.0.1", "1.0.0-1", "1.0.0-1.2", "1.0.0-rc.1", "1.0.0+1", "1.0.0-1+1", "2.0.0", "1-1.0.0" ]
        seen, built, refused = {}, 0, 0
        for ns in nss:
            for nm in nms:
                for v in vers:
                    try:
                        u = wb.source_archive_url(ns, nm, v)
                    except wb.WriteBackRefused as e:
                        self.assertIn(e.reason, ("reserved-namespace", "bad-version"))
                        if v != "1-1.0.0":   # the one invalid semver in the set
                            self.assertEqual(e.reason, "reserved-namespace", (ns, nm, v))
                        refused += 1
                        continue
                    built += 1
                    self.assertNotIn(u, seen, f"{(ns, nm, v)} collides with {seen.get(u)}")
                    seen[u] = (ns, nm, v)
        self.assertGreater(built, 200)
        self.assertGreater(refused, 50)
        for ns in ("con", "prn", "aux", "nul", "com0", "com9", "lpt0", "lpt9"):
            with self.assertRaises(wb.WriteBackRefused) as cm:
                wb.source_archive_url(ns, "x", "1.0.0")
            self.assertEqual(cm.exception.reason, "reserved-namespace")

    def test_ac5_no_percent_encoding_of_plus(self):
        u = wb.source_archive_url("a", "b", "1.0.0+m")
        self.assertIn("+", u)
        self.assertNotIn("%2B", u.upper())

    def test_ac5_build_metadata_still_yields_a_url(self):
        self.assertEqual(wb.source_archive_url(*EX2[:3]), EX2[3])


def find_literal(root, needle, exclude=()):
    hits = []
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d != "__pycache__"]
        for f in fn:
            p = os.path.join(dp, f)
            if p in exclude:
                continue
            try:
                if needle in open(p, encoding="utf-8").read():
                    hits.append(p)
            except UnicodeDecodeError:
                continue
    return hits


class Ac5HostSingleSource(unittest.TestCase):
    def test_ac5_host_is_written_only_in_write_back_py_under_tools(self):
        hits = find_literal(os.path.join(REPO, "tools"), HOST_LITERAL)
        self.assertEqual(hits, [os.path.join(TOOLS, "write_back.py")])
        src = open(os.path.join(TOOLS, "write_back.py")).read()
        self.assertEqual(src.count(HOST_LITERAL), 1, "one named constant, one occurrence")

    def test_ac5_positive_control_the_search_finds_a_planted_hardcode(self):
        with tempfile.TemporaryDirectory(prefix="wom008c-") as td:
            open(os.path.join(td, "other.py"), "w").write(f'URL = "https://{HOST_LITERAL}/x"\n')
            open(os.path.join(td, "clean.py"), "w").write("x = 1\n")
            self.assertEqual(find_literal(td, HOST_LITERAL), [os.path.join(td, "other.py")])


FORBIDDEN_IMPORTS = {"subprocess", "socket", "ssl", "urllib", "http", "requests", "httpx", "aiohttp", "ftplib",
                     "smtplib", "telnetlib", "asyncio", "multiprocessing", "ctypes", "os.system"}


def forbidden_imports(source):
    found = set()
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Import):
            found |= {a.name.split(".")[0] for a in node.names}
        elif isinstance(node, ast.ImportFrom) and node.module:
            found.add(node.module.split(".")[0])
    return found & FORBIDDEN_IMPORTS


class Ac6NoSecretNoNetwork(unittest.TestCase):
    CANARY = "CANARY-8c2e51-do-not-leak"

    def test_ac6_module_imports_no_subprocess_or_network_library(self):
        self.assertEqual(forbidden_imports(open(os.path.join(TOOLS, "write_back.py")).read()), set())
        src = open(os.path.join(TOOLS, "write_back.py")).read()
        self.assertNotIn("os.system", src)
        self.assertNotIn("os.popen", src)

    def test_ac6_positive_control_forbidden_import_is_detected(self):
        self.assertEqual(forbidden_imports("import subprocess\n"), {"subprocess"})
        self.assertEqual(forbidden_imports("from urllib.request import urlopen\n"), {"urllib"})
        self.assertEqual(forbidden_imports("import os, json\n"), set())

    def test_ac6_canary_in_env_and_in_result_never_reaches_output_or_errors(self):
        os.environ["MINISIGN_SECRET_KEY"] = self.CANARY
        os.environ["WOM_SIGNING_KEY"] = self.CANARY
        try:
            res = result_for()
            res["secret"] = self.CANARY
            res["artifact"]["secret_key"] = self.CANARY
            res["log"] = f"key: {self.CANARY}"
            self.assertIn(self.CANARY, json.dumps(res), "control: the canary is in the input")
            vals = wb.write_back_values(res, ARCHIVE)
            out = wb.apply_write_back(entry_with(PEND), res, ARCHIVE)
            blob = json.dumps(vals) + json.dumps(out)
            self.assertNotIn(self.CANARY, blob)
            self.assertEqual(set(vals), set(wb.FIVE_KEYS))
            # the failure path does not echo unrelated result content either
            bad = result_for(); bad["artifact"]["source_sha256"] = "x"; bad["secret"] = self.CANARY
            with self.assertRaises(wb.WriteBackRefused) as cm:
                wb.apply_write_back(entry_with(PEND), bad, ARCHIVE)
            self.assertNotIn(self.CANARY, str(cm.exception))
        finally:
            os.environ.pop("MINISIGN_SECRET_KEY", None)
            os.environ.pop("WOM_SIGNING_KEY", None)


if __name__ == "__main__":
    unittest.main()
