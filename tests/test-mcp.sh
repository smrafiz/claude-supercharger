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

# --- Test 2: Developer role adds Magic UI by default; playwright/github are opt-in ---
begin_test "mcp: developer role adds magic-ui only (playwright/github opt-in via SUPERCHARGER_MCP_EXTRAS)"
setup_test_home
echo '{}' > "$HOME/.claude.json"
unset SUPERCHARGER_MCP_EXTRAS
merge_mcp_into_settings "developer" "light"
MU=$(has_mcp_server "magic-ui")
PW=$(has_mcp_server "playwright")
GH=$(has_mcp_server "github")
TOTAL=$(count_tagged_mcp)
if [ "$MU" = "yes" ] && [ "$PW" = "no" ] && [ "$GH" = "no" ] && [ "$TOTAL" -eq 2 ]; then
  pass
else
  fail "expected mu=yes pw=no gh=no total=2, got mu=$MU pw=$PW gh=$GH total=$TOTAL"
fi
teardown_test_home

begin_test "mcp: SUPERCHARGER_MCP_EXTRAS=sequential-thinking adds it role-agnostic"
setup_test_home
echo '{}' > "$HOME/.claude.json"
SUPERCHARGER_MCP_EXTRAS="sequential-thinking" merge_mcp_into_settings "developer" "light"
SEQ=$(has_mcp_server "sequential-thinking")
[ "$SEQ" = "yes" ] && pass || fail "sequential-thinking not added with extras flag"
teardown_test_home

begin_test "mcp: SUPERCHARGER_MCP_EXTRAS=memory adds it role-agnostic"
setup_test_home
echo '{}' > "$HOME/.claude.json"
SUPERCHARGER_MCP_EXTRAS="memory" merge_mcp_into_settings "writer" "light"
MEM=$(has_mcp_server "memory")
[ "$MEM" = "yes" ] && pass || fail "memory not added with extras flag for writer role"
teardown_test_home

begin_test "mcp: developer with SUPERCHARGER_MCP_EXTRAS=playwright,github adds them (when gh present)"
setup_test_home
echo '{}' > "$HOME/.claude.json"
SUPERCHARGER_MCP_EXTRAS="playwright,github" merge_mcp_into_settings "developer" "light"
PW=$(has_mcp_server "playwright")
MU=$(has_mcp_server "magic-ui")
TOTAL=$(count_tagged_mcp)
HAS_GH="no"; command -v gh &>/dev/null && HAS_GH="yes"
if [ "$HAS_GH" = "yes" ]; then EXPECTED=4; else EXPECTED=3; fi
if [ "$PW" = "yes" ] && [ "$MU" = "yes" ] && [ "$TOTAL" -eq "$EXPECTED" ]; then
  pass
else
  fail "expected pw=yes mu=yes total=$EXPECTED (gh=$HAS_GH), got pw=$PW mu=$MU total=$TOTAL"
fi
teardown_test_home

# --- Test 3: Writer role — no extra servers (duckduckgo removed, WebSearch is native) ---
begin_test "mcp: writer role has only context7 (duckduckgo removed, WebSearch is native)"
setup_test_home
echo '{}' > "$HOME/.claude.json"
merge_mcp_into_settings "writer" "light"
DDG=$(has_mcp_server "duckduckgo-search")
TOTAL=$(count_tagged_mcp)
if [ "$DDG" = "no" ] && [ "$TOTAL" -eq 1 ]; then
  pass
else
  fail "expected duckduckgo=no total=1, got duckduckgo=$DDG total=$TOTAL"
fi
teardown_test_home

# --- Test 4: Multi-role — developer+pm same as developer alone (no extra servers) ---
begin_test "mcp: developer+pm same server count as developer alone"
setup_test_home
echo '{}' > "$HOME/.claude.json"
unset SUPERCHARGER_MCP_EXTRAS
merge_mcp_into_settings "developer,pm" "light"
TOTAL=$(count_tagged_mcp)
# default developer (no extras) = context7 + magic-ui = 2
if [ "$TOTAL" -eq 2 ]; then
  pass
else
  fail "expected total=2, got total=$TOTAL"
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

