# Ownership check: the numeric account id, never the username string

Contract for edge **E16** (`author (forge identity) -> N3`) in `docs/architecture/depgraph.md`
(platform repository), added by amendment on Ludwig's explicit approval (task 032, option A,
2026-09-05). Task 007 implements the ownership gate directly from this document: every ambiguity
left here becomes a bug there, exactly as `contracts/append-only.rules.md` states for its own
edge (E4).

## Scope: what this document governs, and what it deliberately does not

This document answers exactly one question: **is the account that opened this PR authorised to
touch every namespace it touches?** It is the check `contracts/append-only.rules.md` names and
declines to perform itself: "Binding the namespace to an owner is the ownership gate's job
(ADR-0058 Section 2–3), not this document's." That delegation is correct, and this document is
its other half.

This document does **not** govern:
- **Whether `owner` may change after it is first set.** That is `append-only.rules.md`'s frozen-
  field rule ("no PR may ever change either, not even one from the namespace's own owner"). This
  document only decides who may cause the *first* write of `owner`, and who may add a version
  once `owner` already exists — never whether `owner` itself may later be edited. The two
  documents work together: this one gates identity, that one gates mutation, and neither
  substitutes for the other.
- **Schema shape or PR classification** — N3's other two jobs (`docs/architecture/depgraph.md`),
  owned by `contracts/entry.schema.json` and task 007's own classifier respectively.
- **Reserved-namespace list membership itself** (which namespaces are on the list, and why) —
  that is ADR-0119 and `reserved-namespaces.json`. This document only states how the identity
  check behaves once a namespace is known to be on that list.

## The comparison model: `old.owner`, never `new.owner`

