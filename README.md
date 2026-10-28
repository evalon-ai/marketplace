# ev-ai hooks marketplace

Claude Code / Cursor / Codex plugin marketplace for Layer-3 runtime telemetry.

Each plugin ships its own runtime under `dist/`: the compiled `launcher.mjs` and the bundled `hook.mjs` it runs. `hooks.json` invokes `node dist/launcher.mjs` via the runner's plugin-root variable. Customer repos enable a plugin and commit a shared `collector_url` manifest — not per-event blocks in runner settings.

> **Requires Node.js (>= 18) on `PATH`.** There is no binary fallback: without `node` every hook command is a fail-open no-op.

> **A plugin hook never reaches the npm registry.** The runtime is the shipped payload, pinned by the payload `package.json` version. The launcher may adopt a newer *signed* `hook.mjs` published by the collector, but never one below the shipped version. The package still publishes publicly as **`@ev-ai/agent-hook`** for `configure` / `migrate-to-plugin` and for repos on file-wiring; consumers need no `.npmrc` and no token.

## Layout

```text
.
├── .claude-plugin/marketplace.json   # Claude Code marketplace catalog
├── .cursor-plugin/marketplace.json   # Cursor marketplace catalog
├── .agents/plugins/marketplace.json  # Codex marketplace catalog
└── plugins/
    ├── claude/                       # Claude Code
    │   ├── .claude-plugin/plugin.json   # name: ev-ai-agent-hooks
    │   ├── hooks/hooks.json          # event map — invokes node dist/launcher.mjs
    │   ├── package.json              # payload version + launcher protocol (read by the launcher)
    │   └── dist/
    │       ├── launcher.mjs          # hook entry: selects a hook and runs it
    │       ├── launcher-update.mjs   # signed hook update check, loaded on demand
    │       └── hook.mjs              # bundled runtime (zero-dependency)
    ├── cursor/                       # Cursor — same files
    └── codex/                        # OpenAI Codex — same files
```

