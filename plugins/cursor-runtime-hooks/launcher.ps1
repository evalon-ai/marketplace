# Dual-shell hook launcher (PowerShell 5.1). Probe once, cache, exec the runtime.
#
# Runtime order: `node hook.mjs`, then the Bun-compiled binary, fetched on
# demand from the CDN. There is deliberately no `npx` branch: `npx` ships with
# Node, so it is unreachable on the machines that need a fallback, and it would
# reach the npm registry from a developer machine on every event.
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
# Empty under the scriptblock form the hook commands use — the root variable is
# the real resolution path; this only covers `-File` invocation.
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

# Payload version, shipped beside hook.mjs. Lives in the payload rather than in
# the hook command, so the binary this launcher fetches matches the bytes the
# plugin shipped without putting a version in the hook definition.
$version = $null
$versionFile = Join-Path $root 'version'
if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
  $version = ((Get-Content -LiteralPath $versionFile -Raw) -replace '\s', '')
}

$cacheDir = Join-Path $HOME '.ev-ai'
$cacheFile = Join-Path $cacheDir 'runtime'
$binName = 'ev-ai-agent-hook.exe'
$binHome = Join-Path $cacheDir 'agent-hook'
$fetchStamp = Join-Path $binHome '.fetch-stamp'
$fetchTtlMinutes = if ($env:EV_AI_BINARY_FETCH_TTL_MIN) { [int]$env:EV_AI_BINARY_FETCH_TTL_MIN } else { 360 }
$cdnBase = if ($env:EV_AI_BINARY_BASE_URL) { $env:EV_AI_BINARY_BASE_URL } else { 'https://ev-ai-agent-hook.s3.us-east-1.amazonaws.com' }

# Version-pinned copy first (what this launcher fetches), then whatever
# install.sh pinned behind `current` — an older binary still posts.
$binary = $null
if ($version) {
  $pinned = Join-Path (Join-Path $binHome $version) $binName
  if (Test-Path -LiteralPath $pinned -PathType Leaf) { $binary = $pinned }
}
if (-not $binary) {
  $currentBin = Join-Path (Join-Path $binHome 'current') $binName
  if (Test-Path -LiteralPath $currentBin -PathType Leaf) { $binary = $currentBin }
}

# Release slug for this host; $null on anything not built for.
function Get-PlatformSlug {
  switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { return 'windows-x64' }
    'ARM64' { return 'windows-arm64' }
  }
  return $null
}

function Get-RemoteFile($url, $dest) {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  } catch {
    # Older hosts: leave the default protocol alone rather than failing here.
  }
  try {
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 300
    return (Test-Path -LiteralPath $dest -PathType Leaf)
  } catch {
    return $false
  }
}

function Get-SumsEntry($sumsPath, $rel) {
  foreach ($line in (Get-Content -LiteralPath $sumsPath)) {
    $parts = $line -split '\s+' | Where-Object { $_ }
    if ($parts.Count -ge 2 -and ($parts[1] -eq $rel -or $parts[1] -eq "*$rel")) {
      return $parts[0]
    }
  }
  return $null
}

# `<sha>  <slug>/<name>` line for this platform, from the payload copy when the
# plugin shipped one (git-anchored) and from the CDN otherwise (TLS-anchored).
function Get-ExpectedSha($slug) {
  $rel = "$slug/$binName"
  $local = Join-Path $root 'SHA256SUMS'
  if (Test-Path -LiteralPath $local -PathType Leaf) {
    $sha = Get-SumsEntry $local $rel
    if ($sha) { return $sha }
  }
  $tmpSums = Join-Path $binHome (".sums." + $PID)
  if (Get-RemoteFile "$cdnBase/$version/SHA256SUMS" $tmpSums) {
    $sha = Get-SumsEntry $tmpSums $rel
    Remove-Item -LiteralPath $tmpSums -Force -ErrorAction SilentlyContinue
    if ($sha) { return $sha }
  }
  Remove-Item -LiteralPath $tmpSums -Force -ErrorAction SilentlyContinue
  return $null
}

