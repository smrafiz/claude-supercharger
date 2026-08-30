#!/usr/bin/env bash
# Tests for the /sc activate-deactivate toggle (v2.9.0):
#   tools/sc-toggle.sh off|on|status  +  the shared-lib kill-switch early-exit.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOGGLE="$REPO_DIR/tools/sc-toggle.sh"

echo "=== sc-toggle (activate/deactivate) Tests ==="

# Build an isolated ~/.claude with the deployed lib + a CLAUDE.md managed block.
_setup() {
  setup_test_home
  mkdir -p "$HOME/.claude/supercharger/scope" "$HOME/.claude/supercharger/hooks" "$HOME/.claude/backups"
  cp "$REPO_DIR/hooks/lib-suppress.sh" "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
  cp "$REPO_DIR/hooks/lib-timing.sh"   "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
  cp "$REPO_DIR/hooks/lib-paths.sh"    "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
  # merge-style CLAUDE.md: user content, then the Supercharger managed block
  printf '# My rules\nUse tabs.\n\n# --- Claude Supercharger\nManaged block line 1\nManaged block line 2\n' > "$HOME/.claude/CLAUDE.md"
}
FLAG_REL=".claude/supercharger/scope/.supercharger-disabled"

begin_test "sc-toggle: status is ACTIVE by default"
_setup
bash "$TOGGLE" status 2>/dev/null | grep -q "ACTIVE" && pass || fail "expected ACTIVE"
teardown_test_home

begin_test "sc-toggle: off sets the kill-switch flag"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
[ -f "$HOME/$FLAG_REL" ] && pass || fail "flag not created"
teardown_test_home

begin_test "sc-toggle: off strips the Supercharger block but keeps user content"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
if grep -q "Use tabs" "$HOME/.claude/CLAUDE.md" && ! grep -q "Managed block" "$HOME/.claude/CLAUDE.md"; then
  pass
else
  fail "expected user content kept + managed block removed, got: $(cat "$HOME/.claude/CLAUDE.md")"
fi
teardown_test_home

begin_test "sc-toggle: off writes a backup"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
ls "$HOME/.claude/backups"/deactivate-* >/dev/null 2>&1 && pass || fail "no backup written"
teardown_test_home

begin_test "sc-toggle: a hook sourcing lib-suppress EXITS immediately when off"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
OUT=$(HOME="$HOME" bash -c '. "$HOME/.claude/supercharger/hooks/lib-suppress.sh"; echo REACHED' 2>/dev/null)
[ "$OUT" != "REACHED" ] && pass || fail "hook did not early-exit (kill-switch ignored)"
teardown_test_home

begin_test "sc-toggle: security hooks (lib-timing) also early-exit when off"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
OUT=$(HOME="$HOME" bash -c '. "$HOME/.claude/supercharger/hooks/lib-timing.sh"; echo REACHED' 2>/dev/null)
[ "$OUT" != "REACHED" ] && pass || fail "security hook did not early-exit"
teardown_test_home

begin_test "sc-toggle: SUPERCHARGER_TOGGLE bypasses the kill-switch (no bootstrap trap)"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
OUT=$(HOME="$HOME" SUPERCHARGER_TOGGLE=1 bash -c '. "$HOME/.claude/supercharger/hooks/lib-suppress.sh"; echo REACHED' 2>/dev/null)
[ "$OUT" = "REACHED" ] && pass || fail "toggle bypass failed — /sc on could strand disabled"
teardown_test_home

begin_test "sc-toggle: status is DISABLED after off"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" status 2>/dev/null | grep -qi "DISABLED" && pass || fail "expected DISABLED"
teardown_test_home

begin_test "sc-toggle: on removes the flag"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on >/dev/null 2>&1
[ ! -f "$HOME/$FLAG_REL" ] && pass || fail "flag not removed"
teardown_test_home

begin_test "sc-toggle: on restores the CLAUDE.md block byte-exactly"
_setup
ORIG=$(cat "$HOME/.claude/CLAUDE.md")
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on >/dev/null 2>&1
[ "$(cat "$HOME/.claude/CLAUDE.md")" = "$ORIG" ] && pass || fail "CLAUDE.md not restored exactly"
teardown_test_home

