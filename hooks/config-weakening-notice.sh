#!/usr/bin/env bash
# Claude Supercharger — Config Weakening Notice
# Event: CwdChanged | Matcher: (none)
#
# Entering a directory whose `.supercharger.json` disables security categories or
# hooks is a guardrail change nobody reviewed — the config arrives with the branch,
# the clone, or the worktree, not with a decision. path-guard stops the AGENT from
# writing these files (path-guard.sh:216); nothing covered them arriving this way.
#
# This does NOT block. A repo carrying its own config is ordinary and legitimate,
# and a guard that fought it would be wrong. What was missing is that the change was
# silent; this says it out loud, once, at the moment you arrive.
#
# On CwdChanged, deliberately NOT WorktreeCreate. Worktree* are PROVIDER events —
# Claude Code delegates worktree creation to a hook registered there and requires a
# path back, so a passive hook breaks `isolation: worktree` for every agent. That
# was shipped and reverted in v2.7.26→.27, and test-install.sh:242 guards it.
# CwdChanged also covers strictly more: any cd into any repo, not just a new worktree.
set -euo pipefail

# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true

_INPUT=$(cat)

CWD=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('cwd') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -n "$CWD" ] || exit 0
[ -f "$CWD/.supercharger.json" ] || exit 0

CWD="$CWD" python3 <<'PY' 2>/dev/null || exit 0
import json, os, sys

root = os.environ['CWD']
path = os.path.join(root, '.supercharger.json')
try:
    with open(path) as f:
        cfg = json.load(f)
except Exception:
    # Malformed config is project-config's problem to report, not this hook's. Two
    # differently worded complaints about one file is worse than one.
    sys.exit(0)
if not isinstance(cfg, dict):
    sys.exit(0)

notes = []
cats = cfg.get('disableSecurityCategories')
if isinstance(cats, list) and cats:
    notes.append('security categories off: ' + ', '.join(str(c) for c in cats[:6]))
hooks_off = cfg.get('disableHooks')
if isinstance(hooks_off, list) and hooks_off:
    notes.append('hooks off: ' + ', '.join(str(h) for h in hooks_off[:6]))

if not notes:
    sys.exit(0)

msg = ('[CONFIG] ' + (os.path.basename(root.rstrip('/')) or root) +
       ' carries a .supercharger.json that weakens guards — ' + '; '.join(notes) +
       '. It came with the directory, not from a choice you made here.')
print(json.dumps({'systemMessage': msg, 'suppressOutput': True}))
PY
exit 0
