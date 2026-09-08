#!/usr/bin/env bash
# Claude Supercharger — Installation Health Check
set -euo pipefail

# Windows python defaults stdout to the ANSI codepage (cp1252) and raises
# UnicodeEncodeError on the box-drawing and arrow characters this tool prints,
# losing ALL of its output. Hooks get this from hooks/lib-paths.sh; tools do not
# reach that file, so they set it themselves. `:=` honours an explicit setting.
: "${PYTHONIOENCODING:=utf-8}"
: "${PYTHONUTF8:=1}"
export PYTHONIOENCODING PYTHONUTF8

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

# Safe Mode detection (Claude Code v2.1.169+)
# CLAUDE_CODE_SAFE_MODE=1 disables ALL customizations including hooks, skills,
# plugins, MCP, and CLAUDE.md. Supercharger guards are entirely off in this mode.
if [ "${CLAUDE_CODE_SAFE_MODE:-}" = "1" ]; then
  echo -e "${RED}${BOLD}⚠  CLAUDE_CODE_SAFE_MODE=1 detected${NC}"
  echo -e "${YELLOW}Claude Code is running with --safe-mode — ALL Supercharger hooks,"
  echo -e "MCP servers, and rules are disabled. Health-check output below reflects"
  echo -e "what is INSTALLED, not what is ACTIVE in the current session.${NC}"
  echo -e "${YELLOW}Unset the env var or remove --safe-mode to restore guardrails.${NC}"
  echo ""
fi

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
  # Also counts entries that are PRESENT but inert. `"matcher": null` is a shape
  # hooks.json never writes for the events that take no matcher, and Claude Code
  # ignores it — a /sc off + on before v4.0.1 produced 59 of them while every
  # count still looked right. Present is not the same as working.
  read -r HOOK_COUNT HOOK_INERT <<<"$(SETTINGS_PATH="$HOME/.claude/settings.json" python3 -c "
import json, os
with open(os.environ['SETTINGS_PATH']) as f:
    s = json.load(f)
hooks = s.get('hooks', {})
count = inert = 0
for event in hooks.values():
    for entry in event:
        mine = 0
        for h in entry.get('hooks', []):
            if 'supercharger' in h.get('command', ''):
                mine += 1
        if 'supercharger' in entry.get('command', ''):
            mine += 1
        count += mine
        if 'matcher' in entry and entry['matcher'] is None:
            inert += mine