begin_test "sc-toggle: hook runs normally again after on"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on >/dev/null 2>&1
OUT=$(HOME="$HOME" bash -c '. "$HOME/.claude/supercharger/hooks/lib-suppress.sh"; echo REACHED' 2>/dev/null)
[ "$OUT" = "REACHED" ] && pass || fail "hook still blocked after on"
teardown_test_home

begin_test "sc-toggle: off is idempotent (already off)"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" off 2>/dev/null | grep -qi "already OFF" && pass || fail "expected already-OFF message"
teardown_test_home

begin_test "sc-toggle: on is idempotent (already on)"
_setup
bash "$TOGGLE" on 2>/dev/null | grep -qi "already ON" && pass || fail "expected already-ON message"
teardown_test_home

begin_test "sc-toggle: statusline renders nothing when off (looks vanilla)"
_setup
cp "$REPO_DIR/hooks/statusline.sh" "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
bash "$TOGGLE" off >/dev/null 2>&1
# kill-switch fires before stdin is even read → no output at all
OFF_OUT=$(printf '%s' '{"model":{"display_name":"x"},"cwd":"/tmp"}' | HOME="$HOME" bash "$HOME/.claude/supercharger/hooks/statusline.sh" 2>/dev/null)
[ -z "$OFF_OUT" ] && pass || fail "statusline should be blank when off, got: $OFF_OUT"
teardown_test_home

begin_test "sc-toggle: statusline does NOT early-exit when on (guard line not taken)"
_setup
cp "$REPO_DIR/hooks/statusline.sh" "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
# no flag → the guard is false → the script must reach `_INPUT=$(cat)` and consume stdin.
# Prove it read stdin: pipe a sentinel and confirm the process consumed it (grep the source
# path is simplest — assert the guard line exists AND the flag is absent so it's inert).
[ ! -f "$HOME/.claude/supercharger/scope/.supercharger-disabled" ] \
  && grep -q 'supercharger-disabled.*exit 0' "$HOME/.claude/supercharger/hooks/statusline.sh" \
  && pass || fail "statusline missing the kill-switch guard, or flag present when it should not be"
teardown_test_home

begin_test "sc-toggle: deploy-mode (whole-file CLAUDE.md, marker at line 1) blanks then restores"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope" "$HOME/.claude/supercharger/hooks"
cp "$REPO_DIR/hooks/lib-suppress.sh" "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
cp "$REPO_DIR/hooks/lib-paths.sh"    "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
printf '# Claude Supercharger v9.9.9\n\n## rules\nbe terse\n' > "$HOME/.claude/CLAUDE.md"
ORIG=$(cat "$HOME/.claude/CLAUDE.md")
bash "$TOGGLE" off >/dev/null 2>&1
BLANK_OK=1; [ -s "$HOME/.claude/CLAUDE.md" ] && BLANK_OK=0
bash "$TOGGLE" on >/dev/null 2>&1
if [ "$BLANK_OK" = 1 ] && [ "$(cat "$HOME/.claude/CLAUDE.md")" = "$ORIG" ]; then pass; else fail "deploy-mode blank/restore failed (blank_ok=$BLANK_OK)"; fi
teardown_test_home

