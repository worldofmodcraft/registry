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

**Verified, live, against this project's own registry:**
```
$ gh api repos/worldofmodcraft/registry/pulls/3 --jq '{merged, user:{login:.user.login,id:.user.id}}'
{"merged":true,"number":3,"user":{"id":324089373,"login":"womcraft"}}
```
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
womcraft <worldofmodcraft_github@snabbpost.com>
$ git commit --allow-empty --author="Totally Fake Name <fake@example.com>" -m "throwaway test commit, will be reset"
$ git log -1 --format='%an <%ae>'
Totally Fake Name <fake@example.com>
$ git reset --hard HEAD~1
$ git log -1 --format='%an <%ae> (restored)'
womcraft <worldofmodcraft_github@snabbpost.com> (restored)
```
Anyone can set a commit's author to any string with no verification whatsoever. The only identity
in a PR that the forge itself vouches for is the account that opened the PR through its own
authenticated API/UI session — GitHub's `pulls.user` field. **The ownership gate must read
identity from `pulls.user.id`, never from `git log`'s author/committer fields, a `Co-Authored-By`
trailer, or any other text inside the diff.**

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
paths; the check enumerates every one that appears in the diff, extracts its namespace, and
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

## The reserved-namespace case (ADR-0119): a reservation, not an ownership exemption

`mc` and `test` are reserved (`reserved-namespaces.json`), bound to the `worldofmodcraft`
organisation's numeric account id rather than an individual's:

```
$ gh api orgs/worldofmodcraft --jq '{login,id,type}'
{"id":324218296,"login":"worldofmodcraft","type":"Organization"}
```
This matches `reserved-namespaces.json`'s own recorded `owner.id` (`324218296`) for both `mc` and
`test`, confirmed live against the real account rather than assumed from the file's own content.

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
{"full_name":"worldofmodcraft/registry","owner":{"login":"worldofmodcraft","id":324218296,"type":"Organization"}}
```
(`324218296`, the org, against `324089373`, the individual account `womcraft` used to submit real
PRs in this repository's own history — shown above under "What identity is compared.") **The
ordinary rule ("PR author's id equals `owner.id`") can therefore never pass for a reserved
namespace by construction, no matter who submits the PR** — this is exactly why ADR-0119 §3
defines a *separate* authorisation path rather than special-casing the equality check: the two
are different questions. Ordinary case: "is this PR author's id equal to `owner.id`?" Reserved
case: "is this PR author currently a member of the organisation that owns this namespace?"

**The membership check itself, verified against the real API this project uses:**
```
$ gh api orgs/worldofmodcraft/members/womcraft -i
HTTP/2.0 204 No Content
```
`GET /orgs/{org}/members/{username}` returns `204` if the named user is a member, `404`
otherwise. **This endpoint is keyed by username, not by numeric id** — unlike the ordinary
ownership comparison above, which is deliberately id-based. This is not a contradiction: GitHub's
own membership API gives no id-keyed equivalent, and unlike a namespace binding that must survive
username recycling for years, org membership is re-evaluated **live, at the moment the check
runs**, against whatever account currently holds that PR's `pulls.user.login` — there is no
stored, long-lived "membership at first publish" value to be spoofed by a later username change,
because membership is never frozen the way `owner` is. A person who leaves the organisation loses
authorisation the next time the check runs, with no `owner` field to update anywhere.

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
object, and either the existing `owner.id` it did not match (ordinary case) or the fact that the
author is not a current member of `worldofmodcraft` (reserved case, naming ADR-0119). This is the
same actionable-rejection standard `append-only.rules.md` and the asset scanner already meet — no
generic "ownership check failed," always the specific mismatch a reader can act on.

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
