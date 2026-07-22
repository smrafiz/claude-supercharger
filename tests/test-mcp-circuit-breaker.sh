#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/mcp-circuit-breaker.sh"

echo "=== mcp-circuit-breaker Tests ==="
export SUPERCHARGER_NO_DEDUP=1

# PostToolUse: feed a tool_response (records health). Isolated HOME.
_post() { # <home> <tool> <response-json>
  printf '{"hook_event_name":"PostToolUse","tool_name":"%s","tool_response":%s}' "$2" "$3" \
    | HOME="$1" bash "$HOOK" 2>/dev/null
}
# PreToolUse: no tool_response (checks/blocks). Echoes stdout.
_pre() { # <home> <tool>
  printf '{"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{}}' "$2" \
    | HOME="$1" bash "$HOOK" 2>/dev/null
}

begin_test "mcp-breaker: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "mcp-breaker: healthy server call is allowed (no cooldown)"
H=$(mktemp -d)
OUT=$(_pre "$H" "mcp__github__create_issue")
[ -z "$OUT" ] && pass || fail "expected allow with no health file, got: $OUT"
rm -rf "$H"

begin_test "mcp-breaker: 429 response trips breaker → next call blocked"
H=$(mktemp -d)
_post "$H" "mcp__github__create_issue" '{"isError":true,"content":"HTTP 429 Too Many Requests"}' >/dev/null
OUT=$(_pre "$H" "mcp__github__create_issue")
echo "$OUT" | grep -q 'permissionDecision.*deny' && echo "$OUT" | grep -qi 'MCP-BREAKER' \
  && pass || fail "expected block after 429, got: $OUT"
rm -rf "$H"

begin_test "mcp-breaker: 503 unavailable also trips breaker"
H=$(mktemp -d)
_post "$H" "mcp__context7__query" '{"content":"503 Service Unavailable"}' >/dev/null
OUT=$(_pre "$H" "mcp__context7__query")
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected block after 503, got: $OUT"
rm -rf "$H"

begin_test "mcp-breaker: a DIFFERENT server stays healthy (per-server)"
H=$(mktemp -d)
_post "$H" "mcp__github__x" '{"content":"429 rate limit"}' >/dev/null
OUT=$(_pre "$H" "mcp__context7__query")
[ -z "$OUT" ] && pass || fail "expected other server unaffected, got: $OUT"
rm -rf "$H"

begin_test "mcp-breaker: clean success resets a tripped breaker"
H=$(mktemp -d)
_post "$H" "mcp__github__x" '{"content":"429 rate limit"}' >/dev/null
_post "$H" "mcp__github__x" '{"content":"ok, issue #12 created"}' >/dev/null
OUT=$(_pre "$H" "mcp__github__x")
[ -z "$OUT" ] && pass || fail "expected reset after success, got: $OUT"
rm -rf "$H"

begin_test "mcp-breaker: cooldown expires → call allowed again (TTL)"
H=$(mktemp -d)
_post "$H" "mcp__github__x" '{"content":"429"}' >/dev/null   # base cooldown via env below
# Re-trip with 1s cooldown, wait it out
printf '{"hook_event_name":"PostToolUse","tool_name":"mcp__slow__op","tool_response":{"content":"503"}}' \
  | HOME="$H" SUPERCHARGER_MCP_COOLDOWN=1 bash "$HOOK" >/dev/null 2>&1
sleep 2
OUT=$(_pre "$H" "mcp__slow__op")
[ -z "$OUT" ] && pass || fail "expected allow after cooldown, got: $OUT"
rm -rf "$H"

begin_test "mcp-breaker: non-mcp tool is ignored"
H=$(mktemp -d)
OUT=$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' | HOME="$H" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected non-mcp ignored, got: $OUT"
rm -rf "$H"

begin_test "mcp-breaker: disabled via SUPERCHARGER_MCP_BREAKER=0"
H=$(mktemp -d)
_post "$H" "mcp__github__x" '{"content":"429"}' >/dev/null
OUT=$(printf '{"hook_event_name":"PreToolUse","tool_name":"mcp__github__x","tool_input":{}}' \
  | HOME="$H" SUPERCHARGER_MCP_BREAKER=0 bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected no block when disabled, got: $OUT"
rm -rf "$H"

begin_test "mcp-breaker: successful call with no error markers doesn't trip"
H=$(mktemp -d)
_post "$H" "mcp__github__x" '{"content":"issue created successfully"}' >/dev/null
OUT=$(_pre "$H" "mcp__github__x")
[ -z "$OUT" ] && pass || fail "expected clean success not to trip, got: $OUT"
rm -rf "$H"

begin_test "mcp-breaker: fail-open on malformed JSON"
H=$(mktemp -d)
OUT=$(printf 'not json' | HOME="$H" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected fail-open, got: $OUT"
rm -rf "$H"

# ---- 2.21.15: breaker is per-session (server health keyed by session id) ----
_post_sid() { # <home> <tool> <response-json> <sid>
  printf '{"hook_event_name":"PostToolUse","tool_name":"%s","session_id":"%s","tool_response":%s}' "$2" "$4" "$3" \
    | HOME="$1" bash "$HOOK" 2>/dev/null
}
_pre_sid() { # <home> <tool> <sid>
  printf '{"hook_event_name":"PreToolUse","tool_name":"%s","session_id":"%s","tool_input":{}}' "$2" "$3" \
    | HOME="$1" bash "$HOOK" 2>/dev/null
}

begin_test "mcp-breaker: per-session — session B not blocked by session A's 429"
H=$(mktemp -d)
_post_sid "$H" "mcp__github__create_issue" '{"isError":true,"content":"HTTP 429 Too Many Requests"}' "sessA" >/dev/null
OUTA=$(_pre_sid "$H" "mcp__github__create_issue" "sessA")
OUTB=$(_pre_sid "$H" "mcp__github__create_issue" "sessB")
if echo "$OUTA" | grep -q 'deny' && [ -z "$OUTB" ]; then pass
else fail "expected session A blocked, session B allowed. A=[$OUTA] B=[$OUTB]"; fi
rm -rf "$H"

report
