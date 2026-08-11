#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GEN="$REPO_DIR/tools/gen-plugin-hooks.sh"
HOOKS_JSON="$REPO_DIR/hooks/hooks.json"

echo "=== Plugin hooks.json Emitter Tests ==="

begin_test "gen-plugin-hooks: committed hooks/hooks.json is up to date"
OUT=$(bash "$GEN" --check 2>&1)
if [ $? -eq 0 ]; then pass; else fail "stale — run gen-plugin-hooks.sh: $OUT"; fi

begin_test "hooks.json: valid JSON wrapped in top-level 'hooks' object"
if python3 -c "import sys, json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d.get('hooks'),dict) else 1)" "$HOOKS_JSON" 2>/dev/null; then
  pass
else
  fail "hooks.json is not {\"hooks\": {...}}"
fi

begin_test "hooks.json: every command uses \${CLAUDE_PLUGIN_ROOT}, none reference \$HOME"
BAD=$(python3 -c "
import json
d=json.load(open('$HOOKS_JSON'))
bad=[]
for ev,entries in d['hooks'].items():
    for e in entries:
        for h in e.get('hooks',[]):
            c=h.get('command','')
            if '\${CLAUDE_PLUGIN_ROOT}' not in c or '/.claude/supercharger' in c or '\$HOME' in c:
                bad.append(ev+': '+c)
print('\n'.join(bad))
" 2>/dev/null)
if [ -z "$BAD" ]; then pass; else fail "bad commands: $BAD"; fi

begin_test "hooks.json: \${CLAUDE_PLUGIN_ROOT} is double-quoted for space-safety"
UNQUOTED=$(python3 -c "
import json
d=json.load(open('$HOOKS_JSON'))
bad=[c for ev,es in d['hooks'].items() for e in es for h in e.get('hooks',[])
     for c in [h.get('command','')] if c and '\"\${CLAUDE_PLUGIN_ROOT}\"' not in c]
print('\n'.join(bad))
" 2>/dev/null)
if [ -z "$UNQUOTED" ]; then pass; else fail "unquoted plugin-root: $UNQUOTED"; fi

begin_test "hooks.json: registration count matches get_hooks_for_mode (no drift)"
# shellcheck source=lib/hooks.sh
. "$REPO_DIR/lib/hooks.sh"
TUPLES=$(SUPERCHARGER_EMIT_ALL=1 get_hooks_for_mode "full" "true" '"${CLAUDE_PLUGIN_ROOT}"/hooks' | grep -c .)
ENTRIES=$(python3 -c "import sys, json; d=json.load(open(sys.argv[1])); print(sum(len(v) for v in d['hooks'].values()))" "$HOOKS_JSON")
if [ "$TUPLES" = "$ENTRIES" ]; then pass; else fail "tuples=$TUPLES json=$ENTRIES"; fi

begin_test "hooks.json: async / asyncRewake flags survive the emit"
if python3 -c "
import json, sys
d=json.load(open(sys.argv[1]))
flat=[h for es in d['hooks'].values() for e in es for h in e.get('hooks',[])]
assert any(h.get('async') for h in flat), 'no async'
assert any(h.get('asyncRewake') for h in flat), 'no asyncRewake'
" "$HOOKS_JSON" 2>/dev/null; then pass; else fail "a flag class was dropped in emit"; fi

begin_test "no registration uses the 'if' field — it stops the hook firing at all"
# v2.26.85: `if` was dropped from the two git registrations, and this asserts it
# stays dropped rather than asserting the emitter can still produce it.
#
# Measured against a live Claude Code session: a hook registered with `if` NEVER
# FIRES. `git push --force origin main` — a command that literally starts with the
# gated prefix — was not blocked, while the same installed hook invoked directly
# returns rc=2. git-safety (force-push) and git-remote-guard (remote exfiltration)
# had both been inert on every classic install since 6fc897b.
#
# Same class as v2.24.5, where a bare `mcp__` matcher silently killed 13
# registrations: a filter that matches nothing fires nothing and errors nothing.
# The emitter still SUPPORTS the field; nothing may use it until someone
# demonstrates, on a live session, that a gated hook actually runs.
GATED=$(python3 -c "
import json, sys
d=json.load(open(sys.argv[1]))
print(' '.join(h.get('command','?').split('/')[-1].split()[0]
                for es in d['hooks'].values() for e in es for h in e.get('hooks',[])
                if h.get('if')))
" "$HOOKS_JSON" 2>/dev/null)
[ -z "$GATED" ] && pass || fail "if-gated (and therefore inert) registrations: $GATED"

begin_test "hooks.json: every hook carries a timeout (CC defaults to 600s)"
# The default is ten minutes, so an unbounded hook that wedges freezes a tool call
# for that long with no indication why. Asserting on EVERY entry, not on presence
# somewhere: one un-timed hook on the hot path is the whole problem.
if python3 -c "
import json
d=json.load(open('$HOOKS_JSON'))
flat=[h for es in d['hooks'].values() for e in es for h in e.get('hooks',[])]
missing=[h['command'] for h in flat if not isinstance(h.get('timeout'), int)]
assert not missing, 'no timeout on: %s' % missing[:3]
" 2>/dev/null; then pass; else fail "at least one hook has no timeout"; fi

begin_test "hooks.json: blocking hooks get the tight cap, async hooks the loose one"
# Two tiers because they fail differently — a blocking hook stalls the user, an
# async one stalls nobody. A single value would either strangle the async scanners
# or leave the hot path effectively unbounded.
if python3 -c "
import json
d=json.load(open('$HOOKS_JSON'))
flat=[h for es in d['hooks'].values() for e in es for h in e.get('hooks',[])]
for h in flat:
    want = 120 if (h.get('async') or h.get('asyncRewake')) else 15
    assert h.get('timeout') == want, (h['command'], h.get('timeout'), want)
assert any(h['timeout'] == 15 for h in flat) and any(h['timeout'] == 120 for h in flat)
" 2>/dev/null; then pass; else fail "timeout tier wrong for at least one hook"; fi

# The real CLI validator only runs where it is installed — but the ASSERTION is
# always emitted. v2.24.11: `begin_test` used to live inside the `if`, so on a
# machine without the CLI this test silently did not exist. That made the suite
# TOTAL environment-dependent (present on a dev mac, absent on the CI runner),
# and the README tests-badge check compares that total exactly — so CI could not
# be green on both platforms at once. Reporting the skip keeps the count stable
# and keeps the skip visible, which is the point of test-orphan-registration.
begin_test "claude plugin validate: hooks.json passes schema (warnings OK)"
if command -v claude >/dev/null 2>&1; then
  OUT=$(claude plugin validate "$REPO_DIR" 2>&1)
  if echo "$OUT" | grep -qiE 'hooks\.json.*(error|invalid)'; then
    fail "validator flagged hooks.json: $OUT"
  else
    pass
  fi
else
  echo "    (skipped: claude CLI not installed — schema not validated here)"
  pass
fi

echo ""
echo "=== Prompt-Layer Inject Tests (Phase 3) ==="

INJECT="$REPO_DIR/hooks/prompt-layer-inject.sh"

begin_test "prompt-layer-inject: plugin runtime emits additionalContext with the layer"
DATA=$(mktemp -d)
OUT=$(printf '{"session_id":"t","source":"startup"}' | CLAUDE_PLUGIN_ROOT="$REPO_DIR" CLAUDE_PLUGIN_DATA="$DATA" bash "$INJECT" 2>/dev/null)
if printf '%s' "$OUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
c=d['hookSpecificOutput']['additionalContext']
assert d['hookSpecificOutput']['hookEventName']=='SessionStart'
assert 'Claude Supercharger' in c and 'Token Economy' in c
assert '{{' not in c, 'unfilled placeholder'
" 2>/dev/null; then pass; else fail "bad/empty additionalContext: $OUT"; fi
rm -rf "$DATA"

begin_test "prompt-layer-inject: installer runtime (no CLAUDE_PLUGIN_ROOT) is a no-op"
OUT=$(printf '{"session_id":"t"}' | env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA bash "$INJECT" 2>/dev/null || true)
if [ -z "$OUT" ]; then pass; else fail "expected no output under installer, got: $OUT"; fi

begin_test "prompt-layer-inject: SUPERCHARGER_TIER selects the tier snippet"
DATA=$(mktemp -d)
MARK=$(head -3 "$REPO_DIR/configs/economy/minimal.md" | tail -1)
OUT=$(printf '{"session_id":"t"}' | CLAUDE_PLUGIN_ROOT="$REPO_DIR" CLAUDE_PLUGIN_DATA="$DATA" SUPERCHARGER_TIER=minimal bash "$INJECT" 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])" 2>/dev/null)
if printf '%s' "$OUT" | grep -qF "$MARK"; then pass; else fail "minimal tier snippet not injected"; fi
rm -rf "$DATA"

# Regression: the active role's rules file must be injected, not just the role NAME
# (bug fixed 2.17: prompt-layer-inject only filled {{ROLES}} and never read configs/roles/<role>.md).
begin_test "prompt-layer-inject: injects the active role's rules (configs/roles/<role>.md)"
DATA=$(mktemp -d)
OUT=$(printf '{"session_id":"t"}' | CLAUDE_PLUGIN_ROOT="$REPO_DIR" CLAUDE_PLUGIN_DATA="$DATA" CLAUDE_PLUGIN_OPTION_ROLE=writer bash "$INJECT" 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])" 2>/dev/null)
# "## Communication Style" is a stable, ASCII-only heading unique to configs/roles/writer.md.
if printf '%s' "$OUT" | grep -qF "## Communication Style"; then pass; else fail "writer role rules not injected (only the name?)"; fi
rm -rf "$DATA"

report
