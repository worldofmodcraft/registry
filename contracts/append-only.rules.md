# Append-only rules for `entry.json`

Contract for edge **E4** (`N2 -> N3`, registry-ci's immutability gate) in
`docs/architecture/depgraph.md`. Task 007 implements a field-level diff checker
directly from this document: every ambiguity left here becomes a bug there, so
each rule below is stated at field level, with the boundary cases spelled out
rather than left to inference.

## Scope: this document governs `entry.json` only

Every mod directory holds two files, `mods/<namespace>.<name>/entry.json`
(`contracts/entry.schema.json`) and `mods/<namespace>.<name>/page.json`
(`contracts/page.schema.json`). **Only `entry.json` is append-only.**
`page.json` is the opposite by design: ADR-0059 Section 2 calls it
"immediately editable" content, and Section 3 states approved page changes
"publish immediately". A checker that applies this document's rules to
`page.json` is applying the wrong contract to the wrong file — every field in
`page.schema.json` may be freely replaced by a later PR, and there is nothing
further to say about it here.

The rest of this document is about `entry.json`, whose shape is
`{ id, owner, versions: [...] }` (`contracts/entry.schema.json`).

## The comparison model

A PR is checked by comparing two parsed JSON values of the same `entry.json`
file: `old` (the file's content at the PR's merge-base with the target
branch) and `new` (the file's content in the PR branch, i.e. what the PR
proposes to merge). **Comparison is always over parsed values, never over
raw bytes or text.** This has one concrete, deliberate consequence and one
explicit non-consequence, both stated because "immutable" alone does not
settle either:

- **Whitespace, indentation, trailing newline, and numeric literal spelling**
  (e.g. `1.0` vs `1.00` are the same JSON number; this schema uses no such
  fields, so this is theoretical here but stated for completeness) carry no
  meaning and are never a violation, anywhere in the file, on their own.
- **Key order within a single JSON object** (e.g. writing a version object's
  `commit` before `version` instead of after) carries no meaning and is
  never a violation, anywhere in the file, on its own. JSON objects are
  unordered maps; this document's rules are about which keys exist and what
  values they hold, never about the order they were written in.
- **Element order within a JSON array** (there is exactly one array in this
  schema: `versions`) is **not** the same case as key order and is
  meaningful — see "Ordering of `versions[]`" below. Do not generalise the
  object-key-order rule to arrays.

## Fields outside `versions[]`: `id` and `owner`

`entry.json` has exactly two top-level fields besides `versions`: `id` and
`owner` (with `owner`'s three subfields `provider`, `id`, `name_at_registration`).

**Both are frozen. There are currently no mutable top-level fields on this
document.** Concretely: `new.id != old.id`, or `new.owner` not deep-equal to
`old.owner` (any of its three subfields changed), is a violation, full stop —
no PR may ever change either, not even one from the namespace's own owner.

This follows directly from ADR-0058 Section 3: "Namespaces are never
reassigned" and Section 2's ownership binding — if `owner` could be edited by
a normal PR, the append-only/ownership machinery would be pointless, since an
attacker's PR could simply rewrite `owner.id` to their own id in the same PR
that adds a version. (Reserved-namespace entries, ADR-0119, are not a special
case here: their `owner` is just as frozen, bound to the organisation's id
instead of an individual's — the freeze rule does not distinguish the two.)

If a future ADR introduces a legitimate way to change `owner` (account
migration, namespace transfer under new governance) or any other top-level
field, **that ADR must amend this document before task 007's checker is
allowed to permit it.** Silently loosening this rule to accommodate a new
feature is exactly the kind of undocumented exception ADR-0119's own context
section warns against.

## `versions[]`: append-only, order-preserving

Let `n = len(old.versions)`. The check is:

1. **`new.versions[0:n]` must be deep-equal, element-for-element and in the
   same order, to `old.versions[0:n]`.** Every version object that existed
   before this PR must appear, unchanged, at the same index, in the PR's
   version. This single rule is the entire mechanism; everything below is a
   consequence of it, spelled out because each one is a place a diff checker
   could reasonably get it wrong.
2. **`new.versions` may be longer than `old.versions`** (`len(new.versions)
   >= n`); every element from index `n` onward is a newly added version
   object and must itself satisfy `entry.schema.json`.
3. **`new.versions` must never be shorter than `old.versions`**
   (`len(new.versions) < n` is always a violation) — a version can never be
   removed.
4. **A newly added version's `version` field must not equal any existing
   version's `version` field.** ADR-0041's "existing hashes can never be
   updated, only new versions added" presumes each version string identifies
   at most one version object; without this rule a PR could not modify
   `versions[2]` in place but could add a second object with the same
   `version` string and a different `commit`/hash, which achieves the same
   practical deception (which build is "the" 1.2.0?) through an addition
   instead of an edit. This document treats that as append-only's rule 1
   already covering it in spirit, but names it explicitly since it is not a
   literal prefix-comparison failure.
5. **No rule in this document requires new version numbers to be
   numerically greater than existing ones**, or requires `published_at`
   timestamps to be monotonically increasing. Nothing read for this task
   (ADR-0041, ADR-0042) states such a constraint, and inventing one here
   would be exactly the kind of undocumented registry semantics this task's
   instructions forbid. If monotonic version ordering is wanted, it is a
   separate, not-yet-written decision — booked under Questions in
   `docs/tasks/006-contracts.md`.

### Ordering of `versions[]` is part of what is frozen

Because rule 1 compares `new.versions[0:n]` to `old.versions[0:n]`
**positionally**, reordering the array's existing elements is a violation
even when the *set* of version objects is unchanged and every object's own
content is byte-for-byte identical to before. Swapping `versions[0]` and
`versions[1]` changes `new.versions[0]` away from `old.versions[0]`, which
fails rule 1 at index 0 — exactly the same failure a checker reports for a
genuine content edit. This document deliberately does not special-case
"same elements, different order" as a lesser or different violation: the
check is a single equality comparison over a prefix, not a set-membership
test, because a prefix comparison is the boring, mechanically simple
operation (ADR-0103) and a set-membership check would silently accept
reordering, which has no stated justification in any ADR read for this task
and removes ordering information (publish sequence) that `published_at`
alone does not fully replace once objects can move.

### A version removed and then re-added identically

Consider a PR that removes `versions[2]` from a 5-element array (now 4
elements) and, in the same PR, appends an object deep-equal to the original
`versions[2]` at the end (now 5 elements again — same length as `old`, same
*set* of version objects, same *count*).

**This is a violation, for the same reason as reordering, not a separate
special case.** Applying rule 1: `new.versions[2]` is now what was
`old.versions[3]`, `new.versions[3]` is now what was `old.versions[4]`, and
`new.versions[4]` is the re-added object — none of `new.versions[2:5]`
equals `old.versions[2:5]` positionally, so the prefix comparison fails at
index 2 regardless of the fact that the re-added object is byte-for-byte
identical to what used to sit at index 2. **The checker must never
deduplicate or match objects by content to "recognise" that the same
version came back** — doing so would mean a version's *position*, and by
extension the meaning of "was this ever removed", stops being verifiable
from the file alone. Content-equality is not the thing being protected;
prefix-stability is.

### Malformed edits that are not simple truncation or prefix mismatch

`len(new.versions) == n` but `new.versions[i] != old.versions[i]` for some
`i < n` (an in-place edit that keeps the array the same length, e.g.
rewriting `versions[1].source_sha256` to point at different bytes) is a
violation under rule 1 exactly the same way a shorter array is — the check
does not need, and should not have, a separate "was this a resize or an
edit" branch. One rule, one comparison, covers both.

## What this document does not cover

- **`page.json`** — see "Scope" above; not append-only at all.
- **Manifest content (`mod.lua` / `manifest.schema.json`) as archived per
  version.** ADR-0059 Section 2 calls "the technical manifest fields" of a
  given version "frozen forever" as part of *version-bound* content, but
  that immutability is enforced structurally — the manifest is inside the
  archived source tarball a version's `source_archive`/`source_sha256`
  already point at and hash, not duplicated as separate JSON fields on the
  version object — so there is no separate manifest-level diff rule to
  state here.
- **Whether a newly appended version object's fields are individually valid**
  (e.g. `commit` really is 40 hex characters) — that is `entry.schema.json`'s
  job, checked independently of this document's append-only rules. A PR must
  satisfy both: the new state must validate against `entry.schema.json`, and
  the transition from the old state to the new state must satisfy this
  document.
