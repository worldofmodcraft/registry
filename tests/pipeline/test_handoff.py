"""Task 008b-2: `--no-sign`, `sign_built.py` and the build-result handoff (`handoff.py`).

Everything is offline: keys are throwaway (helpers.make_keypair), repositories are local, nothing reads a
real credential. Criteria 16 (a)-(d) and 26 (b)-(e) of docs/tasks/008b2-pipeline-build-sign.md."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tarfile
import unittest
import warnings

from helpers import (Base, CLI, TOOLS, good_files, make_keypair, make_repo, sha256sum, tar_gz, clean_tar_entries,
                     vobj, write_entry)

warnings.simplefilter("ignore", ResourceWarning)   # the tests read small files inline

import archive
import handoff
import sign_built
from pipeline_errors import PipelineError

SIGN_CLI = os.path.join(TOOLS, "sign_built.py")
HANDOFF_CLI = os.path.join(TOOLS, "handoff.py")
TAG = "test.hello-1.0.0"
VID = "test.hello@1.0.0"
GOOD_REASON_PREFIX = "[manifest/license-not-osi]: "


def flat(obj, prefix=""):
    out = {}
    for k, v in obj.items():
        if isinstance(v, dict):
            out.update(flat(v, prefix + k + "."))
        else:
            out[prefix + k] = v
    return out


class NoSignBase(Base):
    def setUp(self):
        warnings.simplefilter("ignore", ResourceWarning)   # the tests read small files inline

    def nosign(self, repo, commit, mod_id="test:hello", version="1.0.0", extra=(), allow=True):
        entry = write_entry(os.path.join(self.fresh("e"), "entry.json"), mod_id, [vobj(version, commit, repo)])
        out = os.path.join(self.fresh("outparent"), "out")
        work = self.fresh("work")
        argv = [sys.executable, CLI, "--entry", entry, "--version", version, "--workdir", work, "--out", out, "--no-sign"]
        if allow:
            argv.append("--allow-local-source")
        argv += list(extra)
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
        r = subprocess.run(argv, capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL, timeout=300)
        r.out_dir, r.work_dir, r.entry = out, work, entry
        return r

    def leg(self, repo, commit, version="1.0.0", mod_id="test:hello", **kw):
        """What the workflow's build leg does: build --no-sign with stderr captured outside --out, then finish_build."""
        r = self.nosign(repo, commit, mod_id=mod_id, version=version, **kw)
        errfile = os.path.join(self.fresh("err"), "build.stderr")
        with open(errfile, "w") as f:
            f.write(r.stderr)
        tag = f"{mod_id.replace(':', '.')}-{version}"
        outcome = handoff.finish_build(r.out_dir, errfile, f"{mod_id.replace(':', '.')}@{version}", tag, r.returncode)
        return r, outcome

    def oneshot(self, repo, commit):
        return self.build_local(repo, commit)


class NoSignTests(NoSignBase):
    def test_no_sign_outputs_and_result_fields(self):
        repo, c = make_repo(self.tmp, "ns1", good_files())
        r = self.nosign(repo, c)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(sorted(os.listdir(r.out_dir)), ["build.log", "result.json", f"{TAG}.tar.gz"])
        res = json.load(open(os.path.join(r.out_dir, "result.json")))
        self.assertIs(res["signed"], False)
        self.assertEqual(set(res["artifact"]), {"source_sha256"})
        self.assertEqual(res["artifact"]["source_sha256"], sha256sum(os.path.join(r.out_dir, f"{TAG}.tar.gz")))

    def test_result_json_differs_from_oneshot_by_exactly_the_documented_keys(self):
        repo, c = make_repo(self.tmp, "ns2", good_files())
        a = self.nosign(repo, c)
        b = self.oneshot(repo, c)
        self.assertEqual((a.returncode, b.returncode), (0, 0))
        fa = flat(json.load(open(os.path.join(a.out_dir, "result.json"))))
        fb = flat(json.load(open(os.path.join(b.out_dir, "result.json"))))
        self.assertEqual(set(fa) ^ set(fb), {"signed", "artifact.signature", "artifact.key_id"})
        for k in set(fa) & set(fb):
            if k != "built_at":
                self.assertEqual(fa[k], fb[k], k)
        self.assertNotIn("signed", fb)   # the one-shot mode is untouched

    def test_no_sign_with_key_or_pubkey_is_refused_before_any_clone(self):
        repo, c = make_repo(self.tmp, "ns3", good_files())
        for flag, val in (("--key", self.key), ("--pubkey", self.pub)):
            r = self.nosign(repo, c, extra=(flag, val))
            self.assertEqual(r.returncode, 2, (flag, r.stderr))
            self.assertIn("--no-sign", r.stderr)
            self.assertFalse(os.path.exists(r.out_dir), "nothing may be created")
            self.assertEqual(os.listdir(r.work_dir), [], "no clone may have started")

    def test_without_no_sign_key_and_pubkey_stay_required(self):
        repo, c = make_repo(self.tmp, "ns4", good_files())
        r = self.build_local(repo, c, drop=("--key", self.key, "--pubkey", self.pub))
        self.assertEqual(r.returncode, 2)
        self.assertIn("required unless --no-sign", r.stderr)


