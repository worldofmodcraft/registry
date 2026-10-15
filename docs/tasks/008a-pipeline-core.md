# Task 008a: Pipeline core — clone, validate, scan, archive, hash, sign (offline)

- **Mission:** SITE-V1, deliverable **D2** (first half; umbrella `docs/tasks/008-build-pipeline.md`) — **Status:** done (implementer, 2026-10-15; spec-approved by manager 2026-10-14 after independent spec review round 2: PASS) 
- **Agent / model:** implementer / sonnet (the signing and verifier parts get an independent reviewer at the same tier or higher with full tools — OPERATIONS.md, "The reviewer agent cannot run this project's verify artefacts")
- **Budget:** large (≤ 6 agent-sessions)
- **Branch / worktree:** `task/008a-pipeline-core` / `~/wt/registry-task-008a` — **registry** repo (`worldofmodcraft/registry`)

## Objective
A command-line tool exists in the registry repo that, given a version to build, produces — from
nothing but a git repository, a 40-hex commit, and a key *file* — the exact artefacts the
contracts describe: a deterministic `.tar.gz` of that commit with a single rooted directory
(`archive-layout.md`), its SHA-256, a minisign detached signature whose trusted comment follows
`signature-format.md`, the release tag and two asset names from `artifact-naming.md`, and a result
object holding the computed hash, signature, `key_id` and build time. (Turning those into a registry write-back, and the `source_archive` URL, are task 008c.) Every rejection the mission requires (§7.1) is produced
by this tool for the pipeline half (non-OSI licence, wrong-extension Blizzard payload, GLB with a
disallowed embedded payload) and is demonstrated against hostile fixtures. Nothing here touches the
network, GitHub, or a real key.

## Context to load (exhaustive)
- ADRs: 0041 (integrity chain, archiving), 0058 §1-§3, 0059 §1, 0030 (manifest fields), 0103,
  0117, 0119 (reserved namespaces), 0120 (content whitelist), 0099 (CI gates), 0049 (licence, via
  `manifest.schema.json`). ADR selection: INDEX.json lookups on "pipeline", "signing", "archive",
  "manifest".
