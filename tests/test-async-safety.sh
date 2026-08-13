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
d = json.load(open(sys.argv[1]))
ok = any(h.get('async') for ms in d.get('hooks', {}).values() for m in ms
         for h in m.get('hooks', []) if 'prompt-validator' in h.get('command', ''))
sys.exit(0 if ok else 1)" "$REPO_DIR/hooks/hooks.json" && pass || fail "hooks.json is generated — run tools/gen-plugin-hooks.sh"

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
import json, os, re, sys, collections
d = json.load(open(sys.argv[1]))
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
    p = os.path.join(sys.argv[2], 'hooks', n)
    if not os.path.isfile(p):
        continue
    s = open(p).read()
    if re.search(r'^\s*exit 2\b', s, re.M) or 'permissionDecision' in s:
        bad.append(n)
print(' '.join(sorted(bad)))" "$REPO_DIR/hooks/hooks.json" "$REPO_DIR")
[ -z "$BAD" ] && pass || fail "async-only hooks that can block: $BAD"

# --- a hook that REWRITES files must stay synchronous -------------------------
# typecheck went asyncRewake because it only reads (`tsc --noEmit`) and its whole
# output is findings — 150 runs at a 10.6s median was 37 minutes of blocking for
# information the model could just as well be woken with.
#
# quality-gate costs MORE in total (1423 runs, 53 min) and is deliberately NOT
# async, so this pins the reason before someone optimises the bigger number: it
# runs `eslint --fix`, `prettier --write`, `ruff format`. Async would let those
# writes land after the model moved on, racing its next edit against a rewrite of
# the same file. Cost is not the only axis.
begin_test "file-mutating PostToolUse hooks are not async"
BAD=$(python3 - "$REPO_DIR/hooks/hooks.json" "$REPO_DIR" <<'PYEOF'
import json, os, re, sys
d = json.load(open(sys.argv[1]))
repo = sys.argv[2]
# An in-place rewrite of the edited file, not merely writing state of its own.
MUTATES = re.compile(r'--fix\b|--write\b|\bruff format\b|\bgofmt -w\b|\brustfmt\b|\bblack -q\b')
bad = []
for ev, entries in (d.get('hooks') or {}).items():
    if not ev.startswith('PostToolUse'):
        continue
    for e in entries:
        for h in e.get('hooks', []):
            if not (h.get('async') or h.get('asyncRewake')):
                continue
            name = os.path.basename(h.get('command', '').replace(' #supercharger', '').split()[0])
            p = os.path.join(repo, 'hooks', name)
            try:
                src = open(p, errors='ignore').read()
            except Exception:
                continue
            if MUTATES.search(src):
                bad.append(name)
print(' '.join(sorted(set(bad))))
PYEOF
)
[ -z "$BAD" ] && pass || fail "async hook rewrites the edited file — its write can race the model's next edit: $BAD"

begin_test "typecheck is asyncRewake (read-only, so it must not block)"
python3 - "$REPO_DIR/hooks/hooks.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
ok = any(h.get('asyncRewake')
         for ev, es in (d.get('hooks') or {}).items() if ev.startswith('PostToolUse')
         for e in es for h in e.get('hooks', []) if 'typecheck.sh' in h.get('command', ''))
sys.exit(0 if ok else 1)
PYEOF
[ $? -eq 0 ] && pass || fail "typecheck is blocking again — 10.6s median on every edit"

report
