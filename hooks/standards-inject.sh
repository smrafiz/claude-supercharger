#!/usr/bin/env bash
# Claude Supercharger — Stack Standards Injector
# Event: SessionStart | Matcher: (none)
# Detects project stack via lib/detect_stack.py and injects matching standards
# (forbidden patterns, toolchain, pitfalls) from rules/stacks/<name>.md.
# User override: ~/.claude/rules/stacks/<name>.md takes precedence over bundled.
# Tier-scaled output: minimal=stack tag, lean=key sections, standard=full.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# These dirs may be missing on installs that pre-date the rules/stacks copy
# (the install.sh fix landed alongside this hardening). Skip cleanly when
# nothing is available rather than crashing the SessionStart hook.
LIB_DIR=""
[ -d "$HOOKS_DIR/../lib" ] && LIB_DIR="$(cd "$HOOKS_DIR/../lib" && pwd)"
RULES_DIR=""
[ -d "$HOOKS_DIR/../rules" ] && RULES_DIR="$(cd "$HOOKS_DIR/../rules" && pwd)"
[ -z "$LIB_DIR" ] && exit 0
[ -z "$RULES_DIR" ] && [ ! -d "$HOME/.claude/rules/stacks" ] && exit 0

[ "${SUPERCHARGER_STANDARDS:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "standards-inject" && exit 0
hook_profile_skip "standards-inject" && exit 0

MSG=$(PROJECT_DIR="$PROJECT_DIR" LIB_DIR="$LIB_DIR" RULES_DIR="$RULES_DIR" python3 -c "
import os, sys
sys.path.insert(0, os.environ['LIB_DIR'])
from detect_stack import detect_stack

TIER = os.environ.get('SUPERCHARGER_TIER', 'standard')
proj = os.environ['PROJECT_DIR']
rules_dir = os.environ['RULES_DIR']
home = os.path.expanduser('~')

s = detect_stack(proj)
if not s['detected']:
    sys.exit(0)

matched = []
fw = [f.lower() for f in s.get('framework', [])]
langs = [l.lower() for l in s.get('language', [])]

for name in fw:
    n = name.lower()
    if 'next' in n and 'nextjs' not in matched:
        matched.append('nextjs')
    if 'react' in n and 'react' not in matched:
        matched.append('react')
    if 'svelte' in n and 'svelte' not in matched:
        matched.append('svelte')
    if n == 'vue' and 'vue' not in matched:
        matched.append('vue')
for lang in langs:
    if lang in ('python', 'go', 'rust', 'php') and lang not in matched:
        matched.append(lang)

if not matched:
    sys.exit(0)

if TIER == 'minimal':
    print('[stack: ' + '+'.join(matched) + ']')
    sys.exit(0)

def resolve_stack_file(name):
    user = os.path.join(home, '.claude', 'rules', 'stacks', name + '.md')
    if os.path.isfile(user):
        return user
    bundled = os.path.join(rules_dir, 'stacks', name + '.md')
    if os.path.isfile(bundled):
        return bundled
    return None

def parse_sections(text):
    body = text
    if body.startswith('---'):
        end = body.find('---', 3)
        if end != -1:
            body = body[end+3:].lstrip()
    sections = {}
    current = None
    buf = []
    for line in body.splitlines():
        if line.startswith('## '):
            if current:
                sections[current] = '\n'.join(buf).rstrip()
            current = line[3:].strip()
            buf = [line]
        else:
            buf.append(line)
    if current:
        sections[current] = '\n'.join(buf).rstrip()
    return sections

allowed = {'lean': ('Forbidden', 'Toolchain')}
keep = allowed.get(TIER)

out_blocks = []
for name in matched:
    p = resolve_stack_file(name)
    if not p:
        continue
    with open(p) as f:
        text = f.read()
    if keep is None:
        body = text
        if body.startswith('---'):
            end = body.find('---', 3)
            if end != -1:
                body = body[end+3:].lstrip()
        out_blocks.append('# ' + name + '\n' + body.rstrip())
    else:
        secs = parse_sections(text)
        kept = [secs[k] for k in keep if k in secs]
        if kept:
            out_blocks.append('# ' + name + '\n' + '\n\n'.join(kept))

if out_blocks:
    print('\n\n'.join(out_blocks))
" 2>/dev/null)

[ -z "$MSG" ] && exit 0

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
hook_already_emitted "standards-inject" "$SESSION_ID" "$MSG" && exit 0

# Cross-session TTL: stack rules don't change between sessions of the same
# project, so re-injecting on every session start is pure token waste. Skip
# if we've already emitted for this (project, message-hash) pair within the
# last 24h. Saves ~425 tokens × N sessions/day per project (react+nextjs).
TTL_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$TTL_DIR" 2>/dev/null
PROJECT_HASH=$(printf '%s' "$PROJECT_DIR" | shasum 2>/dev/null | cut -c1-12)
if [ -n "$PROJECT_HASH" ]; then
  TTL_FILE="$TTL_DIR/.standards-inject-${PROJECT_HASH}"
  MSG_HASH=$(printf '%s' "$MSG" | shasum 2>/dev/null | cut -c1-12)
  if [ -f "$TTL_FILE" ]; then
    LAST=$(cat "$TTL_FILE" 2>/dev/null | head -1)
    LAST_TS="${LAST%% *}"; LAST_HASH="${LAST##* }"
    NOW_TS=$(date +%s)
    if [ -n "$LAST_TS" ] && [ "$LAST_HASH" = "$MSG_HASH" ] && [ $((NOW_TS - LAST_TS)) -lt 86400 ]; then
      exit 0
    fi
  fi
  printf '%s %s\n' "$(date +%s)" "$MSG_HASH" > "$TTL_FILE"
fi

# v2.7.8: jq -Rs replaces a python3 fork for JSON string-escaping (same pattern
# as session-memory-inject / agent-router); python fallback kept for jq-less hosts.
MSG_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null \
  || printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)
printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"
exit 0
