#!/usr/bin/env bash
# Comma matcher lists are inert before Claude Code v2.1.191 (v2.29.2)
#
# Claude Code's documented rule: a matcher of only [A-Za-z0-9_,| -] is an EXACT
# match — "Exact string, or list of exact strings separated by | or , with
# optional surrounding whitespace". Both separators mean the same thing.
#
# But only ONE of them has a version floor:
#   "Comma separators and the surrounding whitespace tolerance require
#    Claude Code v2.1.191 or later."
#
# Below that version a comma-list matcher parses as a single literal tool name
# ("Bash,PowerShell"), which no tool has. It selects nothing, fires nothing and
# errors nothing — so safety.sh, the write guards and the secret scanners were
# all silently absent for anyone on an older build, with no in-product signal.
# That is anthropics/claude-code#69970 (fixed upstream in 2.1.191); we do not
# pin a minimum Claude Code version, so the exposure is ours to close.
#
# The pipe form carries no version floor and is the SAME exact-list mode, so the
# rewrite is back-compat only. These tests assert exactly that: commas gone from
# tool-name matchers, and the SELECTED TOOL SET unchanged — a rewrite that
# quietly widened or narrowed coverage would be worse than the bug.
#
# Sibling guard to test-matcher-validity.sh (can this matcher match anything?)
# and test-mcp-matchers.sh (is this matcher in the right MODE?). This one asks:
# does this matcher still work on the versions our users actually run?
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Overridable so the fix can be negative-tested against a pre-fix hooks.json.
HOOKS_JSON="${SC_HOOKS_JSON:-$REPO_DIR/hooks/hooks.json}"

echo "=== Comma Matcher Back-Compat Tests ==="

# Claude Code's matcher rule, modelled exactly. Shared shape with
# test-mcp-matchers.sh: a bare re.search would substring-match and would happily
# call the broken form "working".
CC_PY="
import json, re, sys
SIMPLE = re.compile(r'^[A-Za-z0-9_,| -]*\$')
TOOL_EVENTS = ('PreToolUse', 'PostToolUse')

def tokens(m):
    # The token set an exact-list matcher selects. Separator-agnostic on
    # purpose: that is the whole point of the rewrite being a no-op.
    return frozenset(t.strip() for t in re.split(r'[,|]', m) if t.strip())

def load(path):
    return json.load(open(path))['hooks']
"