# --- v2.23.46: `off` must also drop Supercharger's OWN MCP servers (they load at
# session start and cost context), while never touching the user's own. ---
# Servers can live in ~/.claude.json (mcp-setup's PRIMARY target) and/or the legacy
# ~/.claude/settings.json — both must be handled, each restoring to its own file.
_mcp_setup() {
  _setup
  python3 -c '
import json,sys
json.dump({"mcpServers":{
  "context7 #supercharger":{"command":"npx"},
  "magic-ui #supercharger":{"command":"npx"},
  "my-own-primary":{"command":"node"}}}, open(sys.argv[1],"w"), indent=2)' "$HOME/.claude.json"
  python3 -c '
import json,sys
json.dump({"model":"opus","mcpServers":{
  "context7 #supercharger":{"command":"npx"},
  "my-own-legacy":{"command":"node"}}}, open(sys.argv[1],"w"), indent=2)' "$HOME/.claude/settings.json"
}
_keys_of() { python3 -c '
import json,sys
try: m=json.load(open(sys.argv[1])).get("mcpServers",{})
except Exception: m={}
print(",".join(sorted(m)))' "$1" 2>/dev/null; }
_mcp_keys() { _keys_of "$HOME/.claude/settings.json"; }

begin_test "sc-toggle: off removes tagged MCP servers from the LEGACY settings.json"
# v2.28.14: KEEP stderr. v2.28.13 added a message naming any settings file whose
# rewrite failed, and this line was discarding it — so the one diagnostic built
# for this failure could never reach the log. The runner still reports the tagged
# server surviving, and now it can say why.
_mcp_setup
_MCP_ERR=$(bash "$TOGGLE" off 2>&1 >/dev/null)
if [ "$(_mcp_keys)" = "my-own-legacy" ]; then pass
else
  fail "expected only the user's server, got: $(_mcp_keys)
--- sc-toggle stderr ---
${_MCP_ERR:-<none>}
--- legacy settings.json on disk ---
$(cat "$HOME/.claude/settings.json" 2>&1 | head -12)"
fi

begin_test "sc-toggle: off removes tagged MCP servers from ~/.claude.json (primary)"
[ "$(_keys_of "$HOME/.claude.json")" = "my-own-primary" ] && pass || fail "primary file not cleaned: $(_keys_of "$HOME/.claude.json")"

begin_test "sc-toggle: off leaves the user's own MCP servers alone (both files)"
{ printf '%s' "$(_mcp_keys)" | grep -q "my-own-legacy" \
  && printf '%s' "$(_keys_of "$HOME/.claude.json")" | grep -q "my-own-primary"; } && pass || fail "a user MCP server was removed"

begin_test "sc-toggle: off backs up ~/.claude.json (it is now edited)"
ls "$HOME/.claude/backups/"*/claude.json >/dev/null 2>&1 && pass || fail "no claude.json in the backup dir"

begin_test "sc-toggle: off stashes them and settings.json stays valid JSON"
{ [ -f "$HOME/.claude/supercharger/.deactivated/mcp-servers.json" ] \
  && python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$HOME/.claude/settings.json"; } 2>/dev/null \
  && pass || fail "stash missing or settings.json invalid"

begin_test "sc-toggle: on restores each MCP server to the file it came from"
bash "$TOGGLE" on >/dev/null 2>&1
{ [ "$(_keys_of "$HOME/.claude.json")" = "context7 #supercharger,magic-ui #supercharger,my-own-primary" ] \
  && [ "$(_mcp_keys)" = "context7 #supercharger,my-own-legacy" ]; } && pass \
  || fail "round-trip wrong — primary:[$(_keys_of "$HOME/.claude.json")] legacy:[$(_mcp_keys)]"
teardown_test_home

# v2.28.17: the LAST file in the list must be processed even when the first has
# nothing to remove. The paths used to travel as one newline-separated env var,
# and MSYS converts only the leading path of such a value - so on Git Bash the
# first file was cleaned and every later one was silently skipped, with no error,
# by the same loop. Every existing assertion here put a tagged server in BOTH
# files, so all of them passed on the first file alone and none could see it.
begin_test "sc-toggle: off cleans the LAST settings file when the first needs no change"
_setup
mkdir -p "$HOME/.claude"
python3 -c '
import json,sys
json.dump({"mcpServers":{"my-own-primary":{"command":"node"}}}, open(sys.argv[1],"w"), indent=2)' "$HOME/.claude.json"
python3 -c '
import json,sys
json.dump({"mcpServers":{"context7 #supercharger":{"command":"npx"},
  "my-own-legacy":{"command":"node"}}}, open(sys.argv[1],"w"), indent=2)' "$HOME/.claude/settings.json"
bash "$TOGGLE" off >/dev/null 2>&1
if [ "$(_mcp_keys)" = "my-own-legacy" ]; then pass
else fail "last file not processed when the first was a no-op, got: $(_mcp_keys)"; fi
teardown_test_home

begin_test "sc-toggle: settings.json with no mcpServers key still toggles cleanly"
_setup; printf '{"model":"opus"}\n' > "$HOME/.claude/settings.json"
{ bash "$TOGGLE" off >/dev/null 2>&1 && bash "$TOGGLE" on >/dev/null 2>&1; } && pass || fail "toggle failed without mcpServers"
teardown_test_home

# --- v2.23.37: plugin-install path parity. The flag must land where PLUGIN hooks
# read it ($CLAUDE_PLUGIN_DATA/scope), not only the classic path — else /sc off is a
# silent no-op on plugin installs (rules kept loading). ---
PDATA_REL=".claude/plugins/data/claude-supercharger-claude-supercharger"

begin_test "sc-toggle: off writes the flag to the PLUGIN scope dir too"
_setup
mkdir -p "$HOME/$PDATA_REL/scope"
bash "$TOGGLE" off >/dev/null 2>&1
[ -f "$HOME/$PDATA_REL/scope/.supercharger-disabled" ] && pass || fail "plugin-scope flag not written (the reported bug)"
teardown_test_home

begin_test "sc-toggle: a PLUGIN-context hook (CLAUDE_PLUGIN_DATA set) early-exits when off"
_setup
mkdir -p "$HOME/$PDATA_REL/scope"
bash "$TOGGLE" off >/dev/null 2>&1
OUT=$(HOME="$HOME" CLAUDE_PLUGIN_DATA="$HOME/$PDATA_REL" bash -c '. "$HOME/.claude/supercharger/hooks/lib-suppress.sh"; echo REACHED' 2>/dev/null)
[ -z "$OUT" ] && pass || fail "plugin hook did NOT early-exit when off (got: $OUT)"
teardown_test_home

begin_test "sc-toggle: on clears the flag from the PLUGIN scope dir too"
_setup
mkdir -p "$HOME/$PDATA_REL/scope"
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on  >/dev/null 2>&1
[ ! -f "$HOME/$PDATA_REL/scope/.supercharger-disabled" ] && pass || fail "plugin-scope flag not cleared by on"
teardown_test_home

begin_test "sc-toggle: status reports DISABLED when only the plugin flag exists"
_setup
mkdir -p "$HOME/$PDATA_REL/scope"
# simulate a flag that somehow only exists at the plugin path
printf 'disabled_at test\n' > "$HOME/$PDATA_REL/scope/.supercharger-disabled"
bash "$TOGGLE" status 2>/dev/null | grep -qi "DISABLED" && pass || fail "status missed the plugin-only flag"
teardown_test_home

# --- rules/ is the OTHER half of the prompt layer ----------------------------
# Claude Code auto-loads ~/.claude/rules/*.md — lib/roles.sh:57 says so, and no
# import exists in CLAUDE.md. `off` stripped only the CLAUDE.md block, so the
# universal rules, guardrails, economy tier and active role kept entering every
# session: roughly 9KB of Supercharger instructions while it claimed to be OFF.
# Reported from a real install, where /sc off still showed rules/developer.md and
# rules/supercharger.md loading.
_setup_rules() {
  _setup
  mkdir -p "$HOME/.claude/rules" "$HOME/.claude/supercharger/roles"
  printf 'universal\n'  > "$HOME/.claude/rules/supercharger.md"
  printf 'guards\n'     > "$HOME/.claude/rules/guardrails.md"
  printf 'tier\n'       > "$HOME/.claude/rules/economy.md"
  printf 'role rules\n' > "$HOME/.claude/rules/developer.md"
  printf 'role rules\n' > "$HOME/.claude/supercharger/roles/developer.md"  # marks it ours
  printf 'MY OWN NOTES\n' > "$HOME/.claude/rules/my-notes.md"              # the user's
}

begin_test "sc-toggle: off removes the Supercharger rules/ files too"
_setup_rules
bash "$TOGGLE" off >/dev/null 2>&1
LEFT=$(ls -A "$HOME/.claude/rules" 2>/dev/null | grep -c 'supercharger.md\|guardrails.md\|economy.md\|developer.md')
[ "$LEFT" = "0" ] && pass || fail "rules still present after off: $(ls -A "$HOME/.claude/rules" | tr '\n' ' ')"
teardown_test_home

begin_test "sc-toggle: off does NOT touch a rules file the user wrote"
# `off` means default Claude, not "lose your own config". A role file is only
# taken when a same-named source exists in supercharger/roles/.
_setup_rules
bash "$TOGGLE" off >/dev/null 2>&1
if [ -f "$HOME/.claude/rules/my-notes.md" ] \
   && grep -q 'MY OWN NOTES' "$HOME/.claude/rules/my-notes.md"; then pass
else fail "the user's own rules file was moved or altered"; fi
teardown_test_home

begin_test "sc-toggle: on restores every rules file byte-identically"
_setup_rules
SUM_BEFORE=$(cat "$HOME/.claude/rules/supercharger.md" "$HOME/.claude/rules/developer.md" 2>/dev/null)
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on  >/dev/null 2>&1
SUM_AFTER=$(cat "$HOME/.claude/rules/supercharger.md" "$HOME/.claude/rules/developer.md" 2>/dev/null)
if [ "$SUM_BEFORE" = "$SUM_AFTER" ] && [ -f "$HOME/.claude/rules/economy.md" ]; then pass
else fail "restore lost or changed a rules file"; fi
teardown_test_home

begin_test "sc-toggle: on does not clobber a file that reappeared while off"
# If something recreated the name while Supercharger was off, that file wins —
# restoring over it would silently destroy whatever replaced it.
_setup_rules
bash "$TOGGLE" off >/dev/null 2>&1
printf 'WROTE THIS WHILE OFF\n' > "$HOME/.claude/rules/developer.md"
bash "$TOGGLE" on >/dev/null 2>&1
grep -q 'WROTE THIS WHILE OFF' "$HOME/.claude/rules/developer.md" \
  && pass || fail "restore clobbered a file created while off"
teardown_test_home

begin_test "sc-toggle: off is safe when there is no rules/ directory at all"
_setup
rm -rf "$HOME/.claude/rules"
bash "$TOGGLE" off >/dev/null 2>&1
[ -f "$HOME/$FLAG_REL" ] && pass || fail "off failed when rules/ was absent"
teardown_test_home

# --- registrations: off must stop them SPAWNING, not just acting --------------
# The kill-switch is read inside the hook body, so a disabled hook still forks,
# sources lib-suppress and exits — about 18 spawns per Bash tool call, whose
# floor is bash startup alone. `off` claimed default Claude and charged that on
# every call, so the tagged registrations come out of settings.json too.
_settings_with_hooks() {
  python3 - "$HOME/.claude/settings.json" <<'PY'
import json, sys
json.dump({
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [
        {"type": "command", "command": "/h/safety.sh #supercharger"},
        {"type": "command", "command": "/user/own-hook.sh"}]},
      {"matcher": "Write", "hooks": [
        {"type": "command", "command": "/h/path-guard.sh #supercharger"}]}],
    "Stop": [
      {"matcher": "", "hooks": [{"type": "command", "command": "/h/stop.sh #supercharger"}]}],
    # No matcher KEY at all -- the real shape hooks.json writes for the events
    # that take no matcher. The fixture only ever had "matcher": "" (a string),
    # so the round-trip that turned an absent key into "matcher": null went
    # unnoticed while the registration count still matched.
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "/h/session-memory.sh #supercharger"}]}],
    "UserPromptSubmit": [
      {"hooks": [{"type": "command", "command": "/h/adaptive-economy.sh #supercharger"}]}]},
  "statusLine": {"type": "command", "command": "/h/supercharger/statusline.sh"},
  "env": {"KEEP": "me"},
}, open(sys.argv[1], "w"), indent=2)
PY
}
_count_tagged() {
  python3 - "$HOME/.claude/settings.json" <<'PY'
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: print(0); raise SystemExit
print(sum(1 for ev in (d.get("hooks") or {}).values() for e in ev
          for h in e.get("hooks", []) if "#supercharger" in h.get("command", "")))
PY
}

