#!/usr/bin/env bash
# Claude Supercharger — Session Start Hook
# Event: SessionStart | Matcher: (none)
# 1. First-run welcome (once ever)
# 2. Auto-detects stack and injects context
# 3. Loads .supercharger.json if present

set -euo pipefail

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

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

# v2.26.42: record the session's LAUNCH directory so path-guard has a stable
# project boundary.
#
# The boundary was read from each payload's `.cwd`, which follows the session's
# working directory — Claude Code emits CwdChanged on a plain `cd`. Open Claude
# in a wrapper directory holding two repos, let cwd move into one of them, and
# the sibling silently becomes "outside the project": writes that worked at the
# start of the session start failing, with nothing announcing why. Reported from
# the field, and confirmed by the reporter watching it happen.
#
# CLAUDE_PROJECT_DIR would be the natural source but is NOT set by this Claude
# Code version (verified — the env carries only CLAUDE_CODE_*, CLAUDE_PID,
# CLAUDE_EFFORT), so we record it ourselves, once, at SessionStart.
#
# Session-scoped: two sessions in different projects must not share a root.
_SR_SID="${CLAUDE_CODE_SESSION_ID:-}"
if [ -n "$_SR_SID" ]; then
  mkdir -p "$SUPERCHARGER_STATE/scope" 2>/dev/null || true
  _SR_FILE="$SUPERCHARGER_STATE/scope/.session-root-$_SR_SID"
  # Write once. SessionStart also fires on resume/compact, and by then cwd may
  # already have moved — overwriting would defeat the whole point.
  [ -f "$_SR_FILE" ] || printf '%s\n' "$PROJECT_DIR" > "$_SR_FILE" 2>/dev/null || true
fi

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

# Derive the scope key HERE and hand python the key, not just the path.
#
# Both channels ran the same algorithm on different INPUTS. PROJECT_DIR crosses
# as an env var, and MSYS rewrites a single-path env var in transit, so a POSIX
# cwd reached python respelled: bash keyed 'Users-me-proj' while python keyed
# 'C:-Program Files-Git-Users-me-proj' off the same project. The writer and the
# readers then used different scope files and every per-project setting —
# profile, disabled-hooks, allowPatterns, customPatterns — silently did nothing.
#
# A key has no slashes left to rewrite, so it crosses unchanged. This also
# retires the "MUST match byte for byte" duplication below: two copies of an
# algorithm agreeing by discipline is the cross-channel parity drift this repo
# keeps rediscovering. python still keeps its own copy as a fallback for
# callers that do not set the variable.
SC_PROJECT_KEY=""
if command -v sc_project_key >/dev/null 2>&1; then
  sc_project_key "$PROJECT_DIR"
fi

