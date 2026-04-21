#!/usr/bin/env bash
# Claude Supercharger — Installation Health Check
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════╗"
echo "║    Claude Supercharger Health Check       ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(grep -m1 '^VERSION=' "$REPO_DIR/lib/utils.sh" 2>/dev/null | tr -d '"' | cut -d= -f2 || echo "?")

ERRORS=0

# Health score accumulators
SCORE_CORE=0      # max 40
SCORE_HOOKS=0     # max 25
SCORE_ECONOMY=0   # max 15
SCORE_TEAM=0      # max 10
SCORE_HYGIENE=0   # max 10

check_file() {
  local path="$1"
  local label="$2"
  local points="${3:-0}"
  if [ -f "$path" ]; then
    echo -e "  ${GREEN}✓${NC} $label"
    SCORE_CORE=$((SCORE_CORE + points))
  else
    echo -e "  ${RED}✗${NC} $label — ${RED}missing${NC}"
    ERRORS=$((ERRORS + 1))
  fi
}

# Config Files
echo -e "${BLUE}Config Files:${NC}"
check_file "$HOME/.claude/CLAUDE.md" "CLAUDE.md" 15
check_file "$HOME/.claude/rules/supercharger.md" "rules/supercharger.md — universal rules" 10
check_file "$HOME/.claude/rules/guardrails.md" "rules/guardrails.md — Four Laws + safety" 10

# Primary roles (active in rules/)
echo ""
echo -e "${BLUE}Primary Roles (active):${NC}"
ROLES_FOUND=""
for role in developer writer student data pm designer devops researcher; do
  if [ -f "$HOME/.claude/rules/${role}.md" ]; then
    ROLE_LABEL="$(echo "${role:0:1}" | tr '[:lower:]' '[:upper:]')${role:1}"
    echo -e "  ${GREEN}✓${NC} ${ROLE_LABEL}"
    ROLES_FOUND="${ROLES_FOUND:+$ROLES_FOUND, }$ROLE_LABEL"
  fi
done
if [ -z "$ROLES_FOUND" ]; then
  echo -e "  ${YELLOW}○${NC} No primary roles found"
else
  SCORE_CORE=$((SCORE_CORE + 5))
fi

echo ""
echo -e "${BLUE}Available Roles (mode switching):${NC}"
AVAILABLE_FOUND=""
for role in developer writer student data pm designer devops researcher; do
  if [ -f "$HOME/.claude/supercharger/roles/${role}.md" ]; then
    ROLE_LABEL="$(echo "${role:0:1}" | tr '[:lower:]' '[:upper:]')${role:1}"
    AVAILABLE_FOUND="${AVAILABLE_FOUND:+$AVAILABLE_FOUND, }$ROLE_LABEL"
  fi
done
if [ -n "$AVAILABLE_FOUND" ]; then
  echo -e "  ${GREEN}✓${NC} ${AVAILABLE_FOUND}"
else
  echo -e "  ${YELLOW}○${NC} No role files in supercharger/roles/"
fi

# Shared assets
echo ""
echo -e "${BLUE}Shared Assets:${NC}"
check_file "$HOME/.claude/rules/anti-patterns.yml" "rules/anti-patterns.yml"

