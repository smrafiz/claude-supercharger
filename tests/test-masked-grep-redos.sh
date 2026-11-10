#!/usr/bin/env bash
# _MASKED_GREP_RE backtracked exponentially (2026-11-09): a quote could start a quoted
# string or stand alone, so each quoted word after a grep doubled the paths. Inside C
# the 0.5s watchdog cannot run, so safety.sh hung and the command ran unguarded.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== masked-grep regex: no exponential backtracking ==="

for f in safety-detect.py env-file-detect.py; do
  begin_test "$f: 40 quoted words after a grep finish in under 5s"
  out=$(F="$REPO_DIR/hooks/$f" python3 -I -c '
import os, re, subprocess, sys
src = open(os.environ["F"]).read()
m = re.search(r"_MASKED_GREP_RE = re\.compile\(\n((?:    r\"\"\".*\"\"\"\n)+)", src)
rx = re.compile(eval("(" + m.group(1) + ")"))
code = "import re,sys; re.compile(sys.argv[1]).search(sys.argv[2])"
s = "grep x " + "\x27a\x27 " * 40 + "| cat"
try:
    subprocess.run([sys.executable, "-c", code, rx.pattern, s], timeout=5)
    print("ok")
except subprocess.TimeoutExpired:
    print("timeout")
' 2>&1)
  [ "$out" = ok ] && pass || fail "got: $out"
done

report