# Download, verify, install. Runs only in the detached child — 15-24 MB does not
# fit the hook timeout budget (10 s on Claude MessageDisplay).
function Invoke-BinaryFetch {
  $slug = Get-PlatformSlug
  if (-not $slug -or -not $version) { return }

  $dir = Join-Path $binHome $version
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $tmp = Join-Path $dir (".download." + $PID)

  if (-not (Get-RemoteFile "$cdnBase/$version/$slug/$binName" $tmp)) {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    return
  }

  $want = Get-ExpectedSha $slug
  $got = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
  if (-not $want -or -not $got -or $got -ne $want.ToUpperInvariant()) {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    return
  }

  # Rename inside one directory is atomic: no partial binary is ever runnable at
  # the final path, and no `current` link is touched (no swap window).
  Move-Item -LiteralPath $tmp -Destination (Join-Path $dir $binName) -Force
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

# Rate-limited, detached, opt-out-able. Never blocks the event.
function Start-BinaryFetch {
  if ($env:EV_AI_BINARY_FETCH -eq '0') { return }
  if (-not $version -or -not (Get-PlatformSlug)) { return }
  $self = Join-Path $root 'launcher.ps1'
  if (-not (Test-Path -LiteralPath $self -PathType Leaf)) { return }

  New-Item -ItemType Directory -Force -Path $binHome | Out-Null
  # A stamp younger than the TTL means a fetch just ran or is still running.
  if (Test-Path -LiteralPath $fetchStamp -PathType Leaf) {
    $age = (Get-Date) - (Get-Item -LiteralPath $fetchStamp).LastWriteTime
    if ($age.TotalMinutes -lt $fetchTtlMinutes) { return }
  }
  Set-Content -LiteralPath $fetchStamp -Value '' -NoNewline

  # Re-enter through the same host that is already running rather than assuming
  # `powershell` on PATH — the scriptblock form leaves $PSCommandPath empty, so
  # the child is launched by path with the flag appended.
  $psHost = $null
  try { $psHost = (Get-Process -Id $PID).Path } catch { $psHost = $null }
  if (-not $psHost) { $psHost = 'powershell' }

  $quoted = $self -replace "'", "''"
  $inner = "& ([scriptblock]::Create((Get-Content -Raw -LiteralPath '$quoted'))) --ev-ai-fetch-binary"
  $spawnArgs = @('-NoProfile', '-NonInteractive', '-Command', $inner)
  try {
    Start-Process -FilePath $psHost -WindowStyle Hidden -ArgumentList $spawnArgs | Out-Null
  } catch {
    # -WindowStyle is Windows-only; a non-Windows edition rejects it outright.
    # Retry bare rather than losing the fetch on the one path that needs it.
    Start-Process -FilePath $psHost -ArgumentList $spawnArgs | Out-Null
  }
}

if ($args.Count -ge 1 -and $args[0] -eq '--ev-ai-fetch-binary') {
  Invoke-BinaryFetch
  exit 0
}

$runtime = $null
if (Test-Path -LiteralPath $cacheFile -PathType Leaf) {
  $runtime = ((Get-Content -LiteralPath $cacheFile -Raw) -replace '[\r\n]', '').Trim()
}

# Discard a verdict this launcher no longer implements (e.g. `npx` written by an
# older payload) rather than treating it as a miss — a stale token must re-probe,
# not fall through to the fetch on a machine that has Node.
if ($runtime -ne 'node' -and $runtime -ne 'binary') { $runtime = $null }

function Probe-Runtime {
  if ($hook -and (Get-Command node -ErrorAction SilentlyContinue)) { return 'node' }
  if ($binary) { return 'binary' }
  return 'none'
}

if (-not $runtime) {
  $runtime = Probe-Runtime
  # `none` is deliberately not cached: it is the one verdict a background fetch
  # can change, and caching it would freeze the machine out of the binary branch
  # the moment the download lands.
  if ($runtime -ne 'none') {
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    Set-Content -LiteralPath $cacheFile -Value $runtime -NoNewline
  }
}

switch ($runtime) {
  'node' {
    if (-not $hook) { Fail-Open }
    & node $hook @args
    if ($LASTEXITCODE -ne 0) { Fail-Open }
  }
  'binary' {
    if ($binary) {
      & $binary @args
      if ($LASTEXITCODE -ne 0) { Fail-Open }
    } else {
      # Cached verdict with nothing on disk — re-fetch, fail open meanwhile.
      Start-BinaryFetch
      Fail-Open
    }
  }
  default {
    Start-BinaryFetch
    Fail-Open
  }
}