# Hooks
echo ""
echo -e "${BLUE}Hooks:${NC}"
if [ -f "$HOME/.claude/settings.json" ]; then
  HOOK_COUNT=$(SETTINGS_PATH="$HOME/.claude/settings.json" python3 -c "
import json, os
with open(os.environ['SETTINGS_PATH']) as f:
    s = json.load(f)
hooks = s.get('hooks', {})
count = 0
for event in hooks.values():
    for entry in event:
        for h in entry.get('hooks', []):
            if 'supercharger' in h.get('command', ''):
                count += 1
        if 'supercharger' in entry.get('command', ''):
            count += 1
print(count)
" 2>/dev/null || echo "0")
  echo -e "  ${GREEN}✓${NC} settings.json valid — ${HOOK_COUNT} Supercharger hook(s) registered"
  # Score: 5 for any hooks, +5 for 10+, +5 for 20+, +5 for 35+, +5 for 50+
  if [ "$HOOK_COUNT" -gt 0 ]; then SCORE_HOOKS=$((SCORE_HOOKS + 5)); fi
  if [ "$HOOK_COUNT" -ge 10 ]; then SCORE_HOOKS=$((SCORE_HOOKS + 5)); fi
  if [ "$HOOK_COUNT" -ge 20 ]; then SCORE_HOOKS=$((SCORE_HOOKS + 5)); fi
  if [ "$HOOK_COUNT" -ge 35 ]; then SCORE_HOOKS=$((SCORE_HOOKS + 5)); fi
  if [ "$HOOK_COUNT" -ge 50 ]; then SCORE_HOOKS=$((SCORE_HOOKS + 5)); fi

  if [ -d "$HOME/.claude/supercharger/hooks" ]; then
    for hook in safety notify git-safety quality-gate enforce-pkg-manager audit-trail project-config prompt-validator compaction-backup; do
      if [ -f "$HOME/.claude/supercharger/hooks/${hook}.sh" ]; then
        if grep -q "${hook}.sh" "$HOME/.claude/settings.json" 2>/dev/null; then
          echo -e "    ${GREEN}✓${NC} ${hook} — active"
        else
          echo -e "    ${YELLOW}○${NC} ${hook} — installed but not active"
        fi
      fi
    done
  fi
else
  echo -e "  ${YELLOW}○${NC} No settings.json — no hooks installed"
fi

# Statusline
echo ""
echo -e "${BLUE}Statusline:${NC}"
if [ -f "$HOME/.claude/settings.json" ]; then
  SL_CMD=$(SETTINGS_PATH="$HOME/.claude/settings.json" python3 -c "
import json, os
with open(os.environ['SETTINGS_PATH']) as f:
    s = json.load(f)
cmd = s.get('statusLine', {}).get('command', '')
print(cmd)
" 2>/dev/null)
  if echo "$SL_CMD" | grep -q "#supercharger"; then
    echo -e "  ${GREEN}✓${NC} Enhanced statusline — active"
    SCORE_CORE=$((SCORE_CORE > 40 ? 40 : SCORE_CORE))  # cap before adding; statusline is bonus via economy
  elif [ -n "$SL_CMD" ]; then
    echo -e "  ${YELLOW}○${NC} Custom statusline configured (not Supercharger)"
  else
    echo -e "  ${YELLOW}○${NC} No statusline configured"
  fi
else
  echo -e "  ${YELLOW}○${NC} No settings.json — no statusline"
fi

# MCP Servers
echo ""
echo -e "${BLUE}MCP Servers:${NC}"
if [ -f "$HOME/.claude.json" ]; then
  SETTINGS_PATH="$HOME/.claude.json" python3 -c "
import json, os
with open(os.environ['SETTINGS_PATH']) as f:
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
    print(f'  \033[0;31m✗\033[0m Missing core: {\", \".join(missing)}')
" 2>/dev/null
else
  echo -e "  ${YELLOW}○${NC} No ~/.claude.json — no MCP servers"
fi

# Stack Detection
echo ""
echo -e "${BLUE}Detected Stack:${NC}"
DETECT_SCRIPT="$HOME/.claude/supercharger/hooks/detect-stack.sh"
if [ -f "$DETECT_SCRIPT" ]; then
  STACK_OUTPUT=$(bash "$DETECT_SCRIPT" 2>/dev/null || echo "detected=false")
  if echo "$STACK_OUTPUT" | grep -q "detected=true"; then
    LANG=$(echo "$STACK_OUTPUT" | grep '^language=' | cut -d= -f2-)
    FW=$(echo "$STACK_OUTPUT" | grep '^framework=' | cut -d= -f2-)
    PM=$(echo "$STACK_OUTPUT" | grep '^package_manager=' | cut -d= -f2-)
    TEST_FW=$(echo "$STACK_OUTPUT" | grep '^test_framework=' | cut -d= -f2-)
    BUILD=$(echo "$STACK_OUTPUT" | grep '^build_tool=' | cut -d= -f2-)
    [ -n "$LANG" ] && echo -e "  ${GREEN}✓${NC} Language: ${BOLD}${LANG}${NC}"
    [ -n "$FW" ] && echo -e "  ${GREEN}✓${NC} Framework: ${BOLD}${FW}${NC}"
    [ -n "$PM" ] && echo -e "  ${GREEN}✓${NC} Package manager: ${BOLD}${PM}${NC}"
    [ -n "$TEST_FW" ] && echo -e "  ${GREEN}✓${NC} Testing: ${BOLD}${TEST_FW}${NC}"
    [ -n "$BUILD" ] && echo -e "  ${GREEN}✓${NC} Build: ${BOLD}${BUILD}${NC}"
  else
    echo -e "  ${YELLOW}○${NC} No project files detected in current directory"
  fi
else
  echo -e "  ${YELLOW}○${NC} detect-stack not installed"
fi

# Session Summaries
echo ""
echo -e "${BLUE}Session Summaries:${NC}"
SUMMARIES_DIR="$HOME/.claude/supercharger/summaries"
SUMMARY_COUNT=$(find "$SUMMARIES_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$SUMMARY_COUNT" -gt 0 ]; then
  LATEST=$(find "$SUMMARIES_DIR" -maxdepth 1 -name '*.md' -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo "?")
  echo -e "  ${GREEN}✓${NC} ${SUMMARY_COUNT} summary file(s) — latest: ${LATEST}"
else
  echo -e "  ${YELLOW}○${NC} No session summaries yet — say 'session summary' in Claude Code"
fi

# Config Validation
echo ""
echo -e "${BLUE}Config Validation:${NC}"
LINT_ISSUES=0

# Check for empty rule files
for rule in "$HOME/.claude/rules/"*.md "$HOME/.claude/rules/"*.yml; do
  if [ -f "$rule" ] && [ ! -s "$rule" ]; then
    echo -e "  ${RED}✗${NC} Empty file: $(basename "$rule")"
    LINT_ISSUES=$((LINT_ISSUES + 1))
  fi
done

# Check CLAUDE.md size (warn if > 200 lines — wastes context)
if [ -f "$HOME/.claude/CLAUDE.md" ]; then
  LINE_COUNT=$(wc -l < "$HOME/.claude/CLAUDE.md" | tr -d ' ')
  if [ "$LINE_COUNT" -gt 200 ]; then
    echo -e "  ${YELLOW}⚠${NC} CLAUDE.md is ${LINE_COUNT} lines (>200) — may waste context tokens"
    LINT_ISSUES=$((LINT_ISSUES + 1))
  fi
fi

# Check hook scripts are executable
if [ -d "$HOME/.claude/supercharger/hooks" ]; then
  for hook_script in "$HOME/.claude/supercharger/hooks/"*.sh; do
    if [ -f "$hook_script" ] && [ ! -x "$hook_script" ]; then
      echo -e "  ${RED}✗${NC} Not executable: $(basename "$hook_script")"
      LINT_ISSUES=$((LINT_ISSUES + 1))
    fi
  done
fi

# Check for syntax errors in hook scripts
if [ -d "$HOME/.claude/supercharger/hooks" ]; then
  for hook_script in "$HOME/.claude/supercharger/hooks/"*.sh; do
    if [ -f "$hook_script" ]; then
      if ! bash -n "$hook_script" 2>/dev/null; then
        echo -e "  ${RED}✗${NC} Syntax error: $(basename "$hook_script")"
        LINT_ISSUES=$((LINT_ISSUES + 1))
      fi
    fi
  done
fi

# Check settings.json is valid JSON
if [ -f "$HOME/.claude/settings.json" ]; then
  if ! SETTINGS_PATH="$HOME/.claude/settings.json" python3 -c "import json, os; json.load(open(os.environ['SETTINGS_PATH']))" 2>/dev/null; then
    echo -e "  ${RED}✗${NC} settings.json is malformed JSON"
    LINT_ISSUES=$((LINT_ISSUES + 1))
    ERRORS=$((ERRORS + 1))
  fi
fi

if [ "$LINT_ISSUES" -eq 0 ]; then
  echo -e "  ${GREEN}✓${NC} All config files valid"
  SCORE_HYGIENE=10
else
  # Deduct proportionally, min 0
  SCORE_HYGIENE=$((10 - LINT_ISSUES * 3))
  [ "$SCORE_HYGIENE" -lt 0 ] && SCORE_HYGIENE=0
fi

# Features you're not using
echo ""
echo -e "${BLUE}Features You're Not Using:${NC}"
UNUSED=0

# Check webhook
if [ ! -f "$HOME/.claude/supercharger/webhook.json" ]; then
  echo -e "  ${YELLOW}→${NC} Webhook notifications — get Slack/Discord/Telegram alerts"
  echo -e "    Run: ${BOLD}bash tools/webhook-setup.sh${NC}"
  UNUSED=$((UNUSED + 1))
else
  SCORE_TEAM=$((SCORE_TEAM + 4))
fi

# Check profiles
if [ ! -f "$HOME/.claude/supercharger/.active-profile" ]; then
  echo -e "  ${YELLOW}→${NC} Profiles — switch role+economy+MCP in one command"
  echo -e "    Run: ${BOLD}bash tools/profile-switch.sh --list${NC}"
  UNUSED=$((UNUSED + 1))
else
  SCORE_TEAM=$((SCORE_TEAM + 3))
fi

# Check project config
if [ ! -f ".supercharger.json" ]; then
  echo -e "  ${YELLOW}→${NC} Project config — auto-apply roles/economy when opening this project"
  echo -e "    Create: ${BOLD}.supercharger.json${NC} in project root"
  UNUSED=$((UNUSED + 1))
else
  SCORE_TEAM=$((SCORE_TEAM + 3))
fi

# Check economy tier (default lean may not be optimal)
if [ -f "$HOME/.claude/rules/economy.md" ]; then
  ACTIVE_TIER=$(grep -i "Active Tier:" "$HOME/.claude/rules/economy.md" 2>/dev/null | head -1 | sed 's/.*Active Tier:[[:space:]]*//' | sed 's/[[:space:]].*//' || echo "")
  if [ -z "$ACTIVE_TIER" ]; then
    echo -e "  ${YELLOW}→${NC} Economy tier — not detected. Run: ${BOLD}bash tools/economy-switch.sh lean${NC}"
    UNUSED=$((UNUSED + 1))
  else
    SCORE_ECONOMY=$((SCORE_ECONOMY + 15))
  fi
fi

# Check inactive roles (installed in supercharger/roles/ but not in rules/)
INACTIVE_ROLES=""
for role in developer writer student data pm designer devops researcher; do
  if [ -f "$HOME/.claude/supercharger/roles/${role}.md" ] && [ ! -f "$HOME/.claude/rules/${role}.md" ]; then
    ROLE_LABEL="$(echo "${role:0:1}" | tr '[:lower:]' '[:upper:]')${role:1}"
    INACTIVE_ROLES="${INACTIVE_ROLES:+$INACTIVE_ROLES, }$ROLE_LABEL"
  fi
done
if [ -n "$INACTIVE_ROLES" ]; then
  echo -e "  ${YELLOW}→${NC} Inactive roles available: ${INACTIVE_ROLES}"
  echo -e "    Switch mid-conversation: ${BOLD}\"as [role]\"${NC}"
  UNUSED=$((UNUSED + 1))
fi

# Check session summaries
if [ ! -d "$HOME/.claude/supercharger/summaries" ] || [ -z "$(ls -A "$HOME/.claude/supercharger/summaries" 2>/dev/null)" ]; then
  echo -e "  ${YELLOW}→${NC} Session summaries — never lose context across sessions"
  echo -e "    Say: ${BOLD}\"session summary\"${NC} in Claude Code"
  UNUSED=$((UNUSED + 1))
fi

if [ "$UNUSED" -eq 0 ]; then
  echo -e "  ${GREEN}✓${NC} You're using everything!"
fi

# Cap categories
[ "$SCORE_CORE" -gt 40 ] && SCORE_CORE=40
[ "$SCORE_HOOKS" -gt 25 ] && SCORE_HOOKS=25
[ "$SCORE_ECONOMY" -gt 15 ] && SCORE_ECONOMY=15
[ "$SCORE_TEAM" -gt 10 ] && SCORE_TEAM=10
[ "$SCORE_HYGIENE" -gt 10 ] && SCORE_HYGIENE=10

TOTAL_SCORE=$((SCORE_CORE + SCORE_HOOKS + SCORE_ECONOMY + SCORE_TEAM + SCORE_HYGIENE))

# Color based on score
if [ "$TOTAL_SCORE" -ge 80 ]; then
  SCORE_COLOR="$GREEN"
elif [ "$TOTAL_SCORE" -ge 50 ]; then
  SCORE_COLOR="$YELLOW"
else
  SCORE_COLOR="$RED"
fi

# Build progress bar (20 chars wide)
FILLED=$((TOTAL_SCORE / 5))
EMPTY=$((20 - FILLED))
BAR="${SCORE_COLOR}"
for ((i=0; i<FILLED; i++)); do BAR+="█"; done
BAR+="${NC}"
for ((i=0; i<EMPTY; i++)); do BAR+="░"; done

# Health Score
echo ""
echo -e "${CYAN}────────────────────────────────────────────${NC}"
echo -e "${BOLD}Health Score: ${SCORE_COLOR}${TOTAL_SCORE}/100${NC}  ${BAR}"
echo ""
echo -e "  Core     ${SCORE_CORE}/40   (CLAUDE.md, rules, roles)"
echo -e "  Hooks    ${SCORE_HOOKS}/25   (registered hooks)"
echo -e "  Economy  ${SCORE_ECONOMY}/15   (tier configured)"
echo -e "  Team     ${SCORE_TEAM}/10   (webhooks, profiles, project config)"
echo -e "  Hygiene  ${SCORE_HYGIENE}/10   (no errors, valid configs)"
echo ""

if [ -n "$ROLES_FOUND" ]; then
  echo -e "Roles: ${BOLD}$ROLES_FOUND${NC}"
fi
ACTIVE_PROFILE="$HOME/.claude/supercharger/.active-profile"
if [ -f "$ACTIVE_PROFILE" ]; then
  echo -e "Profile: ${BOLD}$(cat "$ACTIVE_PROFILE")${NC}"
fi
if [ -f ".supercharger.json" ]; then
  echo -e "Project config: ${GREEN}.supercharger.json detected${NC}"
fi
echo -e "Version: ${BOLD}${VERSION}${NC}"
echo ""

if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}All checks passed ✓${NC}"
else
  echo -e "${RED}${ERRORS} issue(s) found. Run install.sh to fix.${NC}"
fi
echo ""
# Analytics Summary
echo -e "${BLUE}Analytics (7d):${NC}"
PROJECTS_BASE="$HOME/.claude/projects"
if [ -d "$PROJECTS_BASE" ]; then
  ANALYTICS_SUMMARY=$(SUPERCHARGER_PROJECTS_DIR="$PROJECTS_BASE" python3 << 'PYEOF'
import os, json, time

PRICE = {'input': 3.00, 'cache_write': 3.75, 'cache_read': 0.30, 'output': 15.00}
projects_dir = os.environ.get('SUPERCHARGER_PROJECTS_DIR', '')
cutoff = time.time() - 7 * 86400

total = dict(input=0, cache_write=0, cache_read=0, output=0, sessions=0)
total_cost = total_saved = 0.0

for proj in os.listdir(projects_dir):
    proj_path = os.path.join(projects_dir, proj)
    if not os.path.isdir(proj_path):
        continue
    try:
        for fname in os.listdir(proj_path):
            if not fname.endswith('.jsonl'):
                continue
            fpath = os.path.join(proj_path, fname)
            try:
                if os.path.getmtime(fpath) < cutoff:
                    continue
            except OSError:
                continue
            turns = 0
            t = dict(input=0, cache_write=0, cache_read=0, output=0)
            try:
                with open(fpath) as f:
                    for line in f:
                        try:
                            d = json.loads(line)
                            if d.get('type') == 'assistant':
                                u = d.get('message', {}).get('usage', {})
                                if u:
                                    inp = u.get('input_tokens', 0)
                                    cw  = u.get('cache_creation_input_tokens', 0)
                                    cr  = u.get('cache_read_input_tokens', 0)
                                    out = u.get('output_tokens', 0)
                                    if inp + cw + cr + out > 0:
                                        t['input']       += inp
                                        t['cache_write'] += cw
                                        t['cache_read']  += cr
                                        t['output']      += out
                                        turns += 1
                        except:
                            pass
            except:
                continue
            if turns == 0:
                continue
            total['sessions'] += 1
            for k in ('input', 'cache_write', 'cache_read', 'output'):
                total[k] += t[k]
            cost = (t['input'] / 1e6 * PRICE['input'] +
                    t['cache_write'] / 1e6 * PRICE['cache_write'] +
                    t['cache_read']  / 1e6 * PRICE['cache_read'] +
                    t['output']      / 1e6 * PRICE['output'])
            saved = t['cache_read'] / 1e6 * (PRICE['input'] - PRICE['cache_read'])
            total_cost  += cost
            total_saved += saved
    except OSError:
        continue

denom = total['cache_read'] + total['input']
cache_pct = int(total['cache_read'] / denom * 100) if denom > 0 else 0

if total['sessions'] == 0:
    print("  no sessions in last 7 days")
else:
    s = total['sessions']
    print(f"  ${total_cost:.2f} across {s} session{'s' if s != 1 else ''} | cache {cache_pct}% | saved ${total_saved:.2f}")
PYEOF
  )
  echo -e "$ANALYTICS_SUMMARY"
else
  echo -e "  ${YELLOW}○${NC} No session data (${PROJECTS_BASE} not found)"
fi
echo ""
echo -e "For full capability overview: ${BOLD}bash tools/supercharger.sh${NC}"
