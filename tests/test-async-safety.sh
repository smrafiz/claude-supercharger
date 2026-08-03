#!/usr/bin/env bash
# A hook may only be async if nothing downstream waits on it (v2.26.37)
#
# `async: true` means Claude Code does not wait for the hook before proceeding.
# That is free latency for a hook whose only output is an advisory line on
# stderr — and silently BROKEN for one that blocks, asks, or injects context,
# because the decision would arrive after the thing it was meant to gate.
#
# prompt-validator was 35ms of the ~131ms UserPromptSubmit chain: the single
# largest contributor to the gap between the user pressing enter and the model
# starting. It writes only stderr and always exits 0, so it moved to async.
# Precedent on the same event: context-advisor, learn-from-prompts.
#
# The risk this file exists to catch is drift: someone adds a `block` to an
# async hook later, and the guard silently stops guarding. That would not fail
# any behavioural test — the hook still "works" when run directly.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Async Safety Tests ==="

begin_test "prompt-validator is registered async"
grep -q 'prompt-validator.sh|async' "$REPO_DIR/lib/hooks.sh" && pass \
  || fail "not async — the 35ms is back on the prompt path"

begin_test "prompt-validator is async in the generated plugin hooks.json"
python3 -c "
import json, sys
d = json.load(open('$REPO_DIR/hooks/hooks.json'))
ok = any(h.get('async') for ms in d.get('hooks', {}).values() for m in ms
         for h in m.get('hooks', []) if 'prompt-validator' in h.get('command', ''))
sys.exit(0 if ok else 1)" && pass || fail "hooks.json is generated — run tools/gen-plugin-hooks.sh"

# --- the invariant that makes async correct ---------------------------------
begin_test "prompt-validator cannot block (no exit 2, no deny/ask)"
S=$(cat "$REPO_DIR/hooks/prompt-validator.sh")
printf '%s' "$S" | grep -qE '\bexit 2\b' && fail "async hook can exit 2 — the block would arrive too late" || \
{ printf '%s' "$S" | grep -qE "permissionDecision" && fail "async hook emits a permission decision" || pass; }

begin_test "prompt-validator does not inject context (nothing downstream waits)"
printf '%s' "$S" | grep -qE 'additionalContext|hookSpecificOutput' \
  && fail "async hook injects context — it would be dropped or arrive after the prompt" || pass

begin_test "it still emits its advisory notes on stderr"
OUT=$(printf '%s' "$(V='fix all the things' python3 -c '
import json, os
print(json.dumps({"prompt": os.environ["V"]}))')" \
  | bash "$REPO_DIR/hooks/prompt-validator.sh" 2>&1 >/dev/null)
printf '%s' "$OUT" | grep -q 'Supercharger' && pass || fail "advisory notes lost: $OUT"

begin_test "and it still exits 0 on a prompt with no anti-pattern"
printf '{"prompt":"yes"}' | bash "$REPO_DIR/hooks/prompt-validator.sh" >/dev/null 2>&1
[ $? -eq 0 ] && pass || fail "non-zero exit from an async hook"

# --- every OTHER async-only hook must satisfy the same invariant ------------
# Checked across the board, not just for the hook that prompted this file: an
# async hook that can block is a guard that silently does not guard.
#
# Scoped to hooks that are async in EVERY registration. Two exclusions, both
# legitimate and both false positives in the first draft of this check:
#   * dual-registered hooks — budget-cap and mcp-circuit-breaker run async on
#     PostToolUse AND sync on PreToolUse. The blocking code belongs to the sync
#     registration; flagging the file conflates the two.
#   * asyncRewake — a distinct contract (act late, then wake the model), so an
#     exit 2 there is the mechanism working, not a hole.
begin_test "no async-ONLY hook can block"
BAD=$(python3 -c "
import json, os, re, collections
d = json.load(open('$REPO_DIR/hooks/hooks.json'))
mode = collections.defaultdict(set)
for ev, ms in d.get('hooks', {}).items():
    for m in ms:
        for h in m.get('hooks', []):
            n = os.path.basename(h.get('command', '').replace(' #supercharger', '').split()[0])
            mode[n].add('asyncRewake' if h.get('asyncRewake')
                        else 'async' if h.get('async') else 'sync')
bad = []
for n, modes in mode.items():
    if modes != {'async'}:
        continue
    p = os.path.join('$REPO_DIR', 'hooks', n)
    if not os.path.isfile(p):
        continue
    s = open(p).read()
    if re.search(r'^\s*exit 2\b', s, re.M) or 'permissionDecision' in s:
        bad.append(n)
print(' '.join(sorted(bad)))")
[ -z "$BAD" ] && pass || fail "async-only hooks that can block: $BAD"

report
