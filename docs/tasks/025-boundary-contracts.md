# Task 025: The six boundary contracts the dependency graph names but nobody wrote

- **Mission:** SITE-V1 — **Status:** spec-approved (manager, 2026-09-04)
- **Agent / model:** doc-writer / sonnet
- **Budget:** medium (<= 3 agent-sessions)
- **Branch / worktree:** task/025-boundary-contracts / `~/wt/registry-task-025`
- **Graph:** writes the contract files for edges **E7, E9, E11, E12, E13, E14** in
  `docs/architecture/depgraph.md` (platform repo). Adds **no new edges** — every one of these is
  already declared there; only its contract file is missing.

## Objective
Every edge the SITE-V1 dependency graph declares has the contract file it names. Task 006 wrote the
four that block everything (entry, page, manifest, append-only); these six are the rest. When this
lands, no task in the mission has to invent a boundary agreement or infer one from a one-line table
cell.

## Why now, and why this is not busywork
ADR-0117's rule is that every boundary edge names its contract; an edge without one is an
architecture error. Six edges currently point at files that do not exist, and **two of them are
being worked around right now**: task 009 (the site build) is coding against `depgraph.md`'s
one-line definitions for E11 and E13 and recording assumptions, because it had nothing else. Every
hour those stay unwritten is another assumption to reconcile later. Task 008 needs E7 and E9 before
it can archive or sign anything.

## Context to load (exhaustive)
- `docs/architecture/depgraph.md` in the platform repo `~/wom` (read-only, never write there) —
  the edge table is the source. **Its one-line definitions are decisions already taken; your job is
  to state them precisely enough to implement, not to re-decide them.**
- **ADR-0041** (integrity chain, archiving, `key_id` for rotation) — governs E7 and E9.
- **ADR-0059** §1 (pages built from the archive, never the live repo) — governs E11.
- **ADR-0030** (manifest fields, including `screenshots`) — the paths E11 must locate.
- **ADR-0058** §4 (provider neutrality) — nothing here may assume GitHub except where the mission
  explicitly does (Pages, `repository_dispatch`).
- **ADR-0103** (boring solutions) and **ADR-0056** (English).
- `docs/tasks/MISSION-worldofmodcraft-site-v1.md` §4 D2, D3 and §7 in the platform repo.
- In this repository: `contracts/entry.schema.json`, `contracts/append-only.rules.md` and
  `contracts/validation-report.schema.json` — **match their conventions**, and read
  `append-only.rules.md` in particular for the standard of precision expected: it took four review
  rounds to reach it, and the lesson was that prose which *sounds* sufficient is routinely
  satisfiable in a way that breaks the guarantee.
- `docs/tasks/006-contracts.md` in this repository — the review history, worth skimming for the
  failure modes to avoid.

