# Release tag and asset naming

Contract for edge **E7** (`N5 -> N6`, build-pipeline to artifact-store) in
`docs/architecture/depgraph.md`. The pipeline (N5) creates exactly one thing per accepted
version — a GitHub Release, in the org's artifact-store repository, carrying two assets — and
this document is the deterministic function that turns `(namespace, name, version)` into the
tag and the two asset filenames, so that anything writing a release (the pipeline) and anything
reading one back by name (a future re-archival tool, a manual audit, Ludwig looking at the
Releases page) agree on the name without asking each other first.

## Inputs and what "deterministic" means here

The three inputs are exactly `entry.json`'s own fields for one version: `namespace` and `name`
(the two halves of `id`, `contracts/entry.schema.json`'s pattern
`^[a-z0-9][a-z0-9_-]*:[a-z0-9][a-z0-9_-]*$`, split on the single `:`) and `version` (that same
schema's semver string). **Deterministic** means: the same three inputs always produce the same
tag and the same two asset filenames, and no other information — not `commit`, not
`published_at`, not the time the pipeline happens to run — is ever part of the name. This matters
because the takedown transition (`contracts/append-only.rules.md`) never changes `version`, so a
removed version's release keeps existing under the exact name it was created with, forever;
nothing about this naming scheme ever needs to change when a version's `status` changes.

## Why not the `id` string's own separator

`id` itself already exists as `namespace:name` and would be the obvious thing to paste directly
into a tag or filename. **This document deliberately does not do that**, because `:` is not
merely awkward but **outright illegal in a git reference name** (`git check-ref-format` rejects
any ref containing `:`), and a release tag is a git ref. A naming scheme built by pasting `id`
and `version` together with a separator would fail to create the tag at all for every single mod,
not merely for edge cases — this is the first thing "deterministic from `(namespace, name,
version)` alone" could be satisfied by while breaking the one thing the scheme exists to do,
recorded fully in "Attack attempts" below.

**The fix reuses a convention this project already committed to elsewhere**, rather than
inventing a new one: `contracts/entry.schema.json`'s own storage path is
`mods/<namespace>.<name>/entry.json` — a literal `.` joining namespace and name, already chosen
once, in the registry's own directory layout. This document uses the identical join for tags and
asset names, so a reader who already knows the registry's path convention needs to learn nothing
new. `.` is unambiguous here because neither `namespace` nor `name` can themselves contain `.`
(the pattern above allows only `[a-z0-9_-]` after the first character, `.` excluded), so the join
point is always exactly one character, at a position no other `.` in the string could be mistaken
for.

## The naming scheme

Let `ns` = namespace, `nm` = name, `v` = the exact `version` string (byte-for-byte, including any
`-prerelease` or `+build` suffix — this document does not normalise or truncate it).

- **Release tag:** `ns.nm-v` — e.g. namespace `mc`, name `hello-world`, version `1.0.0` gives the
  tag `mc.hello-world-1.0.0`.
- **Source tarball asset:** `ns.nm-v.tar.gz` — e.g. `mc.hello-world-1.0.0.tar.gz`. This is the
  file `contracts/archive-layout.md` (E11) describes the interior of, and the file
  `entry.json`'s `source_archive` field points at (as a full URL, not merely this filename).
- **Detached signature asset:** `ns.nm-v.tar.gz.minisig` — e.g.
  `mc.hello-world-1.0.0.tar.gz.minisig`. The `.minisig` suffix matches minisign's own default
  naming for a detached signature of a file (`contracts/signature-format.md`, E9); this document
  only fixes the filename, not the bytes inside it.

**Global uniqueness, forever.** `version` is unique within one mod's own `versions[]`
(`contracts/append-only.rules.md` rule 4) and `id` is frozen once an entry exists, so
`ns.nm-v` never repeats across the registry's lifetime once assigned — a tag is never reused, and
the pipeline must treat a pre-existing tag of this exact name as an error (it means either this
version was already archived, or a naming collision this document did not anticipate), never as
something to overwrite.

**Leading-character safety.** Both `namespace` and `name` are required by `entry.schema.json`'s
pattern to start with `[a-z0-9]`, never `-` or `_`. Every tag and asset name under this scheme
therefore always starts with an alphanumeric character — never a `-`, which some command-line
tools (including `git` itself in some invocations) can misparse as an option flag rather than a
positional argument. This is a consequence of a rule already fixed in `entry.schema.json`, stated
here only because this document is where it matters.

## Rejected namespaces: Windows reserved device names

Beyond the character set itself (already filename-safe on every mainstream OS — see the next
section), one more rule is needed because of *where* `namespace` lands in the name this document
builds: **`namespace` is always the segment before the first `.`, in both the tag and both asset
filenames.** Windows treats a fixed list of names — `CON`, `PRN`, `AUX`, `NUL`, `COM0`–`COM9`,
`LPT0`–`LPT9` — as reserved device names, and applies that reservation to the portion of a
filename **before its first `.`**, regardless of what follows: `aux.txt`, `aux.tar.gz` and
`aux.hello-1.0.0.tar.gz` are all rejected by native Windows file APIs on that basis, exactly as
`aux` alone is. Because `git` stores a tag as a loose ref file when it is not yet packed, a tag
whose leading segment matches one of these names can fail to be created at all on a Windows
runner or in a Windows-hosted clone, for the identical reason.

**A namespace matching one of these names, case-insensitively, must be rejected at first-publish
time — before the namespace is bound (ADR-0058 §3) and before any release under this scheme is
attempted — not silently substituted, escaped, or worked around.** The pipeline (or whichever
component performs the first-publish confirmation ADR-0058 §3 describes; that component's own
mechanics are outside this document's scope) must refuse to proceed and report why, in the same
way any other publish-time rejection is reported.

**Concrete input that must be rejected:** the namespace `com1` (legal under
`contracts/entry.schema.json`'s `id` pattern — `com1:anytool` is a syntactically valid `id`).
Under this scheme its release tag would begin `com1.anytool-...`, whose leading segment before
the first `.` is `com1` — a reserved device name. This must never reach a created tag; the
publish attempt is rejected at the namespace-binding step instead.

**`name` is not subject to this check under this scheme**, because the join order above
(`ns.nm-...`) means `name` is never the segment before the first `.` — it always follows one.
This is stated explicitly, and tied to the fixed join order, so that a future change reordering
the two (`nm.ns-...`, or some other scheme) does not silently inherit this section's guarantee
without someone re-deriving it.

## Characters legal in an `id` but awkward in a filename

This is the general form of the question this document must answer, per this task's own
instructions. Two distinct answers, because two distinct problems exist:

1. **The `:` separator inside `id` itself** — legal in the composite `id` string (it is the
   required separator between `namespace` and `name`), illegal in a git ref name, and awkward
   (though not universally illegal) in a bare filename. **Answer: never used here — replaced by
   `.`** as described above, because `namespace` and `name` individually cannot contain `.`, so
   the substitution introduces no new ambiguity.
2. **A namespace or name that is, in full, a Windows reserved device name** — legal under
   `entry.schema.json`'s pattern (that pattern has no denylist), awkward — in fact broken outright
   on one major OS — as a filename component. **Answer: rejected outright at publish time**, as
   described above, rather than accepted and given a mangled or escaped name. Every other
   character `[a-z0-9_-]` permits is already filename-safe, ref-safe, and URL-path-safe on every
   platform this project's own tooling ADRs name (ADR-0040: Linux, Windows, macOS runners), so no
   further substitution or rejection rule is needed beyond these two.

## Attack attempts against this contract, recorded per acceptance criterion 3

**Attempt 1 — paste `id` and `version` directly.** A reading of "deterministic from `(namespace,
name, version)` alone" that ignores everything else could produce the tag `mc:hello-world-1.0.0`
(literal `id`, then `-`, then `version`) — this is a pure, deterministic function of exactly the
three named inputs, satisfying the letter of the requirement. **Outcome: `git tag` refuses to
create a ref containing `:`, so the very first version of the very first mod ever published fails
to archive at all** — not a rare edge case, a universal failure, because every `id` contains this
character by construction. This is why the scheme above uses `.` instead of `:`, reusing the
registry's own existing path convention rather than inventing a new delimiter.

**Attempt 2 — accept any namespace the `id` pattern accepts, since the pattern is already the
agreed validation.** A reading that treats `entry.schema.json`'s pattern as the complete
authority on which namespaces are nameable could argue that since `com1` (or `aux`, `con`, `nul`)
matches `^[a-z0-9][a-z0-9_-]*$`, no further check belongs in a naming *scheme* document — schema
validation already happened, so any string it accepts is fair game. **Outcome: the pipeline
attempts to create a tag or write a release asset beginning `com1.`, and on a Windows-hosted
runner or for any Windows user who later downloads and tries to save the tarball with its given
name, the write fails at the OS level** — a namespace that was perfectly valid registry data
produces a release that cannot exist on a real, supported build platform (ADR-0040 names Windows
runners explicitly). Satisfying `entry.schema.json` was never sufficient on its own — schema
validity and filename validity are different properties, and this document exists specifically
because the graph's one-line E7 definition does not say so.

## What this document does not cover

- **Which specific org-owned repository hosts these Releases** (a dedicated artifact-store repo
  versus Releases on the `registry` repository itself) — no ADR or graph node fixes this; it is a
  build-pipeline setup detail (task 008), not a naming-scheme question, and this scheme's inputs
  and outputs are unaffected by which repository holds them.
- **The bytes inside the two assets** — the tarball's interior is `contracts/archive-layout.md`
  (E11); the signature's encoding is `contracts/signature-format.md` (E9).
- **Retry/idempotency behaviour if the pipeline is re-run for a version already archived** — a
  pipeline-implementation concern (task 008), constrained only by this document's uniqueness rule
  above (never overwrite an existing tag of this name).

## Questions

- (none — the two decisions this contract needed to make, the delimiter substitution and the
  reserved-device-name rejection, are both settled above with their reasoning; nothing here was
  left for a future ADR to decide.)