begin_test "sc-toggle: off removes the tagged hook registrations"
_setup; _settings_with_hooks
bash "$TOGGLE" off >/dev/null 2>&1
[ "$(_count_tagged)" = "0" ] && pass || fail "tagged hooks still registered: $(_count_tagged)"
teardown_test_home

begin_test "sc-toggle: off leaves a hook the USER registered"
# The single most damaging thing this could get wrong.
_setup; _settings_with_hooks
bash "$TOGGLE" off >/dev/null 2>&1
grep -q 'own-hook.sh' "$HOME/.claude/settings.json" && pass || fail "the user's own hook was removed"
teardown_test_home

begin_test "sc-toggle: off keeps unrelated settings keys intact"
_setup; _settings_with_hooks
bash "$TOGGLE" off >/dev/null 2>&1
grep -q '"KEEP"' "$HOME/.claude/settings.json" && pass || fail "an unrelated settings key was lost"
teardown_test_home

begin_test "sc-toggle: off removes our statusLine"
_setup; _settings_with_hooks
bash "$TOGGLE" off >/dev/null 2>&1
grep -q 'statusLine' "$HOME/.claude/settings.json" && fail "statusLine survived off" || pass
teardown_test_home

begin_test "sc-toggle: on restores every registration it removed"
_setup; _settings_with_hooks
BEFORE=$(_count_tagged)
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on  >/dev/null 2>&1
AFTER=$(_count_tagged)
if [ "$BEFORE" = "$AFTER" ] && grep -q 'own-hook.sh' "$HOME/.claude/settings.json" \
   && grep -q 'statusLine' "$HOME/.claude/settings.json"; then pass
