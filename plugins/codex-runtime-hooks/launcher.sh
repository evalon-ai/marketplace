#!/usr/bin/env sh
# Dual-shell hook launcher (POSIX). Probe once, cache, exec the runtime.
#
# Runtime order: `node hook.mjs`, then the Bun-compiled binary, fetched on
# demand from the CDN. There is deliberately no `npx` branch: `npx` ships with
# Node, so it is unreachable on the machines that need a fallback, and it would
# reach the npm registry from a developer machine on every event.
# Git Bash stands down so the .ps1 sibling can run without a double POST.
set -u

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) printf '%s\n' '{"continue":true}'; exit 0 ;;
esac

fail_open() {
  printf '%s\n' '{"continue":true}'
  exit 0
}

ROOT="${CLAUDE_PLUGIN_ROOT:-${CURSOR_PLUGIN_ROOT:-${PLUGIN_ROOT:-}}}"
if [ -z "$ROOT" ]; then
  ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
fi

HOOK=""
for candidate in \
  "$ROOT/hook.mjs" \
  "$ROOT/dist/hook.mjs" \
  "$ROOT/../dist/hook.mjs" \
  "$ROOT/../packages/agent-hook/dist/hook.mjs"
do
  if [ -f "$candidate" ]; then
    HOOK="$candidate"
    break
  fi
done

# Payload version, shipped beside hook.mjs. Lives in the payload rather than in
# the hook command, so the binary this launcher fetches matches the bytes the
# plugin shipped without putting a version in the hook definition.
VERSION=""
if [ -f "$ROOT/version" ]; then
  VERSION="$(tr -d ' \011\015\012' < "$ROOT/version" 2>/dev/null || true)"
fi

CACHE_DIR="${HOME}/.ev-ai"
CACHE_FILE="${CACHE_DIR}/runtime"
BIN_NAME="ev-ai-agent-hook"
BIN_HOME="${CACHE_DIR}/agent-hook"
FETCH_STAMP="${BIN_HOME}/.fetch-stamp"
FETCH_TTL_MIN="${EV_AI_BINARY_FETCH_TTL_MIN:-360}"
CDN_BASE="${EV_AI_BINARY_BASE_URL:-https://ev-ai-agent-hook.s3.us-east-1.amazonaws.com}"

# Version-pinned copy first (what this launcher fetches), then whatever
# install.sh pinned behind `current` — an older binary still posts.
BINARY=""
if [ -n "$VERSION" ] && [ -x "${BIN_HOME}/${VERSION}/${BIN_NAME}" ]; then
  BINARY="${BIN_HOME}/${VERSION}/${BIN_NAME}"
elif [ -x "${BIN_HOME}/current/${BIN_NAME}" ]; then
  BINARY="${BIN_HOME}/current/${BIN_NAME}"
fi

# Release slug for this host; empty (silent) on anything not built for.
platform_slug() {
  _os=""
  _arch=""
  case "$(uname -s 2>/dev/null)" in
    Darwin) _os="darwin" ;;
    Linux) _os="linux" ;;
    *) return 0 ;;
  esac
  case "$(uname -m 2>/dev/null)" in
    arm64|aarch64) _arch="arm64" ;;
    x86_64|amd64) _arch="x64" ;;
    *) return 0 ;;
  esac
  printf '%s-%s' "$_os" "$_arch"
}

download() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time 300 "$1" -o "$2" 2>/dev/null
    return $?
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q -T 300 -O "$2" "$1" 2>/dev/null
    return $?
  fi
  return 1
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  fi
}

# `<sha>  <slug>/<name>` line for this platform, from the payload copy when the
# plugin shipped one (git-anchored) and from the CDN otherwise (TLS-anchored).
expected_sha() {
  _rel="${1}/${BIN_NAME}"
  _sha=""
  if [ -f "$ROOT/SHA256SUMS" ]; then
    _sha="$(awk -v rel="$_rel" '$2 == rel || $2 == "*" rel { print $1; exit }' "$ROOT/SHA256SUMS" 2>/dev/null)"
    if [ -n "$_sha" ]; then
      printf '%s' "$_sha"
      return 0
    fi
  fi
  _sums="${BIN_HOME}/.sums.$$"
  if download "${CDN_BASE}/${VERSION}/SHA256SUMS" "$_sums"; then
    _sha="$(awk -v rel="$_rel" '$2 == rel || $2 == "*" rel { print $1; exit }' "$_sums" 2>/dev/null)"
  fi
  rm -f "$_sums" 2>/dev/null || true
  [ -n "$_sha" ] || return 1
  printf '%s' "$_sha"
}

