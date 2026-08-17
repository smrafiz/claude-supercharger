#!/usr/bin/env bash
# Claude Supercharger — Tool History Tracker
# Event: PostToolUse | Matcher: (none, runs on every tool)
# Appends a JSONL entry per tool call to ~/.claude/supercharger/scope/.tool-history-<session_id>.
# Per-session file prevents cross-session data leakage when multiple Claude
# windows run concurrently. Consumed by confidence-gate.sh. Auto-trimmed to last 20 entries.
# Disable: SUPERCHARGER_CONFIDENCE=0

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_CONFIDENCE:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
SCOPE_DIR="$SUPERCHARGER_STATE/scope"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

# v2.27.27: fork-free fast path for the SUCCESS case, which is almost every call.
# This hook cannot be pre-gated — confidence-gate needs every call recorded — so
# the python fork below was paid on EVERY PostToolUse, for every tool, measured
# at 42ms against a 2ms floor and the most expensive hook on the chain.
#
# The split is deliberately lopsided. The fast path handles only payloads that
# are unambiguously successful and plainly shaped; ANYTHING failure-shaped or
# unusual falls through to the python below, which stays the authority. The
# marker test is a fail-safe SUPERSET of python's failure logic (interrupted,
# either error key, and every stderr marker it greps), tested against the WHOLE
# payload rather than the extracted stderr — so a marker anywhere, even in a
# command string or in ordinary output, costs one python fork and the exact
# answer. Only the total absence of any of them takes the shortcut.
#
# Extraction refuses rather than guesses: a key that is absent, that occurs
# twice, whose value carries a backslash escape, or that runs past 200 chars
# hands back to python. `#` and `%%` are single scans and stay linear on a large
# payload; `//` is used ONLY on the already-bounded session id.
_THK_VAL=""
_thk_str() { # $1=key -> _THK_VAL. rc 0 ok, 1 not confident, 2 key absent
  local key="$1" rest after val
  _THK_VAL=""
  rest="${_INPUT#*\"$key\":}"
  [ "$rest" = "$_INPUT" ] && return 2
  case "$rest" in *"\"$key\":"*) return 1 ;; esac
  after="${rest#"${rest%%[![:space:]]*}"}"
  case "$after" in \"*) after="${after#\"}" ;; *) return 1 ;; esac
  val="${after%%\"*}"
  case "$val" in *\\*) return 1 ;; esac
  [ "${#val}" -gt 200 ] && return 1
  _THK_VAL="$val"
  return 0
}

RESULT=""
_thk_fast=0
case "$_INPUT" in
  '{'*'}')
    case "$_INPUT" in
      *'"interrupted": true'*|*'"interrupted":true'*|*'"error"'*|\
      *'command not found'*|*'Traceback'*|*'fatal:'*|*'ModuleNotFoundError'*|\
      *'No such file or directory'*|*'Permission denied'*|*'npm ERR!'*|\
      *'error:'*|*'panic:'*) ;;
      *) _thk_fast=1 ;;
    esac
    ;;
esac

if [ "$_thk_fast" = 1 ]; then
  _thk_sid_raw=""; _thk_tool=""
  # set -e is on: capture the rc through `||`, never as a bare statement.
  _thk_rc=0; _thk_str session_id || _thk_rc=$?
  case "$_thk_rc" in
    0) _thk_sid_raw="$_THK_VAL" ;;
    2) _thk_sid_raw="default" ;;      # python: str(sid or 'default')
    *) _thk_fast=0 ;;
  esac
  if [ "$_thk_fast" = 1 ]; then
    if _thk_str tool_name; then _thk_tool="$_THK_VAL"; else _thk_fast=0; fi
  fi
  # The tool name goes into JSON unescaped, so accept only names that need no
  # escaping. Real names are identifiers (Bash, Read, mcp__server__tool).
  case "$_thk_tool" in
    ''|*[!A-Za-z0-9_-]*) _thk_fast=0 ;;
  esac
fi

if [ "$_thk_fast" = 1 ]; then
  # Identical to python's re.sub(r'[^a-zA-Z0-9_-]','',...)[:64] or 'default'.
  # Safe to use // here: the value is capped at 200 chars by _thk_str above.
  _thk_sid="${_thk_sid_raw//[^a-zA-Z0-9_-]/}"
  _thk_sid="${_thk_sid:0:64}"
  [ -z "$_thk_sid" ] && _thk_sid="default"
  if [ -n "${EPOCHSECONDS:-}" ]; then _thk_ts="$EPOCHSECONDS"; else _thk_ts=$(date +%s); fi
  # Spacing matches json.dumps exactly — confidence-gate substring-matches
  # '"success": false', so the separators are part of the contract.
  RESULT=$(printf '%s\n{"session_id": "%s", "tool": "%s", "success": true, "ts": %s}' \
    "$_thk_sid" "$_thk_sid" "$_thk_tool" "$_thk_ts")
