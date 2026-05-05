#!/usr/bin/env bash
# Claude Supercharger — Comment Replacement Check
# Event: PostToolUse | Matcher: Edit, MultiEdit
# Detects when Claude replaces working code with comments. Advisory — injects
# systemMessage so Claude deletes code cleanly instead of leaving "this was here"
# comments. Skipped for .md/.mdx/.txt/.rst files.
# Inspired by carlrannaberg/claudekit check-comment-replacement.

set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
[ "${SUPERCHARGER_ADVISORY_HOOKS:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "comment-replacement-check" && exit 0
hook_profile_skip "comment-replacement-check" && exit 0

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

# Skip docs
for ext in ('.md', '.mdx', '.txt', '.rst'):
    if file_path.endswith(ext):
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

COMMENT_PATTERNS = [
    re.compile(r'^\s*//.*'),
    re.compile(r'^\s*/\*.*\*/\s*$'),
    re.compile(r'^\s*#(?!#).*'),
    re.compile(r'^\s*--.*'),
    re.compile(r'^\s*\*\s+.*'),
    re.compile(r'^\s*<!--.*-->\s*$'),
]

def is_comment(line):
    s = line.strip()
    if not s:
        return False
    return any(p.match(s) for p in COMMENT_PATTERNS)

violations = 0
for old, new in edits:
    old_lines = [l for l in old.split('\n') if l.strip()]
    new_lines = [l for l in new.split('\n') if l.strip()]
    if not old_lines or not new_lines:
        continue
    old_code = [l for l in old_lines if not is_comment(l)]
    if not old_code:
        continue  # old was already all comments
    new_all_comments = all(is_comment(l) for l in new_lines)
    if not new_all_comments:
        continue
    # Size check: if new is significantly smaller, it's probably a deletion-with-explanation, not replacement
    size_diff = abs(len(old_lines) - len(new_lines))
    threshold = max(2, len(old_lines) * 0.5)
    if size_diff <= threshold:
        violations += 1

if violations:
    if TIER == 'minimal':
        print(f'[comment-repl] {violations} block(s) — delete, do not comment out')
    elif TIER == 'lean':
        print(f'[Comment replace] {violations} block(s) — delete cleanly, do not comment out')
    else:
        print(f'Code-with-comments replacement detected ({violations} block(s)). If you mean to remove code, delete it cleanly. Comments left behind become noise — git history records why code was removed.')
" 2>/dev/null)

[ -z "$MSG" ] && exit 0

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
hook_already_emitted "comment-replacement-check" "$SESSION_ID" "$MSG" && exit 0

MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"

exit 0