- Contracts (registry `origin/main`): `signature-format.md` (all of it, esp. "Deriving `key_id`"
  and the eleven verifier rejections), `artifact-naming.md` (all of it, incl. Windows reserved
  names and the `.` join), `archive-layout.md` (root convention, path-escape rule, malformed
  archives), `manifest.schema.json`, `entry.schema.json` (read-only: the version object's `version`, `commit` and `source_url` fields),
  `validation-report.schema.json`. (Not needed here, by design: task 057's amendments and task 058's report — 008c.)
- Code to reuse, not reimplement: `tools/validation/scan_assets.py` (takes a **directory**; exit 0
  accept, 1 reject, 2 usage error — a 2 is never a rejection), `tools/validation/magic.py`,
  `tests/contracts/schema_check.py` (`validate(instance, schema)` raises; `NotImplementedError` on
  unsupported keywords), `reserved-namespaces.json`.
- Docs: `docs/validation/asset-scanner.md`, `docs/architecture/key-management.md` (public key,
  `key_id` `6E5B30596A7A8CC4`, **no private key anywhere in this task**).
- Doctrine: MANAGER.md §2c, §3.6b, §3.6c, §3.7, §3.10; CLAUDE.md rules 5, 11.
- Graph: nodes **N5**, **N4** (the manifest half is new), **N6** (names only); edges E1, E5/E6, E7,
  E8 (the computed object), E9.

## Environmental facts this spec relies on (verified here, 2026-10-14; commands shown)
```
$ which minisign && minisign -v          →  /home/ludwig/.local/bin/minisign   minisign 0.12
$ D=$(mktemp -d); cd $D; minisign -G -W -p k.pub -s k.key      # throwaway key, exit 0
$ minisign -S -s k.key -m f.tar.gz -t "format=1;id=test:hello-world;version=1.0.0;sha256=<hex>" -x f.tar.gz.minisig   # exit 0, no prompt
$ minisign -V -p k.pub -m f.tar.gz -x f.tar.gz.minisig        # exit 0: "Signature and comment signature verified"
$ echo x >> f.tar.gz; minisign -V …                           # exit 1: "Signature verification failed"
```
- Line 2 of the produced `.minisig` base64-decodes to **74 bytes** starting `ED` (the prehashed
  variant is minisign 0.12's default for `-S`); line 4 decodes to **64 bytes**; the 8 key-id bytes
  of line 2, **reversed** and upper-cased, equal the 16 hex characters in `k.pub`'s comment line
  (`C20EF6F59D3AB182` in that run). This confirms `signature-format.md` against the real tool for
  `ED`; the `Ed` legacy variant (`-l`) was not exercised here.
- `minisign -S -s <(cat k.key) …` (key via process substitution, no key file argument on disk)
  exits 0 in that run: the secret can reach minisign without being written to a file by the caller.
  Whether the same works under the CI runner's shell is unverified (008b).
- `git archive --format=tar --prefix=src/ HEAD | gzip -n` run twice, two seconds apart, gave
  byte-identical output (sha256 `ec33042e…` both). So `gzip -n` plus a fixed `--prefix` is
  deterministic for a fixed commit. Plain `git archive` without `--prefix` has no root
  (`archive-layout.md` shows this too).
- Node 24 and Python 3 stdlib are present; Lua is **not** (`which lua lua5.4 luajit` prints nothing).
- **Not verified, so every dependent criterion carries it:** that minisign can be installed on a
  GitHub-hosted runner (the only known-good route is the pinned static binary Ludwig used in M3 —
  `docs/runbooks/site-v1-manual-steps.md` — with its checksum checked; apt availability untested);
  and that `git archive` honours `export-ignore`/`export-subst` from the archived tree's own
  `.gitattributes` (documented git behaviour; test it, criterion 4).

## Design (decisions made in this spec)
1. **Fetch:** `git clone --no-checkout <source_url> <dir>`, then `git cat-file -e <commit>^{commit}`,
   then `git archive` straight from the object database. **No working tree is ever checked out**:
   no smudge/clean filters, no LFS, no hooks (hooks are not cloned) run on attacker content.
   Submodules are not followed. Any host, no GitHub API (mission D2 step 1).
   **Transport is restricted (review fix, 2026-10-14).** `entry.schema.json` lets `source_url` be any
   scheme or an scp-like `user@host:path`; the pipeline accepts only `https://`. Every git invocation
   runs with `GIT_ALLOW_PROTOCOL=https`, `GIT_TERMINAL_PROMPT=0`, and `-c protocol.ext.allow=never -c protocol.file.allow=never`
   (so `ext::` and `file:` are refused by git itself, not only by the tool's own check), and the tool
   rejects any other scheme before spawning git, naming the rule and the remedy ("publish a public https URL").
   `file://` and bare local paths are accepted **only** behind an explicit `--allow-local-source` flag that
   tests use and the workflow never passes; with the flag, `GIT_ALLOW_PROTOCOL=file` replaces `https` and
   `protocol.file.allow` is set to `always` for that process only. Whether this restriction conflicts with
   ADR-0058 §4's "any host" is a reading: §4 speaks of the host (a public git repo, "not GitHub"), not the
   transport; ADR-0058 does not mention `ssh`/`git://`. [Judgement, not verified; flagged for the spec reviewer.]
2. **Tarball:** `git archive --format=tar --prefix=<root>/ <commit> | gzip -n`, `<root>` a fixed
   literal chosen once: `src/` (archive-layout.md leaves the value open; ADR-0103 says one fixed
   boring literal). Deterministic, so a re-run yields the same SHA-256.
3. **Scan the tarball, not the clone.** The asset scan and manifest validation run on the contents
   *extracted from the produced tarball* into a fresh directory, because that is what users and the
   site receive. `.gitattributes` `export-ignore` could otherwise hide a file from the tarball but
   not from a scan of the clone, or the reverse.
4. **Extraction is hostile-input safe:** the tool inspects every tar entry before extracting and
   rejects the whole archive on: a `..` segment, an absolute path, a symlink target escaping the root
   (all three from `archive-layout.md`, "path-escape rule"); **and** — added here because that
   contract is silent on them (grep of `origin/main:contracts/archive-layout.md` for
   `hardlink|hard link|device|fifo|special|size|limit|count` matched only the symlink/escape passages, lines
   150-179 and 232, none concerning these) — a **hard link** entry, a **device node** (character or block),
   a **FIFO**, any entry type other than regular file, directory or (inspected) symlink, a total **uncompressed size**
   above 200 MiB, a **compressed size** above 50 MiB, and more than 10,000 **entries**. The three limits are this
   spec's assumed constants (no ADR or contract states them; the 50 MiB figure matches the site downloader's
   ceiling in task 055), kept as named constants and recorded in `docs/pipeline/build-pipeline.md`.
   `git archive` cannot itself emit hard links, devices or FIFOs (git stores neither — *stated from git's
   object model, not verified here*), so these checks are defence in depth over a tarball the tool did not
   hand-build; the fixtures hand-build the hostile tars. The same gap exists in `archive-layout.md` and in the
   site's extractor; amending the contract is the sibling contract work (umbrella, Dependencies), not this task.
5. **Manifest (decided: Ludwig, 2026-10-14, Q-C):** read `<root>/mod.lua` with the restricted static reader (a literal table only; the file is never executed); project the eleven schema fields;
   validate against `manifest.schema.json`; check `manifest.id == entry id` and
   `manifest.version == version` (both cross-checks are named in the schema's descriptions as
   "pipeline logic"). Licence validity is the schema's SPDX-OSI enum (task 006); `LicenseRef-*`
   and `NOASSERTION` are rejected by it, which the existing invalid examples already show.
6. **Key handling:** the signing step takes a **path** to a key file (`--key`), never key bytes on
   the command line or in an argument, and never logs it. In CI the path is a process substitution
   or a 0600 file under a temp directory removed on exit (008b chooses).
7. **Name safety:** the namespace is checked against the Windows reserved device names
   (case-insensitive, `CON PRN AUX NUL COM0-9 LPT0-9`) **before** any tag or filename is built
   (`artifact-naming.md`). The exact matching behaviour is stated there as unverified against a
   Windows machine; the rule is enforced regardless.

## CLI and result shape
`python3 tools/pipeline/build_version.py --entry <path to entry.json> --version <semver>
--workdir <empty dir> --key <path> --pubkey <path> --out <dir> [--allow-local-source]`  (the flag is for tests only; the workflow never passes it)
Exit codes: **0** built; **1** rejected (the version is bad — message names the rule/contract
clause and the remedy); **2** usage/internal error (including scanner exit 2, missing tool, clone
failure) — distinct, documented, and never conflated (OPERATIONS.md).
Outputs in `--out`: `<tag>.tar.gz`, `<tag>.tar.gz.minisig` (names per `artifact-naming.md`),
`result.json` (below), `build.log` (the full log; the thing 008b posts as a PR comment).
`result.json`: `{ "id", "version", "tag", "assets": {"tarball", "signature"}, "built_at", "artifact":
{"source_sha256", "signature", "key_id"}, "scan": <validation-report object> }`; `built_at` is RFC 3339
UTC. The mapping of these into a registry write-back (`published_at`, `source_archive`, `apply_write_back`)
and the `source_archive` URL function are **task 008c**. This task provides one pure function for the
upload step, `release_asset_url(owner, repo, tag, asset)` — the direct
`https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>` URL; the repository is `worldofmodcraft/archive`
(decision Q-E, Ludwig 2026-10-14), a value passed in, not hard-coded; its output is pinned by a test.

## Acceptance criteria
All command-based; all demonstrated by `docs/tasks/008a-verify.sh` unless marked.
1. **Standalone CLI with three distinct exits** as above, each shown: a clean build (0), a rejected
   fixture (1), and a usage error such as a missing `--key` (2). Reading 2 as 1 is the recorded
   failure mode.
2. **Exact-commit fetch.** The commit is **read from the entry**: the tool loads `--entry`, selects the
   version object whose `version` equals `--version`, and takes that object's `commit` and `source_url`
   (it accepts no commit on the command line, so there is one source). Against a local fixture repo
   (created by the test, used through `--allow-local-source`): the tool builds from the entry's commit
   even when the branch has moved on (`HEAD` ≠ commit), and the tarball contains the *older* tree. A commit
   absent from the repo → exit 1 naming it. Before any clone, exit 1 for: a `commit` that is not 40 lowercase
   hex (the schema's pattern; an uppercase-hex commit is the negative case), a `--version` that does not match
   the semver pattern in `entry.schema.json`, and a `--version` that no version object carries.
3. **Determinism.** Two builds of the same commit, at different wall-clock times, yield
   byte-identical tarballs and equal SHA-256; the recorded `source_sha256` equals `sha256sum` of the
   file (cross-checked against the OS tool, not against the tool's own code).
4. **Archive layout.** Every entry has the single root `src/`; a fixture repo with a **symlink**
   whose target is absolute or `..`-escaping is rejected whole (exit 1, `archive-layout.md`
   cited); a `.gitattributes` fixture using `export-ignore` on `mod.lua` is rejected as "manifest
   missing in the produced archive" (proves scanning is of the tarball); a fixture using
   `export-subst` records what happened in the log and is accepted or rejected per the test's
   stated expectation — the test asserts the observed behaviour, whichever it is, so the doc states it.
5. **Manifest (decided Q-C, Ludwig, 2026-10-14).** The reader accepts a literal table with comments and nested tables
   and rejects, with a named message: a function call, string concatenation, `require`, a
   `dofile`, an unterminated string, and a file that does not `return` a table. `mod.lua` carrying
   kernel-only keys (`depends`, `permissions`, …) is accepted (they are ignored by projection);
   a missing required field, `id` ≠ entry id, and `version` ≠ version are each rejected separately.
6. **Licence (mission §7.1, "a non-OSI licence").** A manifest with `LicenseRef-Proprietary`, one
   with `NOASSERTION`, and one with an invented identifier are each rejected; `MIT` and
   `Apache-2.0` are accepted — the positive controls sit beside the hostile cases.
7. **Asset scan (mission §7.1, both Blizzard cases).** Over the *extracted tarball*: a file with
   DBC/MPQ/BLP/M2 magic bytes named `innocent.png` → exit 1 naming the format; a `.glb` whose
   embedded buffer carries a disallowed payload → exit 1. Built with
   `tests/validation/fixture_builder.py` where it supports the case. A clean mod (PNG, OGG, GLB,
   text) → accepted. The scanner's own exit 2 (e.g. pointed at a file) surfaces as this tool's
   exit 2.
8. **Reserved device names.** Namespace `com1` (and `AUX`, `Nul`) → exit 1 *before any output file
   exists* (asserted: the `--out` directory is empty afterwards); `comet` and `console` are accepted
   (positive controls: the rule is the whole name before the first `.`, not a prefix match).
9. **Signature, byte-exact against the contract and against the real tool.** With a throwaway key
   generated by the test (`minisign -G -W`): the produced `.minisig` has four lines; line 2 decodes
   to 74 bytes, line 4 to 64; the trusted comment equals exactly
   `format=1;id=<id>;version=<version>;sha256=<hex>`; `minisign -V` accepts it; and an
   **independent reference verifier written in this task** (stdlib only, implementing
   `signature-format.md` rejections 1-3, 5-11 and the `key_id` reversal; rejection 4's Ed25519
   check delegated to `minisign -V`) also accepts it. `key_id` in `result.json` equals the
   uppercase-hex, reversed form read from the public key's comment line — compared against the
   pubkey file, not recomputed from the same bytes by the same function.
10. **The verifier can fail (each its own check, §2c rule 3):** (a) one byte appended to the
    tarball; (b) trusted comment edited; (c) line 2's key-id bytes edited; (d) a **copied
    signature for a different `id`** (the contract's "signature reuse across identities" attack:
    valid signature, `evil:not-hello-world`); (e) trusted-comment `sha256` ≠ entry `source_sha256`;
    (f) a wrong pubkey. Each is rejected by the reference verifier with the rule number it violates.
    Ordering of fixes: the fixtures are written and shown failing *against a deliberately naive
    verifier* first (one that checks only "signature verifies the bytes"), and the naive verifier
    must accept (d) — proving the fixture catches what rule 11 exists for.
11. **No secret in any output.** The test puts a canary string in the environment variable the key
    would come from and as the content of the throwaway key's *comment*, and asserts the canary
    appears in none of: stdout, stderr, `build.log`, `result.json`, the tarball. Mutation: make the
    tool log its `--key` path's contents; the check must redden.
12. **Computed values.** `result.json`'s `artifact` holds `{source_sha256, signature, key_id}` and `built_at`:
    `source_sha256` equals the OS `sha256sum` of the tarball; `signature` is the four-line file verbatim with
    newlines preserved (`signature-format.md`, "What `entry.json`'s `signature` field holds"); `built_at` is
    RFC 3339 UTC and matches the pattern `entry.schema.json` gives `published_at`. `release_asset_url` is pinned by
    a test over the `artifact-naming.md` examples. (Everything that applies these to an entry —
    `apply_write_back`, the `pending → published` shape, `source_archive` — is task 008c.)
13. **Positive controls.** A clean first build, a clean second version of the same mod, and a mod
    carrying only text files all build and verify, beside the hostile cases.
14. **Mutation, fresh clone.** `008a-verify.sh` was mutation-tested (break the determinism flag
    `-n`, the `--prefix`, the reversal in `key_id`, the trusted-comment grammar, the symlink check;
    each reddens a named check) and run in a fresh clone; output pasted in the log.
15. **Docs move with code.** `docs/pipeline/build-pipeline.md` (new) states the CLI, exits, design
    decisions 1-7, and what is *not* verified (the not-verified list above); `docs/contracts/README.md`
    updated if the contract task left it stale. `docs/validation/` gains the manifest reader's
    description. [Read by the reviewer; not script-verified beyond a grep for each section heading.]

16. **Clone transport is restricted (hostile `source_url` fixtures).** Each of these is rejected with exit 1,
    naming the rule, **and no process is spawned that could run it** (asserted by a canary: a fixture whose
    `ext::` command would create a marker file, and the test asserts the file does not exist):
    `ext::sh -c 'touch <marker>'`, `file:///<local repo>` and a bare local path (both without
    `--allow-local-source`), `ssh://host/x`, `git://host/x`, `http://host/x`, scp-like `user@host:x`, and an
    `https://` URL carrying userinfo (`https://user:pw@host/x`; credentials in a stored URL are refused). Positive control: with
    `--allow-local-source`, the local fixture repo builds; an `https://` URL passes the scheme check (the
    clone itself is not attempted over the network — the test stops at the spawned command line, captured
    from a stub `git` earlier on `PATH`, and asserts `GIT_ALLOW_PROTOCOL=https` and the two `-c protocol.*` flags
    are present on it). Mutation: remove each of the three guards (scheme check, env var, `-c` flags) in
    turn; the check that only that guard satisfies must redden (the `ext::` canary needs the env-var/`-c` guards, so it is run
    with the tool's own scheme check bypassed in the mutation).
17. **Tarball hardening (each its own hand-built hostile tar, with a clean tar beside it as positive control).**
    Rejected whole, exit 1 naming the entry type and the limit: a hard-link entry; a character device; a block device;
    a FIFO; an entry of an unknown type; 10,001 entries; an uncompressed size over 200 MiB (built sparsely so
    the test does not write 200 MiB, e.g. a tar header declaring the size with a gzip stream that is small — the test
    asserts the tool refuses on the declared/streamed size without buffering it); a compressed tarball over 50 MiB
    (a stub size, since the limit is a constant the test may override downward and then asserts the
    default value separately). The three pre-existing escapes (`..`, absolute, escaping symlink) stay in
    criterion 4. Mutation: raise each limit to infinity and drop each type check; each reddens its named
    fixture. The log states the `archive-layout.md` silence cited in design 4 and links the sibling contract work.

## Explicitly OUT of scope
- GitHub Actions, releases, uploads, the write-back PR, secrets, the ownership carve-out, E15 — 008b.
- `apply_write_back`, `source_archive_url`, the `pending → published` shape and `result.json`'s write-back view — 008c (they need tasks 057 and 058).
- The `page.json` screenshot scan — task 040 (needs the archive this tool makes).
- Software Heritage (umbrella Q5). Binary/plugin signing (mission §2).

## File scope (declared; anything else = stop and report)
In the **registry** repo:
- `tools/pipeline/` (new) — the CLI, `release_asset_url`, the reference verifier
- `tools/validation/manifest.py` (new) — the Q-C restricted static reader and projection; `tools/validation/` otherwise untouched
- `tests/pipeline/` (new) — suite and fixtures (all keys are throwaway, generated at test time)
- `docs/pipeline/build-pipeline.md` (new), `docs/validation/manifest-reader.md` (new), `docs/contracts/README.md` (only if stale)
- `docs/tasks/008a-pipeline-core.md` (this file as log), `docs/tasks/008a-verify.sh` (new, executable)
Reading `contracts/` is expected; **editing** a contract is not in scope — a needed change is a
stop-and-report (§3.3) and belongs to the contract task.

## Forbidden here (beyond MANAGER.md §3.7)
- Any real key, any use of `MINISIGN_SECRET_KEY`, reading `~/wom-keys`, `~/.config/gh`, or any
  credential file (CLAUDE.md rule 11). Throwaway keys exist only in a temp directory the test
  creates and removes. A denied access is not retried; it is logged.
- `git clone` followed by a checkout of attacker content; running any code from the mod.
- Extension-based file typing anywhere (mission §5.2); skipping the GLB-internal scan.
- Hand-rolling Ed25519 verification or the hash prehash (delegate to `minisign -V`).
- Treating scanner exit 2 as a rejection, or any non-zero as "rejected" without reading which.
- Inventing semantics the contracts do not state (e.g. version monotonicity — `append-only.rules.md` rule 5).
- A verifier test that derives its expected bytes from the code under test (the project's
  signature failure, six times now).
- Editing `contracts/`, `reserved-namespaces.json`, or any other task's file.

## Dependencies and sequencing
- Needs: tasks 002 (scanner) and 006/025 (contracts) merged — they are. **Does not need task 057 or 058**
  (the split of 2026-10-14 exists to remove that dependency); Q-B, Q-C and Q-E are decided (Ludwig, 2026-10-14).
- Not blocked by 007/039. File overlap with 007: none (`tools/registry/` vs `tools/pipeline/`).
- Blocks 008b and **008c** (008c extends `tools/pipeline/` after this merges).

## Verification artefact (MANAGER.md §2c)
Declared: `docs/tasks/008a-verify.sh`; every criterion except 15's prose is command-based and
covered; the log pastes its output. Fix rounds, if any, add the found break as a fixture first.

## Deliverables
Code + tests + docs + verify script + this file's log section current.

## Questions  (agent-maintained; see MANAGER.md 8b)
- Q (A-3, SSRF; BOOKED FOR LUDWIG, 8b): an `https://` `source_url` may name an internal address (127.0.0.1, 10.x, 169.254.169.254). The tool does not filter addresses (a hostname check is bypassed by DNS rebinding, an address check by redirects). Options: A) leave it to 008b, where the clone runs in a job without the signing secret (docs/pipeline/build-pipeline.md, "SSRF note") * lean / B) add an IP-literal/localhost deny-list now (cheap, partial, gives false confidence) / C) clone through an egress-restricted runner. | assumed: A | built on: the SSRF note only; no code depends on it.
- Q: root directory literal `src/` vs `<name>-<version>/` | options: A) `src/` / B) per-version
  name | assumed: A (ADR-0103; archive-layout says any non-empty value is valid) | built on: criterion 4.
