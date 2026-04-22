#!/usr/bin/env bash
# Claude Supercharger — Session Start Hook
# Event: SessionStart | Matcher: (none)
# 1. First-run welcome (once ever)
# 2. Auto-detects stack and injects context
# 3. Loads .supercharger.json if present

set -euo pipefail

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")
fi

if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
WELCOME_FLAG="$SUPERCHARGER_DIR/.welcomed"
mkdir -p "$SUPERCHARGER_DIR"

# Walk up to find .supercharger.json (max 5 levels)
CONFIG_FILE=""
SEARCH_DIR="$PROJECT_DIR"
for _ in 1 2 3 4 5; do
  if [ -f "$SEARCH_DIR/.supercharger.json" ]; then
    CONFIG_FILE="$SEARCH_DIR/.supercharger.json"
    break
  fi
  PARENT=$(dirname "$SEARCH_DIR")
  [ "$PARENT" = "$SEARCH_DIR" ] && break
  SEARCH_DIR="$PARENT"
done

RESULT=$(CONFIG_FILE="$CONFIG_FILE" PROJECT_DIR="$PROJECT_DIR" WELCOME_FLAG="$WELCOME_FLAG" python3 << 'PYEOF'
import json, os, sys, re

project_dir = os.environ['PROJECT_DIR']
config_file = os.environ.get('CONFIG_FILE', '')
welcome_flag = os.environ['WELCOME_FLAG']

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
    pkg = os.path.join(project_dir, 'package.json')
    if os.path.isfile(pkg):
        with open(pkg) as f:
            pdata = json.load(f)
        deps = {}
        deps.update(pdata.get('dependencies', {}))
        deps.update(pdata.get('devDependencies', {}))

        if 'typescript' in deps or os.path.isfile(os.path.join(project_dir, 'tsconfig.json')):
            stack_parts.append('TypeScript')
        else:
            stack_parts.append('JavaScript')

        for fw, label in [
            ('next', 'Next.js'), ('react', 'React'), ('vue', 'Vue'),
            ('@angular/core', 'Angular'), ('svelte', 'Svelte'),
            ('express', 'Express'), ('@nestjs/core', 'NestJS'),
        ]:
            if fw in deps:
                stack_parts.append(label)
                break

        for pm, lock in [('pnpm','pnpm-lock.yaml'),('bun','bun.lockb'),('yarn','yarn.lock')]:
            if os.path.isfile(os.path.join(project_dir, lock)):
                stack_parts.append(f'pkg:{pm}')
                break

    elif os.path.isfile(os.path.join(project_dir, 'wp-config.php')) or \
         os.path.isfile(os.path.join(project_dir, 'functions.php')):
        stack_parts.append('WordPress')

    elif any(os.path.isfile(os.path.join(project_dir, f))
             for f in ['requirements.txt', 'pyproject.toml', 'setup.py']):
        stack_parts.append('Python')
        for fw, kw in [('Django','django'),('FastAPI','fastapi'),('Flask','flask')]:
            for fname in ['requirements.txt', 'pyproject.toml']:
                fpath = os.path.join(project_dir, fname)
                if os.path.isfile(fpath):
                    with open(fpath) as f:
                        if kw in f.read().lower():
                            stack_parts.append(fw)
                            break

    elif os.path.isfile(os.path.join(project_dir, 'Cargo.toml')):
        stack_parts.append('Rust')

    elif os.path.isfile(os.path.join(project_dir, 'go.mod')):
        stack_parts.append('Go')

    elif os.path.isfile(os.path.join(project_dir, 'composer.json')):
        stack_parts.append('PHP')
except Exception:
    pass

if stack_parts:
    import hashlib
    cache_dir = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
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
                    budget_file = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', '.budget-cap')
                    with open(budget_file, 'w') as f:
                        f.write(str(budget))
                    cfg_parts.append(f'Budget: ${budget:.2f}')
            except (ValueError, TypeError):
                pass

        auto_economy = config.get('autoEconomy', True)
        if auto_economy is False:
            cfg_parts.append('Auto-economy: off')

        thinking_control = config.get('thinkingControl', True)
        if thinking_control is False:
            tc_file = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', '.no-thinking-control')
            with open(tc_file, 'w') as f:
                f.write('1')
            cfg_parts.append('Thinking control: off')
        else:
            tc_file = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', '.no-thinking-control')
            if os.path.isfile(tc_file):
                os.remove(tc_file)

        forecast_turns = config.get('forecastTurnsPerAgent', '')
        if forecast_turns:
            try:
                forecast_turns = int(forecast_turns)
                if forecast_turns != 10:
                    cfg_parts.append(f'Forecast: {forecast_turns} turns/agent')
            except (ValueError, TypeError):
                pass

        # Per-project hook overrides
        disable_hooks = config.get('disableHooks', [])
        disabled_file = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', '.disabled-hooks')
        if isinstance(disable_hooks, list) and disable_hooks:
            valid = [h.strip() for h in disable_hooks if isinstance(h, str) and h.strip()]
            if valid:
                os.makedirs(os.path.dirname(disabled_file), exist_ok=True)
                with open(disabled_file, 'w') as f:
                    f.write('\n'.join(valid) + '\n')
                cfg_parts.append('Disabled hooks: ' + ', '.join(valid))
        else:
            if os.path.isfile(disabled_file):
                os.remove(disabled_file)

        if cfg_parts:
            parts.append('Project config: ' + '. '.join(cfg_parts) + '.')
    except Exception:
        pass

# --- Cache economy tier to scope file (avoids repeated grep in UserPromptSubmit hooks) ---
try:
    scope_dir = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
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
