#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

source "$REPO_DIR/lib/mcp.sh"

# Helper: count MCP entries with supercharger tag in settings.json
count_tagged_mcp() {
  SETTINGS_PATH="$HOME/.claude.json" python3 -c "
import json, os
with open(os.environ['SETTINGS_PATH']) as f:
    s = json.load(f)
count = sum(1 for k in s.get('mcpServers', {}) if '#supercharger' in k)
print(count)
" 2>/dev/null || echo "0"
}

# Helper: check if a specific server name exists (tagged)
has_mcp_server() {
  local name="$1"
  SETTINGS_PATH="$HOME/.claude.json" MCP_NAME="$name" python3 -c "
import json, os
with open(os.environ['SETTINGS_PATH']) as f:
    s = json.load(f)
name = os.environ['MCP_NAME']
found = any(name in k and '#supercharger' in k for k in s.get('mcpServers', {}))
print('yes' if found else 'no')
" 2>/dev/null || echo "no"
}

# Helper: check if a specific server name exists (untagged, user's own)
has_user_mcp_server() {
  local name="$1"
  SETTINGS_PATH="$HOME/.claude.json" MCP_NAME="$name" python3 -c "
import json, os
with open(os.environ['SETTINGS_PATH']) as f:
    s = json.load(f)
name = os.environ['MCP_NAME']
found = any(k == name for k in s.get('mcpServers', {}))
print('yes' if found else 'no')
" 2>/dev/null || echo "no"
}

# --- Test 1: Core servers present ---
begin_test "mcp: core servers present after install (light profile)"
setup_test_home
echo '{}' > "$HOME/.claude.json"
merge_mcp_into_settings "writer" "light"
CTX=$(has_mcp_server "context7")
SEQ=$(has_mcp_server "sequential-thinking")
MEM=$(has_mcp_server "memory")
if [ "$CTX" = "yes" ] && [ "$SEQ" = "no" ] && [ "$MEM" = "no" ]; then
  pass
else
  fail "light profile: expected ctx=yes seq=no mem=no, got ctx=$CTX seq=$SEQ mem=$MEM"
fi
teardown_test_home

# --- Test 2: Developer role adds Playwright + Magic UI (+ GitHub if gh CLI present) ---
begin_test "mcp: developer role adds playwright and magic-ui (light profile)"
setup_test_home
echo '{}' > "$HOME/.claude.json"
merge_mcp_into_settings "developer" "light"
PW=$(has_mcp_server "playwright")
MU=$(has_mcp_server "magic-ui")
TOTAL=$(count_tagged_mcp)
HAS_GH="no"
command -v gh &>/dev/null && HAS_GH="yes"
if [ "$HAS_GH" = "yes" ]; then EXPECTED=4; else EXPECTED=3; fi
if [ "$PW" = "yes" ] && [ "$MU" = "yes" ] && [ "$TOTAL" -eq "$EXPECTED" ]; then
  pass
else
  fail "expected pw=yes mu=yes total=$EXPECTED (gh=$HAS_GH), got total=$TOTAL"
fi
teardown_test_home

# --- Test 3: Writer role adds DuckDuckGo ---
begin_test "mcp: writer role adds duckduckgo-search (light profile)"
setup_test_home
echo '{}' > "$HOME/.claude.json"
merge_mcp_into_settings "writer" "light"
DDG=$(has_mcp_server "duckduckgo-search")
TOTAL=$(count_tagged_mcp)
if [ "$DDG" = "yes" ] && [ "$TOTAL" -eq 2 ]; then
  pass
else
  fail "expected duckduckgo=yes total=2, got duckduckgo=$DDG total=$TOTAL"
fi
teardown_test_home