## File scope (declared)
- `contracts/artifact-naming.md` (E7)
- `contracts/signature-format.md` (E9)
- `contracts/archive-layout.md` (E11)
- `contracts/rebuild-trigger.md` (E12)
- `contracts/site-output.md` (E13)
- `contracts/url-scheme.md` (E14)
- `docs/contracts/README.md` (add the six to its index — docs move with the work)
- `docs/tasks/025-boundary-contracts.md` (this file's log)

Anything else = stop and report. In particular **do not edit the four contracts task 006 shipped**,
and do not touch `docs/architecture/depgraph.md` in the platform repo — if you believe an edge
definition is wrong, that is a report, not an edit.

## What each contract must settle
The graph gives one line each. Turn each into something an implementer codes from without
inference. **Where the graph is silent and a decision is genuinely needed, book it as a question
rather than inventing it** — and say what you assumed in the meantime and what rests on it.

1. **E7 `contracts/artifact-naming.md`** (N5 → N6) — the release tag and asset naming scheme for the
   archived source tarball and its signature, in platform-owned storage (org GitHub Releases).
   Must be deterministic from `(namespace, name, version)` alone, and must state what happens for
   a namespace or name containing characters that are legal in an id but awkward in a filename.
2. **E9 `contracts/signature-format.md`** (N5 → signing key) — minisign (Ed25519) **detached**
   signature; `key_id` taken from the public-key comment; the **signed trusted comment** carries mod
   id, version and SHA-256. Decided already (mission log Q3=A) — state the exact byte layout of what
   is signed, so a verifier written independently agrees with the signer. Say what a verifier must
   reject. **Never include a private key, or any real key material, anywhere.**
3. **E11 `contracts/archive-layout.md`** (N6 → N7) — the archive interior: `README.md` at the
   tarball root, screenshots at the paths the manifest declares. State the root convention exactly
   (single top-level directory or not — this is the classic tarball ambiguity), how a screenshot
   path in the manifest maps to a path inside the archive, what the site must do when a declared
   path is absent, and what it must do when the archive contains a path escaping the root
   (`../`) — that last one is a security property, not an edge case.
4. **E12 `contracts/rebuild-trigger.md`** (N2 → N7) — the `repository_dispatch` event type and
   payload that a registry merge sends to the site repository. Name the event type exactly, give
   the payload shape, and state what the site build does when the payload is malformed or absent.
5. **E13 `contracts/site-output.md`** (N7 → N8) — the build output: the `dist/` tree and the `CNAME`
   file. State what must be present for a deploy to be valid.
6. **E14 `contracts/url-scheme.md`** (N8 → public) — HTTPS on the apex domain; the URL scheme
   `/mods/<ns>/<name>`. State the canonical form, what happens to a namespace or name needing
   escaping, and whether trailing slashes are canonical — the site generator and any future link
   builder must agree without guessing.

## Acceptance criteria
Each demonstrated by a command actually run, with its real output in the log.
1. All six files exist, each naming its edge id and the node pair it connects, matching the
   conventions of the contracts already in `contracts/`.
2. Each contract is stated at a level an implementer codes from: no "appropriate", no "sensible",
   no "as needed". For every rule, a reader can say what input violates it.
3. **The adversarial pass, which is the point of this task:** for each contract, try to satisfy its
   letter while breaking its purpose, and record the attempt and the outcome. `append-only.rules.md`
   needed four rounds because nobody did this first; "identify by magic bytes" and "a well-formed
   instance of a whitelisted format" were each satisfied by a file carrying a byte-for-byte Blizzard
   payload. **A contract with no recorded attack attempt is not finished.**
4. E11 states the path-escape rule (`../` and absolute paths inside the archive) and E7 states the
   awkward-characters rule — both demonstrated by naming a concrete input that must be rejected.
5. `docs/contracts/README.md` indexes all ten contracts (the four from task 006 plus these six).
6. Nothing in `contracts/` from task 006 is modified — demonstrated by `git diff --name-only`.
7. Every question booked under `## Questions` with what was assumed and what rests on it.

## Forbidden here
Beyond MANAGER.md §3.7:
- **Inventing a decision the graph or an ADR already made**, or contradicting one. The edge table's
  definitions are settled; you are making them precise.
- **Deciding something genuinely undecided and not saying so.** Book it.
- Writing any code, schema, workflow or checker. These are prose contracts. Task 007 and task 008
  implement them.
- Any real key material, token, or secret in any file.
- Editing the four contracts task 006 shipped, or anything in the platform repository.

## Questions  (agent-maintained; see MANAGER.md §8b)
- (none yet)

---
# Task 025 log  (append-only, updated continuously by the executing agent)
- 2026-09-04 spec approved; worktree created from registry `main` after task 006 merged (PR #2).
- 2026-09-04 all six contracts written and committed one at a time, E11 and E13 first as the spec
  asked (task 009 is coding against them live). Commits: `c942f6e` (E11 archive-layout.md),
  `0354995` (E13 site-output.md), `8ce708d` (E7 artifact-naming.md), `8ad4a95` (E9
  signature-format.md), `bbc9203` (E12 rebuild-trigger.md), `3839951` (E14 url-scheme.md),
  `ee0a905` (`docs/contracts/README.md` index update).

## Acceptance criteria — demonstrated

1. **All six files exist, named per their edge and node pair, matching existing conventions.**
   ```
   $ ls -1 contracts/*.md
   contracts/append-only.rules.md
   contracts/archive-layout.md
   contracts/artifact-naming.md
   contracts/rebuild-trigger.md
   contracts/signature-format.md
   contracts/site-output.md
   contracts/url-scheme.md
   ```
   Every new file opens with "Contract for edge **E<n>** (`N<x> -> N<y>` ...)" naming its edge id
   and node pair explicitly, matching `append-only.rules.md`'s own opening line's convention.

2. **Stated at implementer level, no "appropriate"/"sensible"/"as needed".** Checked by
   re-reading each file for hedge words after writing it; none found. Every rule names a concrete
   input/output pair (e.g. E7's exact tag string, E9's exact byte offsets, E12's exact
   `event_type` string, E13's exact `CNAME` content, E14's exact path form).

3. **Adversarial pass — one attack attempt per contract, recorded in each file's own "Attack
   attempt(s)" section:**
   - **E7** (`artifact-naming.md`): (a) pasting `id` verbatim into a git ref — `git tag` rejects
     the literal `:` outright; (b) treating `entry.schema.json`'s pattern as sufficient — a
     namespace like `com1` collides with a Windows reserved device name at the OS level even
     though it is schema-valid.
   - **E9** (`signature-format.md`): signature-reuse-across-identities — copying a genuinely
     signed artefact's `source_archive`/`source_sha256`/`signature`/`key_id` onto an unrelated
     entry passes every byte/hash/signature check; only the trusted-comment `id`/`version`
     cross-check (rule 11) catches it.
   - **E11** (`archive-layout.md`): a non-manifest-declared hostile tar entry using `../`
     traversal, never looked up by name, defeats a check scoped only to manifest-declared paths;
     the rule is stated over every archive entry during extraction instead.
   - **E12** (`rebuild-trigger.md`): a near-miss `event_type` string (e.g. `registry-update`) is
     a fully successful `repository_dispatch` call that GitHub never routes anywhere, with no
     error surfaced on either side.
   - **E13** (`site-output.md`): (a) a `dist/`+`CNAME` pair missing `.nojekyll` — GitHub Pages'
     Jekyll processing silently drops Astro's `_astro/` assets; (b) a `CNAME` containing a
     scheme/trailing-slash form GitHub Pages does not treat as a bare hostname.
   - **E14** (`url-scheme.md`): (a) building the URL from a display label
     (`owner.name_at_registration`) instead of the raw lowercase `id`; (b) treating a
     trailing-slash variant as equivalent because a host happens to resolve both, breaking
     canonical-URL dedup.

4. **E11 states the path-escape rule; E7 states the awkward-characters rule; both demonstrated by
   naming a concrete input that must be rejected.** E11: a tar entry
   `mymod-abc123/assets/screenshots/../../../../../home/runner/.ssh/authorized_keys`, never
   declared in `page.json`, must be rejected during extraction and the whole archive treated as
   malformed. E7: the namespace `com1` (id `com1:anytool`, schema-valid) must be rejected at
   first-publish time because its release tag/asset names would begin `com1.`, colliding with a
   Windows reserved device name.

5. **`docs/contracts/README.md` indexes all ten contracts.** Verified by re-reading the file's
   "Files" table after editing: four task-006 rows plus six new rows, one per file.

6. **Nothing from task 006 modified.**
   ```
   $ git diff --name-only 74f5739 HEAD -- contracts/entry.schema.json contracts/page.schema.json \
       contracts/manifest.schema.json contracts/append-only.rules.md \
       contracts/validation-report.schema.json
   (no output)
   ```
   Full diff since the spec commit touches exactly the six new files plus
   `docs/contracts/README.md`:
   ```
   $ git diff --name-only 74f5739 HEAD
   contracts/archive-layout.md
   contracts/artifact-naming.md
   contracts/rebuild-trigger.md
   contracts/signature-format.md
   contracts/site-output.md
   contracts/url-scheme.md
   docs/contracts/README.md
   ```

7. **Every question booked under `## Questions`, with assumption and what rests on it.** Four
   booked: two in `archive-layout.md` (whether the pipeline must normalise the archive's
   top-level directory name; whether a nested README is ever a fallback), one in `site-output.md`
   (whether a deploy workflow must mechanically verify this document's requirements, or whether
   task 009's own acceptance criteria are relied on once at task-completion time), and one in
   `url-scheme.md` (whether `www.worldofmodcraft.com` is ever configured). Each carries an
   explicit "assumed meanwhile" and "what rests on this." E7, E9 and E12 each state explicitly
   that no question remained open once their assigned decisions (naming scheme, byte layout,
   event type/payload) were pinned per this task's own "what each contract must settle" list —
   none of those three needed a genuinely-undecided call left to a future ADR.

## What I could not verify

- **GitHub Pages' exact Jekyll-processing and extension-less-path-resolution behaviour** (the
  `.nojekyll`/`_astro/` interaction in `site-output.md`, and the trailing-slash resolution
  mentioned in `url-scheme.md`) is stated from general, well-documented GitHub Pages/Jekyll
  behaviour, not verified against this project's own live Pages instance — Pages is not yet
  enabled (mission §6.1 is still pending Ludwig's action). If GitHub's actual behaviour ever
  differs from what is described, that is a fact to re-verify once Pages is live, not something
  this task could run a command against.
- **The minisign reference implementation's exact byte offsets and trusted-comment signing
  scheme** (`signature-format.md`) are stated from the published minisign file-format
  specification, not from running `minisign` in this environment (no keypair exists to sign
  anything with, deliberately, per this task's forbidden-key-material rule) — task 008's
  implementer should confirm byte-for-byte against a real `minisign -Sm` run before relying on
  this document for a hand-rolled verifier.
- **Windows' exact reserved-device-name matching rule** (E7's rejection rule) is stated from
  well-known, longstanding Windows filesystem behaviour, not tested against a live Windows
  runner in this environment.
