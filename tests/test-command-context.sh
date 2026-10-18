#!/usr/bin/env bash
# tools/command-context.py feeds /sc-status, /sc-why and /sc-perf through `!`.
# A non-zero exit there aborts the whole slash command with no reply, so the
# script must exit 0 on every input; and it must read THIS session, not the newest.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
CTX="$REPO_DIR/tools/command-context.py"
# Native Windows python cannot open MSYS paths: hand it the mixed form.
_n() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
ctx() { HOME="$(_n "$HOME")" python3 "$(_n "$CTX")" "$@"; }

begin_test "command-context: every mode (and a bad one) exits 0 on an empty install"
setup_test_home
RCS=""
for m in status why perf bogus ""; do ctx $m >/dev/null 2>&1; RCS="$RCS$?"; done
[ "$RCS" = "00000" ] && pass || fail "exit codes: $RCS"
teardown_test_home

begin_test "command-context: why says so when nothing has fired"
setup_test_home
OUT=$(ctx why 2>&1)
[ "$OUT" = "No recent hook activity recorded." ] && pass || fail "got: $OUT"
teardown_test_home

begin_test "command-context: status uses CLAUDE_CODE_SESSION_ID, not the newest transcript"
setup_test_home
P="$HOME/proj"; mkdir -p "$P"; P=$(cd "$P" && pwd -P)
ENC=$(cd "$P" && python3 -c "import os,re; print(re.sub(r'[^A-Za-z0-9-]', '-', os.getcwd()))")
D="$HOME/.claude/projects/$ENC"; mkdir -p "$D" "$HOME/.claude/supercharger/scope"
printf '{"type":"assistant","message":{"model":"claude-sonnet","usage":{"output_tokens":1000000}}}\n' > "$D/mine.jsonl"
sleep 1; : > "$D/other-newer.jsonl"
printf '{"success": false}\n{"success": true}\n' > "$HOME/.claude/supercharger/scope/.tool-history-mine"
OUT=$(cd "$P" && CLAUDE_CODE_SESSION_ID=mine ctx status 2>&1)
{ printf '%s' "$OUT" | grep -q '^session_id: mine$' \
  && printf '%s' "$OUT" | grep -q '^session_cost: \$15.00' \
  && printf '%s' "$OUT" | grep -q '^tools_last10: 1 ok / 1 fail$'; } && pass || fail "got: $OUT"
teardown_test_home

begin_test "command-context: session_cost prices a response written as several lines once"
setup_test_home
P="$HOME/proj"; mkdir -p "$P"; P=$(cd "$P" && pwd -P)
ENC=$(cd "$P" && python3 -c "import os,re; print(re.sub(r'[^A-Za-z0-9-]', '-', os.getcwd()))")
D="$HOME/.claude/projects/$ENC"; mkdir -p "$D" "$HOME/.claude/supercharger/scope"
L='{"type":"assistant","message":{"id":"m1","model":"claude-sonnet","usage":{"output_tokens":1000000}}}'
printf '%s\n%s\n%s\n' "$L" "$L" "$L" > "$D/mine.jsonl"
OUT=$(cd "$P" && CLAUDE_CODE_SESSION_ID=mine ctx status 2>&1)
printf '%s' "$OUT" | grep -q '^session_cost: \$15.00' && pass || fail "got: $(printf '%s' "$OUT" | grep session_cost)"
teardown_test_home

begin_test "command-context: the three commands inject it and allow exactly that call"
OK=1
for c in sc-status sc-why sc-perf; do
  f="$REPO_DIR/configs/commands/$c.md"
  grep -q '^allowed-tools: Bash(python3 ~/.claude/supercharger/tools/command-context.py:\*)$' "$f" || OK=0
  grep -q '!`python3 ~/.claude/supercharger/tools/command-context.py [a-z]*`' "$f" || OK=0
  grep -q '!`[^`]*\$ARGUMENTS' "$f" && OK=0   # arguments never reach a ! shell line
done
[ "$OK" = 1 ] && pass || fail "a command lost its injection, allow rule, or put \$ARGUMENTS in a ! line"

begin_test "command-context: a plugin install reads its state from CLAUDE_PLUGIN_DATA"
PD=$(mktemp -d); mkdir -p "$PD/scope"; printf 'lean\n' > "$PD/scope/.economy-tier"
OUT=$(cd "$PD" && HOME="$(_n "$(mktemp -d)")" CLAUDE_PLUGIN_DATA="$(_n "$PD")" python3 "$(_n "$CTX")" status 2>&1)
printf '%s' "$OUT" | grep -q '^tier: lean' && pass || fail "plugin state ignored: $(printf '%s' "$OUT" | grep tier:)"
rm -rf "$PD"

report
