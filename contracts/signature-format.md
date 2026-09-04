# Signature format: minisign, detached, over the archived source

Contract for edge **E9** (`N5 -> signing key`) in `docs/architecture/depgraph.md`. The choice of
minisign, Ed25519, detached signature, `key_id` from the public-key comment, and a signed trusted
comment carrying mod id, version and SHA-256 is already decided (mission log Q3=A; ADR-0041). This
document's job is the one thing that decision left unstated: the **exact byte layout** of what is
signed and what is stored, precisely enough that a verifier implemented independently of the
signer — a different language, a different minisign library, hand-rolled Ed25519 — produces the
same accept/reject verdict as the signer intended. **No real key, token, or signature over real
project data appears anywhere in this document; every example below is fabricated placeholder
data, clearly marked as such.**

## What is signed: the archived source tarball, unmodified

The signed artefact is exactly the bytes of `versions[i].source_archive`
(`contracts/entry.schema.json`) — the `.tar.gz` file `contracts/artifact-naming.md` (E7) names and
`contracts/archive-layout.md` (E11) describes the interior of. **The signer signs those bytes as
retrieved, with no transformation** — not the decompressed tar stream, not a normalised or
re-ordered copy, the gzip file itself, byte for byte. `source_sha256` (`entry.schema.json`) is the
SHA-256 of this exact same byte sequence; both fields describe the same object from two different
angles (a hash and a signature), and this document's later cross-check section exists precisely
because those two descriptions can drift apart if either is tampered with independently.

## This project adopts minisign's own signature file format unchanged

Everything in this section is minisign's own file format (Frank Denis's reference
implementation), not a project invention — stated here in full because an implementer must not
need to go spelunking in minisign's source to reconstruct it, and because getting any one byte
boundary wrong here silently breaks interoperability with every other correctly-written verifier.

A minisign detached signature, as produced by `minisign -Sm <file>`, is a text file of exactly
four lines:

```
untrusted comment: <arbitrary text, not authenticated>
<base64: 2-byte algorithm + 8-byte key id + 64-byte Ed25519 signature>
trusted comment: <this project's fixed grammar, see below>
<base64: 64-byte Ed25519 signature over (line-2's 64-byte signature || the trusted comment's raw bytes)>
```

**Line 1, the untrusted comment, carries no security value and is not covered by any signature in
this file** — minisign's own design; a verifier must never make an accept/reject decision based on
its content, and this document does not constrain what it says (informational text describing the
signing event is sufficient; e.g. `untrusted comment: signature from minisign secret key`,
minisign's own default).

**Line 2, base64-decoded, is exactly 74 bytes:**

| Bytes | Meaning |
|---|---|
| 0–1 | Signature algorithm: ASCII `"Ed"` (bytes `0x45 0x64`) for the legacy, non-prehashed variant (sign the file's raw bytes directly), or ASCII `"ED"` (bytes `0x45 0x44`) for the prehashed variant (sign BLAKE2b-512 of the file's raw bytes) — minisign's default since its version 0.10 and the variant this project's pipeline must use unless a specific, documented reason requires the legacy form. **The two bytes are self-describing: a verifier reads which variant was used from this field and must support both**, never assume one without checking, because the field exists exactly so old and new signatures both verify correctly forever. |
| 2–9 | The 8-byte key id, identical to the key id embedded in the public key that produced this signature (see "Deriving `key_id`" below). |
| 10–73 | The 64-byte raw Ed25519 signature, over the file's raw bytes (`"Ed"` variant) or over BLAKE2b-512(file's raw bytes) (`"ED"` variant). |