print(count, inert)
" 2>/dev/null || echo "0 0")"
  HOOK_COUNT=${HOOK_COUNT:-0}; HOOK_INERT=${HOOK_INERT:-0}
  echo -e "  ${GREEN}✓${NC} settings.json valid — ${HOOK_COUNT} Supercharger hook(s) registered"

  # Compare against what install.sh recorded leaving behind. Without a baseline
  # a count is just a number: 122 looks fine until you know it should be 154.
  HOOK_STAMP_FILE="$HOME/.claude/supercharger/.registration-count"
  if [ -r "$HOOK_STAMP_FILE" ]; then
    read -r HOOK_STAMP < "$HOOK_STAMP_FILE" 2>/dev/null || HOOK_STAMP=""
    case "${HOOK_STAMP:-}" in
      ''|*[!0-9]*) ;;
      *) if [ "$HOOK_STAMP" -gt 0 ] && [ "$HOOK_COUNT" -lt "$HOOK_STAMP" ]; then
           HOOK_SHORTFALL=$((HOOK_STAMP - HOOK_COUNT))
           echo -e "  ${RED}✗${NC} ${HOOK_SHORTFALL} registration(s) MISSING — install left ${HOOK_STAMP}, found ${HOOK_COUNT}. Those guards are not running. Fix: run /sc-update"
           ERRORS=$((ERRORS + 1))
         fi ;;
    esac
  else
    # No stamp: this install predates v4.0.1, so the count above cannot be
    # compared against anything. SAY SO. A guard is right to fail open — do not
    # block work you cannot assess — but this tool is an ORACLE: it prints a
    # health score, and people run it to find out whether they are protected.
    # Silence from a guard means "nothing to report"; silence from an oracle
    # reads as "verified". Reporting a full hooks score while structurally
    # unable to check completeness is a clean bill of health it cannot issue.
    echo -e "  ${YELLOW}○${NC} Completeness unverified — no install stamp, so ${HOOK_COUNT} cannot be checked against what the install left behind. Re-run: /sc-update"
  fi

  # v4.0.11: registrations being present is not the same as the deep scan having
  # RUN. safety-detect.py kills itself on a wall-clock overrun and exits 0 with no
  # output, which safety.sh cannot distinguish from a clean scan (`|| PY_REASON=""`
  # flattens every failure into the same silent allow). Measured 2026-09-01: about
  # 0.6% of calls under heavy parallel load, and some rules — the archive and
  # secret-directory checks among them — live ONLY in that file, so while it is
  # cut short they are not running at all.
  #
  # Same reasoning as the stamp branch above. Failing open there is correct; an
  # oracle staying quiet about it is not, because the number it prints reads as
  # "you were protected". Report it, do not score it: the fail-open is working as
  # designed and docking points for it would train people to ignore this tool.
  # NOTE: user-facing lines in this report print `~/...`, never the expanded
  # $HOME. This report exists to be PASTED to someone else for help, and an
  # absolute path carries the operator's account name — and, on a work machine,
  # often a client or project directory name with it. Borrowed from
  # jacksonanstee/agent-harness-JA ADR-0027, which found that 25 credential
  # rules matched no filesystem path, so every retained row kept the home
  # directory in cleartext.
  #
  # Only the SHAREABLE surface is normalised. That ADR built three designs to
  # rewrite paths at every retained sink and killed all three — Design B's
  # injectivity proof is false because `~` is a legal directory name at any
  # depth, so the substitution is not reversible. Do not rebuild that.
  OVERRUN_FILE="$HOME/.claude/supercharger/scope/.detect-overruns"
  if [ -r "$OVERRUN_FILE" ]; then
    OVERRUNS=$(grep -c . "$OVERRUN_FILE" 2>/dev/null | tr -d ' ' || true)
    case "${OVERRUNS:-0}" in
      ''|0|*[!0-9]*) ;;
      *) echo -e "  ${YELLOW}○${NC} Deep scan cut short ${OVERRUNS} time(s) — safety-detect.py hit its ${SUPERCHARGER_DETECT_BUDGET_S:-0.5}s budget and those calls fell back to the regex checks alone. Usually a loaded machine. Raise it with SUPERCHARGER_DETECT_BUDGET_S, or clear the log: rm ~/.claude/supercharger/scope/.detect-overruns" ;;
    esac
  fi
  if [ "${HOOK_INERT:-0}" -gt 0 ]; then
    echo -e "  ${RED}✗${NC} ${HOOK_INERT} registration(s) present but INERT (null matcher) — counted above, but Claude Code ignores them. Fix: run /sc-update"
    ERRORS=$((ERRORS + 1))
  fi
  # Score: 5 for any hooks, +5 for 10+, +5 for 20+, +5 for 35+, +5 for 50+
  if [ "$HOOK_COUNT" -gt 0 ]; then SCORE_HOOKS=$((SCORE_HOOKS + 5)); fi
  if [ "$HOOK_COUNT" -ge 10 ]; then SCORE_HOOKS=$((SCORE_HOOKS + 5)); fi
  if [ "$HOOK_COUNT" -ge 20 ]; then SCORE_HOOKS=$((SCORE_HOOKS + 5)); fi
  if [ "$HOOK_COUNT" -ge 35 ]; then SCORE_HOOKS=$((SCORE_HOOKS + 5)); fi
  if [ "$HOOK_COUNT" -ge 50 ]; then SCORE_HOOKS=$((SCORE_HOOKS + 5)); fi

  # The bands top out at 50, so an install missing a third of its registrations
  # still scored a perfect 25/25 while the lines above said "32 MISSING". A
  # report that contradicts itself is worse than either half alone: the reader
  # believes the number.
  if [ "${HOOK_SHORTFALL:-0}" -gt 0 ] || [ "${HOOK_INERT:-0}" -gt 0 ]; then
    SCORE_HOOKS=$((SCORE_HOOKS - 10))
    [ "$SCORE_HOOKS" -lt 0 ] && SCORE_HOOKS=0
  fi

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
# v4.0.38: every substitution below ends `|| true`. A no-match `grep` exits 1,
# and under this script's `set -euo pipefail` that ABORTS THE WHOLE DIAGNOSTIC
# mid-report — reported 2026-09-08 from a repo whose stack detects as
# JavaScript/pnpm/Vite with no framework: the script died here, so the session
# summaries, the Delivery & Integrity block and the paste-back verdict line never
# printed at all. A diagnostic that stops early is worse than one that reports a
# gap, because the reader cannot tell "clean" from "never got there".
echo -e "${BLUE}Detected Stack:${NC}"
DETECT_SCRIPT="$HOME/.claude/supercharger/hooks/detect-stack.sh"
if [ -f "$DETECT_SCRIPT" ]; then
  STACK_OUTPUT=$(bash "$DETECT_SCRIPT" 2>/dev/null || echo "detected=false")
  if echo "$STACK_OUTPUT" | grep -q "detected=true"; then
    LANG=$(echo "$STACK_OUTPUT" | grep '^language=' | cut -d= -f2- || true)
    FW=$(echo "$STACK_OUTPUT" | grep '^framework=' | cut -d= -f2- || true)
    PM=$(echo "$STACK_OUTPUT" | grep '^package_manager=' | cut -d= -f2- || true)
    TEST_FW=$(echo "$STACK_OUTPUT" | grep '^test_framework=' | cut -d= -f2- || true)
    BUILD=$(echo "$STACK_OUTPUT" | grep '^build_tool=' | cut -d= -f2- || true)
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
# `find` exits 1 if the dir is missing, and `pipefail` promotes that to the whole
# pipeline — so the group failed, `|| echo 0` APPENDED a second zero, and
# SUMMARY_COUNT became the two-line string "0\n0". The next line then ran
# `[ "0\n0" -gt 0 ]`, which prints
#     claude-check.sh: line NNN: [: 0
#     0: integer expression expected
# on stderr and skips the section. Only visible on a PRISTINE $HOME — i.e. a
# fresh install, or a colleague's first run — which is why it survived: the
# author's own machine always has the directory.
#
# Found 2026-09-08 by an assertion looking for something else entirely (absolute
# home paths in the shareable report); the error text carries the script's own
# path, so it tripped the path check. Second time today that `set -euo pipefail`
# plus a legitimately-nonzero command broke this script mid-report — the first
# was the no-match greps at "Detected Stack".
#
# Skip the pipeline when the directory is absent, then normalise defensively with
# the numeric-guard pattern used elsewhere in this codebase.
SUMMARY_COUNT=0
if [ -d "$SUMMARIES_DIR" ]; then
  SUMMARY_COUNT=$(find "$SUMMARIES_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ' || echo 0)
fi
case "$SUMMARY_COUNT" in ''|*[!0-9]*) SUMMARY_COUNT=0 ;; esac
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
    ERRORS=$((ERRORS + 1))
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
      ERRORS=$((ERRORS + 1))
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
        ERRORS=$((ERRORS + 1))
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

