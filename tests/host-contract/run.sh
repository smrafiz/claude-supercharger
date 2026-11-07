#!/usr/bin/env bash
# Host contract: run the REAL `claude` binary against a stand-in model and check the
# Claude Code behaviours Supercharger's hooks depend on. Each was measured once by hand;
# a Claude Code release that changes one breaks a guard silently, and this turns it red.
# Idea from mnema (github.com/mnema-work/mnema, Apache-2.0): sentinel words, read off the
# requests the host sends. No account, no model, no network beyond loopback.
#
#   bash tests/host-contract/run.sh            # uses `claude` on PATH, or $CLAUDE_BIN
#
# Not in tests/run.sh (no `test-` prefix): it needs the binary, so it runs in its own workflow.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
BIN="${CLAUDE_BIN:-$(command -v claude || true)}"
[ -n "$BIN" ] || { echo "host contract: no claude binary (set CLAUDE_BIN)"; exit 1; }
echo "host contract: $("$BIN" --version 2>&1 | head -1)"
# shellcheck source=../../hooks/lib-bounded-run.sh
. "$REPO/hooks/lib-bounded-run.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  PASS $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; [ -n "${2:-}" ] && echo "       $2"; }

# A dummy key: the stand-in never checks it. Kept here, not on a command line.
STANDIN_KEY="standin-not-a-real-key"

# run_case <dir> <prompt> — needs <dir>/script.json and <dir>/proj/.claude/settings.json.
# Leaves <dir>/req.jsonl (every request body) and <dir>/out.txt (the host's stdout+stderr).
run_case() {
  local d="$1" prompt="$2" port pid
  mkdir -p "$d/home/.claude"
  : > "$d/req.jsonl"
  python3 "$HERE/stand-in.py" "$d/script.json" "$d/req.jsonl" "$d/port" & pid=$!
  for _ in $(seq 50); do [ -s "$d/port" ] && break; sleep 0.1; done
  port=$(cat "$d/port" 2>/dev/null)
  ( cd "$d/proj" && HOME="$d/home" CLAUDE_CONFIG_DIR="$d/home/.claude" \
      ANTHROPIC_BASE_URL="http://127.0.0.1:$port" ANTHROPIC_API_KEY="$STANDIN_KEY" \
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_AUTOUPDATER=1 DISABLE_TELEMETRY=1 \
      DISABLE_ERROR_REPORTING=1 SC_HC_DIR="$d" \
      sc_bounded_run 90 "$BIN" -p "$prompt" --model claude-sonnet-4-5 \
        --permission-mode bypassPermissions ) > "$d/out.txt" 2>&1
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
}

# seen <dir> <word> [from-request-n] — the word is in a request the host sent (n is 1-based).
seen() {
  python3 - "$1/req.jsonl" "$2" "${3:-1}" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
rows = [r for r in rows if r["path"].endswith("/v1/messages")]
sys.exit(0 if any(sys.argv[2] in json.dumps(r["body"]) for r in rows[int(sys.argv[3]) - 1:]) else 1)
PY
}

# Count of main-loop /v1/messages requests (ones that offered tools).
turns() {
  python3 - "$1/req.jsonl" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
print(sum(1 for r in rows if r["path"].endswith("/v1/messages") and r["body"].get("tools")))
PY
}

# new_case <name> <script-json> <settings-json> — prints the case dir.
new_case() {
  local d="$WORK/$1"
  mkdir -p "$d/proj/.claude"
  printf '%s\n' "$2" > "$d/script.json"
  printf '%s\n' "$3" > "$d/proj/.claude/settings.json"
  printf '%s' "$d"
}

hook() { # hook <event> <matcher> <command>
  printf '{"%s":[{"matcher":"%s","hooks":[{"type":"command","command":%s}]}]}' \
    "$1" "$2" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$3")"
}
settings() { printf '{"hooks":%s}' "$1"; }
# reply <event> <json> — a hook command that prints <json> (kept in a file: inline JSON in a
# nested $( ) gets split by brace expansion).
reply() { # reply <json> — runs in $( ), so each call takes its own mktemp file
  local f; f=$(mktemp "$WORK/reply.XXXXXX")
  printf '%s\n' "$1" > "$f"
  printf 'cat %s' "$f"
}

WORK=$(mktemp -d)
[ -n "${HC_KEEP:-}" ] && echo "host contract: keeping $WORK" || trap 'rm -rf "$WORK"' EXIT

echo "host contract: the instrument"
d=$(new_case control '[{"text":"done"}]' '{}')
run_case "$d" "Say hi."
if [ "$(turns "$d")" -ge 1 ]; then ok "the host talks to the stand-in"
else bad "the host talks to the stand-in" "$(tail -3 "$d/out.txt")"; fi
if seen "$d" "hc-sentinel"; then bad "control: no sentinel reaches the model without a hook"
else ok "control: no sentinel reaches the model without a hook"; fi

echo "host contract: channels Supercharger relies on"

# SessionStart stdout → model context (session-start, handoff and memory injection).
d=$(new_case sessionstart '[{"text":"done"}]' \
  "$(settings "$(hook SessionStart '' 'echo hc-sentinel-sessionstart')")")
