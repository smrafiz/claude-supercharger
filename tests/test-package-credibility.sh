#!/usr/bin/env bash
# Suite for package-credibility-guard.sh + package-credibility.py (v4.0.4).
#
# Slopsquatting: an LLM names a package that does not exist, someone registers
# it, and the install finds it waiting. The other four supply-chain hooks all
# pass it — it has a normal name, comes from the real registry, and has no CVE
# because nobody has looked at it yet.
#
# EVERY TEST HERE IS OFFLINE. The hook makes registry calls by design, but a
# suite that depends on npmjs.org being reachable is a suite that fails on a
# train. The pure logic (token extraction, verdict thresholds) is tested
# directly, and the shell layer is tested on the paths that never reach curl.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/package-credibility-guard.sh"
PY="$REPO_DIR/hooks/package-credibility.py"

echo "=== package-credibility guard ==="

_run() {  # $1 = command, rest = env assignments -> stdout+stderr
  local cmd="$1"; shift
  local d; d=$(mktemp -d)
  printf '{"cwd":"/tmp","tool_name":"Bash","hook_event_name":"PostToolUse","tool_input":{"command":%s},"tool_response":{"output":"ok"}}' \
    "$(P="$cmd" python3 -c 'import json,os;print(json.dumps(os.environ["P"]))')" \
    | env SUPERCHARGER_STATE="$d" "$@" bash "$HOOK" 2>&1
  rm -rf "$d"
}

begin_test "credibility: silent on a command that is not an install"
[ -z "$(_run 'git add -A')" ] && pass || fail "fired on a non-install command"

begin_test "credibility: silent on a bare install (manifest restore, no names)"
# `npm install` with no arguments restores package.json. There is no
# agent-invented name to check, and hitting the registry for the whole tree
# would be the project-wide crawl this hook deliberately avoids.
[ -z "$(_run 'npm install')" ] && pass || fail "fired on a bare npm install"

begin_test "credibility: kill switch silences it"
[ -z "$(_run 'npm install some-package' SUPERCHARGER_PACKAGE_CREDIBILITY=0)" ] \
  && pass || fail "kill switch did not silence the hook"

begin_test "credibility: minimal profile silences it"
[ -z "$(_run 'npm install some-package' SUPERCHARGER_PROFILE=minimal)" ] \
  && pass || fail "fired under the minimal profile"

begin_test "credibility: fails OPEN when curl is unavailable"
# No network client means no verdict is possible. A supply-chain check that
# blocks or errors when it cannot reach the registry teaches people to disable it.
D=$(mktemp -d); mkdir -p "$D/bin"
for b in bash env python3 jq mktemp rm printf; do
  p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$D/bin/$(basename "$b")" 2>/dev/null
done
OUT=$(printf '{"cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"npm install x"}}' \
  | PATH="$D/bin" SUPERCHARGER_STATE="$D" bash "$HOOK" 2>&1)
[ -z "$OUT" ] && pass || fail "did not fail open without curl: $OUT"
rm -rf "$D"

echo "=== token extraction (pure, no network) ==="

