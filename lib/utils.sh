#!/usr/bin/env bash
# Claude Supercharger — Utility Functions

# Windows python defaults stdout to the ANSI codepage (cp1252) and raises
# UnicodeEncodeError on the box-drawing and arrow characters this script prints,
# losing ALL of its output. Hooks get this from hooks/lib-paths.sh; installer-side
# code never reaches that file, so it sets its own. `:=` honours an explicit setting.
: "${PYTHONIOENCODING:=utf-8}"
: "${PYTHONUTF8:=1}"
export PYTHONIOENCODING PYTHONUTF8

VERSION="2.27.18"

# Every scope dir a HOOK might read state from — classic install + any plugin install.
# Hooks resolve the dir as ${CLAUDE_PLUGIN_DATA:-~/.claude/supercharger}/scope, but
# skill/CLI-invoked TOOLS run OUTSIDE any hook, so CLAUDE_PLUGIN_DATA is usually unset
# for them — trusting it silently falls back to the classic path and control flags
# (profile / readonly / strict / disabled-hooks / …) never reach the plugin's hooks.
# So glob the plugin data dirs directly and act on ALL of them. See memory
# sc-toggle-plugin-path-divergence. Usage: `while read -r d; do …; done < <(sc_scope_dirs)`
# (or a heredoc loop for bash 3.2 process-substitution safety).
sc_scope_dirs() {
  # If CLAUDE_PLUGIN_DATA is explicitly set, that IS the state root — use only it.
  # Two reasons this is right, not a special case:
  #   1. Semantics: an explicit location beats discovery. Nothing should be writing
  #      outside a root the caller named.
  #   2. Isolation: the tests sandbox by setting this var (they do NOT override HOME).
  #      v2.23.40 made this function glob $HOME unconditionally, so `autopilot.sh off`
  #      inside a test deleted the developer's REAL autopilot/readonly/strict flags —
  #      a live session would silently lose its window minutes after granting it.
  # Tools invoked from a skill run outside any hook, where the var is unset, so they
  # still discover every scope dir — which is what the plugin-path fix needed.
  if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
    printf '%s\n' "$CLAUDE_PLUGIN_DATA/scope"
    return 0
  fi
  printf '%s\n' "$HOME/.claude/supercharger/scope"
  local _pd
  for _pd in "$HOME/.claude/plugins/data/"*supercharger*; do
    [ -d "$_pd" ] && printf '%s\n' "$_pd/scope"
  done
}

# Color codes — declared here, used across tools/* via `source lib/utils.sh`.
# shellcheck disable=SC2034
RED='\033[0;31m'
# shellcheck disable=SC2034
GREEN='\033[0;32m'
# shellcheck disable=SC2034
BLUE='\033[0;34m'
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
# shellcheck disable=SC2034
CYAN='\033[0;36m'
# shellcheck disable=SC2034
BOLD='\033[1m'
# shellcheck disable=SC2034
NC='\033[0m'

info()    { echo -e "${BLUE}$1${NC}"; }
success() { echo -e "${GREEN}  ✓ $1${NC}"; }
warn()    { echo -e "${YELLOW}  ⚠ $1${NC}"; }
error()   { echo -e "${RED}  ✗ $1${NC}"; }

detect_platform() {
  case "$OSTYPE" in
    darwin*)        PLATFORM="macos" ;;
    linux*)         PLATFORM="linux" ;;
    msys*|cygwin*)  PLATFORM="windows" ;;
    *)              PLATFORM="unknown" ;;
  esac

  # Force Python to use UTF-8 on Windows (default cp1252 can't handle → and other unicode)
  export PYTHONUTF8=1

  # Ensure python3 is available.
  # On Windows Git Bash: 'python3' rarely exists, 'python' may be a Windows Store
  # alias stub (zero-byte exe that opens Microsoft Store instead of running Python).
  # The 'py' launcher (installed by python.org) is the most reliable candidate.
  if ! command -v python3 &>/dev/null || ! python3 -c "import sys" &>/dev/null 2>&1; then
    local py_cmd=""
    # Try candidates in order: py (Windows launcher), python, py3
    for candidate in py python py3; do
      if command -v "$candidate" &>/dev/null && "$candidate" -c "import sys" &>/dev/null 2>&1; then
        py_cmd="$candidate"
        break
      fi
    done
    if [[ -n "$py_cmd" ]]; then
      local shim_dir
      shim_dir=$(mktemp -d)
      printf '#!/usr/bin/env bash\nexec %s "$@"\n' "$py_cmd" > "$shim_dir/python3"
      chmod +x "$shim_dir/python3"
      export PATH="$shim_dir:$PATH"
    else
      echo ""
      echo "Error: Python 3 is required but not found."
      echo ""
      echo "  Install from: https://python.org"
      echo ""
      if [[ "$PLATFORM" == "windows" ]]; then
        echo "  Windows users: if Python is installed but this still fails,"
        echo "  disable App Execution Aliases in:"
        echo "    Settings > Apps > Advanced app settings > App execution aliases"
        echo "    (turn off the 'python' and 'python3' entries)"
        echo ""
        echo "  Or install Python from python.org (not Microsoft Store)"
        echo "  and ensure 'Add to PATH' is checked during install."
      fi
      echo ""
      exit 1
    fi
  fi
}

show_banner() {
  echo -e "${CYAN}"
  echo "╔═══════════════════════════════════════════╗"
  echo "║    Claude Supercharger v${VERSION} Installer   ║"
  echo "╚═══════════════════════════════════════════╝"
  echo -e "${NC}"
}

resolve_script_dir() {
  local source="${BASH_SOURCE[1]:-$0}"
  local dir
  dir=$(cd "$(dirname "$source")" && pwd)
  if [[ "$(basename "$dir")" == "lib" ]]; then
    dir=$(dirname "$dir")
  fi
  echo "$dir"
}
