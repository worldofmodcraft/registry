"""Ownership checker for registry PRs (task 007b, edge E16): contracts/ownership.md, rules R1-R12 and the
checker-constraining invariants I1-I9 (R12 and I9: the pipeline write-back, task 118, implemented by task 120).
Offline and pure: no network, no environment, no file reads. Everything arrives as an argument (the seam task 039
fills in).

    check(author, files, reserved_base, membership_oracle, *, login=None, r11_identity=None,
          pipeline_identity=None, base_entries=None, namespace_owners=None) -> verdict (report.make shape,
          checker "ownership")

author            (provider, id): the PR author as read from pulls.user.id (I1). Never read from anywhere else.
login             pulls.user.login. Used for messages and for the FIRST-PUBLISH rules R4/R6 only (they are defined
                  on the username); never compared for authorising an existing namespace (R3/R7, I6).
files             {path: (old, new)} for every touched path: parsed JSON at the merge-base / in the PR, None =
                  absent. A path that is not mods/<ns>.<name>/entry.json|page.json is rejected (R1), never skipped.
reserved_base     the parsed reserved-namespaces.json AS AT THE MERGE-BASE (I4). Whatever the PR does to that file
                  (it may appear in `files`) changes neither this list nor R11's authority.
membership_oracle (org, author) -> int, the HTTP status of the membership question: 204 member, 404 not a member,
                  anything else (302, 500, an exception) is R9's closed rejection (I5: a 302 is never followed).
r11_identity      (provider, id) that R11 authorises for takedowns. Configuration, never data from the PR. None
                  (the default) means R11 authorises nobody: every takedown PR is then rejected by R11 (and R3/R7).
pipeline_identity (provider, id) that R12 authorises to write a build result back (one T1 or one T3). Configuration
                  (config/pipeline-identity.json at the merge-base), never data from the PR. None (the default) means
                  R12 authorises nobody: every PR containing a T1 or T3 mutation is rejected by R12. When it equals
                  r11_identity the check raises ToolError, with no verdict (I9).
namespace_owners  {namespace: (provider, id)} read from EVERY mods/*/entry.json at the merge-base (never from the
                  PR's files). A namespace is first published by a PR only if absent from this mapping and from the
                  reserved list; a new entry.json in a namespace present here is judged by R3 on the recorded owner's
                  id (ownership.md Attack 4), never by R4/R6's login. None = not supplied: every PR adding a new
                  entry.json is rejected (fail closed). An empty mapping is legitimate (empty registry).
base_entries      {mods/<ns>.<name>/entry.json: parsed entry at the merge-base} for the siblings of touched
                  page.json files that are not themselves in `files`; a missing key means "no entry" (R10).

I8: an "accepted" verdict is NEVER a merge signal (MANAGER.md section 7); the verdict says so (merge_signal False).
"""

import append_only
import classify
import report

T1_T3_TARGETS = ("published", "rejected")  # what a pending element may become (T1, T3), or be born as: R12 territory
FAIL_CLOSED_CITE = "ADR-0121 / append-only.rules.md 'Coexistence of T1, T2 and T3'"
R12_CITE = "ownership.md R12, ADR-0121"


def _pair(value, what):
    if not (isinstance(value, (tuple, list)) and len(value) == 2 and isinstance(value[0], str)
            and isinstance(value[1], int) and not isinstance(value[1], bool)):
        raise report.ToolError(f"{what} must be a (provider, numeric id) pair, got {value!r}")
    return (value[0], value[1])


def _d(x):
    return x if isinstance(x, dict) else {}


def _owner_pair(entry):
    """(provider, id) of an entry's owner, or None when it is not a well-formed pair (None never equals an author)."""
    o = _d(_d(entry).get("owner"))
    p, i = o.get("provider"), o.get("id")
    return (p, i) if isinstance(p, str) and isinstance(i, int) and not isinstance(i, bool) else None


def _versions(x):
    v = _d(x).get("versions")
    return v if isinstance(v, list) else []


def _status(e):
    return _d(e).get("status")


