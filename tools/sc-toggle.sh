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

# Every scope dir a hook might read the kill-switch from. Hooks resolve it as
# ${CLAUDE_PLUGIN_DATA:-~/.claude/supercharger}/scope (lib-suppress.sh), so a PLUGIN
# install reads $CLAUDE_PLUGIN_DATA/scope — but this tool is launched by the /sc skill
# OUTSIDE any hook, so CLAUDE_PLUGIN_DATA is usually absent from its env. We therefore
# glob the plugin data dirs directly and write/clear the flag in ALL of them; writing
# to only the classic path made /sc off a silent no-op on plugin installs.
_flag_dirs() {
  printf '%s\n' "$SCOPE_DIR"
  [ -n "${CLAUDE_PLUGIN_DATA:-}" ] && printf '%s\n' "$CLAUDE_PLUGIN_DATA/scope"
  local pd
  for pd in "$HOME/.claude/plugins/data/"*supercharger*; do
    [ -d "$pd" ] && printf '%s\n' "$pd/scope"
  done
}
# True if the disable-flag exists in ANY scope dir.
_any_flag() {
  local d
  while IFS= read -r d; do
    [ -f "$d/.supercharger-disabled" ] && return 0
  done <<EOF
$(_flag_dirs)
EOF
  return 1
}

# First line of the Supercharger managed block, either marker form.
_marker_line() {
  [ -f "$CLAUDE_MD" ] || { echo ""; return; }
  grep -nE '^# --- Claude Supercharger|^# Claude Supercharger v' "$CLAUDE_MD" 2>/dev/null | head -1 | cut -d: -f1
}

# --- MCP servers -----------------------------------------------------------
# Supercharger registers its MCP servers under settings.json > mcpServers, tagged
# "<name> #supercharger". Those load at session start and cost context (tool
# schemas, ~300-3500 tokens by profile) — so leaving them registered meant `off`
# was not total. We move ONLY the tagged entries aside and restore them verbatim
# on `on`; a user's own MCP servers are never touched. Writes temp-then-mv, and a
# full settings.json copy already sits in the timestamped backup dir.
# BOTH files matter: mcp-setup.sh writes ~/.claude.json (primary) and treats
# ~/.claude/settings.json as legacy — a real install can have tagged servers in
# either or both, so handling only one leaves them loading. The stash is keyed by
# file so `on` restores each entry to the file it came from.
MCP_FILES="$HOME/.claude.json
$HOME/.claude/settings.json"
MCP_STASH="$STATE_DIR/mcp-servers.json"

_mcp_off() {   # extract tagged servers from every settings file -> stash
  SC_FILES="$MCP_FILES" SC_STASH="$MCP_STASH" python3 - <<'PY' 2>/dev/null || true
import json, os, sys
stash = os.environ["SC_STASH"]
saved, moved = {}, 0
for p in [x for x in os.environ["SC_FILES"].split("\n") if x.strip()]:
    if not os.path.isfile(p):
        continue
    try:
        with open(p) as f: s = json.load(f)
    except Exception:
        continue
    m = s.get("mcpServers") or {}
    tagged = {k: v for k, v in m.items() if "supercharger" in k.lower()}
    if not tagged:
        continue
    for k in tagged: del m[k]
    if m: s["mcpServers"] = m
    else: s.pop("mcpServers", None)
    tmp = p + ".sctmp"
    try:
        with open(tmp, "w") as f: json.dump(s, f, indent=2)
        os.replace(tmp, p)
    except Exception:
        try: os.unlink(tmp)
        except Exception: pass
        continue
    saved[p] = tagged
    moved += len(tagged)
if saved:
    os.makedirs(os.path.dirname(stash), exist_ok=True)
    with open(stash, "w") as f: json.dump(saved, f, indent=2)
    print(moved)
PY
}

_mcp_on() {    # restore each stashed server to the file it came from
  [ -f "$MCP_STASH" ] || return 0
  SC_STASH="$MCP_STASH" python3 - <<'PY' 2>/dev/null || true
import json, os, sys
try:
    with open(os.environ["SC_STASH"]) as f: saved = json.load(f)
except Exception:
    sys.exit(0)
back = 0
for p, tagged in saved.items():
    if not os.path.isfile(p):
        continue
    try:
        with open(p) as f: s = json.load(f)
    except Exception:
        continue
    m = s.get("mcpServers") or {}
    for k, v in tagged.items():
        m.setdefault(k, v)          # never clobber a hand-re-added key
    s["mcpServers"] = m
    tmp = p + ".sctmp"
    try:
        with open(tmp, "w") as f: json.dump(s, f, indent=2)
        os.replace(tmp, p)
        back += len(tagged)
    except Exception:
        try: os.unlink(tmp)
        except Exception: pass
if back: print(back)
PY
}

