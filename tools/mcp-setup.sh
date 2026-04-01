#!/usr/bin/env bash
set -eo pipefail
umask 077

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SETTINGS_FILE="$HOME/.claude/settings.json"
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
echo -e "${CYAN}  Advanced MCP Servers (API key required)  ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""

ORDERED_SERVERS=("github" "brave-search" "slack" "neon" "notion" "prisma" "sentry" "figma")

declare -A SERVER_LABELS=(
  ["github"]="GitHub (Personal Access Token)"
  ["brave-search"]="Brave Search (API Key — free: 2K/mo)"
  ["slack"]="Slack (Bot Token)"
  ["neon"]="Neon (Connection String)"
  ["notion"]="Notion (API Key)"
  ["prisma"]="Prisma (project CLI — no key)"
  ["sentry"]="Sentry (Auth Token)"
  ["figma"]="Figma (Access Token)"
)

declare -A SERVER_CMDS=(
  ["github"]="-y @modelcontextprotocol/server-github"
  ["brave-search"]="-y @modelcontextprotocol/server-brave-search"
  ["slack"]="-y @modelcontextprotocol/server-slack"
  ["neon"]="-y @neondatabase/mcp-server-neon"
  ["notion"]="-y @notionhq/notion-mcp-server"
  ["prisma"]="prisma mcp"
  ["sentry"]="-y @sentry/mcp-server"
  ["figma"]="-y @anthropic/figma-mcp-server"
)

declare -A SERVER_ENV_KEYS=(
  ["github"]="GITHUB_PERSONAL_ACCESS_TOKEN"
  ["brave-search"]="BRAVE_API_KEY"
  ["slack"]="SLACK_BOT_TOKEN"
  ["neon"]="DATABASE_URL"
  ["notion"]="NOTION_API_KEY"
  ["sentry"]="SENTRY_AUTH_TOKEN"
  ["figma"]="FIGMA_ACCESS_TOKEN"
)

echo "Select servers to configure (enter y/n for each):"
echo ""

SELECTED=()
for server in "${ORDERED_SERVERS[@]}"; do
  read -rp "  ${SERVER_LABELS[$server]}? [y/N]: " -n 1
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    SELECTED+=("$server")
  fi
done

if [ ${#SELECTED[@]} -eq 0 ]; then
  echo ""
  echo -e "${YELLOW}No servers selected.${NC}"
  exit 0
fi

echo ""

add_server() {
  local name="$1"
  local args="$2"
  local env_json="${3:-}"

  MCP_NAME="$name" MCP_TAG="$TAG" MCP_ARGS="$args" MCP_ENV="$env_json" SETTINGS_FILE="$SETTINGS_FILE" \
  python3 -c "
import json, os

settings_file = os.environ['SETTINGS_FILE']
name = os.environ['MCP_NAME']
tag = os.environ['MCP_TAG']
args = os.environ['MCP_ARGS'].split()
env_str = os.environ.get('MCP_ENV', '')

with open(settings_file, 'r') as f:
    settings = json.load(f)

if 'mcpServers' not in settings:
    settings['mcpServers'] = {}

key = name + ' ' + tag
entry = {'command': 'npx', 'args': args}
if env_str:
    entry['env'] = json.loads(env_str)

settings['mcpServers'][key] = entry

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>/dev/null
}

for server in "${SELECTED[@]}"; do
  args="${SERVER_CMDS[$server]}"

  if [ "$server" = "prisma" ]; then
    echo -e "${BLUE}Configuring Prisma (no key needed)...${NC}"
    add_server "$server" "$args"
    echo -e "  ${GREEN}✓${NC} $server configured"
    continue
  fi

  env_key="${SERVER_ENV_KEYS[$server]:-}"
  if [ -n "$env_key" ]; then
    read -rsp "  Enter ${SERVER_LABELS[$server]%% (*} key (or Enter to skip): " secret
    echo
    if [ -n "$secret" ]; then
      env_json=$(MCP_USER_SECRET="$secret" MCP_ENV_KEY="$env_key" python3 -c "
import json, os
print(json.dumps({os.environ['MCP_ENV_KEY']: os.environ['MCP_USER_SECRET']}))
" 2>/dev/null)
      add_server "$server" "$args" "$env_json"
      echo -e "  ${GREEN}✓${NC} $server configured"
    else
      echo -e "  ${YELLOW}○${NC} $server skipped"
    fi
  fi
done

echo ""
echo -e "${GREEN}Done!${NC} Restart Claude Code to activate new servers."
echo ""