This document adopts `append-only.rules.md`'s own `old`/`new` vocabulary: `old` is the parsed
`entry.json` at the PR's merge-base with the target branch; `new` is the parsed `entry.json` in
the PR branch. **The ownership check always compares the PR author's real numeric account id
against `old.owner.id` (and `old.owner.provider` — see "Provider is part of the comparison,
not just id" below) — it must never read the id to compare against out of `new.owner`, the
version of the file the PR itself proposes.** This single rule is stated up front, ahead of
everything else below, because getting it backwards produces a checker that looks correct on
every well-behaved input and silently authorises the one attack this document exists to prevent
(Attack attempt 1, below).

For a namespace that does not yet exist on the target branch (no `old` value — this is a first
publish), there is nothing in `old` to compare against; "What a first publish binds" below states
the rule that applies instead.

## What identity is compared: the forge's numeric account id, never the username string

**The check compares the PR author's numeric account id against `owner.id`. It never compares
usernames, display names, or `owner.name_at_registration`.** This must hold precisely because a
username can be released by its holder — deliberately, by renaming, or involuntarily, by account
deletion — and later registered by a completely different person, while a numeric account id
identifies exactly one account for that account's entire lifetime and is never reassigned to a
different one. A check that "helpfully" compares names instead of ids reopens exactly the
namespace-capture attack ADR-0058 §2 exists to close: once a username is recycled, a
username-based check cannot tell the new holder apart from the original owner.

**Verified, live, against this project's own registry (re-run in this fix round, 2026-09-06):**
```
$ gh api repos/worldofmodcraft/registry/pulls/3 --jq '{merged, user:{login:.user.login,id:.user.id}}'
{"merged":true,"user":{"id":324089373,"login":"womcraft"}}
```
(A two-key `--jq` object filter cannot emit a third `number` field; an earlier revision of this
document pasted `{"merged":true,"number":3,"user":{...}}` here, which the filter above cannot
produce under any input. That was a fabrication, found and corrected in review round 1 — see
`docs/tasks/032-ownership-contract.md`'s fix-round-1 log and `docs/tasks/032-verify.sh`, whose
`B6` checks assert this object's exact key set against both the current text and the pre-fix blob.)
This is the real shape the check reads from: a PR's `user.id` is a stable integer field on the PR
object itself (returned by GitHub's API independent of anything the PR's file contents claim),
distinct from `user.login`, which is a mutable display string.

**Why the check must read this from the PR object's `user.id`, never from anything inside the
git commits the PR carries.** A git commit's author name and email are arbitrary, unauthenticated
text the committer sets locally — they carry no relationship to any forge account and are not
verified by the forge at all. Demonstrated in this environment, on this worktree, with a
throwaway commit created and immediately discarded:
```
$ git log -1 --format='%an <%ae>'
womcraft <womcraft@snabbpost.com>
$ git commit --allow-empty --author="Totally Fake Name <fake@example.com>" -m "throwaway test commit, will be reset"
$ git log -1 --format='%an <%ae>'
Totally Fake Name <fake@example.com>
$ git reset --hard HEAD~1
$ git log -1 --format='%an <%ae> (restored)'
womcraft <womcraft@snabbpost.com> (restored)
```
(The committer address shown is whatever this worktree's local `git config user.email` holds at
the moment the demonstration is run — it has genuinely changed since this document was first
written, which is expected environment drift, not a defect; re-run to see the current value. The
substantive claim — a commit's author/committer identity is arbitrary, unauthenticated text — does
not depend on which placeholder address happens to be configured.)
Anyone can set a commit's author to any string with no verification whatsoever. The only identity
in a PR that the forge itself vouches for is the account that opened the PR through its own
authenticated API/UI session — GitHub's `pulls.user` field. **The ownership gate must read
identity from `pulls.user.id`, never from `git log`'s author/committer fields, a `Co-Authored-By`
trailer, or any other text inside the diff.**

**`GITHUB_ACTOR` and `GITHUB_ACTOR_ID`, the environment variables GitHub Actions exposes to a
running job, are equally forbidden as an identity source — for a different, more subtle reason
than the git-commit case above.** Unlike commit metadata, `GITHUB_ACTOR_ID` genuinely is a numeric,
forge-verified id, free in the CI environment, and is exactly what an implementer told to "compare
the numeric account id" is likely to reach for. But it identifies whoever's workflow run is
currently executing, which equals the PR author only for a plain `pull_request` event — it is a
**different** account (frequently a maintainer re-running a failed job, or a service account) for a
workflow re-run or a `workflow_dispatch` trigger. The only field this document ever authorises is
`pulls.user.id`, read from the PR object itself via the API, never from the environment of the job
evaluating it, `GITHUB_ACTOR`/`GITHUB_ACTOR_ID` included.

## Provider is part of the comparison, not just id

`owner` is `{ provider, id, name_at_registration }` (ADR-0058 §2, `contracts/entry.schema.json`).
**The comparison is on the `(provider, id)` pair, never on `id` alone.** The registry format is
provider-agnostic (ADR-0058 §4) precisely so a future non-GitHub source can publish, and two
different providers can — with nothing preventing it — assign the identical small integer to two
completely unrelated accounts. Phase 1 only ever sees `provider = "github"` in practice, but a
checker hard-coded to assume that (comparing bare integers with no provider check) would already
be wrong the day a second provider is accepted, and "already wrong the day X happens" is exactly
the failure shape `contracts/artifact-naming.md`'s `:`-in-a-git-ref attack describes for a
different document. Stated once, here, so task 007 never has to rediscover it.

## Against what: `owner.id` for every namespace the PR touches

The check runs **once per distinct namespace the PR touches, independently** — never only against
the first `entry.json` in the diff, and never only against whichever file changed the most lines.
A registry PR is a single diff that may touch any number of `mods/<namespace>.<name>/entry.json`
**and/or `mods/<namespace>.<name>/page.json`** paths — **the enumeration is not confined to
`entry.json`: ADR-0059 §3 requires a PR touching only `page.json` to pass "the same ownership
check (numeric id)"** as a PR touching `entry.json`, so a `page.json`-only PR is not a hole this
check skips (see "`page.json` PRs" below for what this does, and does not, additionally require).
The check enumerates every such path that appears in the diff, extracts its namespace (from the
path, identically for either file), and
evaluates that namespace's rule (this document's ordinary rule, or the reserved-namespace rule
below, whichever applies) independently for each.

**The two-namespace case, stated explicitly:** a single PR touching `alice:toolkit` and
`bob:widget` in the same diff must pass **both** namespaces' checks before either is accepted —
`alice`'s numeric id must equal `alice:toolkit`'s `old.owner.id`, **and separately**, `bob`'s
namespace requires the PR author's id to equal `bob:widget`'s `old.owner.id`. Since a PR has
exactly one author (`pulls.user`, a single account), this means a PR can only ever legitimately
touch multiple *existing* namespaces if the same single account owns every one of them; a PR
touching two namespaces owned by two different people must be rejected outright, in full, not
merged with only the touches to the author's own namespace applied. There is no partial-merge
path in this model — `contracts/append-only.rules.md`'s own gate operates on the PR as a whole,
and this check is a further whole-PR precondition, not a per-file filter.

## What a first publish binds

ADR-0058 §3, quoted verbatim, is the confirmation the CLI shows and the site documents before a
first publish proceeds:

> "This creates the namespace `X:` permanently bound to your GitHub account (id N). Namespaces
> are never reassigned."

**At the moment a namespace is created** (no `old` entry exists for it yet — this is the first
publish PR for that namespace, ADR-0058 §1), the fields that become authoritative, forever, are:

- **`id`** (the `namespace:name` string) — frozen from this PR onward
  (`contracts/append-only.rules.md`).
- **`owner.provider`** and **`owner.id`** — must equal the PR author's real `(provider, id)` pair
  as read from the PR object (`pulls.user.id`, GitHub in phase 1), **never a value taken from the
  PR's own proposed `entry.json` content without independently cross-checking it against the
  live PR object.** A checker that trusts the JSON's self-declared `owner.id` at first publish
  would let a PR create an entry claiming any numeric id at all — including someone else's —
  with nothing to stop it, since there is no `old` value yet to compare against. The check at
  first publish is therefore not "does `new.owner.id` equal `old.owner.id`" (there is no `old`)
  but "does `new.owner.id` equal the real, forge-verified id of whoever is submitting this PR
  right now."
  **Exception for a namespace on the reserved list (ADR-0119 §2) — stated here, at the point this
  rule is made, so the two rules never need to be reconciled by a reader:** the paragraph above is
  the **ordinary** case only, and it can never be satisfied for a reserved namespace — no
  individual account's numeric id can ever equal the organisation's ("The reserved-namespace case"
  below proves this from this project's own data). If the namespace being created is on the
  reserved list, `owner.provider`/`owner.id` MUST instead equal the value `reserved-namespaces.json`
  records for it (in phase 1, `provider: "github"`, `id: 324218296`, the `worldofmodcraft`
  organisation), never the PR author's own id — and authorisation for the PR is, from this first
  publish onward, **organisation membership**, not id-equality, exactly as "The reserved-namespace
  case" below states for every later version. There is no separate first-publish rule for `mc` or
  `test`: that section is the *entire* rule for a reserved namespace, first publish included, and
  the ordinary first-publish rule in this paragraph never applies to them at all.
- **`owner.name_at_registration`** — the account's username *at the moment of this publish*,
  recorded once, for humans reading history (ADR-0058 §3's confirmation text names the account by
  it). It is informational only and is never itself compared for authorisation, at first publish
  or ever after — only `owner.id` is (see "What identity is compared" above).
- **The namespace string itself** (the part of `id` before `:`) is derived from the account's
  username at that moment (ADR-0039), except for the reserved set (next section).

**What may never change afterwards:** `id` and every field of `owner`, per
`contracts/append-only.rules.md`'s existing frozen-field rule — this document does not repeat
that rule's mechanics, only relies on it. Consistent with "namespaces are never reassigned,"
nothing in this document, or in `append-only.rules.md`, admits any path by which `owner` changes
after the namespace's first publish, short of a future ADR that amends both documents together
(`append-only.rules.md` already states this precondition explicitly).

## The namespace string itself: MUST equal the author's username at first publish (ADR-0039)

**At first publish only, the namespace string (the part of `id` before `:`) MUST equal the PR
author's current GitHub username (`pulls.user.login`), compared case-insensitively.** Without this
check, nothing in this document's id-based rule stops a fresh account from first-publishing into a
namespace named after someone else's existing username entirely: the id-equality rule only ever
asks whether the PR author's id equals `new.owner.id`, and at first publish the PR itself supplies
`new.owner.id` — nothing yet requires that value, or the namespace string next to it, to bear any
relationship to any *other* person's account at all. Concretely: an account whose real id is `999`
and whose username is `mallory` opens a first-publish PR creating `mods/alice.cooltool/entry.json`
with `owner: {provider: "github", id: 999, name_at_registration: "mallory"}`. The first-publish
id-equality rule alone asks only "does `999` (the submitter's real id) equal `999` (`new.owner.id`,
which the same PR supplies)?" — trivially yes, and `alice` is not reserved, so a checker built from
the id rule alone accepts it. That is namespace capture, unrelated-account first publish into a
namespace named after someone else's identity — the exact attack ADR-0058 §2 exists to close, and
the reason edge E16 (this document) was added to the graph at all. **The namespace-string check
above is what closes it**: `mallory`'s username, `mallory`, does not equal `alice`, the namespace
this PR proposes, so the PR is rejected regardless of what the PR's own proposed `owner` says.

**Case-folding: compare after folding both sides to lowercase.** `contracts/entry.schema.json`'s
`id` pattern (`^[a-z0-9][a-z0-9_-]*:[a-z0-9][a-z0-9_-]*$`) is lowercase-only, while GitHub
usernames may contain uppercase letters; a literal, case-sensitive comparison would reject every
first publish from a user whose username contains a capital letter, which is not this rule's
purpose. *Booked to Ludwig as an FYI, not a blocking question: this normalisation rule follows
mechanically from ADR-0039's naming rule plus `entry.schema.json`'s existing lowercase-only
pattern, but no ADR states the case-folding step in these words — see this document's own
`## Questions`.*

**Scope: first publish only, and never re-checked after.** There is no `old` value for a
namespace-derivation rule to compare against on a later PR to an existing namespace — a PR adding
a version never re-derives the namespace string, and `id` is frozen forever once created
(`append-only.rules.md`, and "What may never change afterwards" above). A later account rename
does not retroactively invalidate an existing binding: `owner.id` is what is bound, and
`name_at_registration` is explicitly informational, exactly as stated above for the ordinary
ownership check.

**Reserved namespaces are exempt from this check.** `mc` and `test` do not derive their namespace
string from any account's username at all (ADR-0119 §1–2); "The reserved-namespace case" below is
the entire rule for those namespaces' first publish, replacing both this section and the ordinary
`owner.id`-equality rule above.

This adds a **third** failure mode to "Where the check runs and what it does on failure" below,
distinct from id-mismatch and non-membership: a first-publish PR whose namespace string does not
equal (case-insensitively) the PR author's username, and whose namespace is not on the reserved
list, is rejected on that basis alone — independently of whether `new.owner.id` happens to equal
the PR author's own real id, which it trivially always can at a first publish since there is no
`old` value to contradict it.

## The reserved-namespace case (ADR-0119): a reservation, not an ownership exemption

`mc` and `test` are reserved (`reserved-namespaces.json`), bound to the `worldofmodcraft`
organisation's numeric account id rather than an individual's:

```
$ gh api orgs/worldofmodcraft --jq '{login,id,type}'
{"id":324218296,"login":"worldofmodcraft","type":"Organization"}
```
This matches `reserved-namespaces.json`'s own recorded `owner.id` (`324218296`) for both `mc` and
`test`, confirmed live against the real account rather than assumed from the file's own content.

**This section governs a reserved namespace's first publish exactly as it governs every later
version — it is not confined to `present -> present`.** "What a first publish binds" above states
this section's rule replaces the ordinary first-publish rule for `mc` and `test`, in full, not
only after the namespace already exists; there is no separate reserved-first-publish rule anywhere
else in this document.

**The binding mechanism is identical to every other namespace** (ADR-0119 §2): `owner` for a
reserved namespace is the same three-field shape, and `contracts/entry.schema.json`'s own
description states this explicitly — "this schema does not distinguish the two cases, by design."
Nothing about *what is stored* differs.

**What differs is *how a PR is authorised*, and it must differ, structurally — this is not a
design choice with an alternative, it is a consequence of what the numbers are.** No individual
GitHub account's numeric id can ever equal the organisation's own numeric id — they are different
accounts, verified distinct in this project's own data:
```
$ gh api repos/worldofmodcraft/registry --jq '{full_name,owner:{login:.owner.login,id:.owner.id,type:.owner.type}}'
{"full_name":"worldofmodcraft/registry","owner":{"id":324218296,"login":"worldofmodcraft","type":"Organization"}}
```
(Re-run in this fix round: the nested `owner` object's key order in real output is `id, login,
type` — alphabetical — not the `login, id, type` order the filter literally names. `gh api --jq`
uses `gojq`, which sorts constructed-object keys alphabetically regardless of the order they are
written in the filter; an earlier revision of this document pasted the filter's literal order
instead of the real output. The values themselves were always correct; only the key order was
wrong. Content, not just presence, now matches a fresh run.)
(`324218296`, the org, against `324089373`, the individual account `womcraft` used to submit real
PRs in this repository's own history — shown above under "What identity is compared.") **The
ordinary rule ("PR author's id equals `owner.id`") can therefore never pass for a reserved
namespace by construction, no matter who submits the PR** — this is exactly why ADR-0119 §3
defines a *separate* authorisation path rather than special-casing the equality check: the two
are different questions. Ordinary case: "is this PR author's id equal to `owner.id`?" Reserved
case: "is this PR author currently a member of the organisation that owns this namespace?"

**The membership check itself: the answer depends on who is calling, not only on who is being
asked about — this is documented GitHub behaviour, not just an observation from one token.**
GitHub's own REST reference for `GET /orgs/{org}/members/{username}` states three outcomes:
`204` if "requester is an organization member and user is a member"; `404` if "requester is an
organization member and user is not a member"; **`302`** if "requester is not an organization
member" — regardless of whether the named user is one. (<https://docs.github.com/en/rest/orgs/members>,
fetched live during this round.) **The calling identity's own membership gates which of these
three branches is even reachable.**

Verified live, in this environment, both branches:

- **Member-caller branch** (the `womcraft` token, itself an org member, asking about `womcraft`):
  ```
  $ gh api orgs/worldofmodcraft/members/womcraft -i
  HTTP/2.0 204 No Content
  ```
  Direct `204`/`404` answers, no redirect, exactly as documented for a member requester.
- **Non-member-caller branch** (an unauthenticated request — GitHub treats "no credential" the
  same as "requester is not an organization member" for this endpoint, since there is no
  authenticated identity to be a member):
  ```
  $ curl -s -o /dev/null -w 'status=%{http_code} redirect=%{redirect_url}\n' \
      https://api.github.com/orgs/worldofmodcraft/members/womcraft
  status=302 redirect=https://api.github.com/organizations/324218296/public_members/womcraft
  $ curl -s -L -o /dev/null -w 'final_status=%{http_code}\n' \
      https://api.github.com/orgs/worldofmodcraft/members/womcraft
  final_status=404
  ```
  `womcraft` genuinely **is** a member (`204` above, from the member-caller branch) but is not a
  **public** member, so a non-member caller is redirected to `GET
  /orgs/{org}/public_members/{username}` — a different, public-only endpoint — and following that
  redirect lands on `404` regardless of the target's real (private) membership.

**The redirect-following hazard, stated as a rule a checker must follow, not left for the reader
to infer:** a checker MUST NOT follow the `302` and treat the followed request's final status as
the answer. `curl -L`, Python's `requests`, `gh api`, and `octokit.js` all follow redirects by
default, so this is the behaviour an implementer gets unless they deliberately turn it off. Two
correct designs, either is acceptable:
1. Run the check as a caller that is itself confirmed to be an organisation member, so the `204`/
   `404` branch answers directly and `302` is never reached; **or**
2. Detect a `302` response explicitly (do not follow it) and treat it as "the calling identity
   cannot see this membership," failing the check closed with an actionable error — never
   silently reinterpreting a followed redirect's `404` as "not a member."
Under the flat, caller-unqualified rule this document stated before this round, a checker built
faithfully from that text follows the redirect (every default HTTP client does) and rejects every
genuine private-member PR — including the first publish of `test:hello-world`, mission acceptance
criterion 2.

**What this means for the actual CI caller — established here, not assumed.** Which branch CI
hits depends entirely on whether the identity registry CI authenticates as is itself an
organisation member. **This could not be established in this environment: this machine has no
GitHub Actions runner, and settling it by reading a stored credential is forbidden (CLAUDE.md
rule 11, MANAGER.md guardrail 10).** GitHub Actions' default `GITHUB_TOKEN` is a per-run,
repository-scoped installation token, not any individual account's token, and whether it (or an
org-scoped credential stored as a secret) satisfies "requester is an organization member" for this
endpoint is an **unverified claim, marked here at the point this document would otherwise assert
it** (guardrail 6b): task 007's implementer must confirm which identity the ownership-check job
authenticates as before relying on the member-caller branch above, and if it is not itself an org
member, the check must not silently run through the non-member branch and reject every reserved-
namespace PR.

**A second candidate, with its own caller requirement — not adopted, only established:**
`GET /orgs/{org}/memberships/{username}` has no `302` branch, but GitHub's own documentation
states it requires the same precondition: *"In order to get a user's membership with an
organization, the authenticated user must be an organization member."* Verified live in this
environment: unauthenticated, it refuses outright rather than degrading to a public view —
```
$ curl -s -o /dev/null -w 'status=%{http_code}\n' \
    https://api.github.com/orgs/worldofmodcraft/memberships/womcraft
status=401
```
— and as a member-caller (the `womcraft` token) it answers directly, no redirect:
```
$ gh api orgs/worldofmodcraft/memberships/womcraft --jq '{state,role}'
{"state":"active","role":"admin"}
```
`state == "active"` is the success condition when this endpoint answers at all. **This endpoint is
a candidate, not an answer**, exactly as the round-1 fix brief named it: it removes the `302`/
redirect ambiguity, but it does not remove the "is CI's own identity an org member" question above
— GitHub's documented `403` for an authenticated-but-non-member caller was not independently
reproduced here, since doing so would require a second identity, which this round does not use.

**Which revision of `reserved-namespaces.json` the check reads: `old`, never `new` — the same
discipline "The comparison model" above applies to `owner`, applied here to list membership.** The
check evaluates a PR against the reserved list as it stood at the PR's merge-base with the target
branch, never the version the PR itself proposes. A PR that, in the same diff, removes `mc` from
`reserved-namespaces.json` **and** first-publishes `mc:core` must still be evaluated as if `mc`
were reserved — reading `new` here would let a single PR strip a namespace's reserved status and
capture it in the same breath, the identical attack shape Attempt 1 below closes for `owner`
itself, applied to list membership instead of the ownership field.

**This is a reservation, not an ownership exemption:** a PR touching `mc:` or `test:` is
authorised **only** when the PR author is currently a member of `worldofmodcraft`; every other
account is rejected, exactly as an ordinary namespace rejects a non-owner, citing ADR-0119 by
name in the rejection message (ADR-0119 §3: "rejects it otherwise with a message naming this
ADR").

## Where the check runs and what it does on failure

The check runs in registry CI (**N3**, `docs/architecture/depgraph.md`), on every PR against
`worldofmodcraft/registry`, before the append-only diff check and schema validation are treated as
sufficient to merge — `append-only.rules.md` explicitly assumes this check exists elsewhere and
does not perform it. On failure, the PR is rejected with a message that states, per namespace that
failed: which namespace, the PR author's real numeric id (and provider) as read from the PR
object, and one of **three** failure modes:
1. the existing `owner.id` it did not match (ordinary, existing-namespace case);
2. the fact that the author is not a current member of `worldofmodcraft` (reserved-namespace
   case, naming ADR-0119, first publish or later, per "The reserved-namespace case" above); or
3. at first publish for a non-reserved namespace, the namespace string not equalling
   (case-insensitively) the PR author's username ("The namespace string itself" above).

This is the same actionable-rejection standard `append-only.rules.md` and the asset scanner already meet — no
generic "ownership check failed," always the specific mismatch a reader can act on.

## `page.json` PRs: same ownership check, narrower scope (ADR-0059 §3)

A PR touching only `page.json` (no `entry.json` change in the diff at all) is checked under
"Against what" above exactly as an `entry.json` PR is: the namespace of every touched `page.json`
path is extracted and evaluated against `old.owner.id` (ordinary case) or the reserved-namespace
membership rule, identically. **This is the entirety of what this document requires for
`page.json`.**

**What this document does not additionally require for `page.json` — a declared boundary, not a
silent one.** ADR-0059 §3 also requires an "asset scan on new screenshots" for a page-content PR.
That is a separate gate, owned by the asset scanner (`contracts/validation-report.schema.json`),
not this document — and it is **deferred to task 040**, because no archived source exists to scan
new screenshots against until task 008 (the build pipeline) has run at least once; task 040 depends
on that archive existing. A `page.json` PR that changes screenshots must therefore pass **two**
independent gates before it is accepted: this document's ownership check, and task 040's asset
scan — this document only ever speaks to the first, and passing this check alone is not sufficient
to accept such a PR.

## The required regression case for task 007 (acceptance criterion 3)

**A PR whose author id differs from `owner.id` while the username matches must be rejected.**
Written here as a required fixture so task 007 inherits it rather than inventing its own version
of the same test.

**Fabricated example — no real account is involved, every id below is placeholder data clearly
marked as such:**

- On the target branch, `mods/alice.cooltool/entry.json` already exists, with
  `owner = { provider: "github", id: 100200300, name_at_registration: "alice" }`.
- The GitHub account whose *current* username is `alice` opens a PR adding a new version to this
  entry. Its real numeric id, as GitHub's API reports on the PR object
  (`pulls.user.id`), is `900800700` — a different number entirely. (Consistent with real,
  verified GitHub behaviour: "Your username will be available for anyone to use after 90 days"
  — GitHub's own documentation, quoted verbatim under "Attack attempts against this contract"
  below — so a second, unrelated account legitimately holding the username `alice` today is a
  real reachable state, not a contrived one.)
- **A checker comparing usernames** (`pulls.user.login == owner.name_at_registration`, both
  literally the string `"alice"`) **accepts this PR.** This is the wrong check and must never be
  what task 007 implements.
- **A checker comparing `pulls.user.id` against `owner.id`** (`900800700` vs `100200300`)
  **rejects this PR**, correctly, because the two numbers differ. This is the check this document
  requires.

Task 007 must include this exact fixture shape — matching username, differing numeric id — as a
regression test before its ownership gate ships, and the test must fail (i.e. correctly reject)
against it.

## Attack attempts against this contract, recorded per acceptance criterion 4

**Attempt 1 — rewrite `owner.id` to the submitter's own id, inside the same PR that adds a
version ("namespace transfer between accounts").** A publisher wants to move
`alice:cooltool` to a new account they control (a personal reorganisation, or moving a solo
project under a fresh organisation) and opens a single PR that both adds a new version **and**
changes `owner` to the new account, submitted *from* that new account. **Under a checker that
compares the PR author's real id against `new.owner.id`** (the version of `owner` the PR itself
proposes, rather than `old.owner.id`, the version already on the target branch) **this passes
completely** — the new account's real id, freshly written into `new.owner.id` by the same PR,
trivially equals itself. Every input looks legitimate: the version content is real and wanted,
and "the PR author's id matches owner.id" is technically true of the PR's own proposed content.
**What the contract does about it:** "The comparison model" above fixes this before it can be
implemented wrong — the comparison is always against `old.owner`, which still names the
*original* account, so the mismatch (original id vs new submitter's id) is caught regardless of
what the PR proposes to change `owner` to. This is also exactly why
`contracts/append-only.rules.md`'s frozen-`owner` rule exists as a second, independent barrier: even
setting the identity question aside, no PR may ever change `owner` at all, so this specific attempt
is rejected twice over, by two different documents, for two different reasons — this document
because the *submitter* was never authorised in the first place, `append-only.rules.md` because
`owner` itself may not move even for someone who is.

**Attempt 2 — treat "reserved" as "unchecked," from outside the organisation.** A contributor who
is not a member of `worldofmodcraft` opens a PR adding a version to `test:hello-world`, an
existing reserved-namespace entry, changing nothing about `owner` at all (so
`append-only.rules.md`'s freeze never even triggers — `owner` is genuinely, byte-for-byte,
unchanged). The bet: since `test:` is "the platform's own namespace, not any individual's," maybe
nothing actually re-checks who is submitting once a PR merely adds a version rather than
touching `owner`. **What the contract does about it:** the reserved-namespace path above is an
*active* authorisation check — org membership, re-verified live — not an early-exit that skips
authorisation because the namespace is special. The contributor's account is not a member of
`worldofmodcraft`, the membership check returns `404`, and the PR is rejected citing ADR-0119, the
same as any other unauthorised PR. ADR-0119 §4's own words apply directly here: this reservation
"is an exception surface," and an exception surface that turns into "nobody checks" the moment a
PR avoids touching `owner` would be exactly the undocumented leniency ADR-0119's context section
exists to prevent.

**Attempt 3 — collide numeric ids across providers.** ADR-0058 §4 requires the registry format to
stay provider-agnostic; suppose a second provider is eventually accepted (phase 3) and, by sheer
coincidence, assigns the same small integer as some existing GitHub account's id to an entirely
different person on the new provider. A PR from that second-provider account, touching a
namespace whose `owner.id` happens to equal that same integer under `provider: "github"`, is
submitted. **Under a checker comparing `id` alone**, ignoring `provider`, **this passes** — the
integers match, even though the two accounts have nothing to do with each other and live on
different forges entirely. **What the contract does about it:** "Provider is part of the
comparison, not just id" above requires the `(provider, id)` pair to match as a whole; a PR from
`provider: "some-new-forge", id: 100200300` never matches `owner = { provider: "github", id:
100200300, ... }`, regardless of the numeric coincidence, because the providers differ.

**Attempt 4 — a deleted-then-recreated account, same human, same username, new id.** The original
owner of `alice:cooltool` deletes their GitHub account (any reason — a fresh start, a security
incident, a policy action) and, more than 90 days later, registers a **new** GitHub account under
the identical username `alice` (GitHub's own documentation, quoted below, confirms the old
username becomes available to be claimed again after that window — by anyone, including
originally the very same person). They now hold a **different** numeric account id than before —
GitHub assigns a new id to every new account — and attempt to publish a new version to their own,
original `alice:cooltool` namespace from this new account. **Under this document's rule, this PR
is rejected**, indistinguishably from an attacker who is not the original person at all: the new
account's real id does not equal `old.owner.id`, full stop, and this document's own id-based
check has no way — and is not designed to have a way — to tell "the original person, now on a
new account" apart from "someone else entirely who happens to hold the same username today." This
is not a gap to close; it is the direct, permanent, intended consequence of "namespaces are never
reassigned" (ADR-0058 §3) plus ADR-0041's "the platform never reassigns a namespace" for
abandoned mods — the only paths back are forking to a new namespace (ADR-0041) or a future ADR
that defines an explicit account-migration recovery process and amends both this document and
`append-only.rules.md`'s frozen-`owner` rule together (that document's own text already names
this exact hook: "account migration, namespace transfer under new governance"). **Recording this
here, rather than treating it as self-evidently fine, is the point of this attack attempt**: a
reader who has not thought it through might expect the "legitimate original owner" case to be
special-cased somehow; it is not, and cannot be, from GitHub identity data alone.

**Attempt 5 — first-publish into a namespace named after someone else, relying on the id rule
alone.** An account whose real numeric id is `999` and whose current username is `mallory` opens a
first-publish PR creating `mods/alice.cooltool/entry.json` with `owner: {provider: "github", id:
999, name_at_registration: "mallory"}` — a namespace named after a different person's identity
entirely, one `mallory` does not hold. **Under a checker built only from the id-equality rule in
"What a first publish binds,"** without "The namespace string itself" section, **this passes**:
the submitter's real id (`999`) trivially equals `new.owner.id` (`999`), which the same PR
supplies, and there is no `old` value yet to contradict it. By this document's own "namespaces are
never reassigned," there is then no recovery path — the real `alice`, whoever she is, can never
register the namespace her own username would otherwise have bound her to. **What the contract
does about it:** "The namespace string itself" above requires the namespace string to equal
(case-insensitively) the PR author's own username at first publish; `mallory` does not equal
`alice`, so this PR is rejected regardless of what `owner` it proposes for itself. This is
namespace capture through the front door of the id-equality rule alone — exactly the attack
ADR-0058 §2, and edge E16 itself, exist to prevent — closed by a check this document did not
originally state explicitly, found in review round 1 (finding B3).

**Attempt 6 — a `page.json`-only PR, hoping the enumeration only ever looks at `entry.json`.** ADR-
0059 §3 requires "the same ownership check (numeric id)" for a PR that touches only
`mods/<ns>.<name>/page.json` — no `entry.json` change at all. An account not authorised for a
namespace opens a PR editing only that namespace's `page.json` (rewriting its description, links,
or screenshots), betting that an enumeration written narrowly against `entry.json` paths finds
nothing to check in this diff and lets it through vacuously. **What the contract does about it:**
"Against what" above enumerates every `mods/<ns>.<name>/entry.json` **and**
`mods/<ns>.<name>/page.json` path in the diff, on identical per-namespace, no-partial-merge terms;
a `page.json`-only PR is not exempt, and is rejected by the same `old.owner.id`/reserved-membership
rule as any other PR touching that namespace. Found in review round 1 (finding B4); before the fix,
this document's enumeration named only `entry.json`, and `grep -c "page.json"
contracts/ownership.md` returned `0`.

**On GitHub's documented username-recycling behaviour, quoted verbatim, underpinning attempts 1
and 4 above:**
> "After changing your username, your old username becomes available for anyone else to claim."
> — <https://docs.github.com/en/account-and-profile/concepts/username-changes>, fetched live
> during this task.

> "Your username will be available for anyone to use after 90 days." — the same account's
> username, after **deletion** rather than a voluntary rename —
> <https://docs.github.com/en/account-and-profile/reference/personal-account-reference>, fetched
> live during this task.

**What could not be verified, and is carried as an inline caveat rather than asserted: whether a
numeric account id is ever reused for a different account, including after the original account
is deleted.** ADR-0058 §2's entire defence rests on this never happening ("the numeric GitHub
account id (never reused)"). Neither GitHub docs page fetched above states this explicitly for
numeric ids (only for usernames, which they explicitly say *are* recycled); a general web search
for GitHub's own numeric-id-reuse policy for deleted accounts returned no authoritative GitHub
statement either — only third-party summaries with no cited source. Indirect, and only indirect,
supporting evidence was found and is real: GitHub attributes content from **deleted** accounts to
a fixed placeholder account, `ghost` (numeric id `10137`), rather than leaving the original id
free for reassignment:
```
$ gh api users/ghost --jq '{login,id,type}'
{"id":10137,"login":"ghost","type":"User"}
```
This is consistent with ids not being recycled — a recycling scheme would have no particular need
for a placeholder account — but it is not a documented guarantee, and this document does not
claim it is one. **If GitHub's numeric-id-reuse behaviour is ever found to differ from "never
reused," ADR-0058 §2's own defence needs re-examination, not just this contract** — this is
flagged here because this is the first document written under MANAGER.md guardrail 6b, and the
claim is load-bearing for the entire ownership model, not a peripheral detail.

## What this document does not cover

- **Whether `owner` may ever change after first publish, or the mechanics of that freeze** —
  `contracts/append-only.rules.md` (E4), relied on throughout above, never restated here.
- **Which namespaces are on the reserved list, or why** — `reserved-namespaces.json` and ADR-0119
  itself; this document only states how the identity check behaves once a namespace is known to
  be reserved.
- **Schema shape validation or PR classification** — N3's other two jobs
  (`docs/architecture/depgraph.md`), owned by `contracts/entry.schema.json` and task 007's own
  classifier.
- **An account-migration or namespace-transfer recovery process.** None exists. Attempt 1 and
  Attempt 4 above both end at "rejected, permanently, absent a future ADR" — this document does
  not invent a recovery path that no ADR has decided.
- **Any provider other than GitHub in practice.** Phase 1 only ever sees `provider = "github"`;
  "Provider is part of the comparison" above states the rule in provider-neutral terms because
  ADR-0058 §4 requires the *format* to stay provider-agnostic, not because a second provider
  exists yet.
- **The asset scan on new screenshots in a `page.json` PR** (ADR-0059 §3) — a separate gate from
  this one, deferred to task 040 for the reasons "`page.json` PRs" above states (no archive to scan
  against before task 008 runs). This document's check and that scan are two independent gates a
  screenshot-changing `page.json` PR must both pass.
- **Who may open a PR performing a legally-mandated takedown against a namespace they do not
  own.** An explicit, unresolved gap — see "Takedown PRs" below, not silently assumed away here.

## Takedown PRs: an authority question this document does not resolve (explicit exclusion)

A legally-mandated takedown (ADR-0041) sets an existing version's `status` to `"removed"`.
`contracts/append-only.rules.md` defines the *shape* of that one permitted in-place mutation and
explicitly declines to say who may perform it: *"This document defines the shape of a legal
takedown, not who may perform one."* The ownership gate — this document — is the only other place
that identity question could land, since it is the document that decides who may touch a
namespace at all.

**This document does not resolve it either, and states that as a deliberate, named gap rather than
leaving it silent.** Who may open a PR performing a legally-mandated takedown against a namespace
they do not own is an **authority** question, not a mechanical one: ADR-0041 mandates that
takedowns happen, and `MANAGER.md` §7 already makes *merging* one Ludwig's own written decision,
account by account — but nobody has yet decided the *opening* side, and this document does not
invent an answer to a question that belongs to Ludwig.

**The consequence, today, stated plainly:** a takedown PR opened by any account other than the
namespace's own recorded `owner.id` (or, for a reserved namespace, a current member of
`worldofmodcraft`) is rejected by the **ordinary** rule in this document, exactly as any other
unauthorised PR would be — including one opened by the platform itself to remove a namespace
owner's own infringing entry, which is the entire premise ADR-0041's legal-grounds clause exists
for. There is no carve-out here for a "legally-privileged opener," because none has been decided.

**The two contracts the delegation falls between, named explicitly:** `append-only.rules.md`
defines the mutation's shape and declines the identity question; this document defines identity
for the ordinary and reserved-namespace cases and says nothing about a takedown opener. The
delegation `append-only.rules.md` makes lands nowhere until Ludwig rules on it — booked in this
document's own `## Questions` below, so an implementer reading only this file (not the task log)
still sees the gap.

## Questions

1. **Whether the reserved-namespace membership check (ADR-0119 §3) must be re-evaluated on every
   CI run for a given PR, or only once when the PR is first opened.** A PR can sit open for a long
   time, and organisation membership can change while it does (someone leaves `worldofmodcraft`
   after opening a PR against `test:`, for instance). No ADR read for this task settles whether
   the check is a point-in-time gate or a continuously-reasserted one. **Assumed meanwhile:** the
   check re-runs, and must pass, on every CI evaluation of the PR (e.g. every new commit push and
   every re-run), never cached from the PR's first evaluation — the boring, restartable choice
   (ADR-0103), and consistent with "membership is never frozen" as stated above. **What rests on
   this:** if a future decision instead treats membership as fixed at PR-open time, a person who
   leaves the organisation mid-review would need an explicit re-check step added back in.
2. **The account-migration recovery path Attempt 4 above ends without one.**
   `contracts/append-only.rules.md` already books this same hook ("If a future ADR introduces a
   legitimate way to change `owner` ... that ADR must amend this document"). Recorded here too,
   in matching wording, because this document's own attack attempts are what surfaces the human
   cost of there being no such path today, not merely append-only's field-freeze mechanics.
   **Assumed meanwhile:** no recovery path exists; a namespace whose owning account is
   inaccessible is permanently unpublishable-to, per ADR-0041's "abandoned mods" clause (fork to a
   new namespace). **What rests on this:** nothing yet — this is a known, accepted consequence of
   two already-accepted ADRs, not a defect in this document, and is booked only so it is visible
   next to the attack attempt that demonstrates it rather than left to be rediscovered.
3. **The case-folding rule in "The namespace string itself" above is not stated by any ADR read
   for this task, in these words.** It follows mechanically from ADR-0039 (namespace = username)
   plus `entry.schema.json`'s existing lowercase-only `id` pattern — a literal, case-sensitive
   comparison would reject every first publish from a username containing a capital letter, which
   nothing suggests is intended — but it is this document introducing the normalisation step, not
   an ADR. **Assumed meanwhile:** case-insensitive comparison, folding both sides to lowercase.
   **What rests on this:** task 007's checker, built from this rule as written; an FYI to Ludwig,
   not a blocking question, since no other reading of ADR-0039 plus the schema pattern was found.
4. **Who may open a PR performing a legally-mandated takedown against a namespace they do not
   own** (found in review round 1, finding B5). An authority question sitting with Ludwig, not
   settled by any ADR read for this task; see "Takedown PRs" above for the full statement of the
   gap and its consequence today. **Assumed meanwhile:** no such PR is authorised; the ordinary
   rule in this document rejects it, exactly as it rejects any other unauthorised PR. **What rests
   on this:** ADR-0041's legal-grounds takedown clause has no PR that can currently open it on a
   namespace's owner's behalf without their own cooperation — a real, currently-unclosed gap
   between what ADR-0041 mandates and what this registry's own ownership rule permits.
