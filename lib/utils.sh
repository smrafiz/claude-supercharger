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

  # Windows Git Bash: 'python3' is a Windows Store alias stub, not real Python.
  # Create a shim so all subsequent python3 calls resolve to 'python'.
  if [[ "$PLATFORM" == "windows" ]] && ! python3 --version &>/dev/null 2>&1; then
    if python --version &>/dev/null 2>&1; then
      local shim_dir
      shim_dir=$(mktemp -d)
      printf '#!/usr/bin/env bash\nexec python "$@"\n' > "$shim_dir/python3"
      chmod +x "$shim_dir/python3"
      export PATH="$shim_dir:$PATH"
    else
      echo "Error: Python 3 is required. Install from https://python.org and re-run."
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
