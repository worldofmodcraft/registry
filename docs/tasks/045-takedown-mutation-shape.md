# Task 045 — `append-only.rules.md` must define the takedown mutation shape precisely enough to carry `R11`

- **Status:** spec-approved
- **Repo:** registry (`worldofmodcraft/registry`)
- **Date:** 2026-09-07
- **Approved by:** Ludwig, in session, 2026-09-07
- **Effort budget:** small (≤ 1 agent-session)
- **Depends on:** task 032 merged (PR #4)
- **Blocks:** task 007 — sequence this **before** 007 builds against the ownership contract, because 007 consumes both documents.

## Objective

Make `contracts/append-only.rules.md`'s definition of **the takedown mutation shape** precise enough to
carry the weight that task 032's `R11` now places on it, and prove the precision with a fixture.

## Why — the load this definition now bears

Ludwig ruled (2026-09-07) that the platform's own organisation account may **open** a takedown PR
against a namespace it does not own, with MANAGER.md §7's written-approval gate governing the
**merge**. Task 032 fix round 4 made that ruling operative: `R11` declares
`Precedence: R11 over R3, R7`, so for the one PR `R11` authorises, the ordinary ownership rejection
does not apply.

That exception is bounded by one clause — **"nothing but the takedown mutation itself, in the shape
`append-only.rules.md` defines"**. Everything keeping the exception narrow therefore rests on how
precisely that other file defines the shape. Task 032's round 4 correctly did **not** read or change
that file's side of the boundary (it was out of scope), and booked the question instead. The result
is that `R11` leans on a definition nobody has checked against this new load.

**The risk in one sentence:** an exception is the classic attack surface — forbidden work smuggled
under a permitted label — and this one currently delegates its own boundary to a document that was
written before the exception existed.

## Scope

- `contracts/append-only.rules.md` — the takedown mutation definition, and only what that requires.
- Its verify artefact (`docs/tasks/045-verify.sh`, new) carrying the fixture below.

## Out of scope

- `contracts/ownership.md` and anything in task 032 — that document is finished; if this task finds
  that `R11`'s wording must change, **stop and report** rather than editing it.
- Implementing any checker. Any schema change.
- Re-litigating who may open or merge a takedown: both are decided (Ludwig, 2026-09-07).

## Acceptance criteria

1. `append-only.rules.md` states the takedown mutation shape as an **exhaustive** description: exactly
   which field(s) change, to which value(s), what must be added (the reason), and — stated explicitly —
   that **everything else in the entry and the PR must be unchanged**.
2. A diff that is *takedown-shaped but not exactly a takedown* is **rejected**, and this is proven by a
   committed fixture, written first and **shown red before the fix** (MANAGER.md §2c rule 5). At
   minimum: a takedown plus a whitespace change; a takedown plus a `page.json` edit; a takedown that
   also adds a version object; a takedown of a version that does not exist.
3. Positive controls sit beside the hostile fixtures: a genuine, correctly-shaped takedown is
   **accepted**. A suite that rejects everything scores perfectly and proves nothing.
4. The mutation test is shown: break what each new check claims to check, show it redden, restore
   byte-identically (§2c rule 2).
5. Any environmental claim carries its verification command or an inline caveat at the point of the
   claim (guardrail 6b); anything checkable with a tool on this machine is **run**, not caveated (6c).
6. `docs/tasks/045-verify.sh` is committed, executable, portable and deterministic — proven in a
   **fresh clone**, and its scope check is **merge-base-relative**, never pinned to a commit
   (a pinned baseline goes permanently red at merge; `docs/tasks/006-verify.sh` is red on `main` today
   for exactly that reason).

## Notes

Task 032's round 4 is the reference for the shape this work should take: the fix closes a **class**
rather than an instance, and every closure ships a regression fixture that fails if the defect returns.
