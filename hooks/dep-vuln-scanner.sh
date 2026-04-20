#!/usr/bin/env bash
# Claude Supercharger — Dependency Vulnerability Scanner
# Event: PostToolUse | Matcher: Bash
# Runs audit after package installs and reports critical/high vulnerabilities.

set -euo pipefail

INPUT=$(cat)

COMMAND=$(printf '%s\n' "$INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$COMMAND" ] && exit 0

# Only fire after install commands
if ! printf '%s\n' "$COMMAND" | grep -qE '^\s*(npm install|npm i |yarn add|pnpm add|pip install|pip3 install|poetry add|uv add)'; then
  exit 0
fi

# Determine package manager and run audit
CWD=$(printf '%s\n' "$INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('cwd', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$CWD" ] && CWD="$(pwd)"

FINDINGS=""

if printf '%s\n' "$COMMAND" | grep -qE '^\s*(npm install|npm i |yarn add|pnpm add)'; then
  # npm/yarn/pnpm audit
  if command -v npm >/dev/null 2>&1; then
    AUDIT=$(cd "$CWD" && npm audit --json 2>/dev/null || echo "{}")
    FINDINGS=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    vulns = d.get('vulnerabilities', {})
    critical = sum(1 for v in vulns.values() if v.get('severity') == 'critical')
    high = sum(1 for v in vulns.values() if v.get('severity') == 'high')
    if critical > 0 or high > 0:
        names = [n for n, v in vulns.items() if v.get('severity') in ('critical', 'high')][:5]
        print(f'{critical} critical, {high} high vulnerabilities found in: {chr(44).join(names)}')
except Exception:
    pass
" "$AUDIT" 2>/dev/null || echo "")
  fi
elif printf '%s\n' "$COMMAND" | grep -qE '^\s*(pip install|pip3 install|poetry add|uv add)'; then
  # pip audit (requires pip-audit)
  if command -v pip-audit >/dev/null 2>&1; then
    AUDIT=$(cd "$CWD" && pip-audit --format json 2>/dev/null || echo "[]")
    FINDINGS=$(python3 -c "
import json, sys
try:
    vulns = json.loads(sys.argv[1])
    if isinstance(vulns, list) and len(vulns) > 0:
        names = [v.get('name','?') for v in vulns[:5]]
        print(f'{len(vulns)} vulnerable package(s): {chr(44).join(names)}')
except Exception:
    pass
" "$AUDIT" 2>/dev/null || echo "")
  fi
fi

if [ -n "$FINDINGS" ]; then
  echo "[Supercharger] dep-vuln-scanner: $FINDINGS" >&2
  python3 -c "
import json, sys
msg = '[SECURITY] Dependency audit after install: {}. Run the appropriate audit command for full details and consider upgrading or replacing affected packages.'.format(sys.argv[1])
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': msg}}))
" "$FINDINGS"
fi

exit 0
