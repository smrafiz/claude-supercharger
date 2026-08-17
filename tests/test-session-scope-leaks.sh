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

# ---- v2.27.30: the same leak through a SPACED payload -----------------------
# Three hooks extracted the session id with the literal `"session_id":"`, which
# only matches COMPACT JSON. Claude Code emits compact today, so none of this is
# firing in production — but the failure mode is silent and each hook fails
# differently, so it is pinned by behaviour rather than left to a serialiser
# never changing. budget-cap was already correct (it falls back to jq); the
# other two were not.
SPACED='{"session_id": "sessS", "cwd": "/tmp", "tool_name": "Bash", "tool_input": {"command": "ls"}, "context_window": {"used_percentage": 85}, "prompt": "hi"}'

# context-advisor was the worst: the strip matched nothing, returned the WHOLE
# payload, and `%%\"*` cut it to a bare `{` — so every session shared
# .ctx-advisor-peak-{ regardless of who was running.
begin_test "context-advisor: a spaced payload still scopes the peak file per session"
D=$(new_state)
SUPERCHARGER_STATE="$D" bash "$REPO_DIR/hooks/context-advisor.sh" >/dev/null 2>&1 <<<"$SPACED"
if [ -f "$D/scope/.ctx-advisor-peak-sessS" ]; then pass
else fail "peak file: $(find "$D/scope" -name '.ctx-advisor-peak-*' -exec basename {} \; | tr '\n' ' ')"; fi
rm -rf "$D"

# session-checkpoint failed open instead: the debounce was skipped entirely and
# the hook ran 4 git subprocesses plus a python fork on EVERY call.
begin_test "session-checkpoint: a spaced payload still writes the debounce marker"
D=$(new_state)
SUPERCHARGER_STATE="$D" bash "$REPO_DIR/hooks/session-checkpoint.sh" >/dev/null 2>&1 <<<"$SPACED"
if [ -f "$D/scope/.checkpoint-walk-sessS" ]; then pass
else fail "marker: $(find "$D/scope" -name '.checkpoint-walk-*' -exec basename {} \; | tr '\n' ' ')"; fi
rm -rf "$D"

begin_test "session-checkpoint: the debounce then suppresses the git walk on a spaced payload"
D=$(new_state)
SHIM=$(mktemp -d); GLOG="$SHIM/g"
printf '#!/bin/bash\necho git >> "%s"\nexec %s "$@"\n' "$GLOG" "$(command -v git)" > "$SHIM/git"
chmod +x "$SHIM/git"
SUPERCHARGER_STATE="$D" bash "$REPO_DIR/hooks/session-checkpoint.sh" >/dev/null 2>&1 <<<"$SPACED"
: > "$GLOG"
PATH="$SHIM:$PATH" SUPERCHARGER_STATE="$D" bash "$REPO_DIR/hooks/session-checkpoint.sh" >/dev/null 2>&1 <<<"$SPACED"
GF=$(grep -c git "$GLOG" 2>/dev/null | tr -d ' '); GF=${GF:-0}
[ "$GF" -eq 0 ] && pass || fail "debounced call still forked git $GF time(s)"
rm -rf "$D" "$SHIM"

begin_test "budget-cap: spaced payload scoping (the sibling that was already right)"
D=$(new_state)
SUPERCHARGER_STATE="$D" bash "$REPO_DIR/hooks/budget-cap.sh" >/dev/null 2>&1 <<<"$SPACED"
if [ ! -f "$D/scope/.main-tokens-" ] && [ ! -f "$D/scope/.main-tokens-{" ]; then pass
else fail "budget-cap wrote a garbage-scoped token file"; fi
rm -rf "$D"

report
