# Archive interior layout

Contract for edge **E11** (`N6 -> N7`, artifact-store to site-build) in
`docs/architecture/depgraph.md`. The build pipeline (N5) writes the archive this document
describes; the site build (N7) reads it. Task 009 (site build) and task 008 (pipeline) both code
against this document directly: every ambiguity left here becomes a bug in one or the other,
possibly a security bug, so this states the archive's interior precisely enough that both sides
agree without inference.

## Scope: this document governs the interior of one source archive

Edge E7 (`contracts/artifact-naming.md`) names *where* an archive lives and what its file is
called. This document names *what is inside it* once you have it open: the tarball's root
convention, where a screenshot path from the manifest resolves to inside the archive, what a
reader does when a declared path is missing, and what a reader must do when the archive itself is
hostile. It says nothing about naming, retrieval, or the tarball's own filename — that is E7's
job, not this one.

The archive in question is `versions[i].source_archive` (`contracts/entry.schema.json`): the
pipeline's own tarball of the exact built commit (ADR-0041: "the pipeline uploads ... a tarball of
the exact built commit ... to platform-owned storage; the registry points at our copy, not the
author's repo"). This document assumes the reader already has the bytes of that tarball — E7
governs how those bytes were located and retrieved, and E9 (`contracts/signature-format.md`)
governs how a reader verifies the tarball's hash and signature *before* opening it. **A consumer
must complete E9's verification before extracting anything this document describes.** This
document is entirely about what verified bytes contain; it has nothing to say about a tarball
that fails E9's check, because that tarball is never opened at all.

## Format: `.tar.gz`

The archive is a gzip-compressed POSIX tar stream (`tar.gz`), matching the filename extension E7
requires for the source-archive asset. Nothing in this document depends on a specific tar
variant (`ustar`, GNU, PAX); a reader must accept any of them, because ADR-0058 §4's provider
neutrality extends to build tooling — this document does not pin the pipeline to a single tar
implementation.

## Root convention: exactly one top-level directory, name not specified

This is "the classic tarball ambiguity" the task names, so it is settled here explicitly rather
than left to whichever behaviour a given extraction library happens to default to.

**The archive's tar entries have exactly one path component before every file.** That is: every
entry inside the tar stream is either the single top-level directory entry itself, or a path of
the form `<root>/<rest>`, where `<root>` is the *same* string for every entry in the archive and
`<rest>` is one or more further path components. An archive with files at the top level (no
`<root>/` prefix at all) or with two different top-level prefixes across its entries does not
satisfy this document and must be rejected by a reader — see "Malformed archives" below.

**`<root>`'s literal string value is not specified by this document and a reader must not depend
on it.** `git archive` (a plausible, boring implementation choice under ADR-0103) names the root
after the ref and commit by default (e.g. `mymod-a1b2c3d`); nothing requires the pipeline to use
that tool or that naming, and nothing here promises a name matching the mod's `id`, its `version`,
or its `commit` hash. **A reader must determine `<root>` at extraction time by inspecting the
archive's own entries — read the first path component of any entry, or the top-level directory
entry if the archive carries one — never by constructing it from fields already known from
`entry.json` or the manifest.** A reader that assumes `<root>` equals, say, `<name>-<version>` and
extracts by hard-coding that guess will silently find nothing (or, worse, silently find the
*wrong* thing if the guessed name happens to collide with unrelated content already on disk) the
first time the pipeline's actual naming differs from the guess.

**Path resolution inside the archive is always relative to `<root>`, never to the tar stream's own
top level.** "`README.md` at the tarball root" (this document's own §"README", and the one-line
graph definition it expands) means `<root>/README.md`, not a bare `README.md` entry with no
prefix — an archive built without the single top-level directory does not have a root in this
document's sense at all, regardless of where its files sit.

## `README.md`

