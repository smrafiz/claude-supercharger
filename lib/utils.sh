#!/usr/bin/env bash
# Claude Supercharger — Utility Functions

VERSION="1.1.0"

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
    darwin*)  PLATFORM="macos" ;;
    linux*)   PLATFORM="linux" ;;
    *)        PLATFORM="unknown" ;;
  esac
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
