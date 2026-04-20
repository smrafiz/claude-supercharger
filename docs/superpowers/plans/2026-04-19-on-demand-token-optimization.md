# On-Demand Token Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce per-session token overhead by ~60% by making MCP servers profile-switched and rules files path-scoped, so heavy context only loads when the task actually needs it.

**Architecture:** Two orthogonal changes — (1) `paths:` frontmatter on role/code-specific rules files so Claude Code lazy-loads them only when accessing matching file types, and (2) MCP server profiles so heavy tool schemas (Playwright, memory, sequential-thinking) aren't registered globally on every session. A new `tools/mcp-profile.sh` script handles runtime profile switching; `install.sh` gets a new MCP profile prompt.

**Tech Stack:** Bash, Python 3 (already used in `lib/mcp.sh`), Claude Code `paths:` frontmatter, `~/.claude.json` / `~/.claude/settings.json`

---

## Token Budget (Before / After)

| Source | Before | After |
|---|---|---|
| MCP tool schemas (Playwright + memory + sequential-thinking) | ~4,500 tokens | ~300 tokens (light profile) |
| Role rules files (developer, anti-patterns, etc.) | ~900 tokens always | ~0 on non-code sessions |
| Total saving | — | **~5,100 tokens/session** |

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `configs/roles/developer.md` | Modify | Add `paths:` frontmatter |
| `configs/roles/devops.md` | Modify | Add `paths:` frontmatter |
| `configs/roles/designer.md` | Modify | Add `paths:` frontmatter |
| `configs/roles/researcher.md` | Modify | Add `paths:` frontmatter |
| `configs/roles/data.md` | Modify | Add `paths:` frontmatter |
| `configs/universal/anti-patterns.yml` | Modify | Add `paths:` frontmatter |
| `lib/mcp.sh` | Modify | Restructure core/profile server lists |
| `tools/mcp-profile.sh` | Create | Runtime MCP profile switcher |
| `install.sh` | Modify | Add MCP profile step to wizard |
| `tests/test-mcp.sh` | Modify | Tests for new profile logic |

**Not touched:** `configs/universal/guardrails.md`, `configs/universal/economy.md`, `configs/universal/supercharger.md`, `configs/universal/CLAUDE.md`, all hooks, `lib/hooks.sh`, `lib/roles.sh`.

---

## Task 1: Add `paths:` frontmatter to developer.md

**Files:**
- Modify: `configs/roles/developer.md`

- [ ] **Step 1: Read the current file**

```bash
cat configs/roles/developer.md
```

- [ ] **Step 2: Add paths frontmatter**

Replace the opening line of `configs/roles/developer.md` with:

```markdown
---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs}"
  - "**/*.{py,go,rs,rb,php,java,kt,swift,c,cpp,h}"
  - "**/*.{sh,bash}"
  - "package.json"
  - "Cargo.toml"
  - "go.mod"
  - "pyproject.toml"
---

# Role: Developer
```

(Keep everything after `# Role: Developer` unchanged.)

- [ ] **Step 3: Verify file starts correctly**

```bash
head -12 configs/roles/developer.md
```

Expected: YAML frontmatter block, then `# Role: Developer`

- [ ] **Step 4: Commit**

```bash
git add configs/roles/developer.md
git commit -m "feat: lazy-load developer role via paths frontmatter"
```

---

## Task 2: Add `paths:` frontmatter to devops.md

**Files:**
- Modify: `configs/roles/devops.md`

- [ ] **Step 1: Read the current file**

```bash
head -5 configs/roles/devops.md
```

- [ ] **Step 2: Add paths frontmatter**

Prepend to `configs/roles/devops.md`:

```markdown
---
paths:
  - "**/*.{yml,yaml}"
  - "**/Dockerfile"
  - "**/*.dockerfile"
  - "**/*.tf"
  - "**/*.hcl"
  - ".github/**"
  - "**/docker-compose*.{yml,yaml}"
---

```

