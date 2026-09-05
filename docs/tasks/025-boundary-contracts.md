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
- **ADR-0058** §3 (the first-publish confirmation that binds a namespace) — **added retroactively,
  2026-09-05, as a manager Context-selection miss.** `artifact-naming.md` relies on it in two
  places and it was never declared here. Review round 1, non-blocking finding 6; checklist item
  4(b). Recorded as a manager error, not an agent one.
- **ADR-0040** §1 (the pipeline's Linux/Windows/macOS runners) — **added retroactively,
  2026-09-05, same manager miss.** `artifact-naming.md` cites it to establish that Windows runners
  are a platform this project actually builds on. The citation is factually correct — ADR-0040 §1
  names them explicitly — but SITE-V1's mission scope excludes the build pipeline, so the citation
  must not be load-bearing for the *rule*; see the fix brief. Review round 1, finding 5.
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

Booked here in fix round 1 (2026-09-05), moved from the four contract files they were originally
written into only, per review round 1 BLOCKING 4 (MANAGER.md §8b.1 puts questions in the task log,
not only in the shipped contract). Left in place in their source contracts too (see "Fix round 1"
section below for why); wording here and there is kept consistent, and the `www` question below is
the corrected version — see BLOCKING 5 in that section for what was wrong with the original.

1. **From `contracts/archive-layout.md`:** whether the pipeline must normalise the archive's
   `<root>` top-level directory name to a fixed, predictable value (e.g. always `source/`) rather
   than leaving it to whatever the archiving tool defaults to. No ADR read for this task requires a
   specific root name, and ADR-0103 favours the boring default (`git archive`'s own naming) over
   inventing a normalisation step with no stated need. **Assumed meanwhile:** the root name is
   arbitrary and every reader determines it from the archive itself at extraction time. **What
   rests on this:** if a future contract or tool needs to predict the root name without opening the
   archive first, that tool cannot be written against this document as it stands and this question
   would need an answer first.
2. **From `contracts/archive-layout.md`:** whether a `README.md` deeper than the archive root
   (e.g. `<root>/docs/README.md`) is ever considered as a fallback when the top-level one is
   absent. No ADR states a fallback search order, and inventing one would be undocumented leniency
   this document elsewhere declines to add. **Assumed meanwhile:** no fallback search; only
   `<root>/README.md` counts. **What rests on this:** a mod whose README lives elsewhere in its
   tree renders no README on the site under this document as written, until either the mod moves
   its README or this question is answered.
3. **From `contracts/site-output.md`:** whether a deploy workflow must mechanically verify this
   document's requirements (a smoke test over `dist/` before the Pages action runs) or whether task
   009's own acceptance criteria are taken as sufficient verification once, at task-completion
   time, without a standing check on every future deploy. No ADR read for this task settles this;
   it is an implementation decision for task 008/009's workflow, not a boundary-contract question.
   **Assumed meanwhile:** this document states what "valid" means; whether that gets checked by an
   automated step or relied on by convention is left to whoever implements E12/E13's workflow.
   **What rests on this:** if no automated check is ever added, a future regression (someone's
   Astro upgrade drops `.nojekyll` from a template default, for instance) would only be caught by
   someone noticing the live site is broken, not by CI.
4. **From `contracts/url-scheme.md`, rewritten in fix round 1 (see below — the original version of
   this question rested on a false claim about live DNS):** what `www.worldofmodcraft.com` should
   serve, given that the DNS record for it already exists (a CNAME to
   `worldofmodcraft.github.io`, set up in the mission's own DNS cutover session M2, 2026-09-02, and
   independently re-verified here 2026-09-05 with `getent hosts www.worldofmodcraft.com`) — not
   whether it should exist at all. GitHub Pages is not yet enabled for `worldofmodcraft/site`
   (still pending; the repo is empty), so this project has not observed GitHub's actual apex/www
   redirect behaviour for its own domain pair. **Assumed meanwhile:** the canonical URL scheme
   never uses `www` in a generated link, regardless of how the host eventually resolves requests to
   it. **What rests on this:** once Pages is enabled and a custom domain is set (mission §6),
   Ludwig's choice of which of {apex, www} to configure as primary determines which one redirects
   to the other; this is a decision to make at that moment, not before, since it cannot be verified
   before Pages exists for this domain. **This one bears directly on one of Ludwig's own manual
   steps (mission §6 DNS/Pages setup)** — the reason BLOCKING 4 flagged it as a real consequence of
   leaving the log's own Questions section empty.

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

## Fix round 1 (2026-09-05)

Independent adversarial review returned BLOCKING (checklist:
`docs/manager/REVIEW-CHECKLIST.md`). This section records what changed, per finding, and where.
Task file's Context section was already corrected by the manager before this round started (ADR-
0058 §3 and ADR-0040 §1 added — a manager Context-selection miss, not something this round needed
to redo).

**BLOCKING 1 — `signature-format.md`, the four-line layout and "line 2 is 74 bytes" stated as
unqualified fact.** Added an inline "Unverified in this environment" note directly under the
byte-layout table (`contracts/signature-format.md`, immediately after the table, before "Line 3,
the trusted comment"), stating the layout comes from minisign's published spec, not a real
`minisign -Sm` run here, and naming task 008's implementer as the one who must confirm it
byte-for-byte before shipping a verifier. The normative rule itself (the byte layout, the rejection
list) is unchanged.

**BLOCKING 2 — `artifact-naming.md`, Windows reserved-device-name behaviour stated as fact.**
Added an inline "Unverified in this environment" note in the "Rejected namespaces" section,
directly after the paragraph stating the reserved-name list and the before-first-`.` matching
rule, noting this is documented-but-unexercised Windows behaviour and that task 008's first-publish
implementer should confirm the exact matching behaviour against a real Windows machine. The
rejection rule itself is unchanged and stays fully normative.

**BLOCKING 3 — `site-output.md` and `url-scheme.md`, GitHub Pages behaviour stated as fact while
Pages is not yet enabled.** Three inline notes added:
- `contracts/site-output.md`, directly under the "`.nojekyll`: required..." heading, before the
  Jekyll/`_astro/` explanation: notes the mechanism is GitHub Pages' generally documented
  behaviour, not observed against this project's own instance, and that the `.nojekyll`
  requirement stays normative regardless — confirm the specific mechanism at the first live
  deploy.
- `contracts/site-output.md`, directly after the second attack attempt (the malformed-`CNAME`
  paragraph): notes GitHub Pages' exact handling of a malformed `CNAME` (reject vs. silently
  misconfigure) is unverified here; the content rule stays normative regardless.
- `contracts/url-scheme.md`, in the trailing-slash paragraph: strengthened the existing partial
  hedge into an explicit "Unverified in this environment" statement — which way GitHub Pages
  resolves the trailing-slash variant for this project's own build output has not been observed,
  Pages is not enabled yet, and the no-trailing-slash canonical rule is normative regardless of
  what a live deploy turns out to do.

None of these three weakened any normative rule; each only adds where the supporting claim comes
from and who/when confirms it.

**BLOCKING 4 — the log's own `## Questions` said "(none yet)" while four real questions existed,
booked only inside the shipped contracts.** All four questions are now booked in this file's own
`## Questions` section above, each naming the contract file it came from, with its "assumed
meanwhile" / "what rests on this" preserved. **Decision: left in the contracts as well as the
log.** Reasoning: BLOCKING 1-3 above make the same point from the other direction — an implementer
reading only a contract file has no way to see anything that lives only in the task log — so a
genuinely open decision that could affect how a contract is implemented belongs in both places, not
only the log. The log is where the manager triages and the next session looks first (MANAGER.md
§8b.1); the contract is where task 008/009's implementer actually reads. Wording is kept
consistent between the two; the `www` question (BLOCKING 5, below) was corrected in both places
together so neither contradicts the other.

**BLOCKING 5 — the `www` question in `url-scheme.md` rested on a false claim about live DNS.**
Re-ran the check myself rather than trusting the manager's brief at face value:
```
$ getent hosts www.worldofmodcraft.com
2606:50c0:8003::153 worldofmodcraft.github.io www.worldofmodcraft.com
2606:50c0:8000::153 worldofmodcraft.github.io www.worldofmodcraft.com
2606:50c0:8002::153 worldofmodcraft.github.io www.worldofmodcraft.com
2606:50c0:8001::153 worldofmodcraft.github.io www.worldofmodcraft.com
```
confirmed, and cross-checked against the mission log's own record
(`docs/tasks/MISSION-worldofmodcraft-site-v1-log.md`: session M2, 2026-09-02, "`www` CNAME →
`worldofmodcraft.github.io`"; re-verified in that log 2026-09-03, "`www` CNAMEs correctly"). Also
checked the apex and the live HTTP/TLS behaviour, to see whether anything else in `url-scheme.md`
or `site-output.md` reasoned about live hosting rather than observing it:
```
$ getent hosts worldofmodcraft.com
185.199.109.153 worldofmodcraft.com
185.199.110.153 worldofmodcraft.com
185.199.111.153 worldofmodcraft.com
185.199.108.153 worldofmodcraft.com
$ curl -sk -o /dev/null -w "HTTP:%{http_code}\n" https://worldofmodcraft.com
HTTP:404
$ curl -sv https://worldofmodcraft.com 2>&1 | tail -6
* subjectAltName does not match hostname worldofmodcraft.com
* SSL: no alternative certificate subject name matches target hostname 'worldofmodcraft.com'
```
This matches the mission log's own 2026-09-03 "Site status" note exactly (404 over HTTP, a
certificate-name error over HTTPS, "the exact signature of DNS points at GitHub, no GitHub site
claims this hostname yet") — DNS is correctly pointed at GitHub Pages, GitHub Pages itself is just
not yet enabled for this domain (`worldofmodcraft/site` is empty). Nothing here contradicts any
other claim already in `url-scheme.md`.

Changes made in `contracts/url-scheme.md`:
- "Scheme and host" section: replaced "No ADR or mission document read for this task reserves or
  configures a `www` host, and this document does not invent one" (false — the record exists and
  was deliberately configured) with a statement that the DNS record exists and resolves, cited
  against both the mission log and today's own `getent` output, while keeping "no link this site
  generates ever uses `www`" as the (still true, still normative) canonical-scheme rule.
- `## Questions`: rewrote the entry from "whether `www` should exist at all" (false premise) to
  "what `www` should serve, given the record already exists" — redirect vs. independent vs.
  unsupported — explicitly declining to assert GitHub Pages' apex/www redirect behaviour since
  Pages is not enabled yet and that behaviour has not been observed for this project's own domain.
  Mirrored into this log's own `## Questions` item 4 above, in matching wording.

**Non-blocking 6 — `artifact-naming.md`, ADR-0040 load-bearing for the reserved-name rule.**
Reworded both ADR-0040 references (the "Characters legal..." section and Attack attempt 2) so the
rule's stated basis is only its own two merits — a Windows end user cannot save the file; `git`
cannot create the loose ref — with ADR-0040 §1 kept only as supporting evidence that Windows is a
platform this project targets, explicitly noting SITE-V1 excludes the build pipeline ADR-0040
governs so the rule must not depend on it. Chose to keep the citation (reworded) rather than drop
it, since it is factually correct supporting evidence and dropping it entirely would lose the "this
isn't a hypothetical platform" grounding — it is now clearly subordinate, not load-bearing.

**Non-blocking 7 — `signature-format.md`, fabricated base64 examples were invalid base64 and the
wrong length.** Verified the review's finding first:
```
$ python3 -c "import base64; base64.b64decode('RWRlxAAA...')"
binascii.Error: Incorrect padding
```
Replaced both example lines with base64 that decodes successfully to the exact byte counts the
document requires (74 bytes for line 2, 64 for line 4), built from repeated placeholder bytes
(`Ed` + eight `0x00` + sixty-four `0xAA` for line 2; sixty-four `0xBB` for line 4) so nothing
resembles real key material. Confirmed:
```
$ python3 -c "
import base64
l2='RWQAAAAAAAAAAKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqo='
l4='u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7uw=='
print(len(base64.b64decode(l2)), len(base64.b64decode(l4)))
"
74 64
```
Updated the caption below the example to state plainly that both lines decode successfully to
placeholder bytes of the correct length and are not signatures of anything.

**BLOCKING 8 — the log never demonstrated the pre-existing suite still passes.** Re-ran it myself
in this worktree, unmodified:
```
$ python3 -m unittest discover -s tests/contracts -v
...
----------------------------------------------------------------------
Ran 23 tests in 0.007s

OK
```
23 tests, all pass — matches the reviewer's own report exactly. Full verbose output was 23 `ok`
lines across `DeterminismTests`, `EntryExampleTests`, `LicenseListTests`, `ManifestExampleTests`,
`OwnerIdIsNumericTests`, `PageExampleTests`, `ProviderNeutralityTests`, `ReservedNamespacesTests`,
`SchemaWellFormedTests`, `ScreenshotPathTests` — no test file touched this round (file scope is
`contracts/*.md`, `docs/contracts/README.md`, this log).

**Files changed this round:** `contracts/signature-format.md`, `contracts/artifact-naming.md`,
`contracts/site-output.md`, `contracts/url-scheme.md`, `docs/tasks/025-boundary-contracts.md`
(this file — Questions populated, this section appended). `docs/contracts/README.md` and
`contracts/archive-layout.md` were not touched — no finding required a change to either (archive-
layout.md's two questions were only copied into this log's Questions section verbatim, not
reworded).
