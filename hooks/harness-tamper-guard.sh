#!/usr/bin/env bash
# Claude Supercharger — Harness Tamper Guard
# Event: PreToolUse | Matcher: Bash
#
# Self-defense on the BASH channel. path-guard protects .claude/settings.json and
# the hooks on the Write/Edit channel; safety.sh's `selfmod` category blocks Bash
# edits to the CONFIG files (settings.json / .supercharger.json / .disabled-hooks
# / …). Two gaps remain on the Bash channel, closed here:
#   1. `claude --dangerously-skip-permissions` (or --permission-mode bypassPermissions)
#      spawns an UNGUARDED sub-instance — an agent must not launch one.
#   2. rm / mv / chmod -x / truncate / redirect against the HOOK SCRIPTS or the
#      install dir (…/supercharger/hooks/*, .claude/hooks/*, plugin hooks dir) or
#      the kill-switch file (.supercharger-disabled) tears the layer down — the
#      selfmod filename list does not cover the scripts/dir themselves.
# Blocks (deny). Fail-open; disable with SUPERCHARGER_HARNESS_TAMPER_GUARD=0.
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_HARNESS_TAMPER_GUARD:-1}" = "0" ] && exit 0

_INPUT=$(cat)

# Fast-path: only the commands that could plausibly tamper carry one of these
# tokens. Everything else exits before the (cheap) parse. Fail-safe: the tokens
# are a superset of every target pattern matched below.
# v2.23.10: use the SPECIFIC install-path forms, not a bare `*supercharger*` —
# that matched the "supercharger" substring in the cwd field for anyone working
# in this repo or the install dir (~/.claude/supercharger), defeating the early
# exit (~6ms tax on every Bash call there). These forms still cover every
# _HT_TARGET pattern below but no longer match a plain `claude-supercharger` cwd.
case "$_INPUT" in
  *dangerously-skip-permissions*|*permission-mode*|*--settings*|*--mcp-config*|*supercharger/hooks*|*supercharger-disabled*|*.claude/supercharger*|*.claude/hooks*|*.claude/plugins*) : ;;
  *) exit 0 ;;
esac

check_hook_disabled "harness-tamper-guard" 2>/dev/null && exit 0

CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // .tool_input.script // empty' 2>/dev/null || true)
if [ -z "$CMD" ]; then
  CMD=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json;ti=json.load(sys.stdin).get('tool_input',{});print(ti.get('command') or ti.get('script') or '')" 2>/dev/null || echo "")
fi
[ -z "$CMD" ] && exit 0

REASON=""

# (1) Launching an unguarded / reconfigured Claude instance.
case "$CMD" in
  *--dangerously-skip-permissions*|*--allow-dangerously-skip-permissions*)  # v2.23.26: +allow- variant
    REASON="launches Claude with a dangerously-skip-permissions flag, which spawns an instance with NO permission prompts and NO guardrails. An agent must not start an unguarded sub-instance." ;;
esac
if [ -z "$REASON" ]; then
  # --permission-mode bypassPermissions (flag + value, any spacing/quoting)
  if printf '%s' "$CMD" | grep -Eq -- '--permission-mode[[:space:]=]+["'\'']?bypassPermissions'; then
    REASON="sets --permission-mode bypassPermissions — spawns an unguarded Claude instance. An agent must not disable its own permission layer."
  fi
fi
if [ -z "$REASON" ]; then
  # v2.23.26: inline --settings/--mcp-config JSON to `claude` DEFINES hooks / MCP
  # servers (code execution) WITHOUT writing a file — bypassing path-guard's
  # settings.json/.mcp.json write guards. The value being inline JSON (starts with
  # `{`) is the smuggling signal; a plain `--settings ./file.json` is left alone.
  if printf '%s' "$CMD" | grep -Eq -- 'claude\b[^|;&]*--(settings|mcp-config)[[:space:]=]+["'\'']?\{'; then
    REASON="passes inline --settings/--mcp-config JSON to claude — this defines hooks or MCP servers (arbitrary code execution) on a sub-instance without writing a file, bypassing the file-write guardrails. Use a reviewed settings/config FILE, not inline JSON."
  fi
fi

# (2) Destroying / disabling the hook scripts, install dir, or kill-switch file.
if [ -z "$REASON" ]; then
  # Target: the installed hook scripts / supercharger dir / plugin hooks / kill switch.
  # Scoped to installed locations (.claude / …/supercharger/…) so a repo-relative
  # `chmod +x hooks/foo.sh` during development does NOT match.
  _HT_TARGET='(\.claude/supercharger/hooks/|/supercharger/hooks/|\.claude/hooks/|\.claude/plugins/[^;&|]*/hooks/|\.claude/supercharger([/[:space:]]|$)|\.supercharger-disabled)'
  # v2.23.22: PowerShell cmdlet verbs added for cross-channel parity (matcher now
  # Bash,PowerShell) — Remove-Item/Move-Item/Rename-Item/Clear-Content/Set-Content/
  # Out-File are the PowerShell equivalents of rm/mv/truncate/redirect over the hooks.
  _HT_VERB='(^|[[:space:];&|(])(rm|unlink|mv|truncate|shred|chmod|chattr|touch|ln|sed[[:space:]]+-i|tee|dd[[:space:]]+of=|:[[:space:]]*>|>>?|Remove-Item|Move-Item|Rename-Item|Clear-Content|Set-Content|Add-Content|Out-File)([[:space:]]|>)'
  if printf '%s' "$CMD" | grep -Eq -- "$_HT_VERB" && printf '%s' "$CMD" | grep -Eq -- "$_HT_TARGET"; then
    REASON="removes, disables, or overwrites Supercharger hook scripts / install dir / kill-switch — this tears down the guardrail layer. Use the documented controls (/sc off, hook-toggle.sh, SUPERCHARGER_* env) instead of editing the harness from the shell."
  fi
fi

[ -z "$REASON" ] && exit 0

RSN=$(printf '%s' "harness-tamper: $REASON" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$REASON")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
echo "[Supercharger] harness-tamper-guard: DENY — $REASON" >&2

# Log to the block ledger for /why and audits (best-effort).
_BLK="$SUPERCHARGER_STATE/scope/.blocked-commands"
mkdir -p "$(dirname "$_BLK")" 2>/dev/null || true
printf '[%s] harness-tamper — %s — %.120s\n' "$(date '+%Y-%m-%dT%H:%M:%SZ')" "guardrail teardown" "$CMD" >> "$_BLK" 2>/dev/null || true

exit 2
