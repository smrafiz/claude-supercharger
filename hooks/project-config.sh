#!/usr/bin/env bash
# Claude Supercharger — Session Start Hook
# Event: SessionStart | Matcher: (none)
# 1. First-run welcome (once ever)
# 2. Auto-detects stack and injects context
# 3. Loads .supercharger.json if present

set -euo pipefail

_INPUT=$(cat)

# Honor the global kill-switch (/sc off) — don't inject project rules/role context
# when Supercharger is disabled. lib-suppress exits 0 when the flag is present.
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")
fi

if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

# Resolve state/code roots for both installer and plugin runtimes (see lib-paths.sh).
. "${BASH_SOURCE[0]%/*}/lib-paths.sh" 2>/dev/null || true
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
: "${SUPERCHARGER_HOME:=${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/supercharger}}"

SUPERCHARGER_DIR="$SUPERCHARGER_STATE"
WELCOME_FLAG="$SUPERCHARGER_DIR/.welcomed"
mkdir -p "$SUPERCHARGER_DIR"

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
LIB_DIR="$(cd "$HOOKS_DIR/../lib" && pwd)"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"

# Walk up to find .supercharger.json (max 5 levels).
# v2.6.36: in a linked worktree, start from main repo root.
CONFIG_FILE=""
SEARCH_DIR=$(_resolve_project_root "$PROJECT_DIR")
for _ in 1 2 3 4 5; do
  if [ -f "$SEARCH_DIR/.supercharger.json" ]; then
    CONFIG_FILE="$SEARCH_DIR/.supercharger.json"
    break
  fi
  PARENT=$(dirname "$SEARCH_DIR")
  [ "$PARENT" = "$SEARCH_DIR" ] && break
  SEARCH_DIR="$PARENT"
done