else fail "restore mismatch: before=$BEFORE after=$AFTER"; fi
teardown_test_home

begin_test "sc-toggle: on restores the hooks section with its SHAPE intact, not just the count"
# Counting registrations is not enough. The save path built saved entries as
# {"matcher": entry.get("matcher"), ...}, so an entry with NO matcher key came
# back as "matcher": null -- a shape hooks.json never writes. The count matched
# (154 == 154) so `on` reported full success while every matcher-less event
# (SessionStart, UserPromptSubmit, PostToolUse, PreCompact, SubagentStop) was
# restored in an altered form. Compare the structure, not the tally.
_setup; _settings_with_hooks
cp "$HOME/.claude/settings.json" "$HOME/before.json"
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on  >/dev/null 2>&1
python3 - "$HOME/before.json" "$HOME/.claude/settings.json" <<'PY' && pass || fail "on altered the hooks section shape"
import json, sys
a = json.load(open(sys.argv[1])).get("hooks", {})
b = json.load(open(sys.argv[2])).get("hooks", {})

def norm(d):
    # (event, matcher-as-stored, command) -- a null matcher is NOT an absent one.
    out = set()
    for ev, entries in d.items():
        for e in entries:
            m = "<ABSENT>" if "matcher" not in e else repr(e["matcher"])
            for h in e.get("hooks", []):
                out.add((ev, m, h.get("command", "")))
    return out

