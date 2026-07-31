#!/usr/bin/env bash
# Config weakening notice (v2.26.8) — CwdChanged.
#
# Entering a directory whose .supercharger.json disables security categories or
# hooks is a guardrail change nobody reviewed: the config arrives with the branch,
# the clone, or the worktree, not with a decision. path-guard stops the AGENT from
# writing those files; nothing covered them arriving this way.
#
# The hook notices, it never blocks — a repo carrying its own config is ordinary.
#
# It lives on CwdChanged and NOT on WorktreeCreate: Worktree* are provider events
# (CC delegates worktree creation to a hook registered there), and a passive hook
# there breaks `isolation: worktree` for every agent — shipped and reverted in
# v2.7.26→.27. test-install.sh:242 guards that; the last assertion here pins the
# positive half, that this hook chose the right event.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/config-weakening-notice.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT

echo "=== Config Weakening Notice Tests ==="

fire() { printf '{"hook_event_name":"CwdChanged","cwd":"%s","previous_cwd":"/tmp"}' "$1" | bash "$HOOK" 2>/dev/null; }

begin_test "notice: silent when the directory has no .supercharger.json"
mkdir -p "$TD/clean"
OUT=$(fire "$TD/clean")
[ -z "$OUT" ] && pass || fail "expected silence, got: $OUT"

begin_test "notice: silent on a config that weakens nothing"
mkdir -p "$TD/benign"; printf '{"economy":"lean","budget":5.0}' > "$TD/benign/.supercharger.json"
OUT=$(fire "$TD/benign")
[ -z "$OUT" ] && pass || fail "a config with no disable keys must not warn: $OUT"

begin_test "notice: warns when the directory disables security categories"
mkdir -p "$TD/weak"; printf '{"disableSecurityCategories":["selfmod","abs-path"]}' > "$TD/weak/.supercharger.json"
OUT=$(fire "$TD/weak")
printf '%s' "$OUT" | python3 -c "
import json,sys
m=json.load(sys.stdin)['systemMessage']
assert 'selfmod' in m and 'CONFIG' in m, m
print('ok')
" >/dev/null 2>&1 && pass || fail "no usable warning: $OUT"

begin_test "notice: warns when the directory disables hooks"
mkdir -p "$TD/nohooks"; printf '{"disableHooks":["safety"]}' > "$TD/nohooks/.supercharger.json"
OUT=$(fire "$TD/nohooks")
printf '%s' "$OUT" | grep -q 'hooks off' && pass || fail "no disableHooks warning: $OUT"

begin_test "notice: NEVER blocks — exit 0, no permissionDecision"
mkdir -p "$TD/weak2"; printf '{"disableSecurityCategories":["selfmod"]}' > "$TD/weak2/.supercharger.json"
OUT=$(fire "$TD/weak2"); RC=$?
{ [ "$RC" = "0" ] && ! printf '%s' "$OUT" | grep -q 'permissionDecision'; } \
  && pass || fail "must notice, not block: rc=$RC out=$OUT"

begin_test "notice: malformed config is silent, not a second complaint"
mkdir -p "$TD/bad"; printf 'not json {' > "$TD/bad/.supercharger.json"
OUT=$(fire "$TD/bad")
[ -z "$OUT" ] && pass || fail "expected silence on malformed config: $OUT"

begin_test "notice: registered on CwdChanged, never on a Worktree* provider event"
# The negative half is test-install.sh:242. This is the positive half: the hook
# exists AND is wired to the event that can carry it.
if grep -q 'CwdChanged.*config-weakening-notice' "$REPO_DIR/lib/hooks.sh" \
   && ! grep -q 'Worktree.*config-weakening-notice' "$REPO_DIR/lib/hooks.sh"; then
  pass
else
  fail "hook not wired to CwdChanged, or wired to a provider event"
fi

report
