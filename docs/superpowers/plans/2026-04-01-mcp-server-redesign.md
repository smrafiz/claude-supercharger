# Role-Based MCP Server Setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-configure zero-config MCP servers during install based on role selection, targeting ~/.claude/settings.json.

**Architecture:** New `lib/mcp.sh` module (same pattern as `lib/hooks.sh`) handles server roster, role mapping, and settings.json merge. Install flow calls it after hooks. Uninstall removes tagged entries. Separate `tools/mcp-setup.sh` handles advanced key-required servers.

**Tech Stack:** Bash, Python 3 (JSON operations), npx (MCP server packages)

---

### Task 1: Create lib/mcp.sh — MCP Server Assembly Module

**Files:**
- Create: `lib/mcp.sh`

- [ ] **Step 1: Create lib/mcp.sh with server roster and role mapping**

```bash
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

  python3 -c "
import json, os, sys

settings_file = '$settings_file'
tag = '$tag'

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
servers_input = '''$server_list'''
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

  python3 -c "
import json, os

settings_file = '$settings_file'
tag = '$tag'

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
```

- [ ] **Step 2: Commit**

```bash
git add lib/mcp.sh
git commit -m "feat: add lib/mcp.sh for role-based MCP server assembly"
```

---

### Task 2: Create tests/test-mcp.sh — MCP Test Suite

**Files:**
- Create: `tests/test-mcp.sh`

- [ ] **Step 1: Create the test file**

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/mcp.sh"

# Helper: count MCP entries with supercharger tag in settings.json
count_tagged_mcp() {
  python3 -c "
import json
with open('$HOME/.claude/settings.json') as f:
    s = json.load(f)
count = sum(1 for k in s.get('mcpServers', {}) if '#supercharger' in k)
print(count)
" 2>/dev/null || echo "0"
}

# Helper: check if a specific server name exists (tagged)
has_mcp_server() {
  local name="$1"
  python3 -c "
import json
with open('$HOME/.claude/settings.json') as f:
    s = json.load(f)
found = any('$name' in k and '#supercharger' in k for k in s.get('mcpServers', {}))
print('yes' if found else 'no')
" 2>/dev/null || echo "no"
}

# Helper: check if a specific server name exists (untagged, user's own)
has_user_mcp_server() {
  local name="$1"
  python3 -c "
import json
with open('$HOME/.claude/settings.json') as f:
    s = json.load(f)
found = any(k == '$name' for k in s.get('mcpServers', {}))
print('yes' if found else 'no')
" 2>/dev/null || echo "no"
}

# --- Test 1: Core servers present ---
begin_test "mcp: core servers present after install"
setup_test_home
echo '{}' > "$HOME/.claude/settings.json"
merge_mcp_into_settings "writer"
CORE_COUNT=$(count_tagged_mcp)
CTX=$(has_mcp_server "context7")
SEQ=$(has_mcp_server "sequential-thinking")
MEM=$(has_mcp_server "memory")
if [ "$CORE_COUNT" -ge 3 ] && [ "$CTX" = "yes" ] && [ "$SEQ" = "yes" ] && [ "$MEM" = "yes" ]; then
  pass
else
  fail "expected 3+ core servers, got $CORE_COUNT (ctx=$CTX seq=$SEQ mem=$MEM)"
fi
teardown_test_home

# --- Test 2: Developer role adds Playwright + Magic UI ---
begin_test "mcp: developer role adds playwright and magic-ui"
setup_test_home
echo '{}' > "$HOME/.claude/settings.json"
merge_mcp_into_settings "developer"
PW=$(has_mcp_server "playwright")
MU=$(has_mcp_server "magic-ui")
TOTAL=$(count_tagged_mcp)
if [ "$PW" = "yes" ] && [ "$MU" = "yes" ] && [ "$TOTAL" -eq 5 ]; then
  pass
else
  fail "expected playwright=$PW magic-ui=$MU total=5, got total=$TOTAL"
fi
teardown_test_home

# --- Test 3: Writer role adds DuckDuckGo ---
begin_test "mcp: writer role adds duckduckgo-search"
setup_test_home
echo '{}' > "$HOME/.claude/settings.json"
merge_mcp_into_settings "writer"
DDG=$(has_mcp_server "duckduckgo-search")
TOTAL=$(count_tagged_mcp)
if [ "$DDG" = "yes" ] && [ "$TOTAL" -eq 4 ]; then
  pass