# Check fallbackModel chain (Claude Code v2.1.166+)
# A configured chain trips fewer "overloaded — try again" interruptions on
# Opus and routes degraded calls to Sonnet/Haiku instead of failing outright.
# Also check ENABLE_PROMPT_CACHING_1H (Anthropic dropped the default cache TTL
# from 1h to 5min on 2026-03-06 — API users now pay for cache rewrites if a
# pause exceeds 5 minutes. Claude Code subscriptions auto-request 1h when this
# env var is set).
if [ -f "$HOME/.claude/settings.json" ]; then
  SETTINGS_CHECK=$(SETTINGS_PATH="$HOME/.claude/settings.json" \
                   ENV_1H="${ENABLE_PROMPT_CACHING_1H:-}" python3 -c "
import json, os
with open(os.environ['SETTINGS_PATH']) as f:
    s = json.load(f)
fb = s.get('fallbackModel') or s.get('fallback_model')
env = (s.get('env') or {})
in_settings = str(env.get('ENABLE_PROMPT_CACHING_1H', '')).strip() in ('1', 'true', 'True')
in_shell = os.environ.get('ENV_1H', '').strip() in ('1', 'true', 'True')
print(f\"{1 if fb else 0}|{1 if (in_settings or in_shell) else 0}\")
" 2>/dev/null || echo "0|0")
  HAS_FALLBACK="${SETTINGS_CHECK%%|*}"
  HAS_CACHE_1H="${SETTINGS_CHECK##*|}"
  if [ "$HAS_FALLBACK" = "0" ]; then
    echo -e "  ${YELLOW}→${NC} fallbackModel chain not set — Opus overloads drop the call instead of routing to Sonnet/Haiku"
    echo -e "    Add to ${BOLD}~/.claude/settings.json${NC}: \"fallbackModel\": [\"claude-sonnet-4-6\", \"claude-haiku-4-5\"]"
    UNUSED=$((UNUSED + 1))
  fi
  if [ "$HAS_CACHE_1H" = "0" ]; then
    echo -e "  ${YELLOW}→${NC} ENABLE_PROMPT_CACHING_1H not set — default cache TTL is 5min (dropped from 1h on 2026-03-06)"
    echo -e "    Add to ${BOLD}~/.claude/settings.json${NC}: \"env\": {\"ENABLE_PROMPT_CACHING_1H\": \"1\"}"
    echo -e "    Pauses >5min currently re-pay the 1.25x cache write; 1h TTL pays 2x once and amortizes across hour-long sessions."
    UNUSED=$((UNUSED + 1))
  fi
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

# The verdict must not contradict the score printed three lines above it.
# "All checks passed ✓" next to 87/100 and Team 0/10 leaves the reader unable to
# tell a FAULT from an UNCONFIGURED optional feature — and that ambiguity is what
# makes a summary line stop being read. ERRORS counts things that are broken;
# the score also counts things merely not set up. Say which is which.
if [ "$ERRORS" -eq 0 ] && [ "$TOTAL_SCORE" -ge 100 ]; then
  echo -e "${GREEN}All checks passed ✓${NC}"
elif [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}No faults found ✓${NC}  ${YELLOW}(score ${TOTAL_SCORE}/100 — optional features not configured, nothing is broken)${NC}"
else
  echo -e "${RED}${ERRORS} issue(s) found. Fix: run /sc-update${NC}"
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

# ── Delivery & Integrity ──────────────────────────────────────────────────────
# Four checks, each earned by a defect that shipped. Everything above this point
# trusts the version stamp; these do not, because the stamp is what lied.
echo ""
echo -e "${BLUE}Delivery & Integrity:${NC}"

_DOC_STATE="${SUPERCHARGER_STATE:-$HOME/.claude/supercharger}"
_DOC_UPDATE="none"
_DOC_INTEGRITY="ok"
_DOC_STATE_MODE="?"

# 1. Does the DEPLOYED tree match the version it claims?
#    update.sh once compared the repo to itself and reported success while
#    deploying nothing — a 15-version-stale install with a correct-looking
#    stamp. Every other check here trusts that stamp, so verify it first.
_doc_stamp=$(cat "$_DOC_STATE/.version" 2>/dev/null || echo "")
_doc_code=$(grep -m1 '^VERSION=' "$_DOC_STATE/lib/utils.sh" 2>/dev/null | tr -d '"' | cut -d= -f2 || echo "")
if [ -z "$_doc_stamp" ] || [ -z "$_doc_code" ]; then
  echo -e "  ${YELLOW}○${NC} Install integrity — cannot read version stamp or lib/utils.sh"
  _DOC_INTEGRITY="unknown"
elif [ "$_doc_stamp" = "$_doc_code" ]; then
  echo -e "  ${GREEN}✓${NC} Install integrity — stamp and deployed code agree (v${_doc_stamp})"
else
  echo -e "  ${RED}✗${NC} Install integrity — stamp says v${_doc_stamp}, deployed code is v${_doc_code}"
  echo -e "      ${CYAN}A partial update. Re-run: /sc-update${NC}"
  ERRORS=$((ERRORS + 1)); _DOC_INTEGRITY="MISMATCH"
fi

# 2. Do the user-facing SessionStart hooks use a channel that RENDERS?
#    Raw stdout from a SessionStart hook is never shown in the terminal; the
#    channel that produces "SessionStart:startup says: ..." is systemMessage.
#    The update notice sat on the wrong one for its entire life while twelve
#    tests asserted it "printed".
_doc_mute=""
for _doc_h in config-scan project-config version-floor-check update-check guard-registration-check; do
  _doc_f="$_DOC_STATE/hooks/$_doc_h.sh"
  [ -f "$_doc_f" ] || continue
  grep -q 'systemMessage' "$_doc_f" || _doc_mute="$_doc_mute $_doc_h"
done
if [ -z "$_doc_mute" ]; then
  echo -e "  ${GREEN}✓${NC} Session notices use a channel that renders (systemMessage)"
else
  echo -e "  ${RED}✗${NC} Session notices that can never be seen:${_doc_mute}"
  ERRORS=$((ERRORS + 1)); _DOC_INTEGRITY="mute-hooks"
fi

# 3. At-rest permissions on the state tree.
#    It inherited the umask until v4.0.35 — 0755 under the common default.
#    Never chmod through a symlink; report and leave it to the target's owner.
_doc_bad_mode=""
for _doc_d in "$_DOC_STATE" "$_DOC_STATE/scope"; do
  [ -d "$_doc_d" ] || continue
  if [ -L "$_doc_d" ]; then continue; fi
  case "$(ls -ld "$_doc_d" 2>/dev/null)" in
    drwx------*) ;;
    *) _doc_bad_mode="$_doc_bad_mode $(basename "$_doc_d")" ;;
  esac
