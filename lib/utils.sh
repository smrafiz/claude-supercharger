#!/usr/bin/env bash
# Claude Supercharger — Utility Functions

VERSION="1.5.0"

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

  # Windows Git Bash: 'python3' and 'python' may be Windows Store alias stubs.
  # Try multiple candidates; 'py' is the Python Launcher installed by python.org
  # and is not affected by App Execution Aliases.
  if [[ "$PLATFORM" == "windows" ]] && ! python3 --version &>/dev/null 2>&1; then
    local py_cmd=""
    for candidate in python py py3; do
      if $candidate --version &>/dev/null 2>&1; then
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
      echo "Error: Python 3 is required. Install from https://python.org and re-run."
      echo "       If already installed, disable App Execution Aliases in:"
      echo "       Settings > Apps > Advanced app settings > App execution aliases"
      echo "       (turn off the 'python' and 'python3' entries)"
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