# --- Test 4: Multi-role deduplication ---
begin_test "mcp: developer+pm deduplicates duckduckgo-search (light profile)"
setup_test_home
echo '{}' > "$HOME/.claude.json"
merge_mcp_into_settings "developer,pm" "light"
TOTAL=$(count_tagged_mcp)
DDG_COUNT=$(SETTINGS_PATH="$HOME/.claude.json" python3 -c "
import json, os
with open(os.environ['SETTINGS_PATH']) as f:
    s = json.load(f)
print(sum(1 for k in s.get('mcpServers', {}) if 'duckduckgo' in k))
" 2>/dev/null || echo "0")
HAS_GH="no"
command -v gh &>/dev/null && HAS_GH="yes"
if [ "$HAS_GH" = "yes" ]; then EXPECTED=5; else EXPECTED=4; fi
if [ "$TOTAL" -eq "$EXPECTED" ] && [ "$DDG_COUNT" -eq 1 ]; then
  pass
else
  fail "expected total=$EXPECTED ddg_count=1, got total=$TOTAL ddg=$DDG_COUNT"
fi
teardown_test_home

# --- Test 5: Uninstall removes only supercharger MCP entries ---
begin_test "mcp: uninstall removes only supercharger entries"
setup_test_home
echo '{"mcpServers":{"my-custom-server":{"command":"npx","args":["-y","my-server"]}}}' > "$HOME/.claude.json"
merge_mcp_into_settings "writer" "light"
remove_supercharger_mcp
TAGGED=$(count_tagged_mcp)
CUSTOM=$(has_user_mcp_server "my-custom-server")
if [ "$TAGGED" -eq 0 ] && [ "$CUSTOM" = "yes" ]; then
  pass
else
  fail "expected tagged=0 custom=yes, got tagged=$TAGGED custom=$CUSTOM"
fi
teardown_test_home

# --- Test 6: User's existing MCP servers preserved after install ---
begin_test "mcp: user MCP servers preserved after install"
setup_test_home
echo '{"mcpServers":{"my-server":{"command":"npx","args":["-y","@my/server"]}}}' > "$HOME/.claude.json"
merge_mcp_into_settings "developer" "light"
CUSTOM=$(has_user_mcp_server "my-server")
if [ "$CUSTOM" = "yes" ]; then
  pass
else
  fail "user server was removed"
fi
teardown_test_home

# --- Test 7: User's existing MCP servers preserved after uninstall ---
begin_test "mcp: user MCP servers preserved after uninstall"
setup_test_home
echo '{"mcpServers":{"my-server":{"command":"npx","args":["-y","@my/server"]}}}' > "$HOME/.claude.json"
merge_mcp_into_settings "writer" "light"
remove_supercharger_mcp
CUSTOM=$(has_user_mcp_server "my-server")
if [ "$CUSTOM" = "yes" ]; then
  pass
else
  fail "user server was removed after uninstall"
fi
teardown_test_home

# --- Test 8: Idempotent — no duplicates after double install ---
begin_test "mcp: idempotent — no duplicates after double install"
setup_test_home
echo '{}' > "$HOME/.claude.json"
merge_mcp_into_settings "developer" "light"
FIRST=$(count_tagged_mcp)
merge_mcp_into_settings "developer" "light"
SECOND=$(count_tagged_mcp)
if [ "$FIRST" -eq "$SECOND" ]; then
  pass
else
  fail "expected $FIRST servers both times, got $SECOND after second install"
fi
teardown_test_home

# --- Test 9: Research profile includes memory and sequential-thinking ---
begin_test "mcp: research profile includes memory and sequential-thinking"
setup_test_home
echo '{}' > "$HOME/.claude.json"
merge_mcp_into_settings "developer" "research"
SEQ=$(has_mcp_server "sequential-thinking")
MEM=$(has_mcp_server "memory")
CTX=$(has_mcp_server "context7")
if [ "$SEQ" = "yes" ] && [ "$MEM" = "yes" ] && [ "$CTX" = "yes" ]; then
  pass
else
  fail "research profile: expected seq=yes mem=yes ctx=yes, got seq=$SEQ mem=$MEM ctx=$CTX"
fi
teardown_test_home

# --- Test 10: Full profile includes research servers ---
begin_test "mcp: full profile includes research servers"
setup_test_home
echo '{}' > "$HOME/.claude.json"
merge_mcp_into_settings "developer" "full"
SEQ=$(has_mcp_server "sequential-thinking")
MEM=$(has_mcp_server "memory")
if [ "$SEQ" = "yes" ] && [ "$MEM" = "yes" ]; then
  pass
else
  fail "full profile: expected seq=yes mem=yes, got seq=$SEQ mem=$MEM"
fi
teardown_test_home

# --- Test 11: Light profile excludes memory and sequential-thinking ---
begin_test "mcp: light profile excludes memory and sequential-thinking"
setup_test_home
echo '{}' > "$HOME/.claude.json"
merge_mcp_into_settings "developer" "light"
SEQ=$(has_mcp_server "sequential-thinking")
MEM=$(has_mcp_server "memory")
if [ "$SEQ" = "no" ] && [ "$MEM" = "no" ]; then
  pass
else
  fail "light profile should not include seq/mem, got seq=$SEQ mem=$MEM"
fi
teardown_test_home

# --- Test 12: Designer role gets magic-ui without playwright ---
begin_test "mcp: designer role gets magic-ui but not playwright"
setup_test_home
echo '{}' > "$HOME/.claude.json"
merge_mcp_into_settings "designer" "light"
MU=$(has_mcp_server "magic-ui")
PW=$(has_mcp_server "playwright")
if [ "$MU" = "yes" ] && [ "$PW" = "no" ]; then
  pass
else
  fail "designer: expected mu=yes pw=no, got mu=$MU pw=$PW"
fi
teardown_test_home

report
