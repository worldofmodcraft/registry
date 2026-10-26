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

## The archived-source URL (`source_archive`)

`entry.json`'s `source_archive` is a second deterministic function of the same inputs, and nothing
else enters it:

```
source_archive = "https://archive.worldofmodcraft.com/" + tag + "/" + tag + ".tar.gz"
```

`tag` is the release tag defined in "The naming scheme" above (`ns.nm-v`). The host is the constant
`archive.worldofmodcraft.com`; the URL has scheme `https`, no port, no userinfo, no query, no
fragment and no trailing slash. This section is the only place the hostname is fixed; task 008c's
single named constant takes its value from here. The signature asset's URL is `source_archive` plus
`.minisig`; it is derived, never stored (`entry.json` carries the signature inline, in `signature`).
The **redirect target** of a request for `<tag>/<asset>` is
`https://github.com/worldofmodcraft/archive/releases/download/<tag>/<asset>` — byte for byte what
`naming.release_asset_url("worldofmodcraft", "archive", tag, asset)` returns (task 008a,
`tools/pipeline/naming.py`; decision Q-E fixes the repository).

**Worked examples** (typed literally; a consumer's derived string must equal them):

1. `mc`, `hello-world`, `1.0.0` gives the tag `mc.hello-world-1.0.0` and
   - `source_archive`: `https://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz`
   - signature URL: `https://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz.minisig`
   - redirect target of the tarball: `https://github.com/worldofmodcraft/archive/releases/download/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz`
   - redirect target of the signature: the tarball's redirect target plus `.minisig`.
2. `a`, `b`, `1.0.0-rc.1+build.5` gives the tag `a.b-1.0.0-rc.1+build.5` and
   - `source_archive`: `https://archive.worldofmodcraft.com/a.b-1.0.0-rc.1+build.5/a.b-1.0.0-rc.1+build.5.tar.gz`
   - redirect target of the tarball: `https://github.com/worldofmodcraft/archive/releases/download/a.b-1.0.0-rc.1+build.5/a.b-1.0.0-rc.1+build.5.tar.gz`

**Path safety and injectivity** (derived from the rules above, not new rules). Every character of
`tag` is in `[0-9A-Za-z._+-]`: `namespace` and `name` allow `[a-z0-9_-]`, the join adds `.` and `-`,
and a semver `version` adds `[0-9A-Za-z.+-]`. All of these are legal path characters (RFC 3986
`pchar`), so no percent-encoding is needed or permitted: `+` is written literally and `%2B` is a
different string. A tag starts with `[a-z0-9]`, so no path segment is `.` or `..`. Distinct
`(namespace, name, version)` triples give distinct URLs: `namespace` and `name` contain no `.`, so
the first `.` ends the namespace and the next `.` is inside the version; the version's major is a
digit run ending at that `.`, so the name ends at the last `-` before it. Injectivity is over byte
strings. The reserved-device-name rule in "Rejected namespaces" applies unchanged to the namespace
in this URL, which is built from the same tag. Cloudflare's wildcard matching is case-insensitive
and GitHub tags are case-sensitive, so the redirect must preserve the case of the captured path
(uppercase prerelease identifiers such as `-RC.1` are legal in semver); the manager's live checks
record whether it does.

**How the address works: a pointer, not configuration.** `archive.worldofmodcraft.com` is a real
HTTP redirect configured at Cloudflare, per the platform runbook step M12 (`docs/runbooks/
site-v1-manual-steps.md`, task 091), which is the source of truth for the rule's syntax. It is
path-only, with the status 302 chosen in task 091; nobody may depend on which of the four 3xx
statuses it sends. A **hop** is one redirect response (301, 302, 307 or 308); the response that
ends the chain is not a hop. Hop 1 is the response from `archive.worldofmodcraft.com`, and its
target is the `worldofmodcraft/archive` Release asset above (decision Q-G: a project-owned URL
fronts `source_archive`, so the registry can move off GitHub, ADR-0077, by repointing the front
without rewriting any entry). Hop 2 is GitHub's own redirect to a signed, expiring asset host
(`release-assets.githubusercontent.com`, observed in task 058) and is never stored anywhere.
Integrity comes from the hash and the signature (ADR-0041), never from the address; what that
requires of consumers is in "Consumer rules".

**Consumer rules (normative).** "Consumer" means the site (task 055), the pipeline's own checks
(task 008b), the runbook check in task 010 and any later launcher or installer.

1. A consumer compares `source_archive` by exact string equality with the URL derived above from
   the entry's own `id` and `version`; it never parses the URL and accepts one that is "close
   enough".
2. A consumer requests `archive.worldofmodcraft.com` with no query string; this applies to the
   request to the front only.
3. A consumer follows every later hop (hop 2 onward, any 301, 302, 307 or 308: GitHub, then its
   signed asset host) unchanged, including its query, only over https with TLS verified, within at
   most 5 hops in total; the hosts on those hops are not an allowlist and not a trust anchor.
4. A consumer accepts the final 2xx response body only within 52,428,800 bytes (50 MiB) and aborts
   the download at that cap. The number equals `MAX_COMPRESSED_BYTES` in `tools/pipeline/archive.py`
   and the site downloader's ceiling (`docs/pipeline/build-pipeline.md`); `archive-layout.md`
   states no cap of its own. Raising task 008a's compressed-size limit above this number requires
   amending this contract.
5. A consumer uses the received bytes only after `source_sha256` and the signature verify, meaning
   none of the rejection rules 1-11 of `signature-format.md` ("What a verifier must reject")
   applies; before that point it does not install, extract or render them.
6. A consumer never executes or parses HTML received at any hop.
7. Consumers do not enforce hop 1's target. Reason: a client that follows redirects automatically
   (`curl -L`, a browser fetch) cannot see hop 1, and this way the front can be repointed without
   a consumer release; a repoint changes runbook step M12 and the redirect-target sentence in this
   section (a contract amendment), not consumers.

**Producer obligations (task 008c writes the entry, task 008b runs the pipeline).**

1. `source_archive` is exactly the URL derived above from the entry's own `id` and `version`,
   never taken from upload output, the GitHub API or `result.json` text.
2. Before opening T1 (`contracts/append-only.rules.md`) the pipeline (i) requests the front
   without following redirects and applies the hop-1 check of "Fail closed" (a), then (ii) fetches
   `source_archive` through the full chain under the consumer rules and requires the SHA-256 of
   the received bytes to equal its own computed `source_sha256`. Any failure is a pipeline fault
   (task 082 PT10, exit 2): no T3 is written, the version stays `pending` and the run fails naming
   the URL. This is the only point where a URL that does not resolve can be stopped before it
   becomes permanent in an append-only record. The manager performs the hop-1 check live
   (runbook step M12, "the manager checks").
3. The pipeline publishes no version whose `version` contains `+` (build metadata) until a live
   Release proves that GitHub resolves `+` in `releases/download` (task 010). Such a version gets
   a T3 `rejected` with the reason "versions with build metadata (+) are not yet published —
   pending proof that GitHub resolves them (task 010)"; it is not left `pending`. The derivation
   above still defines the URL of such a version.

**Fail closed (normative).** There are two lists.

- **(a) Hop 1, checked by the producer (before T1) and the manager (live), not by consumers.** The
  hop-1 check fails when the response from `archive.worldofmodcraft.com` is anything other than a
  301, 302, 307 or 308 whose `Location` equals the redirect target byte for byte: a 200 with any
  body (for example a meta-refresh HTML page, task 058's option A), any 4xx or 5xx, any other
  `Location`.
- **(b) Everywhere, consumers and producer.** Each of these makes the artefact **unverified**: DNS
  failure (for example runbook step M12 not done yet, so the name does not resolve), TLS failure,
  any hop that is not https (no downgrade), any 4xx or 5xx on a later hop, a final response that
  is not 2xx, more than 5 hops, a body over the size cap, a hash mismatch, a signature rejection.
  Consumers then do not install, extract or render the artefact, and never fall back to another
  URL, in particular never to a self-built `github.com` URL (decision Q4). The producer does not
  write T1 and the version stays `pending`.

**Unverified in this environment** (each is a fact about Cloudflare or GitHub behaviour not yet
observed; none is a trust dependency, because "Fail closed" catches each):

- **[unverified]** Whether the Cloudflare rule preserves the case of the captured path, which
  matters for uppercase prerelease identifiers.
- **[unverified]** Whether GitHub resolves a tag containing `+` in `releases/download`.
- **[unverified]** Whether GitHub keeps an uploaded asset filename containing `+` unchanged.
- **[unverified]** How long certificate issuance for the proxied name takes.

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

> **Unverified in this environment.** The reserved-device-name list and the "matched on the
> portion before the first `.`" behaviour above are stated from well-known, longstanding, publicly
> documented Windows filesystem behaviour, not exercised against a live Windows runner or a
> Windows-hosted git clone in this environment. The rule itself does not depend on that
> confirmation — it is enforced by refusing to create the name in the first place, not by
> detecting a failure after the fact — but anyone implementing the rejection check (task 008's
> first-publish component) should confirm the exact matching behaviour (case-insensitivity, the
> before-first-`.` scope, the exact device-name list) against a real Windows machine before relying
> on this paragraph as the sole source.

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
   mainstream OS, so no further substitution or rejection rule is needed beyond these two. **This
   rule stands on its own two merits regardless of any pipeline or build-runner detail** — an end
   user on Windows cannot save the downloaded tarball under its given name, and `git` cannot create
   the loose ref for the tag, full stop, for anyone on Windows, not only on a CI runner. ADR-0040
   §1 (naming Linux, Windows and macOS runners explicitly) is cited only as supporting evidence
   that Windows is a platform this project actually targets, not as the basis for the rule itself —
   SITE-V1's mission scope excludes the build pipeline that ADR governs, so the rule must not, and
   does not, depend on it.

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
produces a release that cannot exist on Windows at all: not on a build runner specifically, but for
any end user who downloads the tarball and tries to save it, and for `git` itself when creating the
loose ref for the tag (ADR-0040 §1 is supporting evidence that Windows is a platform this project
targets; this outcome does not depend on that ADR governing the SITE-V1 build pipeline, which
mission scope excludes). Satisfying `entry.schema.json` was never sufficient on its own — schema
validity and filename validity are different properties, and this document exists specifically
because the graph's one-line E7 definition does not say so.

**Attempt 3 — a hostile or compromised redirect.** A Cloudflare account takeover (or a bad
repoint) points `archive.worldofmodcraft.com` at attacker bytes, or at another genuine signed
artefact. **Outcome: the hash does not match `source_sha256`, or `signature-format.md` rule 11
rejects the artefact because the trusted comment's `id` and `version` are not the entry's own;
at worst this is a denial of service, never a substituted install.** The producer's and the
manager's hop-1 check detects the repoint itself; consumers, which do not check hop 1, still hold
because of the hash and signature rules.

**Attempt 4 — a plausible variant URL accepted by a lenient consumer.** A consumer that parses
`source_archive` and accepts `HTTPS://ARCHIVE.WORLDOFMODCRAFT.COM/...`, `%2B` for `+`, a trailing
`/`, `?x=` or `/../` would fetch something other than the derived string. **Outcome: exact string
equality (consumer rule 1) rejects every one of these.** The redirect forwards any path to
`github.com/worldofmodcraft/archive/releases/download/`, so a consumer that fetched non-derived
paths could be steered to another file there; consumers fetch only the derived string, and
verification still applies.

## What this document does not cover

- **Which repository hosts these Releases** — decided: `worldofmodcraft/archive` (decision Q-E,
  008 umbrella F6). The redirect-target sentence of "The archived-source URL" carries it.
- **The Cloudflare rule's exact configuration** — runbook step M12 (platform) is the source of
  truth for its syntax.
- **`build_log_url`** — a repository file at `logs/<ns>.<nm>/<version>.log`, not a Release asset;
  this front does not serve it.
- **Enforcing the equality of `source_archive` with the derived URL in registry CI** — booked as a
  follow-up (needs a refresh of task 057's pins and checker code); `append-only.rules.md` T1 checks
  shape only.
- **The bytes inside the two assets** — the tarball's interior is `contracts/archive-layout.md`
  (E11); the signature's encoding is `contracts/signature-format.md` (E9).
- **Retry/idempotency behaviour if the pipeline is re-run for a version already archived** — a
  pipeline-implementation concern (task 008), constrained only by this document's uniqueness rule
  above (never overwrite an existing tag of this name).

## Questions

- (none open; task 092's Q1-Q10 were decided by Ludwig on 2026-10-26.)
