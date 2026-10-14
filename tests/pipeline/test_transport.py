"""AC16 and spec amendment A-1/A-2: the clone is restricted to https, option-injection safe,
time- and size-bounded and config-isolated. No network: https cases stop at a stub `git`."""

import os
import shlex
import sys
import time
import unittest

from helpers import Base, make_repo, good_files, vobj, write_entry, write_stub_git, TOOLS, git

import gitops  # noqa: E402
from pipeline_errors import PipelineError, Rejected  # noqa: E402

FAKE_COMMIT = "a" * 40


class Transport(Base):
    def entry_for(self, url):
        return write_entry(os.path.join(self.fresh("e"), "entry.json"), "test:hello", [vobj("1.0.0", FAKE_COMMIT, url)])

    def hostile(self, url, rule_prefix="clone-transport/", extra=()):
        """Run the CLI against `url` with a recording stub git on PATH. The stub must NEVER be
        invoked (no process may be spawned that could run the URL)."""
        log = os.path.join(self.fresh("stublog"), "git.log")
        stub = write_stub_git(os.path.join(os.path.dirname(log), "bin"), "record", log=log)
        r = self.run_cli(self.entry_for(url), "1.0.0", path_prefix=stub, extra=extra)
        self.assertEqual(r.returncode, 1, (url, r.stderr))
        self.assertIn(rule_prefix, r.stderr, url)
        self.assertFalse(os.path.exists(log), f"git was spawned for {url!r}")
        self.assertEqual(os.listdir(r.work_dir), [])
        return r

    def test_ac16_ext_command_is_never_run(self):
        marker = os.path.join(self.tmp, "ext-marker")
        for url in (f"ext::sh -c 'touch {marker}'", f"ext::sh${{IFS}}-c${{IFS}}touch${{IFS}}{marker}", f"ext::touch {marker}"):
            self.hostile(url)
        self.assertFalse(os.path.exists(marker))

    def test_ac16_ext_blocked_by_git_itself_even_if_the_tools_scheme_check_is_bypassed(self):
        # Calls the clone helper directly (the tool's own scheme check is NOT in the path) with a
        # hostile global git config that would otherwise allow ext:: . Only the env var / -c flags /
        # config isolation stand between the URL and a shell.
        marker = os.path.join(self.tmp, "ext-marker-direct")
        home = self.fresh("hostilehome")
        with open(os.path.join(home, ".gitconfig"), "w") as f:
            f.write("[protocol \"ext\"]\n\tallow = always\n[protocol]\n\tallow = always\n")
        old = os.environ.get("HOME")
        os.environ["HOME"] = home
        try:
            with self.assertRaises(PipelineError):
                gitops.clone(f"ext::sh -c 'touch {marker}'", os.path.join(self.fresh("c"), "clone"), allow_local=False, timeout=20, max_bytes=10**9, log=lambda m: None)
        finally:
            os.environ["HOME"] = old if old is not None else ""
        self.assertFalse(os.path.exists(marker), "git ran the ext:: helper")

    def test_ac16_local_file_url_and_bare_path_rejected_without_the_flag(self):
        repo, c = make_repo(self.tmp, "loc", good_files())
        self.hostile("file://" + repo)
        self.hostile(repo)

    def test_ac16_other_schemes_rejected(self):
        for url in ("ssh://host/x", "git://host/x", "http://host/x", "user@host:x", "ftp://host/x", "git@github.com:org/repo.git"):
            self.hostile(url)

    def test_ac16_https_with_userinfo_rejected_and_password_not_echoed(self):
        r = self.hostile("https://user:s3cretpw@host/x")
        self.assertIn("clone-transport/userinfo", r.stderr)
        self.assertNotIn("s3cretpw", r.stderr + r.stdout)

    def test_a1_option_shaped_urls_rejected(self):
        marker = os.path.join(self.tmp, "upload-pack-marker")
        for url in (f"--upload-pack=touch{marker}", "-u/tmp/x", "--config=core.sshCommand=x", "-oProxyCommand=x"):
            self.hostile(url)
        self.assertFalse(os.path.exists(marker))

    def test_a1_double_dash_precedes_the_url_on_the_spawned_command_line(self):
        log = os.path.join(self.fresh("sl"), "git.log")
        stub = write_stub_git(os.path.join(os.path.dirname(log), "bin"), "record", log=log)
        url = "https://example.invalid/mod.git"
        r = self.run_cli(self.entry_for(url), "1.0.0", path_prefix=stub)
        self.assertEqual(r.returncode, 2, r.stderr)   # the stub simulates a failed clone
        text = open(log).read()
        argv = shlex.split(text.split("ARGV: ", 1)[1].split("\n", 1)[0])
        i = argv.index(url)
        self.assertEqual(argv[i - 1], "--", "`--` must directly precede the URL (A-1)")
        self.assertIn("clone", argv)
        self.assertIn("--no-checkout", argv)

    def test_ac16_https_passes_scheme_check_and_spawned_command_carries_all_guards(self):
        log = os.path.join(self.fresh("sl"), "git.log")
        stub = write_stub_git(os.path.join(os.path.dirname(log), "bin"), "record", log=log)
        r = self.run_cli(self.entry_for("https://example.invalid/mod.git"), "1.0.0", path_prefix=stub)
        self.assertEqual(r.returncode, 2, r.stderr)
        text = open(log).read()
        argv = shlex.split(text.split("ARGV: ", 1)[1].split("\n", 1)[0])
        self.assertIn("protocol.ext.allow=never", argv)
        self.assertIn("protocol.file.allow=never", argv)
        self.assertEqual([argv[i - 1] for i, a in enumerate(argv) if a.startswith("protocol.")], ["-c", "-c"])
        env_lines = text.splitlines()
        self.assertIn("GIT_ALLOW_PROTOCOL=https", env_lines)
        self.assertIn("GIT_TERMINAL_PROMPT=0", env_lines)
        self.assertIn("GIT_CONFIG_GLOBAL=/dev/null", env_lines)
        self.assertIn("GIT_CONFIG_NOSYSTEM=1", env_lines)

    def test_ac16_local_flag_switches_guards_for_that_process_only(self):
        repo, c = make_repo(self.tmp, "locflag", good_files())
        log = os.path.join(self.fresh("sl"), "git.log")
        stub = write_stub_git(os.path.join(os.path.dirname(log), "bin"), "record", log=log)
        entry = write_entry(os.path.join(self.fresh("e"), "entry.json"), "test:hello", [vobj("1.0.0", c, repo)])
        self.run_cli(entry, "1.0.0", path_prefix=stub, extra=("--allow-local-source",))
        text = open(log).read()
        self.assertIn("GIT_ALLOW_PROTOCOL=file", text.splitlines())
        self.assertIn("protocol.file.allow=always", text)
        self.assertIn("protocol.ext.allow=never", text)
        # and the same tool WITHOUT the flag is back to https-only (no leakage between runs)
        log2 = os.path.join(self.fresh("sl"), "git.log")
        stub2 = write_stub_git(os.path.join(os.path.dirname(log2), "bin"), "record", log=log2)
        self.run_cli(self.entry_for("https://example.invalid/m.git"), "1.0.0", path_prefix=stub2)
        self.assertIn("GIT_ALLOW_PROTOCOL=https", open(log2).read().splitlines())


