---
name: pin-agent-hook
description: >-
  Pin @ev-ai/agent-hook across marketplace hooks.json files and set each
  plugin.json version to the same semver. Use when the user runs /pin-agent-hook
  or asks to bump/pin the agent-hook package version in this marketplace repo.
disable-model-invocation: true
---

# /pin-agent-hook

Set pinned `npx -y @ev-ai/agent-hook@X.Y.Z --runner <runner>` on every hook event in all runner `hooks.json` files, set each plugin `version` to **the same** `X.Y.Z`, sync README examples. Owner is **ev-ai**. **Never edit until user confirms.**

## Rule

Plugin build version **always equals** npm package version. One semver. No separate `--plugin` flag.

Scope, package owner, and marketplace `owner.name` are **ev-ai**. Package is **`@ev-ai/agent-hook`**. Use that name only.

## Hook commands

Every event is an `npx` command (never a local binary, bunx, or `@latest`):

```text
npx -y @ev-ai/agent-hook@X.Y.Z --runner <claude|cursor|codex>
```

Keep the existing event lists and runner-specific `hooks.json` shape. Only the pinned version changes.

## Files

| Role | Paths |
| --- | --- |
| Event pins (`npx -y @ev-ai/agent-hook@…`) | `plugins/claude-runtime-hooks/hooks/hooks.json` |
| | `plugins/cursor-runtime-hooks/hooks/hooks.json` |
| | `plugins/codex-runtime-hooks/hooks/hooks.json` |
| Build version (= package) | `plugins/claude-runtime-hooks/.claude-plugin/plugin.json` |
| | `plugins/cursor-runtime-hooks/.cursor-plugin/plugin.json` |
| | `plugins/codex-runtime-hooks/.codex-plugin/plugin.json` |
| Docs | `README.md` (`npx -y @ev-ai/agent-hook@…` examples) |

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

- `/pin-agent-hook 1.0.3` → package + all plugin.json → `1.0.3`
- `/pin-agent-hook` with no version → ask for semver first

Discover current state:

```bash
rg -o '@ev-ai/agent-hook@[0-9]+\.[0-9]+\.[0-9]+' plugins README.md | sort -u
rg '"version":' plugins/*/.*/plugin.json
```

Reject if new version equals current package pin (unless user forces with `--force`).

### 2. Confirm (hard gate)

**STOP. Do not write files yet.**

Show plan:

```text
Pin @ev-ai/agent-hook + plugin build (same version)
  npx events + plugins:  <old> → <new>
  README:                update example pins to <new>
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

Or equivalent: every `@ev-ai/agent-hook@OLD` → `@ev-ai/agent-hook@NEW` in the three `hooks.json` + `README.md`; set `"version": "NEW"` in all three `plugin.json`. Leave `npx -y` and `--runner` as-is.

Do not commit unless user asks.

### 4. Verify

```bash
rg -o '@ev-ai/agent-hook@[0-9]+\.[0-9]+\.[0-9]+' plugins README.md | sort -u
rg '"version":' plugins/*/.*/plugin.json
```

Expect one version (`NEW`) for the npx pin and all three `plugin.json`. Summarize changed files; stop.
