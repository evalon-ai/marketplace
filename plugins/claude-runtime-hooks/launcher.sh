#!/usr/bin/env sh
# Dual-shell hook launcher (POSIX). Probe once, cache, exec hook.mjs.
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
[ -n "$HOOK" ] || fail_open

CACHE_DIR="${HOME}/.ev-ai"
CACHE_FILE="${CACHE_DIR}/runtime"
RUNTIME=""
if [ -f "$CACHE_FILE" ]; then
  RUNTIME="$(tr -d '\r\n' < "$CACHE_FILE")"
fi

probe() {
  if command -v node >/dev/null 2>&1; then
    printf 'node'
    return
  fi
  if command -v npx >/dev/null 2>&1; then
    printf 'npx'
    return
  fi
  printf 'none'
}

if [ -z "$RUNTIME" ]; then
  RUNTIME="$(probe)"
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  printf '%s\n' "$RUNTIME" > "$CACHE_FILE" 2>/dev/null || true
fi

case "$RUNTIME" in
  node)
    exec node "$HOOK" "$@" || fail_open
    ;;
  npx)
    exec npx -y --prefer-offline @ev-ai/agent-hook "$@" || fail_open
    ;;
  *)
    fail_open
    ;;
esac