class CloneBounds(Base):
    def test_a2_wall_clock_timeout_kills_the_clone(self):
        stub = write_stub_git(os.path.join(self.fresh("st"), "bin"), "sleep")
        entry = write_entry(os.path.join(self.fresh("e"), "entry.json"), "test:hello", [vobj("1.0.0", FAKE_COMMIT, "https://example.invalid/m.git")])
        t0 = time.monotonic()
        r = self.run_cli(entry, "1.0.0", path_prefix=stub, extra=("--clone-timeout", "1"))
        elapsed = time.monotonic() - t0
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn("timed out", r.stderr)
        self.assertLess(elapsed, 6, "the stub sleeps 8s; the timeout must have cut it short")

    def test_a2_clone_size_cap_rejects_an_oversized_repository(self):
        stub = write_stub_git(os.path.join(self.fresh("st"), "bin"), "bigclone")
        entry = write_entry(os.path.join(self.fresh("e"), "entry.json"), "test:hello", [vobj("1.0.0", FAKE_COMMIT, "https://example.invalid/m.git")])
        t0 = time.monotonic()
        r = self.run_cli(entry, "1.0.0", path_prefix=stub, extra=("--max-clone-bytes", "1000000"))
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("clone-size-cap", r.stderr)
        self.assertLess(time.monotonic() - t0, 6)

    def test_a2_default_constants_are_documented_values(self):
        self.assertEqual(gitops.CLONE_TIMEOUT_S, 300.0)
        self.assertEqual(gitops.MAX_CLONE_BYTES, 512 * 1024 * 1024)

    def test_a2_user_global_git_config_is_not_consulted(self):
        # A hostile ~/.gitconfig rewrites an https URL to the local fixture repo. In local-source mode
        # git only allows `file`, so the clone can ONLY succeed if that config leaked into the process.
        repo, c = make_repo(self.tmp, "isol", good_files())
        home = self.fresh("home")
        with open(os.path.join(home, ".gitconfig"), "w") as f:
            f.write(f'[url "{repo}"]\n\tinsteadOf = https://rewrite.invalid/x.git\n')
        os.makedirs(os.path.join(home, ".config", "git"))
        with open(os.path.join(home, ".config", "git", "config"), "w") as f:
            f.write(f'[url "{repo}"]\n\tinsteadOf = https://rewrite.invalid/x.git\n')
        entry = write_entry(os.path.join(self.fresh("e"), "entry.json"), "test:hello", [vobj("1.0.0", c, "https://rewrite.invalid/x.git")])
        r = self.run_cli(entry, "1.0.0", extra=("--allow-local-source",), env_extra={"HOME": home, "XDG_CONFIG_HOME": os.path.join(home, ".config")})
        self.assertEqual(r.returncode, 2, "user git config must not rewrite the URL: " + r.stderr)
        self.assertIn("git clone failed", r.stderr)

    def test_a2_control_the_rewrite_would_work_if_config_were_read(self):
        # positive control for the test above: the same hostile config really does rewrite the URL
        # when git is run plainly, so the previous test's failure is due to isolation, not to a typo.
        repo, c = make_repo(self.tmp, "isolc", good_files())
        home = self.fresh("homec")
        with open(os.path.join(home, ".gitconfig"), "w") as f:
            f.write(f'[url "{repo}"]\n\tinsteadOf = https://rewrite.invalid/x.git\n')
        import subprocess
        d = os.path.join(self.fresh("cc"), "clone")
        env = {"PATH": os.environ["PATH"], "HOME": home, "GIT_ALLOW_PROTOCOL": "file", "GIT_CONFIG_NOSYSTEM": "1"}
        p = subprocess.run(["git", "-c", "protocol.file.allow=always", "clone", "--no-checkout", "--", "https://rewrite.invalid/x.git", d], env=env, capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)


if __name__ == "__main__":
    unittest.main()
