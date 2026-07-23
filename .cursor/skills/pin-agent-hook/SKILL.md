---
name: pin-agent-hook
description: >-
  Pin @evalon-ai/agent-hook across marketplace hooks.json files and set each
  plugin.json version to the same semver. Use when the user runs /pin-agent-hook
  or asks to bump/pin the agent-hook package version in this marketplace repo.
disable-model-invocation: true
---

# /pin-agent-hook

Set pinned `@evalon-ai/agent-hook@X.Y.Z` in all runner `hooks.json` files, set each plugin `version` to **the same** `X.Y.Z`, sync README examples. **Never edit until user confirms.**

## Rule

Plugin build version **always equals** npm package version. One semver. No separate `--plugin` flag.

## Files

| Role | Paths |
| --- | --- |
| Package pin | `plugins/claude-runtime-hooks/hooks/hooks.json` |
| | `plugins/cursor-runtime-hooks/hooks/hooks.json` |
| | `plugins/codex-runtime-hooks/hooks/hooks.json` |
| Build version (= package) | `plugins/claude-runtime-hooks/.claude-plugin/plugin.json` |
| | `plugins/cursor-runtime-hooks/.cursor-plugin/plugin.json` |
| | `plugins/codex-runtime-hooks/.codex-plugin/plugin.json` |
| Docs | `README.md` (`@evalon-ai/agent-hook@…` examples) |

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
rg -o '@evalon-ai/agent-hook@[0-9]+\.[0-9]+\.[0-9]+' plugins README.md | sort -u
rg '"version":' plugins/*/.*/plugin.json
```

Reject if new version equals current package pin (unless user forces with `--force`).

### 2. Confirm (hard gate)

**STOP. Do not write files yet.**

Show plan:

```text
Pin @evalon-ai/agent-hook + plugin build (same version)
  package + plugins:  <old> → <new>
  README:             update example pins to <new>
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

Or equivalent: every `@evalon-ai/agent-hook@OLD` → `@evalon-ai/agent-hook@NEW` in the three `hooks.json` + `README.md`; set `"version": "NEW"` in all three `plugin.json`.

Do not commit unless user asks.

### 4. Verify

```bash
rg -o '@evalon-ai/agent-hook@[0-9]+\.[0-9]+\.[0-9]+' plugins README.md | sort -u
rg '"version":' plugins/*/.*/plugin.json
```

Expect one version (`NEW`) for package pin and all three `plugin.json`. Summarize changed files; stop.
