#!/usr/bin/env bash
# Claude Supercharger — Code Security Scanner Hook
# Event: PreToolUse | Matcher: Write,Edit
# Scans content Claude is about to write for common security vulnerabilities.
# Warns Claude but does not block — Claude may intentionally write these patterns
# in test files, security tools, or documentation.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# v2.6.31: one python3 fork replaces 2 jq + ~6 python3 + ~22 grep invocations.
# Was: jq cwd, jq content + python3 fallback, python3 tool_name, wc, jq
# file_path + python3 fallback, then ~22 separate `grep -qE` for each pattern,
# plus a final python3 to JSON-wrap the message. Now: 1 python3 heredoc
# parses stdin, compiles all 22 regex patterns once, walks them against the
# content + file_path, and emits the final JSON. Median 80ms → ~30ms.
# asyncRewake hook — runs in background, doesn't block Claude, but volume
# matters: fires on every Write/Edit.
OUT=$(HOOK_INPUT="$_INPUT" HOOK_SUPPRESS="$HOOK_SUPPRESS" python3 <<'PYEOF'
import json, os, re, sys

raw = os.environ.get('HOOK_INPUT', '')
suppress = os.environ.get('HOOK_SUPPRESS', 'false').lower() in ('true', '1', 'yes')

try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

ti = data.get('tool_input') or {}
content = ti.get('content') or ti.get('new_string') or ''
tool_name = data.get('tool_name') or ''
file_path = ti.get('file_path') or ''

if not content or len(content) < 20:
    sys.exit(0)

# Edit patches under 5 lines often lack context for the regex to fire
# meaningfully; skip them to reduce noise.
if tool_name == 'Edit' and content.count('\n') < 4:
    sys.exit(0)

warnings = []

# --- JavaScript / TypeScript ---
js_checks = (
    (r'eval\(',                                 'eval() — arbitrary code execution risk'),
    (r'\.innerHTML[ \t]*=',                     '.innerHTML = — XSS risk; use textContent or a sanitizer'),
    (r'dangerouslySetInnerHTML',                'dangerouslySetInnerHTML — React XSS risk; sanitize input before use'),
    (r'document\.write\(',                      'document.write() — XSS risk'),
    (r'new Function\(',                         'new Function() — code injection risk'),
)
# --- Python ---
py_checks = (
    (r'pickle\.loads?\(',                                   'pickle.load(s)() — unsafe deserialization; never unpickle untrusted data'),
    (r'(?:^|[^a-zA-Z_])(?:exec|compile)\(',                 'exec()/compile() — arbitrary code execution risk'),
    (r'os\.system\(',                                       'os.system() — shell injection risk; prefer subprocess with a list of args'),
    (r'subprocess\.(?:call|run|Popen).*shell[ \t]*=[ \t]*True', 'subprocess with shell=True — shell injection risk; pass args as a list instead'),
    (r'__import__\(',                                       '__import__() — dynamic import injection risk'),
)
# --- SQL injection ---
sql_checks = (
    (r'f"(?:SELECT|INSERT|UPDATE|DELETE)[^"]*\{',                  'f-string SQL query — SQL injection risk; use parameterised queries'),
    (r'"(?:SELECT|INSERT|UPDATE|DELETE)[^"]*"[ \t]*\+',            'string-concatenated SQL query — SQL injection risk; use parameterised queries'),
)
# --- Hardcoded secrets ---
secret_checks = (
    (r'password[ \t]*=[ \t]*"[^"]+"',  'hardcoded password — use environment variables or a secrets manager'),
    (r'secret[ \t]*=[ \t]*"[^"]+"',    'hardcoded secret — use environment variables or a secrets manager'),
    (r'api_key[ \t]*=[ \t]*"[^"]+"',   'hardcoded api_key — use environment variables or a secrets manager'),
)
# --- Weak hashing ---
hash_checks = (
    (r"crypto\.createHash\(['\"]md5['\"]|hashlib\.md5\(",  'MD5 hashing — cryptographically broken; use SHA-256 or bcrypt for passwords'),
)
# --- Obfuscated injection ---
obf_checks = (
    (r'atob\(|btoa\(|base64[._-]?decode|b64decode',  'base64 decode in code — check for obfuscated prompt injection or payload'),
)

for pat, msg in js_checks + py_checks + sql_checks + hash_checks + obf_checks:
    if re.search(pat, content):
        warnings.append(msg)

for pat, msg in (
    (r'password[ \t]*=[ \t]*"[^"]+"', 'hardcoded password — use environment variables or a secrets manager'),
):
    pass  # placeholder so secret_checks above could be case-insensitive via re.I if needed

# secret_checks are case-insensitive in the original — re-run with IGNORECASE
for pat, msg in secret_checks:
    if re.search(pat, content, re.IGNORECASE) and msg not in warnings:
        warnings.append(msg)

# Unicode zero-width characters
if re.search(r'[​‌‍﻿­]', content):
    warnings.append('invisible Unicode characters detected — possible hidden prompt injection')

# GitHub Actions workflow command injection (only .yml/.yaml)
if file_path.endswith(('.yml', '.yaml')) and '${{ github.event.' in content:
    warnings.append('${{ github.event.* }} in workflow — GitHub Actions command injection risk; sanitise before use')

# File path shell metacharacters
if file_path and re.search(r'(\$\(|`|;|\||&&|\{)', file_path):
    warnings.append('file path contains shell metacharacters ($(), backticks, ;, |) — command injection risk if path is later interpolated into a shell command')

if not warnings:
    sys.exit(0)

warning_list = '\n'.join(' • ' + w for w in warnings)
message = (
    f'[SECURITY WARNING] Potentially insecure pattern(s) detected in the content being written to {file_path or "<file>"}:\n'
    f'{warning_list}\n\n'
    'Review each pattern before proceeding. These may be intentional (test files, security tools, docs) — if so, no action needed.'
)

# v2.7.30: the header intent is "warn Claude, do NOT block". The old shape
# ({'permissionDecision':'ask'} without the required hookEventName) was malformed
# and dropped by CC — and 'ask' would have escalated to a blocking prompt anyway.
# Warn Claude via hookSpecificOutput.additionalContext (supported on PreToolUse),
# no permission decision → no block.
print(json.dumps({
    'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'additionalContext': message},
    'suppressOutput': suppress,
}))
PYEOF
)

[ -z "$OUT" ] && exit 0
printf '%s\n' "$OUT"

# Signal statusline: scan alert (per-session, not global — v2.6.49)
SCOPE_DIR="$HOME/.claude/supercharger/scope"
SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -z "$SID" ] && SID="default"
mkdir -p "$SCOPE_DIR"
echo "code" > "$SCOPE_DIR/.scan-alert-${SID}" 2>/dev/null || true

# v2.6.77: was `exit 2` which hard-blocks every warning despite the JSON
# emitting `permissionDecision: "ask"`. Exit 0 lets CC honor the JSON
# decision (ask user) instead of unconditional deny.
exit 0
