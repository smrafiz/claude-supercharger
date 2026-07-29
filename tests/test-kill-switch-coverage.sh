#!/usr/bin/env bash
# /sc off must be TOTAL: every registered hook has to honor the global kill-switch.
# A hook honors it by sourcing lib-suppress.sh or lib-timing.sh (both exit at source
# time when the disable flag is present) or by checking the flag itself.
# Structural test — a NEW hook added without the guard fails here, not in the field.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Kill-Switch Coverage Tests ==="

begin_test "every registered hook honors the /sc off kill-switch"
GAPS=$(python3 - "$REPO_DIR" <<'PY'
import json, os, re, sys
repo = sys.argv[1]
d = json.load(open(os.path.join(repo, "hooks", "hooks.json")))
scripts = set()
for entries in d.get("hooks", {}).values():
    for e in entries:
        for h in e.get("hooks", []):
            m = re.search(r'/hooks/([A-Za-z0-9_.-]+\.sh)', h.get("command", ""))
            if m:
                scripts.add(m.group(1))
gaps = []
for s in sorted(scripts):
    p = os.path.join(repo, "hooks", s)
    if not os.path.isfile(p):
        continue
    src = open(p, encoding="utf-8", errors="replace").read()
    if not any(k in src for k in ("lib-suppress.sh", "lib-timing.sh", "supercharger-disabled")):
        gaps.append(s)
print(" ".join(gaps))
PY
)
[ -z "$GAPS" ] && pass || fail "hooks ignoring /sc off: $GAPS"

begin_test "the statusline honors it too (registered under statusLine, not hooks.json)"
grep -qE "lib-suppress|lib-timing|supercharger-disabled" "$REPO_DIR/hooks/statusline.sh" && pass || fail "statusline.sh ignores the kill-switch"

begin_test "with the flag set, a representative hook chain is silent and exits 0"
H=$(mktemp -d); ST="$H/state"; mkdir -p "$ST/scope" "$H/proj"
DIS=".supercharger-""disabled"; printf 'disabled\n' > "$ST/scope/$DIS"
PAY=$(python3 -c 'import json,sys;print(json.dumps({"session_id":"s","tool_name":"Bash","tool_input":{"command":"npm install lodash"},"cwd":sys.argv[1],"prompt":"hi"}))' "$H/proj")
BAD=""
for h in safety.sh path-guard.sh enforce-pkg-manager.sh update-check.sh session-complete.sh notify-stop.sh event-logger.sh; do
  [ -f "$REPO_DIR/hooks/$h" ] || continue
  OUT=$(printf '%s' "$PAY" | SUPERCHARGER_STATE="$ST" SUPERCHARGER_HOME="$REPO_DIR" bash "$REPO_DIR/hooks/$h" 2>/dev/null); RC=$?
  { [ -n "$OUT" ] || [ "$RC" != 0 ]; } && BAD="$BAD $h(rc=$RC)"
done
rm -rf "$H"
[ -z "$BAD" ] && pass || fail "not silent/clean when off:$BAD"

report
