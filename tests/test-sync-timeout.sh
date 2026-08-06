#!/usr/bin/env bash
# Platform-aware sync hook timeout (v2.26.70)
#
# The 15s cap on blocking hooks was chosen from macOS measurements, where a hook
# forks in ~2ms and real work is under 10ms. Git Bash has no fork(): every python3
# or jq is a CreateProcess through MSYS, commonly 200-500ms, worse with Defender
# scanning each launch. A UserPromptSubmit hook making ~8 of them exceeds 15s
# honestly — and Claude Code then DISCARDS the hook's output, so the user loses the
# context injection as well as the time:
#
#     UserPromptSubmit hook timed out after 15s — output discarded.
#
# Reported from a real Windows desktop, 2026-08-06. Raising the cap does not make
# Windows fast; it stops a slow hook from also being a silently dropped one. The
# fork count is the real fix and is not a one-line change.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Emit settings.json under a sandbox HOME with a given PLATFORM, echo the timeouts.
emit() { # platform, override -> "<sync-timeouts> | <async-timeouts>"
  local plat="$1" override="$2" out
  setup_test_home >/dev/null 2>&1
  mkdir -p "$HOME/.claude"; echo '{}' > "$HOME/.claude/settings.json"
  (
    PLATFORM="$plat"
    [ -n "$override" ] && SUPERCHARGER_SYNC_TIMEOUT="$override"
    export PLATFORM SUPERCHARGER_SYNC_TIMEOUT
    source "$REPO_DIR/lib/hooks.sh"
    merge_hooks_into_settings "full" "true"
  ) >/dev/null 2>&1
  out=$(python3 -c "
import json
d=json.load(open('$HOME/.claude/settings.json'))['hooks']
sync=set(); asyn=set()
for ev,entries in d.items():
    for e in entries:
        for h in e.get('hooks',[]):
            (asyn if h.get('async') or h.get('asyncRewake') else sync).add(h.get('timeout'))
print(','.join(str(x) for x in sorted(sync))+' | '+','.join(str(x) for x in sorted(asyn)))
" 2>/dev/null)
  teardown_test_home >/dev/null 2>&1
  printf '%s' "$out"
}

echo "=== Sync Hook Timeout Tests ==="

begin_test "non-Windows keeps the 15s blocking cap"
R=$(emit "macos" "")
[ "${R%% *}" = "15" ] && pass || fail "expected sync=15, got: $R"

begin_test "Windows raises the blocking cap to 60s"
R=$(emit "windows" "")
[ "${R%% *}" = "60" ] && pass || fail "expected sync=60 on windows, got: $R"

begin_test "async hooks keep 120s on every platform"
# The async tier is unrelated to fork cost and must not drift with this change.
RM=$(emit "macos" ""); RW=$(emit "windows" "")
[ "${RM##* }" = "120" ] && [ "${RW##* }" = "120" ] && pass \
  || fail "async tier changed: macos=[$RM] windows=[$RW]"

begin_test "SUPERCHARGER_SYNC_TIMEOUT overrides on any platform"
# A slow machine is not exclusively a Windows machine — network filesystems and
# loaded CI boxes hit the same wall.
R=$(emit "macos" "45")
[ "${R%% *}" = "45" ] && pass || fail "override ignored, got: $R"

begin_test "the override wins on Windows too"
R=$(emit "windows" "30")
[ "${R%% *}" = "30" ] && pass || fail "override ignored on windows, got: $R"

begin_test "every blocking hook gets exactly one cap, not a mixture"
# A partially-applied change here would leave some hooks at 15 and some at 60,
# which reads as working while a subset still drops its output.
R=$(emit "windows" "")
case "${R%% *}" in
  *,*) fail "mixed sync timeouts on windows: ${R%% *}" ;;
  *)   pass ;;
esac

report
