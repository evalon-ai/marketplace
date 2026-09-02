# Dual-shell hook launcher (PowerShell 5.1). Probe once, cache, exec hook.mjs.
# Reads plugin root from the environment; does not trust runner substitution.
$ErrorActionPreference = 'SilentlyContinue'

function Fail-Open {
  Write-Output '{"continue":true}'
  exit 0
}

$root = $null
foreach ($name in @('CLAUDE_PLUGIN_ROOT', 'CURSOR_PLUGIN_ROOT', 'PLUGIN_ROOT')) {
  $item = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
  if ($item -and $item.Value) {
    $root = $item.Value
    break
  }
}
if (-not $root) { $root = $PSScriptRoot }

$hook = $null
foreach ($rel in @(
    'hook.mjs',
    'dist/hook.mjs',
    (Join-Path '..' 'dist/hook.mjs'),
    (Join-Path '..' 'packages/agent-hook/dist/hook.mjs')
  )) {
  $candidate = Join-Path $root $rel
  if (Test-Path -LiteralPath $candidate -PathType Leaf) {
    $hook = $candidate
    break
  }
}
if (-not $hook) { Fail-Open }

$cacheDir = Join-Path $HOME '.ev-ai'
$cacheFile = Join-Path $cacheDir 'runtime'
$runtime = $null
if (Test-Path -LiteralPath $cacheFile -PathType Leaf) {
  $runtime = ((Get-Content -LiteralPath $cacheFile -Raw) -replace '[\r\n]', '').Trim()
}

function Probe-Runtime {
  if (Get-Command node -ErrorAction SilentlyContinue) { return 'node' }
  if (Get-Command npx -ErrorAction SilentlyContinue) { return 'npx' }
  return 'none'
}

if (-not $runtime) {
  $runtime = Probe-Runtime
  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
  Set-Content -LiteralPath $cacheFile -Value $runtime -NoNewline
}

switch ($runtime) {
  'node' {
    & node $hook @args
    if ($LASTEXITCODE -ne 0) { Fail-Open }
  }
  'npx' {
    & npx -y --prefer-offline @ev-ai/agent-hook @args
    if ($LASTEXITCODE -ne 0) { Fail-Open }
  }
  default { Fail-Open }
}