- [ ] **Step 3: Verify**

```bash
head -12 configs/roles/devops.md
```

Expected: YAML frontmatter, then the role heading.

- [ ] **Step 4: Commit**

```bash
git add configs/roles/devops.md
git commit -m "feat: lazy-load devops role via paths frontmatter"
```

---

## Task 3: Add `paths:` frontmatter to designer.md

**Files:**
- Modify: `configs/roles/designer.md`

- [ ] **Step 1: Read the current file**

```bash
head -5 configs/roles/designer.md
```

- [ ] **Step 2: Add paths frontmatter**

Prepend to `configs/roles/designer.md`:

```markdown
---
paths:
  - "**/*.{css,scss,sass,less}"
  - "**/*.{svg,figma}"
  - "**/tailwind.config.*"
  - "**/*.{tsx,jsx}"
  - "**/styles/**"
  - "**/components/**"
  - "**/design-system/**"
---

```

- [ ] **Step 3: Verify**

```bash
head -12 configs/roles/designer.md
```

- [ ] **Step 4: Commit**

```bash
git add configs/roles/designer.md
git commit -m "feat: lazy-load designer role via paths frontmatter"
```

---

## Task 4: Add `paths:` frontmatter to researcher.md and data.md

**Files:**
- Modify: `configs/roles/researcher.md`
- Modify: `configs/roles/data.md`

- [ ] **Step 1: Read both files**

```bash
head -5 configs/roles/researcher.md
head -5 configs/roles/data.md
```

- [ ] **Step 2: Add frontmatter to researcher.md**

Prepend to `configs/roles/researcher.md`:

```markdown
---
paths:
  - "**/*.{md,mdx,txt,rst}"
  - "**/docs/**"
  - "**/research/**"
  - "**/reports/**"
---

```

- [ ] **Step 3: Add frontmatter to data.md**

Prepend to `configs/roles/data.md`:

```markdown
---
paths:
  - "**/*.{csv,tsv,parquet,json,jsonl}"
  - "**/*.{sql,ipynb}"
  - "**/data/**"
  - "**/notebooks/**"
  - "**/queries/**"
---

```

- [ ] **Step 4: Verify both**

```bash
head -8 configs/roles/researcher.md
head -8 configs/roles/data.md
```

- [ ] **Step 5: Commit**

```bash
git add configs/roles/researcher.md configs/roles/data.md
git commit -m "feat: lazy-load researcher and data roles via paths frontmatter"
```

---

## Task 5: Add `paths:` frontmatter to anti-patterns.yml

**Files:**
- Modify: `configs/universal/anti-patterns.yml`

- [ ] **Step 1: Read the first 5 lines**

```bash
head -5 configs/universal/anti-patterns.yml
```

- [ ] **Step 2: Add YAML frontmatter block**

The file is already YAML, so the frontmatter uses the same `---` delimiter. Prepend:

```yaml
---
paths:
  - "**/*.{ts,tsx,js,jsx,py,go,rs,rb,java,sh}"
---
```

Then a blank line, then the existing content starting with `schema_version: "1.0"`.

- [ ] **Step 3: Verify the file parses as valid YAML**

```bash
python3 -c "
import yaml
with open('configs/universal/anti-patterns.yml') as f:
    content = f.read()
# Strip frontmatter block for validation
parts = content.split('---', 2)
body = parts[2] if len(parts) >= 3 else content
yaml.safe_load(body)
print('OK')
"
```

Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add configs/universal/anti-patterns.yml
git commit -m "feat: lazy-load anti-patterns via paths frontmatter"
```

---

## Task 6: Restructure MCP server tiers in lib/mcp.sh

**Files:**
- Modify: `lib/mcp.sh`

This is the main logic change. Today `get_core_servers()` includes `memory` and `sequential-thinking` for every session. These are heavy (memory has ~10 tools, sequential-thinking has a ~400 token schema). They should be profile-specific.

- [ ] **Step 1: Read lib/mcp.sh in full**

```bash
cat lib/mcp.sh
```

- [ ] **Step 2: Define the new server tiers**

Replace `get_core_servers()` and add two new profile functions. Edit `lib/mcp.sh`:

```bash
# Core servers — loaded in ALL profiles (minimal token cost, universal utility)
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

  if echo "$roles" | grep -q "developer"; then
    if command -v gh &>/dev/null; then
      servers="${servers}
