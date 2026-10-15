"""Release tag, asset names and the reserved-device-name rule (contracts/artifact-naming.md, edge E7).

Also `release_asset_url`, the one pure function the upload step needs (task 008a); the
repository it points at is a value passed in (decision Q-E), never hard-coded here.
"""

from __future__ import annotations

import re

from pipeline_errors import Rejected

# artifact-naming.md, "Rejected namespaces: Windows reserved device names". Matched
# case-insensitively against the portion of the namespace before its first "." (a
# namespace cannot contain "." at all, so that is the whole namespace).
RESERVED_DEVICE_NAMES = frozenset(
    ["con", "prn", "aux", "nul"]
    + [f"com{i}" for i in range(10)]
    + [f"lpt{i}" for i in range(10)]
)

_ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*:[a-z0-9][a-z0-9_-]*$")
_OWNER_REPO_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
_TAG_ASSET_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.+-]*$")


def split_id(mod_id: str) -> tuple[str, str]:
    if not _ID_RE.match(mod_id):
        raise ValueError(f"not a valid mod id: {mod_id!r}")
    ns, nm = mod_id.split(":")
    return ns, nm


def check_namespace(ns: str) -> None:
    """Reject a Windows reserved device name BEFORE any tag or filename is built."""
    stem = ns.split(".", 1)[0].lower()
    if stem in RESERVED_DEVICE_NAMES:
        raise Rejected(
            "artifact-naming/reserved-device-name",
            f"namespace {ns!r} is a Windows reserved device name "
            "(contracts/artifact-naming.md, 'Rejected namespaces')",
            "choose a different namespace; CON PRN AUX NUL COM0-9 LPT0-9 cannot be used",
        )


def release_tag(ns: str, nm: str, version: str) -> str:
    return f"{ns}.{nm}-{version}"


def asset_names(ns: str, nm: str, version: str) -> tuple[str, str]:
    tag = release_tag(ns, nm, version)
    return f"{tag}.tar.gz", f"{tag}.tar.gz.minisig"


def release_asset_url(owner: str, repo: str, tag: str, asset: str) -> str:
    """The direct download URL of a release asset. Pure; validates its inputs so a
    slash or traversal in any part cannot produce a URL pointing somewhere else."""
    if not _OWNER_REPO_RE.match(owner) or not _OWNER_REPO_RE.match(repo):
        raise ValueError(f"invalid owner/repo: {owner!r}/{repo!r}")
    if not _TAG_ASSET_RE.match(tag) or not _TAG_ASSET_RE.match(asset):
        raise ValueError(f"invalid tag/asset: {tag!r}, {asset!r}")
    return f"https://github.com/{owner}/{repo}/releases/download/{tag}/{asset}"
