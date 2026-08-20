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

# Windows python defaults stdout to the ANSI codepage (cp1252) and raises
# UnicodeEncodeError on the box-drawing and arrow characters this tool prints,
# losing ALL of its output. Hooks get this from hooks/lib-paths.sh; tools do not
# reach that file, so they set it themselves. `:=` honours an explicit setting.
: "${PYTHONIOENCODING:=utf-8}"
: "${PYTHONUTF8:=1}"
export PYTHONIOENCODING PYTHONUTF8
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
  # Explicit root wins over discovery — mirrors sc_scope_dirs in lib/utils.sh, and
  # keeps a test that sandboxes via CLAUDE_PLUGIN_DATA from reaching the real $HOME.
  if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
    printf '%s\n' "$CLAUDE_PLUGIN_DATA/scope"
    return 0
  fi
  printf '%s\n' "$SCOPE_DIR"
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

# --- ~/.claude/rules/*.md -----------------------------------------------------
# Claude Code auto-loads this directory (lib/roles.sh:57 says so in as many
# words), with no import anywhere in CLAUDE.md. So stripping the CLAUDE.md block
# was only HALF the prompt layer: `off` left ~9KB of Supercharger instructions —
# the universal rules, the guardrails, the economy tier and the active role —
# entering every session. The command promised "default Claude Code behavior"
# and delivered the role and workflow rules anyway.
#
# Only files Supercharger OWNS are moved. A role file is ours when a file of the
# same name exists in supercharger/roles/, which is where the installer copies
# every role from; the other four are installer-deployed by name. Anything else
# in rules/ is the user's and is left exactly where it is — `off` means default
# Claude, not "lose your own config".
RULES_DIR="$HOME/.claude/rules"
RULES_STASH="$STATE_DIR/rules"
RULES_MANIFEST="$STATE_DIR/rules-moved.txt"

