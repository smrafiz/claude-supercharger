#!/usr/bin/env bash
# No file path may be INTERPOLATED into a `python3 -c "..."` block.
#
# The Windows rule, measured on a real runner (docs/WINDOWS-SUPPORT-PLAN.md §13.2):
# MSYS rewrites a path passed as an ARGUMENT into the Windows spelling, and does
# not touch a path baked into the `-c` string. Native Windows python then gets
# `/d/a/repo/hooks/hooks.json` and raises FileNotFoundError.
#
# Every site swallowed that error, so the damage was silent rather than loud:
#   hook-doctor      reported "0 registered hooks" on a healthy Windows install
#   config-health    scored that same install as broken
#   stop-verify      never found a test script, so verification was skipped
#   adaptive-economy ignored a project's autoEconomy:false
# and 40 test sites reported `parse-error` instead of a real assertion.
#
# This is a SCANNER, not a list of known-bad files, because the class kept coming
# back one file at a time — v2.26.8x fixed 14 files, then 6 more, then 27 more.
# A scan cannot be partially applied, which is the whole point.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SCAN="$REPO_DIR/tests/lib-argv-path-scan.py"

echo "=== Interpolated-path (argv) Scan ==="

begin_test "the scanner itself is present and runnable"
[ -f "$SCAN" ] && python3 "$SCAN" --help >/dev/null 2>&1 || true
[ -f "$SCAN" ] && pass || fail "lib-argv-path-scan.py missing"

begin_test "no product script interpolates a path into a python -c block"
OUT=$(python3 "$SCAN" "$REPO_DIR" 2>&1)
if [ -z "$OUT" ]; then pass; else fail "interpolated paths (break on Windows): $OUT"; fi

begin_test "no test script interpolates a path into a python -c block"
OUT=$(python3 "$SCAN" "$REPO_DIR" --tests 2>&1)
if [ -z "$OUT" ]; then pass; else fail "interpolated paths (break on Windows): $OUT"; fi

# A scanner that cannot fail is worse than no scanner — it reports clean forever.
# Build a decoy with the exact shape and require a hit, so a broken regex is
# caught here rather than by the next Windows recon three weeks later.
begin_test "the scanner actually detects the pattern (guard the guard)"
DECOY=$(mktemp -d)
mkdir -p "$DECOY/hooks"
cat > "$DECOY/hooks/decoy.sh" <<'EOF'
#!/usr/bin/env bash
X=$(python3 -c "
import json
d = json.load(open('$SOME_DIR/thing.json'))
print(d)
" 2>/dev/null || echo "")
EOF
HITS=$(python3 "$SCAN" "$DECOY" 2>&1)
rm -rf "$DECOY"
if printf '%s' "$HITS" | grep -q 'decoy.sh'; then pass; else fail "scanner missed a planted site — regex is broken"; fi

# The argv form must NOT be reported, or the scan becomes noise everyone ignores.
begin_test "the scanner does not flag the correct argv form"
DECOY=$(mktemp -d)
mkdir -p "$DECOY/hooks"
cat > "$DECOY/hooks/good.sh" <<'EOF'
#!/usr/bin/env bash
X=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(d)
" "$SOME_DIR/thing.json" 2>/dev/null || echo "")
EOF
HITS=$(python3 "$SCAN" "$DECOY" 2>&1)
rm -rf "$DECOY"
if [ -z "$HITS" ]; then pass; else fail "false positive on the correct form: $HITS"; fi

# --- v4.0.46: the LIST-in-an-env-var sibling ---------------------------------
# Three channels, not two. MSYS converts a path for ARGV and for a SINGLE-path
# env var, but not the entries of a list inside one. That shipped twice: the
# v4.0.44 smart-approve gate, and tools/token-report.sh (sibling of a site
# session-analytics.sh had already fixed by converting the ROOT once).
begin_test "the env-list scanner flags a split path list handed to python"
DECOY=$(mktemp -d); mkdir -p "$DECOY/tools"
cat > "$DECOY/tools/bad.sh" <<'EOF'
#!/usr/bin/env bash
FILES=$(find . -name '*.json')
SC_FILES="$FILES" python3 <<'PY'
import os
for f in os.environ.get('SC_FILES', '').split('\n'):
    if f:
        open(f)
PY
EOF
HITS=$(python3 "$SCAN" "$DECOY" 2>&1)
rm -rf "$DECOY"
printf '%s' "$HITS" | grep -q 'env path LIST' && pass || fail "missed the env path-list form: ${HITS:-<none>}"

# The FP control. A single path in an env var IS converted by MSYS and is
# correct; so is splitting a non-path value. 46 of the tree's 64 env-prefixed
# python3 sites open a path, and flagging those would make the scan noise
# nobody reads — lib/economy.sh splits ACTIVE_ROLES on ',' while opening a
# single-path env var in the same block, and was this rule's one false positive
# before it was narrowed to newline splits.
begin_test "the env-list scanner does NOT flag a single path or a value list"
DECOY=$(mktemp -d); mkdir -p "$DECOY/tools"
cat > "$DECOY/tools/ok.sh" <<'EOF'
#!/usr/bin/env bash
TEMPLATE_FILE="$1" ROLES="a,b,c" python3 <<'PY'
import os
with open(os.environ['TEMPLATE_FILE']) as f:
    body = f.read()
active = [r.strip() for r in os.environ.get('ROLES', '').split(',') if r.strip()]
print(len(body), active)
PY
EOF
HITS=$(python3 "$SCAN" "$DECOY" 2>&1)
rm -rf "$DECOY"
[ -z "$HITS" ] && pass || fail "false positive on a single path / value list: $HITS"

begin_test "a file that converts with cygpath is exempt"
# Converting the entries (or the root they descend from) in bash IS the fix, so
# a file that does it must not stay flagged forever. Proximity-based, and its
# limit is documented in the scanner: it would wrongly exempt a file that
# converts one list and not another.
DECOY=$(mktemp -d); mkdir -p "$DECOY/tools"
cat > "$DECOY/tools/fixed.sh" <<'EOF'
#!/usr/bin/env bash
FILES=$(find . -name '*.json')
if command -v cygpath >/dev/null 2>&1; then FILES=$(cygpath -m "$FILES"); fi
SC_FILES="$FILES" python3 <<'PY'
import os
for f in os.environ.get('SC_FILES', '').split('\n'):
    if f:
        open(f)
PY
EOF
HITS=$(python3 "$SCAN" "$DECOY" 2>&1)
rm -rf "$DECOY"
[ -z "$HITS" ] && pass || fail "flagged a file that already converts: $HITS"

report