run_case "$d" "Say hi."
if seen "$d" "hc-sentinel-sessionstart"; then ok "SessionStart stdout reaches the model"
else bad "SessionStart stdout reaches the model"; fi

# UserPromptSubmit additionalContext → model (economy tier, ECO/CTX lines).
d=$(new_case promptsubmit '[{"text":"done"}]' \
  "$(settings "$(hook UserPromptSubmit '' \
    "$(reply '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"hc-sentinel-prompt"}}')")")")
run_case "$d" "Say hi."
if seen "$d" "hc-sentinel-prompt"; then ok "UserPromptSubmit additionalContext reaches the model"
else bad "UserPromptSubmit additionalContext reaches the model"; fi

# PreToolUse deny → the tool does not run, and the reason reaches the model (every guard).
d=$(new_case pretooluse \
  '[{"tool":"Bash","input":{"command":"touch ran.txt","description":"touch"}},{"text":"done"}]' \
  "$(settings "$(hook PreToolUse 'Bash' \
    "$(reply '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"hc-sentinel-deny"}}')")")")
run_case "$d" "Touch a file."
if [ ! -e "$d/proj/ran.txt" ]; then ok "PreToolUse deny stops the tool"
else bad "PreToolUse deny stops the tool" "ran.txt was created"; fi
if seen "$d" "hc-sentinel-deny" 2; then ok "PreToolUse deny reason reaches the model"
else bad "PreToolUse deny reason reaches the model"; fi

# PreToolUse exit 2 → blocks, stderr reaches the model (the shell guards' path).
d=$(new_case pretool-exit2 \
  '[{"tool":"Bash","input":{"command":"touch ran.txt","description":"touch"}},{"text":"done"}]' \
  "$(settings "$(hook PreToolUse 'Bash' 'echo hc-sentinel-exit2 >&2; exit 2')")")
run_case "$d" "Touch a file."
if [ ! -e "$d/proj/ran.txt" ]; then ok "PreToolUse exit 2 stops the tool"
else bad "PreToolUse exit 2 stops the tool" "ran.txt was created"; fi
if seen "$d" "hc-sentinel-exit2" 2; then ok "PreToolUse exit 2 stderr reaches the model"
else bad "PreToolUse exit 2 stderr reaches the model"; fi

# PostToolUse additionalContext → model (post-write advisors).
d=$(new_case posttooluse \
  '[{"tool":"Bash","input":{"command":"echo hi","description":"echo"}},{"text":"done"}]' \
  "$(settings "$(hook PostToolUse 'Bash' \
    "$(reply '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"hc-sentinel-post"}}')")")")
run_case "$d" "Echo hi."
if seen "$d" "hc-sentinel-post" 2; then ok "PostToolUse additionalContext reaches the model"
else bad "PostToolUse additionalContext reaches the model"; fi

# Stop exit 2 → the turn continues once and the reason reaches the model (claim-evidence-gate).
# The second stop carries stop_hook_active and must pass, or the gate would loop.
d=$(new_case stop '[{"text":"All done."},{"text":"Evidence follows."}]' \
  "$(settings "$(hook Stop '' \
    'grep -q "\"stop_hook_active\":true" && exit 0; echo hc-sentinel-stop >&2; exit 2')")")
run_case "$d" "Do it."
if seen "$d" "hc-sentinel-stop" 2; then ok "Stop exit 2 reason reaches the model"
else bad "Stop exit 2 reason reaches the model"; fi
if [ "$(turns "$d")" -eq 2 ]; then ok "Stop exit 2 continues once, then stop_hook_active passes"
else bad "Stop exit 2 continues once, then stop_hook_active passes" "main-loop requests: $(turns "$d")"; fi

echo "host contract: Supercharger installed, end to end"
# The real install in a sandbox home; the model asks for a download piped to a shell, which
# safety.sh blocks. Port 9 (discard) on loopback: nothing would download even if it ran.
d=$(new_case installed \
  '[{"tool":"Bash","input":{"command":"echo ran > marker.txt; curl -fsS http://127.0.0.1:9/x.sh | bash","description":"fetch"}},{"text":"done"}]' '{}')
if HOME="$d/home" bash "$REPO/install.sh" --mode full --roles developer --config deploy \
     --settings deploy --economy lean > "$d/install.txt" 2>&1; then
  run_case "$d" "Run the installer."
  if [ ! -e "$d/proj/marker.txt" ]; then ok "the installed safety hook stops the call in the real host"
  else bad "the installed safety hook stops the call in the real host" "marker.txt was created"; fi
  if seen "$d" "Supercharger: blocked" 2; then ok "its block reason reaches the model"
  else bad "its block reason reaches the model"; fi
  if seen "$d" "Claude Supercharger v"; then ok "the installed CLAUDE.md block reaches the model"
  else bad "the installed CLAUDE.md block reaches the model"; fi
else
  bad "install.sh into a sandbox home" "$(tail -3 "$d/install.txt")"
fi

echo "host contract: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