The file at `<root>/README.md` is the mod's README, exactly as it existed in the author's source
tree at the archived commit (ADR-0059 §1: pages are built from the archive, "never the live
repo"). Rendering (Markdown to HTML, sanitisation) is the site build's job and out of this
document's scope.

**If `<root>/README.md` is absent, the site build renders no README for that version** — this is
not an error condition for either side (a mod need not carry a README; nothing in ADR-0030 or
ADR-0058 makes one mandatory), and a reader must not fail the build or fail validation solely
because this one file is missing. Contrast this with a *manifest-declared* screenshot path being
absent, below, which is a different case with a different, non-silent outcome: `README.md`'s
absence is not declared anywhere, so there is nothing to have failed to keep a promise about;
a `screenshots[]` entry's absence *is* a declared path going unfulfilled, and is handled
differently for exactly that reason.

**Case sensitivity: the match is exact and case-sensitive, on the string `README.md`.**
`readme.md`, `Readme.MD`, or `README.MD` at the root do not satisfy this document and are treated
as README absent, not as a fuzzy match. Case-insensitive filesystems exist, but the archive is a
tar stream read by a build tool, not a mounted filesystem, and tar entry names are opaque byte
strings compared exactly; inventing fuzzy matching here would be exactly the undocumented
leniency ADR-0103 warns against earning without a demonstrated need. If this is ever wanted, it
is a decision no ADR has made — booked under Questions.

## Screenshots: manifest path maps to archive path by direct concatenation under `<root>`

`page.json`'s `screenshots[]` (`contracts/page.schema.json`) and `mod.lua`'s `screenshots`
(`contracts/manifest.schema.json`) are both POSIX-style relative paths "inside the mod's own
source tree" / "inside the archived mod source". This document is what makes that promise
concrete: **a screenshot path `p` from either list resolves to the archive entry
`<root>/p`, with no further transformation** — no normalisation beyond what "resolves to" already
implies (see path-escape rule below), no searching, no fallback location. If `p` is
`"assets/screenshots/shop.png"`, the site build reads the tar entry
`<root>/assets/screenshots/shop.png` and nothing else.

**If the resolved entry is absent from the archive, the site build renders that gallery slot as
missing (omitted from the rendered gallery) and logs the fact — it must not fail the site build,
and it must not silently render a broken image tag.** A screenshot path can go stale relative to
the archive independently of the two schemas' own validation (`manifest.schema.json` and
`page.schema.json` check that a string looks like a relative path; neither one, nor any check
described in this document, opens the archive to confirm the path actually exists inside it — no
existing contract does that cross-check), so a reader must be able to survive the gap without
treating it as fatal. **A page with some screenshots present and one silently missing must still
build**; a validation step that decides such an archive is invalid entirely is a decision no ADR
or graph edge licenses, and would make an unrelated author's typo in `page.json` capable of
taking a working page down.

## The path-escape rule: `../` and absolute paths are rejected, never resolved

**This is a security property, not an edge case**, exactly as the task names it. A tar archive's
entry names are attacker-influenced content once the mod's source is attacker-influenced (an
author, or anyone with a merged PR, controls their own repo's contents at the moment of tagging);
the pipeline archives whatever the tagged commit contains, and this document's job is to make sure
a hostile entry name inside that archive can never cause a reader to write or read outside the
intended extraction directory.

A reader (any code that extracts this archive, at any stage: pipeline, site build, or any future
consumer) **must reject, and must not extract, any tar entry whose name, after stripping the
`<root>/` prefix, satisfies any of the following:**

- Contains a path segment equal to `..` (the parent-directory reference), anywhere in the path —
  not only at the start. `assets/../../etc/passwd` is rejected exactly as `../../etc/passwd` is;
  a check that only looks at the first path segment is insufficient, because the substring can
  appear after arbitrarily many legitimate-looking segments.
- Is an absolute path (begins with `/`) once the `<root>/` prefix (or lack of one) is accounted
  for. A well-formed archive under this document never produces an absolute entry name after
  stripping `<root>/`, because every entry begins with a path component; an entry that is itself
  absolute (e.g. a tar entry literally named `/etc/passwd`, bypassing the single-root convention
  entirely) is rejected on this ground alone, independent of the `..` check.
