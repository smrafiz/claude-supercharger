#!/usr/bin/env bash
# Claude Supercharger — MCP Server Setup
# Interactive installer for the bundled MCP server profiles.
set -eo pipefail

# Windows python defaults stdout to the ANSI codepage (cp1252) and raises
# UnicodeEncodeError on the box-drawing and arrow characters this tool prints,
# losing ALL of its output. Hooks get this from hooks/lib-paths.sh; tools do not
# reach that file, so they set it themselves. `:=` honours an explicit setting.
: "${PYTHONIOENCODING:=utf-8}"
: "${PYTHONUTF8:=1}"
export PYTHONIOENCODING PYTHONUTF8
umask 077

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
# shellcheck disable=SC2034
RED='\033[0;31m'
CYAN='\033[0;36m'
# shellcheck disable=SC2034
BOLD='\033[1m'
NC='\033[0m'

SETTINGS_FILE="$HOME/.claude.json"
SETTINGS_FILE_LEGACY="$HOME/.claude/settings.json"
TAG="#supercharger"

echo -e "${CYAN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Claude Supercharger — MCP Server Setup   ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════╝${NC}"
echo ""

if [ ! -f "$SETTINGS_FILE" ]; then
  echo -e "${YELLOW}No settings.json found. Run install.sh first.${NC}"
  exit 1
fi

# Show currently configured servers
echo -e "${BLUE}Currently configured MCP servers:${NC}"
SETTINGS_FILE="$SETTINGS_FILE" MCP_TAG="$TAG" python3 -c "
import json, os
with open(os.environ['SETTINGS_FILE']) as f:
    s = json.load(f)
tag = os.environ['MCP_TAG']
servers = s.get('mcpServers', {})
if not servers:
    print('  (none)')
else:
    for k in sorted(servers):
        label = ' (Supercharger)' if tag in k else ' (user)'
        name = k.replace(' ' + tag, '')
        print(f'  - {name}{label}')
" 2>/dev/null
echo ""

echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}  Advanced MCP Servers (key or sign-in)    ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""

# Parallel indexed arrays (Bash 3 compatible — no declare -A)
SERVER_NAMES=("brave-search" "notion" "sentry" "figma" "slack")
SERVER_LABELS=(
  "Brave Search (API Key — free: 2K/mo)"
  "Notion (Integration Token, or browser sign-in)"
  "Sentry (browser sign-in, or Access Token)"
  "Figma (browser sign-in, or Personal Access Token)"
  "Slack (Bot Token — no admin approval needed)"
)
# Brave, Notion and Sentry are the vendors' own packages; figma-developer-mcp and
# slack-mcp-server are community ones (no official local package). Each variable
# name is the one its package reads: a wrong name gives a server that starts and fails.
SERVER_CMDS=(
  "-y @brave/brave-search-mcp-server"
  "-y @notionhq/notion-mcp-server"
  "-y @sentry/mcp-server"
  "-y figma-developer-mcp"
  "-y slack-mcp-server"
)
SERVER_ENV_KEYS=(
  "BRAVE_API_KEY"
  "NOTION_TOKEN"
  "SENTRY_ACCESS_TOKEN"
  "FIGMA_API_KEY"
  "SLACK_MCP_XOXB_TOKEN"
)
# The vendor's own remote server: pressing Enter at the key prompt adds this and
# Claude Code signs in through the browser on first use. Empty = key only.
SERVER_REMOTE=(
  ""
  "https://mcp.notion.com/mcp"
  "https://mcp.sentry.dev/mcp"
  "https://mcp.figma.com/mcp"
  ""
)

# Note: GitHub MCP is now Docker-based (ghcr.io/github/github-mcp-server)
# and Neon MCP uses a remote server (mcp.neon.tech) — both require manual setup.
# Run: claude mcp add github -- docker run -i ghcr.io/github/github-mcp-server
# See: https://github.com/github/github-mcp-server for details.

