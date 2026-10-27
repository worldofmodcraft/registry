# World of Modcraft — mod registry

This repository is the **truth about mods** for [World of Modcraft](https://worldofmodcraft.com):
which mods exist, which versions were published, where the archived source of each version lives,
and the hash and signature that prove the archive is what was published.

It is data, not code you install. The platform's kernel and launcher read it; the site renders it.

- One directory per mod: `mods/<namespace>.<name>/`, holding the registry entry and its page content.
- Versions are **append-only**: they may be added, never modified or deleted (ADR-0041).
- Namespace ownership is bound to a **numeric account id**, never a username string (ADR-0058 §2).
- Publishing happens by pull request, validated automatically before merge.

**Status: under construction.** The schemas and the CI gate are built; the publishing pipeline is not live yet, so this
repository is not yet accepting submissions. [`CONTRIBUTING.md`](CONTRIBUTING.md) documents the manual pull-request publish
flow, including the permanent namespace notice. Every pull request gets one required check, `gate`, computed from the base
branch only; green means "the checks pass", never "approved".

The decisions behind all of the above are recorded in the project's decision log; the architecture
is summarised at worldofmodcraft.com once the site is live.
