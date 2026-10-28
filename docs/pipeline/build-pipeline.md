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

`--no-sign` (task 008b-2) builds without a key: `--key` and `--pubkey` are then not accepted (argparse error,
exit 2, before any clone), `--out` holds `<tag>.tar.gz`, `result.json` and `build.log` (no `.minisig`), and
`result.json` has `"signed": false` and no `artifact.signature` or `artifact.key_id`. See "The pipeline workflow".

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
| `bad-value` | a value fails its `entry.schema.json` pattern, or `signature` is empty. Patterns are matched as ECMA-262 does: full-match (a trailing newline fails) and ASCII-only digits (each unescaped `\d` in a schema pattern is translated to `[0-9]` when the pattern is loaded, so Arabic-Indic digits fail; `\s`/`\S` are left at Python's default, which is Unicode-aware like ECMA's, so U+00A0 and U+2028 fail `\S`; no global `re.ASCII` flag). `published_at` accepts what the schema pattern accepts: `YYYY-MM-DDThh:mm:ss`, an optional fraction (`.` and one or more digits), then `Z` or a `+hh:mm`/`-hh:mm` offset. The pattern checks shape only, not calendar validity (month 13 passes) |
| `bad-id` / `bad-version` / `reserved-namespace` | `source_archive_url` input is not a valid id, a semver string, or a Windows reserved device name |
| `entry-malformed` / `result-malformed` | the arguments are not objects of the expected shape |

### Not verified

- [unverified] Nothing here checks a hash against a tarball, nor that `source_archive` equals the derived
  URL (092 decision Q2, a separate CI task). `source_archive` is checked for shape only. Hash and
  signature verification before use is the E9 verifiers' job.

Tests: `tests/pipeline/test_write_back.py`; verification: `docs/tasks/008c-verify.sh` (and
`docs/tasks/008c-verify.sh --mutate`).

## The planner (task 008b-1)

`tools/pipeline/plan_pending.py` decides which versions the pipeline workflow builds. It is pure and
offline: the registry state, the branch list, the archive's log list and the dispatch inputs are all passed
in. It writes one **plan document** and nothing else; building, signing, releasing and opening PRs are other
tasks (008b-2, 008b-3b). Contract text: `contracts/pipeline-trigger.md` (PT4, PT5, PT6, PT9, PT12);
decisions: umbrella `008b-pipeline-workflow.md`, designs 2, 3 and 9.

```
python3 -I tools/pipeline/plan_pending.py --registry DIR --head-sha SHA --branches FILE --archive-logs FILE \
    [--dry-run true|false] [--version <namespace>.<name>@<semver>] \
    [--dry-run-source-url https://... --dry-run-commit <40 hex>] [--out FILE]
```

`--registry` is a checkout of `main` (it reads `mods/*/entry.json`); `--head-sha` is that checkout's SHA
(40 lowercase hex), logged on stderr and copied into the document. `--branches` lists the repository's
existing branches, `--archive-logs` the existing paths under `logs/` in `worldofmodcraft/archive`, one per
line, bare names (`pipeline/mc.a-1.0.0`, `logs/mc.a/1.0.0+b.1.log`). Both are required: an absent file is
an input error, never "nothing exists". The document goes to stdout (and to `--out` if given).

### The plan document

```json
{
  "head_sha": "<40 hex>",
  "build":  [ {"version_id": "mc.a@1.1.0", "entry_path": "mods/mc.a/entry.json", "kind": "build", "reason": ""} ],
  "refuse": [ {"version_id": "mc.a@2.0.0+b.1", "entry_path": "mods/mc.a/entry.json", "kind": "refuse",
               "reason": "<the 092 text>", "log_exists": false} ],
  "skip":   [ {"version_id": "mc.a@1.0.0", "entry_path": "mods/mc.a/entry.json", "kind": "skip",
               "reason": "pipeline/mc.a-1.0.0"} ],
  "fault":  [ {"version_id": null, "entry_path": "mods/bad.one/entry.json", "kind": "fault",
               "reason": "mods/bad.one/entry.json fails entry.schema.json: ..."} ]
}
```