fi

# v2.7.58: ONE python fork does both the session-id sanitize AND the entry build.
# Was jq (session_id) + python (entry) = 2 forks on EVERY PostToolUse — the
# highest-frequency event, and this hook can't be pre-gated (it must record every
# call for the confidence-gate). python already parsed the payload, so the jq was
# pure redundancy. Line 1 = sanitized session id, line 2 = entry JSON.
if [ -z "$RESULT" ]; then
RESULT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json, time, re
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
sid = re.sub(r'[^a-zA-Z0-9_-]', '', str(d.get('session_id') or 'default'))[:64] or 'default'
tool = d.get('tool_name', '?')
resp = d.get('tool_response')
# v2.7.30: PostToolUse tool_response has NO exit_code (it's
# {interrupted,isImage,noOutputExpected,stderr,stdout} for Bash) — reading it
# meant EVERY command logged as success, so confidence-gate never saw failures.
# Infer failure from interrupted + strong stderr markers, same as failure-tracker.
success = True
if isinstance(resp, dict):
    stderr = str(resp.get('stderr') or '')
    if resp.get('interrupted') is True:
        success = False
    elif resp.get('error') or d.get('error'):
        success = False
    elif re.search(r'command not found|Traceback|fatal:|ModuleNotFoundError|No such file or directory|Permission denied|npm ERR!|error:|panic:', stderr):
        success = False
print(sid)
print(json.dumps({'session_id': sid, 'tool': tool, 'success': success, 'ts': int(time.time())}))
" 2>/dev/null)
fi

[ -z "$RESULT" ] && exit 0
# Windows python print() terminates every line with CRLF, and bash splits on \n
# alone — so both fields below kept a trailing CR. The session id then built the
# filename `.tool-history-<sid>\r`, and CR is not a legal character in a Windows
# filename, so the append failed and NOTHING was ever recorded: no history, no
# per-session isolation, and a confidence-gate with no failures to see.
# Neither field can legitimately contain a CR — the id is sanitized to
# [A-Za-z0-9_-] above, and a real CR inside the JSON is escaped as two characters
# — so stripping the byte outright is safe and covers both lines at once.
RESULT=${RESULT//$'\r'/}
SESSION_ID=${RESULT%%$'\n'*}
ENTRY=${RESULT#*$'\n'}
[ -z "$SESSION_ID" ] && SESSION_ID="default"
[ -z "$ENTRY" ] && exit 0
HISTORY="$SCOPE_DIR/.tool-history-${SESSION_ID}"

printf '%s\n' "$ENTRY" >> "$HISTORY"

if [ -f "$HISTORY" ]; then
  COUNT=$(wc -l < "$HISTORY" | tr -d ' ')
  if [ "$COUNT" -gt 20 ]; then
    # v2.26.51 (WINDOWS-SUPPORT-PLAN G3): the flock wrapper is gone. Three reasons,
    # in order of how much they mattered:
    #
    # 1. It never ran on macOS. `flock` is util-linux; Darwin does not ship it, so
    #    since v2.6.77 the subshell hit `command not found`, took the `|| true`,
    #    and trimmed unserialized on the primary development platform. Git Bash
    #    behaves identically — the "Windows gap" was already the macOS behaviour.
    # 2. It did not protect what the comment claimed. The append on line 60 is
    #    OUTSIDE the lock, so an entry written between another process's `tail`
    #    and its `mv` is lost with or without flock. The lock serialized the trim
    #    against itself and nothing else.
    # 3. The remaining race is benign. `mv` is atomic within a filesystem, and
    #    every concurrent trim writes "the last 20 lines as it saw them" — so a
    #    loser's result is simply replaced by an equally valid 20-line file. The
    #    worst case is one advisory history entry, not a corrupt file.
    #
    # Keeping a lock that runs on one of three platforms, guards the wrong window,
    # and protects advisory telemetry is worse than not having one: it reads as a
    # guarantee. The atomic write below is the real protection.
    tail -n 20 "$HISTORY" > "$HISTORY.$$.tmp" 2>/dev/null \
      && mv "$HISTORY.$$.tmp" "$HISTORY" 2>/dev/null \
      || rm -f "$HISTORY.$$.tmp" 2>/dev/null || true
    # Sweep the lock file left behind by installs that ran the old code path.
    rm -f "$HISTORY.lock" 2>/dev/null || true
  fi
fi

exit 0
