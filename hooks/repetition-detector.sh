#!/usr/bin/env bash
# Claude Supercharger — Repetition Detector
# Event: PostToolUse | Matcher: Bash,Read
# Merged from loop-detector.sh + reread-detector.sh
# Detects repeated tool calls (loops) and unchanged file re-reads.
# Saves 10-50K tokens per caught loop; prevents redundant context reads.

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-hash.sh
. "$HOOKS_DIR/lib-hash.sh" 2>/dev/null || true

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# v2.6.27: one jq fork extracts all 5 fields (cwd, tool_name, command,
# file_path, session_id) using @tsv. Was 3-4 separate jq forks. Median
# 70ms → ~30ms on the common case (no loop, no re-read).
# v2.7.59: .cwd // .workspace.current_dir — restore the v2.6.57 dual-field fallback
# the perf-sweep @tsv consolidation dropped (CC 2.1.176+ may send CWD only in
# workspace.current_dir; without it, empty PROJECT_DIR → wrong suppress scope).
FIELDS=$(printf '%s\n' "$_INPUT" | jq -r '[.cwd // .workspace.current_dir // "", .tool_name // "", .tool_input.command // "", .tool_input.file_path // "", .session_id // "default"] | @tsv' 2>/dev/null || true)
# v2.7.44 perf: split the jq @tsv line ONCE with a bash read instead of 4 awk
# forks. This hook fires on every Bash AND Read (hottest hook).
# 2.21.14: convert the tab delimiters to unit-separator (\037) BEFORE read.
# `read` with IFS=tab COLLAPSES empty columns (tab is IFS-whitespace) — so for a
# Read tool (empty command column) it shifted file_path→F_CMD and
# session_id→F_FPATH, and the Read fingerprint below keyed on the SESSION ID,
# making any 3 reads look like a loop (the bogus `[LOOP] 'Read:<sid>'`). \037 is
# non-whitespace so empty columns survive; @tsv already escaped any literal
# tab/newline in the values, so this is lossless. session_id (field 5) now
# reads correctly, so no separate awk extraction is needed.
IFS=$'\037' read -r PROJECT_DIR TOOL_NAME F_CMD F_FPATH SID_RAW <<EOF_FIELDS
$(printf '%s' "$FIELDS" | tr '\t' '\037')
EOF_FIELDS
SID="${SID_RAW//[^a-zA-Z0-9_-]/}"; SID="${SID:0:64}"; [ -z "$SID" ] && SID="default"
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
hook_profile_skip "repetition-detector" && exit 0

[ -z "$TOOL_NAME" ] && exit 0

SCOPE_DIR="$SUPERCHARGER_STATE/scope"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

MESSAGES=()

# ── Loop detection (Bash + Read) ──
LOOP_FILE="$SCOPE_DIR/.loop-history-${SID}"

FINGERPRINT=""
case "$TOOL_NAME" in
  Bash)
    [ -z "$F_CMD" ] && FINGERPRINT="" || FINGERPRINT="Bash:${F_CMD}"
    ;;
  Read)
    [ -z "$F_FPATH" ] && FINGERPRINT="" || FINGERPRINT="Read:${F_FPATH}"
    ;;
esac

