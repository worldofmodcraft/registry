# Public URL scheme

Contract for edge **E14** (`N8 -> public`) in `docs/architecture/depgraph.md`. This is the last
edge in the graph — what an actual visitor, or any code outside this project entirely (a search
engine, a social-media unfurl, a hand-typed URL, a future `modcraft://` launcher resolving to a
web fallback), sees and depends on. Unlike every other contract in this task, there is no second
internal component to keep in sync here — the "other side" of this edge is the public internet,
which cannot be asked to re-read a fixed document if this project changes its mind later. That
makes precision here, if anything, more consequential than elsewhere: this document states the one
canonical form the site generator must emit and any future link builder must reproduce, without
either one guessing at the other's behaviour.

## Scope

This document fixes: the scheme and host, the path form for a mod page, what a namespace or name
needing escaping would require (and whether that case is currently reachable at all), and whether
a trailing slash is part of the canonical form. It does not fix what a mod page contains
(`contracts/entry.schema.json`, `contracts/page.schema.json`, mission §4 D3's own acceptance
criteria) or how the file tree backing these URLs is produced (`contracts/site-output.md`, E13) —
only the URL a client actually requests.

## Scheme and host: `https://worldofmodcraft.com`, always

The canonical scheme is `https`, on the apex host `worldofmodcraft.com` — matching `contracts/
site-output.md`'s `CNAME` content exactly (both name the same bare apex domain; a mismatch between
the two documents would be a bug in one of them). A request over plain `http` must be redirected
to the `https` equivalent; this is GitHub Pages' "Enforce HTTPS" setting, which is Ludwig's own
one-time manual toggle (mission §6.2), not something this document or any code in this project
implements directly — this document only states that the canonical form is always `https`, so
nothing in the site's own generated links, sitemaps, or `<link rel="canonical">` tags should ever
emit a bare `http://` URL for itself.

**No subdomain (`www.worldofmodcraft.com` or any other) is part of this scheme.** No ADR or
mission document read for this task reserves or configures a `www` host, and this document does
not invent one — see Questions below for what is left open here.

## Path form for a mod page: `/mods/<namespace>/<name>`, no trailing slash

The canonical path for one mod's page is exactly `/mods/` followed by the mod's `namespace`, a
single `/`, and its `name` — the two halves of `entry.schema.json`'s `id` field, split on `id`'s
own `:` separator, each substituted verbatim (see "Escaping" below for why "verbatim" is safe
here) and **with no trailing slash**: `https://worldofmodcraft.com/mods/mc/hello-world`, not
`.../mods/mc/hello-world/`. This matches the graph's own one-line edge definition literally (`/mods
/<ns>/<name>`, no trailing `/` shown), and this document fixes it as the canonical form rather than
treating the graph's line as merely illustrative.

**A trailing-slash variant may or may not resolve to the same content depending on how the static
host serves extension-less paths** (GitHub Pages' own path-resolution behaviour, not something
this project configures) — this document does not forbid a host from also answering requests to
the trailing-slash form; it forbids the *site itself* from treating that form as canonical. Every
link the site generates to a mod page — internal navigation, the browse page, Pagefind's indexed
URLs, any `<link rel="canonical">` tag, any future sitemap — must use the no-trailing-slash form
above, consistently, and a future link builder outside this codebase (a browser extension, a
`modcraft://` fallback page, a third-party tool) reproducing this scheme independently must
produce the identical string for the identical mod, not a slash-variant that happens to also
serve the right page by accident of host behaviour.

**Delimiter choice.** `/` is used to join `namespace` and `name` here, distinct from `contracts/
artifact-naming.md`'s choice of `.` for the same pair — deliberately different, because each
delimiter is the natural one for its own context: `/` is what a URL path already uses to separate
segments (using `.` here would put both halves in a single segment for no reason), while `.` was
needed in E7 specifically because `/` is not legal inside a single git ref or filename component.
Neither document borrows the other's delimiter; a reader must not assume the two naming schemes
are otherwise related beyond both ultimately identifying the same `(namespace, name)` pair.

## Escaping: not reachable today, defined anyway for the case it ever is

