#!/usr/bin/env bash
# MCP matcher normalization (v2.24.5)
#
# Regression guard for a SILENT security failure: every hook registered with a
# bare "mcp__" matcher had stopped firing. Claude Code decides matcher mode from
# the matcher's own characters — one made only of [A-Za-z0-9_,| -] is an EXACT
# match (optionally a list), anything else is an unanchored regex. So "mcp__"
# asked for a tool literally *named* "mcp__", which no server exposes, and the
# hooks never ran. Nothing errors when a matcher matches nothing, so this was
# invisible until the statusline's MCP badge stopped appearing.
#
# Six hooks were inert, including mcp-egress-guard (SSRF/exfil) and the mcp__
# arms of prompt-injection-scanner and output-secrets-scanner.
#
# These tests assert the emitted matchers, not the source tuples — the rewrite
# happens at emit time, after the '|' split, because regex alternation is also
# '|' and would otherwise corrupt the pipe-delimited record.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Overridable so the fix can be negative-tested against a pre-fix hooks.json —
# a matcher test that passes on the broken file would be worthless.
HOOKS_JSON="${SC_HOOKS_JSON:-$REPO_DIR/hooks/hooks.json}"

# Claude Code's documented matcher rule, modelled exactly: a matcher made only of
# [A-Za-z0-9_,| -] is an EXACT match (optionally a comma/pipe list); anything else
# is an unanchored regex. Tests MUST use this rather than a bare re.search, which
# substring-matches and would report the broken 'mcp__' form as working.
CC_MATCH_PY="
import re
SIMPLE=re.compile(r'^[A-Za-z0-9_,| -]*\$')
def cc_matches(matcher, tool):
    if matcher in ('','*'): return True
    if SIMPLE.match(matcher):
        toks=[t.strip() for t in re.split(r'[,|]', matcher) if t.strip()]
        return tool in toks
    try:
        return re.search(matcher, tool) is not None
    except re.error:
        return False
"

echo "=== MCP Matcher Normalization Tests ==="

begin_test "mcp matchers: no emitted matcher is a bare mcp__ prefix (the inert form)"
BAD=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))['hooks']
bad=[]
for ev,entries in d.items():
    for e in entries:
        m=e.get('matcher','')
        for tok in m.split('|'):
            # A token that starts with mcp__ but has no regex metachar can only
            # ever match a tool with that exact literal name -> never fires.
            if tok.startswith('mcp__') and '.' not in tok and '*' not in tok:
                bad.append(ev+':'+m)
print('; '.join(sorted(set(bad))))
" "$HOOKS_JSON" 2>&1)
if [ -z "$BAD" ]; then pass; else fail "bare mcp__ matcher (will never fire): $BAD"; fi

begin_test "mcp matchers: every mcp__ token ends in .* so mcp__<server>__<tool> matches"
BAD=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))['hooks']
bad=[]
for ev,entries in d.items():
    for e in entries:
        m=e.get('matcher','')
        for tok in m.split('|'):
            if tok.startswith('mcp__') and not tok.endswith('.*'):
                bad.append(tok)
print('; '.join(sorted(set(bad))))
" "$HOOKS_JSON" 2>&1)
if [ -z "$BAD" ]; then pass; else fail "mcp token without .* suffix: $BAD"; fi

begin_test "mcp matchers: regex actually matches a real mcp__<server>__<tool> name"
# The whole point — verify against concrete tool names seen in the wild rather
# than trusting the shape of the string.
RES=$(python3 -c "
import json,re,sys
$CC_MATCH_PY
d=json.load(open(sys.argv[1]))['hooks']
samples={
 'mcp__context7__supercharger__resolve-library-id':'generic mcp',
 'mcp__github__create_or_update_file':'github write gate',
 'mcp__postgres__query':'sql guard',
 'mcp__playwright__browser_navigate':'playwright guard',
 'mcp__filesystem__write_file':'destructive guard',
 'mcp__desktop-commander__execute_command':'shell-exec via safety.sh',
}
hit={k:False for k in samples}
for ev,entries in d.items():
    for e in entries:
        m=e.get('matcher','')
        if 'mcp__' not in m: continue
        for name in samples:
            if cc_matches(m,name): hit[name]=True
miss=[samples[k] for k,v in hit.items() if not v]
print('UNMATCHED: '+', '.join(sorted(miss)) if miss else 'OK')
" "$HOOKS_JSON" 2>&1)
if [ "$RES" = "OK" ]; then pass; else fail "$RES"; fi

begin_test "mcp matchers: plain tool lists stay EXACT (regex mode would over-match)"
# Bash,PowerShell must not become a regex — unanchored it would also match
# BashOutput and friends, silently widening hooks that were never scoped to them.
BAD=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))['hooks']
bad=[]
for ev,entries in d.items():
    for e in entries:
        m=e.get('matcher','')
        if 'mcp__' in m or m in ('','*'): continue
        if '.' in m and 'settings.json' not in m and '.env' not in m:
            bad.append(ev+':'+m)
        if '*' in m:
            bad.append(ev+':'+m)
print('; '.join(sorted(set(bad))))
" "$HOOKS_JSON" 2>&1)
if [ -z "$BAD" ]; then pass; else fail "non-mcp matcher gained regex metachars: $BAD"; fi

