#!   /usr/bin/env -S /bin/sh -- # 2>nul
:; # Three spaces stop Windows from launching sh. "2>nul" hides cmd's message that #! is not a command.
:; # env -S splits this line and stops at "#", so Linux runs /bin/sh -- and does not see 2>nul as an option. macOS env -S does the same.
:; # Use node on PATH. If it is missing, use the node binary Cursor ships.
:; if command -v node >/dev/null 2>&1; then exec node "$@"; fi
:; for candidate in "/Applications/Cursor.app/Contents/Resources/app/resources/helpers/node" "$HOME/.local/share/cursor/resources/app/resources/helpers/node" "/usr/share/cursor/resources/app/resources/helpers/node" "/usr/lib/cursor/resources/app/resources/helpers/node" "/opt/Cursor/resources/app/resources/helpers/node" "/opt/cursor/resources/app/resources/helpers/node"; do if [ -x "$candidate" ]; then exec "$candidate" "$@"; fi; done
:; echo "ev-ai-agent-hooks: node was not found" >&2
:; exit 0
@echo off
setlocal EnableExtensions
set "NODE="
for /f "delims=" %%A in ('where node 2^>nul') do (
  echo %%A | findstr /i /c:"WindowsApps" >nul
  if errorlevel 1 if not defined NODE set "NODE=%%A"
)
if not defined NODE set "NODE=%LOCALAPPDATA%\Programs\cursor\resources\app\resources\helpers\node.exe"
if not exist "%NODE%" set "NODE=%LOCALAPPDATA%\Programs\Cursor\resources\app\resources\helpers\node.exe"
if not exist "%NODE%" set "NODE=%LOCALAPPDATA%\Programs\cursor\resources\helpers\node.exe"
if not exist "%NODE%" set "NODE=%ProgramFiles%\cursor\resources\app\resources\helpers\node.exe"
if not exist "%NODE%" set "NODE=%ProgramFiles%\Cursor\resources\app\resources\helpers\node.exe"
if exist "%NODE%" goto run
echo ev-ai-agent-hooks: node was not found 1>&2
exit /b 0
:run
"%NODE%" %*
exit /b %errorlevel%
