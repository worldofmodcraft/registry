# Build pipeline core (task 008a)

`tools/pipeline/build_version.py` builds **one** registry version, offline, from nothing but a git
repository, a 40-hex commit and a key *file*: a deterministic `.tar.gz` with a single rooted
directory, its SHA-256, a minisign detached signature, the release tag and two asset names, and a
`result.json`. It is node **N5** of the dependency graph; it touches edges E1 (the `mod.lua`
manifest, via `tools/validation/manifest.py`), E5/E6 (the asset scanner), E7 (naming), E8 (the
computed object only) and E9 (signing). Turning the result into a registry write-back, the
`source_archive` URL, the GitHub workflow, uploads and secrets are tasks 008b and 008c, not this one.
Nothing here touches the network (except `git clone` of the author's public https URL when a real
build is run), GitHub, or a real key.

## CLI

```
python3 tools/pipeline/build_version.py --entry <entry.json> --version <semver> \
    --workdir <empty dir> --key <minisign secret key file> --pubkey <public key file> \
    --out <dir> [--allow-local-source]
```

The commit and the source URL are read from the entry: the tool selects the version object whose
`version` equals `--version` and uses *that object's* `commit` and `source_url`. There is no commit
argument, so there is one source of truth. `--key` is a **path**; key bytes never appear on a command
line and the tool never reads or logs the file (it hands the path to `minisign`).
`--allow-local-source` is for tests only (it admits `file://` URLs and local paths); the workflow
never passes it. Further flags (`--clone-timeout`, `--max-clone-bytes`, `--max-compressed-bytes`,
`--max-uncompressed-bytes`, `--max-entries`, `--scanner`) are hidden test knobs whose defaults are the
constants below; tests only ever lower them.

### Exit codes

| Code | Meaning | Examples |
|---|---|---|
| **0** | built | |
| **1** | **rejected**: the version is bad. The message on stderr is `REJECTED [rule]: ... -- remedy: ...` naming the rule or contract clause and what to do. | non-OSI licence, Blizzard magic bytes, symlink escape, reserved device name, commit not in the repository, oversized repository |
| **2** | **usage or internal error**: not a statement about the version. | missing `--key`, unreadable `--entry`, `minisign` not installed, clone failure, clone timeout, asset scanner exit 2, a `--key` that is not the secret half of `--pubkey` |

1 and 2 are never conflated. The asset scanner has the same split (0 accept, 1 reject, 2 usage); the
scanner's 2 surfaces as this tool's 2.

### Outputs (`--out`)

`<tag>.tar.gz`, `<tag>.tar.gz.minisig` (names per `contracts/artifact-naming.md`), `result.json`,
`build.log`. `--out` must not exist or must be empty. Rejections found **before any clone**
(entry, namespace, version, commit and URL checks) leave `--out` untouched and report on stderr only.
A rejection or error after the build started leaves `build.log` (only) behind, so the reason can be
posted.

`result.json`: `id`, `version`, `tag`, `assets {tarball, signature}`, `built_at` (RFC 3339 UTC, the
same pattern as `published_at`), `artifact {source_sha256, signature, key_id}` and `scan` (the
validation-report object). `artifact.signature` is the four-line signature file verbatim, newlines
preserved (`contracts/signature-format.md`, "What `entry.json`'s `signature` field holds").
`naming.release_asset_url(owner, repo, tag, asset)` is the one pure function for the upload step:
`https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>`; the repository (decision Q-E:
`worldofmodcraft/archive`) is a value passed in, not hard-coded.

## Design decisions (spec 008a, 1-7)