def _t1t3_hits(files):
    """R12's broad detection, on the RAW statuses and never on 007a's classification: {path: [(index, born)]} for
    every entry.json element that goes pending -> published or pending -> rejected, or is newly added (including
    every element of a new file) already published or rejected. born=True marks the newly added ones."""
    hits = {}
    for path in sorted(files):
        p = classify.parse_mod_path(path)
        if p is None or p[2] != "entry":
            continue
        old, new = files[path]
        ov = _versions(old)
        for i, n in enumerate(_versions(new)):
            if _status(n) in T1_T3_TARGETS and (i >= len(ov) or _status(ov[i]) == "pending"):
                hits.setdefault(path, []).append((i, i >= len(ov)))
    return hits


def _writeback(author, pipeline, files, hits):
    """R12: None when the PR contains no T1/T3 mutation (R12 says nothing); "" when R12 authorises it; otherwise
    the reason it does not."""
    if not hits:
        return None
    if pipeline is None:
        return "R12 is not configured (config/pipeline-identity.json is absent or null), so it authorises nobody"
    if author != pipeline:
        return f"its author {author[0]} id {author[1]} is not the pipeline identity"
    if len(files) != 1 or len(hits) != 1 or sum(len(v) for v in hits.values()) != 1:
        return ("it is not exactly one T1 or T3 element in exactly one entry.json with no other path touched "
                f"({len(files)} path(s), {sum(len(v) for v in hits.values())} T1/T3 element(s))")
    (path, [(i, born)]), = hits.items()
    if born:
        return f"element {i} is born already published or rejected, which is not a T1 or T3 (it needs an existing pending element)"
    old, new = files[path]
    try:
        v = append_only.check_entry(old, new, path)
    except report.ToolError as exc:
        return f"the entry could not be evaluated ({exc})"
    kind = v["elements"][i]["classification"] if i < len(v["elements"]) else None
    if v["findings"] or kind not in ("T1", "T3"):
        return f"append-only.rules.md does not classify element {i} as a legal T1 or T3 ({len(v['findings'])} finding(s))"
    only = dict(old, versions=[new["versions"][j] if j == i else x for j, x in enumerate(old["versions"])])
    if not append_only._same(only, new):
        return f"the new entry.json differs from the old one by more than element {i}'s transition"
    return ""


def _fail_closed(files, hits, why):
    """ADR-0121, evaluated FIRST on the raw old/new pair (never on 007a's classification). A T1/T3 mutation (hits) is
    R12's: rejected by R12 with `why` unless R12 authorised it (why == ""). Any other change to an existing element
    keeps the fail-closed tag: at index i < len(old) the new element is missing, or differs and (old is pending, or
    new is published/rejected, which a pending old element would have made a hit)."""
    out = []
    for path in sorted(files):
        if why and path in hits:
            els = ", ".join(str(i) for i, _ in hits[path])
            out.append(report.finding(
                ["R12"], f"{path}: this PR contains a T1 or T3 mutation (element {els} goes or is born pending -> "
                f"published/rejected) and R12 does not authorise it, whoever opened it: {why}. Only the pipeline "
                "identity may write a build result back, as exactly one T1 or one T3 in one entry.json and nothing else",
                "remove the change to the pending/published/rejected elements; the build pipeline writes those",
                R12_CITE, path=path, index=hits[path][0][0]))
        p = classify.parse_mod_path(path)
        if p is None or p[2] != "entry":
            continue
        old, new = files[path]
        nv = _versions(new)
        skip = {i for i, born in hits.get(path, []) if not born}
        for i, o in enumerate(_versions(old)):
            if i in skip:
                continue
            if i >= len(nv):
                why_fc = f"element {i} is missing from the new file (versions[] truncated, append-only rule 3)"
            elif not append_only._same(o, nv[i]) and (_status(o) == "pending" or _status(nv[i]) in ("published", "rejected")):
                key = (_status(o), _status(nv[i]))
                why_fc = (f"element {i} changes {key[0]} -> {key[1]}, which is not permitted at all (append-only rule 1), "
                          "and is in any case a pipeline-only status")
            else:
                continue
            out.append(report.finding(
                ["fail-closed"], f"{path}: {why_fc}. ADR-0121 rejects every change to an existing pending, published "
                "or removed element that is not a T1, T2 or T3, whoever its author is", "remove the change to existing "
                "elements", FAIL_CLOSED_CITE, path=path, index=i))
    return out


