#!/usr/bin/env bash
# Claude Supercharger — Skill/Tool Poisoning Scanner
# Event: PreToolUse | Matcher: Skill
# Scans skill content for hidden shell commands, encoded payloads,
# and prompt injection patterns before the skill is loaded.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# Extract skill name from input
SKILL_NAME=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('skill',''))" 2>/dev/null)
[ -z "$SKILL_NAME" ] && exit 0

# Find skill file paths — check common locations
FINDINGS=""
SCAN_PATHS=""

# Build list of skill file paths to scan
for base in \
  "$HOME/.claude/commands" \
  "$HOME/.claude/plugins" \
  ".claude/commands" \
  ".claude/plugins"; do
  if [ -d "$base" ]; then
    # Find .md files matching the skill name
    while IFS= read -r f; do
      [ -f "$f" ] && SCAN_PATHS="$SCAN_PATHS $f"
    done < <(find "$base" -maxdepth 5 -name "*.md" -path "*${SKILL_NAME}*" 2>/dev/null || true)
  fi
done

[ -z "$SCAN_PATHS" ] && exit 0

# Scan patterns — ordered by severity
check_pattern() {
  local label="$1" pattern="$2" severity="$3"
  for f in $SCAN_PATHS; do
    local matches
    matches=$(grep -cE "$pattern" "$f" 2>/dev/null || echo "0")
    if [ "$matches" -gt 0 ]; then
      FINDINGS="${FINDINGS}${severity}: ${label} (${matches}x in $(basename "$f"))\n"
    fi
  done
}

# Critical — likely malicious
check_pattern "base64 decode execution" 'base64\s+(-d|--decode)|atob\(|b64decode' "CRITICAL"
check_pattern "hidden eval/exec" '\beval\b.*\$|exec\s*\(' "CRITICAL"
check_pattern "curl pipe to shell" 'curl.*\|\s*(ba)?sh|wget.*\|\s*(ba)?sh' "CRITICAL"
check_pattern "environment exfiltration" 'env\b.*curl|printenv.*\||(API_KEY|SECRET|TOKEN|PASSWORD).*curl' "CRITICAL"
check_pattern "reverse shell pattern" 'mkfifo|/dev/tcp/|nc\s+-[el]' "CRITICAL"

# High — suspicious
check_pattern "hidden instruction override" 'ignore\s+(previous|above|all)\s+(instructions|rules)|disregard.*instructions|you\s+are\s+now' "HIGH"
check_pattern "steganographic whitespace" '[\x{200B}\x{200C}\x{200D}\x{FEFF}]' "HIGH"
check_pattern "obfuscated variable expansion" '\$\{[A-Z_]*:.*:.*\}.*\$\{' "HIGH"
check_pattern "credential file access" '/etc/shadow|\.ssh/id_|\.aws/credentials|\.netrc|keychain' "HIGH"

# Medium — worth noting
check_pattern "subprocess spawn" 'os\.system\(|subprocess\.(run|call|Popen)|child_process' "MEDIUM"
check_pattern "file write outside project" "open\(.*'/tmp\|open\(.*'/var\|>/etc/" "MEDIUM"

if [ -n "$FINDINGS" ]; then
  CRITICAL_COUNT=$(printf '%b' "$FINDINGS" | grep -c "^CRITICAL" || echo "0")

  if [ "$CRITICAL_COUNT" -gt 0 ]; then
    # Block critical findings
    REASON="Skill '$SKILL_NAME' contains suspicious patterns:\n$(printf '%b' "$FINDINGS")\nReview the skill source before allowing execution."
    REASON_JSON=$(printf '%b' "$REASON" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
    printf '{"decision":"block","reason":%s}\n' "$REASON_JSON"
    echo "[Supercharger] skill-poisoning-scanner: BLOCKED skill '$SKILL_NAME' — ${CRITICAL_COUNT} critical finding(s)" >&2
    exit 2
  else
    # Warn on non-critical findings
    MSG="[SUPERCHARGER] Skill '$SKILL_NAME' has suspicious patterns (non-blocking):\n$(printf '%b' "$FINDINGS")"
    MSG_JSON=$(printf '%b' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
    printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"
    echo "[Supercharger] skill-poisoning-scanner: warned on skill '$SKILL_NAME'" >&2
  fi
fi

exit 0
