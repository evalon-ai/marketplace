# ev-ai hooks marketplace

Claude Code / Cursor / Codex plugin marketplace for Layer-3 runtime telemetry.

Each plugin ships its own runtime: `hook.mjs` plus a `sh` + PowerShell launcher pair at the plugin root. `hooks.json` invokes the launcher, the launcher resolves the plugin root from its own environment, probes once for a usable runtime, caches the verdict at `~/.ev-ai/runtime`, and execs the payload. Customer repos enable a plugin and commit a shared `collector_url` manifest — not per-event blocks in runner settings.

On a machine with no Node at all, the launcher fetches the Bun-compiled binary from the CDN in the background, verifies it against `SHA256SUMS`, and uses it from the next event onward. Nothing blocks on the download, and there is no `npx` branch — `npx` requires Node, so it could never serve the machine a fallback is for.

> **A plugin hook never reaches the npm registry.** The runtime is either `hook.mjs` from the payload or the CDN binary, resolved at the payload's own `version`, so a plugin never runs a runtime newer than the event map it shipped with. The package still publishes publicly as **`@ev-ai/agent-hook`** for `configure` / `migrate-to-plugin` and for repos on file-wiring; consumers need no `.npmrc` and no token.

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
    │   ├── launcher.ps1              # PowerShell 5.1 launcher
    │   ├── version                   # payload version — pins both fallbacks
    │   └── SHA256SUMS                # checksums for the 6 CDN binaries
    ├── cursor-runtime-hooks/         # Cursor — same six files
    └── codex-runtime-hooks/          # OpenAI Codex — same six files
```

Every file above except `plugin.json` is **generated** — never hand-edit them here. They are copied from (or stamped by) `packages/agent-hook` in the monorepo via `sync:hooks` (see [Releasing](#releasing)).

`version` carries the package version in the *payload* rather than in a hook command, which is what lets a bump pin the fallbacks without rewriting `hooks.json`. `SHA256SUMS` makes this repo the trust anchor for the on-demand binary download; if a release ships without it, the launcher verifies against the CDN's own copy instead.

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
        node   → node hook.mjs                            ~40 ms to ack
        binary → ~/.ev-ai/agent-hook/<version>/ev-ai-agent-hook   ~23 ms to ack
        none   → {"continue":true} now, and a detached CDN fetch of the
                 binary (verified against SHA256SUMS) for the next event
  → ack; collect + POST continue detached
```

The `none` verdict is deliberately **not** cached — it is the one verdict a background fetch can change. The fetch is rate-limited by the mtime of `~/.ev-ai/agent-hook/.fetch-stamp` (6 h default, `EV_AI_BINARY_FETCH_TTL_MIN`) and disabled entirely by `EV_AI_BINARY_FETCH=0`.

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

That copies `hook.mjs` + both launchers into all three plugin trees, stamps `version`, and rewrites every `hooks/hooks.json`.

To also anchor the binary download to this repo, cross-compile first — `yarn workspace @ev-ai/agent-hook build:hook-binary` — and `sync:hooks` picks up the generated `SHA256SUMS`. The six binaries themselves go to the CDN, never into this repo:

```bash
aws s3 sync packages/agent-hook/compile-out/bin s3://ev-ai-agent-hook/<X.Y.Z>/
```

Then set the plugin manifest versions to the package version here:

```bash
/pin-agent-hook <X.Y.Z>
```

Commit and push; the plugin payload ships with the plugin.