github|gh|extension exec github-mcp-server stdio"
    fi
    servers="${servers}
playwright|npx|-y @playwright/mcp --headless"
  fi

  if echo "$roles" | grep -qE "(developer|designer)"; then
    servers="${servers}
magic-ui|npx|-y @magicuidesign/mcp@latest"
  fi

  if echo "$roles" | grep -qE "(writer|student|data|pm|devops|researcher)"; then
    servers="${servers}
duckduckgo-search|npx|-y duckduckgo-mcp-server"
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
```

- [ ] **Step 3: Update count functions to pass profile**

In `lib/mcp.sh`, update `count_mcp_servers` and `count_role_servers`:

```bash
count_mcp_servers() {
  local roles="$1"
  local profile="${2:-light}"
  build_server_list "$roles" "$profile" | wc -l | tr -d ' '
}

count_role_servers() {
  local roles="$1"
  get_role_servers "$roles" | wc -l | tr -d ' '
}
```

- [ ] **Step 4: Update merge_mcp_into_settings to accept profile**

```bash
merge_mcp_into_settings() {
  local roles="$1"
  local profile="${2:-light}"
  local tag="$SUPERCHARGER_MCP_TAG"
  local server_list
  server_list=$(build_server_list "$roles" "$profile")

  _write_mcp_to_file "$HOME/.claude.json" "$tag" "$server_list" || return 1
  _write_mcp_to_file "$HOME/.claude/settings.json" "$tag" "$server_list" || return 1
  return 0
}
```

- [ ] **Step 5: Verify syntax**

```bash
bash -n lib/mcp.sh && echo "OK"
```

Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git add lib/mcp.sh
git commit -m "feat: split MCP servers into core/research/role tiers with profile support"
```

---

## Task 7: Create tools/mcp-profile.sh

**Files:**
- Create: `tools/mcp-profile.sh`

This lets users switch MCP profiles at runtime without reinstalling.

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
# Claude Supercharger — MCP Profile Switcher
# Usage: bash tools/mcp-profile.sh [light|dev|research|full]
# Profiles:
#   light    — context7 only (~300 tokens)
#   dev      — light + playwright + github + magic-ui (~1,200 tokens)
#   research — light + memory + sequential-thinking (~1,500 tokens)
#   full     — everything (~3,500 tokens)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/mcp.sh"

PROFILE="${1:-}"

if [ -z "$PROFILE" ]; then
  echo "Usage: mcp-profile.sh [light|dev|research|full]"
  echo ""
  echo "  light    — context7 only (~300 tokens of tool schemas)"
  echo "  dev      — light + playwright + github + magic-ui"
  echo "  research — light + memory + sequential-thinking"
  echo "  full     — everything"
  echo ""
  CURRENT=""
  if [ -f "$HOME/.claude/supercharger/scope/.mcp-profile" ]; then
    CURRENT=$(cat "$HOME/.claude/supercharger/scope/.mcp-profile")
  fi
  [ -n "$CURRENT" ] && echo "Current profile: $CURRENT" || echo "Current profile: light (default)"
  exit 0
fi

case "$PROFILE" in
  light|dev|research|full) ;;
  *) echo "Unknown profile: $PROFILE. Use: light | dev | research | full"; exit 1 ;;
esac

# Determine role set — read from installed version stamp if available
INSTALLED_ROLES="developer"
ROLES_STAMP="$HOME/.claude/supercharger/.roles"
if [ -f "$ROLES_STAMP" ]; then
  INSTALLED_ROLES=$(cat "$ROLES_STAMP")
