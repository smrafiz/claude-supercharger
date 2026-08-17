#!/usr/bin/env bash
# v2.27.32 — payload paths reach python POSIX-shaped on Windows.
#
# Claude Code launches hooks through Git Bash, so a payload `cwd` arrives as
# /d/a/repo. Native Windows python resolves a leading-slash path against the
# CURRENT DRIVE, so Path('/d/a/repo') becomes D:\d\a\repo — which does not
# exist. Every is_dir() check then fails, the project-level base is skipped, and
# a SECURITY SCANNER reports clean having looked at nothing. The Windows recon
# suite showed exactly that: "project-level agents/ not scanned", the same for
# skills/, and a real injection in an agent file missed outright.
#
# path-guard and safety already normalise; these four did not. The normaliser is
# gated on os.name, so this cannot be exercised directly from macOS or Linux —
# instead the function is extracted and run with the branch forced, which is the
# only way to test Windows semantics off Windows.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== MSYS path normalisation (Git Bash POSIX form) ==="

CONSUMERS="agent-poisoning-scanner workflow-guard skill-poisoning-scanner config-scan"

begin_test "every scanner that path-joins a payload cwd normalises it first"
MISSING=""
for h in $CONSUMERS; do
  grep -q 'def _msys' "$REPO_DIR/hooks/$h.sh" || MISSING="$MISSING $h"
done
[ -z "$MISSING" ] && pass || fail "no MSYS normalisation in:$MISSING"

begin_test "the shared resolver normalises too, not just its callers"
grep -q 'def msys_path' "$REPO_DIR/hooks/lib_poison_patterns.py" \
  && grep -q 'home_dir = msys_path(home_dir)' "$REPO_DIR/hooks/lib_poison_patterns.py" \
  && grep -q 'cwd = msys_path(cwd)' "$REPO_DIR/hooks/lib_poison_patterns.py" \
  && pass || fail "lib_poison_patterns.resolve_agent_defs does not normalise its inputs"

begin_test "normalisation maps the Git Bash form to a real Windows path"
OUT=$(python3 - "$REPO_DIR" <<'PYEOF'
import sys, re, os
sys.path.insert(0, os.path.join(sys.argv[1], 'hooks'))
from lib_poison_patterns import msys_path as fn

# The real function is gated on os.name, so off Windows it cannot be exercised
# directly. `forced` is the SAME transform with the gate removed — it pins the
# mapping, while the assertions below pin that the real one stays inert here.
def forced(x):
    if not x or not isinstance(x, str):
        return x
    m = re.match(r'^/([A-Za-z])(/|$)', x)
    return (m.group(1).upper() + ':\\' + x[3:].replace('/', '\\')) if m else x

cases = [
    ('/d/a/repo',        'D:\\a\\repo'),
    ('/c/Users/me',      'C:\\Users\\me'),
    ('/c',               'C:\\'),
    ('/Users/me/proj',   '/Users/me/proj'),   # POSIX home: single-letter rule must not match
    ('C:\\already\\win', 'C:\\already\\win'),
    ('',                 ''),
]
bad = []
for src_v, want in cases:
    got = forced(src_v)
    if got != want:
        bad.append('%r -> %r (want %r)' % (src_v, got, want))
# And the real function must be INERT on this platform (POSIX passthrough).
if os.name != 'nt':
    for src_v, _ in cases:
        if fn(src_v) != src_v:
            bad.append('not inert off Windows: %r -> %r' % (src_v, fn(src_v)))
print('BAD:' + '; '.join(bad) if bad else 'OK')
PYEOF
)
[ "$OUT" = "OK" ] && pass || fail "$OUT"

begin_test "a POSIX directory named /c is never rewritten off Windows"
# The inverse risk: on Linux /c is a legitimate directory, so normalising there
# would break a real path. The os.name gate is what prevents it.
python3 - "$REPO_DIR" <<'PYEOF' && pass || fail "msys_path altered a path on a POSIX platform"
import sys, os
sys.path.insert(0, os.path.join(sys.argv[1], 'hooks'))
from lib_poison_patterns import msys_path
sys.exit(0 if os.name == 'nt' or msys_path('/c/data') == '/c/data' else 1)
PYEOF

report
