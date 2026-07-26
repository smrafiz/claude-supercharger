#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== lib_code_patterns.scan_content Tests ==="

# Drive the shared module directly through python; each case prints PASS/FAIL.
OUT=$(HOOKS_DIR="$REPO_DIR/hooks" python3 <<'PY'
import os, sys
sys.path.insert(0, os.environ["HOOKS_DIR"])
import lib_code_patterns as L

def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)

check("empty content -> no hits", L.scan_content("") == [])
check("clean code -> no hits", L.scan_content("def add(a,b):\n return a+b") == [])
check("eval flagged", any("eval()" in h for h in L.scan_content("eval(userInput)")))
check("pickle flagged", any("pickle" in h for h in L.scan_content("pickle.loads(data)")))
check("php unserialize flagged", any("unserialize" in h for h in L.scan_content("$x = unserialize($d);")))
check("results de-duplicated", len(L.scan_content("eval(a)\neval(b)\neval(c)")) == 1)
check("Math.random gated: benign non-secret", L.scan_content("const j = Math.random()*100;") == [])
check("Math.random gated: near token -> flagged", any("cryptographically" in h for h in L.scan_content("const token = Math.random();")))
check("python random gated: near secret -> flagged", any("secrets module" in h for h in L.scan_content("otp = random.randint(0,9)")))
PY
)
while IFS= read -r line; do
  [ -z "$line" ] && continue
  begin_test "${line#* }"
  case "$line" in PASS*) pass ;; *) fail "$line" ;; esac
done <<< "$OUT"

report
