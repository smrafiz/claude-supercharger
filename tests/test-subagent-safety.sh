#!/usr/bin/env bash
# Suite for subagent-safety.sh (v2.21.7).
# Every SubagentStart must receive the FULL mandatory rules. Previously a
# session-scoped flag meant only the FIRST subagent per session got the rules;
# siblings got a dangling "already in scope" reference to a context they never
# saw, and ran unguarded. Each subagent is an independent context.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/subagent-safety.sh"

D=$(mktemp -d); mkdir -p "$D/scope"
J='{"session_id":"s1","agent_type":"general-purpose"}'

run() { SUPERCHARGER_STATE="$D" bash "$H" 2>/dev/null <<<"$J"; }

begin_test "subagent-safety: first spawn injects full mandatory rules"
run | grep -q "mandatory rules" && pass || fail "first spawn missing rules"

begin_test "subagent-safety: SECOND spawn (same session) STILL injects full rules"
run | grep -q "mandatory rules" && pass || fail "second spawn got a dangling reference, not the rules"

begin_test "subagent-safety: second spawn does not emit 'already in scope' stub"
run | grep -q "already in scope" && fail "second spawn emitted the removed dedup stub" || pass

begin_test "subagent-safety: no per-session injected-flag file is created"
run >/dev/null
ls "$D/scope"/.subagent-safety-injected-* >/dev/null 2>&1 && fail "stale injected-flag still written" || pass

rm -rf "$D"
report
