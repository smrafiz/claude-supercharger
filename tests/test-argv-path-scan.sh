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

report