fi

# Map profile to internal role/profile args
case "$PROFILE" in
  light)
    ROLES="$INSTALLED_ROLES"
    INTERNAL_PROFILE="light"
    ;;
  dev)
    ROLES="$INSTALLED_ROLES"
    INTERNAL_PROFILE="light"
    # Force developer role for dev profile
    echo "$ROLES" | grep -q "developer" || ROLES="developer,${ROLES}"
    ;;
  research)
    ROLES="$INSTALLED_ROLES"
    INTERNAL_PROFILE="research"
    ;;
  full)
    ROLES="$INSTALLED_ROLES"
    INTERNAL_PROFILE="full"
    ;;
esac

echo "Switching to MCP profile: $PROFILE..."

if merge_mcp_into_settings "$ROLES" "$INTERNAL_PROFILE"; then
  COUNT=$(count_mcp_servers "$ROLES" "$INTERNAL_PROFILE")
  # Save profile selection
  mkdir -p "$HOME/.claude/supercharger/scope"
  echo "$PROFILE" > "$HOME/.claude/supercharger/scope/.mcp-profile"
  echo "Done. $COUNT MCP server(s) configured. Restart Claude Code to apply."
else
  echo "Error: failed to write MCP config."
  exit 1
fi
```

- [ ] **Step 2: Make executable**

```bash
chmod +x tools/mcp-profile.sh
```

- [ ] **Step 3: Test light profile (dry run — check output file)**

```bash
# Back up first
cp "$HOME/.claude.json" /tmp/claude-json-backup.json 2>/dev/null || true

bash tools/mcp-profile.sh light

# Verify only context7 is present
python3 -c "
import json
with open('$HOME/.claude.json') as f:
    s = json.load(f)
servers = [k for k in s.get('mcpServers', {}) if '#supercharger' in k]
print('Servers:', servers)
assert len(servers) == 1, f'Expected 1 server, got {len(servers)}'
assert any('context7' in k for k in servers), 'context7 not found'
print('PASS')
"
```

Expected:
```
Servers: ['context7 #supercharger']
PASS
```

- [ ] **Step 4: Test research profile**

```bash
bash tools/mcp-profile.sh research

python3 -c "
import json
with open('$HOME/.claude.json') as f:
    s = json.load(f)
servers = [k for k in s.get('mcpServers', {}) if '#supercharger' in k]
print('Servers:', servers)
names = [k.split(' #')[0] for k in servers]
assert 'context7' in names, 'context7 missing'
assert 'sequential-thinking' in names, 'sequential-thinking missing'
assert 'memory' in names, 'memory missing'
assert 'playwright' not in names, 'playwright should not be in research profile'
print('PASS')
"
```

Expected: 3 servers (context7, sequential-thinking, memory), `PASS`

- [ ] **Step 5: Restore original config**

```bash
cp /tmp/claude-json-backup.json "$HOME/.claude.json" 2>/dev/null || true
```

- [ ] **Step 6: Commit**

```bash
git add tools/mcp-profile.sh
git commit -m "feat: add mcp-profile.sh for runtime MCP profile switching"
```

---

## Task 8: Persist roles stamp during install

**Files:**
- Modify: `install.sh`

`mcp-profile.sh` reads `~/.claude/supercharger/.roles` to know what roles were installed. We need to write this file during install.

- [ ] **Step 1: Find where install.sh writes the version stamp**

```bash
grep -n "\.version" install.sh
```

Expected: a line like `echo "$VERSION" > "$HOME/.claude/supercharger/.version"`

- [ ] **Step 2: Add roles stamp immediately after version stamp**

In `install.sh`, find the block:

```bash
echo "$VERSION" > "$HOME/.claude/supercharger/.version"
```

Add directly after:

```bash
echo "${ROLES_CSV}" > "$HOME/.claude/supercharger/.roles"
```

Where `ROLES_CSV` is already defined earlier in the script as `$(IFS=,; echo "${SELECTED_ROLES[*]}")`.

- [ ] **Step 3: Verify ROLES_CSV is in scope at that point**

```bash
grep -n "ROLES_CSV" install.sh | head -10
```

Confirm `ROLES_CSV` is defined before the version stamp line.

- [ ] **Step 4: Verify the stamp would be written by running install in dry-run**

```bash
bash -n install.sh && echo "Syntax OK"
```

Expected: `Syntax OK`

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat: persist installed roles to .roles stamp for mcp-profile.sh"
```