Every `pending` version is on exactly one list; `published`, `removed` and `rejected` versions are on none.
Entries are ordered by entry directory, then by position in the entry. Every entry has exactly the four
fields `version_id`, `entry_path`, `kind`, `reason`; a `refuse` entry adds `log_exists` (boolean). `reason`
is empty for `build`, the exact 092 text for `refuse`, the branch name for `skip`, and the error for
`fault`. A `fault` is per entry file (`version_id` is `null`, except in a `version` dispatch, where it is the
requested id). This document is internal to node N5 and adds no edge to the dependency graph.

### Planner rules

- **Exit codes.** Exit 0 with the document whenever the inputs are well-formed, even if the plan has `skip`,
  `refuse` or `fault` entries. Exit 1 only for malformed or conflicting inputs or an unreadable state, and
  then no document is written (stdout is empty, `--out` is not touched). A skip or fault is never reported
  by a non-zero planner exit.
- **Input snapshot (PT4).** The state is `mods/*/entry.json` at the logged `main` head; never the push's
  `github.sha` or range. A `mods/` directory that does not exist is an empty registry (zero pending, exit 0).
- **What is listed (PT5).** With no `version` (a push, or a dispatch with an empty `version`) every `pending`
  version. With `version=<namespace>.<name>@<semver>` only that version, and only if it is `pending`;
  a malformed id, an absent entry, or a version that is absent or not `pending` exits 1. In that mode only
  that entry is read, so a fault in another entry does not matter.
- **Schema fault (C15, PT9).** An entry that fails `contracts/entry.schema.json` (also: not JSON, duplicate
  keys, `NaN`, an `id` that does not belong to its directory `mods/<namespace>.<name>/`, the same version
  twice, a `mods/<dir>/` without `entry.json`) is one `fault` entry naming the file. Nothing is built for
  any version of it and no T3 is opened. Other entries continue. Patterns are matched through
  `write_back`'s helpers (full match, ASCII-only `\d`); task 094 will move the pipeline to
  `tools/registry/schema.py`'s `ecma_pattern`, and the `\s` residual booked in task 008c applies here too.
- **Branch skip (C13, PT6).** A `pending` version whose `pipeline/<namespace>.<name>-<version>` branch exists
  is a `skip`, never built, and the skip applies before the `+` rule. It is not silent: see
  `summarize_outcomes` below.
- **`+` versions (092 Q10).** A `pending` version whose `version` contains `+` is a `refuse` with the reason
  "versions with build metadata (+) are not yet published — pending proof that GitHub resolves them (task 010)".
  A prerelease without `+` (`1.0.0-rc.1`) is built. `log_exists` is `true` iff
  `logs/<namespace>.<name>/<version>.log` is in the `--archive-logs` list: if the refusal log was committed
  and the T3 PR then failed, the next plan carries `log_exists: true` and 008b-3b re-opens only the T3 PR
  (it neither recommits the log nor faults). Neither value is a fault.
- **Dry-run inputs (PT12, Q-M option A).** `--dry-run` is `true`, `false` or empty. A dry run needs exactly
  one source: a `version` (planned as above), or the pair `--dry-run-source-url` (`https://`, printable
  ASCII) plus `--dry-run-commit` (40 lowercase hex). The pair is accepted only together, only with
  `--dry-run true`, and only with `version` empty. Anything else exits 1. With the pair the plan is empty
  (all four lists empty): the synthetic in-run entry is built by 008b-2's dry-run job, not read from `main`.

### Ending the run: `summarize_outcomes(plan, outcomes)`