_tokens() {  # $1 = full command -> extracted names, space separated
  P="$1" REPO="$REPO_DIR" python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('pc', os.environ['REPO'] + '/hooks/package-credibility.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
cmd = os.environ['P']
mm = m.NPM_INSTALL.match(cmd) or m.PIP_INSTALL.match(cmd)
print(' '.join(m.tokens(mm.group(1))) if mm else 'NOTINSTALL')
" 2>/dev/null
}

while IFS='|' read -r CMD WANT; do
  [ -z "$CMD" ] && continue
  begin_test "tokens: ${CMD:0:52}"
  GOT=$(_tokens "$CMD")
  [ "$GOT" = "$WANT" ] && pass || fail "got [$GOT], wanted [$WANT]"
done <<'CASES'
npm install express zod|express zod
npm i lodash@4.17.21|lodash
pnpm add @scope/thing|@scope/thing
yarn add react react-dom|react react-dom
npm install --save-dev typescript|typescript
pip install requests==2.31.0|requests
pip3 install flask>=2.0|flask
npm install|
npm install ./local-pkg|
npm install git+https://github.com/o/r.git|
npm install https://example.com/pkg.tgz|
pip3 install ./dist/mypkg.whl|
git add -A|NOTINSTALL
docker install something|NOTINSTALL
CASES

echo "=== verdict thresholds (pure, no network) ==="

_verdict() {  # name age weekly repo
  A="$1" B="$2" C="$3" E="$4" REPO="$REPO_DIR" python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('pc', os.environ['REPO'] + '/hooks/package-credibility.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
age = None if os.environ['B'] == 'none' else int(os.environ['B'])
wk  = None if os.environ['C'] == 'none' else int(os.environ['C'])
repo = None if os.environ['E'] == 'none' else os.environ['E']
print(m.verdict(os.environ['A'], age, wk, repo) or 'SILENT')
" 2>/dev/null
}

begin_test "verdict: old and popular is silent"
[ "$(_verdict pkg 2000 500000 https://github.com/o/r)" = "SILENT" ] && pass || fail "flagged a credible package"

begin_test "verdict: brand new AND barely downloaded is reported"
OUT=$(_verdict pkg 4 6 https://github.com/o/r)
case "$OUT" in *"4 days ago"*|*"6 downloads"*) pass ;; *) fail "did not report: $OUT" ;; esac

begin_test "verdict: no repository link ALONE is not worth mentioning"
# On its own this is too weak a signal — plenty of old, widely used packages
# have no repository field, and a guard that cries wolf gets switched off.
[ "$(_verdict pkg 2000 500000 none)" = "SILENT" ] && pass || fail "flagged on a missing repo alone"

begin_test "verdict: old but no repo AND low downloads is reported"
OUT=$(_verdict pkg 2000 3 none)
case "$OUT" in *"3 downloads"*) pass ;; *) fail "did not report: $OUT" ;; esac

begin_test "verdict: reports the NUMBERS, not a verdict word"
# "suspicious package" is a claim the reader cannot check. The publish date and
# the download count are facts they can judge for themselves.
OUT=$(_verdict pkg 4 6 none)
case "$OUT" in *suspicious*|*malicious*|*dangerous*) fail "editorialised: $OUT" ;; *) pass ;; esac

echo "=== registration ==="

begin_test "credibility: registered on PreToolUse:Bash in the generated artifact"
python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
ok = any('package-credibility-guard' in h.get('command','')
         for e in d['hooks'].get('PreToolUse', []) for h in e.get('hooks', []))
sys.exit(0 if ok else 1)
" "$REPO_DIR/hooks/hooks.json" && pass || fail "not registered in hooks.json"

begin_test "credibility: a flagged package ASKS before the install runs (PreToolUse)"
# The install script is the payload, so a warning after the install is too late.
# Copy the hook with a stub companion that reports one flagged package.
SB=$(mktemp -d)
cp "$REPO_DIR"/hooks/package-credibility-guard.sh "$REPO_DIR"/hooks/lib-*.sh "$SB/"
printf '#!/usr/bin/env python3\nprint("evilpkg: first published 2 days ago, 3 downloads last week")\n' > "$SB/package-credibility.py"
OUT=$(printf '{"cwd":"/tmp","tool_name":"Bash","hook_event_name":"PreToolUse","tool_input":{"command":"npm install evilpkg"}}' \
  | HOME="$SB" SUPERCHARGER_STATE="$SB" bash "$SB/package-credibility-guard.sh" 2>/dev/null)
case "$OUT" in *'"permissionDecision":"ask"'*evilpkg*'2 days ago'*) pass ;; *) fail "no ask: $OUT" ;; esac
rm -rf "$SB"

begin_test "credibility: the python companion ships beside the shell hook"
# The shell hook calls it by path. A deploy that copies only *.sh leaves the
# guard calling a file that is not there — the phantom-deny failure mode.
[ -f "$PY" ] && [ -x "$PY" ] && pass || fail "package-credibility.py missing or not executable"

echo "=== known malware (OSV MAL-), offline: curl is a stub ==="

