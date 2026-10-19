#!/usr/bin/env bash
# onFailure "block" on the core guards (Claude Code 2.1.295+): a guard that crashes,
# times out or prints bad JSON denies the call instead of letting it through. The
# installer writes the field only when the local Claude Code is new enough.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

CORE="git-safety.sh harness-tamper-guard.sh path-guard.sh safety.sh"

emit() { # claude-version ("" = no claude on PATH), override -> sorted hooks carrying onFailure
  local ver="$1" override="$2" bin out
  setup_test_home >/dev/null 2>&1
  mkdir -p "$HOME/.claude"; echo '{}' > "$HOME/.claude/settings.json"
  bin=$(mktemp -d)
  [ -n "$ver" ] && printf '#!/bin/sh\necho "%s (Claude Code)"\n' "$ver" > "$bin/claude" && chmod +x "$bin/claude"
  (
    PATH="$bin:$(dirname "$(command -v python3)"):/usr/bin:/bin"
    [ -n "$override" ] && SUPERCHARGER_ONFAILURE="$override"
    export PATH SUPERCHARGER_ONFAILURE
    source "$REPO_DIR/lib/hooks.sh"
    merge_hooks_into_settings "full" "true"
  ) >/dev/null 2>&1
  out=$(python3 -c "
import json, sys, re
d=json.load(open(sys.argv[1]))['hooks']
s=sorted({re.search(r'([\w-]+\.sh)', h['command']).group(1)
          for es in d.values() for e in es for h in e.get('hooks',[]) if h.get('onFailure')=='block'})
print(' '.join(s))" "$HOME/.claude/settings.json" 2>/dev/null)
  rm -rf "$bin"; teardown_test_home >/dev/null 2>&1
  printf '%s' "$out"
}

echo "=== onFailure block on core guards ==="

begin_test "onFailure: 2.1.295 marks exactly the four core guards"
R=$(emit "2.1.295" "")
[ "$R" = "$CORE" ] && pass || fail "got: [$R]"

begin_test "onFailure: a newer build marks them too"
R=$(emit "2.2.10" "")
[ "$R" = "$CORE" ] && pass || fail "got: [$R]"

begin_test "onFailure: 2.1.294 writes no onFailure field"
R=$(emit "2.1.294" "")
[ -z "$R" ] && pass || fail "got: [$R]"

begin_test "onFailure: no claude on PATH writes no onFailure field"
R=$(emit "" "")
[ -z "$R" ] && pass || fail "got: [$R]"

begin_test "onFailure: SUPERCHARGER_ONFAILURE=0 turns it off on a new build"
R=$(emit "2.1.302" "0")
[ -z "$R" ] && pass || fail "got: [$R]"

report
