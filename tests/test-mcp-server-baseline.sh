#!/usr/bin/env bash
# v4.1.31: config-scan records each project .mcp.json stdio server's command and
# warns when one is added or changed after the first sighting (a git pull can swap
# a server between sessions; the risk check stays quiet for npx/uvx launchers).
# Also: SessionStart hands Claude Code the git-root watch paths (watchPaths).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
HOOK="$REPO_DIR/hooks/config-scan.sh"
echo "=== MCP Server Baseline Tests ==="

ST=$(mktemp -d); P=$(mktemp -d); git -C "$P" init -q; mkdir -p "$P/sub"
# cwd is a native path, as Claude Code sends it: native Windows python cannot read /tmp/x.
scan() { printf '{"cwd":"%s","session_id":"s","hook_event_name":"SessionStart","source":"startup"}' "$(native_path "${1:-$P}")" \
  | SUPERCHARGER_STATE="$ST" bash "$HOOK" 2>/dev/null; }

printf '{"mcpServers":{"docs":{"command":"npx","args":["-y","good-mcp"]}}}' > "$P/.mcp.json"
begin_test "mcp-baseline: first sighting records, no security warning"
OUT=$(scan); echo "$OUT" | grep -q 'since last session' && fail "warned on first sight: $OUT" || pass
begin_test "mcp-baseline: unchanged servers stay silent"
OUT=$(scan); echo "$OUT" | grep -q 'since last session' && fail "warned when unchanged: $OUT" || pass

printf '{"mcpServers":{"docs":{"command":"npx","args":["-y","evil-mcp"]},"x":{"command":"uvx","args":["y"]}}}' > "$P/.mcp.json"
OUT=$(scan)
begin_test "mcp-baseline: a changed server command warns"
echo "$OUT" | grep -q "command changed since last session: 'docs'" && pass || fail "no change warning: $OUT"
begin_test "mcp-baseline: a new server warns"
echo "$OUT" | grep -q "new server since last session: 'x'" && pass || fail "no new-server warning: $OUT"

begin_test "watchPaths: SessionStart names the git-root files, from a subdirectory"
OUT=$(scan "$P/sub")
echo "$OUT" | python3 -c '
import json, os, sys
d = json.load(sys.stdin); w = d["hookSpecificOutput"]["watchPaths"]
root = os.path.realpath(sys.argv[1])
need = [os.path.join(root, r) for r in (".mcp.json", ".claude/settings.json", ".supercharger.json")]
sys.exit(0 if all(n in w for n in need) else 1)' "$P" && pass || fail "watchPaths missing git-root files: $OUT"

rm -rf "$ST" "$P"
report
