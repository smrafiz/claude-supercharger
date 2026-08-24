#!/usr/bin/env bash
# Claude Supercharger — Claude Code Version Floor Check
# Event: SessionStart | Matcher: (none)
#
# Several hook EVENTS we register did not exist in older Claude Code builds.
# Claude Code does not complain about a registration on an event it does not
# know: it does not fire it, does not warn, and does not error — verified on
# 2.1.240 by registering a deliberately bogus event name and reading the
# `--debug hooks` log, which showed the hook subsystem running normally and no
# mention of the bogus event anywhere. So on an older build those hooks are
# simply absent, and nothing anywhere says so.
#
# That is the same silent-failure shape as the v2.29.2 comma-matcher bug, but it
# cannot be fixed the same way. A comma matcher had an older equivalent spelling
# to fall back to; an event that does not exist yet has none. The capability is
# genuinely missing, so the only honest thing to do is SAY so.
#
# Opt out with SUPERCHARGER_NO_VERSION_FLOOR_CHECK=1.

set -euo pipefail

# Honor the global kill-switch — /sc off must silence EVERY hook. Sourcing
# lib-timing exits at source time when the disable flag is set.
# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true

[ "${SUPERCHARGER_NO_VERSION_FLOOR_CHECK:-0}" = "1" ] && exit 0

# Drain stdin so the parent never takes SIGPIPE on the payload.
cat >/dev/null 2>&1 || true

# shellcheck source=hooks/lib-paths.sh
. "${BASH_SOURCE[0]%/*}/lib-paths.sh" 2>/dev/null || true
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"

SCOPE_DIR="$SUPERCHARGER_STATE/scope"
CACHE_FILE="$SCOPE_DIR/.cc-version"
WARNED_FILE="$SCOPE_DIR/.cc-floor-warned"

# ── Floor table ───────────────────────────────────────────────────────────────
# Event|first Claude Code version that fires it|what is lost without it
#
# Sourced from the Claude Code CHANGELOG (the release that announced each
# event), not from guesswork. tests/test-version-floor.sh fails if an event we
# register is missing from this table, so a newly-adopted event cannot slip in
# unlisted. Baseline events (PreToolUse, PostToolUse, SessionStart, Stop,
# UserPromptSubmit, PreCompact, SubagentStop, SessionEnd, Notification,
# UserPromptExpansion) predate every supported build and are deliberately absent
# — listed in _BASELINE below so the drift test can tell "old enough to be safe"
# apart from "nobody recorded a floor for this yet".
#
# Ordered newest floor first so the message leads with what most users lack.
_BASELINE='PreToolUse PostToolUse SessionStart Stop UserPromptSubmit
PreCompact SubagentStop SessionEnd Notification UserPromptExpansion'

_FLOORS='
DirectoryAdded|2.1.219|/add-dir audit record
MessageDisplay|2.1.152|SECURITY: secret redaction in displayed messages
PostToolUseFailure|2.1.119|tool-failure advice and failure telemetry
PermissionDenied|2.1.89|permission-denial advice
TaskCreated|2.1.84|task telemetry
CwdChanged|2.1.83|SECURITY: config-weakening notice when cwd changes
FileChanged|2.1.83|file-change watcher
StopFailure|2.1.78|diagnostics when a turn dies on an API error
Elicitation|2.1.76|SECURITY: elicitation guard
ElicitationResult|2.1.76|elicitation discovery
PostCompact|2.1.76|context restoration after compaction
InstructionsLoaded|2.1.69|instruction-load telemetry
ConfigChange|2.1.49|config-change telemetry
TaskCompleted|2.1.33|task-completion telemetry
TeammateIdle|2.1.33|teammate-idle telemetry
Setup|2.1.10|setup health check on --init
PermissionRequest|2.0.45|smart-approve and permission notifications
SubagentStart|2.0.43|subagent safety, cost tracking and circuit breaker'

# ── Version compare ───────────────────────────────────────────────────────────
# True when $1 is strictly older than $2. Field-by-field numeric, so 2.1.9 sorts
# BELOW 2.1.10 (a string compare gets that backwards, which is the whole point).
# Non-numeric fields degrade to 0 rather than tripping `set -u` on odd builds.
_sc_older_than() {
  [ "$1" = "$2" ] && return 1
  _a="$1"; _b="$2"
  while [ -n "$_a$_b" ]; do
    _x="${_a%%.*}"; _y="${_b%%.*}"
    case "$_x" in ''|*[!0-9]*) _x=0 ;; esac
    case "$_y" in ''|*[!0-9]*) _y=0 ;; esac
    [ "$_x" -lt "$_y" ] && return 0
    [ "$_x" -gt "$_y" ] && return 1
    case "$_a" in *.*) _a="${_a#*.}" ;; *) _a="" ;; esac
    case "$_b" in *.*) _b="${_b#*.}" ;; *) _b="" ;; esac
  done
  return 1
}

