#!/usr/bin/env bash
# Claude Supercharger — Code Security Scanner Hook
# Event: PreToolUse | Matcher: Write,Edit
# Scans content Claude is about to write for common security vulnerabilities.
# Warns Claude but does not block — Claude may intentionally write these patterns
# in test files, security tools, or documentation.

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# v2.6.31: one python3 fork replaces 2 jq + ~6 python3 + ~22 grep invocations.
# Was: jq cwd, jq content + python3 fallback, python3 tool_name, wc, jq
# file_path + python3 fallback, then ~22 separate `grep -qE` for each pattern,
# plus a final python3 to JSON-wrap the message. Now: 1 python3 heredoc
# parses stdin, compiles the regex patterns once, walks them against the
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
# v2.9.3: NotebookEdit uses new_source (cell code) + notebook_path — cover it too.
content = ti.get('content') or ti.get('new_string') or ti.get('new_source') or ''
if not content and isinstance(ti.get('edits'), list):  # v2.22.6: MultiEdit edits[]
    content = '\n'.join(str(e.get('new_string', '')) for e in ti['edits'] if isinstance(e, dict))
tool_name = data.get('tool_name') or ''
file_path = ti.get('file_path') or ti.get('notebook_path') or ''

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
    # v2.23.15: Node command injection (mirrors the Python subprocess check) —
    # child_process.exec/execSync run through a shell; shell:true on spawn/exec
    # does the same. .execSync( is unambiguous (only child_process has it).
    (r'child_process\.exec\(|\.execSync\(',     'child_process.exec()/execSync() — command injection risk; use execFile/spawn with an args array'),
    (r'shell[ \t]*:[ \t]*true',                 'shell: true in a child_process call — command injection risk; pass args as an array, no shell'),
    (r'\.insertAdjacentHTML\(',                 'insertAdjacentHTML — XSS risk; sanitize input or use textContent'),
    (r'\.outerHTML[ \t]*=',                     '.outerHTML = — XSS risk; use textContent or a sanitizer'),
    (r'crypto\.createCipher\(',                 'crypto.createCipher() — deprecated & insecure (no IV); use createCipheriv with a random IV'),
)
# --- Python ---
py_checks = (
    (r'pickle\.loads?\(',                                   'pickle.load(s)() — unsafe deserialization; never unpickle untrusted data'),
    (r'(?:^|[^a-zA-Z_])(?:exec|compile)\(',                 'exec()/compile() — arbitrary code execution risk'),
    (r'os\.system\(',                                       'os.system() — shell injection risk; prefer subprocess with a list of args'),
    (r'os\.popen\(',                                        'os.popen() — shell injection risk; prefer subprocess with a list of args'),  # v2.23.15
    (r'subprocess\.(?:call|run|Popen).*shell[ \t]*=[ \t]*True', 'subprocess with shell=True — shell injection risk; pass args as a list instead'),
    (r'yaml\.load\(',                                       'yaml.load() — unsafe deserialization; use yaml.safe_load()'),  # v2.23.15
    (r'__import__\(',                                       '__import__() — dynamic import injection risk'),
)
# --- Cross-language unsafe deserialization (v2.23.15) ---
deser_checks = (
    (r'(?:^|[^a-zA-Z_])unserialize\(',  'unserialize() — PHP object-injection risk; never unserialize untrusted data'),
    (r'Marshal\.load\(',                'Marshal.load() — Ruby unsafe deserialization; never load untrusted data'),
    (r'ObjectInputStream',              'ObjectInputStream — Java unsafe deserialization; validate/avoid on untrusted data'),
)
# --- SQL injection ---
sql_checks = (
    (r'f"(?:SELECT|INSERT|UPDATE|DELETE)[^"]*\{',                  'f-string SQL query — SQL injection risk; use parameterised queries'),
    (r'"(?:SELECT|INSERT|UPDATE|DELETE)[^"]*"[ \t]*\+',            'string-concatenated SQL query — SQL injection risk; use parameterised queries'),
)
# --- Hardcoded secrets ---
# v2.8.2: match single/double/backtick quotes and `:` assignment. Previously
# only `key = "double"` fired — `password = 'x'` (Python's default quoting) and
# `password: "x"` (YAML/JS object) both slipped past. {3,} avoids empty stubs;
# a quote must follow the operator, so env reads (= os.environ[...]) don't match.
secret_checks = (
    ("password[ \t]*[:=][ \t]*[\"'`][^\"'`]{3,}",     'hardcoded password — use environment variables or a secrets manager'),
    ("secret[ \t]*[:=][ \t]*[\"'`][^\"'`]{3,}",       'hardcoded secret — use environment variables or a secrets manager'),
    ("api[_-]?key[ \t]*[:=][ \t]*[\"'`][^\"'`]{3,}",  'hardcoded api_key — use environment variables or a secrets manager'),
)
# --- Weak hashing ---
# v2.8.2: SHA-1 is collision-broken too — flag it alongside MD5.
hash_checks = (
    (r"crypto\.createHash\(['\"](?:md5|sha1)['\"]|hashlib\.(?:md5|sha1)\(",  'MD5/SHA-1 hashing — cryptographically broken; use SHA-256 or bcrypt for passwords'),
)
# --- Obfuscated injection ---
obf_checks = (
    (r'atob\(|btoa\(|base64[._-]?decode|b64decode',  'base64 decode in code — check for obfuscated prompt injection or payload'),
)

for pat, msg in js_checks + py_checks + deser_checks + sql_checks + hash_checks + obf_checks:
    if re.search(pat, content):
        warnings.append(msg)

# --- Insecure randomness for secrets (v2.23.15) ---
# Math.random()/the `random` module are fine for non-security use, so gate on a
# security context word nearby to keep false positives low (a blind Math.random(
# match would be far too noisy).
_SECCTX = re.compile(r'token|secret|password|passwd|nonce|salt|otp|api[_-]?key|session[_-]?id|csrf|reset', re.I)
if re.search(r'Math\.random\(', content) and _SECCTX.search(content):
    warnings.append('Math.random() used near a token/secret — not cryptographically secure; use crypto.getRandomValues() / crypto.randomBytes()')
if re.search(r'(?:^|[^a-zA-Z_])random\.(?:random|randint|choice|randrange|getrandbits)\(', content) and _SECCTX.search(content):
    warnings.append('random module used near a token/secret — not cryptographically secure; use the secrets module')

# secret_checks are case-insensitive — run with IGNORECASE
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
SCOPE_DIR="$SUPERCHARGER_STATE/scope"
SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -z "$SID" ] && SID="default"
mkdir -p "$SCOPE_DIR"
echo "code" > "$SCOPE_DIR/.scan-alert-${SID}" 2>/dev/null || true

# v2.6.77: was `exit 2` which hard-blocks every warning despite the JSON
# emitting `permissionDecision: "ask"`. Exit 0 lets CC honor the JSON
# decision (ask user) instead of unconditional deny.
exit 0