1. **Fetch without checkout; https only.** `git clone --no-checkout --no-tags --template=<empty> -- <url> <dir>`,
   then `git cat-file -e <commit>^{commit}`, then `git archive` straight from the object database.
   No working tree is ever checked out, so no smudge/clean filters, no LFS and no hooks (hooks are
   not cloned) run on attacker content. Submodules are not followed. The commit must be reachable
   from a ref that `clone` fetches. Transport: only `https://`. Every git invocation runs with an
   explicit whitelisted environment (`GIT_ALLOW_PROTOCOL=https`, `GIT_TERMINAL_PROMPT=0`,
   `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, `GIT_NO_REPLACE_OBJECTS=1`) and
   `-c protocol.ext.allow=never -c protocol.file.allow=never`; the tool also rejects any other scheme
   *before spawning git*, naming the rule and the remedy. Rejected without any process: `ext::`,
   `file://`, bare paths, `ssh://`, `git://`, `http://`, scp-like `user@host:path`, anything starting
   with `-`, anything containing whitespace/control characters, and `https://` with userinfo
   (credentials in a stored URL are refused; the password is never echoed). With
   `--allow-local-source`, `GIT_ALLOW_PROTOCOL=file` and `protocol.file.allow=always` apply to that
   process only. *Reading, not verified:* ADR-0058 section 4's "any host" is read as any *host*, not
   any *transport* (it does not mention `ssh`/`git://`).
   **A-1:** `--` precedes the URL on the `git clone` command line.
   **A-2:** the clone has a wall-clock timeout (`CLONE_TIMEOUT_S` = 300 s; exit 2 when it fires) and a
   size cap on the clone directory (`MAX_CLONE_BYTES` = 512 MiB; exit 1 when it fires), enforced by
   polling and killing the whole process group. Both constants are assumptions, as are the three
   archive limits below.
2. **Tarball.** `git archive --format=tar --prefix=src/ <commit>` to a file, then `gzip -n -c`. The
   root literal is `src/` (ADR-0103: one fixed boring literal; `contracts/archive-layout.md` leaves
   the value open). Compressing from a *named file* with `-n` is deliberate: without `-n` gzip stores
   the file name and mtime, so two builds differ; with it, equal input gives equal bytes.
3. **Scan the tarball, not the clone.** The manifest read and the asset scan run on the contents
   *extracted from the produced tarball*, because that is what users and the site receive.
   `.gitattributes` `export-ignore` can hide a file from the tarball but not from the clone: a
   manifest hidden that way is rejected as "manifest missing in the produced archive", and the log
   lists the paths the archive dropped. `export-subst` is applied by `git archive`; the expanded
   archive is what is scanned and signed (observed: `$Format:%H$` becomes the commit hash, the
   build is accepted, and the log notes it).
4. **Extraction is hostile-input safe.** Two phases: `archive.inspect_archive` walks every tar header
   and rejects the **whole** archive on the first violation, then `archive.extract` writes the
   validated plan (regular files via `O_EXCL|O_NOFOLLOW` with modes the tool chooses, symlinks last).
   Rejected: a `..` segment anywhere; an absolute name; an entry outside the single root; a
   symlink target that is absolute or contains `..`; (added here, because the contract is silent on
   them) a hard link, character or block device, FIFO or any other entry type; setuid/setgid/sticky
   mode bits; duplicate names; a path written *through* a symlink (`src/l -> .` then `src/l/x`) and a
   file/directory name conflict; empty or `.` path segments; more than **10,000 entries**; a declared
   uncompressed size above **200 MiB** (judged from the tar headers before any data is read, so a
   header declaring 300 MiB is refused without buffering it; the decompressed stream position is
   also capped); a compressed tarball above **50 MiB**. The 50 MiB figure matches the site
   downloader's ceiling (task 055); the three limits are this spec's assumed constants in
   `tools/pipeline/archive.py` (`MAX_UNCOMPRESSED_BYTES`, `MAX_COMPRESSED_BYTES`, `MAX_ENTRIES`).
   **The contract is silent on these.** `grep -n -i -E 'hardlink|hard link|device|fifo|special|size|limit|count' contracts/archive-layout.md`
   matches only line 150 ("accounted"), line 179 ("encountered") and line 232 ("README.md counts"):
   none concerns hard links, devices, FIFOs, special modes, sizes or counts. `git archive` itself cannot
   emit hard links, devices or FIFOs (git's object model stores neither; *stated from git's design,
   not verified here*), so these checks are defence in depth over a tarball the tool did not
   hand-build; the fixtures hand-build the hostile tars. The same gap exists in the site's
   extractor; amending `archive-layout.md` is the sibling contract work, not this task.
5. **Manifest.** `mod.lua` is read by the restricted static reader (`docs/validation/manifest-reader.md`);
   the file is never executed. The eleven schema fields are projected and validated against
   `manifest.schema.json`; `manifest.id` must equal the entry id and `manifest.version` the version
   (both named in the schema as "pipeline logic"). Licence validity is the schema's OSI enum:
   `LicenseRef-*`, `NOASSERTION` and invented identifiers are rejected (`manifest/license-not-osi`).
   Patterns for `commit`, `version` and `id` are matched with `fullmatch` because the schema
   validator's `re.search` lets `$` accept a trailing newline.
6. **Key handling.** The tool takes a *path* (`--key`), passes it to `minisign -S -s`, and never reads,
   prints or logs it. `minisign` is run with a minimal environment (`PATH`, `LC_ALL`); the caller's
   environment, including any secret-bearing variable, is not forwarded. The finished signature is
   verified by `minisign -V` against `--pubkey` and by the independent reference verifier
   (`tools/pipeline/reference_verify.py`) before anything is written. In CI the path is a process
   substitution or a 0600 file under a temp directory removed on exit (008b chooses).
7. **Name safety.** The namespace is checked against the Windows reserved device names
   (`CON PRN AUX NUL COM0-9 LPT0-9`, case-insensitive, whole namespace) before any tag or file name
   is built, and before `--out` is touched. `comet`, `console` and `com10` are accepted: the rule
   is the whole name before the first `.`, not a prefix match.

## The reference verifier

`tools/pipeline/reference_verify.py` re-implements the eleven rejections of
`contracts/signature-format.md` independently of the signing code (it derives the key id by
reversing the 8 bytes itself). It does **not** hand-roll Ed25519 or the BLAKE2b prehash: rules 4 and
5 are delegated to `minisign -V`, whose error text separates them ("Comment signature verification
failed" is rule 5, any other failure rule 4). Order: 1, 2, 3, 6, 7, 8, then 4/5, then 9, 10, 11.
The `minisign -V` call uses the public key file named by the entry's `key_id`, never "try every
key". The tests carry a deliberately naive verifier (signature verifies the bytes, nothing else)
and show that it accepts the copied-signature attack (rule 11) that this verifier rejects.

## SSRF note (spec amendment A-3)

An `https://` `source_url` may name an internal address (`https://10.0.0.5/x`,
`https://169.254.169.254/...`, a hostname resolving to loopback). `git clone` would issue a GET to
`<url>/info/refs?service=git-upload-pack` from the build host. The tool does **not** filter
addresses: a hostname check is bypassed by DNS rebinding and an address check by redirects, so a
partial filter would manufacture confidence. **Recorded answer:** whether this is in scope depends on
where the pipeline runs; that is 008b's decision (GitHub-hosted ephemeral runners expose a link-local
metadata endpoint and no internal services of ours, but they hold the signing secret, so the clone
must run in a step or job that does not have it, or in a job without network access to
non-public ranges). This is booked as a question for Ludwig in the task file, not decided here.
What the tool does guarantee: only the git smart-HTTP exchange is attempted, git's error text (which
may reveal a status code) goes to `build.log`, and the clone is time- and size-bounded.

