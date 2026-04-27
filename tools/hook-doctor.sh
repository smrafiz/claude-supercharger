#!/usr/bin/env bash
# Claude Supercharger — Hook Doctor
# Diagnoses broken hook installations by inspecting settings.json
# and validating each registered hook script.
#
# Usage: bash tools/hook-doctor.sh [--quiet]
#   --quiet   Exit 1 if any issues found, no output (for CI)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

QUIET=false
[ "${1:-}" = "--quiet" ] && QUIET=true

SETTINGS="$HOME/.claude/settings.json"
ISSUES=0
CHECKED=0

print_header() {
  $QUIET && return
  echo -e "${CYAN}${BOLD}"
  echo "╔═══════════════════════════════════╗"
  echo "║   Claude Supercharger Hook Doctor  ║"
  echo "╚═══════════════════════════════════╝"
  echo -e "${NC}"
}

ok()   { $QUIET || echo -e "  ${GREEN}✓${NC}  $1"; }
warn() { $QUIET || echo -e "  ${YELLOW}⚠${NC}  $1"; ISSUES=$((ISSUES + 1)); }
fail() { $QUIET || echo -e "  ${RED}✗${NC}  $1"; ISSUES=$((ISSUES + 1)); }
info() { $QUIET || echo -e "  ${DIM}→${NC}  $1"; }

# ── Pre-flight ────────────────────────────────────────────────────────────────
print_header

if [ ! -f "$SETTINGS" ]; then
  fail "settings.json not found at $SETTINGS — Supercharger may not be installed"
  exit 1
fi

HOOK_COUNT=$(python3 -c "
import json
with open('$SETTINGS') as f:
    s = json.load(f)
hooks = s.get('hooks', {})
count = sum(1 for event in hooks.values() for entry in event
            for h in entry.get('hooks', [])
            if '#supercharger' in h.get('command', '') or '#supercharger' in h.get('prompt', ''))
print(count)
" 2>/dev/null || echo "0")

$QUIET || echo -e "${BOLD}Checking $HOOK_COUNT registered supercharger hooks...${NC}"
$QUIET || echo ""

if [ "$HOOK_COUNT" -eq 0 ]; then
  fail "No supercharger hooks found in settings.json — run install.sh"
  exit 1
fi

# ── Extract and check each hook command ──────────────────────────────────────
python3 -c "
import json, sys

with open('$SETTINGS') as f:
    s = json.load(f)

hooks = s.get('hooks', {})
for event, entries in hooks.items():
    for entry in entries:
        for h in entry.get('hooks', []):
            cmd = h.get('command', '')
            if '#supercharger' not in cmd:
                continue
            # Strip the tag suffix
            script_and_args = cmd.replace(' #supercharger', '').strip()
            # First token is the script path
            script = script_and_args.split()[0]
            print(f'{event}|{script}')
" 2>/dev/null | sort -u | while IFS='|' read -r event script; do
  CHECKED=$((CHECKED + 1))
  NAME=$(basename "$script")

  if [ ! -e "$script" ]; then
    fail "MISSING: $NAME ($event) — expected at $script"
    continue
  fi

  if [ ! -f "$script" ]; then
    fail "NOT A FILE: $NAME ($event) — $script"
    continue
  fi

  if [ ! -x "$script" ]; then
    warn "NOT EXECUTABLE: $NAME ($event) — run: chmod +x $script"
    continue
  fi

  SHEBANG=$(head -1 "$script" 2>/dev/null || echo "")
  if ! printf '%s\n' "$SHEBANG" | grep -qE '^#!.*(bash|sh|python|python3)'; then
    warn "BAD SHEBANG: $NAME — got: $SHEBANG"
    continue
  fi

  ok "$NAME ($event)"
done

CHECKED=$?  # exit code from while loop

# ── Supercharger directory check ──────────────────────────────────────────────
$QUIET || echo ""
$QUIET || echo -e "${BOLD}Checking installation directories...${NC}"
$QUIET || echo ""

SC_DIR="$HOME/.claude/supercharger"
HOOKS_DIR="$SC_DIR/hooks"
TOOLS_DIR="$SC_DIR/tools"
LIB_DIR="$SC_DIR/lib"

for dir in "$SC_DIR" "$HOOKS_DIR" "$TOOLS_DIR" "$LIB_DIR"; do
  if [ -d "$dir" ]; then
    COUNT=$(ls "$dir"/*.sh 2>/dev/null | wc -l | tr -d ' ')
    ok "$(basename "$dir")/ ($COUNT scripts)"
  else
    fail "MISSING directory: $dir"
  fi
done

# ── Stale pending gate files ──────────────────────────────────────────────────
SCOPE_DIR="$SC_DIR/scope"
if [ -d "$SCOPE_DIR" ]; then
  STALE_COUNT=0
  NOW=$(date -u +%s 2>/dev/null || echo "0")
  for pf in "$SCOPE_DIR"/.gate-pending-*; do
    [ -f "$pf" ] || continue
    FILE_TS=$(tail -1 "$pf" 2>/dev/null || echo "0")
    AGE=$(( NOW - FILE_TS ))
    if [ "$AGE" -gt 3600 ]; then
      STALE_COUNT=$((STALE_COUNT + 1))
    fi
  done
  if [ "$STALE_COUNT" -gt 0 ]; then
    warn "$STALE_COUNT stale approval-gate pending file(s) — will auto-clear on next hook run"
  else
    ok "No stale approval-gate pending files"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
$QUIET || echo ""
if [ "$ISSUES" -eq 0 ]; then
  $QUIET || echo -e "${GREEN}${BOLD}All hooks look healthy.${NC}"
else
  $QUIET || echo -e "${RED}${BOLD}$ISSUES issue(s) found.${NC} Run install.sh to repair."
  exit 1
fi