A pure function in the same module, called by 008b-2's `summary` job. `outcomes` is a list of
`{"version_id": ..., "exit_class": 0|1|2}`, one per built version. It returns `(green, message)`. The run
is non-green if the plan has a `skip` entry, a `fault` entry, a built version whose outcome is exit class 2
(a pipeline fault, PT5), or a `build` entry with no reported outcome; the message names every one of them.
Exit class 1 (a 008a verdict, handled by its T3) and `refuse` entries alone leave the run green. A malformed
outcome list (unknown exit class, duplicate or stray version id) raises `ValueError`.

### Recovering a skipped version

A `skip` means an earlier run's write-back PR is still open, or an earlier run died after pushing the branch
(PT8). Nothing is built for it and the run ends non-green naming it. Recovery is manual: close its PR, delete
its `pipeline/` branch, then dispatch the workflow (with `version=<namespace>.<name>@<semver>`, or with an
empty `version` to plan every pending version).

Tests: `tests/pipeline/test_plan_pending.py`; verification: `docs/tasks/008b1-verify.sh` (and
`docs/tasks/008b1-verify.sh --mutate`).

## The pipeline workflow (task 008b-2)

`.github/workflows/pipeline.yml` runs the planner, builds, signs and dry-runs; task 008b-3b adds the write-back
job. Contract: `contracts/pipeline-trigger.md` (PT1-PT12); design: umbrella `008b-pipeline-workflow.md`, designs
1, 6, 8, 9. Tests: `tests/pipeline/test_handoff.py`; verification: `docs/tasks/008b2-verify.sh` (and `--mutate`).

**Push gate.** Until write-back exists every job has `github.event_name != 'push'` in its `if:`, so a push to
`main` starts a run whose jobs are all skipped; only `workflow_dispatch` does anything. The trigger block itself
is the contract's. 008b-3b removes the gate.

| Job | Holds | Does |
|---|---|---|
| `plan` | nothing (`contents: read`) | checks out `main` (the SHA is logged, PT4), asserts the checkout is complete (below), collects the `pipeline/*` branches and the archive's `logs/` paths, runs `plan_pending.py`, uploads artifact `plan`, outputs `head_sha`, `has_build`, `has_writeback`, `matrix` (`handoff.plan_flags`, `handoff.plan_matrix`) |
| `build` | **no secret**, `contents: read` | one matrix leg per `build` entry, `fail-fast: false` (PT5): `build_version.py --no-sign`, stderr captured, `handoff.finish_build`, artifact `build-<tag>` |
| `sign` | `MINISIGN_SECRET_KEY` under `environment: signing`, only on `github.ref == 'refs/heads/main'` | per leg: downloads `build-<tag>`, guard (`outcome.json` `exit_code == 0`, else the leg does nothing), installs minisign, writes the key to a `0600` file in one step and removes it, runs `sign_built.py`, `handoff.finish_sign`, artifact `signed-<tag>`. Never clones, never runs the build tool |
| `dry-run` | nothing, **no environment** | `dry_run=true` only: same legs, signs with an ephemeral key generated in the run and deleted, uploads `dryrun-<tag>` (with `build.log`) and fails unless the version built and signed |
| `summary` | nothing | `always() && github.event_name != 'push'`; fails if `plan` failed, else `handoff.py summarize` calls `plan_pending.summarize_outcomes` with one outcome per built version |

Inputs (`dry_run`, `version`, `dry_run_source_url`, `dry_run_commit`, and for the source pair also `dry_run_id`,
`dry_run_version`) reach scripts only through `env:`. **The source pair needs the mod's id and version**: 008a
cross-checks them against `mod.lua`, and the synthetic in-run entry (`handoff.synthetic_entry`, never written to
`main`) cannot know them, so the two extra inputs carry them (assumption, question Q-D of the task file).

### Handoff layout (read by 008b-3b through `handoff.read_outcomes` only)

