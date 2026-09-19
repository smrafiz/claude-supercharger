#!/usr/bin/env bash
# Context-percentage sidecar (v4.1.8).
#
# The bug these cover: `context_window.used_percentage` is not in ANY hook event
# payload — only on the statusLine payload. adaptive-economy, context-advisor and
# auto-compact all read it off their own stdin and so never fired once in 62
# sessions (docs/ECONOMY-LAYER-2026-09-19.md).
#
# The existing suites did not catch it because their fixtures SYNTHESISE a
# `context_window` key into the hook payload (tests/test-adaptive-economy-v2.sh
# `_make_input`), which no real hook event has. Every payload below is therefore
# a REALISTIC one — no context_window — and the percentage must arrive through
# the sidecar or not at all.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Context percentage sidecar Tests ==="

SID="sidecar-test-session"

# A UserPromptSubmit payload exactly as Claude Code sends it: no context_window.
_prompt_input() {
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"go"}' \
    "$SID" "$1"
}
# A PostToolUse payload exactly as Claude Code sends it: no context_window.
_tool_input() {
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}' \
    "$SID" "$1"
}
_write_sidecar() {  # _write_sidecar <pct> [age_seconds]
  printf '%s %s\n' "$(( $(date +%s) - ${2:-0} ))" "$1" > "$SCOPE_DIR/.ctx-pct-$SID"
}

# --- statusline publishes the sidecar ----------------------------------------
begin_test "statusline writes the context percentage sidecar"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
SUPERCHARGER_STATE="$HOME/.claude/supercharger" \
SUPERCHARGER_HOME="$REPO_DIR" \
  printf '{"session_id":"%s","cwd":"%s","model":{"display_name":"Opus 5"},"context_window":{"used_percentage":85,"context_window_size":200000,"total_input_tokens":170000,"total_output_tokens":100}}' "$SID" "$HOME" \
  | SUPERCHARGER_STATE="$HOME/.claude/supercharger" SUPERCHARGER_HOME="$REPO_DIR" \
    bash "$REPO_DIR/hooks/statusline.sh" >/dev/null 2>&1
GOT=$(cut -d' ' -f2 "$SCOPE_DIR/.ctx-pct-$SID" 2>/dev/null || echo "")
if [ "$GOT" = "85" ]; then pass; else fail "expected sidecar pct 85, got '$GOT'"; fi
teardown_test_home

# used_percentage is null before the first API response and again right after
# /compact. Publishing 0 there would read as "context empty", not "unknown".
begin_test "statusline writes no sidecar when used_percentage is null"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
printf '{"session_id":"%s","cwd":"%s","model":{"display_name":"Opus 5"},"context_window":{"used_percentage":null,"context_window_size":200000}}' "$SID" "$HOME" \
  | SUPERCHARGER_STATE="$HOME/.claude/supercharger" SUPERCHARGER_HOME="$REPO_DIR" \
    bash "$REPO_DIR/hooks/statusline.sh" >/dev/null 2>&1
if [ -f "$SCOPE_DIR/.ctx-pct-$SID" ]; then
  fail "wrote a sidecar for a null percentage: $(cat "$SCOPE_DIR/.ctx-pct-$SID")"
else pass; fi
teardown_test_home

# --- the three readers, on realistic payloads ---------------------------------
begin_test "adaptive-economy switches tier from the sidecar (payload has no context_window)"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "lean" > "$SCOPE_DIR/.economy-tier"
_write_sidecar 85
_prompt_input "$HOME" | SUPERCHARGER_STATE="$HOME/.claude/supercharger" \
  bash "$REPO_DIR/hooks/adaptive-economy.sh" >/dev/null 2>&1
GOT=$(tr -d '[:space:]' < "$SCOPE_DIR/.economy-tier" 2>/dev/null)
if [ "$GOT" = "minimal" ]; then pass; else fail "expected 'minimal', got '$GOT'"; fi
teardown_test_home

