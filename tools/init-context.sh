#!/usr/bin/env bash
# Claude Supercharger — Context Scaffolder
# Usage: bash tools/init-context.sh [--dir DIR] [--force]
# Scaffolds CLAUDE.md index stubs in subdirectories for efficient context navigation.
# Keep each CLAUDE.md under 200 tokens — it's a map, not documentation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()    { echo -e "  ${CYAN}→${NC} $1"; }
success() { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}!${NC} $1"; }

ARG_DIR=""
ARG_FORCE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)   ARG_DIR="$2"; shift 2 ;;
    --force) ARG_FORCE="true"; shift ;;
    --help)
      echo "Usage: bash tools/init-context.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --dir DIR    Target project directory (default: current directory)"
      echo "  --force      Overwrite existing CLAUDE.md files"
      echo "  --help       Show this help"
      echo ""
      echo "Creates CLAUDE.md index stubs in subdirectories."
      echo "Edit each file to describe what's in that directory."
      echo "Keep under 200 tokens — it's a map, not documentation."
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

PROJECT_DIR="${ARG_DIR:-$(pwd)}"
PROJECT_NAME=$(basename "$PROJECT_DIR")

# Directories to skip
SKIP_DIRS=("node_modules" ".git" ".next" ".nuxt" "dist" "build" "out" "__pycache__" ".cache"
           "coverage" ".nyc_output" "vendor" ".venv" "venv" "env" ".env" "target" ".cargo"
           ".github" ".husky" ".turbo" "tmp" "temp" "logs" ".claude")

echo ""
echo -e "${BOLD}Claude Supercharger — Context Scaffolder${NC}"
echo -e "${DIM}Project: $PROJECT_DIR${NC}"
echo ""

# Find code-containing subdirectories (one level only)
GENERATED=0
SKIPPED=0

for subdir in "$PROJECT_DIR"/*/; do
  [ -d "$subdir" ] || continue

  dirname=$(basename "$subdir")

  # Skip known non-code directories
  skip="false"
  for s in "${SKIP_DIRS[@]}"; do
    [[ "$dirname" == "$s" ]] && skip="true" && break
  done
  [[ "$skip" == "true" ]] && continue

  # Skip hidden directories
  [[ "$dirname" == .* ]] && continue

  TARGET="$subdir/CLAUDE.md"

  if [ -f "$TARGET" ] && [ "$ARG_FORCE" != "true" ]; then
    info "Skipping $dirname/CLAUDE.md (already exists)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Detect what kind of code is in this directory
  FILE_TYPES=""
  for ext in ts tsx js jsx py rs go php; do
    if ls "$subdir"*."$ext" 2>/dev/null | head -1 | grep -q .; then
      FILE_TYPES="$FILE_TYPES $ext"
    fi
  done

  # Count files
  FILE_COUNT=$(find "$subdir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')

  cat > "$TARGET" <<STUB
# ${dirname}/

<!-- CLAUDE.md: Keep this under 200 tokens. It's a map, not documentation. -->
<!-- Fill in: what this directory is for, key files, conventions to follow. -->

## Purpose
[What this directory is for — one sentence]

## Key files
<!-- List the 3-5 most important files and their role -->
- \`\`: [role]

## Conventions
<!-- Patterns unique to this directory that Claude should follow -->
- [convention]

## Triggers
<!-- When should Claude read this file? -->
- Tasks involving [this directory] → read this first
STUB

  success "Created $dirname/CLAUDE.md"
  GENERATED=$((GENERATED + 1))
done

echo ""
echo -e "${CYAN}────────────────────────────────────────${NC}"
echo -e "${GREEN}  Done!${NC} $GENERATED CLAUDE.md stub(s) created"
[ "$SKIPPED" -gt 0 ] && echo -e "  $SKIPPED skipped (already existed)"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "  1. Open each ${DIM}subdir/CLAUDE.md${NC} and fill in Purpose + Key files"
echo -e "  2. Keep each file under 200 tokens — brevity matters"
echo -e "  3. Claude will auto-load these as context when working in each directory"
echo ""
echo -e "  ${DIM}Tip: Run with --force to regenerate stubs after adding new directories${NC}"
echo ""
