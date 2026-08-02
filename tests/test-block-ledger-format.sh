#!/usr/bin/env bash
# Block-ledger line integrity (v2.26.17)
#
# scope/.blocked-commands is LINE-BASED: /why reads the last N lines, and
# learn-from-blocks parses it into the [BLOCKS] summary injected into every session's
# context. All three writers embedded the raw command, so a MULTI-LINE blocked command
# wrote a multi-line entry — a fragment such as `rm -rf .` became its own row and read
# as a real destructive block. Three corrupted rows were found in the live ledger.
#
# Shortening to 120 chars does not help: the newline sits inside the first 120 bytes.
# The collapse has to happen first, which is what these tests pin.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# A command whose dangerous part is on a LATER line — the shape that corrupted rows.
MULTILINE='echo "step one"
rm -rf /
echo "step three"'

run_hook() { # hook, command -> writes into an isolated state dir, echoes that dir
  local hook="$1" cmd="$2" st
  st=$(mktemp -d); mkdir -p "$st/scope"
  printf '%s' "$(CMD="$cmd" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))')" \
    | env SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/$hook" >/dev/null 2>&1
  printf '%s' "$st"
}

# Every line in the ledger must be a complete entry: `[timestamp] reason — command`.
all_lines_well_formed() {
  local f="$1"
  [ -s "$f" ] || return 1
  ! grep -qvE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}' "$f"
}

echo "=== Block Ledger Format Tests ==="

begin_test "safety.sh: a multi-line command writes ONE well-formed row"
ST=$(run_hook safety.sh "$MULTILINE")
LED="$ST/scope/.blocked-commands"
if [ -s "$LED" ] && all_lines_well_formed "$LED"; then
  [ "$(wc -l < "$LED" | tr -d ' ')" -eq 1 ] && pass || fail "expected 1 row, got $(wc -l < "$LED" | tr -d ' ')"
else
  fail "ledger empty or contains a fragment row: $(head -3 "$LED" 2>/dev/null)"
fi
rm -rf "$ST"

begin_test "safety.sh: the entry keeps the dangerous text (collapsed, not truncated away)"
ST=$(run_hook safety.sh "$MULTILINE")
LED="$ST/scope/.blocked-commands"
grep -q 'rm -rf /' "$LED" 2>/dev/null && pass || fail "collapsing lost the command: $(cat "$LED" 2>/dev/null)"
rm -rf "$ST"

begin_test "harness-tamper-guard: a multi-line teardown writes ONE well-formed row"
ST=$(run_hook harness-tamper-guard.sh 'echo one
rm -rf ~/.claude/supercharger/hooks
echo three')
LED="$ST/scope/.blocked-commands"
if [ -s "$LED" ] && all_lines_well_formed "$LED"; then
  [ "$(wc -l < "$LED" | tr -d ' ')" -eq 1 ] && pass || fail "expected 1 row, got $(wc -l < "$LED" | tr -d ' ')"
else
  fail "ledger empty or fragmented: $(head -3 "$LED" 2>/dev/null)"
fi
rm -rf "$ST"

begin_test 'no row is a bare fragment (the rm-dash-rf-dot symptom)'
ST=$(run_hook safety.sh "$MULTILINE")
LED="$ST/scope/.blocked-commands"
grep -qxE '\s*(rm -rf \.|echo .*)' "$LED" 2>/dev/null && fail "a fragment row was written" || pass
rm -rf "$ST"

begin_test "single-line commands are unaffected"
ST=$(run_hook safety.sh 'rm -rf /')
LED="$ST/scope/.blocked-commands"
if [ -s "$LED" ] && all_lines_well_formed "$LED" && [ "$(wc -l < "$LED" | tr -d ' ')" -eq 1 ]; then
  pass
else
  fail "single-line case regressed: $(cat "$LED" 2>/dev/null)"
fi
rm -rf "$ST"

begin_test "tabs are collapsed too (they break column parsing downstream)"
# Tab-indented second line: blockable AND carries a real tab.
ST=$(run_hook safety.sh "$(printf 'echo one\n\trm -rf /')")
LED="$ST/scope/.blocked-commands"
if [ -s "$LED" ]; then
  if LC_ALL=C grep -q "$(printf '\t')" "$LED" 2>/dev/null; then
    fail "a tab survived into the ledger"
  else
    pass
  fi
else
  fail "nothing logged"
fi
rm -rf "$ST"

report