- `plan`: the planner's JSON. `refuse`, `skip` and `fault` entries get no build leg; the write-back job reads them here.
- `build-<tag>`, uploaded by the leg whatever its exit code: `outcome.json`, `build.stderr`, and for exit 0
  `<tag>.tar.gz`, `result.json` (`signed: false`), `build.log`; for exit 1 and 2 `build.log` only if the build had started.
- `signed-<tag>`, only for exit-0 legs: `<tag>.tar.gz`, `<tag>.tar.gz.minisig`, `result.json` (`signed: true`,
  `artifact.signature`, `artifact.key_id`), `outcome.json` unchanged. If signing fails the artifact holds
  `outcome.json` alone with `exit_code` 2.
- `outcome.json`: `version_id`, `tag`, `exit_code` (0 built, 1 rejected by 008a, 2 pipeline fault), `reason`.
  For exit 1, `reason` is 008a's `REJECTED [rule]: message -- remedy: remedy` line without `REJECTED `, from
  `build.stderr` else the last `result: exit 1 ` line of `build.log`, whitespace collapsed; empty after trimming means
  exit 2. Empty for exit 0 and 2. Any other build exit code, or an exit 0 without tarball and `result.json`, is 2.
- `read_outcomes(dir, require_signed=False)`: one entry per tag, `signed-<tag>` overriding `build-<tag>`; with
  `require_signed=True` (the non-dry-run reading) a built version without `signed-<tag>` is exit 2.
- A plan `build` entry with no artifact at all (a killed leg) is exit 2 for the summary (no outcome reported) and
  must be treated so by 008b-3b.

Job conditions: `build` runs only if `has_build` (so GitHub is never given an empty matrix); `sign` has
`always()` so one failed leg does not skip it; the write-back job (008b-3b) uses `has_writeback`. Zero pending
versions give both false and a green run that wrote nothing.

### `sign_built.py`

`python3 tools/pipeline/sign_built.py --tarball T --result R --key K --pubkey P --out DIR`. The build job cloned an
author-controlled URL, so before signing the tarball is re-checked from its own bytes: compressed size, entry
rules and sizes (`archive.inspect_archive`, 008a's limits), `sha256 == result.json artifact.source_sha256`, naming
and the trusted-comment grammar; then it signs the checked copy and the signature must pass `reference_verify`.
Exit 0 signed; 1 refused (`REFUSED [rule]: ...`); 2 pipeline error. The handoff maps both 1 and 2 to outcome
`exit_code` 2: only 008a's own exit 1 is a rejection of the author's version.

### Failure modes

| What happens | Result |
|---|---|
| 008a rejects (exit 1) | `build-<tag>` with `exit_code` 1 and `reason`; no signing; summary stays green for it (008b-3b opens the T3) |
| 008a pipeline fault (exit 2), clone failure, killed leg | `exit_code` 2 or no artifact; the leg fails; the summary is non-green naming it |
| sign step refuses or errors | `signed-<tag>` with `exit_code` 2, no signature; the leg and the summary are red |
| entry fails the schema, branch exists, plan skip | no leg; `plan` artifact; the summary is non-green (008b-1) |
| plan job fails (bad inputs, broken checkout, archive clone fails) | everything else is skipped; the summary fails first |
| minisign download pin empty | the install step fails closed (question Q-S) |

**Broken or sparse checkout (008b-1 review F2).** The planner reads `mods/*/entry.json`; a checkout that lost them
would look like an empty registry. `handoff.py check-checkout` fails the plan job if `mods/` is missing while git
tracks files under it, or any tracked file under `mods/` is absent on disk.

**Not verified (no workflow has run here):** the pinned `upload-artifact` and `download-artifact` SHAs match their
tags (copied from other files on the dev machine); multi-path uploads land at the artifact root (least common
ancestor); a `pattern:` download with no match does not fail; `matrix` from `fromJSON` with only `include`;
`ubuntu-latest` can run the minisign 0.12 static binary; the `signing` environment mechanics (runbook M11);
that the archive repository is public for the anonymous clone in `plan`.
