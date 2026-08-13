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
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"
# shellcheck source=hooks/lib-json-fast.sh
. "$HOOKS_DIR/lib-json-fast.sh" 2>/dev/null || true

[ "${SUPERCHARGER_TOOL_PREFS:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# v2.24.0: fork-free `cwd` first — this jq ran on every Bash call, before the
# "is there even a config?" exit below. jq stays as the fallback.
if command -v _json_fast_str >/dev/null 2>&1 && _json_fast_str cwd "$_INPUT"; then
  PROJECT_DIR="$_JSON_FAST_VAL"
else
  PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
fi
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "tool-preferences" && exit 0
hook_profile_skip "tool-preferences" && exit 0

# v2.6.36: read .supercharger.json from main worktree root if in a linked worktree
CONFIG="$(_resolve_project_root "$PROJECT_DIR")/.supercharger.json"
[ ! -f "$CONFIG" ] && exit 0

# v2.24.0: a config exists, but most don't define toolPreferences — and finding that
# out used to cost two more jq forks plus a ~30ms python3. Reading the file is a
# builtin redirect and the test is fork-free; same terminal state (no prefs -> exit 0).
_TP_CFG_BODY=$(<"$CONFIG")
case "$_TP_CFG_BODY" in
  *toolPreferences*) ;;
  *) exit 0 ;;
esac

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
