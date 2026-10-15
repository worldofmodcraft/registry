#!/usr/bin/env python3
"""Mutation runner for task 008a (MANAGER.md 2c rule 2): break the thing a check claims to check, in
a scratch copy of the COMMITTED tree, and require the named check to turn red.

    python3 tests/pipeline/mutate.py [--list] [id ...]

Each mutation is (id, file, [(old, new), ...], [check-name substrings that must FAIL]). An anchor
that is not found exactly once is a hard error: a search that finds nothing is a broken search.
Exit code = number of mutations that did NOT turn their named checks red (0 = all red)."""

import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

M = []


def mut(mid, file, edits, red):
    M.append((mid, file, edits, red))


# --- determinism, layout, key id, grammar, symlink (spec criterion 14 list) -----------------------
mut("gzip-without-n", "tools/pipeline/gitops.py", [('["gzip", "-n", "-c", tar_path]', '["gzip", "-c", tar_path]')],
    ["test_ac3_two_builds_at_different_times_are_byte_identical", "test_ac3_gzip_header_carries_no_name_and_no_timestamp"])
mut("no-prefix", "tools/pipeline/gitops.py", [('f"--prefix={ROOT_PREFIX}/", ', '')],
    ["test_ac4_every_entry_has_the_single_root_src", "test_ac1_exit_0_clean_build"])
mut("keyid-no-reversal-in-verifier", "tools/pipeline/reference_verify.py", [('l2[2:10][::-1].hex().upper()', 'l2[2:10].hex().upper()')],
    ["test_ac9_reference_verifier_accepts_it", "test_ac9_unreversed_key_id_in_the_entry_is_rule_6"])
mut("keyid-reversed-in-signer", "tools/pipeline/signing.py", [('    return m.group(1)\n', '    return bytes.fromhex(m.group(1))[::-1].hex().upper()\n')],
    ["test_ac9_key_id_equals_the_public_key_comment_line_and_the_reversed_bytes", "test_ac12_result_json_values"])
mut("trusted-comment-grammar", "tools/pipeline/signing.py", [(';version={version};sha256=', ';ver={version};sha256=')],
    ["test_ac9_trusted_comment_is_exactly_the_contract_grammar", "test_ac9_reference_verifier_accepts_it"])
mut("symlink-check-off", "tools/pipeline/archive.py", [('def _check_symlink_target(name: str, target: str) -> None:\n', 'def _check_symlink_target(name: str, target: str) -> None:\n    return\n')],
    ["test_ac4_symlink_with_absolute_target_rejected_whole", "test_ac4_symlink_with_dotdot_target_rejected_whole", "test_ac4_symlink_entries_escaping"])

# --- AC16 / A-1 / A-2 -----------------------------------------------------------------------------
mut("scheme-check-off", "tools/pipeline/gitops.py", [('    remedy = "publish a public https URL', '    return url\n    remedy = "publish a public https URL')],
    ["test_ac16_ext_command_is_never_run", "test_ac16_other_schemes_rejected", "test_a1_option_shaped_urls_rejected", "test_ac16_local_file_url_and_bare_path_rejected_without_the_flag", "test_ac16_https_with_userinfo_rejected_and_password_not_echoed"])
mut("env-allow-protocol-off", "tools/pipeline/gitops.py", [('        "GIT_ALLOW_PROTOCOL": "file" if allow_local else "https",\n', '')],
    ["test_ac16_https_passes_scheme_check_and_spawned_command_carries_all_guards", "test_ac16_local_flag_switches_guards_for_that_process_only"])
mut("dash-c-protocol-flags-off", "tools/pipeline/gitops.py", [('def _protocol_flags(allow_local: bool) -> list[str]:\n', 'def _protocol_flags(allow_local: bool) -> list[str]:\n    return []\n')],
    ["test_ac16_https_passes_scheme_check_and_spawned_command_carries_all_guards", "test_ac16_local_flag_switches_guards_for_that_process_only"])
mut("all-git-level-guards-off", "tools/pipeline/gitops.py", [
    ('def _protocol_flags(allow_local: bool) -> list[str]:\n', 'def _protocol_flags(allow_local: bool) -> list[str]:\n    return []\n'),
    ('        "GIT_ALLOW_PROTOCOL": "file" if allow_local else "https",\n', ''),
    ('        "GIT_CONFIG_GLOBAL": "/dev/null",\n', ''),
    ('        "GIT_CONFIG_NOSYSTEM": "1",\n', '')],
    ["test_ac16_ext_blocked_by_git_itself_even_if_the_tools_scheme_check_is_bypassed"])