def _takedown_shape(files):
    """True iff the diff is nothing but takedown mutations: every changed path an existing entry.json, every changed
    element a T2 per 007a, id/owner/element count unchanged, at least one T2 in every file."""
    if not files:
        return False
    for path, (old, new) in files.items():
        p = classify.parse_mod_path(path)
        if p is None or p[2] != "entry" or old is None or new is None:
            return False
        try:
            v = append_only.check_entry(old, new, path)
        except report.ToolError:
            return False
        kinds = [e["classification"] for e in v["elements"]]
        if v["findings"] or "T2" not in kinds or any(k not in ("unchanged", "T2") for k in kinds):
            return False
    return True


def _takedown_paths(files):
    """(hits, errors): the entry.json paths whose diff contains a takedown mutation, and those where 007a's check_entry
    raised so the question cannot be answered (task 075). A path with both old and new present contains one iff any
    element is a T2 per check_entry, or is a raw published -> removed status change; evaluated per element and
    independent of findings elsewhere in the file or the PR, so a malformed neighbour cannot hide a removal."""
    hits, errors = [], []
    for path in sorted(files):
        p = classify.parse_mod_path(path)
        old, new = files[path]
        if p is None or p[2] != "entry" or old is None or new is None:
            continue
        try:
            kinds = [e["classification"] for e in append_only.check_entry(old, new, path)["elements"]]
        except report.ToolError:
            errors.append(path)
            continue
        raw = any(_status(o) == "published" and _status(n) == "removed"
                  for o, n in zip(_versions(old), _versions(new)))
        if "T2" in kinds or raw:
            hits.append(path)
    return hits, errors


def _membership(ns, org, author, oracle):
    try:
        status = oracle(org, author)
    except Exception as exc:  # noqa: BLE001 - an oracle failure is R9's closed rejection, whatever it was
        return [_r9(ns, f"the membership oracle raised {type(exc).__name__}: {exc}")]
    if isinstance(status, bool) or not isinstance(status, int):
        return [_r9(ns, f"the membership oracle returned {status!r}, not an HTTP status")]
    if status == 204:
        return []
    if status == 404:
        return [report.finding(
            ["R7"], f"namespace {ns!r} is reserved (ADR-0119) and its author is not a current member of the "
            f"organisation {org!r} that owns it", f"ask a member of {org} to open the PR, or choose another "
            "namespace; ADR-0119 section 3 reserves mc and test to organisation members", "ownership.md R7, ADR-0119")]
    return [_r9(ns, f"the membership question answered HTTP {status}, neither 204 (member) nor 404 (not a member)")]


def _r9(ns, what):
    return report.finding(["R9"], f"namespace {ns!r}: {what}; membership could not be determined and the check fails "
                          "closed rather than guessing (a 302 is never followed, I5)",
                          "re-run with a caller that is an organisation member, so the direct 204/404 branch answers",
                          "ownership.md R9, I5")


