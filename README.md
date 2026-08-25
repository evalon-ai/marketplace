# ev-ai hooks marketplace

Claude Code / Cursor / Codex plugin marketplace for Layer-3 runtime telemetry.

Plugins fire pinned `npx -y @ev-ai/agent-hook@… --runner …` on hook events. Customer repos enable a plugin and commit a shared `collector_url` manifest — not per-event blocks in runner settings.

> Hook package publishes to **GitHub Packages** as **`@ev-ai/agent-hook`**. Consumer machines need `@ev-ai:registry=https://npm.pkg.github.com` plus a `read:packages` token in `.npmrc`.

## Layout

```text
.
├── .claude-plugin/marketplace.json   # Claude Code marketplace catalog
├── .cursor-plugin/marketplace.json   # Cursor marketplace catalog
└── plugins/
    ├── claude-runtime-hooks/         # Claude Code
    ├── cursor-runtime-hooks/         # Cursor
    └── codex-runtime-hooks/          # OpenAI Codex
```

## Plugins

| Plugin | Runner |
| --- | --- |
| `claude-runtime-hooks` | Claude Code |
| `cursor-runtime-hooks` | Cursor |
| `codex-runtime-hooks` | OpenAI Codex |

Commands pin an exact package version (never `@latest`).

## Install

Replace `<owner>/<repo>` with this GitHub repo (e.g. `ev-ai/marketplace`).

### Claude Code

```bash
# Add marketplace
claude plugin marketplace add <owner>/<repo>

# Enable plugin (also commit both keys below for collaborators)
```

Project `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "ev-ai-agent-hooks": {
      "source": {
        "source": "github",
        "repo": "<owner>/<repo>"
      }
    }
  },
  "enabledPlugins": {
    "claude-runtime-hooks@ev-ai-agent-hooks": true
  }
}
```

Configure collector URL:

```bash
npx -y @ev-ai/agent-hook@1.0.9 configure \
  --url "https://<collector-host>/<orgToken>/hook"
```

Commit the collector manifest (`collector_url`).

`enabledPlugins` without `extraKnownMarketplaces` only works on a machine that already ran `claude plugin marketplace add` — other clones will not know `ev-ai-agent-hooks`.

### Cursor

Import this repo as a team/user marketplace (or submit via [cursor.com/marketplace/publish](https://cursor.com/marketplace/publish)), then enable `cursor-runtime-hooks`.

Configure the same collector manifest as Claude (`configure` above).

### Codex

Enable `codex-runtime-hooks` from this marketplace. Trust hooks via `/hooks` (or managed hooks for fleet).

Restart runners; confirm events in the collector.

## Do not double-wire

If the repo already used file-wiring install, migrate first:

```bash
npx -y @ev-ai/agent-hook@1.0.9 migrate-to-plugin
```

Do **not** also keep per-event blocks in runner settings — that double-POSTs.
