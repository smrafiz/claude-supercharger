#!/usr/bin/env bash
# Claude Supercharger — Learn from User Feedback
# Event: UserPromptSubmit | Matcher: (none)
# Detects correction AND reinforcement patterns in user prompts.
# Corrections: what to avoid. Reinforcements: what to keep doing.

set -euo pipefail

# v2.23.44: honor the global kill-switch — /sc off must silence EVERY hook. Sourcing
# lib-timing exits at source time when the disable flag is set (and adds /perf timing).
# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
PROMPT=$(printf '%s\n' "$_INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
if [ -z "$PROMPT" ]; then
  PROMPT=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null || echo "")
fi

[ -z "$PROMPT" ] && exit 0

PROMPT_LOWER=$(printf '%s\n' "$PROMPT" | tr '[:upper:]' '[:lower:]')
# Resolve state/code roots for both installer and plugin runtimes (see lib-paths.sh).
. "${BASH_SOURCE[0]%/*}/lib-paths.sh" 2>/dev/null || true
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
: "${SUPERCHARGER_HOME:=${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/supercharger}}"

SCOPE_DIR="$SUPERCHARGER_STATE/scope"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

# Project-scoped correction log
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null || echo "")
[ -z "$PROJECT_DIR" ] && PROJECT_DIR=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('workspace',{}).get('current_dir') or d.get('cwd',''))" 2>/dev/null || echo "")
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
. "${BASH_SOURCE[0]%/*}/lib-hash.sh" 2>/dev/null || true
PROJ_HASH=$(printf '%s' "$PROJECT_DIR" | sc_md5 2>/dev/null || true); [ -z "$PROJ_HASH" ] && PROJ_HASH="global"
PROJ_HASH="${PROJ_HASH:0:8}"

# v2.26.64: collapse newlines/tabs BEFORE shortening — same fix safety.sh got in
# v2.26.17, never applied to this sibling. Both ledgers below are LINE-BASED:
# learn-from-blocks parses them into the [CORR]/[WORKS] summaries injected at every
# session start, and /why reads the last N lines. A multi-line correction wrote a
# multi-line row, so its continuation became an orphan entry — observed live as
#     [CORR] no need, this:|Want me to write a short "perf & tokens" section...
# where the second field is not a correction at all, just the tail of the first.
# Truncating alone does not help: the newline sits inside the first 200 chars.
# Collapsing here (not at each writer) also fixes the dedup below, which passes
# the snippet to `grep -qF` — a multi-line pattern there matches line-by-line.
# TRUNCATE FIRST, then substitute. These three global substitutions used to run
# over the ENTIRE prompt to build a snippet that is capped at 200 characters two
# lines later — so every byte past the cap was rebuilt for nothing. Bash pattern
# substitution is superlinear, and "for nothing" turned into hours: measured on
# macOS, 16KB took 5.6s and 64KB took 454.8s (7.6 minutes). A prompt with a
# pasted file in it therefore pinned a core; one such process was found running
# 4h46m at 94% CPU, on the UserPromptSubmit path, where it delays the prompt.
#
# Replacement is 1:1 in length, so truncating first is not merely an
# approximation — the first 200 characters of the substituted string are exactly
# the substitution of the first 200 characters.
SNIPPET="${PROMPT:0:200}"
SNIPPET="${SNIPPET//$'\n'/ }"; SNIPPET="${SNIPPET//$'\r'/ }"; SNIPPET="${SNIPPET//$'\t'/ }"

# --- Corrections (negative feedback) ---
# Only match if prompt is short (<500 chars) and starts with correction language.
# Long prompts with incidental "not" are not corrections.
if [ ${#PROMPT} -lt 500 ] && [[ "$PROMPT_LOWER" =~ ^(don.t|do not|stop |never |no,? |wrong|i said not|i told you not|not what i asked|i didn.t ask|undo that|revert that|put it back|roll back|go back to|shouldn.t have|too (verbose|long|short|much)|why did you|you forgot|you missed|you broke|that broke|not solved|not fixed|still broken) ]]; then
  LOG="$SCOPE_DIR/.user-corrections-${PROJ_HASH}"
  # Dedup against last 20 entries
  DEDUP=$(printf '%.80s' "$SNIPPET")
  if [ -f "$LOG" ] && tail -20 "$LOG" 2>/dev/null | grep -qF "$DEDUP"; then
    : # skip duplicate
  else
    printf '[%s] CORRECTION: %s\n' "$(date '+%Y-%m-%d %H:%M')" "$SNIPPET" >> "$LOG" 2>/dev/null || true
    # v2.6.77: cap at 200 lines (same pattern as adaptive-economy history)
    if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 250 ]; then
      tail -200 "$LOG" > "$LOG.$$.tmp" && mv "$LOG.$$.tmp" "$LOG"
    fi
    echo "[Supercharger] learn: logged correction" >&2
  fi
  exit 0
fi

# --- Reinforcements (positive feedback) ---
# Only match short prompts that are clearly praise, not long prompts with incidental words
if [ ${#PROMPT} -lt 300 ] && [[ "$PROMPT_LOWER" =~ ^(perfect|exactly|yes.*(right|correct|that)|good job|well done|keep doing|that.s what i want|nailed it|spot on|much better|way better|love it|brilliant) ]]; then
  LOG="$SCOPE_DIR/.user-reinforcements-${PROJ_HASH}"
  DEDUP=$(printf '%.80s' "$SNIPPET")
  if [ -f "$LOG" ] && tail -20 "$LOG" 2>/dev/null | grep -qF "$DEDUP"; then
    : # skip duplicate
  else
    printf '[%s] REINFORCED: %s\n' "$(date '+%Y-%m-%d %H:%M')" "$SNIPPET" >> "$LOG" 2>/dev/null || true
    # v2.6.77: cap at 200 lines
    if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 250 ]; then
      tail -200 "$LOG" > "$LOG.$$.tmp" && mv "$LOG.$$.tmp" "$LOG"
    fi
    echo "[Supercharger] learn: logged reinforcement" >&2
  fi
  exit 0
fi

exit 0