## What is NOT verified

- That minisign can be installed on a GitHub-hosted runner. The only known-good route is the pinned
  static binary used in M3 (`docs/runbooks/site-v1-manual-steps.md`) with its checksum checked; apt
  availability is untested. (008b.)
- That the process-substitution key route (`minisign -S -s <(cat key)`) works under the CI runner's
  shell. It exited 0 on the authoring machine only. (008b.)
- The legacy `Ed` (non-prehashed, `minisign -l`) signature variant. Only `ED`, minisign 0.12's
  default, was exercised against the real tool; the reference verifier accepts both by contract but
  `Ed` was not produced.
- The Windows reserved-device-name behaviour (case-insensitivity, before-first-`.` scope, exact list)
  is stated from `artifact-naming.md`, not exercised on Windows. The rule is enforced regardless.
- That `git archive` cannot emit hard links, devices or FIFOs (stated from git's object model).
- That ADR-0058 section 4's "any host" permits restricting the transport to https (a reading).
- The three archive limits and the clone timeout/size are assumed constants (no ADR states them).
- A live clone over https: no test touches the network; the https path is verified up to the spawned
  command line (a stub `git` captures it).
- Behaviour on git versions other than 2.53.0 (the protocol flags and `GIT_ALLOW_PROTOCOL` are
  long-standing git features, but only this version was run).

## Tests and verification

`docs/tasks/008a-verify.sh` runs the suite (`tests/pipeline/`, stdlib `unittest`, one `CHECK` line
per test) and the structural checks; `docs/tasks/008a-verify.sh --mutate` breaks each guard in a
scratch copy and requires the named check to turn red. All keys are throwaway, generated at test
time in a temp directory (`wom008a-*`) and removed afterwards.

## Write-back (task 008c)

`tools/pipeline/write_back.py` turns a `build_version.py` `result.json` into the registry's
`pending -> published` write-back (transition T1, ADR-0121; edge E8). It is pure: no network, no
subprocess, no key material, no clock (the timestamp is the build's own `built_at`). It does not open,
commit or merge anything; who may commit its output is task 008b plus the ownership carve-out.

### What is computed

- `write_back_values(result, source_archive)` returns exactly five keys: `source_archive` (the argument,
  passed through), `source_sha256`, `signature` and `key_id` (from `result.artifact`) and `published_at`
  (= `result.built_at`; it must match `entry.schema.json`'s `published_at` pattern, see the `bad-value` row below).
- `source_archive_url(namespace, name, version)` returns
  `https://archive.worldofmodcraft.com/<tag>/<tag>.tar.gz` with `tag` = `naming.release_tag(...)`. The
  host is the single constant `ARCHIVE_HOST`, whose value comes from `contracts/artifact-naming.md`
  ("The archived-source URL"). `+` is written literally. A version with build metadata still yields a
  URL; holding such versions back is 008b's (092 decision Q10).
- `apply_write_back(entry, result, source_archive)` returns a **new** entry in which the one version equal
  to `result.version` has the five values added and `status` set to `published`. Nothing else changes;
  `commit` and every other existing field are never taken from `result`. Inputs are never mutated.

### What is refused

Every refusal raises `WriteBackRefused` (a `PipelineError`: the pipeline is inconsistent, exit 2, never
a PR rejection) with a `reason`:

| reason | when |
|---|---|
| `id-mismatch` | `result.id` differs from the entry's `id` |
| `version-absent` / `version-duplicate` | no version, or more than one, equals `result.version` |
| `not-pending` | the version is `published`, `removed` or `rejected` |
| `pending-shape` | the target `pending` version does not have exactly the four pending keys `version`, `commit`, `source_url`, `status` (`contracts/append-only.rules.md` key-set table; `entry.schema.json`'s `pending` branch): a stray key such as `reason`, or an already-present write-back key such as `source_archive`, is refused before anything is written |
| `result-missing-field` | `result` lacks `artifact.source_sha256`, `artifact.signature`, `artifact.key_id` or `built_at` |
| `key-set` | the computed values do not have exactly the five keys |
| `bad-value` | a value fails its `entry.schema.json` pattern, or `signature` is empty. Patterns are matched as ECMA-262 does: full-match (a trailing newline fails) and ASCII-only digits (`\d` is `[0-9]`, so Arabic-Indic digits fail). `published_at` accepts what the schema pattern accepts: `YYYY-MM-DDThh:mm:ss`, an optional fraction (`.` and one or more digits), then `Z` or a `+hh:mm`/`-hh:mm` offset. The pattern checks shape only, not calendar validity (month 13 passes) |
| `bad-id` / `bad-version` / `reserved-namespace` | `source_archive_url` input is not a valid id, a semver string, or a Windows reserved device name |
| `entry-malformed` / `result-malformed` | the arguments are not objects of the expected shape |

### Not verified

- [unverified] Nothing here checks a hash against a tarball, nor that `source_archive` equals the derived
  URL (092 decision Q2, a separate CI task). `source_archive` is checked for shape only. Hash and
  signature verification before use is the E9 verifiers' job.

Tests: `tests/pipeline/test_write_back.py`; verification: `docs/tasks/008c-verify.sh` (and
`docs/tasks/008c-verify.sh --mutate`).
