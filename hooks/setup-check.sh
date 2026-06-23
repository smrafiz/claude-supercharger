#!/usr/bin/env bash
# Claude Supercharger — Setup Health Check
# Event: Setup | Matcher: (none)
#
# Fires when Claude Code runs `--init`, `--init-only`, or `--maintenance`.
# Validates the Supercharger install: settings.json registered, hooks dir
# present, hook count sane, version readable. Surfaces a one-shot status
# line so the user can spot drift at init time without manually running
# `tools/config-health.sh`.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-timing.sh"

# Drain stdin (Setup payload is empty in current CC but always drain to
# prevent SIGPIPE on the parent if the payload field grows later).
cat >/dev/null 2>&1 || true

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
HOOKS_DIR="$SUPERCHARGER_DIR/hooks"
SETTINGS="$HOME/.claude/settings.json"
UTILS="$SUPERCHARGER_DIR/lib/utils.sh"

issues=()
status_bits=()

ver="unknown"
if [ -f "$UTILS" ]; then
  ver=$(grep -E '^VERSION=' "$UTILS" 2>/dev/null | head -1 | cut -d'"' -f2)
  [ -n "$ver" ] || ver="unknown"
fi

if [ -f "$SETTINGS" ]; then
  # v2.6.77: pass path via env var — prevents shell-interpolating $SETTINGS into
  # python3 -c string (same injection class as the v2.6.72 osascript RCE fix)
  if SC_SETTINGS_PATH="$SETTINGS" python3 -c "import json,sys,os; d=json.load(open(os.environ['SC_SETTINGS_PATH'])); sys.exit(0 if 'hooks' in d and d['hooks'] else 1)" 2>/dev/null; then
    status_bits+=("settings ok")
  else
    issues+=("settings.json missing hooks key — run install.sh")
  fi
else
  issues+=("$HOME/.claude/settings.json absent — run install.sh")
fi

if [ -d "$HOOKS_DIR" ]; then
  count=$(find "$HOOKS_DIR" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt 0 ]; then
    status_bits+=("$count hooks")
  else
    issues+=("$HOOKS_DIR has zero .sh files — install is corrupt")
  fi
else
  issues+=("$HOOKS_DIR missing — run install.sh")
fi

_join() { local sep="$1"; shift; local out="" i; for i in "$@"; do out+="${out:+$sep}$i"; done; printf '%s' "$out"; }

if [ "${#issues[@]}" -eq 0 ]; then
  msg="[Supercharger] Setup check (v$ver): $(_join ', ' "${status_bits[@]}") — healthy"
else
  msg="[Supercharger] Setup check (v$ver) FAILED: $(_join '; ' "${issues[@]}")"
fi

printf '%s\n' "$msg" >&2

MSG="$msg" python3 <<'PYEOF' 2>/dev/null || true
import json, os
print(json.dumps({"systemMessage": os.environ.get("MSG", ""), "suppressOutput": False}))
PYEOF

exit 0