# Download, verify, install. Runs only in the detached child — 15-24 MB does not
# fit the hook timeout budget (10 s on Claude MessageDisplay).
fetch_binary() {
  _slug="$(platform_slug)"
  [ -n "$_slug" ] || return 1
  [ -n "$VERSION" ] || return 1

  _dir="${BIN_HOME}/${VERSION}"
  mkdir -p "$_dir" 2>/dev/null || return 1
  _tmp="${_dir}/.download.$$"

  download "${CDN_BASE}/${VERSION}/${_slug}/${BIN_NAME}" "$_tmp" || {
    rm -f "$_tmp" 2>/dev/null || true
    return 1
  }

  _want="$(expected_sha "$_slug")" || {
    rm -f "$_tmp" 2>/dev/null || true
    return 1
  }
  _got="$(sha256_of "$_tmp")"
  if [ -z "$_got" ] || [ "$_got" != "$_want" ]; then
    rm -f "$_tmp" 2>/dev/null || true
    return 1
  fi

  chmod 0755 "$_tmp" 2>/dev/null || true
  # Rename inside one directory is atomic: no partial binary is ever runnable at
  # the final path, and no `current` symlink is touched (no swap window).
  mv -f "$_tmp" "${_dir}/${BIN_NAME}" 2>/dev/null || {
    rm -f "$_tmp" 2>/dev/null || true
    return 1
  }
}

# Rate-limited, detached, opt-out-able. Never blocks the event.
maybe_spawn_fetch() {
  [ "${EV_AI_BINARY_FETCH:-1}" != "0" ] || return 1
  [ -n "$VERSION" ] || return 1
  [ -n "$(platform_slug)" ] || return 1
  mkdir -p "$BIN_HOME" 2>/dev/null || return 1
  # A stamp younger than the TTL means a fetch just ran or is still running.
  if [ -f "$FETCH_STAMP" ] && [ -z "$(find "$FETCH_STAMP" -mmin +"$FETCH_TTL_MIN" 2>/dev/null)" ]; then
    return 1
  fi
  : > "$FETCH_STAMP" 2>/dev/null || return 1
  nohup sh "$0" --ev-ai-fetch-binary </dev/null >/dev/null 2>&1 &
}

if [ "${1:-}" = "--ev-ai-fetch-binary" ]; then
  fetch_binary
  exit 0
fi

RUNTIME=""
if [ -f "$CACHE_FILE" ]; then
  RUNTIME="$(tr -d '\r\n' < "$CACHE_FILE")"
fi

# Discard a verdict this launcher no longer implements (e.g. `npx` written by an
# older payload) rather than treating it as a miss — a stale token must re-probe,
# not fall through to the fetch on a machine that has Node.
case "$RUNTIME" in
  node|binary) ;;
  *) RUNTIME="" ;;
esac
CACHED="$RUNTIME"

probe() {
  if [ -n "$HOOK" ] && command -v node >/dev/null 2>&1; then
    printf 'node'
    return
  fi
  if [ -n "$BINARY" ]; then
    printf 'binary'
    return
  fi
  printf 'none'
}

if [ -z "$RUNTIME" ]; then
  RUNTIME="$(probe)"
  # `none` is deliberately not cached: it is the one verdict a background fetch
  # can change, and caching it would freeze the machine out of the binary branch
  # the moment the download lands.
  if [ "$RUNTIME" != "none" ]; then
    mkdir -p "$CACHE_DIR" 2>/dev/null || true
    printf '%s\n' "$RUNTIME" > "$CACHE_FILE" 2>/dev/null || true
  fi
fi

# Exec the runtime this verdict names, or return non-zero *without* exec'ing when
# it is not actually usable. The check has to happen before `exec`: a failed
# `exec` exits the shell outright, so `exec node … || fail_open` never runs its
# fallback and leaks 127 to the runner instead of `{"continue":true}`.
try_dispatch() {
  case "$RUNTIME" in
    node)
      [ -n "$HOOK" ] || return 1
      command -v node >/dev/null 2>&1 || return 1
      exec node "$HOOK" "$@"
      ;;
    binary)
      [ -n "$BINARY" ] || return 1
      [ -x "$BINARY" ] || return 1
      exec "$BINARY" "$@"
      ;;
  esac
  return 1
}

try_dispatch "$@"

# The cached verdict did not survive contact: the runtime it names is gone, or
# this process has a different PATH than the one that wrote it (a GUI-launched
# IDE does not inherit a login shell's PATH). Drop it and probe again — once.
if [ -n "$CACHED" ]; then
  rm -f "$CACHE_FILE" 2>/dev/null || true
  RUNTIME="$(probe)"
  if [ "$RUNTIME" != "none" ]; then
    mkdir -p "$CACHE_DIR" 2>/dev/null || true
    printf '%s\n' "$RUNTIME" > "$CACHE_FILE" 2>/dev/null || true
  fi
  try_dispatch "$@"
fi

maybe_spawn_fetch
fail_open
