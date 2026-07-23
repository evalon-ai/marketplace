---
name: pin-agent-hook
description: >-
  Pin @evalon-ai/agent-hook across marketplace hooks.json files and bump plugin
  build versions. Use when the user runs /pin-agent-hook or asks to bump/pin the
  agent-hook package version in this marketplace repo.
disable-model-invocation: true
---

# /pin-agent-hook

Bump pinned `@evalon-ai/agent-hook@X.Y.Z` in all runner `hooks.json` files, bump plugin build `version` in each `plugin.json`, sync README examples. **Never edit until user confirms.**

## Files

| Role | Paths |
| --- | --- |
| Package pin | `plugins/claude-runtime-hooks/hooks/hooks.json` |
| | `plugins/cursor-runtime-hooks/hooks/hooks.json` |
| | `plugins/codex-runtime-hooks/hooks/hooks.json` |
| Build version | `plugins/claude-runtime-hooks/.claude-plugin/plugin.json` |
| | `plugins/cursor-runtime-hooks/.cursor-plugin/plugin.json` |
| | `plugins/codex-runtime-hooks/.codex-plugin/plugin.json` |
| Docs | `README.md` (`@evalon-ai/agent-hook@…` examples) |

Never pin `@latest`. Exact semver only.

## Workflow

Copy checklist; track progress:

```
Pin progress:
- [ ] 1. Resolve versions
- [ ] 2. Show plan + wait for confirm
- [ ] 3. Apply (only after confirm)
- [ ] 4. Verify
```

### 1. Resolve versions

Args from user message (examples):

- `/pin-agent-hook 1.0.3` → package `1.0.3`, plugin patch bump
- `/pin-agent-hook 1.0.3 --plugin 1.1.0` → package `1.0.3`, plugin `1.1.0`
- `/pin-agent-hook` with no version → ask for package version first

Discover current state:

```bash
rg -o '@evalon-ai/agent-hook@[0-9]+\.[0-9]+\.[0-9]+' plugins README.md | sort -u
rg '"version":' plugins/*/.*/plugin.json
```

Defaults:

- **Package version**: required from user (semver `X.Y.Z`)
- **Plugin build version**: if omitted, patch-bump current plugin `version` (all three stay equal). If plugins already disagree, stop and ask which build version to set.

Reject if new package version equals current pin (unless user forces with `--force`).

### 2. Confirm (hard gate)

**STOP. Do not write files yet.**

Show plan:

```text
Pin @evalon-ai/agent-hook
  package:  <old> → <new>
  plugin:   <old> → <new>  (claude / cursor / codex)
  README:   update example pins to <new>
```

Ask for confirmation. Prefer `AskQuestion` single-select:

- `Proceed`
- `Cancel`

If `AskQuestion` unavailable, ask in chat and wait. Only `Proceed` / clear yes continues. `Cancel` / no / silence → stop, no edits.

### 3. Apply

Only after confirm, run:

```bash
node .cursor/skills/pin-agent-hook/scripts/pin.mjs <packageVersion> <pluginVersion>
```

Or equivalent search-replace: every `@evalon-ai/agent-hook@OLD` → `@evalon-ai/agent-hook@NEW` in the three `hooks.json` + `README.md`; set `"version": "NEW_PLUGIN"` in all three `plugin.json`.

Do not commit unless user asks.

### 4. Verify

```bash
rg -o '@evalon-ai/agent-hook@[0-9]+\.[0-9]+\.[0-9]+' plugins README.md | sort -u
rg '"version":' plugins/*/.*/plugin.json
```

Expect one package pin (`NEW`) and one plugin version (`NEW_PLUGIN`) across all three plugins. Summarize changed files; stop.
