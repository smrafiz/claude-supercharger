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
if python3 -c "import json,sys; d=json.load(open('$HOOKS_JSON')); sys.exit(0 if isinstance(d.get('hooks'),dict) else 1)" 2>/dev/null; then
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
ENTRIES=$(python3 -c "import json; d=json.load(open('$HOOKS_JSON')); print(sum(len(v) for v in d['hooks'].values()))")
if [ "$TUPLES" = "$ENTRIES" ]; then pass; else fail "tuples=$TUPLES json=$ENTRIES"; fi

begin_test "hooks.json: async / asyncRewake / if flags survive the emit"
if python3 -c "
import json
d=json.load(open('$HOOKS_JSON'))
flat=[h for es in d['hooks'].values() for e in es for h in e.get('hooks',[])]
assert any(h.get('async') for h in flat), 'no async'
assert any(h.get('asyncRewake') for h in flat), 'no asyncRewake'
assert any(h.get('if') for h in flat), 'no if'
" 2>/dev/null; then pass; else fail "a flag class was dropped in emit"; fi

# Only run the real CLI validator when it's installed (skips cleanly in minimal CI).
if command -v claude >/dev/null 2>&1; then
  begin_test "claude plugin validate: hooks.json passes schema (warnings OK)"
  OUT=$(claude plugin validate "$REPO_DIR" 2>&1)
  if echo "$OUT" | grep -qiE 'hooks\.json.*(error|invalid)'; then
    fail "validator flagged hooks.json: $OUT"
  else
    pass
  fi
fi

report