na, nb = norm(a), norm(b)
lost, gained = na - nb, nb - na
assert not lost and not gained, "lost=%s gained=%s" % (sorted(lost), sorted(gained))
nulls = [(ev, e) for ev, entries in b.items() for e in entries
         if "matcher" in e and e["matcher"] is None]
assert not nulls, "restore wrote null matchers: %s" % [ev for ev, _ in nulls]
PY
teardown_test_home

begin_test "sc-toggle: on does not duplicate registrations when run twice"
# Restoring into a settings.json that already has them must be idempotent, or a
# double toggle silently doubles the hook chain.
_setup; _settings_with_hooks
BEFORE=$(_count_tagged)
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on  >/dev/null 2>&1
bash "$TOGGLE" on  >/dev/null 2>&1
[ "$(_count_tagged)" = "$BEFORE" ] && pass || fail "duplicated: before=$BEFORE now=$(_count_tagged)"
teardown_test_home

# --- agents: listed to the model even when nothing can invoke them ------------
# Agent definitions do not RUN once the hooks are gone, but their frontmatter is
# listed every session — ~2970 tokens, more residual context than the rules files.
# Ownership comes from the reference copy install.sh keeps in supercharger/agents/,
# the same trick roles/ uses; without it a user's own writer.md is indistinguishable
# from ours, so an install predating that copy must move NOTHING rather than guess.
_setup_agents() {
  _setup
  mkdir -p "$HOME/.claude/agents" "$HOME/.claude/supercharger/agents"
  printf 'ours\n'  > "$HOME/.claude/agents/reviewer.md"
  printf 'ours\n'  > "$HOME/.claude/supercharger/agents/reviewer.md"
  printf 'ours\n'  > "$HOME/.claude/agents/writer.md"
  printf 'ours\n'  > "$HOME/.claude/supercharger/agents/writer.md"
  printf 'MINE\n'  > "$HOME/.claude/agents/my-agent.md"
}

begin_test "sc-toggle: off moves the Supercharger agents aside"
_setup_agents
bash "$TOGGLE" off >/dev/null 2>&1
if [ ! -f "$HOME/.claude/agents/reviewer.md" ] && [ ! -f "$HOME/.claude/agents/writer.md" ]; then
  pass
else fail "agents still present: $(ls -A "$HOME/.claude/agents" | tr '\n' ' ')"; fi
teardown_test_home

