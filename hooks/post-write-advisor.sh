#!/usr/bin/env bash
# Claude Supercharger — Post-Write Advisory Dispatcher
# Event: PostToolUse | Matcher: Write, Edit, MultiEdit
#
# Folds three advisory checks that each used to be a separate PostToolUse hook —
# conflict-marker, config-validity (json/yaml/toml), shebang-without-+x — into ONE
# process that reads the final on-disk file a single time. Purely a perf/consolidation
# win: a benign write now costs one hook spawn instead of three (the per-hook floor is
# ~9ms; see [[perf-hook-overhead]]). Behaviour is unchanged — the detection logic lives
# in lib_postwrite.py and each check still honours its ORIGINAL kill-switch
# (SUPERCHARGER_CONFLICT_MARKER_GUARD / _CONFIG_VALIDITY_GUARD / _SHEBANG_EXEC_GUARD),
# plus a master SUPERCHARGER_POST_WRITE_ADVISOR=0. WARN only (additionalContext),
# async, fail-open.
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_POST_WRITE_ADVISOR:-1}" = "0" ] && exit 0

_INPUT=$(cat)
# Combined fast-path: fire python only if a shebang, a conflict marker, or a
# structured-config extension could be present. Benign source writes exit here.
case "$_INPUT" in
  *'#!'*|*'<<<<<<<'*|*'>>>>>>>'*|*.json*|*.yaml*|*.yml*|*.toml*) : ;;
  *) exit 0 ;;
esac
check_hook_disabled "post-write-advisor" 2>/dev/null && exit 0
hook_profile_skip "post-write-advisor" 2>/dev/null && exit 0

_PW_OUT=$(mktemp 2>/dev/null) || _PW_OUT="${TMPDIR:-/tmp}/postwrite.$$"
HOOK_INPUT="$_INPUT" python3 "$HOOKS_DIR/lib_postwrite.py" > "$_PW_OUT" 2>/dev/null
_JSON=$(cat "$_PW_OUT" 2>/dev/null); rm -f "$_PW_OUT" 2>/dev/null
[ -z "$_JSON" ] && exit 0

printf '%s\n' "$_JSON"
echo "[Supercharger] post-write-advisor: emitted advisory (conflict/validity/shebang)" >&2
exit 0