done
_DOC_STATE_MODE=$(ls -ld "$_DOC_STATE" 2>/dev/null | awk '{print substr($1,2,9)}')
if [ -z "$_doc_bad_mode" ]; then
  echo -e "  ${GREEN}✓${NC} State directory is private (0700)"
else
  echo -e "  ${YELLOW}!${NC} State directory is readable by other local users:${_doc_bad_mode}"
  echo -e "      ${CYAN}Harmless alone on a single-user machine; not on a shared host or CI runner. Fix: /sc-update${NC}"
fi

# 4. Version drift. Read the cache rather than the network: a doctor that hangs
#    on a slow connection is a doctor nobody runs twice.
_doc_remote=$(cat "$_DOC_STATE/.update-cache" 2>/dev/null || echo "")

# v4.0.41: two of the same day's fixes collided here. v4.0.40 made install.sh
# CLEAR .update-cache (it is fetched before an install and answers for the old
# version afterwards), which is right — but this block reads only that cache, so
# straight after an update the doctor reported "update unknown" while /sc-update
# said "up to date" ninety seconds earlier. Cosmetic, and exactly the kind of
# small wrongness that teaches people to skim past the verdict line.
#
# No network call here on purpose: a doctor that hangs on a slow connection is
# one nobody runs twice. So say what is actually known instead of "unknown" —
# a fresh install IS the version it just installed, and that is worth stating.
_doc_fresh=""
if [ -z "$_doc_remote" ] && [ -n "$_doc_stamp" ]; then
  # Was the install written more recently than the cache would have been? If the
  # version stamp is newer than the (absent) cache, the cache was cleared BY an
  # install rather than never written.
  if [ -f "$_DOC_STATE/.version" ] && [ ! -f "$_DOC_STATE/.update-cache" ]; then
    _doc_fresh=1
  fi
