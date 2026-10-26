# Task 092: `artifact-naming.md` fixes the archived-source URL as `https://archive.worldofmodcraft.com/<tag>/<asset>` (decision C)

- **Mission:** SITE-V1, deliverable **D2** (umbrella `docs/tasks/008-build-pipeline.md`, Dependencies (c): "the `artifact-naming.md`
  amendment for the project-owned `source_archive` URL, after 058"). **Status:** spec-approved (manager, 2026-10-26, after spec review rounds 1-2; drafted by a Plan agent, 2026-10-26;
  Q1-Q8 decided by Ludwig "Stjärna på allt", Q9-Q10 "Kör A stjärna", 2026-10-26). Contract amendment; independent spec review done (round 1 FAIL folded in, round 2 PASS with four LOW fixes folded in).
- **Merge:** needs **Ludwig's written approval** (contract, ADR-0117; MANAGER.md §7). It fixes a value written once into an
  append-only record.
- **Repo:** registry (this file is copied to the registry branch's `docs/tasks/` as the log, as 057/082 did); platform: this file
  and the `depgraph.md` N6 row (Q6).
- **Agent / model:** split — doc-writer / sonnet for the contract prose, worked examples, README row and depgraph cell; then
  implementer / sonnet for `092-verify.sh` and the log (the verify script is code; precedent 082 for the prose).
  **Budget:** 3 agent-sessions (prose, examples + README + depgraph, verify script + log).
- **Branch / worktree:** `task/092-artifact-naming-archive-url` / `~/wt/registry-task-092`, cut from registry `origin/main`
  (actual cut SHA = `BASE` in the log and `092-verify.sh`).
- **Graph:** edge **E7** (`N5 → N6`) amended; its reading side (N6 read by N7 and installers, E11's input) described, not
  changed. No new edge.

## Source
- **Ludwig, 2026-10-26:** "C star, repo deleted" (mission log `8a4f2ac`) — option C: a project-owned hostname with a real HTTP
  redirect at Cloudflare. "Stjärna på allt" — Q1-Q8 below decided as ★.
- **Task 058 report** (platform `docs/research/archive-url-probe.md`, merged `313e804`): Pages emits no 3xx to a chosen target;
  meta-refresh/JS are followed by no HTTP client tested (only a browser follows a meta-refresh); a local 301/302 is followed by
  every client; C "not eliminated, not tested".
- **Task 091** (platform PR #82, runbook **M12**): Cloudflare Redirect Rule, custom filter `http.host eq
  "archive.worldofmodcraft.com"`, dynamic target `wildcard_replace(http.request.uri.path, "/*",
  "https://github.com/worldofmodcraft/archive/releases/download/${1}")`, status **302**, Preserve query string off; proxied AAAA
  `archive` → `100::`. [unverified] there: case preservation of `${1}`, certificate issuance time, exact field labels.
- Decisions **Q-E** (Releases live in `worldofmodcraft/archive`) and **Q-G** (a project-owned URL fronts `source_archive` before
  the first publish), 008 umbrella. **ADR-0041**: "the registry points at our copy"; "verify hash → verify signature … no trust in
  hosting behaviour".

## Decisions (Ludwig, 2026-10-26, all ★)
- **Q1 = B:** no byte change to `entry.schema.json`; exact equality to the derived URL is enforced by producer and consumers (a
  pattern cannot tie the tag to `id`/`version`). No site schema re-sync.
- **Q2 = B:** "`source_archive` equals the derived URL" in T1 and the append-only checker is a **booked follow-up** (needs a 057
  pin refresh and checker code; T1 is "shape only" by design).
- **Q3 = A:** `contracts/examples/entry/**` `source_archive` values updated to the new shape, values only.
- **Q4 = A:** no fallback — if the front fails, consumers fail closed; never a self-built `github.com` URL.
- **Q5 = A:** before opening T1 the pipeline fetches `source_archive` through the front and requires its SHA-256 to equal
  `source_sha256`; mismatch = pipeline fault (082 PT10 exit 2: no T3, stays `pending`). Stated here; implemented in 008b.
- **Q6 = A:** `docs/architecture/depgraph.md` N6 "Lives in" cell gains "addressed via `archive.worldofmodcraft.com` (Cloudflare
  redirect, M12)"; no new node or edge; `depgraph.json` untouched.
- **Q7 = A:** AC11's live capture (after Ludwig completes M12) **gates the merge**.
- **Q8 = A:** `system-overview.md`'s "not chosen" rows are updated by the booked 056 second pass, not here.
- **Q9 = A:** **hop 1 is checked exactly by the pipeline (pre-T1 check) and the manager (live checks), not by consumers.** The
  response from `archive.worldofmodcraft.com` must be 301/302/307/308 with `Location` byte-equal to the derived target.
  Consumers (site, launcher, installers, task 010's check) do **not** enforce hop 1's target: they require https on every hop,
  the hop bound (5), the size cap, and hash + signature (rules 1-11) before any use. So the front can be repointed (decision
  C's purpose) without a consumer release; a repoint changes M12 and this contract's redirect-target sentence (a contract
  amendment), not consumers. Reason: an auto-following client (`curl -L`, a browser fetch) cannot see hop 1.
- **Q10 = A:** 008b does **not** publish versions with build metadata (`+`) until a live Release proves GitHub resolves `+` in
  `releases/download` (task 010). Stated in the producer obligations; the derivation still defines their URL.
  **Outcome (manager decision, round 2):** such a version gets a T3 `rejected` with reason "versions with build metadata (+) are
  not yet published — pending proof that GitHub resolves them (task 010)" — not left `pending`.
- **Size cap (manager decision, round 2):** 52,428,800 bytes (50 MiB) = `tools/pipeline/archive.py:28` `MAX_COMPRESSED_BYTES` and
  the site downloader ceiling (`docs/pipeline/build-pipeline.md` ~100). Consumers abort the download at the cap. Raising 008a's
  compressed-size limit above this requires amending this contract.

## Objective
`contracts/artifact-naming.md` gains one deterministic function `(namespace, name, version) → archived-source URL` and the
obligations of every producer and consumer of it:
1. **URL:** `source_archive = "https://archive.worldofmodcraft.com/" + tag + "/" + tag + ".tar.gz"`, `tag` = `ns.nm-v` as the
   contract already defines; the signature asset `…/<tag>/<tag>.tar.gz.minisig` is derived, not stored (entry.json carries the
   signature inline).
2. **Redirect target:** `https://github.com/worldofmodcraft/archive/releases/download/<tag>/<asset>` — byte-for-byte what 008a's
   `naming.release_asset_url("worldofmodcraft", "archive", tag, asset)` returns, so 008a's closed test literals stay true.
3. **Consumer rules (normative; site 055, 008b's checks, task 010's runbook check, any later launcher/installer):** compare
   `source_archive` by exact string equality with the URL derived from the entry's own `id` and `version` (never parse and accept
   "close enough"); request the front with **no query string** (this applies to the request to the front only); follow later
   hops (any 301/302/307/308: GitHub, then its signed asset host) **unchanged, including their query**, only over https (TLS
   verified), within **at most 5 hops in total**; those hosts are not an allowlist or trust anchor; accept the final 2xx bytes only within the size cap
   (52,428,800 bytes, 50 MiB; consumers abort the download at the cap; see Approach 3) and only after `source_sha256` and the signature
   (all of `signature-format.md`'s rejection rules 1-11) verify, **before any use**; never execute or parse HTML. Consumers do
   **not** enforce hop 1's target (Q9).
4. **Fail closed (normative).** Two lists.
   (a) **Hop 1, checked by the producer (pre-T1, Q5/Q9) and the manager (live):** the response from
   `archive.worldofmodcraft.com` is anything other than 301/302/307/308 whose `Location` equals the derived target byte for
   byte — a 200 (with any body, e.g. a meta-refresh page), any 4xx/5xx, any other `Location`.
   (b) **Everywhere (consumers and producer):** DNS failure, TLS failure, any non-https hop (no downgrade), any 4xx/5xx on a
   later hop, a final response that is not 2xx, more than 5 hops, a body over the size cap, hash or signature mismatch → the
   artefact is **unverified**: consumers do not install, extract or render it and never fall back to another URL (Q4); the
   producer does not write T1 (Q5) — the version stays `pending`.
5. **Stale text goes:** the "What this document does not cover" bullet about which repository hosts the Releases becomes the Q-E
   decision; "Questions" updated.
6. **Live capture before merge** (Q7): unauthenticated `curl` after M12.
7. **Producer rule (Q10):** 008b publishes no version containing build metadata (`+`) until a live Release proves GitHub
   resolves `+` in `releases/download` (task 010). The derivation still defines the URL of such a version.

## Context to load (reading list, 9 groups)
1. Registry `contracts/artifact-naming.md` (whole). 2. `contracts/entry.schema.json` (`source_archive`, `^https://\S+$`).
3. `contracts/append-only.rules.md` T1 (condition 3; "T1 is checked for shape only"). 4. `contracts/signature-format.md` ("What is
signed"; "What a verifier must reject" 1-11 incl. rule 11's identity binding). 5. `contracts/archive-layout.md` lines ~19, ~195.
6. `tools/pipeline/naming.py`, `tests/pipeline/test_cli.py::test_ac12_*` (read-only), `docs/pipeline/build-pipeline.md` ~54.
7. `docs/contracts/README.md` (032 N5/N5b and 067 AC2.5 phrases "eight prose", "None of the three tasks implements checking
logic" — task 087 re-pins them; whichever merges first, both phrases survive). 8. Platform: 058 report; 091 spec/log (M12);
`008-build-pipeline.md` (F6, Q-E, Q-G); `008c-pipeline-write-back.md` (design 2, criterion 5); `008b-pipeline-workflow.md`
(criteria 3, 6; Forbidden on `source_archive`); `055-site-live-registry.md` (design 3, 4, Q3); `010-test-mod.md` ~96;
`depgraph.md` (N6, E7). 9. ADRs 0041, 0117, 0103, **0121** (version lifecycle `pending`; pending, stays pending — T1/T3 are the 008c/082 mechanics this
   task only names), **0077** (disaster mirror: move off GitHub — why the front is a repointable pointer, not a hostname bound
   to GitHub); MANAGER.md §2c, §3.7; REVIEW-CHECKLIST items 8, 12; CLAUDE.md rule 11.
10. `INDEX.json` lookup (ADR/decision index for archive, redirect, naming, mirror) **done by the manager before approval**; no
    further ADR found beyond 9.

## Approach (the amendment's outline)
New section **"## The archived-source URL (`source_archive`)"** after "The naming scheme":
1. **Definition.** Constant host `archive.worldofmodcraft.com`; scheme `https`, no port, userinfo, query, fragment or trailing
   slash; the URL form; worked examples typed literally: `mc`, `hello-world`, `1.0.0` →
   `https://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz`; its `.minisig` = that URL plus
   `.minisig`; `a`, `b`, `1.0.0-rc.1+build.5` →
   `https://archive.worldofmodcraft.com/a.b-1.0.0-rc.1+build.5/a.b-1.0.0-rc.1+build.5.tar.gz`; each example's redirect target.
   One sentence: this section is the only place the hostname is fixed; 008c's single named constant takes its value from here.
2. **Path safety and injectivity (derived, stated as such):** every character of `tag` is in `[0-9A-Za-z._+-]` (RFC 3986 `pchar`;
   no percent-encoding needed or permitted; `+` literal, `%2B` is a different string); no segment can be `.` or `..`; distinct
   triples give distinct URLs (name has no `.`; the semver major is a digit run ending at the first `.`); injectivity is over
   **byte strings**. Cloudflare wildcard matching is case-insensitive and GitHub tags are case-sensitive, so the front must
   preserve case (AC11b checks it). 092-verify checks injectivity by property test.
3. **How the address works (pointer, not configuration):** a real HTTP redirect configured at Cloudflare per runbook M12
   (platform) — path-only, status 302 chosen in 091; nobody may depend on which 3xx. Hop 1 target = the
   `worldofmodcraft/archive` Release asset (Q-E); hop 2 is GitHub's redirect to a signed, expiring asset host
   (`release-assets.githubusercontent.com`, observed in 058), never stored. Hops 2+ are followed unchanged, including their
   query, over https only, **at most 5 hops in total**. **Size cap:** 52,428,800 bytes (50 MiB) = `tools/pipeline/archive.py:28`
   `MAX_COMPRESSED_BYTES` and the site downloader ceiling (`docs/pipeline/build-pipeline.md` ~100); a stated decision (see
   Decisions); consumers abort the download at the cap; raising 008a's compressed-size limit above this requires amending this
   contract (`archive-layout.md` states no cap — grepped 2026-10-26). M12 is the source of truth for the
   rule's syntax. **Q9:** the producer and the manager check hop 1 exactly; consumers do not, so a repoint of the front changes
   M12 and this section's redirect-target sentence only. [unverified], one sentence each: case preservation of the captured
   path (matters for uppercase prerelease identifiers); whether GitHub resolves a tag containing `+` in `releases/download`;
   whether GitHub keeps an uploaded asset filename containing `+` unchanged; certificate issuance for the proxied name. None is
   a trust dependency — point 6 catches each by failing closed.
4. **Producer obligations (008c, 008b):** `source_archive` is exactly the derived URL from the entry's own `id` and `version` —
   never from upload output, the API or `result.json` text. **Before opening T1** the pipeline (i) requests the front without
   following redirects and requires hop 1 = 301/302/307/308 with `Location` byte-equal to the derived target (Q9), then (ii)
   fetches the URL through the full chain under the consumer rules and requires the SHA-256 of the received bytes to equal its
   computed `source_sha256`; any failure = pipeline fault (082 PT10 exit 2: no T3, stays `pending`, the run fails naming the
   URL) — the only point where a non-resolving URL can be stopped before it becomes permanent. **Q10:** 008b publishes no
   version with build metadata (`+`) until a live Release proves GitHub resolves `+` in `releases/download` (task 010); such a
   version gets a T3 `rejected` with the reason in Decisions (Q10), not left `pending`.
5. **Consumer obligations:** Objective 3, one sentence each, each pinned by full text; one sentence states that consumers do not
   enforce hop 1's target and why (Q9).
6. **Fail closed:** Objective 4's two lists, spelling out "M12 not done yet: the name does not resolve", "the host answers 200
   with HTML (a meta-refresh page, 058 option A)" and "a hop downgrades to http" as failures — never "follow the HTML". No
   fallback to a self-built `github.com` URL (Q4).
7. **Attack attempts** (house style, numbered after the existing two): (3) a hostile or compromised redirect (Cloudflare account
   takeover points the front at attacker bytes or another genuine signed artefact) → hash mismatch or signature rule 11 (id and
   version in the trusted comment) rejects; at worst denial of service, never a substituted install; the producer's and
   manager's hop-1 check detects a repoint, consumers still hold. (4) a plausible variant URL accepted by a lenient consumer
   (`HTTPS://ARCHIVE…`, `%2B` for `+`, trailing `/`, `?x=`, `/../`) → exact string equality rejects all; the rule forwards any
   path, so a consumer fetching non-derived paths could be steered elsewhere on github.com — consumers fetch only the derived
   string, and verification still applies.
8. **"What this document does not cover", updated:** the "which repository hosts these Releases" bullet → "decided:
   `worldofmodcraft/archive` (Q-E, 008 umbrella F6)"; added: the Cloudflare rule's exact configuration (M12); `build_log_url` (a
   repository file at `logs/<ns>.<nm>/<version>.log`, not a Release asset — not served by this front; out of scope); enforcing
   equality in registry CI (Q2, booked). "Questions" → "(none open; task 092's Q1-Q10 decided by Ludwig on 2026-10-26)".
9. **`docs/contracts/README.md`:** in the `artifact-naming.md` row only, one clause naming the archived-source URL
   `https://archive.worldofmodcraft.com/<tag>/<asset>` (Cloudflare redirect to `worldofmodcraft/archive` Releases) and its
   fail-closed consumer rules. No other sentence changes.
10. **`contracts/examples/entry/**` (Q3):** `source_archive` values only, each to the URL derived from that example's id/version.
    An example whose version is not semver (e.g. `invalid/version-not-semver.json`, `"1.0"`) gets "the tag form of the literal
    string" (the derivation applied to the literal string, as the example is invalid on purpose); its validity verdict does not
    change.

**Must not change** (each byte-identical `BASE`→`FINAL`): `entry.schema.json` (the site compares raw SHA-256 — no re-sync);
`append-only.rules.md` (T1 text incl. the `cdn.worldofmodcraft.org` example is pinned by `057-pinned-sections.json`, checked
live by closed 057-verify; that worked-example URL is illustrative and the file is not edited); `signature-format.md`, `archive-layout.md` (their "bytes … as retrieved" wording already covers the
end of a redirect chain).

**Closed scripts and pins (checked 2026-10-26 on registry origin/main):** no closed script pins `artifact-naming.md` text; the
only related pin is `tests/pipeline/test_cli.py` test_ac12 (run by 008a-verify) — the `github.com/…/releases/download/…`
literals, which stay true as the redirect target. A schema hostname pin would redden closed 065-verify AC2
(`https://cdn.example.org/a.tgz` valid) and 057 T1/F1 — the reason for Q1 = B. README: see context 7.

**Downstream sentences 092 does not edit** (the manager books them at merge): 008c design 2 / criterion 5 → this function;
008b criterion 3; criterion 6's "blocked until 058" → "fetched with `curl -L` through the front, bytes equal"; 008b gains the
pre-T1 check (Q5) and the Q10 refusal (T3 `rejected` for a `+` version, reason as in Decisions); 055 design 3 (shape fixed), Q3 allowlist `archive.worldofmodcraft.com` → `github.com` → GitHub's asset host,
the "if 058 finds HTML" clause struck, `localArchivePathFor` follows the new path; 010 ~96 ("resolves" = `curl -sL` + `sha256sum`
equals `source_sha256`); 056 second pass (Q8); 008 umbrella criterion 3 and Dependencies (c) done; the Q2 follow-up.

## Acceptance criteria → `docs/tasks/092-verify.sh` (the log pastes its output)
Deterministic and offline (stdlib Python and git) except AC11 (behind `--live`); exit code = number of failures; own-change checks on the fixed
`BASE`/`FINAL` (and `TIP` if needed) recorded in the script (item 12); live guards on HEAD in a temp clone; the caller's worktree
never modified.
1. **Section exists** at `FINAL`, absent at `BASE` (control); the file's first paragraph still names `E7`, `N5 -> N6`,
   `docs/architecture/depgraph.md`.
2. **Literals:** host, URL form, redirect-target form and the three worked examples byte-equal to literals typed into the script
   (never derived from the code or text under test).
3. **Three-way agreement:** each example's redirect target equals `naming.release_asset_url("worldofmodcraft", "archive", tag,
   asset)` (008a, imported read-only from a clone at the fixed `BASE`/`FINAL`, not `HEAD`) and test_cli.py's literals (same
   clone); each example `source_archive` fullmatches `entry.schema.json`'s
   pattern in a `published` and a `removed` version document under both `tests/contracts/schema_check.py` and 007a's strict
   `tools/registry/schema.py`.
4. **Injectivity and path safety:** the script's own derivation over ≥ 2,000 generated triples (names with `-` and digits,
   prerelease and build versions, adversarial splits such as `x-1`/`2.3.4`): no collisions; no `%`, `..`, `//` after the authority,
   `?` or `#`; every URL matches `^https://archive\.worldofmodcraft\.com/[0-9A-Za-z._+-]+/[0-9A-Za-z._+-]+\.tar\.gz$`;
   reserved-device-name namespaces stay excluded (quote the unchanged rule).
5. **Normative sentences pinned by full text** (032 round-6 lesson), each exactly once (the writer states each — hop bound,
   size cap, hop-1 ownership, etc. — once in the contract and refers to it elsewhere; the script counts occurrences): exact-string equality; https/TLS;
   hop 1 exactness checked by producer and manager only, consumers do not enforce it (Q9); later hops followed unchanged
   over https only, at most 5 hops in total; the size cap number; no `+` versions published until proven, and their T3 `rejected` with the reason (Q10); never parse
   HTML; never send a query; hash and signature (rules 1-11) before any use; host never
   trusted; no fallback; producer computes from `id`/`version` only; the pre-T1 fetch-and-hash check (pipeline fault, stays
   `pending`); each fail-closed case; attack attempts 3 and 4; the four [unverified] markers of Approach 3 (incl. the `+` asset filename).
6. **Stale text gone:** "no ADR or graph node fixes this" 0 at `FINAL`, ≥ 1 at `BASE`; the old Questions sentence replaced; the
   naming-scheme bullets (tag, tarball, `.minisig`), the Windows rule and attack attempts 1-2 byte-identical to `BASE`.
7. **No other contract changed:** `git diff --name-only BASE FINAL -- contracts/` = `artifact-naming.md` plus
   `contracts/examples/entry/**`; a parsed-JSON diff of each example shows only `source_archive` changed, each to its derived URL,
   `_comment` and validity verdicts unchanged; SHA-256 of `entry.schema.json`, `append-only.rules.md`, `signature-format.md`,
   `archive-layout.md` equal at `BASE` and `FINAL` (proof the site needs no re-sync). ADVISORY with `--site DIR`:
   `node DIR/scripts/check-schemas.mjs <clone at FINAL>` → `compared=3 differ=0`.
8. **README:** the `artifact-naming.md` row names the URL; "eight prose" and "None of the three tasks implements checking logic"
   still present.
9. **Pinned own-change scope:** `git diff --name-only BASE FINAL` inside the File scope; controls `FINAL=BASE` → red; unreachable
   pin → red, never skipped.
10. **`--mutate`** (temp clone; each red, restored byte-identically; positive control green): host → `.org`; join → `<tag>-<asset>`;
    target repo → `worldofmodcraft/registry`; example tag → `mc:hello-world-1.0.0`; the hash-and-signature-before-use sentence
    deleted; a permissive tail sentence appended to the consumer rules ("may fall back to the github.com URL"); a sentence making
    consumers enforce hop 1's target appended (Q9); "5 hops" → "bounded"; an [unverified]
    marker dropped; one byte of `entry.schema.json`'s description changed (AC7 red); `signature-format.md` touched (AC7 red); a
    README phrase deleted (AC8 red).
11. **LIVE — gates the merge (Q7), behind `--live`** (network, unauthenticated; run by the manager after Ludwig reports M12
    done). The default run prints "LIVE not run; merge gate satisfied by the log capture of <date>" and does **not** count it as
    a failure; the merge gate is the capture pasted in the log. Checks use `curl -s -o /dev/null -w '%{http_code}
    %{redirect_url}'` **without** `-L` (hop 1 is invisible to auto-following clients, Q9): (a) the `mc.hello-world-1.0.0`
    tarball URL → 301/302/307/308 (302 per M12) with `Location` byte-equal to its derived target; (b) the `+`-build URL and an
    uppercase-prerelease variant (`…-1.0.0-RC.1/…`) → `Location` keeps every byte, `+` and case; (c) the same URL with `?x=1` →
    `Location` carries **no** query (M12 is path-only; if it does, record and stop — the contract text must change); (d)
    `curl -sI https://archive.worldofmodcraft.com/` recorded, including the `server: cloudflare` header; (e) the certificate
    is valid (plain `curl`, no `-k`); (f) an `http://` request → 302 to an https `Location` (M12's third check). AC11 **cannot
    prove** GitHub resolves a `+` tag or keeps a `+` asset filename (Q10 covers it). The end-to-end bytes check is 008b
    criterion 6 / task 010 (no Release exists yet).
12. **Fresh clone and closed scripts:** 092-verify passes in a fresh clone (item 8); every closed verify script on registry main
    at dispatch green on HEAD, one at a time on a quiet machine (`ps` logged).

## File scope
Registry: `contracts/artifact-naming.md` (new section, "does not cover" bullets, Questions); `docs/contracts/README.md` (the
`artifact-naming.md` row only); `contracts/examples/entry/**` (`source_archive` values only); `docs/tasks/092-artifact-naming-
archive-url.md` (log); `docs/tasks/092-verify.sh` (new). Platform: this file; `docs/architecture/depgraph.md` (N6 "Lives in" cell
only). Anything else = stop and report.

## Size
0 source files; ~100-170 lines of contract prose, 1 README row, ≤ 14 example files changed by value only, a verify script of
~300-420 lines (adds hop-1/`--live` handling and clones at `BASE`/`FINAL`); reading list 9 groups + the INDEX.json record. The reading list is ~25 files in 9 groups, over the
10-file cap: one contract amendment has nine inbound documents to cross-check; splitting would hide the cross-doc agreement.

## Forbidden (beyond MANAGER.md §3.7)
Any byte change to `entry.schema.json`, `append-only.rules.md`, `signature-format.md`, `archive-layout.md`; editing any closed
verify script, `057-pinned-sections.json`, `057-gen-fixtures.py`, `057-transition-fixtures.json`, `tests/` or `tools/`; changing
the tag or asset scheme or the reserved-device-name rule; writing `source_archive_url` (008c); Cloudflare or GitHub behaviour
without a command or `[unverified]`; presenting the redirect or host as a trust or integrity mechanism; any fallback URL; any DNS
or Cloudflare change, any GitHub write, any credential (CLAUDE.md rule 11); deriving an expected literal from the code or text
under test.

## Dependencies / sequencing
Upstream: 058 merged (`313e804`); 091 merged and **M12 done by Ludwig** before AC11 (AC1-AC10 can be written now). File overlap:
`docs/contracts/README.md` is also edited by 082 (#20) and 087 (#24) — rebase onto whichever merges first and re-run 032, 067 and
087. Downstream (booked at merge): 008c (unblocked) → 008b → task 010's first publish; 055 design 3 and Q3; the 056 second pass;
the 008 umbrella; the Q2 follow-up.

---
# Task 092 log
- 2026-10-26 Plan agent: spec drafted from decision C (`8a4f2ac`), the 058 report, 091's M12, the 008/008b/008c/055 specs and the
  registry at `4268735`. Measured: no closed script pins `artifact-naming.md` text; a schema hostname pin would redden closed
  065-verify AC2 and 057 T1/F1; the site compares schemas by raw SHA-256; the examples and 057 fixtures use
  `archive.worldofmodcraft.com` with a non-conforming path (`/kelsi/housing/1.0.0.tar.gz`); `system-overview.md` says "not chosen".
- 2026-10-26 manager: Q1-Q8 decided by Ludwig ("Stjärna på allt"); M12's final form (path-only expression) folded into Approach 3
  and AC11(c). Awaiting independent spec review.
- 2026-10-26 manager: spec review round 1 FAIL (2 HIGH, 4 MED, 2 LOW) folded in; Q9 = A, Q10 = A decided by Ludwig ('Kör A stjärna'); round 2 pending.
- 2026-10-26 manager: spec review round 2 PASS with four LOW fixes folded in (reading-list justification, Q10 outcome T3 `rejected`, each normative sentence stated once, later hops any 301/302/307/308; size cap now a stated decision). Status: spec-approved (manager, 2026-10-26, after spec review rounds 1-2).
- 2026-10-26 doc-writer (phase 1 of 2): BASE = 426873502a150ef746063c1b55c2cfbfeed31566 (registry origin/main at cut;
  platform cut 313e804761ec9abd6cfcb0c2cc6ef295d6e92418). FINAL = 41776d74c3200f8a9eded5a3444fcd4703d998ef (content commit: contracts/artifact-naming.md,
  14 files under contracts/examples/entry/, docs/contracts/README.md row). Platform branch task/092-depgraph carries the
  depgraph.md N6 cell. Suites on FINAL, PYTHONDONTWRITEBYTECODE=1: tests/contracts 32 tests OK; tests/registry 362 tests OK.
  Left for phase 2: 092-verify.sh, the PR(s), the AC11 live capture, pasting verify output here.
- 2026-10-26 implementer (phase 2 of 2): `docs/tasks/092-verify.sh` written (script commit 001058e on top of TIP `3348f0a`; TIP stays the
  last commit before the script, as in 039a). Modes: default = AC1-AC9 offline (git + stdlib python3, ~25 s); `--mutate` = AC10;
  `--live` = AC11 (NOT run: M12 is not configured); `--closed [--nm DIR]` = AC12; `--site DIR` = the AC7 ADVISORY node check.
  Pins typed in the script: BASE `426873502a150ef746063c1b55c2cfbfeed31566`, FINAL `41776d74c3200f8a9eded5a3444fcd4703d998ef`, TIP
  `3348f0a52b95887c034c1835b604433c19237f6c`. Every expected literal (host, URL form, redirect-target form, the examples' URLs and
  targets, each normative sentence, the 24 reserved device names, the scope pattern) is typed in the script; the contract text is only
  searched. The script's own `derive()` (typed from the Objective's formula) is cross-checked against its typed literals (AC2.1/2.2).
  Phase-1 rulings applied: "hop" = one redirect response, the final 2xx not counted (pinned by the sentence "A **hop** is one redirect
  response (301, 302, 307 or 308); the response that ends the chain is not a hop." exactly once); the contract may cite runbook M12 by
  name before 091 merges; `depgraph.md`'s "Last reviewed" stamp is untouched.
  **Design notes for the reviewer.**
  (1) AC12 is its own flag (`--closed`), not part of the default run: closed script 039a sweeps every `docs/tasks/*-verify.sh`, so a
  default 092 that also swept them would recurse (039a -> 092 -> 039a). The default run is what 039a's sweep will call after merge
  (it needs no node and no network). (2) The spec says "the three worked examples"; the contract spells out two triples, and the
  signature's redirect target is defined by the rule "the tarball's redirect target plus `.minisig`", not by a literal. AC2 therefore
  pins six literals in the contract (tarball URL, signature URL, tarball target of example 1, example 2's URL and target, plus the
  target form) and AC2.9 pins the signature-target rule (typed `EX1_TS == EX1_T + ".minisig"`, rule sentence present); AC3.1 checks
  `naming.release_asset_url` returns the typed signature target. (3) AC5 pins each normative block whole: the 7 consumer rules, 3
  producer obligations, both fail-closed lists and the 4 `[unverified]` bullets are compared byte-for-byte (whitespace-normalised) with
  the typed text, and each is counted exactly once over the whole file; a tail sentence appended to a rule, a deleted rule or a
  weakened number therefore reddens. (4) AC7's parsed-JSON diff covers all 20 example files (14 changed, 6 untouched pending/rejected
  shapes), and a raw line diff proves only `"source_archive":` lines changed (no reformatting). (5) The `--live` helpers were exercised
  against a throwaway local fake front on 127.0.0.1 (302 + Location, with `+` and a query) to prove the parsing; the real host was NOT
  contacted. AC11c is written to fail with "STOP: ... change the contract text" if the front ever forwards a query.
  **Run, default, PYTHONDONTWRITEBYTECODE=1, foreground, worktree at 001058e: exit 0, 184 PASS, 0 FAIL** (AC9 own-change block 9 PASS +
  3 controls + 4 scope controls; content checks 159 PASS: AC1 6, AC2 14, AC3 18, AC4 11, AC5 55, AC6 18, AC7 29, AC8 8). Key lines:
  - AC9: `PASS  git diff --name-only BASE FINAL is non-empty and inside the file scope (16 files)`; `PASS  AC9 control: FINAL=BASE makes 2
    own-change check(s) fail (red as required)`; `PASS  AC9 control: an unreachable FINAL pin is red, never skipped (5 failure(s))`.
  - AC4: `PASS  AC4.4 24178 distinct valid triples generated (floor 2000); 24 reserved-namespace triples excluded, 0 invalid skipped`;
    `PASS  AC4.6 injectivity: 24178 URLs from 24178 triples, collisions: []`; `PASS  AC4.7 every URL matches
    ^https://archive\.worldofmodcraft\.com/[0-9A-Za-z._+-]+/[0-9A-Za-z._+-]+\.tar\.gz$ with no %, .., //, ? or # (bad: [])`; the
    reserved-device-name rule is quoted from the unchanged section (AC4.3) and `naming.check_namespace` rejects all 26 spellings (AC4.2).
  - AC7: sha256 equal at BASE and FINAL for `entry.schema.json` (`109e172e0d56a58f...`), `append-only.rules.md` (`c555d2f87ca14e98...`),
    `signature-format.md` (`fdda671956214292...`), `archive-layout.md` (`c8a5466ba13f18cf...`), `page.schema.json`, `manifest.schema.json`
    (the site needs no schema re-sync); `AC7.6 the 14 example files with a parsed-JSON diff are exactly the 14 files git reports changed`.
  - AC3: `naming.release_asset_url` at BASE and at FINAL (imported from the clones) and `tests/pipeline/test_cli.py::ComputedValues::
    test_ac12_release_asset_url_pinned_over_artifact_naming_examples` (run in both clones) agree with the typed targets; `naming.py`
    and `test_cli.py` are byte-identical BASE/FINAL; both published and removed version documents for both example URLs validate under
    `tests/contracts/schema_check.py` and the strict `tools/registry/schema.py`; two negative controls (http://, a space) are rejected by both.
  **`--mutate` (foreground): exit 0, 45 PASS, 0 FAIL.** Positive control green (159 checks) before and after; every mutation red on the
  named check and restored byte-identically (sha256 equal, `git status` clean):
  host -> .org (AC2, 12 failing); URL join -> `<tag>-<asset>` (AC2, 1); redirect target repo -> `worldofmodcraft/registry` (AC2, 5);
  example tag -> `mc:hello-world-1.0.0` (AC2, 4); hash-and-signature-before-use sentence deleted (AC5, 5); permissive tail "may fall back
  to the github.com URL" (AC5, 4); tail making consumers enforce hop 1's target (AC5, 2); "5 hops" -> "bounded" (AC5, 6); an `[unverified]`
  marker dropped (AC5, 2); one byte of `entry.schema.json`'s description (AC7.2, 2); `signature-format.md` touched (AC7.2, 2); the README
  phrase "None of the three tasks implements checking logic" deleted (AC8.4, 7).
  **Fresh clone** (`git clone -b task/092-artifact-naming-archive-url https://github.com/worldofmodcraft/registry.git`, at 001058e, default
  mode): exit 0, 184 PASS, 0 FAIL.
  **AC7 ADVISORY (`--site /home/ludwig/wt/site-task-065`, the site branch task/065-resync-entry-schema at a5c88d6, which carries `scripts/check-schemas.mjs`; site main
  does not have the script yet)**: `compared=3 differ=0` against the FINAL clone.
  **AC11 (live): NOT RUN.** Pending: Ludwig finishes runbook step M12; then the manager runs
  `docs/tasks/092-verify.sh --live` (unauthenticated `curl`, no credentials) and pastes the capture here; it gates the merge (Q7).
  **AC12 closed-script sweep: PENDING (not run).** `docs/tasks/092-verify.sh --closed --nm <node_modules with ajv>` was started and polled the
  machine for ~15 minutes; `ps -eo args | grep -E 'docs/tasks/.*-verify\.sh'` never showed it quiet (other sessions' 007a, 062, 064, 065, 067,
  069, 070 verify runs were in flight, e.g. `062-verify.sh /tmp/tmp.W34JSvI2pC/L/tools/dev/node_modules`). The run was stopped before sweeping
  anything, so no closed script was measured concurrently with another. To complete: when `ps` shows no other `*-verify.sh`, run
  `PYTHONDONTWRITEBYTECODE=1 docs/tasks/092-verify.sh --closed --nm /home/ludwig/wt/registry-task-084/tools/dev/node_modules` (foreground; it
  polls up to 60 minutes itself) and paste the result here. After merge, 039a's sweep calls 092 in default mode (no node, no network, no flag).
- 2026-10-26 manager (session 12): **AC11 live capture** — run on a quiet machine (queue log: 0 other verify processes at start),
  `docs/tasks/092-verify.sh --live` at 2e1cd15, 2026-10-26T19:56:52Z, unauthenticated curl 8.18.0: AC1-AC8 159 PASS 0 FAIL;
  AC11a (tarball URL -> 302, Location byte-equal to the derived target), AC11b (`+` kept; `-RC.1` case kept), AC11c (`?x=1` -> Location
  without query), AC11d (`server: cloudflare`), AC11e (plain curl, certificate valid) PASS; **AC11f FAIL**: `http://archive.../mc.hello-world-1.0.0/
  mc.hello-world-1.0.0.tar.gz` -> `302 https://github.com/worldofmodcraft/archive/releases/download/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz`;
  the script requires the Location on `https://archive.worldofmodcraft.com/`. SUMMARY failed=1. This FAIL line is the red-before-fix evidence.
  **Manager ruling (§8b 3a, follows from the spec):** script defect. The task's AC11(f) requires only "an `http://` request -> 302 to an https
  `Location`", and runbook M12's third check (task/091, 46f3a20) expects exactly the observed GitHub target. The front is correct.
- 2026-10-26 independent review (reviewer, read-only, no suite run): **PASS-WITH-AMENDMENTS.** Scope clean; Q1-Q10 implemented; examples change
  only `source_archive`. Agrees with the AC11f ruling. Required for the fix round:
  F1 (MED, §3.6c) `contracts/artifact-naming.md:112-115` states Cloudflare's case-insensitive wildcard matching as fact with no source or inline
  caveat: cite runbook M12 / Cloudflare docs at the claim or mark it [unverified] there; re-pin AC5's text.
  F2 (LOW) the [unverified] markers for case preservation, the literal `+` in the path and certificate issuance (:191-195) are now observed
  (capture above): update them to "observed 2026-10-26, unauthenticated curl, task 092 log", and fix the "the manager's live checks record whether
  it does" sentence (:114-115); re-pin AC5.
  F3 AC11f: require 3xx in {301,302,307,308} with `redirect_url` AND the raw Location byte-equal to `EX1_T`; no host-prefix match; new failure text.
  Add an offline `--live-selftest` (local fake front on 127.0.0.1) with a passing case (http -> the https GitHub target) and a failing case (wrong
  target), shown red against the current check before the fix. AC11c: also compare the raw Location header. AC9: add a name-only check that
  TIP..HEAD touches only `docs/tasks/092-*` files.
  Merge-order condition: platform #82 (091, runbook M12) merges before 092 (the contract cites M12). Before merge: `--mutate`, a fresh-clone default
  run at the new head, `--live`, and the AC12 `--closed` sweep, all pasted here.
  Fix round dispatched after the session-12 quiet-machine queue ends (its runs would overlap the queue).
- 2026-10-26 implementer (fix round for the review F1-F3, base head a687da7):
  **F1** `contracts/artifact-naming.md` (path-safety paragraph): the case-insensitivity claim now cites platform runbook step M12
  (`docs/runbooks/site-v1-manual-steps.md`, task 091, commit 46f3a20, which cites Cloudflare's documentation as read 2026-10-26) and says this
  document has not re-read that documentation; the rule itself is unchanged. **F2** same paragraph: "the manager's live checks record whether it
  does" -> "observed 2026-10-26 by unauthenticated curl, recorded in the task 092 log: the live front does preserve it". The "Unverified"
  list now holds only the two GitHub `+` items (still `[unverified]`, decision Q10, not observed); a new **Observed 2026-10-26** list records
  case preserved, literal `+` kept in the path, valid certificate (issuance time not recorded, not a dependency). The old bullet
  "How long certificate issuance ... takes" is therefore gone, and AC5.8/AC5.9 now pin two markers plus three observed facts.
  **F3** `docs/tasks/092-verify.sh`: AC11f requires 301/302/307/308 with redirect_url AND raw Location byte-equal to EX1_T (no host-prefix match;
  new failure text); AC11c also compares the raw Location (shared `ac11_exact_ok`); AC9 gains `post_tip_check` (commits after TIP, first-parent,
  name-only, touch only `docs/tasks/092-*`) with two red controls (BASE..FINAL as range; unreachable pin); new offline `--live-selftest`
  (python3 stdlib fake front on 127.0.0.1, 17 cases; the real host is never contacted); two new `--mutate` cases for the F1/F2 text.
  **Red before the fix** (commit 7ca6ca2: selftest fixture, old AC11f/AC11c functions; `--live-selftest`, SUMMARY failed=5):
  `FAIL selftest AC11f http -> https GitHub target (302|301|308): verdict FAIL, required PASS` (3 lines),
  `FAIL selftest AC11f http -> https://archive.worldofmodcraft.com: verdict PASS, required FAIL`,
  `FAIL selftest AC11c raw Location has a dot segment (redirect_url is normalised and looks right): verdict PASS, required FAIL`
  (curl normalises `../` in redirect_url, so only the raw header differs). **Green after the fix**: same command, every selftest line PASS,
  `SUMMARY failed=0`. Pins: BASE unchanged; FINAL = TIP = ab31a88e6e828db689b64e73d4310320938570de (the F1/F2 contract commit); the AC9
  "no closed verify script touched" regex now exempts `092-verify.sh` itself (BASE..FINAL contains it). Post-TIP check design note: it walks
  the first-parent chain, so a merge of registry main into the branch adds no files; if TIP is not on HEAD's first-parent chain (after the
  branch is merged into main) it prints an explicit "skipped on purpose" PASS line instead of reddening 039a's post-merge sweep (see Questions).
  **Results** (all `PYTHONDONTWRITEBYTECODE=1`, head 129aadf): default and `--live-selftest`: exit 0, SUMMARY failed=0 (204 PASS with selftest);
  `--mutate`: exit 0, SUMMARY failed=0, 52 PASS, the two new mutations red on AC5 and restored byte-identically (sha256 e8f3149cadbe1d08);
  `--live` (2026-10-26T21:00:27Z, unauthenticated curl 8.18.0): AC11a, AC11b (x2), AC11c (redirect_url and raw Location both the clean target),
  AC11d `server: cloudflare`, AC11e, AC11f (`302`, redirect_url and raw Location = the https GitHub target) all PASS, SUMMARY failed=0.
  Fresh-clone default run: see the next line. `--closed` (AC12) not run, as instructed; the manager runs it.
  **Questions (booked, conservative option assumed):** Q11. The AC9 post-TIP check skips (with an explicit PASS line) when TIP is not on
  HEAD's first-parent chain, which is the post-merge state. Option A (assumed, ★): skip with a message. Option B: always red after merge
  (039a's sweep would fail). Option C: pin a second TIP after merge in a follow-up task.
  **Fresh clone** (`git clone -b task/092-artifact-naming-archive-url`, at 1d9570b, default mode): exit 0, 187 PASS, `SUMMARY failed=0`, `PASS  post-TIP: commits after TIP touch only docs/tasks/092-* files (2 file name(s))`.