begin_test "no comma survives in a PreToolUse/PostToolUse matcher"
RES=$(python3 -c "$CC_PY
bad = []
for ev, entries in load(sys.argv[1]).items():
    if ev not in TOOL_EVENTS:
        continue
    for e in entries:
        m = e.get('matcher', '')
        if ',' in m:
            bad.append(ev + '::' + m)
print('COMMA: ' + '; '.join(sorted(set(bad))) if bad else 'OK')
" "$HOOKS_JSON" 2>&1)
if [ "$RES" = "OK" ]; then pass; else fail "inert on Claude Code < 2.1.191: $RES"; fi

begin_test "non-tool events keep their own matcher dialect"
# FileChanged matches FILE PATHS and Notification has its own vocabulary
# (idle_prompt, auth_success). Their commas are not tool-name separators, so a
# blanket comma rewrite would corrupt them. Assert we left them alone.
RES=$(python3 -c "$CC_PY
h = load(sys.argv[1])
fc = [e.get('matcher', '') for e in h.get('FileChanged', [])]
if not fc:
    print('MISSING FileChanged registration')
elif not any(',' in m and '.' in m for m in fc):
    print('REWRITTEN ' + str(fc))
else:
    print('OK')
" "$HOOKS_JSON" 2>&1)
if [ "$RES" = "OK" ]; then pass; else fail "non-tool matcher dialect damaged: $RES"; fi

begin_test "rewrite is semantically a no-op (same tools selected)"
# The source tuples in lib/hooks.sh are the pre-rewrite truth. Every emitted
# matcher must select the SAME token set as its source, differing only in
# separator. This is what stops the fix from silently changing coverage.
RES=$(
  source "$REPO_DIR/lib/hooks.sh" 2>/dev/null
  SRC=$(SUPERCHARGER_EMIT_ALL=1 get_hooks_for_mode "full" "true" '/h' 2>/dev/null)
  SRC="$SRC" python3 -c "$CC_PY
import os
src = {}
for line in os.environ['SRC'].strip().split('\n'):
    if not line.strip():
        continue
    p = line.split('|', 4)
    ev = p[0]
    m = p[1] if len(p) > 1 else ''
    if ev in TOOL_EVENTS and m and 'mcp__' not in m and SIMPLE.match(m):
        src.setdefault(ev, set()).add(tokens(m))

emitted = {}
for ev, entries in load(sys.argv[1]).items():
    if ev not in TOOL_EVENTS:
        continue
    for e in entries:
        m = e.get('matcher', '')
        if m and 'mcp__' not in m and SIMPLE.match(m):
            emitted.setdefault(ev, set()).add(tokens(m))

if not src:
    print('NO SOURCE TUPLES PARSED')
elif src == emitted:
    print('OK')
else:
    lost = {k: sorted(map(sorted, src.get(k, set()) - emitted.get(k, set()))) for k in src}
    gained = {k: sorted(map(sorted, emitted.get(k, set()) - src.get(k, set()))) for k in emitted}
    print('DRIFT lost=' + str({k: v for k, v in lost.items() if v})[:200] +
          ' gained=' + str({k: v for k, v in gained.items() if v})[:200])
" "$HOOKS_JSON" 2>&1
)
if [ "$RES" = "OK" ]; then pass; else fail "coverage changed: $RES"; fi

begin_test "pipe lists stay EXACT mode (no substring over-match)"
# The rewrite is only safe because | in a [A-Za-z0-9_,| -] matcher is a list
# separator, NOT regex alternation. If a rewritten matcher ever picked up a
# regex metacharacter it would become an unanchored regex and 'Bash|PowerShell'
# would start firing on BashOutput. Assert every rewritten matcher is still
# exact-mode and selects only real, whole tool names.
RES=$(python3 -c "$CC_PY
bad = []
for ev, entries in load(sys.argv[1]).items():
    if ev not in TOOL_EVENTS:
        continue
    for e in entries:
        m = e.get('matcher', '')
        if not m or 'mcp__' in m or not SIMPLE.match(m):
            continue
        for t in tokens(m):
            if not re.fullmatch(r'[A-Za-z0-9_]+', t):
                bad.append(ev + '::' + m + ' token=' + t)
print('BAD: ' + '; '.join(sorted(set(bad))) if bad else 'OK')
" "$HOOKS_JSON" 2>&1)
if [ "$RES" = "OK" ]; then pass; else fail "rewritten matcher left exact mode: $RES"; fi

begin_test "both emitters agree (settings.json vs plugin hooks.json)"
# lib/hooks.sh (installer) and tools/gen-plugin-hooks.sh each carry a copy of
# the rewrite. Cross-channel parity drift is a recurring bug class in this repo;
# here it would mean plugin users keep guards that classic users silently lose.
# merge_hooks_into_settings takes (mode, has_developer) and writes to
# $HOME/.claude/settings.json, so sandbox HOME rather than passing a path.
REAL_HOME="$HOME"
setup_test_home
SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
echo '{}' > "$SETTINGS"
# HARD STOP before writing — see the identical guard in test-mcp-matchers.sh.
# An earlier test in this repo merged into the developer's REAL settings.json.
if [ -z "$TEST_HOME" ] || [ "$HOME" = "$REAL_HOME" ]; then
  fail "refusing to run: HOME is not sandboxed (would write real settings.json)"
else
  (
    source "$REPO_DIR/lib/hooks.sh"
    merge_hooks_into_settings "full" "true"
  ) >/dev/null 2>&1
  RES=$(python3 -c "$CC_PY
def mats(path):
    out = set()
    for ev, entries in load(path).items():
        if ev not in TOOL_EVENTS:
            continue
        for e in entries:
            m = e.get('matcher', '')
            if m and SIMPLE.match(m):
                out.add(ev + '::' + m)
    return out
try:
    a = mats(sys.argv[1]); b = mats(sys.argv[2])
except Exception as ex:
    print('ERR ' + str(ex)); raise SystemExit
if a == b:
    print('OK')
else:
    print('DRIFT only-installer=' + str(sorted(a - b))[:200] +
          ' only-plugin=' + str(sorted(b - a))[:200])
" "$SETTINGS" "$HOOKS_JSON" 2>&1)
  teardown_test_home
  if [ "$RES" = "OK" ]; then pass; else fail "$RES"; fi
fi

report
