# Publishing a mod to the registry

> **Status: under construction.** The checks described here are wired, but the publishing pipeline and the launcher are
> not live yet, so this repository is not accepting real submissions. This page documents the manual pull-request flow
> that will be the supported path (ADR-0058: manual PRs stay possible even when the `modcraft publish` command exists).

A mod is published by opening a pull request against `worldofmodcraft/registry`. Every pull request gets one automatic
check, named **`gate`**. A green `gate` means "the automatic checks pass". It never means "approved": a human merges.

## Your namespace is permanent

When your first version is published, the registry shows this notice and means it:

> This creates the namespace `X:` permanently bound to your GitHub account (id N). Namespaces are never reassigned.

`X` is your namespace (your GitHub username, lower case). `N` is your numeric GitHub account id. The namespace belongs to
the account **id**, not to the username string: renaming your GitHub account later does not move the namespace, and
nobody who later takes your old username gets it. Namespaces are never reassigned, to anyone, for any reason
(ADR-0058 section 3).

You can look up your id at `https://api.github.com/users/<your-username>` (the `id` field).

## The manual publish flow

1. **Fork** `worldofmodcraft/registry` and create a branch.
2. **Add `mods/<namespace>.<name>/entry.json`.** The directory name has exactly one dot. The namespace must be your
   GitHub username (lower case), and `<name>` your mod's name; both match `[a-z0-9][a-z0-9_-]*`. Namespaces `mc` and `test`
   are reserved for the organisation and only its members may publish into them (ADR-0119).
   A first version is born `pending` and carries exactly four keys:

   ```json
   {
     "id": "kelsi:housing",
     "owner": { "provider": "github", "id": 4831207, "name_at_registration": "kelsi" },
     "versions": [
       { "version": "1.0.0", "commit": "<40-hex commit of your mod repo>",
         "source_url": "https://github.com/kelsi/housing", "status": "pending" }
     ]
   }
   ```

   `owner.id` is your numeric account id (a number, not a string) and `name_at_registration` your username. They must
   match the account that opens the pull request; the check compares ids, never usernames.
3. **Optionally add `mods/<namespace>.<name>/page.json`** (description, tags, links, screenshots, `deprecated`) for the
   mod's page on the site (ADR-0059). Schemas and examples are in `contracts/`.
4. **Open the pull request against `main`.** Read the `gate` comment the bot posts: if a rule rejects the change it says
   which one and why. Fix it by pushing to the same branch; the comment updates.
5. **A maintainer merges.** After the merge the pipeline builds your commit, archives and signs it, and writes the
   result back to your entry in its own pull request (ADR-0121). You do not edit those fields yourself.

## Later changes

- **A new version:** append a new version object to your `entry.json` (new `version`, new `commit`, status `pending`).
- **Published versions are append-only (ADR-0041).** You cannot edit a published version's fields, reorder versions, or
  change `owner`. To fix a mistake, publish a new version.
- **Page edits:** a pull request that touches only `page.json` is allowed for the owner. No build runs for it.
  (A scan of page screenshots, ADR-0059 section 3, is planned and not running yet.)
- **Mixing:** keep a pull request to one purpose. Under `mods/` only the files `entry.json` and `page.json` inside a
  `<namespace>.<name>` directory are accepted, and a pull request that mixes `mods/` files with files elsewhere in the
  repository is rejected.

## Removal

**Owners cannot remove a published version** (ADR-0122, rule R11 of `contracts/ownership.md`). A published version stays
published, because other people's installs and signatures depend on it. If a version must come down (for example a legal
takedown), only the registry's takedown process can do it, with the organisation's written approval, and it is recorded
with a public reason. If you think your mod must be taken down, open an issue; do not open a pull request that sets a
version to `removed`: any pull request containing a removal is a takedown, and at present every takedown pull request is
rejected, whoever opens it, because the takedown identity is not configured yet.

## What the check does and does not do

It reads your pull request as data and never runs anything from it. It runs four checkers (what kind of change this is,
the entry schema, the append-only rules, the ownership rules) and reports all of them, so you see every problem at once.
"Could not decide" is shown as such and is not a rejection of you. Pull requests that change nothing under `mods/` (for
example this file) are not judged by the check and rely on human review.