else
  fail "expected duckduckgo=$DDG total=4, got total=$TOTAL"
fi
teardown_test_home

# --- Test 4: Multi-role deduplication ---
begin_test "mcp: developer+pm deduplicates duckduckgo-search"
setup_test_home
echo '{}' > "$HOME/.claude/settings.json"
merge_mcp_into_settings "developer,pm"
TOTAL=$(count_tagged_mcp)
DDG_COUNT=$(python3 -c "
import json
with open('$HOME/.claude/settings.json') as f:
    s = json.load(f)
print(sum(1 for k in s.get('mcpServers', {}) if 'duckduckgo' in k))
" 2>/dev/null || echo "0")
if [ "$TOTAL" -eq 6 ] && [ "$DDG_COUNT" -eq 1 ]; then
  pass
else
  fail "expected total=6 ddg_count=1, got total=$TOTAL ddg=$DDG_COUNT"
fi
teardown_test_home

# --- Test 5: Uninstall removes only supercharger MCP entries ---
begin_test "mcp: uninstall removes only supercharger entries"
setup_test_home
echo '{"mcpServers":{"my-custom-server":{"command":"npx","args":["-y","my-server"]}}}' > "$HOME/.claude/settings.json"
merge_mcp_into_settings "writer"
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
echo '{"mcpServers":{"my-server":{"command":"npx","args":["-y","@my/server"]}}}' > "$HOME/.claude/settings.json"
merge_mcp_into_settings "developer"
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
echo '{"mcpServers":{"my-server":{"command":"npx","args":["-y","@my/server"]}}}' > "$HOME/.claude/settings.json"
merge_mcp_into_settings "writer"
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
echo '{}' > "$HOME/.claude/settings.json"
merge_mcp_into_settings "developer"
FIRST=$(count_tagged_mcp)
merge_mcp_into_settings "developer"
SECOND=$(count_tagged_mcp)
if [ "$FIRST" -eq "$SECOND" ]; then
  pass
else
  fail "expected $FIRST servers both times, got $SECOND after second install"
fi
teardown_test_home

report
```

- [ ] **Step 2: Make test executable**

```bash
chmod +x tests/test-mcp.sh
```

- [ ] **Step 3: Run tests — expect failures (lib/mcp.sh functions need to be sourced properly)**

```bash
bash tests/test-mcp.sh
```

Expected: Tests should run. If `lib/utils.sh` has dependencies, some may fail — fix in next step.

- [ ] **Step 4: Commit**

```bash
git add tests/test-mcp.sh
git commit -m "test: add MCP server test suite (8 tests)"
```

---

### Task 3: Integrate MCP into install.sh

**Files:**
- Modify: `install.sh:13` (add source), `install.sh:195-210` (add MCP after hooks), `install.sh:217-228` (update summary)

- [ ] **Step 1: Add `source lib/mcp.sh` to install.sh**

After line 13 (`source "$SCRIPT_DIR/lib/extras.sh"`), add:

```bash
source "$SCRIPT_DIR/lib/mcp.sh"
```

- [ ] **Step 2: Add MCP deployment after hooks section**

After the hooks deployment block (after line 210: `fi` closing the settings skip block), add:

```bash
# Deploy MCP servers (zero-config)
if [[ "$SETTINGS_ACTION" != "skip" ]]; then
  ROLES_CSV=$(IFS=,; echo "${SELECTED_ROLES[*]}")
  if merge_mcp_into_settings "$ROLES_CSV"; then
    MCP_TOTAL=$(count_mcp_servers "$ROLES_CSV")
    MCP_ROLE=$(count_role_servers "$ROLES_CSV")
    MCP_CORE=$((MCP_TOTAL - MCP_ROLE))
    success "${MCP_TOTAL} MCP server(s) configured (${MCP_CORE} core + ${MCP_ROLE} for your roles)"
  else
    error "Failed to configure MCP servers."
  fi
fi
```

- [ ] **Step 3: Add MCP tip to summary**

In the summary section, before the closing `echo ""` (around line 228), add after the mode/roles display:

```bash
echo ""
echo -e "  Want more MCP servers? Run: ${BOLD}bash tools/mcp-setup.sh${NC}"
```

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: integrate MCP server deployment into install flow"
```

---

### Task 4: Update uninstall.sh

**Files:**
- Modify: `uninstall.sh`

- [ ] **Step 1: Source lib/mcp.sh in uninstall.sh**

The uninstall script doesn't source lib modules — it uses inline Python. Add MCP removal using inline Python (same pattern as hook removal). After the hook removal block (after line 73: `fi`), add:

```bash
# Remove MCP servers from settings.json
if [ -f "$HOME/.claude/settings.json" ]; then
  python3 -c "
import json, os

settings_file = os.path.expanduser('$HOME/.claude/settings.json')
tag = '#supercharger'

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
" 2>/dev/null && echo -e "  ${GREEN}✓${NC} MCP servers removed from settings.json"
fi
```

- [ ] **Step 2: Commit**

```bash
git add uninstall.sh
git commit -m "feat: remove supercharger MCP entries on uninstall"
```

---

### Task 5: Rewrite tools/mcp-setup.sh

**Files:**
- Modify: `tools/mcp-setup.sh` (full rewrite)

- [ ] **Step 1: Rewrite mcp-setup.sh**

Replace entire file content with:

```bash
#!/usr/bin/env bash
set -euo pipefail
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
python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    s = json.load(f)
servers = s.get('mcpServers', {})
if not servers:
    print('  (none)')
else:
    for k in sorted(servers):
        tag = ' (Supercharger)' if '$TAG' in k else ' (user)'
        name = k.replace(' $TAG', '')
        print(f'  - {name}{tag}')
" 2>/dev/null
echo ""

echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}  Advanced MCP Servers (API key required)  ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""

# Server definitions
declare -A SERVER_CMDS=(
  ["github"]="npx|-y @modelcontextprotocol/server-github"
  ["brave-search"]="npx|-y @modelcontextprotocol/server-brave-search"
  ["slack"]="npx|-y @modelcontextprotocol/server-slack"
  ["neon"]="npx|-y @neondatabase/mcp-server-neon"
  ["notion"]="npx|-y @notionhq/notion-mcp-server"
  ["prisma"]="npx|prisma mcp"
  ["sentry"]="npx|-y @sentry/mcp-server"
  ["figma"]="npx|-y @anthropic/figma-mcp-server"
)

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

declare -A SERVER_ENV_KEYS=(
  ["github"]="GITHUB_PERSONAL_ACCESS_TOKEN"
  ["brave-search"]="BRAVE_API_KEY"
  ["slack"]="SLACK_BOT_TOKEN"
  ["neon"]="DATABASE_URL"
  ["notion"]="NOTION_API_KEY"
  ["sentry"]="SENTRY_AUTH_TOKEN"
  ["figma"]="FIGMA_ACCESS_TOKEN"
)

ORDERED_SERVERS=("github" "brave-search" "slack" "neon" "notion" "prisma" "sentry" "figma")

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
  local command="$2"
  local args="$3"
  local env_json="${4:-}"

  MCP_NAME="$name" MCP_TAG="$TAG" MCP_CMD="$command" MCP_ARGS="$args" MCP_ENV="$env_json" \
  python3 -c "
import json, os

settings_file = os.path.expanduser('$SETTINGS_FILE')
name = os.environ['MCP_NAME']
tag = os.environ['MCP_TAG']
cmd = os.environ['MCP_CMD']
args = os.environ['MCP_ARGS'].split()
env_str = os.environ.get('MCP_ENV', '')

with open(settings_file, 'r') as f:
    settings = json.load(f)

if 'mcpServers' not in settings:
    settings['mcpServers'] = {}

key = name + ' ' + tag
entry = {'command': cmd, 'args': args}
if env_str:
    entry['env'] = json.loads(env_str)

settings['mcpServers'][key] = entry

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>/dev/null
}

for server in "${SELECTED[@]}"; do
  IFS='|' read -r cmd args <<< "${SERVER_CMDS[$server]}"

  if [ "$server" = "prisma" ]; then
    echo -e "${BLUE}Configuring Prisma (no key needed)...${NC}"
    add_server "$server" "$cmd" "$args"
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
      add_server "$server" "$cmd" "$args" "$env_json"
      echo -e "  ${GREEN}✓${NC} $server configured"
    else
      echo -e "  ${YELLOW}○${NC} $server skipped"
    fi
  fi
done

echo ""
echo -e "${GREEN}Done!${NC} Restart Claude Code to activate new servers."
echo ""
```

- [ ] **Step 2: Commit**

```bash
git add tools/mcp-setup.sh
git commit -m "feat: rewrite mcp-setup.sh to target settings.json with advanced servers"
```

---

### Task 6: Update tools/claude-check.sh

**Files:**
- Modify: `tools/claude-check.sh:105` (add MCP section before Tools section)

- [ ] **Step 1: Add MCP section**

Before the `# Tools` section (line 108), add:

```bash
# MCP Servers
echo ""
echo -e "${BLUE}MCP Servers:${NC}"
if [ -f "$HOME/.claude/settings.json" ]; then
  python3 -c "
import json
with open('$HOME/.claude/settings.json') as f:
    s = json.load(f)
servers = s.get('mcpServers', {})
sc = {k: v for k, v in servers.items() if '#supercharger' in k}
user = {k: v for k, v in servers.items() if '#supercharger' not in k}
if sc:
    for k in sorted(sc):
        name = k.replace(' #supercharger', '')
        print(f'  \033[0;32m✓\033[0m {name}')
else:
    print('  \033[1;33m○\033[0m No Supercharger MCP servers configured')
if user:
    for k in sorted(user):
        print(f'  \033[0;34m●\033[0m {k} (user-configured)')
core = ['context7', 'sequential-thinking', 'memory']
missing = [c for c in core if not any(c in k for k in sc)]
if missing:
    print(f'  \033[0;31m✗\033[0m Missing core: {', '.join(missing)}')
" 2>/dev/null
else
  echo -e "  ${YELLOW}○${NC} No settings.json — no MCP servers"
fi
```

- [ ] **Step 2: Commit**

```bash
git add tools/claude-check.sh
git commit -m "feat: add MCP server status to claude-check health report"
```

---

### Task 7: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add MCP Servers section after Hooks table**

After the Hooks table (after line 106: `| **compaction-backup** | Full | ...`), add:

```markdown

## MCP Servers

Supercharger auto-configures MCP servers during install — zero API keys, zero JSON editing.

| Tier | Servers | Setup |
|------|---------|-------|
| **Core** (all roles) | Context7, Sequential Thinking, Memory | Automatic |
| **Developer** | + Playwright, Magic UI | Automatic |
| **Writer/Student/Data/PM** | + DuckDuckGo Search | Automatic |
| **Advanced** | GitHub, Brave Search, Slack, Notion, + more | `bash tools/mcp-setup.sh` |

Total: 3-5 servers per role (research shows 3 is the sweet spot, 5 is the max before token overhead).
```

- [ ] **Step 2: Update "What You Get" section**

In the "For everyone" line (around line 62), add MCP mention:

Change:
```
**For everyone:** Safety hooks (block `rm -rf`, `DROP TABLE`), verification gates, anti-pattern detection, **token economy** (concrete response targets, ~40-50% output reduction), context management with compaction guidance, quick mode switches, clarification mode, session handoff
```

To:
```
**For everyone:** Safety hooks (block `rm -rf`, `DROP TABLE`), verification gates, anti-pattern detection, **token economy** (~40-50% output reduction), **auto-configured MCP servers** (zero-setup), context management, quick mode switches, session handoff
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add MCP servers section to README"
```

---

### Task 8: Run Full Test Suite + Update CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run full test suite**

```bash
bash tests/run.sh
```

Expected: 57 existing tests pass + 8 new MCP tests = 65 total, 0 failed.

- [ ] **Step 2: Update CHANGELOG**

Add after the token economy entry in the Ship-Ready Fixes section:

```markdown
- **Role-based MCP servers:** Auto-configures 3-5 zero-config MCP servers based on role selection (Context7, Sequential Thinking, Memory as core; Playwright, Magic UI, DuckDuckGo as role-specific). Advanced tool for key-required servers (GitHub, Brave, Slack, etc.)
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add MCP server redesign to CHANGELOG"
```

---

## Dependency Graph

```
Task 1 (lib/mcp.sh) ──→ Task 2 (tests) ──→ Task 3 (install.sh) ──┐
                                            Task 4 (uninstall.sh) ──┤
                                            Task 5 (mcp-setup.sh) ──┼──→ Task 8 (tests + CHANGELOG)
                                            Task 6 (claude-check) ──┤
                                            Task 7 (README) ────────┘
```

Task 1 first (creates the module). Task 2 next (tests the module). Tasks 3-7 independent of each other. Task 8 last (runs all tests, updates CHANGELOG).