mut("no-double-dash", "tools/pipeline/gitops.py", [('["--", url, dest]', '[url, dest]')],
    ["test_a1_double_dash_precedes_the_url_on_the_spawned_command_line"])
mut("clone-timeout-off", "tools/pipeline/procutil.py", [('if time.monotonic() > deadline:', 'if False:')],
    ["test_a2_wall_clock_timeout_kills_the_clone"])
mut("clone-size-cap-off", "tools/pipeline/procutil.py", [('path_size(watch_path) > max_bytes', 'False', 2)],
    ["test_a2_clone_size_cap_rejects_an_oversized_repository"])
mut("git-config-isolation-off", "tools/pipeline/gitops.py", [
    ('        "GIT_CONFIG_GLOBAL": "/dev/null",\n', ''), ('        "GIT_CONFIG_NOSYSTEM": "1",\n', '')],
    ["test_a2_user_global_git_config_is_not_consulted"])

# --- AC17 / A-3 ----------------------------------------------------------------------------------
mut("uncompressed-limit-infinite", "tools/pipeline/archive.py", [('MAX_UNCOMPRESSED_BYTES = 200 * 1024 * 1024', 'MAX_UNCOMPRESSED_BYTES = 10**18')],
    ["test_ac17_declared_uncompressed_size_over_200_mib_refused_without_buffering", "test_ac17_default_limits_are_the_documented_constants"])
mut("compressed-limit-infinite", "tools/pipeline/archive.py", [('MAX_COMPRESSED_BYTES = 50 * 1024 * 1024', 'MAX_COMPRESSED_BYTES = 10**18')],
    ["test_ac17_default_limits_are_the_documented_constants"])
mut("entry-limit-infinite", "tools/pipeline/archive.py", [('MAX_ENTRIES = 10_000', 'MAX_ENTRIES = 10**9')],
    ["test_ac17_entry_count_limit_boundary", "test_ac17_default_limits_are_the_documented_constants"])
_REG = 'if t in (tarfile.REGTYPE, tarfile.AREGTYPE):'
mut("accept-hardlink", "tools/pipeline/archive.py", [(_REG, 'if t in (tarfile.REGTYPE, tarfile.AREGTYPE, tarfile.LNKTYPE):')], ["test_ac17_hard_link_entry"])
mut("accept-chardev", "tools/pipeline/archive.py", [(_REG, 'if t in (tarfile.REGTYPE, tarfile.AREGTYPE, tarfile.CHRTYPE):')], ["test_ac17_character_device"])
mut("accept-blockdev", "tools/pipeline/archive.py", [(_REG, 'if t in (tarfile.REGTYPE, tarfile.AREGTYPE, tarfile.BLKTYPE):')], ["test_ac17_block_device"])
mut("accept-fifo", "tools/pipeline/archive.py", [(_REG, 'if t in (tarfile.REGTYPE, tarfile.AREGTYPE, tarfile.FIFOTYPE):')], ["test_ac17_fifo"])
mut("accept-unknown-type", "tools/pipeline/archive.py", [(_REG, 'if t in (tarfile.REGTYPE, tarfile.AREGTYPE, b"Z"):')], ["test_ac17_unknown_entry_type"])
mut("setuid-check-off", "tools/pipeline/archive.py", [('if m.mode & 0o7000:', 'if False:')], ["test_a3_setuid_setgid_and_sticky_modes"])
mut("duplicate-check-off", "tools/pipeline/archive.py", [('                if rel in seen:\n', '                if False:\n')], ["test_a3_duplicate_entry_names"])
mut("write-through-check-off", "tools/pipeline/archive.py", [('if pre in symlinks:', 'if False:')], ["test_a3_write_through_a_symlink", "test_a3_write_through_a_symlink_to_a_subdirectory"])
mut("dotdot-check-off", "tools/pipeline/archive.py", [('    if ".." in segs:\n', '    if False:\n')], ["test_ac4_dotdot_segment_anywhere"])
mut("absolute-check-off", "tools/pipeline/archive.py", [('    if name.startswith("/"):\n', '    if False:\n')], ["test_ac4_absolute_entry_name"])
mut("root-check-off", "tools/pipeline/archive.py", [('                if segs[0] != expected_root:', '                if False:')], ["test_ac4_top_level_file_without_root_and_two_roots"])

