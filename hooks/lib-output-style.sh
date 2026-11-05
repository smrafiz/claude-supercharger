#!/usr/bin/env bash
# Claude Supercharger — output style follows the minimal tier
# Sourced by install.sh, tools/economy-switch.sh and economy-reinforce.sh (the
# "eco <tier>" phrase): the places where the USER chooses a tier.
# adaptive-economy's automatic switch deliberately does not call it.
#
# Why: economy.md arrives as a user message and does not bind reply length; an
# output style rewrites the system prompt and does (docs/ECONOMY-OUTPUT-STYLE.md,
# ~45% median cut). The built-in "Concise" style is the minimal tier.
#
# Never seizes the slot (docs: "Never seize the output-style slot"):
#   - minimal: sets outputStyle "Concise" in ~/.claude/settings.json only when
#     none is set (absent or "default"), and records that it did. Once recorded
#     it does not set it again, so a user who turns it off stays off.
#   - any other tier: removes it only if WE set it and it is still "Concise".
# A user's own style is never changed or removed. Invalid settings JSON is left
# untouched. Fails open: a failure here never fails the caller.

# sync_output_style <tier>
sync_output_style() {
  local state="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
  SC_TIER="${1:-}" \
  SC_SETTINGS="$HOME/.claude/settings.json" \
  SC_MARK="$state/scope/.output-style-owned" \
  python3 - <<'PY' 2>/dev/null || true
import json, os, sys, tempfile

tier = os.environ['SC_TIER'].strip().lower()
path = os.path.realpath(os.environ['SC_SETTINGS'])  # keep a dotfiles symlink intact
mark = os.environ['SC_MARK']
STYLE = 'Concise'

try:
    with open(path) as f:
        d = json.load(f)
except FileNotFoundError:
    d = {}
if not isinstance(d, dict):
    sys.exit(1)

cur = d.get('outputStyle')
changed = False
if tier == 'minimal':
    # The mark means we already set it once: if the user since changed or
    # cleared it, that choice stands (a reinstall or update must not undo it).
    if not os.path.isfile(mark) and (cur in (None, '') or str(cur).lower() == 'default'):
        d['outputStyle'] = STYLE
        changed = True
        os.makedirs(os.path.dirname(mark), exist_ok=True)
        open(mark, 'w').close()
elif tier and os.path.isfile(mark):
    if cur == STYLE:
        del d['outputStyle']
        changed = True
    os.remove(mark)

if changed:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix='.settings.', suffix='.tmp')
    try:
        if os.path.exists(path):
            os.chmod(tmp, os.stat(path).st_mode & 0o777)
        with os.fdopen(fd, 'w') as f:
            json.dump(d, f, indent=2)
            f.write('\n')
        os.replace(tmp, path)
    except Exception:
        try: os.remove(tmp)
        except OSError: pass
        raise
PY
}