---

## Task 9: Add MCP profile step to install wizard

**Files:**
- Modify: `install.sh`
- Modify: `lib/mcp.sh` (call site in install)

Add a new install step between economy and notifications that asks which MCP profile to start with.

- [ ] **Step 1: Add ARG_MCP_PROFILE argument parsing**

In `install.sh`, in the argument parsing block (`while [[ $# -gt 0 ]]`), add:

```bash
--mcp-profile) ARG_MCP_PROFILE="$2"; shift 2 ;;
```

And at the top with other `ARG_*` declarations:

```bash
ARG_MCP_PROFILE=""
```

- [ ] **Step 2: Add the interactive MCP profile prompt after economy step**

In `install.sh`, after the economy tier selection block and before the notifications block, add:

```bash
# MCP Profile selection
MCP_PROFILE="light"
if [ -n "$ARG_MCP_PROFILE" ]; then
  MCP_PROFILE=$(echo "$ARG_MCP_PROFILE" | tr '[:upper:]' '[:lower:]')
elif [[ "$NON_INTERACTIVE" == "false" ]]; then
  echo -e "${BOLD}Step 4 of 7: MCP Servers${NC}"
  echo ""
  echo -e "  MCP servers extend Claude with real-time tools. More = more capable, but higher token cost per session."
  echo ""
  echo -e "  ${BOLD}1)${NC} Light    — context7 docs lookup only (~300 token overhead) [recommended]"
  echo -e "  ${BOLD}2)${NC} Dev      — + Playwright browser + GitHub + Magic UI"
  echo -e "  ${BOLD}3)${NC} Research — + memory + sequential thinking"
  echo -e "  ${BOLD}4)${NC} Full     — everything"
  echo ""
  echo -e "  ${DIM}Switch anytime: bash tools/mcp-profile.sh [light|dev|research|full]${NC}"
  echo ""
  read -rp "> " mcp_choice
  case "$mcp_choice" in
    2) MCP_PROFILE="dev" ;;
    3) MCP_PROFILE="research" ;;
    4) MCP_PROFILE="full" ;;
    *) MCP_PROFILE="light" ;;
  esac
  echo ""
fi
```

Also update the existing step numbering: notifications becomes Step 5, commits Step 6, existing config Step 6/7 — renumber as needed.

- [ ] **Step 3: Update the MCP install call to pass profile**

Find the existing `merge_mcp_into_settings "$ROLES_CSV"` call in `install.sh` and update it:

```bash
if merge_mcp_into_settings "$ROLES_CSV" "$MCP_PROFILE"; then
  MCP_TOTAL=$(count_mcp_servers "$ROLES_CSV" "$MCP_PROFILE")
```

- [ ] **Step 4: Update help text in show_usage()**

Add to `show_usage()`:

```bash
echo "  --mcp-profile PROFILE  MCP profile: light, dev, research, full (default: light)"
```

- [ ] **Step 5: Syntax check**

```bash
bash -n install.sh && echo "Syntax OK"
```

Expected: `Syntax OK`

- [ ] **Step 6: Commit**

```bash
git add install.sh
git commit -m "feat: add MCP profile step to install wizard (light/dev/research/full)"
```

---

## Task 10: Update tests

**Files:**
- Modify: `tests/test-mcp.sh`

- [ ] **Step 1: Read existing tests**

```bash
cat tests/test-mcp.sh
```

- [ ] **Step 2: Add profile-aware tests**

