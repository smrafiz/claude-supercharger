#!/usr/bin/env bash
# Claude Supercharger — Activate / Deactivate toggle
# Usage: sc-toggle.sh off | on | status
#
#   off    Switch to default Claude behavior. Sets a global kill-switch flag so
#          EVERY hook exits immediately (no enforcement, no injection, no
#          statusline), and strips the Supercharger block from ~/.claude/CLAUDE.md
#          so the prompt layer is gone next session. Everything stays on disk;
#          nothing is deleted — `sc-toggle.sh on` restores it.
#   on     Re-enable: remove the flag and restore the CLAUDE.md block.
#   status Report ACTIVE / DISABLED.
#
# Design notes:
#   * The kill-switch is a flag file that lib-suppress.sh / lib-timing.sh check at
#     source time — so it takes effect for the very next hook fire, no reinstall.
#   * We DO NOT touch settings.json (no JSON surgery, no blast radius). Registered
#     hooks simply exit instantly via the flag. Files stay dormant on disk.
#   * SUPERCHARGER_TOGGLE=1 is exported so anything this tool sources bypasses the
#     kill-switch (otherwise `sc-toggle.sh on` could be disabled by its own flag).
set -uo pipefail
export SUPERCHARGER_TOGGLE=1

SC_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SC_DIR/scope"
FLAG="$SCOPE_DIR/.supercharger-disabled"
STATE_DIR="$SC_DIR/.deactivated"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

# First line of the Supercharger managed block, either marker form.
_marker_line() {
  [ -f "$CLAUDE_MD" ] || { echo ""; return; }
  grep -nE '^# --- Claude Supercharger|^# Claude Supercharger v' "$CLAUDE_MD" 2>/dev/null | head -1 | cut -d: -f1
}

_backup() {
  local ts bdir
  ts=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo "manual")
  bdir="$HOME/.claude/backups/deactivate-$ts"
  mkdir -p "$bdir" 2>/dev/null || true
  [ -f "$HOME/.claude/settings.json" ] && cp "$HOME/.claude/settings.json" "$bdir/" 2>/dev/null || true
  [ -f "$CLAUDE_MD" ] && cp "$CLAUDE_MD" "$bdir/" 2>/dev/null || true
  printf '%s' "$bdir"
}

case "${1:-status}" in
  off)
    if [ -f "$FLAG" ]; then echo "Supercharger is already OFF (run 'sc-toggle.sh on' to re-enable)."; exit 0; fi
    BDIR=$(_backup)
    mkdir -p "$STATE_DIR" 2>/dev/null || true

    # Save + strip the CLAUDE.md managed block (first marker → EOF). Saving the
    # WHOLE file lets `on` restore byte-exactly regardless of install mode.
    if [ -f "$CLAUDE_MD" ]; then
      cp "$CLAUDE_MD" "$STATE_DIR/claude-md.txt" 2>/dev/null || true
      ML=$(_marker_line)
      if [ -n "$ML" ]; then
        if [ "$ML" -le 1 ]; then
          # Whole file is Supercharger (deploy mode) → default Claude has none.
          : > "$CLAUDE_MD"
        else
          # Merge install → keep the user's own content above the marker.
          head -n "$((ML - 1))" "$CLAUDE_MD" > "$CLAUDE_MD.sctmp" 2>/dev/null \
            && mv "$CLAUDE_MD.sctmp" "$CLAUDE_MD"
          # trim trailing blank lines
          awk 'NF{p=NR} {L[NR]=$0} END{for(i=1;i<=p;i++) print L[i]}' "$CLAUDE_MD" > "$CLAUDE_MD.sctmp" 2>/dev/null \
            && mv "$CLAUDE_MD.sctmp" "$CLAUDE_MD"
        fi
      fi
    fi

    # Kill-switch — every hook exits immediately from here on.
    printf 'disabled_at %s\nbackup %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "$BDIR" > "$FLAG"

    echo ""
    echo "  Supercharger is now OFF — default Claude Code behavior."
    echo ""
    echo "  ⚠  ALL guards are now INACTIVE: destructive-command blocking, path-guard,"
    echo "     credential/env-file guards, git-safety — none of them will run."
    echo "     You are on stock Claude Code with no safety net until you re-enable."
    echo ""
    echo "  • Hooks: off immediately (next tool call)."
    echo "  • Prompt rules: the CLAUDE.md block was removed; takes effect next session."
    echo "  • Nothing was deleted. Backup: $BDIR"
    echo ""
    echo "  Re-enable any time:  /sc on   (or  bash $SC_DIR/tools/sc-toggle.sh on )"
    ;;

  on)
    if [ ! -f "$FLAG" ]; then echo "Supercharger is already ON."; exit 0; fi
    # Restore the exact CLAUDE.md we saved at off-time.
    if [ -f "$STATE_DIR/claude-md.txt" ]; then
      cp "$STATE_DIR/claude-md.txt" "$CLAUDE_MD" 2>/dev/null || true
    fi
    rm -f "$FLAG" 2>/dev/null || true
    rm -rf "$STATE_DIR" 2>/dev/null || true
    echo ""
    echo "  Supercharger is now ON — hooks active again, guards restored."
    echo "  CLAUDE.md rules restored; they re-enter context on your next session."
    ;;

  status)
    if [ -f "$FLAG" ]; then
      echo "Supercharger: DISABLED (default Claude behavior)"
      sed 's/^/  /' "$FLAG" 2>/dev/null || true
      echo "  Re-enable with: /sc on"
    else
      echo "Supercharger: ACTIVE"
    fi
    ;;

  *)
    echo "usage: sc-toggle.sh off | on | status" >&2
    exit 1
    ;;
esac
