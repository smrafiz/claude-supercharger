#!/usr/bin/env bash
# Claude Supercharger — Prompt-Layer Inject Hook
# Event: SessionStart | Matcher: (none)
#
# Delivers the instructional/prompt layer under the PLUGIN runtime, where a plugin
# cannot write ~/.claude/CLAUDE.md or ~/.claude/rules/*.md. It concatenates the
# single source of truth (configs/universal/*.md + the active economy tier) and
# emits it as SessionStart additionalContext.
#
# Under the INSTALLER this hook is a no-op: the same content is already installed
# as persistent files (CLAUDE.md + rules/*.md), so re-emitting it would duplicate
# the whole layer into every session. The CLAUDE_PLUGIN_ROOT gate enforces that.
#
# Role / mode / tier: SUPERCHARGER_* env wins (runtime switches), then the plugin
# userConfig values (exported as CLAUDE_PLUGIN_OPTION_* to hook processes), then a
# sensible default. This is the Phase 5 userConfig wiring.
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

# Plugin-only. Under the installer the layer lives in CLAUDE.md + rules/*.md.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || exit 0

UNIV="$SUPERCHARGER_HOME/configs/universal"
ECON="$SUPERCHARGER_HOME/configs/economy"
[ -d "$UNIV" ] || exit 0

ROLE="${SUPERCHARGER_ROLE:-${CLAUDE_PLUGIN_OPTION_ROLE:-Developer}}"
MODE="${SUPERCHARGER_MODE:-${CLAUDE_PLUGIN_OPTION_MODE:-Full}}"
TIER="${SUPERCHARGER_TIER:-${CLAUDE_PLUGIN_OPTION_ECONOMY_TIER:-standard}}"
VERSION=$(grep -m1 '^VERSION=' "$SUPERCHARGER_HOME/lib/utils.sh" 2>/dev/null | cut -d'"' -f2 || true)
[ -z "$VERSION" ] && VERSION=$(grep -m1 '"version"' "$SUPERCHARGER_HOME/.claude-plugin/plugin.json" 2>/dev/null | cut -d'"' -f4 || true)

TIER_FILE="$ECON/${TIER}.md"
[ -f "$TIER_FILE" ] || TIER_FILE="$ECON/lean.md"

CONTEXT_JSON=$(UNIV="$UNIV" TIER_FILE="$TIER_FILE" ROLE="$ROLE" MODE="$MODE" VERSION="v$VERSION" python3 <<'PYEOF' 2>/dev/null || true
import os, json

univ = os.environ['UNIV']
tier_file = os.environ['TIER_FILE']
subs = {
    '{{ROLES}}': os.environ.get('ROLE', 'Developer'),
    '{{MODE}}': os.environ.get('MODE', 'Full'),
    '{{VERSION}}': os.environ.get('VERSION', ''),
}

def read(path):
    try:
        with open(path, 'r') as f:
            return f.read()
    except OSError:
        return ''

def fill(text):
    for k, v in subs.items():
        text = text.replace(k, v)
    return text

# economy.md carries a {{ACTIVE_TIER}} placeholder -> the selected tier snippet.
economy = read(os.path.join(univ, 'economy.md')).replace('{{ACTIVE_TIER}}', read(tier_file))

# Order mirrors the installer: CLAUDE.md, then rules/*, then economy, then anti-patterns.
parts = [
    fill(read(os.path.join(univ, 'CLAUDE.md'))),
    read(os.path.join(univ, 'guardrails.md')),
    read(os.path.join(univ, 'supercharger.md')),
    fill(economy),
    read(os.path.join(univ, 'anti-patterns.yml')),
]
blocks = [p.strip() for p in parts if p.strip()]
if not blocks:
    raise SystemExit(0)

header = "# Claude Supercharger — active instruction layer (delivered via plugin)\n"
combined = header + "\n\n---\n\n".join(blocks)
print(json.dumps(combined))
PYEOF
)

[ -z "$CONTEXT_JSON" ] && exit 0

# hookSpecificOutput.additionalContext is the SessionStart channel that reaches the
# MODEL (systemMessage only reaches the user).
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$CONTEXT_JSON"
exit 0