# --- AC5-AC8, AC2, AC12 ----------------------------------------------------------------------------
mut("manifest-loaders-allowed", "tools/validation/manifest.py", [('            elif val in _FORBIDDEN_LOADERS:', '            elif False:'), ('        if kind == "NAME" and val in _FORBIDDEN_LOADERS:', '        if False:')],
    ["test_ac5_rejects_require", "test_ac5_rejects_dofile"])
mut("manifest-concat-allowed", "tools/validation/manifest.py", [('        if nk == "SYM" and nv == "..":', '        if False:'), ('        if kind == "SYM" and val == "..":', '        if False:')], ["test_ac5_rejects_string_concatenation"])
mut("schema-validation-off", "tools/pipeline/build_version.py", [('        sc.validate(projected, _load_schema("manifest.schema.json"))', '        pass')],
    ["test_ac6_non_osi_licences_rejected_osi_accepted", "test_ac5_missing_required_field_rejected"])
mut("id-crosscheck-off", "tools/pipeline/build_version.py", [('    if projected["id"] != mod_id:', '    if False:')], ["test_ac5_id_mismatch_rejected_separately"])
mut("version-crosscheck-off", "tools/pipeline/build_version.py", [('    if projected["version"] != version:', '    if False:')], ["test_ac5_version_mismatch_rejected_separately"])
mut("scanner-exit-2-as-rejection", "tools/pipeline/build_version.py", [('        raise PipelineError(f"asset scanner exited {res.returncode} (a usage/internal error, not a rejection)', '        raise Rejected("asset-scan/rejected", "scanner failed", "none")  # (f"asset scanner exited {res.returncode} (a usage/internal error, not a rejection)')],
    ["test_ac7_scanner_exit_2_surfaces_as_exit_2_not_1", "test_ac7_real_scanner_pointed_at_a_file_exits_2_via_run_scan"])
mut("asset-scan-skipped", "tools/pipeline/build_version.py", [('    report = run_scan(extract_parent, archive.ROOT, os.path.join(work, "scan-report.json"), args.scanner)',
    '    report = {"summary": {"files_accepted": 0, "files_rejected": 0, "files_skipped": 0}, "accepted": [], "rejected": [], "scan_errors": [], "root": "src", "schema_version": "0"}')],
    ["test_ac7_blizzard_magic_named_png_rejected_naming_the_format", "test_ac7_glb_with_embedded_blizzard_payload_rejected"])
mut("reserved-names-off", "tools/pipeline/naming.py", [('    if stem in RESERVED_DEVICE_NAMES:', '    if False:')], ["test_ac8_reserved_device_namespaces_rejected_before_any_output", "test_ac8_case_insensitive_unit"])
mut("reserved-names-prefix-match", "tools/pipeline/naming.py", [('    if stem in RESERVED_DEVICE_NAMES:', '    if any(stem.startswith(r) for r in RESERVED_DEVICE_NAMES):')], ["test_ac8_comet_and_console_are_accepted_positive_controls"])
mut("fullmatch-becomes-search", "tools/pipeline/build_version.py", [('re.fullmatch(pattern, value) is not None', 're.search(pattern, value) is not None')],
    ["test_ac2_commit_with_trailing_newline_rejected", "test_ac2_version_not_semver_and_not_in_entry"])
mut("commit-from-head-not-entry", "tools/pipeline/gitops.py", [('f"--prefix={ROOT_PREFIX}/", commit]', 'f"--prefix={ROOT_PREFIX}/", "HEAD"]')],
    ["test_ac2_builds_the_entry_commit_even_when_branch_moved_on"])

