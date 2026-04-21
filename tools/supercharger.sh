#!/usr/bin/env bash
# Claude Supercharger — Capability Overview
# Shows everything Supercharger can do in one screen.

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

VERSION="1.0.3"
RULES_DIR="$HOME/.claude/rules"
SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SETTINGS="$HOME/.claude/settings.json"

mark_active() { echo -e "${GREEN}●${NC}"; }
mark_off()    { echo -e "${DIM}○${NC}"; }

# ── Header ──────────────────────────────────────────────────────────────
echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════╗"
echo "║    Claude Supercharger v${VERSION} — What's On   ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

# ── 1. Your Setup ────────────────────────────────────────────────────────
echo -e "${BLUE}${BOLD}Your Setup${NC}"

# Active roles (files in rules/ excluding non-role files)
ACTIVE_ROLES=""
for role in developer writer student data pm designer devops researcher; do
  if [ -f "$RULES_DIR/${role}.md" ]; then
    LABEL="$(echo "${role:0:1}" | tr '[:lower:]' '[:upper:]')${role:1}"
    ACTIVE_ROLES="${ACTIVE_ROLES:+$ACTIVE_ROLES, }$LABEL"
  fi
done
if [ -n "$ACTIVE_ROLES" ]; then
  echo -e "  Roles:    ${GREEN}${ACTIVE_ROLES}${NC}"
else
  echo -e "  Roles:    ${YELLOW}none${NC}"
fi

# Economy tier — grep for "Active Tier:" in economy.md
ECONOMY_TIER="unknown"
if [ -f "$RULES_DIR/economy.md" ]; then
  DETECTED=$(grep -m1 "^### Active Tier:" "$RULES_DIR/economy.md" 2>/dev/null | sed 's/.*Active Tier: *//' | awk '{print $1}')
  [ -n "$DETECTED" ] && ECONOMY_TIER="$DETECTED"
fi
echo -e "  Economy:  ${GREEN}${ECONOMY_TIER}${NC}"

# Active profile
ACTIVE_PROFILE="$SUPERCHARGER_DIR/.active-profile"
if [ -f "$ACTIVE_PROFILE" ]; then
  echo -e "  Profile:  ${GREEN}$(cat "$ACTIVE_PROFILE")${NC}"
else
  echo -e "  Profile:  ${YELLOW}none${NC}"
fi

# Project config
if [ -f ".supercharger.json" ]; then
  echo -e "  Project:  ${GREEN}.supercharger.json detected${NC}"
else
  echo -e "  Project:  ${DIM}no .supercharger.json in current dir${NC}"
fi

echo ""

# ── 2. Mid-Conversation Commands ─────────────────────────────────────────
echo -e "${BLUE}${BOLD}Mid-Conversation Commands${NC}"
echo -e "  ${DIM}Say these in any Claude Code chat:${NC}"
echo ""

echo -e "  ${BOLD}Role switching${NC} — changes active persona + rules"
for role in developer writer student data pm designer devops researcher; do
  LABEL="$(echo "${role:0:1}" | tr '[:lower:]' '[:upper:]')${role:1}"
  if [ -f "$RULES_DIR/${role}.md" ]; then
    echo -e "    $(mark_active) \"as ${role}\"  ${DIM}(active)${NC}"
  elif [ -f "$SUPERCHARGER_DIR/roles/${role}.md" ]; then
    echo -e "    $(mark_off) \"as ${role}\"  ${DIM}(available, not active)${NC}"
  fi
done

echo ""
echo -e "  ${BOLD}Economy switching${NC} — controls response verbosity"
for tier in standard lean minimal; do
  LABEL="$tier"
  if [ "$tier" = "$ECONOMY_TIER" ] || echo "$ECONOMY_TIER" | grep -qi "$tier"; then
    echo -e "    $(mark_active) \"eco ${tier}\"  ${DIM}(active)${NC}"
  else
    echo -e "    $(mark_off) \"eco ${tier}\""
  fi
done

echo ""
echo -e "  ${BOLD}Workflow commands${NC}"
echo -e "    ${CYAN}»${NC} \"session summary\"     — generate handoff block for next session"
echo -e "    ${CYAN}»${NC} \"interview me\"        — scored clarification mode, one Q at a time"
echo -e "    ${CYAN}»${NC} \"deep interview\"      — same, with deeper assumption surfacing"

