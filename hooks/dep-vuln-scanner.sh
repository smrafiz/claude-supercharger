#!/usr/bin/env bash
# Claude Supercharger — Dependency Vulnerability Scanner
# Event: PostToolUse | Matcher: Bash
# Runs audit after package installs and reports critical/high vulnerabilities.

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# v2.7.42 perf: only acts after package installs. Cheap raw-string gate before
# the jq+python parse — skips ~65ms on the vast majority of Bash calls (ls, git,
# echo, ...) that contain no install verb. The precise install-command grep below
# still runs for anything mentioning install/add.
# v4.1.9: the short verb forms are admitted here too. This gate required the
# literal substring "install" or "add", while the install regexes below (and
# package-credibility.py:29) both list `npm i` as supported — so that
# alternative was unreachable code, and `npm i <pkg>` reached no scanner at
# all. The two-gate trap: an inner rule is dead unless the outer gate admits it.
case "$_INPUT" in *install*|*add*|*"npm i "*|*"pnpm i "*|*"yarn i "*) ;; *) exit 0 ;; esac
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$COMMAND" ] && exit 0
[ "${SUPERCHARGER_PROFILE:-standard}" = "minimal" ] && exit 0

# Only fire after install commands.
# v4.1.9: matched at a SEGMENT start, not the command start. Every agent install
# is a compound -- `cd app && npm install x` -- so the `^` anchor meant the
# scanner skipped the normal case and ran only on the rare bare command.
# Measured with a stub npm: bare SCANNED, `cd app && npm install x` SKIPPED.
_INSTALL_RE='(^|[;&|]|&&)[[:space:]]*(npm install|npm i |yarn add|yarn i |pnpm add|pnpm i |pip install|pip3 install|poetry add|uv add)'
if ! printf '%s\n' "$COMMAND" | grep -qE "$_INSTALL_RE"; then
  exit 0
fi

FINDINGS=""

if printf '%s\n' "$COMMAND" | grep -qE '(^|[;&|]|&&)[[:space:]]*(npm install|npm i |yarn add|yarn i |pnpm add|pnpm i )'; then
  # npm/yarn/pnpm audit
  if command -v npm >/dev/null 2>&1; then
    AUDIT=$(cd "$PROJECT_DIR" && npm audit --json 2>/dev/null || echo "{}")
    # 2.21.8: feed the audit JSON via STDIN, not argv. A large project's audit
    # output easily exceeds ARG_MAX → "Argument list too long" → python never
    # runs → 2>/dev/null||echo"" → findings silently empty exactly where vulns
    # are most likely. stdin has no such limit.
    FINDINGS=$(printf '%s' "$AUDIT" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    vulns = d.get('vulnerabilities', {})
    critical = sum(1 for v in vulns.values() if v.get('severity') == 'critical')
    high = sum(1 for v in vulns.values() if v.get('severity') == 'high')
    if critical > 0 or high > 0:
        names = [n for n, v in vulns.items() if v.get('severity') in ('critical', 'high')][:5]
        print(f'{critical} critical, {high} high vulnerabilities found in: {chr(44).join(names)}')
except Exception:
    pass
" 2>/dev/null || echo "")
  fi
elif printf '%s\n' "$COMMAND" | grep -qE '^\s*(pip install|pip3 install|poetry add|uv add)'; then
  # pip audit (requires pip-audit)
  if command -v pip-audit >/dev/null 2>&1; then
    AUDIT=$(cd "$PROJECT_DIR" && pip-audit --format json 2>/dev/null || echo "[]")
    # 2.21.8: STDIN, not argv (see npm branch — ARG_MAX overflow on large output).
    FINDINGS=$(printf '%s' "$AUDIT" | python3 -c "
import json, sys
try:
    vulns = json.loads(sys.stdin.read())
    if isinstance(vulns, list) and len(vulns) > 0:
        names = [v.get('name','?') for v in vulns[:5]]
        print(f'{len(vulns)} vulnerable package(s): {chr(44).join(names)}')
except Exception:
    pass
" 2>/dev/null || echo "")
  fi
fi

if [ -n "$FINDINGS" ]; then
  echo "[Supercharger] dep-vuln-scanner: $FINDINGS" >&2
  MSG="[SECURITY] Dependency audit after install: ${FINDINGS}. Run the appropriate audit command for full details and consider upgrading or replacing affected packages."
  MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"
fi

exit 0
