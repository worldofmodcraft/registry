# Site build output

Contract for edge **E13** (`N7 -> N8`, site-build to site-host) in `docs/architecture/depgraph.md`.
Task 009 (site build) produces the tree this document describes; Ludwig's one-time GitHub Pages
setup (mission §6.2) and every automated deploy afterward consume it as-is, with no server-side
processing. This document states what "the build output" means precisely enough that a deploy
workflow can check it mechanically before publishing, rather than trusting that a green `npm run
build` implies a servable site.

## Scope: this document governs the contents of `dist/` at the moment of deploy

This document is about the *output* of the site build — the tree an Astro build produces and a
deploy step hands to GitHub Pages. It says nothing about what triggers a build (`contracts/
rebuild-trigger.md`, E12) or what the build reads to produce that tree (`contracts/
entry.schema.json`, `contracts/page.schema.json`, `contracts/archive-layout.md`). It also says
nothing about the URL paths inside the tree beyond what is needed to state validity —
`contracts/url-scheme.md` (E14) owns the canonical URL form; this document only requires that
`dist/`'s actual file layout is consistent with whatever E14 says, not what that form is.

## The output is the entire `dist/` directory, and nothing outside it

**A deploy publishes the complete contents of `dist/` as it exists immediately after the build
step finishes, unmodified, as static files served byte-for-byte.** No file inside `dist/` is
rewritten, renamed, or filtered between build and publish; no file outside `dist/` (source,
`node_modules/`, fixtures, `.astro/` cache) is ever published, deliberately or by accident — a
deploy step that publishes the repository root instead of `dist/` is a violation of this document
even if `dist/` itself is byte-for-byte correct, because it also exposes source and configuration
that were never meant to be public.

`dist/` itself is **never committed to the site repository** — mission §4 D3 and task 009's own
scope forbid committing `dist/`; it exists only as a build artefact, produced fresh by the deploy
workflow from source, and handed directly to the Pages deploy action. This document's rules apply
to that freshly produced tree at deploy time, not to any committed copy (there is none to check).

## `CNAME`: exact location, exact content

A file named exactly `CNAME` (no extension, case-sensitive, all uppercase) must exist at
`dist/CNAME` — the root of the published tree, not nested under any subdirectory. GitHub Pages
reads this file to configure the custom domain; its absence at deploy time means the domain
reverts to the default `*.github.io` host, which is a broken deploy for this project regardless of
whether every other file is correct.

**Content: exactly the apex domain, `worldofmodcraft.com`, as the file's entire content, lowercase,
with no scheme (`https://`), no path, no trailing slash, and no `www.` prefix** — matching E14's
canonical host. A single trailing newline is permitted (most tooling that writes a one-line file
appends one) but is not required; a reader checking this file must accept either
`worldofmodcraft.com` or `worldofmodcraft.com\n` as valid and must treat any other content —
including a URL, a subdomain, trailing whitespace beyond one newline, or a blank file — as
invalid. **An empty `CNAME` file satisfies "a file named `CNAME` exists at the tree's root" while
providing no domain configuration at all** — GitHub Pages treats an empty or malformed `CNAME` as
no custom domain configured, silently falling back to the default host; this document's own
content requirement exists specifically so "the file exists" is never treated as sufficient on
its own.

## `.nojekyll`: required, and why it is not optional decoration