echo ""

# ── 3. Installed Hooks ───────────────────────────────────────────────────
echo -e "${BLUE}${BOLD}Installed Hooks${NC}"
HOOKS_DIR="$SUPERCHARGER_DIR/hooks"

HOOK_DESCS="safety:Blocks dangerous commands before execution
notify:Sends webhook notification on task completion
git-safety:Warns on force-push and destructive git ops
quality-gate:Runs linter/tests and blocks commit if failing
enforce-pkg-manager:Prevents wrong package manager (e.g. npm in pnpm project)
audit-trail:Logs all file writes and deletions to .claude/audit/
project-config:Loads .supercharger.json overrides at session start
prompt-validator:Flags ambiguous or high-risk prompts before execution
compaction-backup:Saves context snapshot before /compact runs
scope-guard:Prevents writes outside declared scope during a session
update-check:Checks for Supercharger updates at session start
session-complete:Saves session summary on Stop event
detect-stack:Detects project language, framework, and package manager"

if [ -d "$HOOKS_DIR" ]; then
  FOUND_HOOKS=0
  for hook in safety notify git-safety quality-gate enforce-pkg-manager audit-trail project-config scope-guard update-check prompt-validator compaction-backup session-complete; do
    if [ -f "$HOOKS_DIR/${hook}.sh" ]; then
      DESC=$(echo "$HOOK_DESCS" | grep "^${hook}:" | cut -d: -f2-)
      if [ -f "$SETTINGS" ] && grep -q "${hook}.sh" "$SETTINGS" 2>/dev/null; then
        echo -e "  $(mark_active) ${BOLD}${hook}${NC} — ${DESC}"
        if [[ "$hook" == "notify" ]]; then
          NO_NOTIFY_FLAG="$SUPERCHARGER_DIR/.no-desktop-notify"
          if [ -f "$NO_NOTIFY_FLAG" ]; then
            echo -e "    ${DIM}↳ desktop popup: off  (bash tools/notify-toggle.sh on to re-enable)${NC}"
          else
            echo -e "    ${DIM}↳ desktop popup: on   (bash tools/notify-toggle.sh off to disable)${NC}"
          fi
        fi
      else
        echo -e "  $(mark_off) ${hook} — ${DESC} ${YELLOW}(installed, not active)${NC}"
      fi
      FOUND_HOOKS=$((FOUND_HOOKS + 1))
    fi
  done
  if [ "$FOUND_HOOKS" -eq 0 ]; then
    echo -e "  ${YELLOW}○${NC} No hooks installed — run ${BOLD}install.sh${NC} to add them"
  fi
else
  echo -e "  ${YELLOW}○${NC} Hooks directory not found — run ${BOLD}install.sh${NC}"
fi

echo ""

# ── 4. Available Tools ───────────────────────────────────────────────────
echo -e "${BLUE}${BOLD}Available Tools${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOOL_DESCS="claude-check.sh:Health check — verify installation & config
economy-switch.sh:Permanently change economy tier (standard/lean/minimal)
export-preset.sh:Export current config as a .supercharger file for sharing
hook-toggle.sh:Enable or disable individual hooks without reinstalling
import-preset.sh:Apply a teammate's .supercharger preset file
mcp-setup.sh:Install and configure MCP servers (context7, sequential, etc.)
profile-switch.sh:Switch active persona profile
resume.sh:Restore session from a saved summary
supercharger.sh:This screen — capability overview
webhook-setup.sh:Configure Slack/Discord/Telegram notifications"

for tool in claude-check.sh economy-switch.sh export-preset.sh hook-toggle.sh import-preset.sh mcp-setup.sh profile-switch.sh resume.sh supercharger.sh webhook-setup.sh; do
  if [ -f "$SCRIPT_DIR/${tool}" ]; then
    DESC=$(echo "$TOOL_DESCS" | grep "^${tool}:" | cut -d: -f2-)
    echo -e "  ${GREEN}✓${NC} ${BOLD}tools/${tool}${NC} — ${DESC}"
  fi
done

echo ""

# ── 5. Features Not In Use ───────────────────────────────────────────────
echo -e "${BLUE}${BOLD}Features You're Not Using${NC}"
NOT_USING=0

