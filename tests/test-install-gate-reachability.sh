#!/usr/bin/env bash
# Install scanners must see the installs that actually get typed (v4.1.9)
#
# Found by auditing the other start-anchored exemptions after v4.1.7 fixed the
# metadata-text one. Two hooks scan package installs, and both missed the same
# two shapes — for two different reasons that compounded:
#
#   1. THE TWO-GATE TRAP. Both hooks open with a cheap substring pre-gate,
#      `case "$_INPUT" in *install*|*add*)`. `npm i <pkg>` contains neither
#      word, so it exited there — while package-credibility.py:29 and both of
#      dep-vuln-scanner's regexes listed `npm i` as supported. The inner rule
#      advertised a form the outer gate forbade, so it was unreachable code.
#
#   2. START ANCHORS. The install regexes were `^\s*`-anchored. Every agent
#      install is a compound (`cd app && npm install x`), so the anchor skipped
#      the normal case and matched only the rare bare command.
#
# Together: `cd app && npm i evil-package` reached NEITHER scanner — wrong verb
# form and wrong position at once.
#
# These assert reachability, not verdicts: whether the scanner RUNS on a given
# command shape. A stub npm records the fact of the audit, so the test needs no
# network and no vulnerable fixture.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Install scanner reachability ==="

scanned() { # command -> "SCANNED" | "skipped"
  local st bin
  st=$(mktemp -d); bin=$(mktemp -d); mkdir -p "$st/scope"
  printf '#!/usr/bin/env bash\necho ran >> "%s/ran.log"\necho "{}"\n' "$st" > "$bin/npm"
  chmod +x "$bin/npm"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$st" \
    | PATH="$bin:$PATH" SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/dep-vuln-scanner.sh" >/dev/null 2>&1
  local r="skipped"; [ -s "$st/ran.log" ] && r="SCANNED"
  rm -rf "$st" "$bin"; printf '%s' "$r"
}

reaches()  { [ "$(scanned "$2")" = "SCANNED" ] && pass || fail "$1: scanner never ran on: $2"; }
ignores()  { [ "$(scanned "$2")" = "skipped" ] && pass || fail "$1: scanner ran on a non-install: $2"; }

begin_test "a bare install is scanned (was already true)"
reaches "bare" "npm install left-pad"

begin_test "a compound install is scanned — the shape agents actually write"
reaches "compound-and" "cd myproject && npm install left-pad"

begin_test "a semicolon-separated install is scanned"
reaches "compound-semi" "cd app; npm install left-pad"

begin_test "the npm i short form reaches the scanner at all"
reaches "short-bare" "npm i left-pad"

begin_test "npm i in a compound reaches the scanner"
reaches "short-compound" "cd app && npm i left-pad"

# The pre-gate stays cheap and the segment anchor stops the obvious false
# positive: prose that merely names an install verb is not an install.
begin_test "an ordinary command is still skipped"
ignores "ordinary" "ls -la"

begin_test "prose mentioning an install verb is not an install"
ignores "prose" "echo npm install in a message"

begin_test "a commit message naming an install verb is not an install"
ignores "commit-prose" "git commit -m 'docs: explain npm install flow'"

# The credibility guard shares the pre-gate, so it shared the blind spot.
# package-credibility.py declares the short form; assert the declaration is
# reachable rather than trusting it.
begin_test "package-credibility regex accepts a compound npm i"
python3 - "$REPO_DIR" <<'PYEOF' && pass || fail "NPM_INSTALL did not match a compound short-form install"
import re, sys, pathlib
src = pathlib.Path(sys.argv[1], "hooks", "package-credibility.py").read_text()
ns = {}
for line in src.splitlines():
    if line.startswith("NPM_INSTALL"):
        exec("import re\n" + line, ns)
        break
sys.exit(0 if ns["NPM_INSTALL"].search("cd app && npm i evil-package") else 1)
PYEOF

begin_test "package-credibility pre-gate admits the short form"
grep -q '"npm i "' "$REPO_DIR/hooks/package-credibility-guard.sh" && pass || fail "pre-gate still forbids npm i, making the regex unreachable"

report
