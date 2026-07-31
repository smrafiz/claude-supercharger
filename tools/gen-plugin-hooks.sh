#!/usr/bin/env bash
# Claude Supercharger — Plugin hooks.json generator
#
# Emits hooks/hooks.json for the PLUGIN runtime from the single source of truth
# (get_hooks_for_mode in lib/hooks.sh) — the same tuple list the installer merges
# into settings.json, so the two channels never drift.
#
# Differences from the installer's merge_hooks_into_settings:
#   - command paths use ${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh (not $HOME/...)
#   - no SUPERCHARGER_TAG suffix (every hook here belongs to the plugin)
#   - no statusLine / env / attribution side-writes (a plugin cannot set those;
#     they are the documented casualties in docs/PLUGIN-DISTRIBUTION-PLAN.md §5)
#   - the full hook set is emitted (SUPERCHARGER_EMIT_ALL=1): the plugin ships full
#     mode and optional hooks self-gate at runtime, per the plan's Phase 2 decision.
#
# Usage: bash tools/gen-plugin-hooks.sh          # writes hooks/hooks.json
#        bash tools/gen-plugin-hooks.sh --check   # verify committed file is current (CI)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$REPO_DIR/hooks/hooks.json"

# shellcheck source=lib/hooks.sh
. "$REPO_DIR/lib/hooks.sh"

# Plugin ships the full set; developer hooks + opt-in hooks are included and
# self-gate at runtime. Literal ${CLAUDE_PLUGIN_ROOT} so the runtime expands it.
# Shell-form commands wrap the var in double quotes per the plugins-reference
# ("In shell-form hooks ... wrap it in double quotes") so a plugin install path
# containing spaces still resolves to a single argument.
HOOKS_LIST=$(SUPERCHARGER_EMIT_ALL=1 get_hooks_for_mode "full" "true" '"${CLAUDE_PLUGIN_ROOT}"/hooks')

GENERATED=$(HOOKS_INPUT="$HOOKS_LIST" python3 <<'PYEOF'
import json, os, sys

hooks_input = os.environ['HOOKS_INPUT']
events = {}


def normalize_mcp_matcher(m):
    """v2.24.5 — MCP matchers must be regex, not exact.

    A matcher of only [A-Za-z0-9_,| -] is an EXACT match (optionally a list);
    anything else is an unanchored regex. "mcp__" therefore matched a tool named
    literally "mcp__" and never fired, silently disabling every MCP-matched hook.
    Real tool names are mcp__<server>__<tool>, so each prefix needs ".*".

    Runs AFTER the '|' split — alternation is also '|'. Non-mcp matchers are
    returned untouched so plain lists stay exact-match.

    Byte-identical to the copy in lib/hooks.sh; tests assert the emitters agree.
    """
    if 'mcp__' not in m:
        return m
    toks = [t for t in m.split(',') if t]
    return '|'.join(t + '.*' if t.startswith('mcp__') else t for t in toks)


for line in hooks_input.strip().split('\n'):
    if not line.strip():
        continue
    parts = line.split('|', 4)
    event = parts[0]
    matcher = normalize_mcp_matcher(parts[1] if len(parts) > 1 else '')
    command = parts[2] if len(parts) > 2 else ''
    flags = parts[3] if len(parts) > 3 else ''
    if_pattern = parts[4] if len(parts) > 4 else ''

    inner = {'type': 'command', 'command': command}
    flag_list = [f.strip() for f in flags.split(',') if f.strip()]
    if 'async' in flag_list:
        inner['async'] = True
    if 'asyncRewake' in flag_list:
        inner['asyncRewake'] = True
    # v2.26.8: cap every hook. Claude Code defaults command hooks to 600s, so one
    # wedged hook — hung network call, stuck python, slow NFS stat — freezes a tool
    # call for ten minutes with the agent unable to proceed and no indication why.
    # Two tiers because the two kinds fail differently: a BLOCKING hook stalls the
    # user, so its cap is deliberately tight (measured hook work is under 10ms, so
    # 15s is three orders of magnitude of headroom); an async hook stalls nobody and
    # some legitimately run long (update-check does network, code-security-scanner
    # runs a python scan). Kept in sync with lib/hooks.sh - a test asserts the two
    # emitters agree.
    inner['timeout'] = 120 if ('async' in flag_list or 'asyncRewake' in flag_list) else 15
    if if_pattern:
        inner['if'] = if_pattern

    entry = {'hooks': [inner]}
    if matcher:
        entry['matcher'] = matcher

    events.setdefault(event, []).append(entry)

doc = {'hooks': events}
print(json.dumps(doc, indent=2))
PYEOF
)

if [[ "${1:-}" == "--check" ]]; then
  if [[ ! -f "$OUT" ]]; then
    echo "hooks/hooks.json is missing — run: bash tools/gen-plugin-hooks.sh" >&2
    exit 1
  fi
  if ! diff -q <(printf '%s\n' "$GENERATED") "$OUT" >/dev/null 2>&1; then
    echo "hooks/hooks.json is stale — regenerate: bash tools/gen-plugin-hooks.sh" >&2
    exit 1
  fi
  echo "hooks/hooks.json is up to date."
  exit 0
fi

printf '%s\n' "$GENERATED" > "$OUT"
echo "Wrote $OUT ($(printf '%s\n' "$HOOKS_LIST" | grep -c . ) hook registrations)"