def _namespace(ns, paths, ctx):
    """Every rule that applies to one namespace (I7: evaluated on its own)."""
    out, reserved = [], ns in ctx["names"]
    author, login, files = ctx["author"], ctx["login"], ctx["files"]
    who = f"{author[0]} id {author[1]}" + (f" (login {login!r})" if login else "")
    for path in paths:
        _, name, kind = classify.parse_mod_path(path)
        old, new = files[path]
        entry_path = f"mods/{ns}.{name}/entry.json"
        first = existing = None
        if kind == "entry":
            if new is not None:
                for label, src in (("new", new), ("old", old)):
                    if src is not None and _d(src).get("id") != f"{ns}:{name}":
                        out.append(report.finding(
                            ["R2"], f"{path}: the directory names namespace {ns!r} but the {label} id is "
                            f"{_d(src).get('id')!r}; the directory path is authoritative (I2)",
                            f"make id exactly {ns}:{name}", "ownership.md R2, I2", path=path))
            if old is not None:
                existing = old
            elif new is not None:
                first = new
        elif entry_path in files:
            eo, en = files[entry_path]
            if eo is None and en is None:
                existing = None
            else:
                continue  # the entry in the same PR decides; the page rides on its verdict
        else:
            existing = ctx["base_entries"].get(entry_path)
        if kind == "page" and existing is None and first is None:
            out.append(report.finding(
                ["R10"], f"{path}: no entry.json exists for {ns}.{name} at the merge-base and none is created in "
                "this PR, so there is no entry to own this page", "open the entry.json first, or add it in the "
                "same PR", "ownership.md R10", path=path))
        elif existing is not None and not reserved:
            if not ctx["authorised"] and _owner_pair(existing) != author:
                out.append(report.finding(
                    ["R3"], f"{path}: namespace {ns!r} is owned by {_owner_pair(existing)!r} but the PR author is "
                    f"{who}; ids are compared as (provider, id), never usernames", f"only the owner may touch {ns}; "
                    "fork and open the PR from the owning account", "ownership.md R3, I3, I6", path=path))
        elif first is not None and ctx["owners"] is None:
            out.append(report.finding(
                ["namespace-owners-missing"], f"{path}: a new entry.json cannot be judged because the merge-base "
                "namespace_owners input was not supplied, so the check cannot tell a first publish from a sibling "
                "entry in an owned namespace", "supply namespace_owners (every merge-base mods/*/entry.json); an empty "
                "mapping is valid for an empty registry", "ownership.md R3, Attack 4", path=path))
        elif first is not None and not reserved and ns in ctx["owners"]:
            if ctx["owners"][ns] != author:
                out.append(report.finding(
                    ["R3"], f"{path}: namespace {ns!r} already exists at the merge-base and is owned by "
                    f"{ctx['owners'][ns]!r}, but the PR author is {who}; a new entry in an owned namespace is judged by "
                    "the recorded owner's id, never by the author's username", f"only the owner may add entries to {ns}",
                    "ownership.md R3, I3, I6, Attack 4", path=path))
            if _owner_pair(first) != ctx["owners"][ns]:
                out.append(report.finding(
                    ["R5"], f"{path}: the new entry's owner is {_owner_pair(first)!r} but namespace {ns!r} is bound "
                    f"to {ctx['owners'][ns]!r}; a namespace is never reassigned and owner is frozen at first write",
                    "set owner.provider and owner.id to the namespace's recorded owner", "ownership.md R5, I6, Attack 4",
                    path=path))
        elif first is not None and reserved:
            rec = ctx["reserved"]["namespaces"][ns].get("owner")
            if not append_only._same(_d(first).get("owner"), rec):
                out.append(report.finding(
                    ["R8"], f"{path}: first publish of reserved namespace {ns!r} must carry the owner the merge-base "
                    f"reserved list records ({rec!r}), not {_d(first).get('owner')!r}", "set owner to the recorded "
                    "organisation owner (ADR-0119)", "ownership.md R8, ADR-0119", path=path))
        elif first is not None:
            own = _d(_d(first).get("owner"))
            if login is None or ns.lower() != login.lower():
                out.append(report.finding(
                    ["R4"], f"{path}: a first publish binds the namespace to the author's username (ADR-0039); "
                    f"namespace {ns!r} vs author {who}", "publish under your own username's namespace "
                    "(compared case-insensitively)" + ("" if login else "; the login was not supplied, so the check "
                                                       "fails closed"), "ownership.md R4, ADR-0039", path=path))
            if _owner_pair(first) != author:
                out.append(report.finding(
                    ["R5"], f"{path}: the proposed owner is {_owner_pair(first)!r} but the PR author is {who}",
                    "set owner.provider and owner.id to your own", "ownership.md R5, I6", path=path))
            if login is None or str(own.get("name_at_registration")).lower() != login.lower():
                out.append(report.finding(
                    ["R6"], f"{path}: name_at_registration {own.get('name_at_registration')!r} is not the author's "
                    f"username {login!r}", "record your own username (case-insensitive)", "ownership.md R6", path=path))
    if reserved and not ctx["authorised"]:
        org = ctx["reserved"]["namespaces"][ns].get("owner", {}).get("name_at_registration")
        if not isinstance(org, str):
            raise report.ToolError(f"the reserved list records no organisation name for {ns!r}")
        out += _membership(ns, org, author, ctx["oracle"])
    return out