_backup() {
  local ts bdir
  ts=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo "manual")
  bdir="$HOME/.claude/backups/deactivate-$ts"
  mkdir -p "$bdir" 2>/dev/null || true
  [ -f "$HOME/.claude/settings.json" ] && cp "$HOME/.claude/settings.json" "$bdir/" 2>/dev/null || true
  # ~/.claude.json also holds mcpServers (mcp-setup.sh's primary target) and `off`
  # now edits it — so it belongs in the backup too.
  [ -f "$HOME/.claude.json" ] && cp "$HOME/.claude.json" "$bdir/claude.json" 2>/dev/null || true
  [ -f "$CLAUDE_MD" ] && cp "$CLAUDE_MD" "$bdir/" 2>/dev/null || true
  printf '%s' "$bdir"
}

case "${1:-status}" in
  off)
    if _any_flag; then echo "Supercharger is already OFF (run 'sc-toggle.sh on' to re-enable)."; exit 0; fi
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

    # Move Supercharger's own MCP servers aside so `off` also drops their context
    # cost. Runs before the flag write; failure here must not abort the toggle.
    _MCP_MOVED=$(_mcp_off || true)

    # Kill-switch — write to EVERY scope dir a hook might read (classic + plugin),
    # else the flag lands where the running hooks never look and off is a no-op.
    _FLAG_BODY=$(printf 'disabled_at %s\nbackup %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "$BDIR")
    while IFS= read -r _d; do
      mkdir -p "$_d" 2>/dev/null || true
      printf '%s\n' "$_FLAG_BODY" > "$_d/.supercharger-disabled" 2>/dev/null || true
    done <<EOF
$(_flag_dirs)
EOF

    echo ""
    echo "  Supercharger is now OFF — default Claude Code behavior."
    echo ""
    echo "  ⚠  ALL guards are now INACTIVE: destructive-command blocking, path-guard,"
    echo "     credential/env-file guards, git-safety — none of them will run."
    echo "     You are on stock Claude Code with no safety net until you re-enable."
    echo ""
    echo "  • Hooks: off immediately (next tool call)."
    echo "  • Prompt rules: the CLAUDE.md block was removed; takes effect next session."
    if [ -n "${_MCP_MOVED:-}" ] && [ "${_MCP_MOVED:-0}" != "0" ]; then
      echo "  • MCP servers: ${_MCP_MOVED} Supercharger-registered server(s) moved aside, so they"
      echo "    stop loading (and stop costing context) — restored by /sc on. Next session."
    fi
    echo "  • Nothing was deleted. Backup: $BDIR"
    echo ""
    echo "  Re-enable any time:  /sc on   (or  bash $SC_DIR/tools/sc-toggle.sh on )"
    ;;

  on)
    if ! _any_flag; then echo "Supercharger is already ON."; exit 0; fi
    # Restore the exact CLAUDE.md we saved at off-time.
    if [ -f "$STATE_DIR/claude-md.txt" ]; then
      cp "$STATE_DIR/claude-md.txt" "$CLAUDE_MD" 2>/dev/null || true
    fi
    # Clear the flag from EVERY scope dir it may have been written to.
    while IFS= read -r _d; do
      rm -f "$_d/.supercharger-disabled" 2>/dev/null || true
    done <<EOF
$(_flag_dirs)
EOF
    # Restore the MCP servers we moved aside (before STATE_DIR, which holds them).
    _MCP_BACK=$(_mcp_on || true)
    rm -rf "$STATE_DIR" 2>/dev/null || true
    echo ""
    echo "  Supercharger is now ON — hooks active again, guards restored."
    echo "  CLAUDE.md rules restored; they re-enter context on your next session."
    if [ -n "${_MCP_BACK:-}" ] && [ "${_MCP_BACK:-0}" != "0" ]; then
      echo "  ${_MCP_BACK} MCP server(s) restored; they load again next session."
    fi
    ;;

  status)
    if _any_flag; then
      echo "Supercharger: DISABLED (default Claude behavior)"
      { [ -f "$FLAG" ] && sed 's/^/  /' "$FLAG"; } 2>/dev/null || true
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
