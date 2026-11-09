#!/usr/bin/env bash
# Statusline context against modelSettings.<model>.autoCompactWindow (2026-11-09).
# A 1M model with autoCompactWindow 400000 compacted at 348K while the bar read 35%.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SL="$REPO_DIR/hooks/statusline.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Statusline autoCompactWindow ==="

# _render <user-settings-json|none> <project-local-json|none> [model id] -> line 2, colours stripped.
# 347,900 tokens used of a 1,000,000 window (CC reports 35%).
_render() {
  local t; t=$(mktemp -d); mkdir -p "$t/home/.claude" "$t/proj/.claude" "$t/st/scope"
  [ "$1" != none ] && printf '%s' "$1" > "$t/home/.claude/settings.json"
  [ "$2" != none ] && printf '%s' "$2" > "$t/proj/.claude/settings.local.json"
  MID="${3:-claude-opus-5-5}" P="$t/proj" python3 -c 'import json, os
print(json.dumps({"model": {"id": os.environ["MID"], "display_name": "Opus 5.5"}, "session_id": "slacw-%d" % os.getpid(),
  "workspace": {"current_dir": os.environ["P"]}, "cwd": os.environ["P"],
  "context_window": {"used_percentage": 35, "context_window_size": 1000000,
    "current_usage": {"input_tokens": 900, "cache_read_input_tokens": 340000, "cache_creation_input_tokens": 7000}}}))' \
    | HOME="$t/home" SUPERCHARGER_STATE="$t/st" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | sed -n 2p
  rm -rf "$t"
}
ACW='{"modelSettings":{"claude-opus-5-5":{"autoCompactWindow":400000}}}'

begin_test "no autoCompactWindow: context against the full 1M window"
L=$(_render none none)
case "$L" in *"Context: 35% (347.9K/1.0M)"*) pass ;; *) fail "got: $L" ;; esac

begin_test "user autoCompactWindow 400000: context against 400K"
L=$(_render "$ACW" none)
case "$L" in *"Context: 86% (347.9K/400.0K)"*) pass ;; *) fail "got: $L" ;; esac

begin_test "a [1m] model id suffix still matches the setting"
L=$(_render "$ACW" none 'claude-opus-5-5[1m]')
case "$L" in *"Context: 86%"*) pass ;; *) fail "got: $L" ;; esac

begin_test "a setting for another model is ignored"
L=$(_render '{"modelSettings":{"claude-sonnet-5-5":{"autoCompactWindow":400000}}}' none)
case "$L" in *"Context: 35%"*) pass ;; *) fail "got: $L" ;; esac

begin_test "project settings.local.json wins over user settings"
L=$(_render "$ACW" '{"modelSettings":{"claude-opus-5-5":{"autoCompactWindow":800000}}}')
case "$L" in *"Context: 43% (347.9K/800.0K)"*) pass ;; *) fail "got: $L" ;; esac

begin_test "a window larger than the model's own is ignored"
L=$(_render '{"modelSettings":{"claude-opus-5-5":{"autoCompactWindow":2000000}}}' none)
case "$L" in *"Context: 35% (347.9K/1.0M)"*) pass ;; *) fail "got: $L" ;; esac

begin_test "unparseable settings never break the render"
L=$(_render '{not json' none)
case "$L" in *"Context: 35%"*) pass ;; *) fail "got: $L" ;; esac

report
