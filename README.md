# Evalon hooks marketplace

Claude Code / Cursor / Codex plugin marketplace for Evalon Layer-3 runtime telemetry.

Plugins fire pinned `npx @evalon-ai/agent-hook@… --runner …`. Customer repos enable a plugin and commit a shared `collector_url` manifest — not per-event blocks in runner settings.

> Hook package publishes to **GitHub Packages** as **`@evalon-ai/agent-hook`**. Consumer machines need `@evalon-ai:registry=https://npm.pkg.github.com` plus a `read:packages` token in `.npmrc`.

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

Replace `<owner>/<repo>` with this GitHub repo (e.g. `evalon-ai/marketplace`).

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
    "evalon-hooks": {
      "source": {
        "source": "github",
        "repo": "<owner>/<repo>"
      }
    }
  },
  "enabledPlugins": {
    "claude-runtime-hooks@evalon-hooks": true
  }
}
```

Configure collector URL:

```bash
npx -y @evalon-ai/agent-hook@1.0.2 configure \
  --url "https://hooks.evalon.ai/<orgToken>/hook"
```

Commit `.claude/evalon-runtime-report.json` (`collector_url`).

`enabledPlugins` without `extraKnownMarketplaces` only works on a machine that already ran `claude plugin marketplace add` — other clones will not know `evalon-hooks`.

### Cursor

Import this repo as a team/user marketplace (or submit via [cursor.com/marketplace/publish](https://cursor.com/marketplace/publish)), then enable `cursor-runtime-hooks`.

Configure the same collector manifest as Claude (`configure` above).

### Codex

Enable `codex-runtime-hooks` from this marketplace. Trust hooks via `/hooks` (or managed hooks for fleet).

Restart runners; confirm events in the collector.

## Do not double-wire

If the repo already used file-wiring install, migrate first:

```bash
npx -y @evalon-ai/agent-hook@1.0.2 migrate-to-plugin
```

Do **not** also keep Evalon per-event blocks in runner settings — that double-POSTs.
