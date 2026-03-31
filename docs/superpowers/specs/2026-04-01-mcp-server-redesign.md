# Role-Based MCP Server Setup — Design Spec

**Date:** 2026-04-01
**Goal:** Zero-config MCP server activation during install, role-aware recommendations, targeting ~/.claude/settings.json
**Scope:** New lib/mcp.sh, install.sh integration, mcp-setup.sh rewrite, uninstall update, tests, README, CHANGELOG

## Motivation

MCP servers are high-value but high-friction. Setting them up means finding package names, crafting JSON, hunting API keys, editing config files manually. Most users don't bother. Supercharger already configures hooks automatically — MCP servers should work the same way.

Research confirms: "Three servers is the sweet spot; five is the max before token overhead hurts performance." The design respects this constraint with role-aware server selection.

## Server Roster

### Core (all roles, all modes — 3 servers)

| Server | npx Command | Value |
|--------|------------|-------|
| Context7 | `npx -y @upstash/context7-mcp` | Live docs for any library, prevents hallucination |
| Sequential Thinking | `npx -y @modelcontextprotocol/server-sequential-thinking` | Multi-step reasoning for complex tasks |
| Memory | `npx -y @modelcontextprotocol/server-memory` | Persist context across sessions (local SQLite) |

All zero-config, no API keys.

### Role-Specific (zero-config, added based on role selection)

| Role | Server(s) | npx Command | Why |
|------|----------|------------|-----|
| Developer | Playwright | `npx -y @playwright/mcp --headless` | Browser automation, E2E testing (22 tools) |
| Developer | Magic UI | `npx -y @magicuidesign/mcp-server-magicui` | React component generation |
| Writer | DuckDuckGo Search | `npx -y duckduckgo-mcp-server` | Research without leaving Claude |
| Student | DuckDuckGo Search | `npx -y duckduckgo-mcp-server` | Look things up while learning |
| Data | DuckDuckGo Search | `npx -y duckduckgo-mcp-server` | Research datasets and methods |
| PM | DuckDuckGo Search | `npx -y duckduckgo-mcp-server` | Research for decisions and planning |

**Total per role:**
- Developer: 5 (3 core + 2 role) — at recommended max
- Writer/Student/Data/PM: 4 (3 core + 1 role)
- Multi-role: deduplicated (e.g., developer+pm = 5, not 6)

### Advanced (via tools/mcp-setup.sh, key required)

| Server | Requires | npx Command |
|--------|----------|------------|
| GitHub | Personal Access Token | `npx -y @modelcontextprotocol/server-github` |
| Brave Search | API Key (free tier: 2K/mo) | `npx -y @modelcontextprotocol/server-brave-search` |
| Slack | Bot Token | `npx -y @modelcontextprotocol/server-slack` |
| Neon | Connection String | `npx -y @neondatabase/mcp-server-neon` |
| Notion | API Key | `npx -y @notionhq/notion-mcp-server` |
| Prisma | Project CLI | `npx prisma mcp` |
| Sentry | Auth Token | `npx -y @sentry/mcp-server` |
| Figma | Access Token | `npx -y @anthropic/figma-mcp-server` |

## Changes

### 1. New File: lib/mcp.sh

MCP server assembly module (same pattern as lib/hooks.sh).

Functions:
- `get_core_servers()` — returns core server list (Context7, Sequential, Memory)
- `get_role_servers(roles)` — returns role-specific servers for given roles, deduplicated
- `merge_mcp_into_settings(servers)` — merges MCP entries into settings.json via Python, tagged with `#supercharger` for clean removal
- `remove_supercharger_mcp()` — removes only `#supercharger`-tagged MCP entries
- `count_mcp_servers(roles)` — returns total count for install summary

settings.json MCP format:
```json
{
  "mcpServers": {
    "context7 #supercharger": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    }
  }
}
```

Tagging approach: append `#supercharger` to the server name key (same pattern as hooks). This allows:
- Identifying Supercharger entries for removal
- Preserving user's own MCP servers
- Idempotent install (strip existing supercharger entries before re-adding)

### 2. Install Flow (install.sh)

After hook deployment, before summary:

1. Source `lib/mcp.sh`
2. Build server list: `get_core_servers()` + `get_role_servers(selected_roles)`
3. Call `merge_mcp_into_settings(servers)`
4. Print: "N MCP servers configured (3 core + M for [roles])"
5. Print: "Want more? Run: bash tools/mcp-setup.sh"

Non-interactive mode: works automatically with existing `--mode` and `--roles` flags. No new flags needed.

### 3. Uninstall (uninstall.sh)

Add call to `remove_supercharger_mcp()` alongside existing hook removal. User's own MCP servers preserved.

### 4. mcp-setup.sh Rewrite (tools/mcp-setup.sh)

- Target `~/.claude/settings.json` (not `claude_desktop_config.json`)
- Split UI: "Zero-config (already installed)" vs "API key required"
- Show which servers are already configured (skip duplicates)
- Add `#supercharger` tagging
- Keep tier selection for advanced servers
- Prompt for API keys inline (for advanced tool only — not during install)

### 5. claude-check.sh Update (tools/claude-check.sh)

Add MCP section to health check:
- List configured MCP servers from settings.json
- Distinguish Supercharger vs user-configured
- Flag missing core servers

### 6. README Update

Add MCP section after Hooks table:

```markdown
## MCP Servers

Supercharger auto-configures MCP servers during install — zero API keys, zero JSON editing.

| Tier | Servers | Setup |
|------|---------|-------|
| **Core** (all roles) | Context7, Sequential Thinking, Memory | Automatic |
| **Developer** | + Playwright, Magic UI | Automatic |
| **Writer/Student/Data/PM** | + DuckDuckGo Search | Automatic |
| **Advanced** | GitHub, Brave Search, Slack, Notion, + more | `bash tools/mcp-setup.sh` |
```

### 7. Tests (tests/test-mcp.sh)

New test file:
1. Core servers present after install (3 entries in settings.json)
2. Developer role adds Playwright + Magic UI
3. Writer role adds DuckDuckGo Search
4. Multi-role deduplication (developer+pm doesn't duplicate DuckDuckGo)
5. Uninstall removes only `#supercharger` MCP entries
6. User's existing MCP servers preserved after install
7. User's existing MCP servers preserved after uninstall
8. Idempotent — no duplicate entries after double install

## Files Changed

| File | Change |
|------|--------|
| `lib/mcp.sh` | **New** — MCP server assembly and settings.json merge |
| `install.sh` | Source lib/mcp.sh, call after hooks |
| `uninstall.sh` | Call remove_supercharger_mcp() |
| `tools/mcp-setup.sh` | Rewrite: target settings.json, add tagging, split tiers |
| `tools/claude-check.sh` | Add MCP server section |
| `README.md` | Add MCP section |
| `CHANGELOG.md` | Update |
| `tests/test-mcp.sh` | **New** — 8 MCP tests |

## Success Criteria

- [ ] Core servers (3) auto-configured for all roles during install
- [ ] Role-specific servers match selection and are deduplicated
- [ ] All auto-enabled servers are zero-config (no API keys, no prompts)
- [ ] No role exceeds 5 total MCP servers
- [ ] User's existing MCP servers never touched
- [ ] Uninstall cleanly removes only Supercharger MCP entries
- [ ] mcp-setup.sh targets settings.json with advanced servers
- [ ] claude-check.sh shows MCP status
- [ ] 8+ new MCP tests pass
- [ ] All 57 existing tests still pass
- [ ] README and CHANGELOG updated