- (umbrella Q1/Q2 are decided: Q-B, Q-C, Ludwig 2026-10-14 — see `008-build-pipeline.md`; nothing in this file is built on an assumption about them any more.)

---
# Task 008a log  (append-only, updated continuously by the executing agent)
- 2026-10-14 spec written under task 054; nothing started.
- 2026-10-14 Q-B, Q-C, Q-E, Q-G folded in from Ludwig's answers; two URL functions replace `release_url`; URL shape waits on task 058.
- 2026-10-14 review fixes: split — `apply_write_back`, `source_archive_url`, the write-back view of `result.json` moved to 008c; clone restricted to https (hostile-URL fixtures, criterion 16); tarball hardening (criterion 17, `archive-layout.md` silence cited); criterion 2 states the commit comes from the entry and drops "uppercase" for `--version`.

## Spec amendment at the gate (manager, 2026-10-14; from spec review round 2, non-blocking items folded in as criteria)
- **A-1:** pass `--` before the URL to `git clone`. Add a fixture for a URL shaped like `--upload-pack=…` or `-u…`.
- **A-2:** give the clone a wall-clock timeout and a size cap. Isolate git config (`GIT_CONFIG_GLOBAL=/dev/null`,
  `GIT_CONFIG_NOSYSTEM=1`). Each gets a fixture or test.
