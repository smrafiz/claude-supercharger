#!/usr/bin/env bash
# Claude Supercharger — Tool Preferences (per-project rejection chains with suggestions)
# Event: PreToolUse | Matcher: Bash
# Reads .supercharger.json `toolPreferences` map. When Claude tries to run a
# disallowed tool, denies with a suggested replacement instead of a blanket block.
#
# Example .supercharger.json:
#   {"toolPreferences": {"npm": "pnpm", "jest": "vitest", "pip": "uv pip"}}
#
# Disable: SUPERCHARGER_TOOL_PREFS=0

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"

[ "${SUPERCHARGER_TOOL_PREFS:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "tool-preferences" && exit 0
hook_profile_skip "tool-preferences" && exit 0

# v2.6.36: read .supercharger.json from main worktree root if in a linked worktree
CONFIG="$(_resolve_project_root "$PROJECT_DIR")/.supercharger.json"
[ ! -f "$CONFIG" ] && exit 0

TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
[ "$TOOL_NAME" != "Bash" ] && exit 0

CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$CMD" ] && exit 0

REASON=$(CMD="$CMD" CONFIG="$CONFIG" python3 <<'PYEOF'
import os, json, shlex, sys

cmd = os.environ.get('CMD', '')
config_path = os.environ.get('CONFIG', '')

try:
    with open(config_path) as f:
        d = json.load(f)
    prefs = d.get('toolPreferences') or {}
except Exception:
    sys.exit(0)

if not isinstance(prefs, dict) or not prefs:
    sys.exit(0)

# Tokenize command — first token is the binary
try:
    tokens = shlex.split(cmd)
except Exception:
    tokens = cmd.split()

if not tokens:
    sys.exit(0)

bin_name = os.path.basename(tokens[0])

# Skip env var assignments and prefixes (FOO=bar cmd ...)
i = 0
while i < len(tokens) and '=' in tokens[i] and not tokens[i].startswith('-'):
    i += 1
if i >= len(tokens):
    sys.exit(0)
bin_name = os.path.basename(tokens[i])

# Allow inline alternative (npx, pnpx, etc. wrap calls)
if bin_name in ('npx', 'bunx', 'pnpx') and i + 1 < len(tokens):
    bin_name = tokens[i + 1]

if bin_name in prefs:
    suggested = prefs[bin_name]
    print(f"This project prefers `{suggested}` over `{bin_name}` (per .supercharger.json toolPreferences). Use `{suggested}` with the same arguments.")
PYEOF
)

if [ -n "$REASON" ]; then
  RSN=$(printf '%s' "$REASON" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$REASON")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  echo "[Supercharger] tool-preferences: SUGGESTED $REASON" >&2
  exit 2
fi

exit 0
