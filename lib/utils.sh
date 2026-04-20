#!/usr/bin/env bash
# Claude Supercharger — Utility Functions

VERSION="3.6.33"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
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