class SignBuiltTests(NoSignBase):
    def built(self, name):
        repo, c = make_repo(self.tmp, name, good_files())
        r = self.nosign(repo, c)
        self.assertEqual(r.returncode, 0, r.stderr)
        return repo, c, r.out_dir

    def sign(self, d, key=None, pub=None, limits=None, out=None):
        out = out or os.path.join(self.fresh("signout"), "signed")
        res = sign_built.sign_built(os.path.join(d, f"{TAG}.tar.gz"), os.path.join(d, "result.json"),
                                    key or self.key, pub or self.pub, out, limits)
        return res, out

    def copy_dir(self, d):
        import shutil
        dst = os.path.join(self.fresh("cp"), "b")
        shutil.copytree(d, dst)
        return dst

    def test_a_equivalent_to_the_oneshot_build(self):
        repo, c, d = self.built("sb1")
        one = self.oneshot(repo, c)
        self.assertEqual(one.returncode, 0, one.stderr)
        res, out = self.sign(d)
        self.assertEqual(sorted(os.listdir(out)), ["result.json", f"{TAG}.tar.gz", f"{TAG}.tar.gz.minisig"])
        for n in (f"{TAG}.tar.gz", f"{TAG}.tar.gz.minisig"):
            self.assertEqual(open(os.path.join(out, n), "rb").read(), open(os.path.join(one.out_dir, n), "rb").read(), n)
        a = json.load(open(os.path.join(out, "result.json")))
        b = json.load(open(os.path.join(one.out_dir, "result.json")))
        for x in (a, b):
            x.pop("built_at")
        self.assertIs(a.pop("signed"), True)
        self.assertEqual(a, b)

    def test_c_one_byte_changed_is_refused_and_nothing_is_signed(self):
        _, _, d = self.built("sb2")
        t = os.path.join(d, f"{TAG}.tar.gz")
        data = bytearray(open(t, "rb").read())
        data[len(data) // 2] ^= 0x01
        open(t, "wb").write(bytes(data))
        out = os.path.join(self.fresh("so"), "signed")
        with self.assertRaises(sign_built.SignRefused):
            self.sign(d, out=out)
        self.assertFalse(os.path.exists(out))

    def test_c_valid_gzip_with_changed_content_is_a_sha_mismatch(self):
        _, _, d = self.built("sb3")
        t = os.path.join(d, f"{TAG}.tar.gz")
        tar_gz(t, clean_tar_entries(extra=[{"name": "src/extra.txt", "data": b"extra"}]))   # an extra entry, sha not updated
        with self.assertRaises(sign_built.SignRefused) as cm:
            self.sign(d)
        self.assertEqual(cm.exception.rule, "tarball/sha-mismatch")

    def test_c_extra_hostile_entry_with_matching_sha_is_refused_by_the_entry_rules(self):
        _, _, d = self.built("sb4")
        t = os.path.join(d, f"{TAG}.tar.gz")
        tar_gz(t, clean_tar_entries(extra=[{"name": "src/../../evil", "data": b"x"}]))
        res = json.load(open(os.path.join(d, "result.json")))
        res["artifact"]["source_sha256"] = sha256sum(t)
        json.dump(res, open(os.path.join(d, "result.json"), "w"))
        with self.assertRaises(sign_built.SignRefused) as cm:
            self.sign(d)
        self.assertTrue(cm.exception.rule.startswith("tarball/"), cm.exception.rule)
        self.assertNotEqual(cm.exception.rule, "tarball/sha-mismatch", "the entry rules, not the hash, must catch this")

    def test_c_size_over_limit_is_refused(self):
        _, _, d = self.built("sb5")
        with self.assertRaises(sign_built.SignRefused) as cm:
            self.sign(d, limits=archive.Limits(max_compressed=10))
        self.assertEqual(cm.exception.rule, "tarball/compressed-size")
        with self.assertRaises(sign_built.SignRefused) as cm:
            self.sign(d, limits=archive.Limits(max_uncompressed=10))
        self.assertTrue(cm.exception.rule.startswith("tarball/"), cm.exception.rule)
        with self.assertRaises(sign_built.SignRefused) as cm:
            self.sign(d, limits=archive.Limits(max_entries=1))
        self.assertTrue(cm.exception.rule.startswith("tarball/"), cm.exception.rule)

    def test_c_sha_mismatch_in_result_json_is_refused(self):
        _, _, d = self.built("sb6")
        res = json.load(open(os.path.join(d, "result.json")))
        res["artifact"]["source_sha256"] = "0" * 64
        json.dump(res, open(os.path.join(d, "result.json"), "w"))
        with self.assertRaises(sign_built.SignRefused) as cm:
            self.sign(d)
        self.assertEqual(cm.exception.rule, "tarball/sha-mismatch")

    def test_signature_that_fails_the_reference_verifier_is_exit_2_class(self):
        _, _, d = self.built("sb7")
        other_pub, _ = make_keypair(self.fresh("k2"))[0], None   # a second throwaway pair
        pub_b, _key_b = make_keypair(self.fresh("kb"), "b")
        out = os.path.join(self.fresh("so"), "signed")
        with self.assertRaises(PipelineError):
            self.sign(d, key=self.key, pub=pub_b, out=out)   # key A signs, public key B verifies
        self.assertFalse(os.path.exists(out))

    def test_refuses_a_result_that_is_already_signed_or_malformed(self):
        _, _, d = self.built("sb8")
        p = os.path.join(d, "result.json")
        res = json.load(open(p))
        res["signed"] = True
        json.dump(res, open(p, "w"))
        with self.assertRaises(sign_built.SignRefused):
            self.sign(d)
        open(p, "w").write("not json")
        with self.assertRaises(sign_built.SignRefused):
            self.sign(d)

    def test_result_json_with_unknown_keys_is_refused_at_every_level(self):
        """F4: the build job is untrusted; nothing outside 008a's result shape may be copied into the signed result.json."""
        _, _, d = self.built("sb10")
        p = os.path.join(d, "result.json")
        good = json.load(open(p))
        self.assertEqual(set(good), {"id", "version", "tag", "assets", "built_at", "artifact", "signed", "scan"})
        cases = {"top": lambda r: r.update(extra="x"), "artifact": lambda r: r["artifact"].update(extra="x"),
                 "assets": lambda r: r["assets"].update(extra="x"), "scan": lambda r: r["scan"].update(extra="x"),
                 "missing built_at": lambda r: r.pop("built_at"), "missing scan": lambda r: r.pop("scan")}
        for name, edit in cases.items():
            res = json.loads(json.dumps(good))
            edit(res)
            json.dump(res, open(p, "w"))
            out = os.path.join(self.fresh("so"), "signed")
            with self.assertRaises(sign_built.SignRefused, msg=name) as cm:
                self.sign(d, out=out)
            self.assertEqual(cm.exception.rule, "result/shape", name)
            self.assertFalse(os.path.exists(out))
        json.dump(good, open(p, "w"))
        self.sign(d)   # the unmodified result still signs

    def _damaged_result(self, name, edit):
        _, _, d = self.built(name)
        p = os.path.join(d, "result.json")
        res = json.load(open(p))
        edit(res)
        json.dump(res, open(p, "w"))
        out = os.path.join(self.fresh("so"), "signed")
        return d, out

    def test_result_json_with_a_bad_scan_value_is_refused(self):
        """Values, not only keys: scan must satisfy validation-report.schema.json (the validator 008a uses)."""
        for i, edit in enumerate((lambda r: r["scan"]["summary"].update(files_inspected="many"),
                                  lambda r: r["scan"].update(root=5),
                                  lambda r: r["scan"].update(accepted="not a list"))):
            d, out = self._damaged_result(f"sb11-{i}", edit)
            with self.assertRaises(sign_built.SignRefused, msg=i) as cm:
                self.sign(d, out=out)
            self.assertEqual(cm.exception.rule, "result/scan", i)
            self.assertFalse(os.path.exists(out))

    def test_result_json_with_a_bad_built_at_is_refused(self):
        for i, value in enumerate(("yesterday", "2026-10-28T00:00:00", 12345, "2026-10-28T00:00:00Z\n")):
            d, out = self._damaged_result(f"sb12-{i}", lambda r, v=value: r.update(built_at=v))
            with self.assertRaises(sign_built.SignRefused, msg=repr(value)) as cm:
                self.sign(d, out=out)
            self.assertEqual(cm.exception.rule, "result/built-at", repr(value))
            self.assertFalse(os.path.exists(out))

    def run_sign_cli(self, d, key=None, pub=None, out=None):
        out = out or os.path.join(self.fresh("so"), "signed")
        argv = [sys.executable, SIGN_CLI, "--tarball", os.path.join(d, f"{TAG}.tar.gz"), "--result", os.path.join(d, "result.json"),
                "--key", key or self.key, "--pubkey", pub or self.pub, "--out", out]
        r = subprocess.run(argv, capture_output=True, text=True, stdin=subprocess.DEVNULL, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
        r.out_dir = out
        return r

    def test_cli_exit_codes_and_the_key_never_appears(self):
        _, _, d = self.built("sb9")
        secret_body = open(self.key).read().splitlines()[1]
        ok = self.run_sign_cli(d)
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertNotIn(secret_body, ok.stdout + ok.stderr)
        for n in os.listdir(ok.out_dir):
            self.assertNotIn(secret_body.encode(), open(os.path.join(ok.out_dir, n), "rb").read())
        bad = self.copy_dir(d)
        open(os.path.join(bad, f"{TAG}.tar.gz"), "ab").write(b"x")
        r = self.run_sign_cli(bad)
        self.assertEqual(r.returncode, 1)
        self.assertTrue(r.stderr.startswith("REFUSED ["), r.stderr)
        pub_b, _ = make_keypair(self.fresh("kb"), "b")
        r = self.run_sign_cli(d, pub=pub_b)
        self.assertEqual(r.returncode, 2, r.stderr)
        r = self.run_sign_cli(d, key="/nonexistent.key")
        self.assertEqual(r.returncode, 2)


class HandoffTests(NoSignBase):
    FILES_EXIT0 = {"build.log", "build.stderr", "outcome.json", "result.json", f"{TAG}.tar.gz"}

    def test_b_exit0_file_sets_and_reader(self):
        repo, c = make_repo(self.tmp, "h1", good_files())
        r, o = self.leg(repo, c)
        self.assertEqual(set(os.listdir(r.out_dir)), self.FILES_EXIT0)
        self.assertEqual(o, {"version_id": VID, "tag": TAG, "exit_code": 0, "reason": ""})
        # sign it as the signing job does
        signed = os.path.join(self.fresh("sg"), "signed")
        rc = subprocess.run([sys.executable, SIGN_CLI, "--tarball", os.path.join(r.out_dir, f"{TAG}.tar.gz"), "--result",
                             os.path.join(r.out_dir, "result.json"), "--key", self.key, "--pubkey", self.pub, "--out", signed],
                            capture_output=True, text=True, stdin=subprocess.DEVNULL).returncode
        fin = handoff.finish_sign(r.out_dir, signed, rc)
        self.assertEqual(fin["exit_code"], 0)
        self.assertEqual(set(os.listdir(signed)), {f"{TAG}.tar.gz", f"{TAG}.tar.gz.minisig", "result.json", "outcome.json"})
        res = json.load(open(os.path.join(signed, "result.json")))
        self.assertIs(res["signed"], True)
        self.assertTrue(res["artifact"]["signature"].startswith("untrusted comment:"))
        self.assertRegex(res["artifact"]["key_id"], r"^[0-9A-F]{16}$")
        self.assertEqual(open(os.path.join(signed, "outcome.json")).read(), open(os.path.join(r.out_dir, "outcome.json")).read())
        root = self.fresh("art")
        import shutil
        shutil.copytree(r.out_dir, os.path.join(root, f"build-{TAG}"))
        shutil.copytree(signed, os.path.join(root, f"signed-{TAG}"))
        self.assertEqual(handoff.read_outcomes(root, require_signed=True), [o])
        self.assertEqual(set(handoff.read_outcomes(root)[0]), {"version_id", "tag", "exit_code", "reason"})

    def test_b_exit1_after_start(self):
        repo, c = make_repo(self.tmp, "h2", good_files(license="LicenseRef-Proprietary"))
        r, o = self.leg(repo, c)
        self.assertEqual(r.returncode, 1)
        self.assertEqual(set(os.listdir(r.out_dir)), {"build.log", "build.stderr", "outcome.json"})
        self.assertEqual(o["exit_code"], 1)
        self.assertTrue(o["reason"].startswith(GOOD_REASON_PREFIX), o["reason"])
        self.assertIn(" -- remedy: ", o["reason"])
        self.assertNotRegex(o["reason"], r"\s\s|\n|^REJECTED")

    def test_b_exit1_preflight_leaves_stderr_only(self):
        repo, c = make_repo(self.tmp, "h3", good_files())
        entry = write_entry(os.path.join(self.fresh("e"), "entry.json"), "test:hello", [vobj("1.0.0", "A" * 40, repo)])
        out = os.path.join(self.fresh("op"), "out")
        r = subprocess.run([sys.executable, CLI, "--entry", entry, "--version", "1.0.0", "--workdir", self.fresh("w"), "--out", out,
                            "--no-sign", "--allow-local-source"], capture_output=True, text=True, stdin=subprocess.DEVNULL)
        self.assertEqual(r.returncode, 1)
        self.assertFalse(os.path.exists(out))
        errfile = os.path.join(self.fresh("err"), "e")
        open(errfile, "w").write(r.stderr)
        o = handoff.finish_build(out, errfile, VID, TAG, 1)
        self.assertEqual(set(os.listdir(out)), {"build.stderr", "outcome.json"})
        self.assertEqual((o["exit_code"], o["reason"].startswith("[commit/not-40-lowercase-hex]: ")), (1, True), o)

    def test_b_exit2_fault_has_no_reason_no_tarball(self):
        from helpers import write_stub_git
        repo, c = make_repo(self.tmp, "h4", good_files())
        entry = write_entry(os.path.join(self.fresh("e"), "entry.json"), "test:hello", [vobj("1.0.0", c, "https://example.invalid/x.git")])
        stub = write_stub_git(self.fresh("stub"), "record", log=os.path.join(self.fresh("log"), "l"))
        out = os.path.join(self.fresh("op"), "out")
        env = dict(os.environ, PATH=stub + os.pathsep + os.environ["PATH"])
        r = subprocess.run([sys.executable, CLI, "--entry", entry, "--version", "1.0.0", "--workdir", self.fresh("w"), "--out", out,
                            "--no-sign"], capture_output=True, text=True, stdin=subprocess.DEVNULL, env=env)
        self.assertEqual(r.returncode, 2, r.stderr)
        errfile = os.path.join(self.fresh("err"), "e")
        open(errfile, "w").write(r.stderr)
        o = handoff.finish_build(out, errfile, VID, TAG, 2)
        self.assertEqual(o, {"version_id": VID, "tag": TAG, "exit_code": 2, "reason": ""})
        self.assertEqual(set(os.listdir(out)), {"build.log", "build.stderr", "outcome.json"})

    def test_d_reason_from_stderr_else_from_the_log(self):
        d = self.fresh("rs")
        open(os.path.join(d, "build.stderr"), "w").write("REJECTED [r/x]:  line  one   -- remedy:   fix it \n")
        open(os.path.join(d, "build.log"), "w").write("a\nresult: exit 1 REJECTED [other]: from the log -- remedy: x\n")
        o = handoff.write_outcome(d, VID, TAG, 1)
        self.assertEqual(o["reason"], "[r/x]: line one -- remedy: fix it")
        self.assertEqual(json.load(open(os.path.join(d, "outcome.json"))), o)
        d = self.fresh("rl")
        open(os.path.join(d, "build.stderr"), "w").write("something else entirely\n")
        open(os.path.join(d, "build.log"), "w").write("result: exit 1 REJECTED [old]: first -- remedy: a\nresult: exit 1 REJECTED [last]: from the log  here -- remedy: b\nlater line\n")
        self.assertEqual(handoff.write_outcome(d, VID, TAG, 1)["reason"], "[last]: from the log here -- remedy: b")

    def test_d_reason_is_the_single_rejected_line_only(self):
        """F5: only the one REJECTED line, never what follows it (warnings, a traceback)."""
        d = self.fresh("r1")
        open(os.path.join(d, "build.stderr"), "w").write(
            "warning: noise before\nREJECTED [r/x]: msg -- remedy: fix\nWARNING: later\nTraceback (most recent call last):\n  File x\n")
        self.assertEqual(handoff.write_outcome(d, VID, TAG, 1)["reason"], "[r/x]: msg -- remedy: fix")
        d = self.fresh("r2")
        open(os.path.join(d, "build.stderr"), "w").write("no rejected line here\n")
        open(os.path.join(d, "build.log"), "w").write("result: exit 1 REJECTED [r/y]: m -- remedy: f\nTraceback follows\n  boom\n")
        self.assertEqual(handoff.write_outcome(d, VID, TAG, 1)["reason"], "[r/y]: m -- remedy: f")

    def test_d_all_whitespace_reason_is_an_exit_2_fault(self):
        d = self.fresh("rw")
        open(os.path.join(d, "build.stderr"), "w").write("  \n\t\n")
        open(os.path.join(d, "build.log"), "w").write("result: exit 1 \t \n")
        o = handoff.write_outcome(d, VID, TAG, 1)
        self.assertEqual((o["exit_code"], o["reason"]), (2, ""))
        d = self.fresh("rn")   # neither file
        self.assertEqual(handoff.write_outcome(d, VID, TAG, 1)["exit_code"], 2)

    def test_exit0_without_its_files_and_odd_codes_are_faults(self):
        d = self.fresh("x0")
        self.assertEqual(handoff.write_outcome(d, VID, TAG, 0)["exit_code"], 2)
        for code in (3, 137, -9, True):
            self.assertEqual(handoff.write_outcome(self.fresh("x"), VID, TAG, code)["exit_code"], 2, code)

    def test_e_every_sign_refusal_becomes_exit_code_2(self):
        for name, damage in (("byte", "byte"), ("extra", "extra"), ("sha", "sha")):
            repo, c = make_repo(self.tmp, f"e{name}", good_files())
            r, o = self.leg(repo, c)
            t = os.path.join(r.out_dir, f"{TAG}.tar.gz")
            if damage == "byte":
                data = bytearray(open(t, "rb").read())
                data[len(data) // 2] ^= 1
                open(t, "wb").write(bytes(data))
            elif damage == "extra":
                tar_gz(t, clean_tar_entries(extra=[{"name": "src/extra.txt", "data": b"e"}]))
            else:
                res = json.load(open(os.path.join(r.out_dir, "result.json")))
                res["artifact"]["source_sha256"] = "1" * 64
                json.dump(res, open(os.path.join(r.out_dir, "result.json"), "w"))
            signed = os.path.join(self.fresh("sg"), "signed")
            p = subprocess.run([sys.executable, SIGN_CLI, "--tarball", t, "--result", os.path.join(r.out_dir, "result.json"),
                                "--key", self.key, "--pubkey", self.pub, "--out", signed], capture_output=True, text=True, stdin=subprocess.DEVNULL)
            self.assertEqual(p.returncode, 1, (name, p.stderr))
            fin = handoff.finish_sign(r.out_dir, signed, p.returncode)
            self.assertEqual(fin["exit_code"], 2, name)
            self.assertEqual(os.listdir(signed), ["outcome.json"], "no tarball and no signature in a failed signed-<tag>")
            self.assertEqual(json.load(open(os.path.join(signed, "outcome.json")))["exit_code"], 2)
        # rc 2 and an incomplete rc-0 output are faults too
        repo, c = make_repo(self.tmp, "e-rc", good_files())
        r, _ = self.leg(repo, c)
        self.assertEqual(handoff.finish_sign(r.out_dir, os.path.join(self.fresh("n"), "none"), 2)["exit_code"], 2)
        self.assertEqual(handoff.finish_sign(r.out_dir, os.path.join(self.fresh("n"), "none"), 0)["exit_code"], 2)

    def test_c_plan_flags(self):
        empty = {"head_sha": "a" * 40, "build": [], "refuse": [], "skip": [], "fault": []}
        self.assertEqual(handoff.plan_flags(empty), {"has_build": "false", "has_writeback": "false"})
        self.assertEqual(handoff.plan_flags(dict(empty, refuse=[{"x": 1}])), {"has_build": "false", "has_writeback": "true"})
        self.assertEqual(handoff.plan_flags(dict(empty, build=[{"x": 1}])), {"has_build": "true", "has_writeback": "true"})
        self.assertEqual(handoff.plan_flags(dict(empty, skip=[{"x": 1}], fault=[{"x": 1}])), {"has_build": "false", "has_writeback": "false"})
        self.assertEqual(handoff.plan_flags(empty, synthetic=1), {"has_build": "true", "has_writeback": "true"})

    def test_matrix_has_one_leg_per_build_entry_only(self):
        plan = {"head_sha": "a" * 40, "build": [{"version_id": "mc.a@1.1.0-rc.1", "entry_path": "mods/mc.a/entry.json", "kind": "build", "reason": ""}],
                "refuse": [{"version_id": "mc.a@2.0.0+b", "entry_path": "mods/mc.a/entry.json"}],
                "skip": [{"version_id": "mc.a@1.0.0"}], "fault": [{"version_id": None}]}
        m = handoff.plan_matrix(plan)
        self.assertEqual(m, {"include": [{"version_id": "mc.a@1.1.0-rc.1", "tag": "mc.a-1.1.0-rc.1", "semver": "1.1.0-rc.1",
                                          "entry_path": "mods/mc.a/entry.json", "synthetic": False}]})
        d = handoff.plan_matrix(dict(plan, build=[]), "m4:probe", "0.1.0", True)
        self.assertEqual(d["include"], [{"version_id": "m4.probe@0.1.0", "tag": "m4.probe-0.1.0", "semver": "0.1.0", "entry_path": "", "synthetic": True}])
        for args in (("", "", True), ("m4:probe", "", True), ("m4:probe", "0.1.0", False), ("", "0.1.0", False), ("Bad Id", "0.1.0", True), ("m4:probe", "x", True)):
            with self.assertRaises(handoff.HandoffError, msg=args):
                handoff.plan_matrix(dict(plan, build=[]), *args)

    def test_synthetic_entry_is_a_buildable_entry(self):
        repo, c = make_repo(self.tmp, "syn", good_files())
        e = handoff.synthetic_entry("test:hello", "1.0.0", c, repo)
        p = os.path.join(self.fresh("se"), "entry.json")
        json.dump(e, open(p, "w"))
        out = os.path.join(self.fresh("o"), "out")
        r = subprocess.run([sys.executable, CLI, "--entry", p, "--version", "1.0.0", "--workdir", self.fresh("w"), "--out", out, "--no-sign",
                            "--allow-local-source"], capture_output=True, text=True, stdin=subprocess.DEVNULL)
        self.assertEqual(r.returncode, 0, r.stderr)

    def _outcome_dir(self, root, prefix, tag, code, vid=None, reason=""):
        d = os.path.join(root, f"{prefix}-{tag}")
        os.makedirs(d)
        json.dump({"version_id": vid or tag, "tag": tag, "exit_code": code, "reason": reason}, open(os.path.join(d, "outcome.json"), "w"))

    def test_read_outcomes_rules(self):
        root = self.fresh("ro")
        self._outcome_dir(root, "build", "a.b-1.0.0", 0, "a.b@1.0.0")
        self._outcome_dir(root, "signed", "a.b-1.0.0", 2, "a.b@1.0.0")          # sign fault overrides the build
        self._outcome_dir(root, "build", "c.d-1.0.0", 0, "c.d@1.0.0")           # built, never signed
        self._outcome_dir(root, "build", "e.f-1.0.0", 1, "e.f@1.0.0", "[r]: m -- remedy: x")
        got = {o["version_id"]: o["exit_code"] for o in handoff.read_outcomes(root)}
        self.assertEqual(got, {"a.b@1.0.0": 2, "c.d@1.0.0": 0, "e.f@1.0.0": 1})
        got = {o["version_id"]: o["exit_code"] for o in handoff.read_outcomes(root, require_signed=True)}
        self.assertEqual(got["c.d@1.0.0"], 2)
        self.assertEqual(handoff.exit_classes(handoff.read_outcomes(root))[0], {"version_id": "a.b@1.0.0", "exit_class": 2})
        bad = self.fresh("rb")
        self._outcome_dir(bad, "build", "x.y-1.0.0", 0, "x.y@1.0.0")
        json.dump({"version_id": "x.y@1.0.0", "tag": "other", "exit_code": 0, "reason": ""}, open(os.path.join(bad, "build-x.y-1.0.0", "outcome.json"), "w"))
        with self.assertRaises(ValueError):
            handoff.read_outcomes(bad)
        json.dump({"version_id": "x.y@1.0.0", "tag": "x.y-1.0.0", "exit_code": 7, "reason": ""}, open(os.path.join(bad, "build-x.y-1.0.0", "outcome.json"), "w"))
        with self.assertRaises(ValueError):
            handoff.read_outcomes(bad)

    def test_check_checkout_fails_closed_on_a_broken_or_sparse_checkout(self):
        from helpers import commit_files, git
        repo, _ = make_repo(self.tmp, "cc", {"mods/a.b/entry.json": "{}", "mods/c.d/entry.json": "{}", "README.md": "x"})
        self.assertEqual(handoff.check_checkout(repo), 2)
        os.unlink(os.path.join(repo, "mods", "c.d", "entry.json"))
        with self.assertRaises(handoff.HandoffError):
            handoff.check_checkout(repo)
        import shutil
        shutil.rmtree(os.path.join(repo, "mods"))
        with self.assertRaises(handoff.HandoffError):
            handoff.check_checkout(repo)
        empty, _ = make_repo(self.tmp, "cc2", {"README.md": "x"})
        self.assertEqual(handoff.check_checkout(empty), 0)   # a registry with no mod yet is fine
        with self.assertRaises(handoff.HandoffError):
            handoff.check_checkout(self.fresh("notrepo"))

    def run_cli(self, *args):
        return subprocess.run([sys.executable, HANDOFF_CLI, *args], capture_output=True, text=True, stdin=subprocess.DEVNULL)

    def test_cli_plan_outputs_and_summarize(self):
        plan = {"head_sha": "a" * 40, "build": [{"version_id": "test.hello@1.0.0", "entry_path": "mods/test.hello/entry.json", "kind": "build", "reason": ""}],
                "refuse": [], "skip": [], "fault": []}
        pp = os.path.join(self.fresh("pl"), "plan.json")
        json.dump(plan, open(pp, "w"))
        r = self.run_cli("plan-outputs", "--plan", pp)
        self.assertEqual(r.returncode, 0, r.stderr)
        kv = dict(line.split("=", 1) for line in r.stdout.splitlines())
        self.assertEqual((kv["has_build"], kv["has_writeback"], kv["head_sha"]), ("true", "true", "a" * 40))
        self.assertEqual(json.loads(kv["matrix"])["include"][0]["tag"], TAG)
        self.assertEqual(self.run_cli("plan-outputs", "--plan", pp, "--pair", "true").returncode, 2)   # pair without id/version
        root = self.fresh("so")
        self.assertEqual(self.run_cli("summarize", "--plan", pp, "--outcomes", root).returncode, 1, "a build entry with no outcome is non-green")
        self._outcome_dir(root, "build", TAG, 0, VID)
        self.assertEqual(self.run_cli("summarize", "--plan", pp, "--outcomes", root).returncode, 1, "built but never signed is non-green")
        self._outcome_dir(root, "signed", TAG, 0, VID)
        r = self.run_cli("summarize", "--plan", pp, "--outcomes", root)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.run_cli("summarize", "--plan", pp, "--outcomes", os.path.join(root, "nope")).returncode, 2)
        dry = self.fresh("dr")
        self._outcome_dir(dry, "build", TAG, 0, VID)
        self.assertEqual(self.run_cli("summarize", "--plan", pp, "--outcomes", dry, "--dry-run", "true").returncode, 0)
        # a synthetic dry-run version that is in no plan list
        plan0 = dict(plan, build=[])
        json.dump(plan0, open(pp, "w"))
        self.assertEqual(self.run_cli("summarize", "--plan", pp, "--outcomes", dry, "--dry-run", "true").returncode, 0)
        self.assertEqual(self.run_cli("summarize", "--plan", pp, "--outcomes", dry).returncode, 2, "stray outcome outside a dry run is an input error")
        g = self.run_cli("guard", "--dir", os.path.join(dry, f"build-{TAG}"))
        self.assertEqual(g.stdout.split(), ["proceed=true", "exit_code=0"])


if __name__ == "__main__":
    unittest.main()