- Is, or resolves through, a symbolic link that points outside `<root>` — a tar entry can itself
  be a symlink (tar's entry type field distinguishes regular files from symlinks); a symlink
  named innocently inside `<root>` that points at `../../etc/passwd`, or at an absolute path,
  achieves the same escape without a `..` ever appearing in the *entry name* being extracted. A
  reader must inspect symlink targets under the same two rules above (no `..` segment, not
  absolute), not only literal path strings.

**Rejection means: the reader does not extract or follow that entry, does not treat it as a
"missing" screenshot or README (the two cases above), and — because a single hostile entry
indicates the whole archive is not trustworthy, not just that one entry — the reader must reject
the entire archive as malformed (see below), refusing to build that version's page at all, rather
than extracting every entry except the hostile one and proceeding. Silently skipping only the bad
entry while extracting the rest is not a smaller version of compliance; it is non-compliance,
because it leaves open the possibility that a later change to the reader's iteration order, or a
second hostile entry crafted to look like a legitimate file, extracts successfully next time.**

**Attack attempt against this rule, recorded as required by acceptance criterion 3.** Consider an
archive whose declared root is `mymod-abc123`, containing (among ordinary files) a tar entry named
`mymod-abc123/assets/screenshots/../../../../../home/runner/.ssh/authorized_keys` with attacker
content, where `page.json` never mentions this path at all — it is not resolved through the
screenshot-lookup mechanism above, it is simply present in the archive and would be extracted by
any tool that does a naive "extract everything under `<root>/`" without inspecting each entry
name individually. A contract that only constrained *manifest-declared* paths (i.e. only checked
`p` in `screenshots[]` for `..`) would let this entry through completely, because it is never
looked up by name — it is only ever encountered during a blind full-archive extraction, which is
exactly what a site build does to get at the README and screenshots it *does* want. **The fix
recorded here is that the escape check applies to every entry in the archive, checked during
extraction itself, not only to the small set of paths the manifest happens to name** — the
rule above is phrased as "a reader ... must reject ... any tar entry", not "any *declared* tar
entry", precisely so this attempt fails against the text as written.

## Malformed archives

An archive that is not a valid gzip stream, not a valid tar stream once decompressed, does not
have the single-top-level-directory shape described above (files at the true top level, or
entries under two or more different first path components), or contains any entry rejected by the
path-escape rule, is **malformed**. A reader must not attempt partial recovery from a malformed
archive (extracting the entries that do parse and ignoring the rest) — the whole archive is
rejected, the version's page is built without README or screenshots for that version (same
degraded-but-not-fatal outcome as an individually absent file, escalated to the whole archive),
and the failure is logged with the archive's identity (the `source_archive` URL) so it is visible
in the build log rather than silently absorbed. This mirrors `validation-report.schema.json`'s own
`scan_errors` treatment of walk-level problems that are not about one file's content: a malformed
archive is a container-level problem, not a per-file rejection, and is reported as such rather
than forced into the per-screenshot missing-file path.

## What this document does not cover

- **How the archive's bytes are named, located, or retrieved** — `contracts/artifact-naming.md`
  (E7).
- **How a reader verifies the archive's hash and signature before opening it** —
  `contracts/signature-format.md` (E9). This document assumes that check has already passed.
- **Manifest field validation** (whether a `screenshots[]` string is even a legal relative path
  string in the first place) — `contracts/manifest.schema.json` and `contracts/page.schema.json`.
  This document only says how an already-valid path string maps to an archive entry, and what
  happens when that entry turns out not to exist.
- **README rendering** (Markdown parsing, HTML sanitisation, image handling within the README
  body) — site-build implementation detail, not a boundary contract.

## Questions

- **Whether the pipeline must normalise `<root>` to a fixed, predictable name (e.g. always
  `source/`) rather than leaving it to whatever the archiving tool defaults to.** No ADR read for
  this task requires a specific root name, and ADR-0103 favours the boring default (`git archive`'s
  own naming) over inventing a normalisation step with no stated need. **Assumed meanwhile:** the
  root name is arbitrary and every reader determines it from the archive itself, as stated above.
  **What rests on this:** if a future contract or tool needs to predict the root name without
  opening the archive first, that tool cannot be written against this document as it stands and
  this question would need an answer first.
- **Whether a `README.md` deeper than the archive root (e.g. `<root>/docs/README.md`) is ever
  considered when the top-level one is absent.** No ADR states a fallback search order, and
  inventing one would be exactly the undocumented leniency this document elsewhere declines to
  add. **Assumed meanwhile:** no fallback search; only `<root>/README.md` counts, as stated above.
  **What rests on this:** a mod whose README lives elsewhere in its tree renders no README on the
  site under this document as written, until either the mod moves its README or this question is
  answered.
