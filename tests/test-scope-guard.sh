#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SCOPE_GUARD="$REPO_DIR/hooks/scope-guard.sh"

# v2.6.77: snapshot + contract files are SID-suffixed. Tests pass
# session_id explicitly so the suffix is deterministic.

# Test 1: snapshot creates file
begin_test "scope-guard: snapshot creates .snapshot file"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
TMPDIR=$(mktemp -d)
cd "$TMPDIR" && git init -q && git commit --allow-empty -m "init" -q
echo '{"session_id":"s1"}' | bash "$SCOPE_GUARD" snapshot "$TMPDIR"
if [ -f "$HOME/.claude/supercharger/scope/.snapshot-s1" ]; then pass
else fail "snapshot file not created"; fi
rm -rf "$TMPDIR"; teardown_test_home

# Test 2: contract extracts single-file-scope
begin_test "scope-guard: contract detects single-file intent"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"session_id":"s2","prompt":"fix the typo in Header.tsx only"}' | bash "$SCOPE_GUARD" contract
CONTRACT=$(cat "$HOME/.claude/supercharger/scope/.contract-s2" 2>/dev/null || echo "")
if echo "$CONTRACT" | grep -q "single-file-scope"; then pass
else fail "single-file-scope not detected: $CONTRACT"; fi
teardown_test_home

# Test 3: contract extracts file path
begin_test "scope-guard: contract extracts file path"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"session_id":"s3","prompt":"update the login function in src/auth.py"}' | bash "$SCOPE_GUARD" contract
CONTRACT=$(cat "$HOME/.claude/supercharger/scope/.contract-s3" 2>/dev/null || echo "")
if echo "$CONTRACT" | grep -q "auth.py"; then pass
else fail "file path not extracted: $CONTRACT"; fi
teardown_test_home

# Test 4: clear removes the per-prompt contract but PRESERVES the snapshot
# baseline (v2.7.23 — snapshot is scope-guard's own check-mode baseline, no
# longer wiped every turn; only the contract is per-prompt scratch).
begin_test "scope-guard: clear removes contract, preserves snapshot baseline"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "scope:general" > "$HOME/.claude/supercharger/scope/.contract-s4"
echo "commit:abc" > "$HOME/.claude/supercharger/scope/.snapshot-s4"
echo '{"session_id":"s4"}' | bash "$SCOPE_GUARD" clear
if [ -f "$HOME/.claude/supercharger/scope/.snapshot-s4" ] && \
   [ ! -f "$HOME/.claude/supercharger/scope/.contract-s4" ]; then pass
else fail "expected snapshot kept + contract cleared (snap=$([ -f "$HOME/.claude/supercharger/scope/.snapshot-s4" ] && echo k || echo G) contract=$([ -f "$HOME/.claude/supercharger/scope/.contract-s4" ] && echo BUG || echo cleared))"; fi
teardown_test_home

# v2.7.22: clear must NOT wipe cumulative session telemetry (subagent costs) —
# it ran on every Stop, making the /sc-status + statusline subagent data vanish.
begin_test "scope-guard: clear preserves .subagent-costs (cumulative telemetry)"
setup_test_home
SD="$HOME/.claude/supercharger/scope"; mkdir -p "$SD"
echo '{"agent_id":"a1","agent_name":"general-purpose","cost_usd":0.42,"total_tokens":200000}' > "$SD/.subagent-costs-sc9.jsonl"
echo "x" > "$SD/.agent-classified-sc9"   # per-turn scratch that SHOULD clear
echo '{"session_id":"sc9","cwd":"/tmp"}' | bash "$SCOPE_GUARD" clear >/dev/null 2>&1
if [ -s "$SD/.subagent-costs-sc9.jsonl" ] && [ ! -f "$SD/.agent-classified-sc9" ]; then pass
else fail "clear wiped costs ($([ -f "$SD/.subagent-costs-sc9.jsonl" ] && echo kept || echo GONE)) or kept scratch"; fi
teardown_test_home

# v2.7.23: clear must also preserve the other cumulative/session-baseline files
# (snapshot = check-mode baseline, tool-history = confidence history, the
# once/session safety flag) while still clearing per-turn scratch.
begin_test "scope-guard: clear preserves snapshot/tool-history/safety-flag, clears scratch"
setup_test_home
SD="$HOME/.claude/supercharger/scope"; mkdir -p "$SD"
echo "base" > "$SD/.snapshot-sc23"
echo "hist" > "$SD/.tool-history-sc23"
echo "1"    > "$SD/.subagent-safety-injected-sc23"
echo "x"    > "$SD/.router-hash-sc23"   # per-turn scratch -> should clear
echo '{"session_id":"sc23","cwd":"/tmp"}' | bash "$SCOPE_GUARD" clear >/dev/null 2>&1
if [ -f "$SD/.snapshot-sc23" ] && [ -f "$SD/.tool-history-sc23" ] && \
   [ -f "$SD/.subagent-safety-injected-sc23" ] && [ ! -f "$SD/.router-hash-sc23" ]; then pass
else fail "clear wrongly wiped a cumulative file or kept scratch (snap=$([ -f "$SD/.snapshot-sc23" ] && echo k || echo G) hist=$([ -f "$SD/.tool-history-sc23" ] && echo k || echo G) flag=$([ -f "$SD/.subagent-safety-injected-sc23" ] && echo k || echo G) scratch=$([ -f "$SD/.router-hash-sc23" ] && echo BUG || echo cleared))"; fi
teardown_test_home

# Test 5: contract is idempotent (second call doesn't overwrite)
begin_test "scope-guard: contract not overwritten on second call"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"session_id":"s5","prompt":"fix Header.tsx only"}' | bash "$SCOPE_GUARD" contract
FIRST=$(cat "$HOME/.claude/supercharger/scope/.contract-s5")
echo '{"session_id":"s5","prompt":"rewrite everything"}' | bash "$SCOPE_GUARD" contract
SECOND=$(cat "$HOME/.claude/supercharger/scope/.contract-s5")
if [ "$FIRST" = "$SECOND" ]; then pass
else fail "contract was overwritten: first=$FIRST second=$SECOND"; fi
teardown_test_home

# Test 6 (NEW v2.6.77): two concurrent sessions don't corrupt each other
begin_test "scope-guard: concurrent sessions isolate snapshot/contract"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"session_id":"sA","prompt":"fix only auth.py"}' | bash "$SCOPE_GUARD" contract
echo '{"session_id":"sB","prompt":"rewrite the whole frontend"}' | bash "$SCOPE_GUARD" contract
A=$(cat "$HOME/.claude/supercharger/scope/.contract-sA" 2>/dev/null || echo "")
B=$(cat "$HOME/.claude/supercharger/scope/.contract-sB" 2>/dev/null || echo "")
if echo "$A" | grep -q "auth.py" && [ -n "$B" ] && [ "$A" != "$B" ]; then pass
else fail "concurrent sessions collided: A=$A B=$B"; fi
teardown_test_home

report
