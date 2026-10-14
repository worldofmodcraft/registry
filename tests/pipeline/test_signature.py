"""AC9, AC10, AC11: the signature is byte-exact against the contract and the real minisign tool;
the independent reference verifier accepts it and rejects every attack with the right rule number;
no secret reaches any output. Keys are throwaway (generated here, removed in tearDownClass)."""

import base64
import json
import os
import re
import subprocess
import unittest

from helpers import Base, good_files, make_keypair, make_repo, sha256sum

import reference_verify as rv  # noqa: E402

ID, VERSION = "test:hello", "1.0.0"


def naive_verify(tarball, claim, trusted):
    """DELIBERATELY NAIVE (MANAGER.md 2c rule 5): "does the signature verify these bytes under the
    claimed key" and nothing else. Hostile fixtures are shown against it first."""
    import tempfile
    pub = trusted[claim.key_id]
    with tempfile.TemporaryDirectory(prefix="wom008a-naive-") as td:
        sf = os.path.join(td, "s.minisig")
        open(sf, "w", newline="").write(claim.signature)
        r = subprocess.run(["minisign", "-V", "-p", pub, "-m", tarball, "-x", sf], capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if r.returncode != 0:
        raise rv.Rejection(4, r.stderr.strip())


class Signature(Base):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        repo, commit = make_repo(cls.tmp, "sigrepo", good_files())
        from helpers import write_entry, vobj
        entry = write_entry(os.path.join(cls.tmp, "entry.json"), ID, [vobj(VERSION, commit, repo)])
        import sys
        from helpers import CLI
        out = os.path.join(cls.tmp, "sigout")
        work = os.path.join(cls.tmp, "sigwork"); os.makedirs(work)
        r = subprocess.run([sys.executable, CLI, "--entry", entry, "--version", VERSION, "--workdir", work, "--key", cls.key, "--pubkey", cls.pub, "--out", out, "--allow-local-source"],
                           capture_output=True, text=True, stdin=subprocess.DEVNULL)
        assert r.returncode == 0, r.stderr
        cls.out = out
        cls.tarball = os.path.join(out, "test.hello-1.0.0.tar.gz")
        cls.sigpath = os.path.join(out, "test.hello-1.0.0.tar.gz.minisig")
        cls.sig = open(cls.sigpath, encoding="utf-8", newline="").read()
        cls.result = json.load(open(os.path.join(out, "result.json")))
        cls.sha = sha256sum(cls.tarball)            # OS tool
        cls.key_id = cls.result["artifact"]["key_id"]
        cls.other_pub, cls.other_key = make_keypair(cls.tmp, "other")

    def claim(self, **kw):
        base = dict(id=ID, version=VERSION, source_sha256=self.sha, key_id=self.key_id, signature=self.sig)
        base.update(kw)
        return rv.VersionClaim(**base)

    @property
    def trusted(self):
        return {self.key_id: self.pub}

    def lines(self):
        return self.sig.rstrip("\n").split("\n")

    def expect_rule(self, rule, claim=None, tarball=None, trusted=None):
        with self.assertRaises(rv.Rejection) as cm:
            rv.verify(tarball or self.tarball, claim or self.claim(), self.trusted if trusted is None else trusted)
        self.assertEqual(cm.exception.rule, rule, str(cm.exception))

    def tampered_tarball(self):
        p = os.path.join(self.fresh("tt"), "t.tar.gz")
        open(p, "wb").write(open(self.tarball, "rb").read() + b"\x00")
        return p

    # ---- AC9 -----------------------------------------------------------------
    def test_ac9_four_lines_and_decoded_lengths(self):
        ls = self.lines()
        self.assertEqual(len(ls), 4)
        self.assertTrue(self.sig.endswith("\n"))
        l2, l4 = base64.b64decode(ls[1], validate=True), base64.b64decode(ls[3], validate=True)
        self.assertEqual(len(l2), 74)
        self.assertEqual(len(l4), 64)
        self.assertEqual(l2[:2], b"ED", "minisign 0.12 -S is prehashed by default")

    def test_ac9_trusted_comment_is_exactly_the_contract_grammar(self):
        expected = f"trusted comment: format=1;id={ID};version={VERSION};sha256={self.sha}"   # sha from the OS tool
        self.assertEqual(self.lines()[2], expected)

    def test_ac9_minisign_accepts_it(self):
        r = subprocess.run(["minisign", "-V", "-p", self.pub, "-m", self.tarball, "-x", self.sigpath], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Signature and comment signature verified", r.stdout)

    def test_ac9_reference_verifier_accepts_it(self):
        self.assertEqual(rv.verify(self.tarball, self.claim(), self.trusted), f"format=1;id={ID};version={VERSION};sha256={self.sha}")

    def test_ac9_key_id_equals_the_public_key_comment_line_and_the_reversed_bytes(self):
        comment = open(self.pub).readline().rstrip("\n")
        m = re.fullmatch(r"untrusted comment: minisign public key ([0-9A-F]{16})", comment)
        self.assertTrue(m)
        self.assertEqual(self.key_id, m.group(1))                       # compared against the pubkey FILE
        l2 = base64.b64decode(self.lines()[1])
        self.assertEqual(l2[2:10][::-1].hex().upper(), m.group(1))      # reversal, derived here
        self.assertNotEqual(l2[2:10].hex().upper(), m.group(1), "encounter-order hex must differ (else the reversal is untested)")
        blob = base64.b64decode(open(self.pub).read().split("\n")[1])
        self.assertEqual(blob[2:10][::-1].hex().upper(), m.group(1))

    def test_ac9_unreversed_key_id_in_the_entry_is_rule_6(self):
        raw = base64.b64decode(self.lines()[1])[2:10].hex().upper()
        self.expect_rule(6, claim=self.claim(key_id=raw), trusted={raw: self.pub})

    # ---- AC10: hostile fixtures, each its own check ---------------------------
    def test_ac10_a_appended_byte(self):
        t = self.tampered_tarball()
        self.expect_rule(4, tarball=t)
        with self.assertRaises(rv.Rejection):
            naive_verify(t, self.claim(), self.trusted)

    def test_ac10_b_trusted_comment_edited(self):
        ls = self.lines()
        ls[2] = ls[2].replace("version=1.0.0", "version=1.0.1")
        sig = "\n".join(ls) + "\n"
        self.expect_rule(5, claim=self.claim(signature=sig))
        with self.assertRaises(rv.Rejection):
            naive_verify(self.tarball, self.claim(signature=sig), self.trusted)

    def test_ac10_b2_trusted_comment_with_extra_content_is_rule_8(self):
        ls = self.lines()
        ls[2] += ";extra=1"
        self.expect_rule(8, claim=self.claim(signature="\n".join(ls) + "\n"))

    def test_ac10_c_line2_key_id_bytes_edited(self):
        ls = self.lines()
        d = bytearray(base64.b64decode(ls[1]))
        d[5] ^= 0x01
        ls[1] = base64.b64encode(bytes(d)).decode()
        sig = "\n".join(ls) + "\n"
        self.expect_rule(6, claim=self.claim(signature=sig))
        with self.assertRaises(rv.Rejection):
            naive_verify(self.tarball, self.claim(signature=sig), self.trusted)

    def test_ac10_d_copied_signature_for_a_different_id(self):
        evil = self.claim(id="evil:not-hello-world")        # every other field copied byte-for-byte
        naive_verify(self.tarball, evil, self.trusted)       # the naive verifier ACCEPTS it: the attack works against it
        self.expect_rule(11, claim=evil)
        self.expect_rule(11, claim=self.claim(version="9.9.9"))

    def test_ac10_e1_entry_sha256_differs_from_trusted_comment(self):
        bad = self.claim(source_sha256="0" * 64)
        naive_verify(self.tarball, bad, self.trusted)        # naive accepts
        self.expect_rule(10, claim=bad)

    def test_ac10_e2_signed_comment_carries_a_hash_that_is_not_the_files(self):
        p = os.path.join(self.fresh("e2"), "x.minisig")
        wrong = "1" * 64
        r = subprocess.run(["minisign", "-S", "-s", self.key, "-m", self.tarball, "-x", p, "-t", f"format=1;id={ID};version={VERSION};sha256={wrong}"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        sig = open(p, newline="").read()
        c = self.claim(signature=sig, source_sha256=wrong)    # entry agrees with the (lying) comment
        naive_verify(self.tarball, c, self.trusted)           # naive accepts
        self.expect_rule(9, claim=c)

    def test_ac10_f1_wrong_public_key_under_the_same_label(self):
        self.expect_rule(4, trusted={self.key_id: self.other_pub})
        with self.assertRaises(rv.Rejection):
            naive_verify(self.tarball, self.claim(), {self.key_id: self.other_pub})

    def test_ac10_f2_key_id_names_no_trusted_key(self):
        self.expect_rule(7, trusted={})
        self.expect_rule(7, trusted={"0" * 16: self.other_pub})

    # ---- the verifier's structural rules (1-3, 8) ------------------------------
    def test_ac10_rule1_structure(self):
        ls = self.lines()
        self.expect_rule(1, claim=self.claim(signature="\n".join(ls[:3]) + "\n"))
        self.expect_rule(1, claim=self.claim(signature="\n".join(ls + ["extra"]) + "\n"))
        self.expect_rule(1, claim=self.claim(signature="\n".join(["comment"] + ls[1:]) + "\n"))
        self.expect_rule(1, claim=self.claim(signature="\n".join(ls[:2] + ["TRUSTED comment: x"] + ls[3:]) + "\n"))

    def test_ac10_rule2_base64_and_lengths(self):
        ls = self.lines()
        self.expect_rule(2, claim=self.claim(signature="\n".join([ls[0], "!!!notbase64!!!", ls[2], ls[3]]) + "\n"))
        short = base64.b64encode(base64.b64decode(ls[1])[:-1]).decode()
        self.expect_rule(2, claim=self.claim(signature="\n".join([ls[0], short, ls[2], ls[3]]) + "\n"))
        short4 = base64.b64encode(base64.b64decode(ls[3])[:-1]).decode()
        self.expect_rule(2, claim=self.claim(signature="\n".join([ls[0], ls[1], ls[2], short4]) + "\n"))

    def test_ac10_rule3_algorithm_bytes(self):
        ls = self.lines()
        d = bytearray(base64.b64decode(ls[1])); d[0:2] = b"XX"
        ls[1] = base64.b64encode(bytes(d)).decode()
        self.expect_rule(3, claim=self.claim(signature="\n".join(ls) + "\n"))

    def test_ac10_rule8_grammar_variants(self):
        base = self.lines()
        for bad in (f"format=2;id={ID};version={VERSION};sha256={self.sha}",
                    f"id={ID};format=1;version={VERSION};sha256={self.sha}",
                    f"format=1;id={ID};version={VERSION}",
                    f"format=1; id={ID};version={VERSION};sha256={self.sha}",
                    f"format=1;id={ID};version={VERSION};sha256={self.sha.upper()}"):
            ls = list(base); ls[2] = "trusted comment: " + bad
            self.expect_rule(8, claim=self.claim(signature="\n".join(ls) + "\n"))


class NoSecretInOutput(Base):
    CANARY = "CANARY-7f3a9c-do-not-leak"

    def test_ac11_canary_in_env_and_key_comment_appears_in_no_output(self):
        pub, key = make_keypair(self.tmp, "canary", secret_comment=f"minisign encrypted secret key {self.CANARY}")
        self.assertIn(self.CANARY, open(key).read(), "control: the canary really is in the key file")
        key_payload = open(key).read().split("\n")[1]
        repo, commit = make_repo(self.tmp, "canrepo", good_files())
        from helpers import write_entry, vobj
        entry = write_entry(os.path.join(self.fresh("e"), "entry.json"), ID, [vobj(VERSION, commit, repo)])
        r = self.run_cli(entry, VERSION, key=key, pubkey=pub, extra=("--allow-local-source",),
                         env_extra={"MINISIGN_SECRET_KEY": self.CANARY, "WOM_SIGNING_KEY": self.CANARY})
        self.assertEqual(r.returncode, 0, r.stderr)
        blobs = {"stdout": r.stdout.encode(), "stderr": r.stderr.encode()}
        for f in os.listdir(r.out_dir):
            blobs[f] = open(os.path.join(r.out_dir, f), "rb").read()
        import gzip
        blobs["tarball (decompressed)"] = gzip.decompress(blobs["test.hello-1.0.0.tar.gz"])
        self.assertIn("build.log", blobs)
        for name, data in blobs.items():
            self.assertNotIn(self.CANARY.encode(), data, name)
            self.assertNotIn(key_payload.encode(), data, name)
        self.assertGreater(len(blobs["build.log"]), 100)

    def test_ac11_failure_paths_do_not_leak_either(self):
        pub, key = make_keypair(self.tmp, "canary2", secret_comment=f"x {self.CANARY}")
        other_pub, _ = make_keypair(self.tmp, "canary2-other")
        repo, commit = make_repo(self.tmp, "canrepo2", good_files())
        from helpers import write_entry, vobj
        entry = write_entry(os.path.join(self.fresh("e"), "entry.json"), ID, [vobj(VERSION, commit, repo)])
        r = self.run_cli(entry, VERSION, key=key, pubkey=other_pub, extra=("--allow-local-source",), env_extra={"MINISIGN_SECRET_KEY": self.CANARY})
        self.assertEqual(r.returncode, 2, "a --key/--pubkey mismatch is an operator error")
        text = r.stdout + r.stderr + open(os.path.join(r.out_dir, "build.log")).read()
        self.assertNotIn(self.CANARY, text)


if __name__ == "__main__":
    unittest.main()
