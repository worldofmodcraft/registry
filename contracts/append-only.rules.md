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

### File-level existence: creation, deletion, rename

Every rule in this document, and everything above, is phrased over a pair
`(old, new)` of **parsed values of the same file at the same path** — which
silently presumes both exist. They do not always. Across a PR, a given mod's
`entry.json` is in exactly one of **four** `(old, new)` existence states:
`absent -> absent`, `absent -> present`, `present -> present`, and
`present -> absent`. All four are listed below; three of them carry
requirements, and the fourth (`absent -> absent`) is named only so the
enumeration is complete and no reader has to wonder whether a case was
forgotten. **A rename or move is not a fifth state** — it is two of these
four states occurring at two different paths, and it is treated below after
them. Task 007's checker must classify each mod directory into one of these
states *before* any rule above can be applied, because rules 1, 3, the
in-place mutation carve-outs (T1, T2, T3) and the ordering sections all
presume the `present -> present` case implicitly.

- **`absent -> absent`.** The file exists on neither side of the PR. There is
  nothing to compare and nothing to validate; no rule in this document
  applies, and none can be violated. Stated for completeness only.
- **`absent -> present` (creation, i.e. first publish, ADR-0058 Section 1).**
  **Model this case as `n = 0`** — not as "schema validation only". There is
  no `old`, so treat the prior version array as empty and set
  `n = len(old.versions) = 0`. Everything below follows mechanically from
  that, and a checker needs no first-publish branch beyond setting `n = 0`:

  - **Rule 1 is vacuous**: `new.versions[0:0]` and `old.versions[0:0]` are
    both the empty list, so the prefix comparison succeeds trivially.
    **Rule 3 is vacuous**: `len(new.versions) < 0` is impossible. **The
    takedown carve-out is vacuous**, and so are T1 and T3: all three are
    defined only for indices `i < n`, and there are none. **"Ordering of `versions[]` is part of what
    is frozen" and "A version removed and then re-added identically" are
    vacuous**: both are consequences of rule 1's positional comparison over
    a prefix that is empty here. Read *vacuous*, not *waived* — the
    guarantee those rules express is not weaker at a first publish; there is
    simply no prior state for them to bite on yet, and from the very next PR
    onward they apply in full to everything this PR wrote.
  - **The `id`/`owner` freeze likewise has nothing to compare against** and
    is vacuous for the same reason. **Binding the namespace to an owner is
    the ownership gate's job (ADR-0058 Section 2–3), not this document's**:
    task 007 must not look here for a check that the PR's `owner` is
    legitimate, or that the confirmation text was shown — that belongs to
    whatever component authorises a first-publish PR in the first place.
    This document only ever compares an entry to its *own* prior state, and
    a first publish has no prior state to compare to.
  - **Every element of `new.versions` is a newly added element** — with
    `n = 0`, `new.versions[n:]` is the whole array. **Rules 2 and 4
    therefore apply unchanged and in full**, because neither rule's content
    depends on `old` existing:

    - **Rule 2** — every element must satisfy the version-object shape in
      `entry.schema.json`, **and every element must be born `pending`** with
      exactly the four keys rule 2 below names (ADR-0121 Q-L). A first
      publish is not exempt from the born-`pending` rule: the author's PR
      can know only a version's `version`, `commit` and `source_url`, so a
      first publish never carries a `published`, `removed` or `rejected`
      element.
    - **Rule 4** — `version` must be **pairwise-unique across
      `new.versions` as a whole**, compared by exact string equality. (Only
      the half of rule 4 that compares against `old.versions` is vacuous
      here; the pairwise half is not.) Two elements both labelled `"1.2.0"`
      in a first-publish entry are a violation of rule 4, exactly as the
      same two objects would be if they arrived in a later PR.
  - Stated flatly, because an earlier revision of this document got it wrong
    in exactly this place: **a first publish is not exempt from rules 2 and
    4, and `new` validating against `entry.schema.json` is necessary here
    but not sufficient.** `entry.schema.json` has no cross-element
    uniqueness keyword and validates one snapshot, never a birth, so it
    accepts both of the shapes rules 4 and 2 reject — a duplicate `version`
    string across two elements, and an element that is well-formed but not
    `pending` (a `published` object carrying hashes the author invented, for
    example). If creation were exempt, identical content
    could be laundered in through a namespace's *first* PR that would be
    rejected twice over as a later append: same end state, opposite verdict,
    with the guarantee depending only on which PR the data arrived in.
