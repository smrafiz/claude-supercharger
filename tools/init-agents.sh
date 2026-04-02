#!/usr/bin/env bash
# Claude Supercharger — Project Agent Scaffolder
# Usage: bash tools/init-agents.sh [--force] [--stack STACK] [--dir DIR]
# Run from inside a project directory to scaffold .claude/agents/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$REPO_DIR/configs/project-agent-templates"
DETECT_STACK="$REPO_DIR/hooks/detect-stack.sh"

# Colors
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()    { echo -e "  ${CYAN}→${NC} $1"; }
success() { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}!${NC} $1"; }
error()   { echo -e "  ${RED}✗${NC} $1"; }

# --- Argument parsing ---
ARG_FORCE="false"
ARG_STACK=""
ARG_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)  ARG_FORCE="true"; shift ;;
    --stack)  ARG_STACK="$2"; shift 2 ;;
    --dir)    ARG_DIR="$2"; shift 2 ;;
    --help)
      echo "Usage: bash tools/init-agents.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --force       Overwrite existing agents without prompting"
      echo "  --stack STACK Override stack detection (e.g. 'react', 'python', 'rust', 'wordpress', 'go', 'shopify')"
      echo "  --dir DIR     Target project directory (default: current directory)"
      echo "  --help        Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

PROJECT_DIR="${ARG_DIR:-$(pwd)}"
PROJECT_NAME=$(basename "$PROJECT_DIR")
AGENTS_DIR="$PROJECT_DIR/.claude/agents"

echo ""
echo -e "${BOLD}Claude Supercharger — Project Agent Scaffolder${NC}"
echo -e "${DIM}Project: $PROJECT_DIR${NC}"
echo ""

# --- Detect stack ---
if [ -n "$ARG_STACK" ]; then
  DETECTED_STACK="$ARG_STACK"
  info "Stack override: $DETECTED_STACK"
else
  info "Detecting stack..."
  STACK_OUTPUT=$(bash "$DETECT_STACK" "$PROJECT_DIR" 2>/dev/null || echo "detected=false")

  DETECTED_STACK=$(echo "$STACK_OUTPUT" | grep "^language=" | cut -d= -f2 | tr '[:upper:]' '[:lower:]' | tr ',' ' ' | awk '{print $1}' || true)
  DETECTED_FRAMEWORK=$(echo "$STACK_OUTPUT" | grep "^framework=" | cut -d= -f2 | tr '[:upper:]' '[:lower:]' | awk '{print $1}' || true)
  DETECTED_PKG=$(echo "$STACK_OUTPUT" | grep "^package_manager=" | cut -d= -f2 || true)

  if [ -z "$DETECTED_STACK" ]; then
    DETECTED_STACK="unknown"
  fi
fi

# Normalize stack to agent set key
STACK_KEY="$DETECTED_STACK"
if echo "$DETECTED_STACK" | grep -qi "javascript\|typescript"; then
  STACK_KEY="node"
  # Check for Shopify
  if [ -f "$PROJECT_DIR/shopify.app.toml" ] || [ -f "$PROJECT_DIR/shopify.config.js" ]; then
    STACK_KEY="shopify"
  fi
fi
if echo "$DETECTED_STACK" | grep -qi "php"; then
  STACK_KEY="php"
  if [ -f "$PROJECT_DIR/wp-config.php" ] || [ -f "$PROJECT_DIR/functions.php" ]; then
    STACK_KEY="wordpress"
  fi
fi

echo -e "  ${CYAN}Stack detected:${NC} ${BOLD}$DETECTED_STACK${NC}${DETECTED_FRAMEWORK:+ + $DETECTED_FRAMEWORK}${DETECTED_PKG:+ ($DETECTED_PKG)}"

# --- Define agent sets per stack ---
case "$STACK_KEY" in
  node|typescript|javascript)
    AGENT_SET=("orchestrator" "architect" "frontend-engineer" "backend-engineer" "debugger" "code-reviewer" "qa-engineer")
    FRONTEND_DIR="src/components"
    BACKEND_DIR="src/lib"
    # Try to detect actual dirs
    for d in "src" "app" "components" "lib"; do
      [ -d "$PROJECT_DIR/$d" ] && FRONTEND_DIR="$d" && break
    done
    ;;
  shopify)
    AGENT_SET=("orchestrator" "architect" "frontend-engineer" "backend-engineer" "debugger" "code-reviewer" "qa-engineer")
    FRONTEND_DIR="web/features"
    BACKEND_DIR="web/lib"
    ;;
  python)
    AGENT_SET=("orchestrator" "architect" "backend-engineer" "debugger" "code-reviewer" "qa-engineer")
    FRONTEND_DIR=""
    BACKEND_DIR="app"
    for d in "app" "src" "api" "backend"; do
      [ -d "$PROJECT_DIR/$d" ] && BACKEND_DIR="$d" && break
    done
    ;;
  wordpress|php)
    AGENT_SET=("orchestrator" "architect" "frontend-engineer" "backend-engineer" "debugger" "code-reviewer")
    FRONTEND_DIR="."
    BACKEND_DIR="."
    [ -f "$PROJECT_DIR/wp-config.php" ] && BACKEND_DIR="wp-content"
    ;;
  rust)
    AGENT_SET=("orchestrator" "architect" "systems-engineer" "debugger" "code-reviewer" "qa-engineer")
    FRONTEND_DIR=""
    BACKEND_DIR="src"
    ;;
  go)
    AGENT_SET=("orchestrator" "architect" "systems-engineer" "debugger" "code-reviewer" "qa-engineer")
    FRONTEND_DIR=""
    BACKEND_DIR="."
    for d in "cmd" "pkg" "internal" "src"; do
      [ -d "$PROJECT_DIR/$d" ] && BACKEND_DIR="$d" && break
    done
    ;;
  *)
    AGENT_SET=("orchestrator" "architect" "debugger" "code-reviewer" "qa-engineer")
    FRONTEND_DIR="src"
    BACKEND_DIR="src"
    ;;