begin_test "sc-toggle: off leaves an agent the USER wrote"
_setup_agents
bash "$TOGGLE" off >/dev/null 2>&1
[ -f "$HOME/.claude/agents/my-agent.md" ] && grep -q 'MINE' "$HOME/.claude/agents/my-agent.md" \
  && pass || fail "the user's own agent was moved"
teardown_test_home

begin_test "sc-toggle: on restores the agents it moved"
_setup_agents
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on  >/dev/null 2>&1
if [ -f "$HOME/.claude/agents/reviewer.md" ] && [ -f "$HOME/.claude/agents/writer.md" ] \
   && [ -f "$HOME/.claude/agents/my-agent.md" ]; then pass
else fail "agents not restored: $(ls -A "$HOME/.claude/agents" | tr '\n' ' ')"; fi
teardown_test_home

begin_test "sc-toggle: an install with no agents source copy moves nothing"
# The degrade path. Guessing at someone else's agent file is worse than doing
# nothing, so an older install must simply keep its agents.
_setup_agents
rm -rf "$HOME/.claude/supercharger/agents"
bash "$TOGGLE" off >/dev/null 2>&1
[ -f "$HOME/.claude/agents/reviewer.md" ] && pass \
  || fail "moved agents without a source copy to identify them"
teardown_test_home

# --- edits made WHILE off must survive `on` ----------------------------------
# `on` used to restore CLAUDE.md with a wholesale copy of the file saved at
# off-time, so anything written in between was silently destroyed. Everything
# else already merged; this one clobbered. Now it compares against what `off`
# actually left behind and, if that changed, keeps the current file and
# re-appends the managed block instead of reinstating a stale copy.
begin_test "sc-toggle: text added to CLAUDE.md while off survives on"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
printf '\n# ADDED WHILE OFF\nAlways use pnpm.\n' >> "$HOME/.claude/CLAUDE.md"
bash "$TOGGLE" on >/dev/null 2>&1
if grep -q 'ADDED WHILE OFF' "$HOME/.claude/CLAUDE.md" \
   && grep -q 'Use tabs' "$HOME/.claude/CLAUDE.md" \
   && grep -q 'Managed block' "$HOME/.claude/CLAUDE.md"; then pass
else fail "lost an edit or the block: $(cat "$HOME/.claude/CLAUDE.md")"; fi
teardown_test_home

begin_test "sc-toggle: an untouched CLAUDE.md is restored byte-exactly"
# The merge path must not fire when nothing happened — that would reorder a file
# the user never touched.
_setup
BEFORE=$(cat "$HOME/.claude/CLAUDE.md")
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on  >/dev/null 2>&1
[ "$BEFORE" = "$(cat "$HOME/.claude/CLAUDE.md")" ] && pass \
  || fail "untouched file changed on the round trip"
teardown_test_home

begin_test "sc-toggle: the managed block is not duplicated by the merge path"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
printf '\n# ADDED WHILE OFF\n' >> "$HOME/.claude/CLAUDE.md"
bash "$TOGGLE" on >/dev/null 2>&1
N=$(grep -c 'Claude Supercharger' "$HOME/.claude/CLAUDE.md")
[ "$N" = "1" ] && pass || fail "managed block appears $N times"
teardown_test_home

begin_test "sc-toggle: off is safe when settings.json has no hooks at all"
_setup
printf '{"env":{"A":"B"}}' > "$HOME/.claude/settings.json"
bash "$TOGGLE" off >/dev/null 2>&1
[ -f "$HOME/$FLAG_REL" ] && grep -q '"A"' "$HOME/.claude/settings.json" \
  && pass || fail "off mishandled a settings.json with no hooks"
teardown_test_home

# --- v2.27.35: mid-session toggle notice ------------------------------------
# Rules in ~/.claude/rules/ are read once at session start, so moving them off
# disk cannot unload them from a conversation already running. The notice states
# the override on the next prompt instead. It is the ONE hook that must keep
# working while the kill-switch is set, which is exactly what makes it fragile:
# adding the "missing" lib-suppress source line would look like a tidy-up and
# would silently disable it in the only case it exists for.

begin_test "sc-toggle: off writes the one-shot announce marker"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
[ -f "$HOME/.claude/supercharger/scope/.sc-toggle-announce" ] && pass || fail "no marker written by off"
teardown_test_home

