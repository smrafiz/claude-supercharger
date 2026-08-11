#!/usr/bin/env bash
# Guards against version drift across the files a release must bump together.
# Source of truth: lib/utils.sh VERSION. Every other version-bearing file must match.
# (Added after .claude-plugin manifests drifted 15 releases behind — 2.20.1 vs 2.23.35 —
#  because the bump flow skipped them.)
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Version Parity Tests ==="

# Source of truth
V=$(grep -m1 '^VERSION=' "$REPO_DIR/lib/utils.sh" | sed 's/.*"\(.*\)".*/\1/')

begin_test "lib/utils.sh VERSION is set and semver-shaped"
if printf '%s' "$V" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then pass; else fail "bad VERSION: '$V'"; fi

eq() { # label  actual  (compares to $V)
  begin_test "$1 matches lib/utils.sh ($V)"
  if [ "$2" = "$V" ]; then pass; else fail "expected '$V' got '$2'"; fi
}

# tools/supercharger.sh
SC=$(grep -m1 '^VERSION=' "$REPO_DIR/tools/supercharger.sh" | sed 's/.*"\(.*\)".*/\1/')
eq "tools/supercharger.sh VERSION" "$SC"

# .claude-plugin/plugin.json  .version
PJ=$(python3 -c "import sys, json;print(json.load(open(sys.argv[1]))['version'])" "$REPO_DIR/.claude-plugin/plugin.json" 2>/dev/null)
eq "plugin.json .version" "$PJ"

# .claude-plugin/marketplace.json  .metadata.version  and  .plugins[0].version
MM=$(python3 -c "import sys, json;print(json.load(open(sys.argv[1]))['metadata']['version'])" "$REPO_DIR/.claude-plugin/marketplace.json" 2>/dev/null)
eq "marketplace.json .metadata.version" "$MM"
MP=$(python3 -c "import sys, json;print(json.load(open(sys.argv[1]))['plugins'][0]['version'])" "$REPO_DIR/.claude-plugin/marketplace.json" 2>/dev/null)
eq "marketplace.json .plugins[0].version" "$MP"

# README badge  version-X-blue
RB=$(grep -oE 'version-[0-9]+\.[0-9]+\.[0-9]+-blue' "$REPO_DIR/README.md" | head -1 | sed 's/version-\(.*\)-blue/\1/')
eq "README version badge" "$RB"

report
