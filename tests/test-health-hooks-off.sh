#!/usr/bin/env bash
# config-health: the guard canary runs guards directly, so it stays green when
# Claude Code itself runs no hooks. IS_DEMO and disableAllHooks must fail Security.
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/tests/helpers.sh"

echo "=== config-health: hooks switched off ==="

setup_test_home
mkdir -p "$HOME/.claude"
health() { printf '%s' "$1" > "$HOME/.claude/settings.json"; shift
  env "$@" bash "$REPO_DIR/tools/config-health.sh" 2>&1; }

begin_test "health: IS_DEMO in settings env is reported"
out=$(health '{"hooks":{},"env":{"IS_DEMO":"1"}}' -u IS_DEMO)
case "$out" in *"IS_DEMO is set"*) pass ;; *) fail "not reported: $out" ;; esac

begin_test "health: IS_DEMO in the environment is reported"
out=$(health '{"hooks":{}}' IS_DEMO=1)
case "$out" in *"IS_DEMO is set"*) pass ;; *) fail "not reported: $out" ;; esac

begin_test "health: IS_DEMO=0 is not reported"
out=$(health '{"hooks":{},"env":{"IS_DEMO":"0"}}' -u IS_DEMO)
case "$out" in *"IS_DEMO is set"*) fail "false report" ;; *) pass ;; esac

begin_test "health: disableAllHooks is reported"
out=$(health '{"hooks":{},"disableAllHooks":true}' -u IS_DEMO)
case "$out" in *"disableAllHooks is true"*) pass ;; *) fail "not reported: $out" ;; esac

begin_test "health: neither set, neither reported"
out=$(health '{"hooks":{}}' -u IS_DEMO)
case "$out" in *"IS_DEMO is set"*|*"disableAllHooks is true"*) fail "false report" ;; *) pass ;; esac

# A project .claude/settings.json outranks the user file, so a cloned repo can turn every
# hook off in its folder (settings-reference, disableAllHooks).
P=$(mktemp -d); mkdir -p "$P/.claude"
begin_test "health: disableAllHooks in the project settings is reported"
printf '{"disableAllHooks":true}' > "$P/.claude/settings.json"
out=$(cd "$P" && health '{"hooks":{}}' -u IS_DEMO)
case "$out" in *"disableAllHooks is true in .claude/settings.json"*) pass ;; *) fail "not reported: $out" ;; esac

begin_test "health: a settings.local.json false outranks the project true"
printf '{"disableAllHooks":false}' > "$P/.claude/settings.local.json"
out=$(cd "$P" && health '{"hooks":{}}' -u IS_DEMO)
case "$out" in *"disableAllHooks is true"*) fail "false report" ;; *) pass ;; esac
rm -rf "$P"

report