def separate_identities(r11, pipeline):
    """I9: when both identities are configured and equal there is no verdict (ToolError, exit 2), for every PR."""
    if r11 is not None and pipeline is not None and r11 == pipeline:
        raise report.ToolError(
            f"I9: config/pipeline-identity.json and config/r11-identity.json hold the same identity {pipeline!r}; one "
            "account may not hold both the takedown power of R11 and the write-back power of R12, so the check "
            "cannot decide (ownership.md I9)")


def check(author, files, reserved_base, membership_oracle, *, login=None, r11_identity=None, pipeline_identity=None,
          base_entries=None, namespace_owners=None):
    author = _pair(author, "author")
    r11 = None if r11_identity is None else _pair(r11_identity, "r11_identity")
    pipeline = None if pipeline_identity is None else _pair(pipeline_identity, "pipeline_identity")
    separate_identities(r11, pipeline)
    names = classify.reserved_names(reserved_base)
    owners = None if namespace_owners is None else {k: _pair(v, f"namespace_owners[{k!r}]")
                                                    for k, v in namespace_owners.items()}
    hits = _t1t3_hits(files)
    why = _writeback(author, pipeline, files, hits)
    pipeline_ok = why == ""
    findings = _fail_closed(files, hits, why) + classify.classify(sorted(files), reserved_base)["findings"]
    shape = _takedown_shape(files)
    authorised = r11 is not None and author == r11 and shape
    if shape and not authorised:
        findings.append(report.finding(
            ["R11"], f"this PR is nothing but takedown mutations, but its author {author[0]} id {author[1]} is not the "
            "platform's own identity" + (" (R11 is not configured, so it authorises nobody)" if r11 is None else ""),
            "only the platform's own account may open a takedown (Ludwig, 2026-09-07); ordinary R3/R7 apply",
            "ownership.md R11"))
    hits, unreadable = _takedown_paths(files)
    mixed = bool(hits or unreadable) and not shape
    if mixed and hits:
        findings.append(report.finding(
            ["R11"], f"this PR contains a takedown mutation (a version's status becoming 'removed': {', '.join(hits)}) "
            "together with other changes; whoever its author is, a PR is a takedown only if it is nothing but takedown "
            "mutations opened by the platform's own identity",
            "split the PR: removals alone in a platform-opened PR, every other change in its own PR (ADR-0041, "
            "Ludwig 2026-10-17)", "ownership.md R11"))
    if mixed and unreadable:
        findings.append(report.finding(
            ["R11"], f"the entry at {', '.join(unreadable)} could not be evaluated (check_entry raised), so it cannot "
            "be ruled out that this PR carries a takedown mutation; rejected fail-closed",
            "make the merge-base and the PR's entry.json well formed so the diff can be classified",
            "ownership.md R11, ADR-0121"))
    by_ns = {}
    for path in files:
        p = classify.parse_mod_path(path)
        if p is not None:
            by_ns.setdefault(p[0], []).append(path)
    ctx = {"author": author, "login": login, "files": files, "names": names, "reserved": reserved_base,
           "oracle": membership_oracle, "authorised": authorised or pipeline_ok, "base_entries": base_entries or {},
           "owners": owners}
    for ns in sorted(by_ns):
        findings += _namespace(ns, sorted(by_ns[ns]), ctx)
    return report.make("ownership", findings, authorised_takedown=authorised,
                       authorised_writeback=pipeline_ok, namespaces=sorted(by_ns), merge_signal=False)