fi

if [ -n "$_doc_remote" ] && [ -n "$_doc_stamp" ] && [ "$_doc_remote" != "$_doc_stamp" ]; then
  echo -e "  ${YELLOW}!${NC} Update available: v${_doc_stamp} → v${_doc_remote} — run /sc-update"
  _DOC_UPDATE="v${_doc_remote}"
elif [ -n "$_doc_remote" ]; then
  echo -e "  ${GREEN}✓${NC} Up to date (v${_doc_stamp})"
elif [ -n "$_doc_fresh" ]; then
  echo -e "  ${GREEN}✓${NC} Freshly installed (v${_doc_stamp}) — next session re-checks the remote"
  _DOC_UPDATE="fresh"
else
  echo -e "  ${YELLOW}○${NC} Not checked yet today — the next session start will check"
  _DOC_UPDATE="not-checked"
fi

# ── One-line verdict ──────────────────────────────────────────────────────────
# The point of this line: a colleague can paste it back. They cannot read the
# report above, and a report nobody can act on is a report nobody runs.
echo ""
echo -e "${BOLD}Paste this if you are asking for help:${NC}"
# HOOK_COUNT is what is actually registered; HOOK_STAMP is what the install
# recorded that it wrote. A shortfall between them is the partial-registration
# case the Hooks section above already detects — surfaced here so the pasted
# line carries it too.
echo "  Supercharger ${_doc_stamp:-?} · hooks ${HOOK_COUNT:-?}/${HOOK_STAMP:-${HOOK_COUNT:-?}} · state ${_DOC_STATE_MODE:-?} · update ${_DOC_UPDATE} · integrity ${_DOC_INTEGRITY} · score ${TOTAL_SCORE:-?}/100 · errors ${ERRORS}"

echo -e "For full capability overview: ${BOLD}bash tools/supercharger.sh${NC}"