# Webhook
WEBHOOK_CFG="$SUPERCHARGER_DIR/webhook.json"
if [ ! -f "$WEBHOOK_CFG" ]; then
  echo -e "  ${YELLOW}○${NC} Webhook notifications — run ${BOLD}tools/webhook-setup.sh${NC}"
  NOT_USING=$((NOT_USING + 1))
else
  WEBHOOK_ENABLED=$(WEBHOOK_PATH="$WEBHOOK_CFG" python3 -c "
import json,os
try:
    with open(os.environ['WEBHOOK_PATH']) as f:
        c=json.load(f)
    print('yes' if c.get('enabled') else 'no')
except:
    print('no')
" 2>/dev/null)
  if [ "$WEBHOOK_ENABLED" != "yes" ]; then
    echo -e "  ${YELLOW}○${NC} Webhook notifications — configured but disabled"
    NOT_USING=$((NOT_USING + 1))
  fi
fi

# Profiles
if [ ! -f "$ACTIVE_PROFILE" ]; then
  echo -e "  ${YELLOW}○${NC} Profiles — run ${BOLD}tools/profile-switch.sh${NC} to activate one"
  NOT_USING=$((NOT_USING + 1))
fi

# Hooks not active
if [ -f "$SETTINGS" ] && [ -d "$HOOKS_DIR" ]; then
  for hook in safety notify git-safety quality-gate; do
    if [ -f "$HOOKS_DIR/${hook}.sh" ] && ! grep -q "${hook}.sh" "$SETTINGS" 2>/dev/null; then
      echo -e "  ${YELLOW}○${NC} Hook ${BOLD}${hook}${NC} — installed but not wired in settings.json"
      NOT_USING=$((NOT_USING + 1))
    fi
  done
fi

# Available roles not active
for role in developer writer student data pm designer devops researcher; do
  if [ -f "$SUPERCHARGER_DIR/roles/${role}.md" ] && [ ! -f "$RULES_DIR/${role}.md" ]; then
    echo -e "  ${YELLOW}○${NC} Role ${BOLD}${role}${NC} — available but not active (copy to ~/.claude/rules/)"
    NOT_USING=$((NOT_USING + 1))
  fi
done

# MCP servers
if [ -f "$SETTINGS" ]; then
  MCP_COUNT=$(SETTINGS_PATH="$SETTINGS" python3 -c "
import json,os
with open(os.environ['SETTINGS_PATH']) as f:
    s=json.load(f)
print(len(s.get('mcpServers',{})))
" 2>/dev/null || echo "0")
  if [ "$MCP_COUNT" -eq 0 ]; then
    echo -e "  ${YELLOW}○${NC} MCP servers — none configured (run ${BOLD}tools/mcp-setup.sh${NC})"
    NOT_USING=$((NOT_USING + 1))
  fi
fi

# Project config
if [ ! -f ".supercharger.json" ]; then
  echo -e "  ${YELLOW}○${NC} Project config — add ${BOLD}.supercharger.json${NC} for per-project overrides"
  NOT_USING=$((NOT_USING + 1))
fi

if [ "$NOT_USING" -eq 0 ]; then
  echo -e "  ${GREEN}✓${NC} You're using everything — nice."
fi

# ── Footer ───────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}────────────────────────────────────────────${NC}"

# Inline update check (non-blocking, best-effort)
REMOTE_VERSION=$(python3 -c "
import urllib.request, json, base64
try:
    url = 'https://api.github.com/repos/smrafiz/claude-supercharger/contents/lib/utils.sh'
    req = urllib.request.Request(url, headers={'User-Agent': 'claude-supercharger'})
    with urllib.request.urlopen(req, timeout=3) as r:
        data = json.load(r)
    content = base64.b64decode(data['content']).decode()
    for line in content.splitlines():
        if line.startswith('VERSION='):
            print(line.split('=')[1].strip('\"'))
            break
except Exception:
    print('')
" 2>/dev/null)

if [ -n "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$VERSION" ]; then
  echo -e "${YELLOW}  Update available: v${VERSION} → v${REMOTE_VERSION}${NC}"
  echo -e "${DIM}  Run: bash ~/.claude/supercharger/tools/update.sh${NC}"
  echo ""
fi

echo -e "${DIM}Health check: tools/claude-check.sh  |  v${VERSION}${NC}"
