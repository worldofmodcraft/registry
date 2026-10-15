// Task 057 criterion 4: run the entry corpus through Ajv 2020 with strict:true (the same options as the
// site repo's src/lib/validate.mjs) and print one JSON verdict per case.
// Usage: node docs/tasks/057-ajv-check.mjs <path-to-node_modules> < corpus.json > verdicts.json
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import path from "node:path";

const nm = path.resolve(process.argv[2]);
const require = createRequire(path.join(nm, "noop.js"));
const Ajv2020 = require("ajv/dist/2020.js");
const schema = JSON.parse(readFileSync(new URL("../../contracts/entry.schema.json", import.meta.url), "utf8"));
const ajv = new Ajv2020({ allErrors: true, strict: true });
const validate = ajv.compile(schema); // throws on any strict-mode violation: that is a failure, not a skip
const corpus = JSON.parse(readFileSync(0, "utf8"));
const out = corpus.map((c) => ({ name: c.name, ajv: validate(c.instance) ? "valid" : "invalid" }));
console.log(JSON.stringify({ ajv_version: require("ajv/package.json").version, verdicts: out }));
