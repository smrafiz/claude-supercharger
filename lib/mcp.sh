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
    if command -v gh &>/dev/null; then
      servers="${servers}
github|npx|-y @modelcontextprotocol/server-github|{\"GITHUB_PERSONAL_ACCESS_TOKEN\":\"\"}"
    fi
    servers="${servers}
playwright|npx|-y @playwright/mcp --headless
magic-ui|npx|-y @magicuidesign/mcp@latest"
  fi

  if echo "$roles" | grep -q "designer"; then
    servers="${servers}
magic-ui|npx|-y @magicuidesign/mcp@latest"
  fi

  if echo "$roles" | grep -qE "(writer|student|data|pm|devops|researcher)"; then
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

# Write MCP entries to a single config file
_write_mcp_to_file() {
  local settings_file="$1"
  local tag="$2"
  local server_list="$3"

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
            print('ERROR: ' + settings_file + ' is malformed.', file=sys.stderr)
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
    parts = line.split('|', 3)
    name = parts[0].strip()
    command = parts[1].strip() if len(parts) > 1 else 'npx'
    args_str = parts[2].strip() if len(parts) > 2 else ''
    env_str = parts[3].strip() if len(parts) > 3 else ''

    key = name + ' ' + tag
    entry = {'command': command, 'args': args_str.split()}
    if env_str:
        try:
            entry['env'] = json.loads(env_str)
        except json.JSONDecodeError:
            pass
    settings['mcpServers'][key] = entry

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>&1
}

# Merge MCP servers into both config files (covers all Claude Code versions)
merge_mcp_into_settings() {
  local roles="$1"
  local tag="$SUPERCHARGER_MCP_TAG"
  local server_list
  server_list=$(build_server_list "$roles")

  # ~/.claude.json — Claude Code current (User MCPs shown in /mcp)
  _write_mcp_to_file "$HOME/.claude.json" "$tag" "$server_list" || return 1

  # ~/.claude/settings.json — Claude Code legacy fallback
  _write_mcp_to_file "$HOME/.claude/settings.json" "$tag" "$server_list" || return 1

  return 0
}

# Remove supercharger MCP entries from a single file
_remove_mcp_from_file() {
  local settings_file="$1"
  local tag="$2"

  [ -f "$settings_file" ] || return 0

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

# Remove supercharger MCP entries from both config files
remove_supercharger_mcp() {
  local tag="$SUPERCHARGER_MCP_TAG"
  _remove_mcp_from_file "$HOME/.claude.json" "$tag"
  _remove_mcp_from_file "$HOME/.claude/settings.json" "$tag"
}