_sc_owned_rules() {   # -> one filename per line, only those present on disk
  local f
  for f in supercharger.md guardrails.md economy.md anti-patterns.yml; do
    [ -f "$RULES_DIR/$f" ] && printf '%s\n' "$f"
  done
  # Roles: identified against the installed role sources, so a same-named file
  # the user wrote themselves is never taken.
  for f in "$HOME/.claude/supercharger/roles/"*.md; do
    [ -f "$f" ] || continue
    f=${f##*/}
    [ -f "$RULES_DIR/$f" ] && printf '%s\n' "$f"
  done
}

_rules_off() {   # move ours aside -> echoes how many
  local n=0 f
  mkdir -p "$RULES_STASH" 2>/dev/null || return 0
  : > "$RULES_MANIFEST" 2>/dev/null || true
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if mv "$RULES_DIR/$f" "$RULES_STASH/$f" 2>/dev/null; then
      printf '%s\n' "$f" >> "$RULES_MANIFEST" 2>/dev/null || true
      n=$((n + 1))
    fi
  done <<EOF
$(_sc_owned_rules)
EOF
  [ "$n" -gt 0 ] && printf '%s' "$n"
}

_rules_on() {    # put back exactly what we took -> echoes how many
  local n=0 f
  [ -f "$RULES_MANIFEST" ] || return 0
  mkdir -p "$RULES_DIR" 2>/dev/null || true
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # Never clobber: if something now occupies the name, leave the user's file.
    [ -e "$RULES_DIR/$f" ] && continue
    mv "$RULES_STASH/$f" "$RULES_DIR/$f" 2>/dev/null && n=$((n + 1))
  done < "$RULES_MANIFEST"
  [ "$n" -gt 0 ] && printf '%s' "$n"
}

_mcp_off() {   # extract tagged servers from every settings file -> stash
  # v2.28.14: stderr is NOT discarded here. v2.28.13 added a message naming any
  # settings file whose rewrite failed, and this 2>/dev/null meant it could never
  # be seen — the fifth time in this sequence a diagnostic was written into a
  # stream its caller throws away. The block below is small and self-contained, so
  # anything it prints on stderr is worth surfacing, including a traceback.
  SC_FILES="$MCP_FILES" SC_STASH="$MCP_STASH" python3 - <<'PY' || true
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
    # v2.28.13: an in-place fallback, and never a SILENT skip. The write was
    # temp-file-plus-replace with a bare except that swallowed any failure and
    # moved on, so a file that could not be replaced simply kept its tagged
    # servers and `off` reported success. Windows is where that bites: it locks
    # files far more readily than POSIX, and the recon has the legacy
    # settings.json keeping its tagged server while the primary file beside it is
    # cleaned by the identical code. Replace is still preferred — it is atomic —
    # but if it fails the content is written in place rather than abandoned, and
    # if BOTH fail the user is told which file still holds Supercharger servers
    # instead of being left to discover it.
    tmp = p + ".sctmp"
    written = False
    try:
        with open(tmp, "w") as f: json.dump(s, f, indent=2)
        os.replace(tmp, p)
        written = True
    except Exception:
        try: os.unlink(tmp)
        except Exception: pass
        try:
            with open(p, "w") as f: json.dump(s, f, indent=2)
            written = True
        except Exception as e:
            sys.stderr.write("sc-toggle: could not rewrite %s (%s) - it still "
                             "holds Supercharger MCP servers\n" % (p, e))
    if not written:
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

# --- settings.json: hook registrations + statusLine ---------------------------
# The kill-switch is read INSIDE the hook body, so with it set every hook still
# SPAWNS, sources lib-suppress, reads the flag and exits. The work stops; the
# fork does not — ~18 process spawns on a Bash tool call, whose measured floor is
# bash startup alone. `off` promised default Claude and still cost that on every
# call, so the registrations come out too.
#
# ONLY entries tagged `#supercharger` are touched — the same marker hook-doctor
# keys on. A hook the user registered themselves stays exactly where it is. The
# statusLine is removed only when it points at our own script.
#
# The flag is still written: a PLUGIN install registers through the plugin's own
# hooks.json, which this tool cannot edit, so the flag remains the only thing
# that stops those.
SETTINGS_JSON="$HOME/.claude/settings.json"
HOOKS_STASH="$STATE_DIR/settings-hooks.json"

_hooks_off() {   # strip tagged registrations -> echoes how many were removed
  SC_SETTINGS="$SETTINGS_JSON" SC_STASH="$HOOKS_STASH" python3 - <<'PY' 2>/dev/null || true
import json, os
p, stash = os.environ["SC_SETTINGS"], os.environ["SC_STASH"]
if not os.path.isfile(p):
    raise SystemExit(0)
try:
    with open(p) as f: s = json.load(f)
except Exception:
    raise SystemExit(0)

def ours(h):
    c = h.get("command", "") or h.get("prompt", "") or ""
    return "#supercharger" in c

saved, removed = {"hooks": {}, "statusLine": None}, 0
hooks = s.get("hooks") or {}
for ev in list(hooks):
    kept_entries = []
    for entry in hooks[ev]:
        mine = [h for h in entry.get("hooks", []) if ours(h)]
        rest = [h for h in entry.get("hooks", []) if not ours(h)]
        if mine:
            saved["hooks"].setdefault(ev, []).append(
                {"matcher": entry.get("matcher"), "hooks": mine})
            removed += len(mine)
        if rest:
            e = dict(entry); e["hooks"] = rest
            kept_entries.append(e)
    if kept_entries: hooks[ev] = kept_entries
    else: del hooks[ev]
if hooks: s["hooks"] = hooks
else: s.pop("hooks", None)

sl = s.get("statusLine")
if isinstance(sl, dict) and "supercharger" in json.dumps(sl).lower():
    saved["statusLine"] = sl
    s.pop("statusLine", None)

if not removed and saved["statusLine"] is None:
    raise SystemExit(0)
# Stash BEFORE rewriting: a crash between the two must never lose the originals.
tmp = stash + ".tmp"
with open(tmp, "w") as f: json.dump(saved, f, indent=2)
os.replace(tmp, stash)
tmp = p + ".sctmp"
with open(tmp, "w") as f: json.dump(s, f, indent=2)
os.replace(tmp, p)
print(removed)
PY
}

_hooks_on() {    # put them back -> echoes how many, or FAIL:<want>:<got>
  SC_SETTINGS="$SETTINGS_JSON" SC_STASH="$HOOKS_STASH" python3 - <<'PY' 2>/dev/null || true
import json, os
p, stash = os.environ["SC_SETTINGS"], os.environ["SC_STASH"]
if not os.path.isfile(stash):
    raise SystemExit(0)
try:
    with open(stash) as f: saved = json.load(f)
except Exception:
    raise SystemExit(0)
try:
    with open(p) as f: s = json.load(f)
except Exception:
    s = {}

want = sum(len(e.get("hooks", [])) for ev in saved.get("hooks", {}).values() for e in ev)
hooks = s.get("hooks") or {}
back = 0
for ev, entries in saved.get("hooks", {}).items():
    cur = hooks.setdefault(ev, [])
    for entry in entries:
        match = next((c for c in cur if c.get("matcher") == entry.get("matcher")), None)
        if match is None:
            cur.append(entry)
        else:
            have = {json.dumps(h, sort_keys=True) for h in match.get("hooks", [])}
            for h in entry.get("hooks", []):
                if json.dumps(h, sort_keys=True) not in have:
                    match.setdefault("hooks", []).append(h)
        back += len(entry.get("hooks", []))
if hooks: s["hooks"] = hooks
if saved.get("statusLine") and "statusLine" not in s:
    s["statusLine"] = saved["statusLine"]

tmp = p + ".sctmp"
with open(tmp, "w") as f: json.dump(s, f, indent=2)
os.replace(tmp, p)

# Verify against the file just written, not against intent. A restore that
# silently drops registrations leaves the user unguarded while reporting success.
try:
    with open(p) as f: after = json.load(f)
except Exception:
    print("FAIL:%d:0" % want); raise SystemExit(0)
now = sum(1 for ev in (after.get("hooks") or {}).values() for e in ev
          for h in e.get("hooks", [])
          if "#supercharger" in (h.get("command", "") or h.get("prompt", "") or ""))
print(("%d" % back) if now >= want else ("FAIL:%d:%d" % (want, now)))
PY
}

# --- ~/.claude/agents/*.md ----------------------------------------------------
# Agent definitions do not RUN while off — nothing invokes them once the hooks
# are gone — but their frontmatter is listed to the model every session: ~2970
# tokens of Supercharger agents in a session that is supposed to be stock Claude.
# That is more residual context than the rules files, so it comes out too.
#
# Ownership is exact: an agent is ours only when the installed source of the same
# name exists in supercharger/agents/ (install.sh keeps that reference copy for
# exactly this, the way it already does for roles). Anything the user wrote stays.
# On an install predating that copy the dir is absent and this moves NOTHING —
# degrading to the old behaviour beats guessing at someone else's agent file.
#
# The 48 slash commands are deliberately NOT touched. /sc itself is one of them,
# so removing commands could strand a user with no way to type `/sc on`, and the
# whole set is worth ~650 tokens — a special case that buys little and can strand.
AGENTS_DIR="$HOME/.claude/agents"
AGENTS_SRC="$HOME/.claude/supercharger/agents"
AGENTS_STASH="$STATE_DIR/agents"
AGENTS_MANIFEST="$STATE_DIR/agents-moved.txt"

_agents_off() {   # move ours aside -> echoes how many
  local n=0 f base
  [ -d "$AGENTS_DIR" ] || return 0
  mkdir -p "$AGENTS_STASH" 2>/dev/null || return 0
  : > "$AGENTS_MANIFEST" 2>/dev/null || true
  for f in "$AGENTS_SRC"/*.md; do
    [ -f "$f" ] || continue
    base=${f##*/}
    [ -f "$AGENTS_DIR/$base" ] || continue
    if mv "$AGENTS_DIR/$base" "$AGENTS_STASH/$base" 2>/dev/null; then
      printf '%s\n' "$base" >> "$AGENTS_MANIFEST" 2>/dev/null || true
      n=$((n + 1))
    fi
  done
  [ "$n" -gt 0 ] && printf '%s' "$n"
}

_agents_on() {    # put back exactly what we took -> echoes how many
  local n=0 f
  [ -f "$AGENTS_MANIFEST" ] || return 0
  mkdir -p "$AGENTS_DIR" 2>/dev/null || true
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # Never clobber something that claimed the name while off.
    [ -e "$AGENTS_DIR/$f" ] && continue
    mv "$AGENTS_STASH/$f" "$AGENTS_DIR/$f" 2>/dev/null && n=$((n + 1))
  done < "$AGENTS_MANIFEST"
  [ "$n" -gt 0 ] && printf '%s' "$n"
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
    #
    # Three things are saved, because `on` has to tell apart "nothing happened
    # while off" from "the user edited this file". Restoring the whole saved copy
    # unconditionally DESTROYED anything written in between — reported, and
    # reproduced: text appended to CLAUDE.md while off vanished on the next `on`.
    #   claude-md.txt        the file as it was, for the untouched case
    #   claude-md-block.txt  just the managed block, to re-append if it changed
    #   claude-md-left.txt   what we left behind, the yardstick for "changed"
    if [ -f "$CLAUDE_MD" ]; then
      cp "$CLAUDE_MD" "$STATE_DIR/claude-md.txt" 2>/dev/null || true
      ML=$(_marker_line)
      if [ -n "$ML" ]; then
        tail -n "+$ML" "$CLAUDE_MD" > "$STATE_DIR/claude-md-block.txt" 2>/dev/null || true
      fi
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
      # Record exactly what off leaves behind, so `on` can tell whether the file
      # was touched since.
      cp "$CLAUDE_MD" "$STATE_DIR/claude-md-left.txt" 2>/dev/null || true
    fi

    # Move Supercharger's own MCP servers aside so `off` also drops their context
    # cost. Runs before the flag write; failure here must not abort the toggle.
    _MCP_MOVED=$(_mcp_off || true)

    # Same for the rules/ half of the prompt layer. After the CLAUDE.md strip, so
    # a failure here cannot leave the block removed AND the rules gone with no
    # record; both are restored from STATE_DIR by `on`.
    _RULES_MOVED=$(_rules_off || true)
    _AGENTS_MOVED=$(_agents_off || true)

    # Registrations last: everything above is recoverable from STATE_DIR and the
    # timestamped backup, and this is the one edit that touches the file holding
    # every hook the user has.
    _HOOKS_MOVED=$(_hooks_off || true)

    # Kill-switch — write to EVERY scope dir a hook might read (classic + plugin),
    # else the flag lands where the running hooks never look and off is a no-op.
    _FLAG_BODY=$(printf 'disabled_at %s\nbackup %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "$BDIR")
    while IFS= read -r _d; do
      mkdir -p "$_d" 2>/dev/null || true
      printf '%s\n' "$_FLAG_BODY" > "$_d/.supercharger-disabled" 2>/dev/null || true
      # One-shot marker for sc-toggle-notice.sh. The rules files are moved off
      # disk below, but a session ALREADY RUNNING has them in context and cannot
      # unread them, so the notice states the override on the next prompt. It is
      # deleted on read: off must not keep talking every turn.
      printf 'off\n' > "$_d/.sc-toggle-announce" 2>/dev/null || true
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
    if [ -n "${_HOOKS_MOVED:-}" ] && [ "${_HOOKS_MOVED:-0}" != "0" ]; then
      echo "  • Hooks: ${_HOOKS_MOVED} registration(s) removed from settings.json, so they no"
      echo "    longer even spawn. Your own hooks were left registered."
    else
      echo "  • Hooks: off immediately (next tool call)."
    fi
    if [ -n "${_RULES_MOVED:-}" ] && [ "${_RULES_MOVED:-0}" != "0" ]; then
      echo "  • Prompt rules: the CLAUDE.md block and ${_RULES_MOVED} rules/ file(s) were"
      echo "    removed; takes effect next session. Your own rules/ files were left alone."
    else
      echo "  • Prompt rules: the CLAUDE.md block was removed; takes effect next session."
    fi
    if [ -n "${_AGENTS_MOVED:-}" ] && [ "${_AGENTS_MOVED:-0}" != "0" ]; then
      echo "  • Agents: ${_AGENTS_MOVED} definition(s) moved aside so they stop being listed"
      echo "    to the model. Your own agents were left in place."
    fi
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
    # Restore CLAUDE.md — byte-exact when untouched, MERGED when the user wrote
    # to it while off. The old code copied the saved file back unconditionally,
    # which silently destroyed anything added in between.
    _CMD_MERGED=0
    if [ -f "$STATE_DIR/claude-md.txt" ]; then
      if [ -f "$STATE_DIR/claude-md-left.txt" ] && [ -f "$STATE_DIR/claude-md-block.txt" ] \
         && ! cmp -s "$CLAUDE_MD" "$STATE_DIR/claude-md-left.txt"; then
        # Changed while off: keep what is there now and put the block back after
        # it, rather than reinstating a stale copy of the whole file.
        {
          cat "$CLAUDE_MD" 2>/dev/null
          printf '\n'
          cat "$STATE_DIR/claude-md-block.txt"
        } > "$CLAUDE_MD.sctmp" 2>/dev/null \
          && mv "$CLAUDE_MD.sctmp" "$CLAUDE_MD" 2>/dev/null \
          && _CMD_MERGED=1
      else
        cp "$STATE_DIR/claude-md.txt" "$CLAUDE_MD" 2>/dev/null || true
      fi
    fi
    # Clear the flag from EVERY scope dir it may have been written to.
    while IFS= read -r _d; do
      rm -f "$_d/.supercharger-disabled" 2>/dev/null || true
      # Symmetric with off. Without this, off is instant while on silently waits
      # for a restart, which is the more surprising of the two.
      mkdir -p "$_d" 2>/dev/null || true
      printf 'on\n' > "$_d/.sc-toggle-announce" 2>/dev/null || true
    done <<EOF
$(_flag_dirs)
EOF
    # Restore the MCP servers and rules we moved aside. Both read from STATE_DIR,
    # so they must run BEFORE it is deleted.
    _MCP_BACK=$(_mcp_on || true)
    _RULES_BACK=$(_rules_on || true)
    _AGENTS_BACK=$(_agents_on || true)
    _HOOKS_BACK=$(_hooks_on || true)
    # A restore that dropped registrations must NOT delete the stash and must not
    # report success — that would leave the user unguarded and with nothing to
    # recover from. Bail loudly and keep STATE_DIR intact.
    case "${_HOOKS_BACK:-}" in
      FAIL:*)
        echo ""
        echo "  ⚠  Hook registrations were NOT fully restored"
        echo "     (expected ${_HOOKS_BACK#FAIL:} — shown as expected:found)."
        echo "     settings.json has been left as-is and the saved copy is kept at:"
        echo "       $HOOKS_STASH"
        echo "     A timestamped backup from 'off' is under ~/.claude/backups/."
        echo "     Supercharger stays OFF until this is resolved — re-run 'on' after"
        echo "     checking settings.json, or restore it from the backup."
        exit 1
        ;;
    esac
    rm -rf "$STATE_DIR" 2>/dev/null || true
    echo ""
    echo "  Supercharger is now ON — hooks active again, guards restored."
    if [ -n "${_HOOKS_BACK:-}" ] && [ "${_HOOKS_BACK:-0}" != "0" ]; then
      echo "  ${_HOOKS_BACK} hook registration(s) restored to settings.json."
    fi
    if [ -n "${_AGENTS_BACK:-}" ] && [ "${_AGENTS_BACK:-0}" != "0" ]; then
      echo "  ${_AGENTS_BACK} agent definition(s) restored."
    fi
    if [ -n "${_RULES_BACK:-}" ] && [ "${_RULES_BACK:-0}" != "0" ]; then
      echo "  CLAUDE.md and ${_RULES_BACK} rules/ file(s) restored; they re-enter context next session."
    else
      echo "  CLAUDE.md rules restored; they re-enter context on your next session."
    fi
    if [ "${_CMD_MERGED:-0}" = "1" ]; then
      echo "  CLAUDE.md had been edited while off — your changes were KEPT and the"
      echo "  Supercharger block re-appended below them."
    fi
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
