#!/usr/bin/env node
/**
 * Pin @ev-ai/agent-hook and set plugin build versions to the same semver.
 * Usage: node pin.mjs <version>
 * Does not prompt — caller must confirm before running.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../../..");
const pkgRe = /@ev-ai\/agent-hook@\d+\.\d+\.\d+/g;
const semver = /^\d+\.\d+\.\d+$/;

const [, , version] = process.argv;
if (!semver.test(version || "")) {
  console.error("Usage: node pin.mjs <version>");
  process.exit(1);
}

const pin = `@ev-ai/agent-hook@${version}`;
const files = {
  hooks: [
    "plugins/claude-runtime-hooks/hooks/hooks.json",
    "plugins/cursor-runtime-hooks/hooks/hooks.json",
    "plugins/codex-runtime-hooks/hooks/hooks.json",
    "README.md",
  ],
  plugins: [
    "plugins/claude-runtime-hooks/.claude-plugin/plugin.json",
    "plugins/cursor-runtime-hooks/.cursor-plugin/plugin.json",
    "plugins/codex-runtime-hooks/.codex-plugin/plugin.json",
  ],
};

let changed = 0;

for (const rel of files.hooks) {
  const abs = path.join(root, rel);
  const before = fs.readFileSync(abs, "utf8");
  const after = before.replace(pkgRe, pin);
  if (after === before) {
    console.error(`No package pin replaced in ${rel}`);
    process.exit(1);
  }
  fs.writeFileSync(abs, after);
  changed += 1;
  console.log(`updated ${rel}`);
}

for (const rel of files.plugins) {
  const abs = path.join(root, rel);
  const json = JSON.parse(fs.readFileSync(abs, "utf8"));
  const old = json.version;
  json.version = version;
  fs.writeFileSync(abs, `${JSON.stringify(json, null, 2)}\n`);
  changed += 1;
  console.log(`updated ${rel}: ${old} → ${version}`);
}

console.log(`done: ${pin} (= plugin version) (${changed} files)`);
