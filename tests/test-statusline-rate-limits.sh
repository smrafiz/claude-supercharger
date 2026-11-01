#!/usr/bin/env bash
# Statusline rate limits: Session and Weekly render whenever Claude Code sends them.
# Weekly used to sit inside a `5h used > 0` check, so a fresh 5-hour window hid it.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SL="$REPO_DIR/hooks/statusline.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Statusline Rate Limit Tests ==="

# rate_limits JSON (or "none") -> line 3, colours stripped. A fresh state dir per render: no cache.
_line3() {
  local st; st=$(mktemp -d); mkdir -p "$st/scope"
  python3 -c 'import json,sys
d={"model":{"display_name":"Opus 5"},"cwd":"/tmp","session_id":"slrl-%d" % __import__("os").getpid(),"workspace":{"current_dir":"/tmp"}}
if sys.argv[1] != "none": d["rate_limits"]=json.loads(sys.argv[1])
print(json.dumps(d))' "$1" | SUPERCHARGER_STATE="$st" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | sed -n 3p
  rm -rf "$st"
}

begin_test "both windows used: Session and Weekly shown"
L=$(_line3 '{"five_hour":{"used_percentage":24},"seven_day":{"used_percentage":15}}')
case "$L" in *"Session: 24%"*"Weekly: 15%"*) pass ;; *) fail "got: $L" ;; esac

begin_test "fresh 5-hour window: Weekly still shown"
L=$(_line3 '{"five_hour":{"used_percentage":0},"seven_day":{"used_percentage":40}}')
case "$L" in *"Weekly: 40%"*) pass ;; *) fail "got: $L" ;; esac

begin_test "fresh 5-hour window: Session shows 0% rather than vanishing"
case "$L" in *"Session: 0%"*) pass ;; *) fail "got: $L" ;; esac

begin_test "only the weekly window sent: Weekly shown alone"
L=$(_line3 '{"seven_day":{"used_percentage":7}}')
case "$L" in *"Session"*) fail "Session invented: $L" ;; *"Weekly: 7%"*) pass ;; *) fail "got: $L" ;; esac

# Plans with weekly limits only: 88% must warn, not sit in dim grey.
begin_test "weekly at 88% is coloured red"
_st=$(mktemp -d); mkdir -p "$_st/scope"
RAW=$(printf '%s' '{"model":{"display_name":"Opus 5"},"cwd":"/tmp","session_id":"slrl-red","workspace":{"current_dir":"/tmp"},"rate_limits":{"seven_day":{"used_percentage":88}}}' \
  | SUPERCHARGER_STATE="$_st" bash "$SL" 2>/dev/null | sed -n 3p); rm -rf "$_st"
RED_ESC=$(printf '\033[31m')   # statusline.sh's RED
case "$RAW" in *"${RED_ESC}Weekly: 88%"*) pass ;; *) fail "not red: $(printf '%s' "$RAW" | cat -v)" ;; esac

begin_test "no rate_limits (API key, gateway): neither shown"
L=$(_line3 none)
case "$L" in *Session*|*Weekly*) fail "got: $L" ;; *) pass ;; esac

begin_test "used_percentage null (before the first response): neither shown"
L=$(_line3 '{"five_hour":{"used_percentage":null},"seven_day":{"used_percentage":null}}')
case "$L" in *Session*|*Weekly*) fail "got: $L" ;; *) pass ;; esac

report