# Helper: print one tagged server's entry as JSON
mcp_entry() {
  SETTINGS_PATH="$HOME/.claude.json" MCP_NAME="$1" python3 -c "
import json, os
s = json.load(open(os.environ['SETTINGS_PATH']))
print(json.dumps(s.get('mcpServers', {}).get(os.environ['MCP_NAME'] + ' #supercharger'), sort_keys=True))
" 2>/dev/null
}

# --- Test 9: Research profile adds DeepWiki as a remote server, not the retired pair ---
begin_test "mcp: research profile adds deepwiki (remote), not sequential-thinking or memory"
setup_test_home
echo '{}' > "$HOME/.claude.json"
merge_mcp_into_settings "developer" "research"
DW=$(mcp_entry deepwiki)
SEQ=$(has_mcp_server "sequential-thinking")
MEM=$(has_mcp_server "memory")
if [ "$DW" = '{"type": "http", "url": "https://mcp.deepwiki.com/mcp"}' ] && [ "$SEQ" = "no" ] && [ "$MEM" = "no" ]; then
  pass
else
  fail "research: expected deepwiki http entry, seq=no mem=no; got dw=$DW seq=$SEQ mem=$MEM"
fi
teardown_test_home

# --- Test 10: an update keeps the retired pair a research user already has ---
begin_test "mcp: reinstall in research keeps existing sequential-thinking/memory; light drops them"
setup_test_home
echo '{"mcpServers":{"sequential-thinking #supercharger":{"command":"npx","args":["-y","@modelcontextprotocol/server-sequential-thinking"]},"memory #supercharger":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}' > "$HOME/.claude.json"
merge_mcp_into_settings "developer" "full"
KEPT="$(has_mcp_server sequential-thinking)$(has_mcp_server memory)"
merge_mcp_into_settings "developer" "light"
GONE="$(has_mcp_server sequential-thinking)$(has_mcp_server memory)"
if [ "$KEPT" = "yesyes" ] && [ "$GONE" = "nono" ]; then
  pass
else
  fail "expected kept=yesyes then gone=nono, got kept=$KEPT gone=$GONE"
fi
teardown_test_home

# --- Test 10b: keyed servers from mcp-setup survive a reinstall and a profile switch ---
# Before 4.4.3 every reinstall (so every /sc-update) wiped them: they carry the tag.
begin_test "mcp: reinstall and profile switch keep the user's keyed servers"
setup_test_home
echo '{"mcpServers":{"notion #supercharger":{"command":"npx","args":["-y","@notionhq/notion-mcp-server"],"env":{"NOTION_TOKEN":"fixture-not-a-secret"}},"figma #supercharger":{"type":"http","url":"https://mcp.figma.com/mcp"}}}' > "$HOME/.claude.json"
merge_mcp_into_settings "developer" "light"
merge_mcp_into_settings "developer" "research"
NO=$(mcp_entry notion); FG=$(mcp_entry figma)
case "$NO|$FG" in
  *fixture-not-a-secret*'|{"type": "http", "url": "https://mcp.figma.com/mcp"}') pass ;;
  *) fail "keyed servers lost: notion=$NO figma=$FG" ;;
esac
teardown_test_home

