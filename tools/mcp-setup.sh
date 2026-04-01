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

# Parallel indexed arrays (Bash 3 compatible — no declare -A)
SERVER_NAMES=("github" "brave-search" "slack" "neon" "notion" "prisma" "sentry" "figma")
SERVER_LABELS=(
  "GitHub (Personal Access Token)"
  "Brave Search (API Key — free: 2K/mo)"
  "Slack (Bot Token)"
  "Neon (Connection String)"
  "Notion (API Key)"
  "Prisma (project CLI — no key)"
  "Sentry (Auth Token)"
  "Figma (Access Token)"
)
SERVER_CMDS=(
  "-y @modelcontextprotocol/server-github"
  "-y @modelcontextprotocol/server-brave-search"
  "-y @modelcontextprotocol/server-slack"
  "-y @neondatabase/mcp-server-neon"
  "-y @notionhq/notion-mcp-server"
  "prisma mcp"
  "-y @sentry/mcp-server"
  "-y @anthropic/figma-mcp-server"
)
SERVER_ENV_KEYS=(
  "GITHUB_PERSONAL_ACCESS_TOKEN"
  "BRAVE_API_KEY"
  "SLACK_BOT_TOKEN"
  "DATABASE_URL"
  "NOTION_API_KEY"
  ""
  "SENTRY_AUTH_TOKEN"
  "FIGMA_ACCESS_TOKEN"
)

echo "Select servers to configure (enter y/n for each):"
echo ""

SELECTED=()
for i in "${!SERVER_NAMES[@]}"; do
  read -rp "  ${SERVER_LABELS[$i]}? [y/N]: " -n 1
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    SELECTED+=("$i")
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

for idx in "${SELECTED[@]}"; do
  server="${SERVER_NAMES[$idx]}"
  args="${SERVER_CMDS[$idx]}"
  env_key="${SERVER_ENV_KEYS[$idx]}"
  label="${SERVER_LABELS[$idx]}"

  if [ "$server" = "prisma" ]; then
    echo -e "${BLUE}Configuring Prisma (no key needed)...${NC}"
    add_server "$server" "$args"
    echo -e "  ${GREEN}✓${NC} $server configured"
    continue
  fi

  if [ -n "$env_key" ]; then
    read -rsp "  Enter ${label%% (*} key (or Enter to skip): " secret
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
