#!/usr/bin/env bash
# Claude Supercharger — Version Bump Tool
# Usage: bash tools/bump-version.sh <new-version>
# Example: bash tools/bump-version.sh 2.1.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

NEW="${1:-}"
if [ -z "$NEW" ]; then
  echo "Usage: bash tools/bump-version.sh <new-version>"
  echo "Example: bash tools/bump-version.sh 2.1.0"
  exit 1
fi

if ! printf '%s\n' "$NEW" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo -e "${RED}Error:${NC} version must be semver format (e.g. 2.1.0), got: $NEW"
  exit 1
fi

OLD=$(grep -m1 '^VERSION=' "$REPO_DIR/lib/utils.sh" | tr -d '"' | cut -d= -f2)

if [ "$OLD" = "$NEW" ]; then
  echo -e "${RED}Error:${NC} new version ($NEW) is the same as current ($OLD)"
  exit 1
fi

echo -e "${BOLD}Bumping $OLD → $NEW${NC}"
echo ""

# lib/utils.sh
sed -i.bak "s/^VERSION=\"$OLD\"/VERSION=\"$NEW\"/" "$REPO_DIR/lib/utils.sh"
rm -f "$REPO_DIR/lib/utils.sh.bak"
echo -e "  ${GREEN}✓${NC} lib/utils.sh"

# tools/supercharger.sh
sed -i.bak "s/^VERSION=\"$OLD\"/VERSION=\"$NEW\"/" "$REPO_DIR/tools/supercharger.sh"
rm -f "$REPO_DIR/tools/supercharger.sh.bak"
echo -e "  ${GREEN}✓${NC} tools/supercharger.sh"

# README.md — version badge
sed -i.bak "s/version-${OLD}-blue/version-${NEW}-blue/" "$REPO_DIR/README.md"
rm -f "$REPO_DIR/README.md.bak"
echo -e "  ${GREEN}✓${NC} README.md (version badge)"

echo ""
echo -e "${BOLD}CHANGELOG.md — add entry manually:${NC}"
echo "  - [${NEW}] - $(date +%Y-%m-%d) — <description>"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  git add lib/utils.sh tools/supercharger.sh README.md CHANGELOG.md"
echo "  git commit -m \"chore: bump version to $NEW\""
echo "  git tag v$NEW && git push && git push --tags"