**Line 3, the trusted comment**, is `"trusted comment: "` followed by this project's fixed
payload grammar, defined below. Its raw bytes (everything after the `"trusted comment: "` prefix,
up to but not including the line's trailing newline) are one of the two inputs to line 4's
signature — this is what makes the trusted comment tamper-evident despite being human-readable
text, unlike line 1.

**Line 4, base64-decoded, is exactly 64 bytes**: an Ed25519 signature, using the same key as line
2, over the concatenation `line2_signature_bytes (64) || trusted_comment_raw_bytes` — the 64
signature bytes from line 2 (not the algorithm/key-id prefix, not the base64 text, the raw decoded
64 bytes), directly followed by the trusted comment's raw bytes as defined above, with no
separator between the two.

## This project's trusted-comment grammar (this document's own decision)

The trusted comment's raw bytes (line 3, after the `"trusted comment: "` prefix) are, exactly,
ASCII, one line, no leading or trailing whitespace, in this fixed order:

```
format=1;id=<id>;version=<version>;sha256=<sha256>
```

- `format=1` — literal, fixed. A future change to this grammar bumps this integer and is
  documented as an amendment to this file, exactly as `validation-report.schema.json`'s own
  `schema_version` is bumped when its shape changes — a verifier reading `format=1` applies the
  rules in this section; an unrecognised `format` value must be treated as "trusted comment
  unparsable" (see rejections below), never guessed at.
- `id=<id>` — the mod's `id` field (`contracts/entry.schema.json`), verbatim, including its own
  internal `:` separator (e.g. `id=mc:hello-world`) — no substitution here, unlike
  `contracts/artifact-naming.md`'s handling of the same string for filenames; a trusted comment is
  plain text, not a git ref or filesystem path, so `:` is not awkward here.
- `version=<version>` — the version string (`entry.schema.json`), verbatim, exactly as it appears
  in `versions[i].version` (semver, including any `-prerelease`/`+build` suffix).
- `sha256=<sha256>` — the same lowercase 64-character hex string as `versions[i].source_sha256`.

Fields appear in exactly this order, joined by a single `;` with no surrounding whitespace, `=`
between each key and its value with no surrounding whitespace, and nothing else on the line. A
signer's own output that does not match this grammar exactly is a bug in the signer, not a
variant a verifier should try to accommodate.

**Fabricated example (no real signature, no real key — every byte below is placeholder data):**

```
untrusted comment: signature from minisign secret key
RWRlxAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
trusted comment: format=1;id=mc:hello-world;version=1.0.0;sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
RWQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
```

(Neither base64 line above decodes to a real signature of anything; both are illustrative
filler of the correct approximate shape and length only.)

## What `entry.json`'s `signature` field holds

`entry.schema.json` defines `signature` as "a non-empty string" and leaves the exact encoding to
this document. **The field holds the complete four-line minisign signature file described above,
verbatim, as a single string** (embedded newlines preserved) — not merely line 2's core signature
in isolation. Storing only the core signature would discard the trusted comment and its own
signature (line 4) entirely, which would make Q3=A's decision — that the trusted comment carries
`id`, `version` and `sha256` — unverifiable, since there would be nothing left in the stored field
to read that comment back from. The whole point of carrying identity information in the trusted
comment (see "Attack attempt" below) requires the full four lines to survive into `entry.json`.

## Deriving `key_id`

A minisign public key file's first line is `"untrusted comment: minisign public key "` followed by
the key id rendered as **16 uppercase hexadecimal characters** (the 8 key-id bytes embedded in the
public key blob, in the same byte order they appear there) — e.g.
`untrusted comment: minisign public key AAAAAAAAAAAAAAAA` (16 `A`s shown here only as a
placeholder shape, not a real id). `entry.json`'s `key_id` field (`entry.schema.json`) holds
exactly this 16-character uppercase hex string, copied from the public key's own comment line —
never derived independently, re-encoded, or lower-cased. A verifier holds one or more trusted
public keys (ADR-0041: "the format carries `key_id` for rotation" — more than one key can be valid
at once during a rotation window), indexed by this same 16-character string, and selects which
public key to attempt verification with by looking up `key_id` — never by trying every trusted key
in turn and accepting the first success, which would make it impossible to say which key actually
signed a given artefact.

## What a verifier must reject

Every one of the following is a rejection — the artefact is treated as unverified, exactly as if
no signature were present at all, never accepted with a warning:

1. `signature` does not parse into exactly four lines matching the shapes above (missing a line,
   an extra line, a line not starting with the expected literal prefix where one is required).
2. Either base64 payload (line 2 or line 4) fails to decode, or decodes to a length other than 74
   bytes (line 2) or 64 bytes (line 4).
3. Line 2's algorithm bytes are anything other than `"Ed"` or `"ED"`.
4. The core Ed25519 signature (line 2, bytes 10–73) does not verify against the downloaded
   archive's raw bytes (or their BLAKE2b-512 prehash, per the algorithm byte) under the public key
   named by `key_id`.
5. The global signature (line 4) does not verify against `line2_signature_bytes ||
   trusted_comment_raw_bytes` under the same public key.
6. `key_id` (the `entry.json` field) does not match the 8-byte key id embedded in line 2's own
   signature blob, byte for byte (rendered as the same 16-character uppercase hex) — the two are
   supposed to always agree; a mismatch means the entry was edited independently of the signature
   it claims to belong to.
7. `key_id` does not name any public key the verifier currently trusts.
8. The trusted comment does not match this document's grammar exactly (wrong `format` value,
   missing field, fields out of the fixed order, or any extra content) — even if lines 2 and 4
   both verify cryptographically. A signer that ever emits a non-conforming trusted comment has a
   bug; a verifier accommodating it anyway would be silently relaxing this document's grammar the
   first time it was violated, exactly the kind of undocumented leniency ADR-0103 warns against.
