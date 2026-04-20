#!/usr/bin/env bash
# Claude Supercharger — Code Security Scanner Hook
# Event: PreToolUse | Matcher: Write,Edit
# Scans content Claude is about to write for common security vulnerabilities.
# Warns Claude but does not block — Claude may intentionally write these patterns
# in test files, security tools, or documentation.

set -euo pipefail

INPUT=$(cat)

# Extract content (Write uses .content, Edit uses .new_string)
CONTENT=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null)
if [ -z "$CONTENT" ]; then
  CONTENT=$(printf '%s\n' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin).get('tool_input', {})
print(d.get('content') or d.get('new_string') or '')
" 2>/dev/null || echo "")
fi

[ -z "$CONTENT" ] && exit 0
[ "${#CONTENT}" -lt 20 ] && exit 0

# Skip tiny Edit patches (< 5 lines) — security patterns need context
TOOL_NAME=$(printf '%s
' "$INPUT" | python3 -c "
import sys, json
print(json.load(sys.stdin).get('tool_name', ''))
" 2>/dev/null || echo "")
if [ "$TOOL_NAME" = "Edit" ]; then
  LINE_COUNT=$(printf '%s
' "$CONTENT" | wc -l | tr -d ' ')
  [ "$LINE_COUNT" -lt 5 ] && exit 0
fi

# Extract file path for context
FILE_PATH=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
if [ -z "$FILE_PATH" ]; then
  FILE_PATH=$(printf '%s\n' "$INPUT" | python3 -c "
import sys, json
print(json.load(sys.stdin).get('tool_input', {}).get('file_path', ''))
" 2>/dev/null || echo "")
fi

# Collect all warnings
WARNINGS=()

# --- JavaScript / TypeScript patterns ---
if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE 'eval\('; then
  WARNINGS+=("eval() — arbitrary code execution risk")
fi

if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE '\.innerHTML[[:space:]]*='; then
  WARNINGS+=(".innerHTML = — XSS risk; use textContent or a sanitizer")
fi

if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE 'dangerouslySetInnerHTML'; then
  WARNINGS+=("dangerouslySetInnerHTML — React XSS risk; sanitize input before use")
fi

if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE 'document\.write\('; then
  WARNINGS+=("document.write() — XSS risk")
fi

if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE 'new Function\('; then
  WARNINGS+=("new Function() — code injection risk")
fi

# --- Python patterns ---
if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE 'pickle\.loads?\('; then
  WARNINGS+=("pickle.load(s)() — unsafe deserialization; never unpickle untrusted data")
fi

if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE '(^|[^a-zA-Z_])(exec|compile)\('; then
  WARNINGS+=("exec()/compile() — arbitrary code execution risk")
fi

if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE 'os\.system\('; then
  WARNINGS+=("os.system() — shell injection risk; prefer subprocess with a list of args")
fi

if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE 'subprocess\.(call|run|Popen).*shell[[:space:]]*=[[:space:]]*True'; then
  WARNINGS+=("subprocess with shell=True — shell injection risk; pass args as a list instead")
fi

if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE '__import__\('; then
  WARNINGS+=("__import__() — dynamic import injection risk")
fi

# --- SQL injection patterns ---
# Flag f-string / string-concat queries but not parameterised ones
if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE 'f"(SELECT|INSERT|UPDATE|DELETE)[^"]*\{'; then
  WARNINGS+=("f-string SQL query — SQL injection risk; use parameterised queries")
fi

if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE '"(SELECT|INSERT|UPDATE|DELETE)[^"]*"[[:space:]]*\+'; then
  WARNINGS+=("string-concatenated SQL query — SQL injection risk; use parameterised queries")
fi

# --- Hardcoded secrets ---
if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qiE 'password[[:space:]]*=[[:space:]]*"[^"]+"'; then
  WARNINGS+=("hardcoded password — use environment variables or a secrets manager")
fi

if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qiE 'secret[[:space:]]*=[[:space:]]*"[^"]+"'; then
  WARNINGS+=("hardcoded secret — use environment variables or a secrets manager")
fi

if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qiE 'api_key[[:space:]]*=[[:space:]]*"[^"]+"'; then
  WARNINGS+=("hardcoded api_key — use environment variables or a secrets manager")
fi

# --- Weak hashing ---
if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE "crypto\.createHash\(['\"]md5['\"]|hashlib\.md5\("; then
  WARNINGS+=("MD5 hashing — cryptographically broken; use SHA-256 or bcrypt for passwords")
fi

# --- GitHub Actions command injection ---
# Only warn for .yml / .yaml files
if [[ "$FILE_PATH" =~ \.(yml|yaml)$ ]]; then
  if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qF '${{ github.event.'; then
    WARNINGS+=("\${{ github.event.* }} in workflow — GitHub Actions command injection risk; sanitise before use")
  fi
fi

# --- File path shell metacharacters (CVE-2026-35021) ---
if [ -n "$FILE_PATH" ]; then
  if printf '%s\n' "$FILE_PATH" | LC_ALL=C grep -qE '(\$\(|`|;|\||&&|\{)'; then
    WARNINGS+=("file path contains shell metacharacters (\$(), backticks, ;, |) — command injection risk (CVE-2026-35021)")
  fi
fi

# --- Obfuscated injection patterns ---
# Base64-encoded "ignore" / "system" / "instructions" (common injection payloads)
if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE 'atob\(|btoa\(|base64[._-]?decode|b64decode'; then
  WARNINGS+=("base64 decode in code — check for obfuscated prompt injection or payload")
fi

# Unicode zero-width / invisible characters (used for hidden injection)
if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qP '[\x{200B}\x{200C}\x{200D}\x{FEFF}\x{00AD}]' 2>/dev/null; then
  WARNINGS+=("invisible Unicode characters detected — possible hidden prompt injection")
fi

# Nothing found — exit clean
[ "${#WARNINGS[@]}" -eq 0 ] && exit 0

# Build warning message
WARNING_LIST=$(printf ' • %s\n' "${WARNINGS[@]}")
MESSAGE="[SECURITY WARNING] Potentially insecure pattern(s) detected in the content being written to ${FILE_PATH:-<file>}:
${WARNING_LIST}

Review each pattern before proceeding. These may be intentional (test files, security tools, docs) — if so, no action needed."

# Emit additionalContext warning and exit 2 (asyncRewake: wakes Claude to deliver warning)
python3 -c "
import json, sys
msg = sys.argv[1]
print(json.dumps({
  'hookSpecificOutput': {
    'hookEventName': 'PreToolUse',
    'additionalContext': msg
  }
}))
" "$MESSAGE"

# Signal statusline: scan alert
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "code" > "$SCOPE_DIR/.scan-alert" 2>/dev/null || true

exit 2
