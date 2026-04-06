#!/usr/bin/env bash
# Claude Supercharger — Session Start Hook
# Event: SessionStart | Matcher: (none)
# 1. First-run welcome (once ever)
# 2. Auto-detects stack and injects context
# 3. Loads .supercharger.json if present

set -euo pipefail

PROJECT_DIR=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")

if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
WELCOME_FLAG="$SUPERCHARGER_DIR/.welcomed"
mkdir -p "$SUPERCHARGER_DIR"

# --- Update Check ---
# Read any notice written by a previous session's background check.
NOTICE_FILE="$SUPERCHARGER_DIR/.update-notice"
UPDATE_NOTICE=""
if [[ -f "$NOTICE_FILE" ]]; then
  UPDATE_NOTICE=$(cat "$NOTICE_FILE" 2>/dev/null || true)
  rm -f "$NOTICE_FILE"
fi

# Launch background check for next session (non-blocking).
if [[ ! -f "$SUPERCHARGER_DIR/.no-update-check" ]]; then
  CACHE_FILE="$SUPERCHARGER_DIR/.update-check"
  NOW=$(date +%s)
  LAST_CHECK=0
  [[ -f "$CACHE_FILE" ]] && LAST_CHECK=$(cat "$CACHE_FILE" 2>/dev/null || echo 0)

  if (( NOW - LAST_CHECK > 86400 )); then
    HOOK_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    (
      REMOTE_UTILS=""
      if command -v curl &>/dev/null; then
        REMOTE_UTILS=$(curl --max-time 5 --silent "https://raw.githubusercontent.com/smrafiz/claude-supercharger/master/lib/utils.sh" 2>/dev/null || true)
      elif command -v wget &>/dev/null; then
        REMOTE_UTILS=$(wget --timeout=5 --quiet -O- "https://raw.githubusercontent.com/smrafiz/claude-supercharger/master/lib/utils.sh" 2>/dev/null || true)
      fi

      if [[ -n "$REMOTE_UTILS" ]]; then
        REMOTE_VERSION=$(echo "$REMOTE_UTILS" | sed -n 's/^VERSION="\(.*\)"/\1/p' || true)
        LOCAL_VERSION=$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$HOOK_SCRIPT_DIR/../lib/utils.sh" 2>/dev/null || true)

        if [[ -n "$REMOTE_VERSION" && -n "$LOCAL_VERSION" && "$REMOTE_VERSION" != "$LOCAL_VERSION" ]]; then
          echo "Supercharger v${REMOTE_VERSION} available (you have v${LOCAL_VERSION}). Run: bash tools/update.sh" > "$NOTICE_FILE"
        fi

        echo "$NOW" > "$CACHE_FILE"
      fi
    ) &
  fi
fi

export UPDATE_NOTICE

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
    parts.append('Detected stack: ' + ', '.join(stack_parts) + '. Use matching conventions.')

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
        if cfg_parts:
            parts.append('Project config: ' + '. '.join(cfg_parts) + '.')
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

update_notice = os.environ.get('UPDATE_NOTICE', '')
if update_notice:
    parts.append(update_notice)

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
