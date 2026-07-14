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

for line in hooks_input.strip().split('\n'):
    if not line.strip():
        continue
    parts = line.split('|', 4)
    event = parts[0]
    matcher = parts[1] if len(parts) > 1 else ''
    command = parts[2] if len(parts) > 2 else ''
    flags = parts[3] if len(parts) > 3 else ''
    if_pattern = parts[4] if len(parts) > 4 else ''

    inner = {'type': 'command', 'command': command}
    flag_list = [f.strip() for f in flags.split(',') if f.strip()]
    if 'async' in flag_list:
        inner['async'] = True
    if 'asyncRewake' in flag_list:
        inner['asyncRewake'] = True
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