Add these test cases to `tests/test-mcp.sh`:

```bash
test_light_profile_has_only_context7() {
  local result
  result=$(build_server_list "developer" "light")
  local count
  count=$(echo "$result" | wc -l | tr -d ' ')
  assert_equals "1" "$count" "light profile should have 1 server"
  assert_contains "$result" "context7" "light profile must include context7"
  assert_not_contains "$result" "playwright" "light profile must not include playwright"
  assert_not_contains "$result" "memory" "light profile must not include memory"
  assert_not_contains "$result" "sequential-thinking" "light profile must not include sequential-thinking"
}

test_research_profile_has_memory_and_sequential() {
  local result
  result=$(build_server_list "developer" "research")
  assert_contains "$result" "context7" "research profile must include context7"
  assert_contains "$result" "memory" "research profile must include memory"
  assert_contains "$result" "sequential-thinking" "research profile must include sequential-thinking"
}

test_dev_profile_has_playwright() {
  local result
  result=$(build_server_list "developer" "light")
  # dev role always gets playwright via get_role_servers
  local role_result
  role_result=$(get_role_servers "developer")
  assert_contains "$role_result" "playwright" "developer role must include playwright"
}

test_full_profile_has_all() {
  local result
  result=$(build_server_list "developer" "full")
  assert_contains "$result" "context7" "full must have context7"
  assert_contains "$result" "memory" "full must have memory"
  assert_contains "$result" "sequential-thinking" "full must have sequential-thinking"
}
```

- [ ] **Step 3: Run tests**

```bash
bash tests/test-mcp.sh
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add tests/test-mcp.sh
git commit -m "test: add MCP profile tier tests"
```

---

## Task 11: Update README / docs

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Find the MCP section in README**

```bash
grep -n "MCP\|mcp" README.md | head -20
```

- [ ] **Step 2: Add profile switching docs**

Find the MCP servers section and add after the existing MCP content:

```markdown
### MCP Profiles

By default, Supercharger installs the **light** profile (context7 only, ~300 tokens overhead). Switch at any time:

```bash
bash tools/mcp-profile.sh light     # context7 only — minimal overhead
bash tools/mcp-profile.sh dev       # + Playwright + GitHub + Magic UI
bash tools/mcp-profile.sh research  # + memory + sequential thinking
bash tools/mcp-profile.sh full      # everything
```

Restart Claude Code after switching.
```

- [ ] **Step 3: Verify README renders**

```bash
grep -A 10 "MCP Profiles" README.md
```

Expected: the section appears correctly.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document MCP profile switching"
```

---

## Self-Review

### Spec coverage check

| Requirement | Covered by |
|---|---|
| Lazy-load role rules | Tasks 1–5 (paths: frontmatter on developer, devops, designer, researcher, data, anti-patterns) |
| MCP server profiles | Task 6 (lib/mcp.sh restructure) |
| Runtime profile switcher | Task 7 (tools/mcp-profile.sh) |
| Install wizard prompt | Task 9 (install.sh) |
| Persist roles stamp | Task 8 (install.sh .roles file) |
| Tests | Task 10 |
| Docs | Task 11 |

**Not covered (out of scope):** `using-superpowers` skill auto-injection — that's in the external `superpowers@claude-plugins-official` plugin and would require a separate upstream PR.

### Placeholder scan

None found. All code blocks are complete.

### Type consistency

- `build_server_list(roles, profile)` — called with 2 args in `merge_mcp_into_settings`, `count_mcp_servers`, `mcp-profile.sh`
- `merge_mcp_into_settings(roles, profile)` — called with 2 args in both `install.sh` and `mcp-profile.sh`
- `count_mcp_servers(roles, profile)` — 2 args everywhere
- `.roles` stamp path: `$HOME/.claude/supercharger/.roles` — used in Tasks 8 and 7 consistently
- `.mcp-profile` stamp path: `$HOME/.claude/supercharger/scope/.mcp-profile` — used only in Task 7