if [ -n "$FINGERPRINT" ]; then
  HASH=$(printf '%s' "$FINGERPRINT" | sc_md5 2>/dev/null || true)
  if [ -n "$HASH" ]; then
    # tail-then-awk; awk always emits the count, no shell-exit-status games
    COUNT=0
    if [ -f "$LOOP_FILE" ]; then
      COUNT=$(tail -20 "$LOOP_FILE" 2>/dev/null | awk -v h="$HASH" '$0==h{c++} END{print c+0}' || echo 0)
      [ -z "$COUNT" ] && COUNT=0
    fi
    echo "$HASH" >> "$LOOP_FILE" 2>/dev/null || true

    # Trim loop history
    if [ -f "$LOOP_FILE" ]; then
      LINES=$(wc -l < "$LOOP_FILE" | tr -d ' ')
      if [ "$LINES" -gt 50 ]; then
        tail -30 "$LOOP_FILE" > "$LOOP_FILE.$$.tmp" 2>/dev/null && mv "$LOOP_FILE.$$.tmp" "$LOOP_FILE" 2>/dev/null || true
      fi
    fi

    if [ "$COUNT" -ge 2 ]; then
      SHORT=$(printf '%.60s' "$FINGERPRINT" | sed 's/["\]//g')
      MESSAGES+=("[LOOP] '${SHORT}' repeated ${COUNT}x — try different approach")
      echo "[Supercharger] repetition-detector: loop '${SHORT}' repeated ${COUNT}x" >&2
      # 2.21.12: reuse SID parsed above (fork-free) instead of re-extracting.
      touch "$SCOPE_DIR/.repetition-flag-${SID}" 2>/dev/null || true
    fi
  fi
fi

# ── Re-read detection (Read only) ──
if [ "$TOOL_NAME" = "Read" ]; then
  FILE_PATH=$(printf '%s' "$FIELDS" | awk -F'\t' '{print $4}')
  if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
    # v2.8.14: session-scope the read history. It was GLOBAL, so reads from every
    # past session/project accumulated forever — a fresh session got false "you
    # already read X" tips, and (worse) confidence-gate's read-before-write check
    # saw those stale reads and silently stopped firing on real blind edits. Now
    # keyed by session like .tool-history-<sid> / .repetition-flag-<sid>.
    SID_RR=$(printf '%s' "$FIELDS" | awk -F'\t' '{print $5}' | tr -cd 'a-zA-Z0-9_-' | head -c 64)
    [ -z "$SID_RR" ] && SID_RR="default"
    READS_FILE="$SCOPE_DIR/.read-history-${SID_RR}"
    # v2.6.78: GNU-first + numeric guard for Linux stat-f portability
    CURRENT_MTIME=$(stat -c '%Y' "$FILE_PATH" 2>/dev/null || stat -f '%m' "$FILE_PATH" 2>/dev/null || echo "")
    case "$CURRENT_MTIME" in ''|*[!0-9]*) CURRENT_MTIME=0 ;; esac

    if [ -f "$READS_FILE" ]; then
      PREV_ENTRY=$(grep -F "${FILE_PATH}	" "$READS_FILE" 2>/dev/null | tail -1 || echo "")
      if [ -n "$PREV_ENTRY" ]; then
        PREV_MTIME=$(printf '%s' "$PREV_ENTRY" | cut -f2)
        if [ "$CURRENT_MTIME" = "$PREV_MTIME" ]; then
          SHORT=$(basename "$FILE_PATH")
          MESSAGES+=("[TOKEN TIP] You already read '${SHORT}' and it hasn't changed. Use cached knowledge or a targeted grep instead of re-reading.")
          echo "[Supercharger] repetition-detector: ${SHORT} unchanged since last read" >&2
        fi
      fi
    fi

    printf '%s\t%s\n' "$FILE_PATH" "$CURRENT_MTIME" >> "$READS_FILE" 2>/dev/null || true

    # Trim read history
    if [ -f "$READS_FILE" ]; then
      LINES=$(wc -l < "$READS_FILE" | tr -d ' ')
      if [ "$LINES" -gt 100 ]; then
        tail -60 "$READS_FILE" > "$READS_FILE.$$.tmp" 2>/dev/null && mv "$READS_FILE.$$.tmp" "$READS_FILE" 2>/dev/null || true
      fi
    fi
  fi
fi

[ ${#MESSAGES[@]} -eq 0 ] && exit 0

# Combine messages and emit
COMBINED=$(printf '%s\n' "${MESSAGES[@]}")
CONTEXT_JSON=$(printf '%s' "$COMBINED" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
  || printf '"%s"' "$(printf '%s' "$COMBINED" | tr -d '"\\' | tr '\n' ' ')")
# v2.7.40: loop/re-read advice is for Claude to act on → additionalContext
# (PostToolUse), not systemMessage (user-only).
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