echo "Select servers to configure (enter y/n for each):"
echo ""

SELECTED=()
for i in "${!SERVER_NAMES[@]}"; do
  read -rp "  ${SERVER_LABELS[$i]}? [y/N]: " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    SELECTED+=("$i")
  fi
done

if [ ${#SELECTED[@]} -eq 0 ]; then
  echo ""
  echo -e "${YELLOW}No servers selected.${NC}"
  exit 0
fi

echo ""

_add_server_to_file() {
  local settings_file="$1"
  local name="$2"
  local args="$3"
  local env_json="${4:-}"
  local url="${5:-}"

  [ -f "$settings_file" ] || return 0

  MCP_NAME="$name" MCP_TAG="$TAG" MCP_ARGS="$args" MCP_ENV="$env_json" MCP_URL="$url" SETTINGS_FILE="$settings_file" \
  python3 -c "
import json, os

settings_file = os.environ['SETTINGS_FILE']
name = os.environ['MCP_NAME']
tag = os.environ['MCP_TAG']
args = os.environ['MCP_ARGS'].split()
env_str = os.environ.get('MCP_ENV', '')
url = os.environ.get('MCP_URL', '')

with open(settings_file, 'r') as f:
    settings = json.load(f)

if 'mcpServers' not in settings:
    settings['mcpServers'] = {}

key = name + ' ' + tag
entry = {'type': 'http', 'url': url} if url else {'command': 'npx', 'args': args}
if env_str and not url:
    entry['env'] = json.loads(env_str)

settings['mcpServers'][key] = entry

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>/dev/null
}

add_server() {
  local name="$1"
  local args="$2"
  local env_json="${3:-}"
  local url="${4:-}"
  _add_server_to_file "$SETTINGS_FILE" "$name" "$args" "$env_json" "$url"
  _add_server_to_file "$SETTINGS_FILE_LEGACY" "$name" "$args" "$env_json" "$url"
}

for idx in "${SELECTED[@]}"; do
  server="${SERVER_NAMES[$idx]}"
  args="${SERVER_CMDS[$idx]}"
  env_key="${SERVER_ENV_KEYS[$idx]}"
  label="${SERVER_LABELS[$idx]}"
  remote="${SERVER_REMOTE[$idx]}"

  if [ -n "$env_key" ]; then
    secret=""
    if [ -n "$remote" ]; then
      # A Notion integration token reaches only the pages shared with it; signing
      # in grants the server everything the account can see.
      [ "$server" = "notion" ] && echo -e "  ${YELLOW}Note:${NC} browser sign-in lets Notion's server see every page your account can; a token sees only pages you share with it."
      read -rsp "  Enter ${label%% (*} token (or Enter to sign in through your browser): " secret
    else
      read -rsp "  Enter ${label%% (*} key (or Enter to skip): " secret
    fi
    echo
    if [ -n "$secret" ]; then
      env_json=$(MCP_USER_SECRET="$secret" MCP_ENV_KEY="$env_key" python3 -c "
import json, os
print(json.dumps({os.environ['MCP_ENV_KEY']: os.environ['MCP_USER_SECRET']}))
" 2>/dev/null)
      add_server "$server" "$args" "$env_json"
      echo -e "  ${GREEN}✓${NC} $server configured"
    elif [ -n "$remote" ]; then
      add_server "$server" "" "" "$remote"
      echo -e "  ${GREEN}✓${NC} $server configured (signs in through your browser on first use)"
    else
      echo -e "  ${YELLOW}○${NC} $server skipped"
    fi
  fi
done

# Restrict permissions on settings files containing API keys
chmod 600 "$SETTINGS_FILE" 2>/dev/null || true
chmod 600 "$SETTINGS_FILE_LEGACY" 2>/dev/null || true

echo ""
echo -e "${GREEN}Done!${NC} Restart Claude Code to activate new servers."
echo ""