- **A-3:** add tar fixtures for a symlink entry followed by a write through it (`src/l -> .`, then `src/l/x`), for
  duplicate entry names, and for setuid/setgid modes. Add a documented note on https URLs aimed at internal addresses
  (SSRF). The runner context decides whether it is in scope, and the spec records the answer.
- Merge authority: signing is involved, so **Ludwig approves the merge** (§7). The overnight waiver does not cover signing.

## Implementation log (implementer, 2026-10-15; head `97a675e`, then log-only commits)

Branch `task/008a-pipeline-core` in `~/wt/registry-008a`, from registry `4d4a204`. Not pushed.

### What was built (file scope held; `008a-verify.sh` checks it against the pinned base `4d4a204`)
- `tools/pipeline/`: `build_version.py` (CLI), `gitops.py` (clone/archive/gzip, transport rules, env), `procutil.py`
  (timeout + size-cap runner), `archive.py` (inspect-then-extract), `signing.py`, `reference_verify.py`, `naming.py`
  (tag, assets, reserved names, `release_asset_url`), `pipeline_errors.py`.
- `tools/validation/manifest.py` (Q-C static reader). Nothing else in `tools/validation/` touched.
- `tests/pipeline/` (114 checks + `mutate.py` with 47 mutations + `run_checks.py`), `docs/pipeline/build-pipeline.md`,
  `docs/validation/manifest-reader.md`, a pointer in `docs/contracts/README.md`, `docs/tasks/008a-verify.sh`.