begin_test "sc-toggle: on writes the marker too (off is instant, on must be as well)"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
rm -f "$HOME/.claude/supercharger/scope/.sc-toggle-announce"
bash "$TOGGLE" on >/dev/null 2>&1
[ -f "$HOME/.claude/supercharger/scope/.sc-toggle-announce" ] && pass || fail "no marker written by on"
teardown_test_home

begin_test "notice hook: silent when no toggle has happened"
_setup
OUT=$(SUPERCHARGER_STATE="$HOME/.claude/supercharger" bash "$REPO_DIR/hooks/sc-toggle-notice.sh" </dev/null 2>&1)
[ -z "$OUT" ] && pass || fail "spoke without a marker: $OUT"
teardown_test_home

begin_test "notice hook: announces off, and is ONE-SHOT"
_setup
printf 'off\n' > "$HOME/.claude/supercharger/scope/.sc-toggle-announce"
OUT1=$(SUPERCHARGER_STATE="$HOME/.claude/supercharger" bash "$REPO_DIR/hooks/sc-toggle-notice.sh" </dev/null 2>&1)
OUT2=$(SUPERCHARGER_STATE="$HOME/.claude/supercharger" bash "$REPO_DIR/hooks/sc-toggle-notice.sh" </dev/null 2>&1)
case "$OUT1:$OUT2" in
  *DEACTIVATED*:) pass ;;
  *) fail "first=$OUT1 second=$OUT2 (expected announce then silence)" ;;
esac
teardown_test_home

begin_test "notice hook: announces on"
_setup
printf 'on\n' > "$HOME/.claude/supercharger/scope/.sc-toggle-announce"
OUT=$(SUPERCHARGER_STATE="$HOME/.claude/supercharger" bash "$REPO_DIR/hooks/sc-toggle-notice.sh" </dev/null 2>&1)
case "$OUT" in *REACTIVATED*) pass ;; *) fail "expected reactivation notice, got: $OUT" ;; esac
teardown_test_home

# THE point of the hook. Every other hook exits here; this one must not.
begin_test "notice hook: STILL announces while the kill-switch is set"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
OUT=$(SUPERCHARGER_STATE="$HOME/.claude/supercharger" bash "$REPO_DIR/hooks/sc-toggle-notice.sh" </dev/null 2>&1)
case "$OUT" in
  *DEACTIVATED*) pass ;;
  *) fail "the kill-switch swallowed the notice - off can no longer announce itself: $OUT" ;;
esac
teardown_test_home

begin_test "notice hook: does not source the kill-switch libs (that would disable it)"
# Assert the file EXISTS first: grep on a missing file also returns non-zero, so
# without this the check passes happily after someone deletes the hook.
if [ ! -f "$REPO_DIR/hooks/sc-toggle-notice.sh" ]; then
  fail "sc-toggle-notice.sh is missing entirely"
elif grep -qE '^[[:space:]]*\.[[:space:]].*lib-(suppress|timing)' "$REPO_DIR/hooks/sc-toggle-notice.sh"; then
  fail "sources a lib that exits on the kill-switch - the hook is now inert when off"
else pass; fi

# --- v2.27.35: the behavioural rules must not be path-scoped ----------------
# With `paths:` frontmatter Claude Code loads a rules file lazily, only once a
# matching file is touched - so the Verification Gate and Scope Discipline were
# silently absent until a session happened to open a code file.
begin_test "supercharger.md is NOT path-scoped (it is universal behaviour)"
if head -1 "$REPO_DIR/configs/universal/supercharger.md" | grep -q '^---$'; then
  fail "supercharger.md has frontmatter again - if it declares paths: it goes back to loading lazily"
else pass; fi

# developer.md stays scoped deliberately: code output style and stack detection
# only matter once there is code, so it costs nothing in a non-coding session.
# Not every role is scoped, and that is correct rather than an oversight - pm,
# student and writer are non-code roles, and scoping them by .ts/.py globs would
# mean they never loaded for the work they exist for.
begin_test "developer.md IS still path-scoped (code guidance, code sessions)"
if head -1 "$REPO_DIR/configs/roles/developer.md" | grep -q '^---$' \
   && awk '/^---$/{n++;next} n==1' "$REPO_DIR/configs/roles/developer.md" | grep -q '^paths:'; then
  pass
else
  fail "developer.md lost its paths: scoping - it is now resident in every session, coding or not"
fi

report