- **`present -> present`.** The `old`-dependent parts of this document —
  rule 1, rule 3, the T1/T2/T3 carve-outs, the `id`/`owner` freeze, and the
  "Ordering of `versions[]`", "A version removed and then re-added
  identically" and "Malformed edits" sections — govern this case, and only
  this case. Rules 2 and 4 govern it as well, but are **not** confined to
  it: they constrain newly added elements, whose content does not depend on
  `old`, and so they apply to the creation case above in full.
- **`present -> absent` (deletion).** **Always a violation.** ADR-0041 is
  titled "nothing can be unpublished" and states authors "cannot remove
  versions"; deleting `entry.json` outright removes every version at once,
  which is at least as severe as removing one, so this case must be at
  least as strict as rule 3 ("`new.versions` must never be shorter than
  `old.versions`"). A checker that finds an `old` value and no `new` value
  for a given path must itself report a violation — it must not evaluate
  no rule and let the PR pass because rules 1–5 have nothing to compare
  against an absent `new`. (The mirror of the creation model gives the same
  verdict and may be used instead: treating an absent `new` as
  `new.versions = []` makes `len(new.versions) = 0 < n` for any entry that
  had at least one version, which rule 3 rejects. Either route must end in a
  violation; silently passing must not be reachable.)
- **A rename or move of the mod directory** (e.g.
  `mods/a.b/entry.json` moving to `mods/a.c/entry.json`) **is a deletion of
  the old path plus a creation of the new one, and is therefore a
  violation** under the deletion case above — regardless of whether the new
  path's content is otherwise byte-for-byte identical to the old one's.
  This needs saying explicitly because `id` and `owner` (below) are only
  ever compared *within one file's own `(old, new)` pair at a fixed path*;
  without this case stated, a rename would let a PR sidestep the frozen-
  `id`/`owner` rule entirely by "moving" an entry to a new path instead of
  editing the old path's `id` or `owner` field in place — the two
  independent pairs it produces (one pure deletion, one pure creation)
  never trigger rule 1's same-path comparison at all.

## Fields outside `versions[]`: `id` and `owner`

`entry.json` has exactly two top-level fields besides `versions`: `id` and
`owner` (with `owner`'s three subfields `provider`, `id`, `name_at_registration`).

**Both are frozen. Besides `versions` — whose permitted changes (appending,
and the transitions T1, T2 and T3 below) are the entire subject of this
document — `entry.json` currently has no other mutable top-level field.**
Concretely: `new.id != old.id`, or `new.owner` not deep-equal to
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

## The version object: four states (ADR-0121)

A version object is in exactly one of four states, selected by its `status`,
and each state has an exact key set: no key may be missing and no other key
may be present. `entry.schema.json` enforces these key sets for a snapshot
(one `oneOf` branch per status); this document says which state may follow
which.

| `status` | exact keys (no others) | created or changed by |
|---|---|---|
| `pending` | `version`, `commit`, `source_url`, `status` | the author's PR, as a newly appended element only |
| `published` | the four `pending` keys plus `source_archive`, `source_sha256`, `signature`, `key_id`, `published_at` (nine keys) | transition T1 only |
| `removed` | the nine `published` keys plus `reason` (non-empty after trimming) | transition T2 (the takedown) only |
| `rejected` | the four `pending` keys plus `reason` (non-empty after trimming) and `build_log_url` (an `https://` URL); none of `source_archive`, `source_sha256`, `signature`, `key_id`, `published_at` | transition T3 only |

`deprecated` is not a version status: it is a mod-level flag in `page.json`
(ADR-0059 Section 2). A `pending` or `rejected` version has no archive, so a
consumer must treat it as not resolvable and say "exists but is not yet
published", never "not found" (ADR-0121 Consequences; that behaviour belongs
to the launcher, the site and the resolver, not to this document).

## `versions[]`: append-only, order-preserving

Let `n = len(old.versions)`. The check is:

1. **`new.versions[0:n]` must be deep-equal, element-for-element and in the
   same order, to `old.versions[0:n]`, with exactly three permitted exceptions:
   the transitions T1, T2 and T3 defined in "The permitted in-place mutations" below.**
   Every version object that existed before this PR must appear unchanged at
   the same index in the PR's version, unless that element is undergoing one
   of the three transitions, in which case the rules in that transition's
   section apply to that one element instead of plain deep-equality. This is
   a four-branch mechanism (unchanged, T1, T2 or T3) rather than a single
   unconditional equality, and each element is classified independently;
   everything below is a consequence of it, spelled out because each one is a
   place a diff checker could reasonably get it wrong.
2. **`new.versions` may be longer than `old.versions`** (`len(new.versions)
   >= n`); every element from index `n` onward is a newly added version
   object and must itself satisfy the version-object shape
   `entry.schema.json` defines for `versions[]` items (the file as a whole
   must of course validate too). **In addition, the born state is fixed
   (ADR-0121 Q-L).** Every newly appended element must be `pending` and carry exactly the four keys `version`, `commit`, `source_url` and `status`. An
   element appended already `published`, `removed` or `rejected`, or
   `pending` with a fifth key, is a violation, although
   `entry.schema.json` alone accepts a well-formed `published`, `removed` or
   `rejected` object as a snapshot. Without this rule an author could write
   their own hashes and skip the pipeline (attack 1 below); `published` is
   reached only by T1, `removed` only by T2 and `rejected` only by T3, never at
   birth. No registry entry exists to migrate (`git ls-tree origin/main mods`
   printed nothing when this rule was written). That a `reason` is non-empty
   after trimming whitespace is checked by the transition rules (T2, T3);
   `entry.schema.json` cannot see it, because `"   "` satisfies its
   `minLength`.
3. **`new.versions` must never be shorter than `old.versions`**
   (`len(new.versions) < n` is always a violation) — a version object can
   never be **deleted from the array**, whatever its status: a `pending`
   version cannot be withdrawn and a `rejected` version is kept as the
   record that it was proposed and why it failed (ADR-0121). Note the
   two senses of "remove" in this document: rule 3 is about *array membership*,
   whereas a takedown (T2, below) sets an existing element's `status` to the
   string `"removed"` while leaving that element in the array, at the same
   index, with the same `version`. A takedown is therefore not a deletion
   and never engages rule 3.
4. **Every newly added version's `version` field must be unique across
   `new.versions` as a whole** — distinct from every existing version's
   `version` field (i.e. from every value in `old.versions`; `version` is
   frozen even under the transitions T1, T2 and T3 below, so every
   `new.versions[0:n]` element's `version` field is always identical to the
   corresponding `old.versions[i].version`, even on an index where
   rule 1's exceptions permit other fields to differ — `new.versions[0:n]`
   is therefore not deep-equal to `old.versions` in general, but it is
   always equal to it field-by-field on `version` specifically) **and**
   pairwise-distinct from every other newly added version's `version` field
   in the same PR (`new.versions[n:]`). Two
   version objects added in the *same* PR that both carry `version:
   "2.0.0"` violate this rule exactly as if one of them had matched an
   existing entry — the rule is stated over `new.versions` as a whole, not
   "against history alone", precisely so this case is not a gap. ADR-0041's
   "existing hashes can never be updated, only new versions added" presumes
   each version string identifies at most one version object; without this
   rule a PR could not modify `versions[2]` in place but could add a second
   object with the same `version` string and a different `commit`/hash
   (whether that second object collides with an existing element or with
   another new element in the same PR), which achieves the same practical
   deception (which build is "the" 1.2.0?) through an addition instead of an
   edit. This document treats the collides-with-history case as append-only's
   rule 1 already covering it in spirit, but names both the history case and
   the within-PR case explicitly since neither is a literal
   prefix-comparison failure.

   **The comparison is exact string equality on the `version` field, not
   semver-normalised comparison.** `"1.0.0"` and `"1.0.0+build.2"` are
   different strings and therefore do not collide under this rule, even
   though semver treats build metadata as not affecting precedence — two
   such textually-different, semver-equivalent strings can both be present
   in `new.versions` without violating this rule. Whether that gap should be
   closed (semver-aware collision detection) is not settled by any ADR read
   for this task and is booked as a question (Q11) in
   `docs/tasks/006-contracts.md` rather than invented here.
5. **No rule in this document requires new version numbers to be
   numerically greater than existing ones**, or requires `published_at`
   timestamps to be monotonically increasing. Nothing read for this task
   (ADR-0041, ADR-0042) states such a constraint, and inventing one here
   would be exactly the kind of undocumented registry semantics this task's
   instructions forbid. If monotonic version ordering is wanted, it is a
   separate, not-yet-written decision — booked under Questions in
   `docs/tasks/006-contracts.md`.

### The permitted in-place mutations

Rule 1 has exactly three exceptions, the transitions T1, T2 and T3, stated
here at field level so a checker can implement each without inference. Each
applies to one existing element at a fixed index `i < n`, is defined by that
element's old and new `status` and by exact key sets, and happens at most once
per element. Every other change to an existing element is a violation of
rule 1. None of them changes array length or ordering: they never permit
removing an element, adding one at a non-final position, or reordering, and
rules 2 and 3 above and "Ordering of `versions[]`" below are untouched by them.

#### T1: `pending -> published`, the pipeline's write-back (ADR-0121)

For an index `i < n`, `new.versions[i]` is permitted to differ from
`old.versions[i]` under T1 if, and only if, **all** of the following hold:

1. `old.versions[i].status == "pending"` and
   `new.versions[i].status == "published"`.
2. `version`, `commit` and `source_url` are deep-equal to the old values: the
   fields the author supplied are frozen.
3. Each of `source_archive`, `source_sha256`, `signature`, `key_id` and
   `published_at` is present in `new.versions[i]`, absent from
   `old.versions[i]`, and satisfies its pattern (or, for `signature` and
   `key_id`, its minimum length) in `entry.schema.json`.
4. `new.versions[i]` has exactly the nine keys of the `published` row of the
   shape table, so no key outside them, and in particular no `reason` and no
   `build_log_url`.
5. The array is otherwise untouched: rules 1 to 3 and "Ordering of
   `versions[]`" apply to every other element.

T1 happens exactly once, by structure: it requires
`old.versions[i].status == "pending"`, and a `pending` element has none of the
five pipeline-written fields. After T1 the element is `published`, and a
`published` element is covered by plain deep-equality under rule 1 (or by T2),
so the five fields can never be written a second time. `published -> pending`
and `pending -> pending` with any change are violations of rule 1.

Nothing else changes under T1: `id` and `owner` stay frozen, `page.json` is
not part of this document, and no element is added, removed or reordered.

T1 is checked for shape only. This document cannot check that
`source_sha256` is the hash of the archive or that `signature` verifies,
because no checker built from it has the tarball or the key; that is the job
of the verifiers of `signature-format.md`, the site's verification and the
launcher. A wrong but well-formed write-back is also never corrected by
rewriting (T1 happens once); the remedy is a new version or a takedown.

**Worked example — permitted T1.** `old.versions[0]`:

```json
{
  "version": "1.0.0",
  "commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "source_url": "https://github.com/example/mod",
  "status": "pending"
}
```

`new.versions[0]` (same index; the author keys unchanged, five keys added,
`status` changed):

```json
{
  "version": "1.0.0",
  "commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "source_url": "https://github.com/example/mod",
  "source_archive": "https://cdn.worldofmodcraft.org/archives/example-mod-1.0.0.tar.gz",
  "source_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "signature": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  "key_id": "E7A1B2C3D4E5F607",
  "published_at": "2026-10-15T09:00:00Z",
  "status": "published"
}
```

**Worked counter-example.** The same `new.versions[0]` with `commit` changed
to `dddd…`, or with `source_sha256` missing, or with an extra `reason` key,
is a violation: the author-supplied fields are frozen, all five pipeline-written
fields are required, and the key set is exact.

#### T2: `published -> removed`, the takedown (ADR-0041)

T2 is the transition ADR-0041 defined, unchanged by ADR-0121 except that it is
now one of three. For an index `i < n` (an element that existed in
`old.versions`), `new.versions[i]` is permitted to differ from
`old.versions[i]` under T2 if, and only if, **all** of the following hold:

- `old.versions[i].status == "published"` **and**
  `new.versions[i].status == "removed"`. From an element whose old status is `published`, this document permits exactly one status transition: T2. (`published` staying
  `published`, i.e. no change at all, is not a transition and is covered by
  plain deep-equality under rule 1, not by this section.)
- `new.versions[i].reason` is present, and **non-empty after stripping
  leading and trailing whitespace** — `"   "` (spaces only), a lone tab, or
  a string of only newlines does not satisfy this; the checker must trim
  before checking length, not rely on `entry.schema.json`'s own
  `minLength: 1`, which `"   "` already satisfies and therefore cannot
  catch on its own. ADR-0041: a removed version's "registry entry [is]
  kept with status **and reason**" **so dependency resolution can explain
  the failure** — a reason a human or a resolver cannot read as text
  explains nothing, so a takedown transition without a non-empty (post-
  trim) `reason` is a violation, not a takedown that merely omitted an
  optional field.
- **Every other field of `new.versions[i]` is deep-equal to the same field
  of `old.versions[i]`**: `version`, `commit`, `source_url`,
  `source_archive`, `source_sha256`, `signature`, `key_id` and
  `published_at` must all be unchanged. Changing any of them alongside the
  `status` transition is a violation — the checker must not accept the
  element merely because its `status` changed legitimately; it must still
  verify every other field individually and report the element as a
  violation if any of them differs.

**The transition is one-way and terminal.** `old.versions[i].status ==
"removed"` and `new.versions[i].status == "published"` (reverting a
takedown) is a violation — no rule in this document, and nothing in
ADR-0041, permits restoring a removed version. Once an element's `status`
is `"removed"`, that element is frozen completely, `reason` included:
if `old.versions[i].status == "removed"`, then *any* field of
`new.versions[i]` differing from `old.versions[i]` — `reason` included — is
a violation under plain rule 1, because the exception above only applies
when the *old* status is `"published"`. Editing the wording of an
already-removed version's `reason` is therefore exactly as much a violation
as editing its `commit`. This is deliberately conservative (ADR-0103): a
correction to a takedown's reason text is a decision no ADR has made, not a
hole this document leaves open by default.

**This document defines the shape of a legal takedown, not who may perform
one.** A field-level diff checker built from this document cannot, by
itself, distinguish an authorised legal takedown from an attacker abusing
this carve-out to erase an inconvenient version's original content by
relabelling it "removed" with a fabricated `reason`.

**The merge gate, stated truthfully.** `main` on the `registry` repository
is branch-protected, and `womcraft` is the **only** collaborator on
`worldofmodcraft/registry` (verified directly against the GitHub API,
2026-09-03: one entry, `role_name: "admin"`). Both Ludwig and the manager
(AI) session that opens and merges PRs on his behalf authenticate and
merge as that same `womcraft` account — GitHub records no distinction
between "Ludwig merged this" and "the manager session merged this". So, as
a matter of **technical** access, it is false to say "only Ludwig can
merge a PR" — this document must not claim that, and does not below.

**Ludwig's decision, 2026-09-03, restated against that corrected premise:**
the authorisation for a takedown transition is not GitHub's merge
permission alone (which the manager session already shares), but a
**standing doctrine rule** layered on top of it: **a takedown PR is never
merged by the manager on its own authority, regardless of technical
ability to do so.** It requires Ludwig's explicit written approval, given
in session, referenced in the PR, before the manager merges it. (This rule
is in `MANAGER.md` Section 7's "always requires Ludwig" list, put there by
task 028 and merged to `main` as commit `c5d5d7a`, PR #17 — if
`MANAGER.md` ever conflicts with this paragraph,
`MANAGER.md` is the current source of truth and this paragraph is stale
and needs a fix commit.) The `reason` text, together with the PR's own
history and Ludwig's referenced approval, stays in git forever as the
audit record. Ludwig's own framing, recorded verbatim because the
reasoning is the point: *"it restores the human gate as doctrine where it
can't (yet) be physics."* No separate signed takedown record or
authorisation check is introduced by this document, and task 007's checker
must not invent one — its job is exactly the shape rules stated above (one
status transition, `reason` required and non-empty after trimming, every
other field frozen, one-way), and nothing about *who* is allowed to merge
such a PR or approve it.

**Revisit condition — present tense, not a future contingency.** Merge
rights already extend beyond a single human: the manager session merges
under the very same `womcraft` account a human uses, so "one trusted
person" was never an accurate description of the *technical* gate, only of
who currently holds *approval* authority under the doctrine rule above.
**Option 3** from the choices put to Ludwig (a separate signed takedown
record, present in the same PR, that the checker itself requires before
accepting the status transition) is the **named upgrade for phase 3**,
due the moment merge rights extend to accounts beyond `womcraft` itself —
external moderators, a genuine multi-account governance change — not a
contingency that may never arrive. At that point the doctrine rule above
stops being sufficient by itself (it depends on there being exactly one
account for Ludwig's approval to gate), and the carve-out in this section
becomes an unguarded hole rather than a doctrine-gated one.

**Worked example — permitted transition.**

`old.versions[2]`:

```json
{
  "version": "1.4.0",
  "commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "source_url": "https://github.com/example/mod",
  "source_archive": "https://cdn.worldofmodcraft.org/archives/example-mod-1.4.0.tar.gz",
  "source_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "signature": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  "key_id": "E7A1B2C3D4E5F607",
  "published_at": "2026-06-01T00:00:00Z",
  "status": "published"
}
```

`new.versions[2]` (same PR, same index — everything but `status` and
`reason` unchanged):

```json
{
  "version": "1.4.0",
  "commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "source_url": "https://github.com/example/mod",
  "source_archive": "https://cdn.worldofmodcraft.org/archives/example-mod-1.4.0.tar.gz",
  "source_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "signature": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  "key_id": "E7A1B2C3D4E5F607",
  "published_at": "2026-06-01T00:00:00Z",
  "status": "removed",
  "reason": "Contained a Blizzard-derived asset reported after publish; artefacts pulled per ADR-0041."
}
```

Permitted: `status` transitions `"published"` -> `"removed"`; `reason` is
new, present and non-empty; every other field (`version`, `commit`,
`source_url`, `source_archive`, `source_sha256`, `signature`, `key_id`,
`published_at`) is unchanged.

**Worked counter-example — same transition, one other field also changed.**

Same `old.versions[2]` as above. `new.versions[2]`:

```json
{
  "version": "1.4.0",
  "commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "source_url": "https://github.com/example/mod",
  "source_archive": "https://cdn.worldofmodcraft.org/archives/example-mod-1.4.0.tar.gz",
  "source_sha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  "signature": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  "key_id": "E7A1B2C3D4E5F607",
  "published_at": "2026-06-01T00:00:00Z",
  "status": "removed",
  "reason": "Contained a Blizzard-derived asset reported after publish; artefacts pulled per ADR-0041."
}
```

**Violation:** `source_sha256` changed (`bbbb…` -> `dddd…`) alongside the
`status` transition. The checker must reject this even though the `status`
transition itself is exactly the permitted one — the carve-out authorises
changing `status` (and adding `reason`) only, never a licence to change
anything else on the same element in the same PR. A checker that accepts
this element because "`status` changed to `removed`, that's allowed"
without separately diffing every other field would silently let a takedown
PR also rewrite which artefact a version's hash points at.

#### T3: `pending -> rejected`, a build that will never succeed (ADR-0121 Q-J)

For an index `i < n`, `new.versions[i]` is permitted to differ from
`old.versions[i]` under T3 if, and only if, **all** of the following hold:

1. `old.versions[i].status == "pending"` and
   `new.versions[i].status == "rejected"`.
2. `version`, `commit` and `source_url` are deep-equal to the old values.
3. `reason` is present in `new.versions[i]`, absent from `old.versions[i]`, a
   string, and non-empty after stripping leading and trailing whitespace;
   `build_log_url` is present in `new.versions[i]`, absent from
   `old.versions[i]`, and matches `^https://\S+$`.
4. `new.versions[i]` has exactly the keys of the `rejected` row of the shape table: none of the five pipeline-written fields of T1, and nothing else.
5. The array is otherwise untouched: rules 1 to 3 and "Ordering of
   `versions[]`" apply to every other element.

`rejected` is terminal and one-way: `rejected -> anything` is a violation of rule 1, and so is `rejected -> rejected` with any change, `reason` included. A changed `reason` is not a correction mechanism; the fix for a failed build is a new version. A `rejected` element is never deleted (rule 3) and its `version` string stays occupied (rule 4). A `rejected` version is never installable or resolvable.

T3 is checked for shape only, like T1: whether the build really failed, and
whether `build_log_url` points at a true log, cannot be checked by this
document. Consumers treat `pending` and `rejected` as not resolvable and say
"exists but is not yet published" rather than "not found" (ADR-0121
Consequences); that behaviour belongs to the launcher, the site and the
resolver and is recorded here only as a dependency.

**Worked example — permitted T3.** `old.versions[1]`:

```json
{
  "version": "1.1.0",
  "commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "source_url": "https://github.com/example/mod",
  "status": "pending"
}
```

`new.versions[1]`:

```json
{
  "version": "1.1.0",
  "commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "source_url": "https://github.com/example/mod",
  "status": "rejected",
  "reason": "Build failed: the manifest declares a dependency that does not exist.",
  "build_log_url": "https://builds.worldofmodcraft.org/logs/example-mod-1.1.0.txt"
}
```

**Worked counter-example.** The same element with `reason` set to `"   "`, or
with `build_log_url` starting `http://`, or carrying a `signature` key, is a
violation.

#### Coexistence of T1, T2 and T3

- T1 and T3 start from `pending`, T2 starts from `published`, and each ends in
  a different state, so one element cannot undergo two of them in one PR.
  `pending -> removed` is a violation (nothing was archived, so there is
  nothing to pull), and so is `published -> rejected`. A T1 element carrying a
  `reason` or a `build_log_url` is a violation, and so is a T3 element carrying
  any of the five pipeline-written fields (the key sets above are exact).
- **Shape layer and authority layer.** This document classifies each element
  independently. A PR holding a T1 on one version and a T2 or T3 on another is shape-legal. Who may carry which
  belongs to `ownership.md`: its `R11` takedown PR must contain nothing but
  takedown mutations, which excludes T1 and T3 in the same PR, and the
  pipeline's carve-out (a sibling task) must be keyed on the pipeline identity
  and on T1 or T3 mutations only.
- **Fail closed.** Until `ownership.md` carries the pipeline-identity carve-out for T1 and T3, a checker implementing T1 or T3 must reject every PR that contains a T1 or T3 mutation, whoever authors it. Without this default an author could write their own `published` or `rejected` fields.
- Authority for T1 and T3 is therefore not defined by this document. It defines the shape of the transitions, as the T2 section says of the takedown.

#### Attack attempts the contract must answer

1. **Author self-publishes.** A PR appends a version already `published`
   with invented hashes. Answer: rule 2 and the shape table reject a
   born-`published` element. Were that rule absent, only `ownership.md` and the
   verification on install would stand between a forged object and users.
2. **Garbage write-back by the pipeline identity.** A compromised or buggy
   pipeline PR writes a well-formed but wrong `source_sha256`. This document
   cannot reject it, because T1 is shape only. The defences are the
   pipeline-identity carve-out keyed on "exactly T1", the fresh hash and
   signature verification on install (`signature-format.md`), and the fact
   that a wrong hash cannot be rewritten: the remedy is a new version or a
   takedown. This is a known limit, not a hidden one.
3. **Splicing a takedown into the pipeline PR** so a version vanishes
   unnoticed. Shape-legal per element, rejected at the authority layer (`R11`
   "nothing but takedown mutations"; the carve-out "exactly T1 or T3"). The tests
   belong to the sibling tasks; this document records the dependency.
4. **Pending squatting.** An author appends `pending` versions that will never
   build, burning version strings. Rule 4 makes the squat permanent; T3 turns
   each such version into a recorded, explained terminal state but does not
   prevent the squat (ADR-0121 Consequences). The cost falls on the
   squatter's own namespace.
5. **Forged rejection.** An author marks their own `pending` version
   `rejected` with a self-chosen reason, to skip the pipeline and retry the
   same string. Shape-legal here (T3 is shape only), rejected by the
   fail-closed rule and later by the ownership carve-out keyed on the pipeline
   identity; this is why that carve-out covers T3 as well as T1.

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
violation under rule 1 exactly the same way a shorter array is, **unless**
the difference at that index is exactly one of the transitions T1, T2 or T3
described in "The permitted in-place mutations" above, field by field. A
checker does not need, and should not have, a separate "was this a resize or
an edit" branch to decide *that* something changed at index `i`; it does
need the T1, T2 and T3 checks above to decide, for each `i < n` where a
difference is found, whether that specific difference is one of the three
permitted shapes or a violation. Rewriting `versions[1].source_sha256` while leaving
`status` alone is still a violation; transitioning `status` to `"removed"`
while *also* rewriting `source_sha256` is still a violation too — only the
exact shapes spelled out in the T1, T2 and T3 sections are exempt from this
paragraph's rule.

## What this document does not cover

- **`page.json`** — see "Scope" above; not append-only at all.
- **Who may perform T1, T2 or T3.** This document defines shapes, not authority (see "Coexistence of T1, T2 and T3"); authority is `ownership.md`'s, and until its pipeline carve-out exists every T1 or T3 mutation is rejected.
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
