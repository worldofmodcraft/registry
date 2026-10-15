# tools/dev -- pinned developer tooling

This directory holds the one third-party tool the registry's verify scripts need: **ajv 8.20.0**, pinned
exactly in `package.json`, with `package-lock.json` (integrity hashes) committed. It is verification tooling
only: nothing under `tools/registry/` imports or invokes it.

Install (from the repository root; needs node and network access to the public npm registry, anonymously):

    npm ci --prefix tools/dev

`docs/tasks/057-verify.sh` and `docs/tasks/062-verify.sh` find ajv in this order: the explicit
`NODE_MODULES_DIR` argument, then the `WOM_NODE_MODULES` environment variable, then
`<repository root>/tools/dev/node_modules`. A missing install is a failure that names the command above.

`tools/dev/node_modules/` is gitignored. To bump ajv, change the version in `package.json` (exact, no range)
and run `npm install --prefix tools/dev --package-lock-only`, then review the lock diff.