# --- Test 10b2: a reinstall renames the variables pre-4.4.3 setups stored wrongly ---
begin_test "mcp: reinstall renames old wrong key variables to the ones packages read"
setup_test_home
echo '{"mcpServers":{"notion #supercharger":{"command":"npx","args":["-y","@notionhq/notion-mcp-server"],"env":{"NOTION_API_KEY":"k1"}},"sentry #supercharger":{"command":"npx","args":["-y","@sentry/mcp-server"],"env":{"SENTRY_AUTH_TOKEN":"k2"}},"figma #supercharger":{"command":"npx","args":["-y","figma-developer-mcp"],"env":{"FIGMA_ACCESS_TOKEN":"k3"}},"slack #supercharger":{"command":"npx","args":["-y","slack-mcp-server"],"env":{"SLACK_BOT_TOKEN":"k4"}},"mine":{"command":"x","env":{"SLACK_BOT_TOKEN":"user"}}}}' > "$HOME/.claude.json"
merge_mcp_into_settings "developer" "light"
GOT="$(mcp_entry notion)$(mcp_entry sentry)$(mcp_entry figma)$(mcp_entry slack)"
MINE=$(SETTINGS_PATH="$HOME/.claude.json" python3 -c "import json,os;print(json.dumps(json.load(open(os.environ['SETTINGS_PATH']))['mcpServers']['mine']['env']))")
if [ "$GOT" = '{"args": ["-y", "@notionhq/notion-mcp-server"], "command": "npx", "env": {"NOTION_TOKEN": "k1"}}{"args": ["-y", "@sentry/mcp-server"], "command": "npx", "env": {"SENTRY_ACCESS_TOKEN": "k2"}}{"args": ["-y", "figma-developer-mcp"], "command": "npx", "env": {"FIGMA_API_KEY": "k3"}}{"args": ["-y", "slack-mcp-server"], "command": "npx", "env": {"SLACK_MCP_XOXB_TOKEN": "k4"}}' ] \
   && [ "$MINE" = '{"SLACK_BOT_TOKEN": "user"}' ]; then
  pass
else
  fail "got: $GOT | user server env: $MINE"
fi
teardown_test_home

# --- Test 10c: mcp-setup writes official packages, the env names they read, and remote sign-in ---
begin_test "mcp-setup: brave key, notion browser sign-in, correct variable names"
setup_test_home
echo '{}' > "$HOME/.claude.json"; echo '{}' > "$HOME/.claude/settings.json"
# y brave, y notion, n sentry, n figma, n slack; brave key; Enter for notion = sign-in
printf 'y\ny\nn\nn\nn\nfixture-brave\n\n' | bash "$REPO_DIR/tools/mcp-setup.sh" >/dev/null 2>&1
BR=$(mcp_entry brave-search); NO=$(mcp_entry notion)
if [ "$BR" = '{"args": ["-y", "@brave/brave-search-mcp-server"], "command": "npx", "env": {"BRAVE_API_KEY": "fixture-brave"}}' ] \
   && [ "$NO" = '{"type": "http", "url": "https://mcp.notion.com/mcp"}' ]; then
  pass
else
  fail "brave=$BR notion=$NO"
fi
teardown_test_home

# --- Test 10d: the token path writes the variable each package actually reads ---
begin_test "mcp-setup: sentry, figma and slack tokens use the names their packages read"
setup_test_home
echo '{}' > "$HOME/.claude.json"; echo '{}' > "$HOME/.claude/settings.json"
printf 'n\ny\ny\ny\ny\nt1\nt2\nt3\nt4\n' | bash "$REPO_DIR/tools/mcp-setup.sh" >/dev/null 2>&1
GOT="$(mcp_entry notion | grep -o NOTION_TOKEN)$(mcp_entry sentry | grep -o SENTRY_ACCESS_TOKEN)$(mcp_entry figma | grep -o FIGMA_API_KEY)$(mcp_entry slack | grep -o SLACK_MCP_XOXB_TOKEN)"
[ "$GOT" = "NOTION_TOKENSENTRY_ACCESS_TOKENFIGMA_API_KEYSLACK_MCP_XOXB_TOKEN" ] && pass || fail "got: $GOT"
teardown_test_home

# --- Test 10e: dev and full add Playwright and Magic UI for any role (menu promise) ---
begin_test "mcp: dev and full profiles add playwright and magic-ui for a writer; full adds deepwiki"
setup_test_home
echo '{}' > "$HOME/.claude.json"
merge_mcp_into_settings "writer" "dev"
DEV="$(has_mcp_server playwright)$(has_mcp_server magic-ui)$(has_mcp_server deepwiki)"
merge_mcp_into_settings "writer" "full"
FULL="$(has_mcp_server playwright)$(has_mcp_server magic-ui)$(has_mcp_server deepwiki)"
if [ "$DEV" = "yesyesno" ] && [ "$FULL" = "yesyesyes" ]; then
  pass
else
  fail "expected dev=yesyesno full=yesyesyes, got dev=$DEV full=$FULL"
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
