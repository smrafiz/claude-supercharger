#!/usr/bin/env bash
# Claude Supercharger — MCP Server Assembly & settings.json Merge

SUPERCHARGER_MCP_TAG="#supercharger"

# Core servers (all roles, all modes)
get_core_servers() {
  cat <<'SERVERS'
context7|npx|-y @upstash/context7-mcp
sequential-thinking|npx|-y @modelcontextprotocol/server-sequential-thinking
memory|npx|-y @modelcontextprotocol/server-memory
SERVERS
}

# Role-specific servers (zero-config only)
get_role_servers() {
  local roles="$1"
  local servers=""

  if echo "$roles" | grep -q "developer"; then
    servers="${servers}
playwright|npx|-y @playwright/mcp --headless
magic-ui|npx|-y @magicuidesign/mcp-server-magicui"
  fi

  if echo "$roles" | grep -qE "(writer|student|data|pm)"; then
    servers="${servers}
duckduckgo-search|npx|-y duckduckgo-mcp-server"
  fi

  echo "$servers" | sort -u | grep -v '^$'
}

# Build full deduplicated server list
build_server_list() {
  local roles="$1"
  {
    get_core_servers
    get_role_servers "$roles"
  } | sort -t'|' -k1,1 -u | grep -v '^$'
}

# Count servers for summary
count_mcp_servers() {
  local roles="$1"
  build_server_list "$roles" | wc -l | tr -d ' '
}

# Count role-specific servers (non-core)
count_role_servers() {
  local roles="$1"
  get_role_servers "$roles" | wc -l | tr -d ' '
}

# Merge MCP servers into settings.json
merge_mcp_into_settings() {
  local roles="$1"
  local settings_file="$HOME/.claude/settings.json"
  local tag="$SUPERCHARGER_MCP_TAG"

  local server_list
  server_list=$(build_server_list "$roles")

  SETTINGS_FILE="$settings_file" MCP_TAG="$tag" SERVERS_INPUT="$server_list" python3 -c "
import json, os, sys

settings_file = os.environ['SETTINGS_FILE']
tag = os.environ['MCP_TAG']
servers_input = os.environ['SERVERS_INPUT']

if os.path.exists(settings_file):
    with open(settings_file, 'r') as f:
        try:
            settings = json.load(f)
        except json.JSONDecodeError:
            print('ERROR: settings.json is malformed.', file=sys.stderr)
            sys.exit(1)
else:
    settings = {}

if 'mcpServers' not in settings:
    settings['mcpServers'] = {}

# Remove existing supercharger MCP entries
settings['mcpServers'] = {
    k: v for k, v in settings['mcpServers'].items()
    if tag not in k
}

# Add new entries
for line in servers_input.strip().split('\n'):
    if not line.strip():
        continue
    parts = line.split('|', 2)
    name = parts[0].strip()
    command = parts[1].strip() if len(parts) > 1 else 'npx'
    args_str = parts[2].strip() if len(parts) > 2 else ''

    key = name + ' ' + tag
    entry = {'command': command, 'args': args_str.split()}
    settings['mcpServers'][key] = entry

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>&1

  return $?
}

# Remove only supercharger MCP entries
remove_supercharger_mcp() {
  local settings_file="$HOME/.claude/settings.json"
  local tag="$SUPERCHARGER_MCP_TAG"

  if [ ! -f "$settings_file" ]; then
    return 0
  fi

  SETTINGS_FILE="$settings_file" MCP_TAG="$tag" python3 -c "
import json, os

settings_file = os.environ['SETTINGS_FILE']
tag = os.environ['MCP_TAG']

with open(settings_file, 'r') as f:
    settings = json.load(f)

if 'mcpServers' in settings:
    settings['mcpServers'] = {
        k: v for k, v in settings['mcpServers'].items()
        if tag not in k
    }
    if not settings['mcpServers']:
        del settings['mcpServers']

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>&1
}