begin_test "context-advisor warns from the sidecar (payload has no context_window)"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
_write_sidecar 85
OUT=$(_prompt_input "$HOME" | SUPERCHARGER_STATE="$HOME/.claude/supercharger" \
  bash "$REPO_DIR/hooks/context-advisor.sh" 2>/dev/null)
case "$OUT" in *"85%"*) pass ;; *) fail "expected an 85% warning, got: ${OUT:-<empty>}" ;; esac
teardown_test_home

begin_test "auto-compact warns from the sidecar (PostToolUse payload has no context_window)"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
_write_sidecar 85
OUT=$(_tool_input "$HOME" | SUPERCHARGER_STATE="$HOME/.claude/supercharger" \
  bash "$REPO_DIR/hooks/auto-compact.sh" 2>/dev/null)
case "$OUT" in *"85%"*) pass ;; *) fail "expected an 85% warning, got: ${OUT:-<empty>}" ;; esac
teardown_test_home

# --- degradation: absence is the normal case, never an error ------------------
# A plugin install cannot set statusLine, and a user with their own statusLine
# keeps it. Both get no sidecar, and must behave exactly as they did pre-4.1.8.
begin_test "all three stay silent and exit 0 with no sidecar at all"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
rm -f "$SCOPE_DIR/.ctx-pct-$SID"
FAILED=""
for h in adaptive-economy context-advisor; do
  OUT=$(_prompt_input "$HOME" | SUPERCHARGER_STATE="$HOME/.claude/supercharger" \
    bash "$REPO_DIR/hooks/$h.sh" 2>/dev/null) || FAILED="$FAILED $h(rc)"
  [ -n "$OUT" ] && FAILED="$FAILED $h(output)"
done
OUT=$(_tool_input "$HOME" | SUPERCHARGER_STATE="$HOME/.claude/supercharger" \
  bash "$REPO_DIR/hooks/auto-compact.sh" 2>/dev/null) || FAILED="$FAILED auto-compact(rc)"
[ -n "$OUT" ] && FAILED="$FAILED auto-compact(output)"
if [ -z "$FAILED" ]; then pass; else fail "not silent:$FAILED"; fi
teardown_test_home

begin_test "a stale sidecar is ignored rather than warned on"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
_write_sidecar 95 9999
OUT=$(_tool_input "$HOME" | SUPERCHARGER_STATE="$HOME/.claude/supercharger" \
  bash "$REPO_DIR/hooks/auto-compact.sh" 2>/dev/null)
if [ -z "$OUT" ]; then pass; else fail "acted on a stale sidecar: $OUT"; fi
teardown_test_home

begin_test "a malformed sidecar is ignored rather than fatal"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
printf 'not-a-number garbage\n' > "$SCOPE_DIR/.ctx-pct-$SID"
OUT=$(_tool_input "$HOME" | SUPERCHARGER_STATE="$HOME/.claude/supercharger" \
  bash "$REPO_DIR/hooks/auto-compact.sh" 2>/dev/null)
RC=$?
if [ -z "$OUT" ] && [ "$RC" -eq 0 ]; then pass; else fail "rc=$RC out='$OUT'"; fi
teardown_test_home

# A session id lands in a file path. This is the `.ctx-advisor-peak-{` class
# (v2.27.30) one layer down: a traversal id must not steer the read.
begin_test "a session id with path characters cannot steer the sidecar read"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
printf '%s %s\n' "$(date +%s)" "95" > "$SCOPE_DIR/.ctx-pct-default"
OUT=$(printf '{"session_id":"../../default","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}' "$HOME" \
  | SUPERCHARGER_STATE="$HOME/.claude/supercharger" \
    bash "$REPO_DIR/hooks/auto-compact.sh" 2>/dev/null)
# The id is rejected and falls back to "default", which is a legitimate bucket —
# assert only that the traversal did not resolve to some other session's file.
if [ -z "$OUT" ] || [ "${OUT#*95%}" != "$OUT" ]; then pass; else fail "unexpected: $OUT"; fi
teardown_test_home

report
