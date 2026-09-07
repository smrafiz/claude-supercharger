#!/usr/bin/env bash
# v2.23.45 statusline render cache: a repeat render within the same wall-clock
# second is served from cache (skips the python fork) and must be byte-identical.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SL="$REPO_DIR/hooks/statusline.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Statusline Render Cache Tests ==="

ST=$(mktemp -d); mkdir -p "$ST/scope"
SID="slcache-test"; CACHE="$ST/scope/.statusline-cache-$SID"
# json.dumps shape (space after the colon) — the parser must tolerate it
PAY=$(python3 -c 'import json,sys;print(json.dumps({"model":{"display_name":"Opus 5"},"cwd":sys.argv[1],"session_id":"slcache-test","transcript_path":"/dev/null","workspace":{"current_dir":sys.argv[1]}}))' "$REPO_DIR")
_render() { printf '%s' "${1:-$PAY}" | SUPERCHARGER_STATE="$ST" bash "$SL" 2>/dev/null; }

begin_test "cold render produces output and writes the cache"
rm -f "$CACHE"
COLD=$(_render)
{ [ -n "$COLD" ] && [ -f "$CACHE" ]; } && pass || fail "no output or no cache file"

begin_test "cached render is byte-identical to the cold one"
WARM=$(_render)
[ "$WARM" = "$COLD" ] && pass || fail "cached output differs from cold"

begin_test "cache key includes cwd — a different cwd is not served the stale line"
PAY2=$(python3 -c 'import json;print(json.dumps({"model":{"display_name":"Opus 5"},"cwd":"/tmp","session_id":"slcache-test","transcript_path":"/dev/null","workspace":{"current_dir":"/tmp"}}))')
OTHER=$(_render "$PAY2")
[ "$OTHER" != "$COLD" ] && pass || fail "served another cwd's cached line"

begin_test "entry expires — a later second re-renders"
_render >/dev/null; S1=$(head -1 "$CACHE" 2>/dev/null)
sleep 1.2
_render >/dev/null; S2=$(head -1 "$CACHE" 2>/dev/null)
{ [ -n "$S1" ] && [ "$S1" != "$S2" ]; } && pass || fail "stamp did not advance ($S1 -> $S2)"

begin_test "session id with unsafe characters disables the cache (no path escape)"
BADPAY=$(python3 -c 'import json;print(json.dumps({"model":{"display_name":"x"},"cwd":"/tmp","session_id":"../../evil","transcript_path":"/dev/null"}))')
_render "$BADPAY" >/dev/null 2>&1
ls "$ST/scope/".statusline-cache-*evil* >/dev/null 2>&1 && fail "wrote a cache file for an unsafe session id" || pass

begin_test "still renders nothing when /sc off"
DIS=".supercharger-""disabled"; printf 'x\n' > "$ST/scope/$DIS"
OFF=$(_render)
rm -f "$ST/scope/$DIS"
[ -z "$OFF" ] && pass || fail "rendered output while disabled"

rm -rf "$ST"

# --- v4.0.36: the update indicator --------------------------------------------
# A persistent counterpart to the SessionStart notice, which is seen once and
# scrolls away. Claude Code surfaces its own updates the same way.
#
# The statusline reads a FLAG and never compares versions: it renders on every
# turn, and a colleague has already uninstalled once over perceived slowness
# ([[perf-hook-overhead]]). update-check.sh writes the flag at SessionStart,
# install.sh clears it on a successful update.
#
# NOTE THE DISTINCT session_ids BELOW. The statusline caches per session per
# second, so re-running with the same id returns the CACHED line and the second
# assertion passes no matter what the flag says. That is exactly how the first
# version of this test "passed" with the flag removed.
# [[measurement-fixture-defects]]
_SLU_H=$(mktemp -d); mkdir -p "$_SLU_H/.claude/supercharger/scope"
_slu_line() {  # $1 = session id
  printf '{"session_id":"%s","cwd":"%s","workspace":{"current_dir":"%s"},"model":{"display_name":"Opus 5"}}' \
    "$1" "$REPO_DIR" "$REPO_DIR" \
    | HOME="$_SLU_H" SUPERCHARGER_HOME="$REPO_DIR" SUPERCHARGER_STATE="$_SLU_H/.claude/supercharger" \
      bash "$REPO_DIR/hooks/statusline.sh" 2>/dev/null | head -1 | sed 's/\x1b\[[0-9;]*m//g'
}

begin_test "statusline shows the update indicator when the flag is set"
printf '9.9.9\n' > "$_SLU_H/.claude/supercharger/scope/.update-available"
case "$(_slu_line slu-a)" in
  *"⬆ v9.9.9 (run /sc-update)"*) pass ;;
  *) fail "no indicator: $(_slu_line slu-a2)" ;;
esac

begin_test "and hides it when the flag is gone (fresh cache key)"
rm -f "$_SLU_H/.claude/supercharger/scope/.update-available"
case "$(_slu_line slu-b)" in
  *"⬆"*) fail "indicator persisted with no flag" ;;
  *) pass ;;
esac
rm -rf "$_SLU_H"

begin_test "update-check writes the flag when newer and clears it when current"
_SLU_T=$(mktemp -d); mkdir -p "$_SLU_T/s/scope"
printf '4.0.35\n' > "$_SLU_T/s/.version"; printf '4.0.36\n' > "$_SLU_T/s/.update-cache"
SUPERCHARGER_STATE="$_SLU_T/s" SUPERCHARGER_HOME="$REPO_DIR" bash "$REPO_DIR/hooks/update-check.sh" >/dev/null 2>&1
_SLU_SET=$(cat "$_SLU_T/s/scope/.update-available" 2>/dev/null)
printf '4.0.35\n' > "$_SLU_T/s/.update-cache"
SUPERCHARGER_STATE="$_SLU_T/s" SUPERCHARGER_HOME="$REPO_DIR" bash "$REPO_DIR/hooks/update-check.sh" >/dev/null 2>&1
_SLU_CLR=$(cat "$_SLU_T/s/scope/.update-available" 2>/dev/null)
rm -rf "$_SLU_T"
[ "$_SLU_SET" = "4.0.36" ] && [ -z "$_SLU_CLR" ] && pass \
  || fail "set='$_SLU_SET' (want 4.0.36), cleared='$_SLU_CLR' (want empty)"

begin_test "install.sh clears the flag, so it goes the moment you update"
grep -q 'rm -f "\$HOME/.claude/supercharger/scope/.update-available"' "$REPO_DIR/install.sh" \
  && pass || fail "install.sh leaves a stale indicator up until the next session"

report
