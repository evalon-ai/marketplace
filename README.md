# ev-ai hooks marketplace

Claude Code / Cursor / Codex plugin marketplace for Layer-3 runtime telemetry.

Each plugin ships its own runtime: `hook.mjs` plus a `sh` + PowerShell launcher pair at the plugin root. `hooks.json` invokes the launcher, the launcher resolves the plugin root from its own environment, probes once for a usable runtime, caches the verdict at `~/.ev-ai/runtime`, and execs the payload. Customer repos enable a plugin and commit a shared `collector_url` manifest — not per-event blocks in runner settings.

> Hook package publishes to the **public npm registry** as **`@ev-ai/agent-hook`**. Consumers need no `.npmrc` and no token. The launcher's `npx` fallback only fires on a machine with no `node` on PATH.

## Layout

```text
.
├── .claude-plugin/marketplace.json   # Claude Code marketplace catalog
├── .cursor-plugin/marketplace.json   # Cursor marketplace catalog
├── .agents/plugins/marketplace.json  # Codex marketplace catalog
└── plugins/
    ├── claude-runtime-hooks/         # Claude Code
    │   ├── .claude-plugin/plugin.json
    │   ├── hooks/hooks.json          # event map — invokes ./launcher.sh / ./launcher.ps1
    │   ├── hook.mjs                  # runtime payload (bundled, zero-dependency)
    │   ├── launcher.sh               # POSIX launcher
    │   └── launcher.ps1              # PowerShell 5.1 launcher
    ├── cursor-runtime-hooks/         # Cursor — same four files
    └── codex-runtime-hooks/          # OpenAI Codex — same four files
```

`hook.mjs`, `launcher.sh` and `launcher.ps1` are **generated** — never hand-edit them here. They are copied from `packages/agent-hook` in the monorepo by `sync:hooks` (see [Releasing](#releasing)).

## Plugins

| Plugin | Runner |
| --- | --- |
| `claude-runtime-hooks` | Claude Code |
| `cursor-runtime-hooks` | Cursor |
| `codex-runtime-hooks` | OpenAI Codex |

## How a hook event runs

```text
runner event
  → launcher (resolves plugin root, ~9 ms)
    → ~/.ev-ai/runtime cached verdict?
        node  → node hook.mjs                     ~40 ms to ack
        npx   → npx -y --prefer-offline @ev-ai/agent-hook   (no node on PATH)
        none  → {"continue":true}, nothing POSTs
  → ack; collect + POST continue detached
```

**No package version appears in any hook command.** A runtime bump changes `hook.mjs`, not `hooks.json` — so it re-prompts nobody. That matters most on Codex, which trusts a hash of the hook definition and un-trusts it on every change.

**Two entries per event on Claude and Cursor**, one POSIX and one PowerShell, both registered unconditionally and selected at fire time: a single path-bearing command cannot parse in both `sh` and PowerShell. Exactly one POSTs — `launcher.sh` stands down on Git Bash (`MINGW*` / `MSYS*` / `CYGWIN*`) so the `.ps1` sibling owns Windows, and `powershell` does not exist on macOS / Linux. Codex has a first-class `commandWindows` field and gets one entry with both.

**Every command ends in `; exit 0`.** A missing payload, a failed runtime probe, or an unsubstituted plugin-root variable becomes stderr noise instead of a hook error on every event. Delivery is observe-only and fail-open by construction.

The launcher reads the plugin root from `CLAUDE_PLUGIN_ROOT` / `CURSOR_PLUGIN_ROOT` / `PLUGIN_ROOT`, and falls back to its own directory. The PowerShell entry reads `Env:*_PLUGIN_ROOT` itself rather than trusting runner-side substitution, and builds a scriptblock from the file instead of using `-File`, so an unsigned `.ps1` runs without depending on ExecutionPolicy.

## Install

Replace `<owner>/<repo>` with this GitHub repo (e.g. `ev-ai/marketplace`).

### Claude Code

```bash
# Add marketplace
claude plugin marketplace add <owner>/<repo>

# Install on this machine (enablement alone does not install)
claude plugin install claude-runtime-hooks@ev-ai-agent-hooks
```

Project `.claude/settings.json` (commit both keys for collaborators):

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
npx -y @ev-ai/agent-hook@1.1.3 configure \
  --url "https://<collector-host>/<orgToken>/hook"
```

Commit the collector manifest (`collector_url`).

`enabledPlugins` without `extraKnownMarketplaces` only works on a machine that already ran `claude plugin marketplace add` — other clones will not know `ev-ai-agent-hooks`.

### Cursor

Import this repo as a team/user marketplace (or submit via [cursor.com/marketplace/publish](https://cursor.com/marketplace/publish)), then enable `cursor-runtime-hooks`.

Configure the same collector manifest as Claude (`configure` above).

> Cursor loads plugin hooks but does **not** register their commands today — plugin delivery is not hook execution on Cursor. Until that is fixed, the working Cursor path is Enterprise / Team `hooks.json` or a committed `.cursor/hooks.json`.

### Codex

Enable `codex-runtime-hooks` from this marketplace, then trust hooks via `/hooks` — install and enable are not enough, and trust is stored against the hook-definition hash. Managed `[hooks]` (MDM / cloud requirements) is trusted by policy and needs no click.

> `allow_managed_hooks_only = true` skips plugin hooks entirely. In an org with that set, put ev-ai on the managed `[hooks]` table instead of this marketplace.

Restart runners; confirm events in the collector.

## Do not double-wire

If the repo already used file-wiring install, migrate first:

```bash
npx -y @ev-ai/agent-hook@1.1.3 migrate-to-plugin
```

Do **not** also keep per-event blocks in runner settings — that double-POSTs.

## Releasing

Payload and event maps are generated from `packages/agent-hook` in the monorepo. From a monorepo checkout:

```bash
yarn workspace @ev-ai/agent-hook build
yarn workspace @ev-ai/agent-hook sync:hooks -- /path/to/marketplace
```

That copies `hook.mjs` + both launchers into all three plugin trees and rewrites every `hooks/hooks.json`. Then set the plugin manifest versions to the package version here:

```bash
/pin-agent-hook <X.Y.Z>
```

Commit and push; the plugin payload ships with the plugin.