# Size AND mtime: mtime alone has whole-second granularity, so a binary replaced
# within the same second as an earlier probe would reuse the stale version — the
# drift test caught exactly that.
_sc_sig() { stat -c "%Y:%s" "$1" 2>/dev/null || stat -f "%m:%z" "$1" 2>/dev/null || echo ""; }

# ── Resolve the running Claude Code version ───────────────────────────────────
# `claude --version` costs ~100ms (measured 89-117ms over 5 runs), which is far
# too much to pay on every session start. It is cached against the binary's path,
# mtime and size, so the steady state is a single stat and an upgrade invalidates
# the cache on its own. `lastOnboardingVersion` in ~/.claude.json looked like a free
# alternative and is NOT one: it read 2.1.212 on a machine actually running
# 2.1.240, which would have produced confident false warnings.
# v2.29.20: `+set`, not `:-`. With `:-` an explicitly-EMPTY SUPERCHARGER_CC_BIN
# fell through to the PATH lookup, so a test setting it to "" to simulate an
# absent claude was really asserting that `claude` is not in the PATH it
# narrowed to — a fact about the host, not about this hook. Proven by placing a
# fake claude on that PATH: the same assertion flipped from silent to warning.
# It only passed because GitHub runners do not ship claude in /usr/bin; the
# identical shape DID break test-tool-preferences on ubuntu-latest, which ships
# gh there. Same override semantics as SUPERCHARGER_GH_BIN in tool-preferences.sh.
if [ -n "${SUPERCHARGER_CC_BIN+set}" ]; then
  CC_BIN="$SUPERCHARGER_CC_BIN"
else
  CC_BIN="$(command -v claude 2>/dev/null || true)"
fi
[ -n "$CC_BIN" ] || exit 0          # not on PATH (plugin sandbox, odd install) — say nothing

CC_KEY="$CC_BIN:$(_sc_sig "$CC_BIN")"
CC_VER=""

if [ -f "$CACHE_FILE" ]; then
  _cached=$(cat "$CACHE_FILE" 2>/dev/null || echo "")
  case "$_cached" in
    "$CC_KEY	"*) CC_VER="${_cached#*	}" ;;
  esac
fi

if [ -z "$CC_VER" ]; then
  # `claude --version` prints e.g. "2.1.240 (Claude Code)".
  _raw=$("$CC_BIN" --version 2>/dev/null || echo "")
  CC_VER=$(printf '%s' "$_raw" | tr -d '\r' | awk '{print $1}')
  case "$CC_VER" in
    ''|*[!0-9.]*) exit 0 ;;         # unparseable — fail open, never guess
  esac
  mkdir -p "$SCOPE_DIR" 2>/dev/null || true
  printf '%s\t%s\n' "$CC_KEY" "$CC_VER" > "$CACHE_FILE" 2>/dev/null || true
fi

# ── Collect what this build cannot fire ───────────────────────────────────────
# Built with literal \n separators, not real newlines: this string becomes a JSON
# string value below. The content is entirely ours (event names, dotted versions
# and fixed ASCII descriptions, all guarded by the drift test), so there is
# nothing here that needs quote or backslash escaping.
inert=""
n=0
while IFS='|' read -r ev floor lost; do
  [ -n "$ev" ] || continue
  if _sc_older_than "$CC_VER" "$floor"; then
    inert="${inert}\\n    ${ev} (needs ${floor}) - ${lost}"
    n=$((n + 1))
  fi
done <<EOF
$_FLOORS
EOF

[ "$n" -gt 0 ] || exit 0            # current build - the common case, stay silent

# ── Warn at most once a day per version ───────────────────────────────────────
# A user pinned to an old build on purpose should not be nagged every session,
# but should not be able to forget either.
_today=$(date -u +%Y-%m-%d 2>/dev/null || echo "")
_stamp="$CC_VER|$_today"
if [ -f "$WARNED_FILE" ]; then
  [ "$(cat "$WARNED_FILE" 2>/dev/null || echo "")" = "$_stamp" ] && exit 0
fi
mkdir -p "$SCOPE_DIR" 2>/dev/null || true
printf '%s\n' "$_stamp" > "$WARNED_FILE" 2>/dev/null || true

# systemMessage, NOT stderr. Measured against a live 2.1.240 with `--debug hooks`:
# a hook's stderr arrives in the debug log as a bare unhandled line, while stdout
# JSON is logged as "Parsed initial response" and rendered to the user. A warning
# on the channel nobody reads is the exact failure this hook exists to report, so
# it must not ship on that channel itself. Registered BLOCKING for the same
# reason - the steady-state cost is one stat, so there is nothing to gain by
# going async and detaching the output.
printf '{"systemMessage":"Claude Code %s predates %d hook event(s) Supercharger uses.\\nThese hooks are registered but WILL NOT FIRE, and Claude Code reports no error for them:\\n%s\\n\\nCore protection is unaffected: the guards on PreToolUse and PostToolUse (safety, path, secret and injection scanning) run on events every supported build has.\\n\\nFix: upgrade Claude Code.  Silence: SUPERCHARGER_NO_VERSION_FLOOR_CHECK=1"}\n' \
  "$CC_VER" "$n" "$inert"

exit 0
