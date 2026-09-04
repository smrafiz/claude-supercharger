#!/usr/bin/env bash
# Claude Supercharger — Skill Integrity Guard
# Event: PreToolUse | Matcher: Skill
#
# skill-poisoning-scanner asks "does this look malicious?" — a fixed pattern
# list. Nothing asked "is this the same file as last time?". The two catch
# different things: a skill that passes the pattern scan today passes it
# tomorrow, after an upstream edit, a marketplace pull, or a local rewrite. A
# skill is instructions Claude follows, so a silent edit to one is a persistent
# behaviour change with no event anywhere.
#
# Trust on first use, like known_hosts: record the hash the first time a skill
# loads, ask when it changes. No lockfile is authored by hand — a curation step
# nobody performs is a guard nobody has.
#
# Honest severity: this is a detection gap, not a live bypass. It buys the case
# where content changed AND the change looks benign to the pattern scanner.
# Disable: SUPERCHARGER_SKILL_LOCK=0
set -uo pipefail

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
_SC_STATE="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"

[ "${SUPERCHARGER_SKILL_LOCK:-1}" = "0" ] && exit 0
check_hook_disabled "skill-integrity-guard" && exit 0

# v2.26.35: fork-free stdin read (no $(cat) fork).
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""
_INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# Fast path: bail with zero forks unless the payload names a skill.
case "$_INPUT" in *'"skill"'*) ;; *) exit 0 ;; esac

RESULT=$(HOOK_INPUT="$_INPUT" HOME_DIR="$HOME" PWD_DIR="$PWD" \
         SC_LOCK="$_SC_STATE/scope/.skills-lock" HOOKS_DIR_PY="$HOOKS_DIR" \
         python3 <<'PYEOF' 2>/dev/null
import hashlib, json, os, re, sys, datetime


def _msys(x):
    # Duplicated from lib_skill_resolve deliberately: it is needed to FIND that
    # module, so it cannot be imported from it. HOOKS_DIR_PY is a custom env
    # var, MSYS only rewrites the ones it recognises, and Windows python
    # resolves the POSIX form against the current drive — so without this the
    # import fails SILENTLY and the guard becomes a no-op. That is v2.27.33.
    if os.name != 'nt' or not x or not isinstance(x, str):
        return x
    m = re.match(r'^/([A-Za-z])(/|$)', x)
    return (m.group(1).upper() + ':\\' + x[3:].replace('/', '\\')) if m else x


sys.path.insert(0, _msys(os.environ.get('HOOKS_DIR_PY', '')))
try:
    from lib_skill_resolve import resolve_skill_paths
except Exception:
    # The shared resolver is the only resolver. Nothing was inspected, so say
    # nothing — do not report a clean comparison that did not happen.
    sys.exit(0)

try:
    payload = json.loads(os.environ.get('HOOK_INPUT') or '{}')
except Exception:
    sys.exit(0)

skill = (payload.get('tool_input') or {}).get('skill') or ''
if not skill:
    sys.exit(0)

paths = resolve_skill_paths(skill, os.environ.get('HOME_DIR', ''),
                            payload.get('cwd') or os.environ.get('PWD_DIR', ''))
if not paths:
    # Nothing on disk to hash. skill-poisoning-scanner reaches the same verdict
    # here; it is a pre-existing unscannable condition, not a change.
    sys.exit(0)

lock_path = os.environ['SC_LOCK']
try:
    with open(lock_path) as fh:
        lock = json.load(fh)
    if not isinstance(lock, dict):
        lock = {}
except Exception:
    lock = {}
skills = lock.setdefault('skills', {})
if not isinstance(skills, dict):
    skills = lock['skills'] = {}

changed, unreadable = [], []
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

for p in paths:
    key = str(p.resolve())
    try:
        digest = hashlib.sha256(p.read_bytes()).hexdigest()
    except Exception:
        # Present but unreadable. NOT the same verdict as unchanged: the file
        # exists and was not compared. v4.0.26, artifact-publish-guard — the
        # error path and the all-clear path must not share an exit.
        unreadable.append(p.name)
        continue
    prior = skills.get(key)
    prior_hash = prior.get('sha256') if isinstance(prior, dict) else None
    if prior_hash is None:
        skills[key] = {'sha256': digest, 'firstSeen': now}
    elif prior_hash != digest:
        changed.append([p.name, key, prior_hash, digest])
        # Rebaseline now: approving once should not ask again for the same
        # content, and declining does not run the skill anyway.
        skills[key] = {'sha256': digest, 'firstSeen': prior.get('firstSeen', now)}

try:
    os.makedirs(os.path.dirname(lock_path), exist_ok=True)
    tmp = lock_path + '.tmp'
    with open(tmp, 'w') as fh:
        json.dump(lock, fh, indent=2, sort_keys=True)
    os.replace(tmp, lock_path)
except Exception:
    # A lock we cannot persist means no baseline for next time. Do not turn that
    # into a prompt — the comparison for THIS load already happened.
    pass

print(json.dumps({'changed': changed, 'unreadable': unreadable}))
PYEOF
) || exit 0

[ -z "$RESULT" ] && exit 0
exit 0