### Decisions I made that the spec left open (flag for the reviewer)
1. **Compress from a named file, not a pipe.** `gzip -n -c source.tar`. I tested: GNU gzip reading **stdin** stores mtime 0
   even without `-n`, so the spec's "break `-n`" mutation would not redden a determinism check on a pipe. From a file, `-n` is
   load-bearing (name + mtime otherwise stored); the `gzip-without-n` mutation reddens two checks.
2. **Exit mapping of the A-2 bounds:** clone wall-clock timeout -> exit 2 (looks like an outage, not the author's fault);
   clone-size cap -> exit 1 (the repository is too big).
3. **Pre-flight rejections leave `--out` untouched** (criterion 8 demands an empty `--out` for reserved names; I applied the
   same rule to every rejection decidable before the clone and report them on stderr only). After the clone starts, a failure
   leaves `build.log` only.
4. **Rule 5 is also delegated to `minisign -V`.** The spec says the reference verifier implements rules 1-3 and 5-11 itself, but rule 5
   (global signature) is Ed25519 arithmetic, which the Forbidden list bars me from hand-rolling. minisign reports "Comment signature
   verification failed" separately, so the verifier maps that text to rule 5 and every other failure to rule 4.
5. **Extra rejections beyond the spec text:** empty/`.` path segments; a file/dir name conflict (`src/a` then `src/a/b`); entry
   beneath a symlink declared *later*; `--version`/`commit`/`id` matched with `fullmatch` (the validator's `re.search` lets `$`
   accept a trailing newline: fixtures `commit+"\n"` and `"1.0.0\n"`); more than one version object with the same version;
   `mod.lua` that is a symlink or over 1 MiB; the tool refuses to emit a signature its own reference verifier rejects (exit 2).
6. **Test-only CLI knobs** (hidden from `--help`): `--clone-timeout`, `--max-clone-bytes`, `--max-compressed-bytes`,
   `--max-uncompressed-bytes`, `--max-entries`, `--scanner`. Defaults are the documented constants; a test pins them.
7. **Hostile tars reach the real CLI** through a stub `git` earlier on PATH whose `archive` subcommand prints the hand-built tar;
   all other subcommands run real git. That is how every AC17/A-3 fixture gets an end-to-end exit 1.
8. `git archive`'s pax global header (type `g`) is skipped and not counted as an entry.

### Evidence per criterion (all produced by `docs/tasks/008a-verify.sh`, run in a FRESH CLONE at `97a675e`)
Fresh clone: `git clone --branch task/008a-pipeline-core ~/wt/registry-008a /tmp/wom008a-fresh-XXXX/clone`.
```
$ ./docs/tasks/008a-verify.sh            # rc=0
suite: 114 passed, 0 failed
ok    suite ran at least 100 checks (114)
ok    test_ac1_*: 5 passing, 0 failing        ok    test_ac10_*: 13 passing, 0 failing
ok    test_ac2_*: 6 passing, 0 failing        ok    test_ac11_*: 2 passing, 0 failing
ok    test_ac3_*: 2 passing, 0 failing        ok    test_ac12_*: 2 passing, 0 failing
ok    test_ac4_*: 11 passing, 0 failing       ok    test_ac13_*: 1 passing, 0 failing
ok    test_ac5_*: 21 passing, 0 failing       ok    test_ac16_*: 7 passing, 0 failing
ok    test_ac6_*: 1 passing, 0 failing        ok    test_ac17_*: 11 passing, 0 failing
ok    test_ac7_*: 5 passing, 0 failing        ok    test_a1_*: 2 / test_a2_*: 5 / test_a3_*: 7 passing, 0 failing
ok    test_ac8_*: 3 passing, 0 failing
ok    test_ac9_*: 6 passing, 0 failing
ok    every changed path is within the declared file scope
ok    untouched: contracts / reserved-namespaces.json / scan_assets.py / magic.py
ok    no wom008a-* temp dirs left behind by the suite
SUMMARY failed=0
$ ./docs/tasks/008a-verify.sh --mutate   # rc=0
MUTATION gzip-without-n: RED (good)  [test_ac3_two_builds_at_different_times_are_byte_identical=FAIL; test_ac3_gzip_header_carries_no_name_and_no_timestamp=FAIL]
MUTATION no-prefix: RED (good)  [test_ac4_every_entry_has_the_single_root_src=FAIL; test_ac1_exit_0_clean_build=FAIL]
MUTATION keyid-no-reversal-in-verifier: RED (good)  [...test_ac9_reference_verifier_accepts_it=FAIL...]
MUTATION trusted-comment-grammar: RED (good)  [...grammar=FAIL; ...reference_verifier_accepts_it=FAIL]
MUTATION symlink-check-off: RED (good)  [absolute=FAIL; dotdot=FAIL; entries_escaping=FAIL]
MUTATION scheme-check-off / env-allow-protocol-off / dash-c-protocol-flags-off / all-git-level-guards-off / no-double-dash /
         clone-timeout-off / clone-size-cap-off / git-config-isolation-off: all RED (good)
MUTATION uncompressed-limit-infinite / compressed-limit-infinite / entry-limit-infinite: RED (good)
MUTATION accept-hardlink / accept-chardev / accept-blockdev / accept-fifo / accept-unknown-type: RED (good), each its own fixture
MUTATION setuid-check-off / duplicate-check-off / write-through-check-off / dotdot-check-off / absolute-check-off / root-check-off: RED (good)
MUTATION verifier-rule-{6,7,8,9,10,11}-off, verifier-crypto-off, log-the-key-contents: RED (good)
MUTATION SUMMARY mutations=47 not_red=0
```
(The full 47 lines are in the verify output; the list above compresses names, not verdicts.)

Per criterion: AC1 `test_ac1_*` (0 / 1 / 2 each shown, 2 for missing `--key`, unreadable entry, clone failure); AC2 `test_ac2_*`
(branch-moved-on tarball holds `old.txt` not `new.txt`; absent commit names it; uppercase / short / `+"\n"` commit, bad / unknown
version all exit 1 with an empty workdir = no clone); AC3 `test_ac3_*` (1.2 s apart, byte-identical, `sha256sum` cross-check, gzip
header flags 0 and mtime 0); AC4 `test_ac4_*` (symlink absolute and `..` rejected whole citing `archive-layout.md`, `export-ignore` on
`mod.lua` -> "manifest missing in the produced archive" + the log lists the dropped path, `export-subst` **observed: `$Format:%H$`
becomes the commit hash, build accepted, log notes it**); AC5 21 checks (reader + CLI; `os.execute` in `mod.lua` never runs, canary
file absent); AC6 five licences incl. positive controls; AC7 DBC/MPQ/BLP/M2 named `innocent.png`, GLB with embedded BLP, clean PNG+OGG+GLB+text,
scanner exit 2 -> tool exit 2 (stub scanner and the real one pointed at a file); AC8 `com1 aux nul con prn lpt9 com0` rejected with `--out`
empty and workdir empty, `comet console com10 auxiliary` accepted; AC9 4 lines, 74/64 bytes, `ED`, comment equals the grammar built
from the OS `sha256sum`, `minisign -V` accepts, reference verifier accepts, `key_id` = pubkey comment line = reversed bytes (and the
unreversed form differs and is rule 6); AC10 a, b, b2, c, d, e1, e2, f1, f2 plus rules 1, 2, 3, 8 each in its own test with the exact rule number;
the deliberately naive verifier (in `test_signature.py`) **accepts (d), (e1), (e2)** — shown by the same tests, which call it before asserting
the reference verifier's rule 11 / 10 / 9 — and rejects a, b, c, f1 on cryptography alone; AC11 canary in
`MINISIGN_SECRET_KEY`, in the key file's comment line and the key payload line: absent from stdout, stderr, `build.log`, `result.json`, tarball
(and its decompressed tar), signature; failure path too; mutation `log-the-key-contents` reddens it; AC12 `result.json` fields, `built_at`
pattern, `signature` verbatim with 4 newlines, `release_asset_url` pinned to literals; AC13 first build, second version, text-only mod,
all re-verified by the reference verifier; AC14 above; AC15 `grep` of eight headings + seven design points + manifest-reader headings; AC16, AC17, A-1..A-3 as named.

### Honest notes on §2c rule 5 ("show each hostile fixture failing against a naive implementation first")
- For the **verifier**: done literally (naive verifier, fixture (d) accepted by it).
- For the **pipeline guards** I wrote the guards before the fixtures, so I could not show a fixture red "before" the fix in time order.
  The equivalent evidence is the mutation run: each guard is replaced by its naive form (check removed, limit infinite, type accepted,
  `--` dropped, ...) in a scratch copy of the committed tree and the named fixture goes red (47/47). One mutation was **initially not red**
  (`manifest-concat-allowed`): the concatenation is caught at two independent sites of the parser, so removing one did nothing; the
  mutation now removes both and is red. Another (`all-git-level-guards-off`) was initially NOT red because my `ext::` canary used shell quoting
  that git's ext helper does not honour (the shell got a mangled argument and never ran `touch`); the canary now uses git's `% ` escape
  (`ext::sh -c touch% <marker>`), which creates the marker when every guard is removed under a hostile `~/.gitconfig`, so that check is real.
- Removing exactly **one** of {env var, `-c` flags, config isolation} does not redden the behavioural `ext::` check (each alone suffices; belt and
  braces). The per-guard mutations are red through the checks that read the spawned command line and environment (stub `git` capture) instead.

### Open / not done / not verified
- Nothing touches the network. The https path is verified only up to the spawned command line. A live clone over https: not run (not needed by any criterion).
- All items in `docs/pipeline/build-pipeline.md`, "What is NOT verified" (minisign on a runner; process-substitution key under the CI shell; the legacy `Ed`
  variant; Windows reserved-name behaviour; git versions other than 2.53.0; the assumed limits).
- Q (SSRF) booked above for Ludwig. Merge authority: Ludwig approves the merge (signing involved, §7); an independent reviewer with full tools is required by the task.
- Temp dirs: every test dir is `wom008a-*` under `/tmp`, removed in `tearDownClass`; the verify script fails if any is left behind.
- 2026-10-15 manager:
  - Fresh-clone re-run at 96296ac: `008a-verify.sh` rc=0, `SUMMARY failed=0`. No .pyc tracked.
  - Independent security review (blind order): **PASS**, no blocking findings. `mutate.py`: 47 mutations, 0 not red.
  - Booked non-blocking findings:
    - (1) The test-only flags are gated by convention only, and `--clone-timeout nan` never times out. Reject
      non-finite values; 008c's workflow tests must assert the flags are absent.
    - (2) Case-collision and Unicode-normalisation of archive names belongs to the client task.
    - (5) Add mutations for killpg, the post-exit size recheck, O_NOFOLLOW and the extraction realpath guard.
    - (7) SSRF is handled by 008b's job split, per the implementer's lean. Ludwig's question is booked.
    - (8) Consumers must extract relative symlinks safely.
  - **Merge waits for Ludwig** (signing, §7).
- 2026-10-15 Ludwig, in session: "Stjärna på allt", which includes ★ merge 008a. Signing merge approved under §7.
  The SSRF policy is also decided: 008b clones in a job that holds no signing secret.