# --- verifier can fail (AC10) and secrets (AC11) -----------------------------------------------------
mut("verifier-rule-11-off", "tools/pipeline/reference_verify.py", [('    if (c_id, c_version) != (claim.id, claim.version):', '    if False:')], ["test_ac10_d_copied_signature_for_a_different_id"])
mut("verifier-rule-10-off", "tools/pipeline/reference_verify.py", [('    if claim.source_sha256 != c_sha:', '    if False:')], ["test_ac10_e1_entry_sha256_differs_from_trusted_comment"])
mut("verifier-rule-9-off", "tools/pipeline/reference_verify.py", [('    if c_sha != h.hexdigest():', '    if False:')], ["test_ac10_e2_signed_comment_carries_a_hash_that_is_not_the_files"])
mut("verifier-rule-8-off", "tools/pipeline/reference_verify.py", [('    m = _COMMENT_RE.fullmatch(comment)\n', '    m = re.search(r"id=([^;]*);version=([^;]*);sha256=([0-9a-f]{64})", comment)\n')],
    ["test_ac10_b2_trusted_comment_with_extra_content_is_rule_8", "test_ac10_rule8_grammar_variants"])
mut("verifier-rule-7-off", "tools/pipeline/reference_verify.py", [('    if pub is None:', '    if False:')], ["test_ac10_f2_key_id_names_no_trusted_key"])
mut("verifier-rule-6-off", "tools/pipeline/reference_verify.py", [('    if embedded != claim.key_id:', '    if False:')], ["test_ac10_c_line2_key_id_bytes_edited"])
mut("verifier-crypto-off", "tools/pipeline/reference_verify.py", [('    if res.returncode != 0:\n        err = res.stderr.strip()', '    if False:\n        err = res.stderr.strip()')],
    ["test_ac10_a_appended_byte", "test_ac10_b_trusted_comment_edited", "test_ac10_f1_wrong_public_key_under_the_same_label"])
mut("log-the-key-contents", "tools/pipeline/build_version.py", [('    signing.sign(args.key, tgz_path, sig_path, signing.trusted_comment(plan["mod_id"], version, sha))\n', '    signing.sign(args.key, tgz_path, sig_path, signing.trusted_comment(plan["mod_id"], version, sha))\n    log(open(args.key).read())\n')],
    ["test_ac11_canary_in_env_and_key_comment_appears_in_no_output"])

def apply(root, file, edits):
    path = os.path.join(root, file)
    text = open(path).read()
    for edit in edits:
        old, new = edit[0], edit[1]
        want = edit[2] if len(edit) > 2 else 1
        n = text.count(old)
        if n != want:
            raise SystemExit(f"MUTATION ANCHOR BROKEN in {file}: found {n} times (need exactly {want}): {old!r}")
        text = text.replace(old, new)
    open(path, "w").write(text)


def main(argv):
    if argv and argv[0] == "--list":
        for mid, f, _e, red in M:
            print(f"{mid}\t{f}\t{','.join(red)}")
        return 0
    wanted = set(argv)
    todo = [m for m in M if not wanted or m[0] in wanted]
    unknown = wanted - {m[0] for m in M}
    if unknown:
        print("unknown mutation ids:", sorted(unknown))
        return 99
    not_red = 0
    for mid, file, edits, red in todo:
        td = tempfile.mkdtemp(prefix="wom008a-mut-")
        try:
            p = subprocess.run(f"git -C '{REPO}' archive HEAD | tar -x -C '{td}'", shell=True, capture_output=True, text=True)
            if p.returncode:
                raise SystemExit("cannot export the committed tree: " + p.stderr)
            apply(td, file, edits)
            env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
            r = subprocess.run([sys.executable, os.path.join(td, "tests", "pipeline", "run_checks.py"), "--only", *red],
                               capture_output=True, text=True, env=env, timeout=900)
            lines = [l for l in r.stdout.splitlines() if l.startswith("CHECK ")]
            statuses = {}
            for name in red:
                hits = [l for l in lines if name in l]
                statuses[name] = ("MISSING" if not hits else ("FAIL" if all(h.endswith(" FAIL") for h in hits) else "PASS"))
            ok = all(s == "FAIL" for s in statuses.values())
            tail = "; ".join(f"{n}={s}" for n, s in statuses.items())
            print(f"MUTATION {mid}: {'RED (good)' if ok else 'NOT RED  <-- the check cannot fail'}  [{tail}]", flush=True)
            if not ok:
                not_red += 1
        finally:
            shutil.rmtree(td, ignore_errors=True)
    print(f"MUTATION SUMMARY mutations={len(todo)} not_red={not_red}")
    return not_red


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