`entry.schema.json`'s `id` pattern (`^[a-z0-9][a-z0-9_-]*:[a-z0-9][a-z0-9_-]*$`) restricts both
`namespace` and `name` to lowercase ASCII letters, digits, `_` and `-` — every one of these
characters is an RFC 3986 **unreserved** character, legal in a URL path segment with no
percent-encoding, ever. **Under the schema as it exists today, no registered mod's `namespace` or
`name` ever requires escaping to appear in this URL scheme, and this document's path form above is
always reachable by direct, unescaped substitution.** This is stated as a fact about the current
schema, not assumed silently — a reader must not add a percent-encoding step "just in case" that
this document does not call for, since doing so on already-unreserved characters would be a no-op
at best and a source of double-encoding bugs at worst.

**If a future change to `entry.schema.json`'s `id` pattern ever admits a character outside this
unreserved set**, this document's fallback rule is: percent-encode that character per RFC 3986 in
the path segment, using uppercase hex digits in the `%XX` escape, and decode with the same rule on
the reading side. This document does not attempt anything more specific than that (no
project-specific escaping table) because there is, at present, no reachable input this rule would
ever apply to, and inventing more machinery than "follow the standard" for a case the current
schema makes impossible would be exactly the unearned cleverness ADR-0103 warns against.

## Attack attempts against this contract, recorded per acceptance criterion 3

**Attempt 1 — build the URL from a display label instead of the registry id.** A link builder
(the site's own generator, or code outside this repository, e.g. a browser extension resolving a
shared link) could read "the URL scheme is `/mods/<ns>/<name>`" and interpolate whatever string it
already has *labelled* as the namespace or name in its own data — for instance,
`entry.schema.json`'s `owner.name_at_registration` (a human display string, explicitly *not* used
for any identity comparison per that field's own description) or a title-cased display form a page
template might use for headings — instead of the raw, lowercase `id` fields this document actually
means. The result, `/mods/MyCoolNamespace/Hello-World` instead of `/mods/mc/hello-world`, is a
syntactically valid path matching the letter of "`/mods/<ns>/<name>`" while pointing at a URL the
site never generates and will 404 on — two independently-written pieces of code, both nominally
"following the URL scheme," disagreeing on what "the namespace" even refers to. **What this
document does about it:** stating explicitly, in the path-form section above, that the substituted
values are `entry.schema.json`'s own `namespace`/`name` (the lowercase halves of `id`) and nothing
display-oriented, and separately, in "Escaping," that no case transformation of any kind is
applied — the values go in exactly as they are stored, never re-cased for presentation.

**Attempt 2 — treat the trailing slash as immaterial because "it's the same page."** A generator
could emit `/mods/mc/hello-world/` (trailing slash) reasoning that since a visitor reaches the same
content either way on a host that resolves both forms, the exact string does not matter — this
satisfies "produces a working URL matching `/mods/<ns>/<name>`" under a reading that only checks
whether the page loads. **What it breaks:** a canonical-URL guarantee is not about whether a page
loads, it is about there being exactly one string every reference to that page agrees on — a
sitemap entry, a `<link rel="canonical">` tag, and Pagefind's own indexed URL for the identical mod
must be byte-identical to be useful for deduplication, caching, and search-engine canonicalisation,
and two spellings that both happen to render the same HTML defeat that even though neither one is
individually "wrong" in isolation. **What this document does about it:** fixing "no trailing
slash" as the canonical form explicitly, rather than leaving "the same page either way" as
implicitly good enough.

## What this document does not cover

- **Mod page content** — `contracts/entry.schema.json`, `contracts/page.schema.json`, mission §4
  D3's acceptance criteria.
- **How the file tree backing these URLs is produced or what marks a deploy valid** —
  `contracts/site-output.md` (E13); this document only fixes the URL a client requests, not the
  file path on disk that answers it (though the two are related by whatever routing convention
  E13's own "what else must be present" section names).
- **Non-mod-page routes** (the start page, browse page, About/Licensing page, search) — not part
  of the `/mods/<ns>/<name>` scheme this edge names, and not fixed by any graph edge read for this
  task.

## Questions

- **Whether `www.worldofmodcraft.com` should exist at all, and if so, whether it redirects to the
  apex or serves independently.** No ADR, the mission, or `contracts/site-output.md`'s `CNAME`
  content (the bare apex domain only) addresses this. **Assumed meanwhile:** `www` is not
  configured, reserved, or part of this scheme at all — a request to it is undefined, host-level
  behaviour (most likely an unresolved DNS lookup, since no record for it is described anywhere
  read for this task) outside this project's control. **What rests on this:** if Ludwig's DNS
  setup (mission §6.2) ever adds a `www` record pointing at the same GitHub Pages target, this
  document does not yet say whether that should redirect to the apex or be treated as a separate,
  unsupported host — worth settling before that DNS record is added, not after.