begin_test "mcp matchers: mixed lists keep their non-mcp tools matching"
# output-secrets-scanner is Bash,Read,WebFetch,WebSearch + mcp__. Turning it into
# a regex must not cost it the Bash arm.
RES=$(python3 -c "
import json,re,sys
$CC_MATCH_PY
d=json.load(open(sys.argv[1]))['hooks']
need=[('Bash','output-secrets-scanner.sh'),('Read','prompt-injection-scanner.sh'),
      ('WebFetch','output-secrets-scanner.sh'),('Bash','safety.sh')]
bad=[]
for tool,script in need:
    ok=False
    for ev,entries in d.items():
        for e in entries:
            if not any(script in h.get('command','') for h in e.get('hooks',[])): continue
            if cc_matches(e.get('matcher',''),tool): ok=True
    if not ok: bad.append(tool+' -> '+script)
print('LOST: '+'; '.join(bad) if bad else 'OK')
" "$HOOKS_JSON" 2>&1)
if [ "$RES" = "OK" ]; then pass; else fail "$RES"; fi

# v2.26.48: coverage that exists only because a SIBLING token forced regex mode.
#
# `mcp__.*|WebFetch|WebSearch|Read` is a regex (it contains . and *), so the
# `Read` arm is UNANCHORED and matches inside `ReadMcpResourceTool` — MCP
# resource reads are scanned for injection and secrets. That is real coverage,
# but nothing declared it: it is a side effect of the mcp__ token's presence.
#
# Drop or rename that token and the matcher flips to exact-list mode, silently
# losing every substring match. No error, no failing test — the same shape as
# v2.24.5, where a bare `mcp__` matched nothing and killed 13 registrations
# quietly. This pins the outcome rather than the spelling.
begin_test "mcp matchers: MCP resource reads are actually scanned (regex-mode side effect)"
RES=$(python3 -c "
import json,sys
$CC_MATCH_PY
d=json.load(open(sys.argv[1]))['hooks']
# tool -> the scanners that must see it
need=[('ReadMcpResourceTool','prompt-injection-scanner.sh'),
      ('ReadMcpResourceTool','output-secrets-scanner.sh')]
bad=[]
for tool,script in need:
    ok=False
    for ev,entries in d.items():
        for e in entries:
            if not any(script in h.get('command','') for h in e.get('hooks',[])): continue
            if cc_matches(e.get('matcher',''),tool): ok=True
    if not ok: bad.append(tool+' -> '+script)
print('UNSCANNED: '+'; '.join(bad) if bad else 'OK')
" "$HOOKS_JSON" 2>&1)
if [ "$RES" = "OK" ]; then pass; else fail "$RES"; fi

begin_test "mcp matchers: the scanner matchers are in regex mode, not exact"
# The assertion above passes ONLY in regex mode. State the precondition too, so a
# failure says WHY coverage was lost rather than just that it was.
RES=$(python3 -c "
import json,re,sys
SIMPLE=re.compile(r'^[A-Za-z0-9_,| -]*\$')
d=json.load(open(sys.argv[1]))['hooks']
bad=[]
for ev,entries in d.items():
    for e in entries:
        for h in e.get('hooks',[]):
            c=h.get('command','')
            if 'prompt-injection-scanner.sh' in c or 'output-secrets-scanner.sh' in c:
                m=e.get('matcher','')
                if m not in ('','*') and SIMPLE.match(m):
                    bad.append(ev+':'+m)
print('EXACT-MODE: '+'; '.join(sorted(set(bad))) if bad else 'OK')
" "$HOOKS_JSON" 2>&1)
if [ "$RES" = "OK" ]; then pass; else fail "scanner matcher fell back to exact mode, losing substring coverage: $RES"; fi

begin_test "mcp matchers: both emitters agree (settings.json vs plugin hooks.json)"
# lib/hooks.sh (installer) and tools/gen-plugin-hooks.sh each carry a copy of the
# normalizer. Cross-channel parity drift is a recurring bug class in this repo,
# and here it would mean plugin users silently lose guards that classic users keep.
# merge_hooks_into_settings takes (mode, has_developer) and writes to
# $HOME/.claude/settings.json, so sandbox HOME rather than passing a path.
REAL_HOME="$HOME"
setup_test_home
SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
echo '{}' > "$SETTINGS"
# HARD STOP before writing. merge_hooks_into_settings takes (mode, has_developer)
# and writes to $HOME/.claude/settings.json — it does NOT take a path. An earlier
# draft of this test passed a path as $1 and merged into the developer's REAL
# settings.json. Writing live user config from a test is the same isolation-leak
# class that silently deleted an active autopilot flag, so refuse rather than risk it.
if [ -z "$TEST_HOME" ] || [ "$HOME" = "$REAL_HOME" ]; then
  fail "refusing to run: HOME is not sandboxed (would write real settings.json)"
else
  (
    source "$REPO_DIR/lib/hooks.sh"
    merge_hooks_into_settings "full" "true"
  ) >/dev/null 2>&1
RES=$(python3 -c "
import json,sys
def mats(path,key):
    d=json.load(open(path))['hooks']
    out=set()
    for ev,entries in d.items():
        for e in entries:
            m=e.get('matcher','')
            if 'mcp__' in m: out.add(ev+'::'+m)
    return out
try:
    a=mats(sys.argv[1],'x'); b=mats(sys.argv[2],'x')
except Exception as ex:
    print('ERR '+str(ex)); raise SystemExit
if a==b: print('OK')
else:
    print('DRIFT only-installer='+str(sorted(a-b))[:200]+' only-plugin='+str(sorted(b-a))[:200])
" "$SETTINGS" "$HOOKS_JSON" 2>&1)
  teardown_test_home
  if [ "$RES" = "OK" ]; then pass; else fail "$RES"; fi
fi

report
