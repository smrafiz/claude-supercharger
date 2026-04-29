#!/usr/bin/env bash
# Claude Supercharger — Lazy Refactor Check
# Event: PostToolUse | Matcher: Edit, MultiEdit
# Detects when Claude renames a parameter `foo` to `_foo` instead of properly
# removing or handling it. Universal anti-pattern across TS/JS/Python/Rust/etc.
# Inspired by carlrannaberg/claudekit check-unused-parameters.

set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "lazy-refactor-check" && exit 0
hook_profile_skip "lazy-refactor-check" && exit 0

MSG=$(printf '%s\n' "$_INPUT" | python3 -c "
import os, sys, json, re

TIER = os.environ.get('SUPERCHARGER_TIER', 'standard')

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = d.get('tool_name') or ''
if tool not in ('Edit', 'MultiEdit'):
    sys.exit(0)

inp = d.get('tool_input') or {}
file_path = (inp.get('file_path') or '').lower()

# Code files only
CODE_EXTS = ('.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.py', '.rs', '.go', '.java', '.kt', '.swift', '.rb', '.php')
if not any(file_path.endswith(e) for e in CODE_EXTS):
    sys.exit(0)

# Collect edits
edits = []
if tool == 'Edit':
    o, n = inp.get('old_string') or '', inp.get('new_string') or ''
    if o and n:
        edits.append((o, n))
elif tool == 'MultiEdit':
    for e in (inp.get('edits') or []):
        o, n = e.get('old_string') or '', e.get('new_string') or ''
        if o and n:
            edits.append((o, n))

if not edits:
    sys.exit(0)

PARAM_LIST_RE = re.compile(r'\\(([^)]*)\\)')

def extract_params(code):
    m = PARAM_LIST_RE.search(code)
    if not m:
        return []
    parts = m.group(1).split(',')
    out = []
    for p in parts:
        nm = re.match(r'\\s*(?:\\.\\.\\.)?(\\w+)', p)
        if nm:
            out.append(nm.group(1))
    return out

violations = []
for old, new in edits:
    old_params = extract_params(old)
    new_params = extract_params(new)
    if not old_params or len(old_params) != len(new_params):
        continue
    for o, n in zip(old_params, new_params):
        if n == f'_{o}' or (not o.startswith('_') and n.startswith('_')):
            violations.append((o, n))
            break

if violations:
    o, n = violations[0]
    if TIER == 'minimal':
        print(f'[lazy] {o} -> {n} — remove or document')
    elif TIER == 'lean':
        print(f'[Lazy refactor] {o} -> {n}: remove unused param or document why kept')
    else:
        print(f'Lazy refactor: parameter \\'{o}\\' renamed to \\'{n}\\' instead of removed. If unused, delete it. If kept for API/interface, document why with a comment.')
" 2>/dev/null)

[ -z "$MSG" ] && exit 0

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
hook_already_emitted "lazy-refactor-check" "$SESSION_ID" "$MSG" && exit 0

MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"

exit 0