# _mal <command> -> the companion's output, with curl answering from canned JSON.
# The stub registry: "goodpkg" is old and popular, "newpkg" is 3 days old with 4
# downloads. OSV reports MAL-TEST-1 on version 2.0.1 of both.
_mal() {
  # Stub get() in-process: a PATH curl stub never runs on Windows, where
  # CreateProcess finds System32\curl.exe first (and cannot exec a #!/bin/sh file).
  CMD="$1" PY="$PY" python3 -c '
import importlib.util, json, os, sys, time
spec = importlib.util.spec_from_file_location("pc", os.environ["PY"])
pc = importlib.util.module_from_spec(spec); spec.loader.exec_module(pc)
def get(u, body=None):
    if "api.osv.dev" in u:
        return {"vulns": [{"id": "MAL-TEST-1", "affected": [{"versions": ["2.0.1"]}]}, {"id": "GHSA-x", "affected": []}]}
    if "downloads" in u:
        return {"downloads": 500000 if u.endswith("goodpkg") else 4}
    if u.endswith("registry.npmjs.org/goodpkg"):
        return {"name": "goodpkg", "dist-tags": {"latest": "2.0.2"}, "time": {"created": "2015-01-01T00:00:00Z"}, "repository": {"url": "git+https://x/y"}}
    if u.endswith("registry.npmjs.org/newpkg"):
        return {"name": "newpkg", "dist-tags": {"latest": "0.0.0-stage"}, "time": {"created": time.strftime("%Y-%m-%dT00:00:00Z", time.gmtime())}}
    return {"error": "Not found"}
pc.get = get
pc.main()
' 2>/dev/null
}

while IFS='|' read -r CMD WANT; do
  [ -z "$CMD" ] && continue
  begin_test "malware: ${CMD} -> ${WANT:-silent}"
  GOT=$(_mal "$CMD")
  case "$WANT" in
    '') [ -z "$GOT" ] && pass || fail "expected silence, got [$GOT]" ;;
    *) case "$GOT" in $WANT) pass ;; *) fail "got [$GOT], wanted $WANT" ;; esac ;;
  esac
done <<'CASES'
npm i goodpkg|
npm i goodpkg@2.0.2|
npm i goodpkg@2.0.1|MALWARE: goodpkg@2.0.1 (MAL-TEST-1)
npm i newpkg|MALWARE: newpkg (MAL-TEST-1 on other versions*
npm i express goodpkg@2.0.1|MALWARE: goodpkg@2.0.1*
CASES

begin_test "malware: pins() takes exact versions only, not ranges or tags"
GOT=$(REPO="$REPO_DIR" python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('pc', os.environ['REPO'] + '/hooks/package-credibility.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(sorted(m.pins('a@1.2.3 @s/b@v2.0.0 c@^1.0 d@latest e==3.1 f>=2').items()))
" 2>/dev/null)
[ "$GOT" = "[('@s/b', '2.0.0'), ('a', '1.2.3'), ('e', '3.1')]" ] && pass || fail "got $GOT"

begin_test "malware: a MALWARE report DENIES (exit 2), not asks"
# An ask is auto-approved under /sc-autopilot full; the install script is the payload.
SB=$(mktemp -d)
cp "$REPO_DIR"/hooks/package-credibility-guard.sh "$REPO_DIR"/hooks/lib-*.sh "$SB/"
printf '#!/usr/bin/env python3\nprint("MALWARE: evilpkg@1.0.0 (MAL-TEST-1)")\n' > "$SB/package-credibility.py"
OUT=$(printf '{"cwd":"/tmp","tool_name":"Bash","hook_event_name":"PreToolUse","tool_input":{"command":"npm install evilpkg@1.0.0"}}' \
  | HOME="$SB" SUPERCHARGER_STATE="$SB" bash "$SB/package-credibility-guard.sh" 2>/dev/null); RC=$?
case "$OUT" in *'"permissionDecision":"deny"'*'evilpkg@1.0.0 (MAL-TEST-1)'*) [ "$RC" = 2 ] && pass || fail "deny JSON but rc=$RC" ;; *) fail "no deny: $OUT" ;; esac
rm -rf "$SB"

report