RESULT=$(CONFIG_FILE="$CONFIG_FILE" PROJECT_DIR="$PROJECT_DIR" WELCOME_FLAG="$WELCOME_FLAG" LIB_DIR="$LIB_DIR" SUPERCHARGER_STATE="$SUPERCHARGER_STATE" python3 << 'PYEOF'
import json, os, sys, re
sys.path.insert(0, os.environ['LIB_DIR'])
from detect_stack import detect_stack

project_dir = os.environ['PROJECT_DIR']
config_file = os.environ.get('CONFIG_FILE', '')
welcome_flag = os.environ['WELCOME_FLAG']

# Resolve the scope dir the SAME way the reader hooks do (lib-suppress/safety use
# ${CLAUDE_PLUGIN_DATA:-~/.claude/supercharger}). Writing to the hardcoded classic path
# made per-project disableHooks / disableSecurityCategories / profile / budget silently
# no-op on plugin installs (readers looked at $CLAUDE_PLUGIN_DATA/scope).
_SCOPE = os.path.join(
    os.environ.get('SUPERCHARGER_STATE') or os.path.join(os.path.expanduser('~'), '.claude', 'supercharger'),
    'scope')

parts = []

# --- First-run welcome ---
is_first_run = not os.path.isfile(welcome_flag)
if is_first_run:
    try:
        open(welcome_flag, 'w').close()
    except Exception:
        pass
    parts.append(
        'Claude Supercharger is active. '
        'Guardrails are on — I will not make destructive changes without asking. '
        'I verify before claiming done. '
        'Responses are lean by default. '
        'Say "supercharger help" anytime to see what I can do.'
    )

# --- Stack detection ---
stack_parts = []
try:
    s = detect_stack(project_dir)
    if s['detected']:
        stack_parts.extend(s['language'])
        if s['framework']:
            stack_parts.append(s['framework'][0])
        if s['package_manager'] and s['package_manager'] not in ('pip', 'cargo', 'go modules', 'composer'):
            stack_parts.append(f"pkg:{s['package_manager']}")
except Exception:
    pass

if stack_parts:
    import hashlib
    cache_dir = _SCOPE
    proj_hash = hashlib.md5(project_dir.encode()).hexdigest()[:8]
    cache_path = os.path.join(cache_dir, f'.stack-cache-{proj_hash}')
    already_known = os.path.isfile(cache_path)
    if already_known:
        # Compact form — stack already injected in a prior session
        parts.append('[stack=' + ','.join(stack_parts) + ']')
    else:
        parts.append('Detected stack: ' + ', '.join(stack_parts) + '. Use matching conventions. If any assumption seems wrong, ask before proceeding.')
        try:
            os.makedirs(cache_dir, exist_ok=True)
            with open(cache_path, 'w') as f:
                f.write(', '.join(stack_parts))
        except Exception:
            pass

# --- Project config (.supercharger.json) ---
if config_file and os.path.isfile(config_file):
    try:
        with open(config_file) as f:
            config = json.load(f)

        VALID_ROLES = {'developer', 'writer', 'student', 'data', 'pm', 'designer', 'devops', 'researcher'}
        roles = [r for r in config.get('roles', []) if isinstance(r, str) and r in VALID_ROLES]

        VALID_ECONOMY = {'standard', 'lean', 'minimal'}
        economy = config.get('economy', '')
        if economy not in VALID_ECONOMY:
            economy = ''

        raw_hints = config.get('hints', '')
        hints = re.sub(r'[^\x20-\x7E]', '', str(raw_hints))[:200]
        hints = re.sub(r'[<>{}\[\]\\`$]', '', hints)

        cfg_parts = []
        if roles:
            cfg_parts.append('Roles: ' + ', '.join(roles))
        if economy:
            cfg_parts.append('Economy: ' + economy)
        if hints:
            cfg_parts.append('Hints: ' + hints)

        # v2 fields
        budget = config.get('budget', '')
        if budget:
            try:
                budget = float(budget)
                if budget > 0:
                    budget_file = os.path.join(_SCOPE, '.budget-cap')
                    with open(budget_file, 'w') as f:
                        f.write(str(budget))
                    cfg_parts.append(f'Budget: ${budget:.2f}')
            except (ValueError, TypeError):
                pass

        auto_economy = config.get('autoEconomy', True)
        if auto_economy is False:
            cfg_parts.append('Auto-economy: off')

        forecast_turns = config.get('forecastTurnsPerAgent', '')
        if forecast_turns:
            try:
                forecast_turns = int(forecast_turns)
                if forecast_turns != 10:
                    cfg_parts.append(f'Forecast: {forecast_turns} turns/agent')
            except (ValueError, TypeError):
                pass

        # Per-project hook overrides. Distinguish key-absent (leave existing
        # .disabled-hooks alone — written by another project) from key-present-
        # but-empty (clear). Conflating these caused cross-project state bleed.
        disable_hooks = config.get('disableHooks', None)
        disabled_file = os.path.join(_SCOPE, '.disabled-hooks')
        if isinstance(disable_hooks, list) and disable_hooks:
            valid = [h.strip() for h in disable_hooks if isinstance(h, str) and h.strip()]
            if valid:
                os.makedirs(os.path.dirname(disabled_file), exist_ok=True)
                with open(disabled_file, 'w') as f:
                    f.write('\n'.join(valid) + '\n')
                cfg_parts.append('Disabled hooks: ' + ', '.join(valid))
        elif disable_hooks is not None:
            # Key explicitly present but empty list — clear the file
            if os.path.isfile(disabled_file):
                os.remove(disabled_file)
        # Key absent → no change (preserves another project's setting)

        # Per-project performance profile
        profile = config.get('profile', '').strip().lower()
        profile_file = os.path.join(_SCOPE, '.profile')
        if profile in ('minimal', 'fast', 'standard'):
            os.makedirs(os.path.dirname(profile_file), exist_ok=True)
            with open(profile_file, 'w') as f:
                f.write(profile)
            if profile != 'standard':
                cfg_parts.append(f'Profile: {profile}')
        else:
            if os.path.isfile(profile_file):
                os.remove(profile_file)

        # Per-project CUSTOM dangerous patterns (v2.26.21). Additive only — a project
        # may TIGHTEN the guard, never loosen it, so there is no "allow" counterpart.
        # This is the on-thesis answer to "I want my own rules": config that survives
        # updates, rather than forking the hooks (which harness-tamper-guard exists to
        # prevent, and which would strand a repo on stale security patterns).
        custom = config.get('customPatterns', [])
        pat_file = os.path.join(_SCOPE, '.custom-patterns')
        if isinstance(custom, list):
            # Bounded: 50 patterns, 200 chars each. A runaway config must not turn every
            # Bash call into an unbounded regex. Newlines are stripped because the file
            # is line-based, exactly like the block ledger.
            clean = []
            for c in custom[:50]:
                if not isinstance(c, str):
                    continue
                c = c.replace('\n', ' ').replace('\r', ' ').strip()[:200]
                if c:
                    clean.append(c)
            # Validate with GREP, not python's re — they are different dialects, and
            # grep is what actually evaluates these. (`foo[unclosed` is rejected by
            # both here, but POSIX classes like [[:space:]] and python-only escapes
            # diverge, so testing with the wrong engine would pass patterns that then
            # fail at match time.)
            #
            # Reported HERE rather than in safety.sh because safety.sh only reaches
            # the custom-pattern code for commands that survive its fast path — a user
            # with a typo could go a whole session without ever seeing the warning,
            # believing a rule protects them when it does not. This runs once, at
            # SessionStart, where the config is read.
            import subprocess
            valid, invalid = [], []
            for c in clean:
                try:
                    rc = subprocess.run(['grep', '-qiE', c], input=b'',
                                        stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL).returncode
                except Exception:
                    rc = 2
                (valid if rc in (0, 1) else invalid).append(c)
            clean = valid
            if invalid:
                cfg_parts.append(
                    'INVALID customPatterns (not active): ' + ', '.join(invalid[:3]))
            if clean:
                os.makedirs(os.path.dirname(pat_file), exist_ok=True)
                with open(pat_file, 'w') as f:
                    f.write('\n'.join(clean) + '\n')
                cfg_parts.append(f'Custom patterns: {len(clean)}')
            elif os.path.isfile(pat_file):
                os.remove(pat_file)
        elif os.path.isfile(pat_file):
            os.remove(pat_file)

        # Per-project security category toggles
        disabled_cats = config.get('disableSecurityCategories', [])
        cats_file = os.path.join(_SCOPE, '.disabled-security-categories')
        valid_cats = {'filesystem', 'database', 'destructive', 'network', 'credentials', 'persistence', 'clipboard', 'browser', 'history', 'selfmod'}
        filtered = [c.strip().lower() for c in disabled_cats if c.strip().lower() in valid_cats]
        if filtered:
            os.makedirs(os.path.dirname(cats_file), exist_ok=True)
            with open(cats_file, 'w') as f:
                f.write('\n'.join(filtered))
            cfg_parts.append(f'Security disabled: {", ".join(filtered)}')
        else:
            if os.path.isfile(cats_file):
                os.remove(cats_file)

        if cfg_parts:
            parts.append('Project config: ' + '. '.join(cfg_parts) + '.')
    except Exception:
        pass

# --- Cache economy tier to scope file (avoids repeated grep in UserPromptSubmit hooks) ---
try:
    scope_dir = _SCOPE
    tier_file = os.path.join(scope_dir, '.economy-tier')
    if not os.path.isfile(tier_file):
        economy_md = os.path.join(os.path.expanduser('~'), '.claude', 'rules', 'economy.md')
        if os.path.isfile(economy_md):
            with open(economy_md) as f:
                for ln in f:
                    if ln.startswith('### Active Tier:'):
                        tier = ln.split(':', 1)[1].strip().split()[0].lower()
                        os.makedirs(scope_dir, exist_ok=True)
                        with open(tier_file, 'w') as tf:
                            tf.write(tier)
                        break
except Exception:
    pass

# --- Last session cost feedback ---
cost_file = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', '.last-session-cost')
if os.path.isfile(cost_file):
    try:
        cost_data = {}
        with open(cost_file) as f:
            for line in f:
                line = line.strip()
                if '=' in line:
                    k, v = line.split('=', 1)
                    cost_data[k.strip()] = v.strip()
        cost_val = float(cost_data.get('cost', '0') or '0')
        economy_val = cost_data.get('economy', 'lean')
        if cost_val > 0:
            parts.append(
                f'Last session cost: ${cost_val:.4f} (economy: {economy_val}). '
                f'Target: concise output per {economy_val} tier rules.'
            )
    except Exception:
        pass

if not parts:
    sys.exit(0)

print(json.dumps({
    'continue': True,
    'suppressOutput': False,
    'systemMessage': '[Supercharger] ' + ' | '.join(parts)
}))
PYEOF
)

if [ -n "$RESULT" ]; then
  echo "$RESULT"
fi

exit 0
