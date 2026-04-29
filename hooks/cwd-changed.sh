#!/usr/bin/env bash
# Claude Supercharger — CwdChanged Hook
# Event: CwdChanged | Matcher: (none)
# Re-runs stack detection when working directory changes, injects updated context.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
LIB_DIR="$(cd "$HOOKS_DIR/../lib" && pwd)"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "cwd-changed" && exit 0
hook_profile_skip "cwd-changed" && exit 0

MSG=$(PROJECT_DIR="$PROJECT_DIR" LIB_DIR="$LIB_DIR" python3 -c "
import os, sys, hashlib
sys.path.insert(0, os.environ['LIB_DIR'])
from detect_stack import detect_stack

new_dir = os.environ['PROJECT_DIR']

# Skip if not a real project dir (no recognisable files)
s = detect_stack(new_dir)
if not s['detected']:
    sys.exit(0)

# Only inject if stack differs from cached value for this dir
cache_dir = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
proj_hash = hashlib.md5(new_dir.encode()).hexdigest()[:8]
cache_path = os.path.join(cache_dir, f'.stack-cache-{proj_hash}')

stack_parts = list(s['language'])
if s['framework']:
    stack_parts.append(s['framework'][0])
if s['package_manager'] and s['package_manager'] not in ('pip', 'cargo', 'go modules', 'composer'):
    stack_parts.append(f'pkg:{s[\"package_manager\"]}')
stack_str = ', '.join(stack_parts)

cached = ''
if os.path.isfile(cache_path):
    try:
        with open(cache_path) as f:
            cached = f.read().strip()
    except Exception:
        pass

if cached == stack_str:
    sys.exit(0)

# Update cache
try:
    os.makedirs(cache_dir, exist_ok=True)
    with open(cache_path, 'w') as f:
        f.write(stack_str)
except Exception:
    pass

print(f'Working directory changed to {new_dir}. Stack: {stack_str}. Use matching conventions.')
" 2>/dev/null)

[ -z "$MSG" ] && exit 0

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
hook_already_emitted "cwd-changed" "$SESSION_ID" "$MSG" && exit 0

MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"

exit 0
