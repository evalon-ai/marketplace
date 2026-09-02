---
name: pin-agent-hook
description: >-
  Set every marketplace plugin.json version to one semver and verify the shipped
  launcher payload (hook.mjs + launcher.sh + launcher.ps1) is intact. Use when the
  user runs /pin-agent-hook or asks to bump/pin the agent-hook plugin version in
  this marketplace repo.
disable-model-invocation: true
---

# /pin-agent-hook

Set each plugin `version` to `X.Y.Z`, verify the generated launcher payload is present and that no `hooks.json` still wires `npx`, and sync README examples. Owner is **ev-ai**. **Never edit until user confirms.**

## Rule

Plugin build version **always equals** npm package version. One semver. No separate `--plugin` flag.

**Hook commands carry no version.** `hooks.json` invokes `launcher.sh` / `launcher.ps1` at a constant path inside the plugin; runtime bumps ride `hook.mjs`. Keeping the hook definition byte-stable across releases is the point of this delivery shape — Codex trusts a hash of the definition and un-trusts it on every change. Do **not** reintroduce `npx …@X.Y.Z` into any `hooks.json`.

Scope, package owner, and marketplace `owner.name` are **ev-ai**. Package is **`@ev-ai/agent-hook`**. Use that name only.

## Generated files — do not hand-edit

`hook.mjs`, `launcher.sh`, `launcher.ps1` and all three `hooks/hooks.json` come from `packages/agent-hook` in the monorepo:

```bash
yarn workspace @ev-ai/agent-hook build
yarn workspace @ev-ai/agent-hook sync:hooks -- /path/to/marketplace
```

Run that **before** this skill whenever the payload or the event maps changed. This skill verifies the result; it does not produce it.

## Files

| Role | Paths |
| --- | --- |
| Build version (= package) | `plugins/claude-runtime-hooks/.claude-plugin/plugin.json` |
| | `plugins/cursor-runtime-hooks/.cursor-plugin/plugin.json` |
| | `plugins/codex-runtime-hooks/.codex-plugin/plugin.json` |
| Verified, never written here | `plugins/*/hook.mjs`, `plugins/*/launcher.sh`, `plugins/*/launcher.ps1` |
| | `plugins/*/hooks/hooks.json` (must invoke the launcher, must not contain `npx`) |
| Docs | `README.md` (`npx -y @ev-ai/agent-hook@…` **configure / migrate** examples only) |

Never pin `@latest`. Exact semver only.

## Workflow

Copy checklist; track progress:

```
Pin progress:
- [ ] 1. Resolve version
- [ ] 2. Show plan + wait for confirm
- [ ] 3. Apply (only after confirm)
- [ ] 4. Verify
```

### 1. Resolve version

Args:

- `/pin-agent-hook 1.1.3` → all plugin.json → `1.1.3`
- `/pin-agent-hook` with no version → ask for semver first

Discover current state:

```bash
rg '"version":' plugins/*/.*/plugin.json
rg -l 'npx' plugins/*/hooks/hooks.json            # expect: no matches
ls plugins/*/hook.mjs plugins/*/launcher.sh plugins/*/launcher.ps1
```

Reject if the new version equals the current plugin version (unless the user forces with `--force`).

### 2. Confirm (hard gate)

**STOP. Do not write files yet.**

Show plan:

```text
Pin plugin build version (= @ev-ai/agent-hook package)
  plugins/*/plugin.json:  <old> → <new>
  README:                 update configure example pins to <new>
  payload:                verify hook.mjs + launcher.sh + launcher.ps1 in all three plugins
```

Ask for confirmation. Prefer `AskQuestion` single-select:

- `Proceed`
- `Cancel`

If `AskQuestion` unavailable, ask in chat and wait. Only `Proceed` / clear yes continues. `Cancel` / no / silence → stop, no edits.

### 3. Apply

Only after confirm, run:

```bash
node .cursor/skills/pin-agent-hook/scripts/pin.mjs <version>
```

It fails loudly (before writing anything) if a payload file is missing or a `hooks.json` still wires `npx`. In that case run `sync:hooks` from the monorepo and retry.

Do not commit unless the user asks.

### 4. Verify

```bash
rg '"version":' plugins/*/.*/plugin.json
rg -o '@ev-ai/agent-hook@[0-9]+\.[0-9]+\.[0-9]+' README.md | sort -u
rg -o 'launcher\.(sh|ps1)' plugins/*/hooks/hooks.json | sort -u
```

Expect one version (`NEW`) across all three `plugin.json` and the README, every `hooks.json` invoking both launchers, and no `npx` anywhere under `plugins/*/hooks/`. Summarize changed files; stop.