esac

# --- Show plan ---
echo ""
echo -e "  ${BOLD}Agents to scaffold:${NC}"
for agent in "${AGENT_SET[@]}"; do
  echo -e "    ${DIM}•${NC} $agent"
done
echo ""

# --- Check existing ---
if [ -d "$AGENTS_DIR" ] && [ "$(ls -A "$AGENTS_DIR" 2>/dev/null)" ] && [ "$ARG_FORCE" != "true" ]; then
  warn "Existing agents found in $AGENTS_DIR"
  echo ""
  echo -e "  ${BOLD}1)${NC} Merge   — add new agents, skip existing"
  echo -e "  ${BOLD}2)${NC} Replace — overwrite all"
  echo -e "  ${BOLD}3)${NC} Cancel"
  echo ""
  read -rp "> " choice
  case "$choice" in
    2) ARG_FORCE="true" ;;
    3) echo "Cancelled."; exit 0 ;;
    *) : ;; # merge = default, skip existing
  esac
  echo ""
fi

mkdir -p "$AGENTS_DIR"

# --- Build template variables ---
FULL_STACK="$DETECTED_STACK"
[ -n "${DETECTED_FRAMEWORK:-}" ] && FULL_STACK="$DETECTED_STACK, $DETECTED_FRAMEWORK"

FRAMEWORK_LINE=""
[ -n "${DETECTED_FRAMEWORK:-}" ] && FRAMEWORK_LINE="\nFramework: $DETECTED_FRAMEWORK"

PKG_MANAGER_LINE=""
[ -n "${DETECTED_PKG:-}" ] && PKG_MANAGER_LINE="\nPackage manager: $DETECTED_PKG"

# Build agents list for orchestrator
AGENTS_LIST_STR=""
for agent in "${AGENT_SET[@]}"; do
  [ "$agent" != "orchestrator" ] && AGENTS_LIST_STR="$AGENTS_LIST_STR\n- **$agent**"
done

# --- Scaffold each agent ---
GENERATED=0
SKIPPED=0

for agent in "${AGENT_SET[@]}"; do
  TEMPLATE="$TEMPLATES_DIR/$agent.md"
  TARGET="$AGENTS_DIR/$agent.md"

  if [ ! -f "$TEMPLATE" ]; then
    warn "No template for '$agent' — skipping"
    continue
  fi

  if [ -f "$TARGET" ] && [ "$ARG_FORCE" != "true" ]; then
    info "Skipping $agent.md (already exists)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Substitute variables
  export SC_PROJECT_NAME="$PROJECT_NAME"
  export SC_FULL_STACK="$FULL_STACK"
  export SC_FRAMEWORK_LINE="$FRAMEWORK_LINE"
  export SC_PKG_MANAGER_LINE="$PKG_MANAGER_LINE"
  export SC_FRONTEND_DIR="${FRONTEND_DIR:-src}"
  export SC_BACKEND_DIR="${BACKEND_DIR:-src}"
  export SC_AGENTS_LIST="$AGENTS_LIST_STR"

  PYTHONUTF8=1 python3 -c "
import sys, os

with open(sys.argv[1]) as f:
    content = f.read()

replacements = {
    '{{PROJECT_NAME}}':     os.environ['SC_PROJECT_NAME'],
    '{{STACK}}':            os.environ['SC_FULL_STACK'],
    '{{FRAMEWORK_LINE}}':   os.environ['SC_FRAMEWORK_LINE'].replace('\\\\n', '\n'),
    '{{PKG_MANAGER_LINE}}': os.environ['SC_PKG_MANAGER_LINE'].replace('\\\\n', '\n'),
    '{{FRONTEND_DIR}}':     os.environ['SC_FRONTEND_DIR'],
    '{{BACKEND_DIR}}':      os.environ['SC_BACKEND_DIR'],
    '{{AGENTS_LIST}}':      os.environ['SC_AGENTS_LIST'].replace('\\\\n', '\n'),
}

for key, val in replacements.items():
    content = content.replace(key, val)

print(content, end='')
" "$TEMPLATE" > "$TARGET"

  success "Created $agent.md"
  GENERATED=$((GENERATED + 1))
done

# --- Summary ---
echo ""
echo -e "${CYAN}────────────────────────────────────────${NC}"
echo -e "${GREEN}  Done!${NC} $GENERATED agent(s) created in .claude/agents/"
[ "$SKIPPED" -gt 0 ] && echo -e "  $SKIPPED skipped (already existed)"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "  1. Open ${DIM}.claude/agents/orchestrator.md${NC} — review agent list and scope"
echo -e "  2. Update file paths in each agent to match your actual project structure"
echo -e "  3. Add project-specific rules to each specialist agent"
echo ""
echo -e "  ${DIM}Tip: Drop .claude/agents/ in your repo to share with your team${NC}"
echo ""
