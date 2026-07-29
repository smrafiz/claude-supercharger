#!/usr/bin/env bash
# Claude Supercharger — MCP Server Assembly & settings.json Merge

SUPERCHARGER_MCP_TAG="#supercharger"

# Core servers (all roles, all modes)
get_core_servers() {
  cat <<'SERVERS'
context7|npx|-y @upstash/context7-mcp
SERVERS
}

# Research/heavy-thinking servers — loaded in 'research' and 'full' profiles
get_research_servers() {
  cat <<'SERVERS'
sequential-thinking|npx|-y @modelcontextprotocol/server-sequential-thinking
memory|npx|-y @modelcontextprotocol/server-memory
SERVERS
}

# Role-specific servers (zero-config only)
get_role_servers() {
  local roles="$1"
  local servers=""

  # Heavy/specialty MCPs are opt-in via SUPERCHARGER_MCP_EXTRAS env var.
  # Examples: SUPERCHARGER_MCP_EXTRAS="playwright,github,sequential-thinking,memory"
  # Default install is lean — these are loaded only when explicitly requested.
  local extras="${SUPERCHARGER_MCP_EXTRAS:-}"

  if echo "$roles" | grep -q "developer" && echo "$extras" | grep -q "github" && command -v gh &>/dev/null; then
    servers="${servers}
github|gh|extension exec github-mcp-server stdio"
  fi

  if echo "$roles" | grep -q "developer" && echo "$extras" | grep -q "playwright"; then
    servers="${servers}
playwright|npx|-y @playwright/mcp --headless"
  fi

  # Reasoning extras — role-agnostic
  if echo "$extras" | grep -qE "\bsequential-thinking\b|\bsequential\b"; then
    servers="${servers}
sequential-thinking|npx|-y @modelcontextprotocol/server-sequential-thinking"
  fi

  if echo "$extras" | grep -q "\bmemory\b"; then
    servers="${servers}
memory|npx|-y @modelcontextprotocol/server-memory"
  fi

  if echo "$roles" | grep -qE "(developer|designer)"; then
    servers="${servers}
magic-ui|npx|-y @magicuidesign/mcp@latest"
  fi

  echo "$servers" | sort -u | grep -v '^$'
}

# Build server list for a given profile and role set
# Profiles: light | dev | research | full
build_server_list() {
  local roles="$1"
  local profile="${2:-light}"
  {
    get_core_servers
    case "$profile" in
      research|full)
        get_research_servers
        ;;
    esac
    get_role_servers "$roles"
  } | sort -t'|' -k1,1 -u | grep -v '^$'
}

# Count servers for summary
count_mcp_servers() {
  local roles="$1"
  local profile="${2:-light}"
  build_server_list "$roles" "$profile" | wc -l | tr -d ' '
}

# Count role-specific servers (non-core)
count_role_servers() {
  local roles="$1"
  get_role_servers "$roles" | wc -l | tr -d ' '
}

# Registry of USER-REGISTERED custom MCP servers that Supercharger manages.
# Claude Code already owns *adding* a server (`claude mcp add`, any transport), so
# we don't reimplement that — we let a server you added participate in Supercharger's
# context-cost profiles, which is the thing Claude Code has no notion of.
# Shape: { "<name>": { "profiles": "all" | "dev,full", "entry": {<raw CC entry>} } }
# The raw entry is stored verbatim, so http/sse/url/headers work as well as stdio.
# Read by tools only (never a hook), so the classic tool-config root is correct.
SUPERCHARGER_MCP_CUSTOM="${SUPERCHARGER_MCP_CUSTOM:-$HOME/.claude/supercharger/mcp-custom.json}"

# Write MCP entries to a single config file
_write_mcp_to_file() {
  local settings_file="$1"
  local tag="$2"
  local server_list="$3"
  local profile="${4:-light}"

  SETTINGS_FILE="$settings_file" MCP_TAG="$tag" SERVERS_INPUT="$server_list" \
  MCP_PROFILE="$profile" MCP_CUSTOM_FILE="$SUPERCHARGER_MCP_CUSTOM" python3 -c "
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

# Re-add user-registered custom servers eligible for THIS profile. Without this the
# wipe above would delete a registered server on every profile switch; the registry
# is the source of truth, so a server excluded by the current profile is dropped from
# the config but never lost — switching back restores it.
custom_file = os.environ.get('MCP_CUSTOM_FILE', '')
profile = os.environ.get('MCP_PROFILE', 'light')
if custom_file and os.path.exists(custom_file):
    try:
        with open(custom_file) as f:
            registry = json.load(f)
    except Exception:
        registry = {}
    for name, spec in (registry or {}).items():
        if not isinstance(spec, dict):
            continue
        entry = spec.get('entry')
        if not isinstance(entry, dict):
            continue
        wanted = str(spec.get('profiles', 'all')).strip().lower()
        allowed = wanted in ('', 'all') or profile in [p.strip() for p in wanted.split(',')]
        if allowed:
            settings['mcpServers'][name + ' ' + tag] = entry

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>&1
}

# Merge MCP servers into both config files (covers all Claude Code versions)
merge_mcp_into_settings() {
  local roles="$1"
  local profile="${2:-light}"
  local tag="$SUPERCHARGER_MCP_TAG"
  local server_list
  server_list=$(build_server_list "$roles" "$profile")

  # ~/.claude.json — Claude Code current (User MCPs shown in /mcp)
  _write_mcp_to_file "$HOME/.claude.json" "$tag" "$server_list" "$profile" || return 1

  # ~/.claude/settings.json — Claude Code legacy fallback
  _write_mcp_to_file "$HOME/.claude/settings.json" "$tag" "$server_list" "$profile" || return 1

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