9. The trusted comment's `sha256` does not equal the SHA-256 the verifier computes itself, fresh,
   over the downloaded archive's bytes. **A verifier must always recompute this hash from the
   bytes it actually received and must never substitute `entry.json`'s own `source_sha256` field
   for this step** — the entire point of hashing independently is to catch a downloaded file that
   does not match what either the entry or the trusted comment claims.
10. `entry.json`'s own `source_sha256` does not equal the trusted comment's `sha256` — a second,
    independent cross-check binding the registry's own claim to the signed claim, catching
    tampering with `entry.json` itself (which append-only.rules.md guards structurally, but a
    belt-and-braces check here costs nothing and guards a different failure path — a bug or bypass
    in that checker, not a re-derivation of it).
11. **The trusted comment's `id` and `version` do not exactly match the `id` and `version` of the
    specific version object in `entry.json` the verifier is currently processing** — see "Attack
    attempt" below for why this check exists and what it prevents; it is not redundant with 9/10
    above, which only bind the hash, not the identity.

## Attack attempt against this contract, recorded per acceptance criterion 3

**Attempt: signature reuse across identities.** Take one mod's genuinely, correctly signed
archive — every field of `versions[0]` for `mc:hello-world` version `1.0.0` is authentic: the
tarball is real, `source_sha256` is its real hash, `signature` verifies against it under a trusted
`key_id`. Now publish a **different** entry, `evil:not-hello-world` version `1.0.0`, whose
`source_archive`, `source_sha256`, `signature` and `key_id` fields are copied byte-for-byte from
the genuine `mc:hello-world` entry above (the underlying file is never re-uploaded — both entries'
`source_archive` URLs could even point at the identical stored object). **Under a verifier that
only checks "does this signature verify against this file's bytes and hash" — rules 1–10 above,
stopping short of 11 — this passes completely**: the file exists, the hash matches, the core
signature verifies, the global signature verifies, `key_id` is trusted. Every check up to the last
one is satisfied by construction, because nothing about the bytes, the hash, or the raw
cryptographic signature was altered at all — this is the same failure shape as "identify by magic
bytes" and "a well-formed instance of a whitelisted format" from this task's own brief: a check
that is individually correct but insufficient to establish the property actually needed, here
"this signature attests to *this* mod's *this* version," not merely "this signature attests to
*some* file the platform once signed." **What the contract does about it:** rule 11 exists
specifically to close this — the trusted comment's `id=mc:hello-world;version=1.0.0` does not
match `evil:not-hello-world`/`1.0.0`'s own identity, and a verifier applying rule 11 rejects the
copied entry outright, even though every byte of the signature itself is completely genuine. This
is exactly why Q3=A's decision to carry `id` and `version` inside the *signed* comment (rather
than leaving identity binding to `entry.json`'s own unsigned structure alone) matters: without it,
nothing in the cryptography would have stopped this attempt, because a raw file signature has no
concept of "which registry entry this belongs to" on its own.

## What this document does not cover

- **Key generation, storage, or rotation procedure** — mission §4 D5's key-management note and
  ADR-0041's "key in build secrets ... written rotation procedure"; this document only fixes the
  format of what gets produced and how a verifier reads it, never how the private key is
  generated, stored, or who may use it.
- **The archive's own interior** (`README.md`, screenshot paths, the path-escape rule) —
  `contracts/archive-layout.md` (E11). This document's "what is signed" stops at "the tarball's
  raw bytes"; what those bytes unpack to is a different contract's job, and by design a verifier
  completes this document's checks *before* ever opening the archive E11 describes.
- **Which specific tool or library performs signing** — any minisign-compatible implementation
  producing the exact byte layout above satisfies this contract; ADR-0103 favours using the
  reference `minisign` binary directly over reimplementing it, but nothing here mandates it by
  name.

## Questions

- (none — Q3=A already fixed the algorithm, detached-signature choice, and that the trusted
  comment carries id/version/sha256; this document's remaining job, the exact byte layout, is
  fully settled above.)