RESULT=$(CONFIG_FILE="$CONFIG_FILE" PROJECT_DIR="$PROJECT_DIR" SC_PROJECT_KEY="$SC_PROJECT_KEY" WELCOME_FLAG="$WELCOME_FLAG" LIB_DIR="$LIB_DIR" SUPERCHARGER_STATE="$SUPERCHARGER_STATE" python3 << 'PYEOF'
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
    os.environ.get('SUPERCHARGER_STATE') or os.path.join((os.environ.get('HOME') or os.path.expanduser('~')), '.claude', 'supercharger'),
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

# v2.26.33: these four files hold PER-PROJECT values but were written to one
# global path, so two projects open at once overwrote each other — a project with
# no `profile` key os.remove()d another project's, and a `budget` set in one
# silently capped the other. Keyed by project path now.
#
# MUST match sc_project_key() in hooks/lib-paths.sh byte for byte, or the writer
# and the readers disagree and the config silently does nothing.
def _project_key(pdir):
    # Prefer the key bash already derived. It arrives as a plain token with no
    # separators left, so MSYS cannot respell it in transit the way it respells
    # PROJECT_DIR — which is exactly how the two channels came to key the same
    # project differently on Windows.
    supplied = os.environ.get('SC_PROJECT_KEY', '')
    if supplied:
        return supplied
    # Fallback for callers that do not set it. Kept byte-identical to
    # sc_project_key in hooks/lib-paths.sh; a disagreement means one channel
    # writes a file the other never reads.
    # v2.26.83: '\\' and ':' folded for Windows payload cwds (C:\Users\...), which
    # carry no '/' to fold and are illegal in an NTFS filename. See lib-paths.sh.
    k = (pdir or '/').replace('/', '-').replace('\\', '-').replace(':', '-')
    if k.startswith('-'):
        k = k[1:]
    if len(k) > 100:
        k = k[-100:]
    return k or 'root'

def _scope(name):
    return os.path.join(_SCOPE, name + '-' + _project_key(project_dir))

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
                    budget_file = _scope('.budget-cap')
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
        disabled_file = _scope('.disabled-hooks')
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
        profile_file = _scope('.profile')
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
        # Bounded: 50 patterns, 200 chars each. A runaway config must not turn every
        # Bash call into an unbounded regex. Newlines are stripped because the file
        # is line-based, exactly like the block ledger.
        #
        # Validated with GREP, not python's re — they are different dialects, and
        # grep is what actually evaluates these. (`foo[unclosed` is rejected by both,
        # but POSIX classes like [[:space:]] and python-only escapes diverge, so
        # testing with the wrong engine would pass patterns that then fail at match
        # time.)
        #
        # Reported HERE rather than in safety.sh because safety.sh only reaches the
        # pattern code for commands that survive its fast path — a user with a typo
        # could go a whole session without ever seeing the warning, believing a rule
        # is in force when it is not. This runs once, at SessionStart.
        #
        # v2.26.34: shared by customPatterns and allowPatterns. Two copies of a
        # validator drift, and a drifted validator on the ALLOW side would be a
        # security bug rather than a cosmetic one.
        import subprocess

        def _validated_patterns(raw):
            cleaned = []
            for c in raw[:50]:
                if not isinstance(c, str):
                    continue
                c = c.replace('\n', ' ').replace('\r', ' ').strip()[:200]
                if c:
                    cleaned.append(c)
            good, bad = [], []
            for c in cleaned:
                try:
                    rc = subprocess.run(['grep', '-qiE', c], input=b'',
                                        stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL).returncode
                except Exception:
                    rc = 2
                (good if rc in (0, 1) else bad).append(c)
            return good, bad

        def _write_patterns(path, patterns):
            if patterns:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, 'w') as f:
                    f.write('\n'.join(patterns) + '\n')
            elif os.path.isfile(path):
                os.remove(path)

        custom = config.get('customPatterns', [])
        # v2.26.34: keyed per project. This was the last config file still written to
        # a shared global path after v2.26.33 — one project's extra block rules
        # applied to every project, which is the tightening direction and so shows up
        # as unexplained false positives somewhere else entirely.
        pat_file = _scope('.custom-patterns')
        if isinstance(custom, list):
            clean, invalid = _validated_patterns(custom)
            if invalid:
                cfg_parts.append(
                    'INVALID customPatterns (not active): ' + ', '.join(invalid[:3]))
            _write_patterns(pat_file, clean)
            if clean:
                cfg_parts.append(f'Custom patterns: {len(clean)}')
        elif os.path.isfile(pat_file):
            os.remove(pat_file)

        # Per-project ALLOW patterns (v2.26.34). The counterpart customPatterns
        # deliberately did not have — a project may now exempt a specific command
        # from a category block instead of switching the whole category off.
        #
        # This LOOSENS, so the boundary is drawn tightly and stated here:
        #   * it only affects safety.sh's category blocks — exactly the surface
        #     `disableSecurityCategories` already turns off wholesale, so an allow
        #     pattern can never permit something the existing config could not
        #     already permit more bluntly. It is strictly the narrower tool.
        #   * it can NEVER exempt a self-modification block. allowPatterns lives in
        #     .supercharger.json, which the selfmod rule protects; a pattern able to
        #     exempt selfmod could authorise edits to the very file that grants it
        #     that power. safety.sh enforces this, not just this comment.
        #   * git-safety, path-guard and harness-tamper-guard are untouched — the
        #     human-approval floor is not negotiable from a config file.
        # Every exemption is written to the block ledger, so it stays visible in
        # /why and the [BLOCKS] summary rather than silently widening the guard.
        allow = config.get('allowPatterns', [])
        allow_file = _scope('.allow-patterns')
        if isinstance(allow, list):
            ok, bad = _validated_patterns(allow)
            if bad:
                cfg_parts.append(
                    'INVALID allowPatterns (not active): ' + ', '.join(bad[:3]))
            _write_patterns(allow_file, ok)
            if ok:
                cfg_parts.append(f'Allow patterns: {len(ok)}')
        elif os.path.isfile(allow_file):
            os.remove(allow_file)

        # Per-project security category toggles
        disabled_cats = config.get('disableSecurityCategories', [])
        cats_file = _scope('.disabled-security-categories')
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
        economy_md = os.path.join((os.environ.get('HOME') or os.path.expanduser('~')), '.claude', 'rules', 'economy.md')
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
cost_file = os.path.join((os.environ.get('HOME') or os.path.expanduser('~')), '.claude', 'supercharger', '.last-session-cost')
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
