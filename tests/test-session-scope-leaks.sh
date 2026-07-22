#!/usr/bin/env bash
# Suite for the 2.21.12 session-scope-leak sweep.
# cache-health / auto-compact / repetition-detector wrote per-session state to
# GLOBAL filenames, so concurrent sessions mixed counters/windows/fingerprints
# → false "degraded"/loop warnings and lost debounce. State must be per-session.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

new_state() { local d; d=$(mktemp -d); mkdir -p "$d/scope"; echo "$d"; }

# ---- repetition-detector: .loop-history is session-scoped ----
begin_test "repetition-detector: writes .loop-history-<sid>, not the global name"
D=$(new_state)
J='{"session_id":"sessA","tool_name":"Bash","tool_input":{"command":"echo hi"},"cwd":"/tmp"}'
SUPERCHARGER_STATE="$D" bash "$REPO_DIR/hooks/repetition-detector.sh" >/dev/null 2>&1 <<<"$J"
if [ -f "$D/scope/.loop-history-sessA" ] && [ ! -f "$D/scope/.loop-history" ]; then pass
else fail "loop-history not session-scoped (global=$([ -f "$D/scope/.loop-history" ] && echo yes || echo no))"; fi
rm -rf "$D"

begin_test "repetition-detector: session B does not inherit session A's loop fingerprints"
D=$(new_state)
JA='{"session_id":"sessA","tool_name":"Bash","tool_input":{"command":"repcmd"},"cwd":"/tmp"}'
JB='{"session_id":"sessB","tool_name":"Bash","tool_input":{"command":"repcmd"},"cwd":"/tmp"}'
# session A repeats the same command 3x → would trip a loop in A's own history
for _ in 1 2 3; do SUPERCHARGER_STATE="$D" bash "$REPO_DIR/hooks/repetition-detector.sh" >/dev/null 2>&1 <<<"$JA"; done
# session B runs it once — must NOT see a loop (fresh history)
OUT=$(SUPERCHARGER_STATE="$D" bash "$REPO_DIR/hooks/repetition-detector.sh" 2>&1 <<<"$JB")
echo "$OUT" | grep -q 'LOOP' && fail "session B saw a loop from session A's history: $OUT" || pass
rm -rf "$D"

# ---- cache-health: counter is session-scoped ----
begin_test "cache-health: writes .cache-health-counter-<sid>, not the global name"
D=$(new_state)
J='{"session_id":"sessA","tool_name":"Bash","cwd":"/tmp","tool_response":{"usage":{"cache_read_input_tokens":10,"input_tokens":100}}}'
SUPERCHARGER_STATE="$D" bash "$REPO_DIR/hooks/cache-health.sh" >/dev/null 2>&1 <<<"$J"
if [ -f "$D/scope/.cache-health-counter-sessA" ] && [ ! -f "$D/scope/.cache-health-counter" ]; then pass
else fail "cache-health counter not session-scoped (global=$([ -f "$D/scope/.cache-health-counter" ] && echo yes || echo no))"; fi
rm -rf "$D"

# ---- auto-compact: band file is session-scoped ----
begin_test "auto-compact: writes .compact-last-band-<sid>, not the global name"
D=$(new_state)
# high context % so a band is written; auto-compact reads the % from the payload
J='{"session_id":"sessA","cwd":"/tmp","tool_response":{},"context":{"used_percent":85}}'
SUPERCHARGER_STATE="$D" bash "$REPO_DIR/hooks/auto-compact.sh" >/dev/null 2>&1 <<<"$J"
if [ ! -f "$D/scope/.compact-last-band" ]; then pass
else fail "auto-compact wrote the GLOBAL .compact-last-band"; fi
rm -rf "$D"

report