Every file above except `plugin.json` is **generated** — never hand-edit them here. They are copied from (or stamped by) `packages/agent-hook` in the monorepo via `sync:hooks` (see [Releasing](#releasing)).

`package.json` carries the package version in the *payload* rather than in a hook command, which is what lets a bump ship a new payload without rewriting `hooks.json`. The `dist/` layout mirrors the npm package: the launcher finds its siblings and `../package.json` relative to itself.

## Plugins

All three runners install the same plugin name — `ev-ai-agent-hooks@ev-ai-marketplace`. Each runner reads its own marketplace index, and each index lists exactly one plugin, so the runner is implied by the index rather than by the name. The directory under `plugins/` names the runner because the three ship different event maps.

| Runner | Marketplace index | Plugin directory |
| --- | --- | --- |
| Claude Code | `.claude-plugin/marketplace.json` | `plugins/claude` |
| Cursor | `.cursor-plugin/marketplace.json` | `plugins/cursor` |
| OpenAI Codex | `.agents/plugins/marketplace.json` | `plugins/codex` |

## How a hook event runs

```text
runner event
  → node ${PLUGIN_ROOT}/dist/launcher.mjs --runner <runner>
  → select hook: cached signed update, else bundled dist/hook.mjs
  → node <hook> --runner <runner>
  → ack; collect + POST continue detached
```

**No package version appears in any hook command.** A runtime bump changes the payload, not `hooks.json` — so it re-prompts nobody. That matters most on Codex, which trusts a hash of the hook definition and un-trusts it on every change.

**One entry per event on Claude and Cursor**: each runner substitutes its plugin-root variable (`${CLAUDE_PLUGIN_ROOT}` / `${CURSOR_PLUGIN_ROOT}`) itself, so the same `node "…/dist/launcher.mjs"` command runs in a POSIX shell and in PowerShell (Cursor uses `pwsh`, else Windows PowerShell, on Windows). Neither gets a `powershell -Command` twin: both runners start every hook on an event in parallel, and a nested Windows PowerShell 5.1 start costs 20-45 s per event — long enough to outlive the 30 s event claim and post the event twice. Codex has a first-class `commandWindows` field and gets one entry with both.

**Every command ends in `; exit 0`.** A missing payload or an unsubstituted plugin-root variable becomes stderr noise instead of a hook error on every event. Delivery is observe-only and fail-open by construction.

POSIX commands expand `${CLAUDE_PLUGIN_ROOT}` / `${CURSOR_PLUGIN_ROOT}` / `${PLUGIN_ROOT}`. Codex's `commandWindows` reads `Env:PLUGIN_ROOT` itself rather than trusting runner-side substitution.

## Install

Replace `<owner>/<repo>` with this GitHub repo (e.g. `ev-ai/marketplace`).

### Claude Code

```bash
# Add marketplace
claude plugin marketplace add <owner>/<repo>

# Install on this machine (enablement alone does not install)
claude plugin install ev-ai-agent-hooks@ev-ai-marketplace
```

Project `.claude/settings.json` (commit both keys for collaborators):

```json
{
  "extraKnownMarketplaces": {
    "ev-ai-marketplace": {
      "source": {
        "source": "github",
        "repo": "<owner>/<repo>"
      }
    }
  },
  "enabledPlugins": {
    "ev-ai-agent-hooks@ev-ai-marketplace": true
  }
}
```

Configure collector URL:

```bash
npx -y @ev-ai/agent-hook@1.3.9 configure \
  --url "https://<collector-host>/<orgToken>/hook"
```

Commit the collector manifest (`collector_url`).

`enabledPlugins` without `extraKnownMarketplaces` only works on a machine that already ran `claude plugin marketplace add` — other clones will not know `ev-ai-marketplace`.

### Claude Code — org rollout (managed settings)

Put this in Claude managed settings (admin console, MDM, or `managed-settings.json`). Every user's Claude Code registers the marketplace and installs the plugin at its next session start, with no per-repo or per-machine step:

```json
{
  "extraKnownMarketplaces": {
    "ev-ai-marketplace": {
      "source": { "source": "github", "repo": "evalon-ai/marketplace" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "ev-ai-agent-hooks@ev-ai-marketplace": true
  },
  "pluginConfigs": {
    "ev-ai-agent-hooks@ev-ai-marketplace": {
      "options": { "collector_url": "https://<collector-host>/<orgToken>/hook" }
    }
  }
}
```

`pluginConfigs` presets the plugin's `collector_url` option; Claude Code exports it to every hook as `CLAUDE_PLUGIN_OPTION_COLLECTOR_URL`. It is the fallback: `--url`, `EV_AI_HOOK_MANIFEST`, `~/.ev-ai/config.json` and a committed repo manifest all win over it. `autoUpdate` is off by default for third-party marketplaces — without it the fleet never gets a release.

### Cursor

Import this repo as a team/user marketplace (or submit via [cursor.com/marketplace/publish](https://cursor.com/marketplace/publish)), then enable `ev-ai-agent-hooks`.

Configure the same collector manifest as Claude (`configure` above).

The plugin declares a required `COLLECTOR_URL` variable (`plugin.json` `variables`), so Cursor asks for the collector URL when the plugin is added and exports it to every hook as `COLLECTOR_URL`. Like Claude's `pluginConfigs` option, it is the fallback: `--url`, `EV_AI_HOOK_MANIFEST`, `~/.ev-ai/config.json` and a committed repo manifest all win over it. It needs a payload from `@ev-ai/agent-hook` that reads `COLLECTOR_URL`; older payloads ignore it and use the manifest.

### Codex

Enable `ev-ai-agent-hooks` from this marketplace, then trust hooks via `/hooks` — install and enable are not enough, and trust is stored against the hook-definition hash. Managed `[hooks]` (MDM / cloud requirements) is trusted by policy and needs no click.

> `allow_managed_hooks_only = true` skips plugin hooks entirely. In an org with that set, put ev-ai on the managed `[hooks]` table instead of this marketplace.

Restart runners; confirm events in the collector.

## Do not double-wire

If the repo already used file-wiring install, migrate first:

```bash
npx -y @ev-ai/agent-hook@1.3.9 migrate-to-plugin
```

Do **not** also keep per-event blocks in runner settings — that double-POSTs.

## Releasing

Payload and event maps are generated from `packages/agent-hook` in the monorepo. From a monorepo checkout:

```bash
yarn workspace @ev-ai/agent-hook build
yarn workspace @ev-ai/agent-hook sync:hooks -- /path/to/marketplace
```

That copies `dist/launcher.mjs`, `dist/launcher-update.mjs` and `dist/hook.mjs` into all three plugin trees, writes each `package.json`, and rewrites every `hooks/hooks.json`.

Then set the plugin manifest versions to the package version here (also run automatically as part of monorepo `/publish-agent-hooks`):

```bash
/pin-agent-hook <X.Y.Z>
# or: node .cursor/skills/pin-agent-hook/scripts/pin.mjs <X.Y.Z>
```

Commit and push; the plugin payload ships with the plugin.