GitHub Pages runs every published tree through Jekyll by default unless a file named exactly
`.nojekyll` (leading dot, all lowercase, empty content, at `dist/`'s root) is present. Jekyll's
default behaviour **excludes any file or directory whose name begins with an underscore**. Astro's
default build emits its bundled JS/CSS assets under `dist/_astro/` — a directory name beginning
with an underscore. **Without `.nojekyll` present, GitHub Pages silently drops every file under
`_astro/` from what it serves, and the deployed site loads with every page returning broken
styling and non-functional scripts, while the build itself reported success and every other
acceptance check (index exists, routes exist, CNAME correct) still passes.** This is exactly the
shape of failure this document exists to prevent: a deploy that is well-formed by every check
except this one, and broken in a way invisible to `npm run build`'s own exit code. `dist/
.nojekyll` is therefore a required file under this document, independent of whether Astro's asset
directory naming ever changes — its presence costs nothing when unneeded and its absence is
silently catastrophic when needed.

## What else must be present for a deploy to be valid

Beyond `CNAME` and `.nojekyll`, a valid `dist/` tree has:

- **`dist/index.html`** — the start page, at the tree's root, so a request for `/` (the apex
  domain with no path) resolves to real content rather than a 404 or an empty directory listing.
- **A directory or file for every mod route E14 defines**, for every mod entry the build was run
  against — e.g. `dist/mods/<ns>/<name>/index.html` for the `/mods/<ns>/<name>` URL scheme E14
  states, using whatever trailing-slash/`index.html` convention E14 settles (see that document; this
  document does not repeat it, only requires that whatever it says is actually what the file tree
  contains — a build that emits `dist/mods/<ns>/<name>.html` while E14 promises directory-style
  URLs is a mismatch this document treats as invalid output, not a cosmetic difference).
- **The Pagefind search index and its runtime assets**, at whatever path Pagefind's own build step
  writes them (its default is `dist/pagefind/`), since mission §4 D3 and task 009's acceptance
  criteria require client-side search to work against the published tree — a `dist/` missing
  Pagefind's output is incomplete even though nothing above forbids the site's *pages* from
  existing without it.
- **No absolute local filesystem paths, environment-specific values, or unresolved template
  placeholders in any served file.** This is deliberately not itemised further (checking it
  mechanically for every possible leak is a task-008/009 implementation concern, not this
  document's), but a build whose HTML contains, say, the build machine's home directory path in an
  error comment is not a valid deploy under this document's intent even though no single rule
  above names that exact case.

**A deploy is valid only when every item above is present and correct at once.** A `dist/` with a
perfect `CNAME` and `.nojekyll` but no `index.html`, or a complete page tree with a missing or
empty `CNAME`, is invalid — this document does not grade partial compliance, because a site with
any one of these wrong is not the site mission §7.3 and §7.4 describe.

## Attack attempt against this contract, recorded per acceptance criterion 3

**Attempt:** produce a `dist/` that satisfies a naive reading of the graph's one-line definition —
"the `dist/` tree + `CNAME`" — by shipping a tree that contains a `dist/` directory (non-empty,
containing *some* HTML) and a file named `CNAME` at its root, while omitting `.nojekyll` entirely.
Read only as "does `dist/` exist, and is there a file called `CNAME`", this deploy passes: both
named things are present. **What it breaks:** every asset Astro placed under `_astro/` is
served as 404 by GitHub Pages the moment Jekyll processing strips that directory, which is
everything the mission's own acceptance criterion 3 needs (Lighthouse performance, working pages)
and criterion 7 needs (a design Ludwig can actually see, rather than unstyled HTML). **What this
document does about it:** `.nojekyll` is stated above as a required file with an explanation of
the exact failure mode it prevents, specifically so "the tree exists and `CNAME` exists" is never
treated as sufficient — the "What else must be present" section exists precisely to close the gap
between the graph's one-line definition and what a deploy actually needs to work.

A second, smaller attempt: a `CNAME` file present and non-empty, but containing
`https://worldofmodcraft.com/` (scheme and trailing slash included) rather than the bare domain.
GitHub Pages' own custom-domain configuration expects a bare hostname and this form is rejected or
misinterpreted by it (behaviour that is a GitHub Pages implementation detail, not something this
document controls) — either way, "a non-empty file named `CNAME` exists" is satisfied while the
custom domain does not actually take effect. The content rule above ("exactly the apex domain ...
no scheme ... no trailing slash") is stated precisely so this shape is named as invalid rather than
left to be discovered by a broken domain after a real deploy.

## What this document does not cover

- **What triggers a build** — `contracts/rebuild-trigger.md` (E12).
- **The canonical URL form and trailing-slash convention for mod pages** —
  `contracts/url-scheme.md` (E14). This document requires consistency with whatever E14 states,
  not a duplicate statement of it.
- **DNS configuration and HTTPS enforcement at the host** — mission §6.2 (Ludwig's manual step)
  and `contracts/url-scheme.md`'s own scope.
- **Build-time data sources** (registry checkout, archive fetches) — `contracts/entry.schema.json`,
  `contracts/page.schema.json`, `contracts/archive-layout.md`.

## Questions

- **Whether a deploy workflow must mechanically verify this document's requirements (a smoke test
  over `dist/` before the Pages action runs) or whether task 009's own acceptance criteria are
  taken as sufficient verification once, at task-completion time, without a standing check on every
  future deploy.** No ADR read for this task settles this, and it is an implementation decision
  for task 008/009's workflow, not a boundary-contract question — **assumed meanwhile:** this
  document states what "valid" means; whether that gets checked by an automated step or relied on
  by convention is left to whoever implements E12/E13's workflow. **What rests on this:** if no
  automated check is ever added, a future regression (someone's Astro upgrade drops `.nojekyll`
  from a template default, for instance) would only be caught by someone noticing the live site is
  broken, not by CI.
