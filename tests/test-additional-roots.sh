#!/usr/bin/env bash
# additionalRoots — sibling directories that count as in-project (v2.26.41)
#
# Field report: a wrapper directory holding two sibling repos (a free and a pro
# plugin that must be edited together). With cwd in one repo, path-guard denied
# every write to the other in BOTH directions. The v2.23.13 git-toplevel widening
# does not help — the toplevel of one repo is that repo.
#
# The workarounds on offer were both far too broad: `/sc off` disables every
# guard, and disableSecurityCategories:["abs-path"] also unprotects ~/.ssh,
# ~/.aws and /etc. This adds a narrow, additive, committed alternative.
#
# MOST OF THIS FILE IS REFUSALS. The feature is six lines; what keeps it from
# being a rebranded bypass is that '/', '$HOME', an ancestor of $HOME, and
# ~/.claude can never become project roots, and that the credential list stays
# blocked no matter what is whitelisted.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GUARD="$REPO_DIR/hooks/path-guard.sh"

# Real path: on macOS $TMPDIR is under /var -> /private/var, and an unresolved
# tmp path trips the SYMLINK check before abs-path is ever reached (that cost me
# a confusing first repro).
newlayout() { # -> echoes wrapper dir with free/ and pro/ as separate git repos
  local b; b=$(mktemp -d); b=$(cd "$b" && pwd -P)
  local w="$b/wrapper"
  mkdir -p "$w/free" "$w/pro"
  git -C "$w/free" init -q 2>/dev/null
  git -C "$w/pro" init -q 2>/dev/null
  printf '<?php\n' > "$w/pro/pro.php"
  printf '<?php\n' > "$w/free/free.php"
  printf '%s' "$w"
}

cfg() { # dir, json
  printf '%s\n' "$2" > "$1/.supercharger.json"
}

edit_from() { # cwd, target -> sets RC/OUT
  OUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$2" "$1" \
    | bash "$GUARD" 2>/dev/null)
  RC=$?
}

echo "=== additionalRoots Tests ==="

# --- the reported bug ---------------------------------------------------------
begin_test "without config, a sibling repo is denied (the reported bug)"
W=$(newlayout)
edit_from "$W/free" "$W/pro/pro.php"
[ "$RC" -eq 2 ] && pass || fail "expected deny before config, got rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "additionalRoots allows the sibling"
W=$(newlayout); cfg "$W/free" '{"additionalRoots":["../pro"]}'
edit_from "$W/free" "$W/pro/pro.php"
[ "$RC" -eq 0 ] && pass || fail "sibling still denied with additionalRoots: rc=$RC out=$OUT"
rm -rf "$(dirname "$W")"

begin_test "and the reverse direction, configured in the other repo"
W=$(newlayout); cfg "$W/pro" '{"additionalRoots":["../free"]}'
edit_from "$W/pro" "$W/free/free.php"
[ "$RC" -eq 0 ] && pass || fail "reverse direction denied: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "an absolute root works as well as a relative one"
W=$(newlayout); cfg "$W/free" "{\"additionalRoots\":[\"$W/pro\"]}"
edit_from "$W/free" "$W/pro/pro.php"
[ "$RC" -eq 0 ] && pass || fail "absolute root rejected: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "a root only widens the repo it is configured in"
# free/ lists pro/, but a session in pro/ has no config -> still denied.
W=$(newlayout); cfg "$W/free" '{"additionalRoots":["../pro"]}'
edit_from "$W/pro" "$W/free/free.php"
[ "$RC" -eq 2 ] && pass || fail "config leaked across repos: rc=$RC"
rm -rf "$(dirname "$W")"

# --- refusals: the load-bearing half -----------------------------------------
begin_test "REFUSES '/' as a root"
W=$(newlayout); cfg "$W/free" '{"additionalRoots":["/"]}'
edit_from "$W/free" "/etc/hosts"
[ "$RC" -eq 2 ] && pass || fail "'/' was accepted as a project root — guard disabled: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "REFUSES \$HOME as a root"
W=$(newlayout); cfg "$W/free" "{\"additionalRoots\":[\"$HOME\"]}"
edit_from "$W/free" "$HOME/.ssh/authorized_keys"
[ "$RC" -eq 2 ] && pass || fail "\$HOME accepted as a root: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "REFUSES an ancestor of \$HOME (e.g. /Users)"
W=$(newlayout); cfg "$W/free" "{\"additionalRoots\":[\"$(dirname "$HOME")\"]}"
edit_from "$W/free" "$HOME/.aws/credentials"
[ "$RC" -eq 2 ] && pass || fail "ancestor of HOME accepted: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "REFUSES ~/.claude (its own config and state)"
W=$(newlayout); cfg "$W/free" "{\"additionalRoots\":[\"$HOME/.claude\"]}"
edit_from "$W/free" "$HOME/.claude/settings.json"
[ "$RC" -eq 2 ] && pass || fail "~/.claude accepted as a project root: rc=$RC"
rm -rf "$(dirname "$W")"

# The three refusal tests above aim at ~/.ssh, ~/.aws and /etc — all of which are
# on the credential list and would be denied even if the root HAD been accepted.
# They would therefore pass vacuously. These aim at targets that ONLY the refusal
# can block, so they fail if the refusal logic is removed.
begin_test "REFUSES '/' — proven with a target that is not on the credential list"
W=$(newlayout); OTHER=$(mktemp -d); OTHER=$(cd "$OTHER" && pwd -P)
cfg "$W/free" '{"additionalRoots":["/"]}'
edit_from "$W/free" "$OTHER/anywhere.php"
[ "$RC" -eq 2 ] && pass || fail "'/' as a root made an arbitrary dir writable: rc=$RC"
rm -rf "$(dirname "$W")" "$OTHER"

begin_test "REFUSES \$HOME — proven with a plain file, not a credential path"
W=$(newlayout); cfg "$W/free" "{\"additionalRoots\":[\"$HOME\"]}"
edit_from "$W/free" "$HOME/sc-additional-roots-probe.txt"
[ "$RC" -eq 2 ] && pass || fail "\$HOME as a root made the home dir writable: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "the credential list stays blocked even with a legitimate root set"
# The whitelist is real and used; ~/.ssh must STILL be refused. This is the
# property that makes additionalRoots additive rather than a bypass.
W=$(newlayout); cfg "$W/free" '{"additionalRoots":["../pro"]}'
edit_from "$W/free" "$HOME/.ssh/config"
[ "$RC" -eq 2 ] && pass || fail "credential path reachable with a root configured: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "a non-existent root is ignored, not silently trusted"
W=$(newlayout); cfg "$W/free" '{"additionalRoots":["../typo-not-here"]}'
edit_from "$W/free" "$W/pro/pro.php"
[ "$RC" -eq 2 ] && pass || fail "a typo'd root appeared to work: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "a file (not a directory) is not accepted as a root"
W=$(newlayout); cfg "$W/free" '{"additionalRoots":["../pro/pro.php"]}'
edit_from "$W/free" "$W/pro/pro.php"
[ "$RC" -eq 2 ] && pass || fail "a file was accepted as a root: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "a symlinked root resolves to its true target before being trusted"
# ln -s / evil  =>  the root must resolve to '/' and be refused, not trusted
# because the symlink itself sits beside the project.
W=$(newlayout); ln -s / "$W/free/evil-link"
cfg "$W/free" '{"additionalRoots":["./evil-link"]}'
edit_from "$W/free" "/etc/hosts"
[ "$RC" -eq 2 ] && pass || fail "symlink to / was trusted as a root: rc=$RC"
rm -rf "$(dirname "$W")"

# --- robustness ---------------------------------------------------------------
begin_test "malformed .supercharger.json does not break the guard"
W=$(newlayout); printf '{ this is not json' > "$W/free/.supercharger.json"
edit_from "$W/free" "$W/pro/pro.php"
[ "$RC" -eq 2 ] && pass || fail "malformed config changed the verdict: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "a non-list additionalRoots value is ignored"
W=$(newlayout); cfg "$W/free" '{"additionalRoots":"../pro"}'
edit_from "$W/free" "$W/pro/pro.php"
[ "$RC" -eq 2 ] && pass || fail "a string value was treated as a root list: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "non-string entries are skipped without breaking valid ones"
W=$(newlayout); cfg "$W/free" '{"additionalRoots":[123,null,"../pro"]}'
edit_from "$W/free" "$W/pro/pro.php"
[ "$RC" -eq 0 ] && pass || fail "valid root lost to invalid siblings: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "writes inside the project still work (no regression)"
W=$(newlayout); cfg "$W/free" '{"additionalRoots":["../pro"]}'
edit_from "$W/free" "$W/free/free.php"
[ "$RC" -eq 0 ] && pass || fail "in-project write broke: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "an unrelated outside directory is still denied"
W=$(newlayout); OTHER=$(mktemp -d); OTHER=$(cd "$OTHER" && pwd -P)
cfg "$W/free" '{"additionalRoots":["../pro"]}'
edit_from "$W/free" "$OTHER/x.php"
[ "$RC" -eq 2 ] && pass || fail "whitelisting pro/ opened an unrelated dir: rc=$RC"
rm -rf "$(dirname "$W")" "$OTHER"

begin_test "no config at all behaves exactly as before"
W=$(newlayout)
edit_from "$W/free" "$W/free/free.php"
[ "$RC" -eq 0 ] && pass || fail "in-project write broke without config: rc=$RC"
rm -rf "$(dirname "$W")"

# --- session launch root (v2.26.42) ------------------------------------------
# The reported sequence: Claude opened in the WRAPPER, cwd later moved into one
# repo, and the sibling silently left the project. Carrying the launch dir keeps
# the boundary where the user opened it. No .supercharger.json involved.
SR_STATE=""
with_session_root() { # launch_dir, cwd, target
  SR_STATE=$(mktemp -d); mkdir -p "$SR_STATE/scope"
  printf '%s\n' "$1" > "$SR_STATE/scope/.session-root-tsid"
  OUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$3" "$2" \
    | CLAUDE_CODE_SESSION_ID=tsid SUPERCHARGER_STATE="$SR_STATE" bash "$GUARD" 2>/dev/null)
  RC=$?
  rm -rf "$SR_STATE"
}

begin_test "launched in the wrapper, cwd moved into free/ — sibling still writable"
W=$(newlayout)
with_session_root "$W" "$W/free" "$W/pro/pro.php"
[ "$RC" -eq 0 ] && pass || fail "the reported bug is not fixed by the session root: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "without the recorded root, the same edit is denied (proves it is doing the work)"
W=$(newlayout)
edit_from "$W/free" "$W/pro/pro.php"
[ "$RC" -eq 2 ] && pass || fail "control failed — the deny is not coming from the boundary: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "a session launched in \$HOME does NOT make the home dir in-project"
# Launching Claude from ~ is common; pinning to it would be a silent, enormous
# widening. It goes through the same refusals as a configured root.
W=$(newlayout)
with_session_root "$HOME" "$W/free" "$HOME/sc-session-root-probe.txt"
[ "$RC" -eq 2 ] && pass || fail "launching from \$HOME opened the whole home dir: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "a session launched at / does not open the filesystem"
W=$(newlayout); OTHER=$(mktemp -d); OTHER=$(cd "$OTHER" && pwd -P)
with_session_root "/" "$W/free" "$OTHER/anywhere.php"
[ "$RC" -eq 2 ] && pass || fail "launching from / opened everything: rc=$RC"
rm -rf "$(dirname "$W")" "$OTHER"

begin_test "credential paths stay blocked with a valid session root"
W=$(newlayout)
with_session_root "$W" "$W/free" "$HOME/.ssh/config"
[ "$RC" -eq 2 ] && pass || fail "session root reached the credential list: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "an unrelated directory is still outside a valid session root"
W=$(newlayout); OTHER=$(mktemp -d); OTHER=$(cd "$OTHER" && pwd -P)
with_session_root "$W" "$W/free" "$OTHER/x.php"
[ "$RC" -eq 2 ] && pass || fail "session root leaked to an unrelated dir: rc=$RC"
rm -rf "$(dirname "$W")" "$OTHER"

begin_test "a stale root pointing at a deleted dir is ignored, not trusted"
W=$(newlayout); GONE=$(mktemp -d); GONE=$(cd "$GONE" && pwd -P); rm -rf "$GONE"
with_session_root "$GONE" "$W/free" "$W/pro/pro.php"
[ "$RC" -eq 2 ] && pass || fail "a deleted session root was trusted: rc=$RC"
rm -rf "$(dirname "$W")"

# --- the recording half (project-config.sh at SessionStart) -------------------
fire_session_start() { # state_dir, sid, cwd
  printf '{"cwd":"%s"}' "$3" \
    | CLAUDE_CODE_SESSION_ID="$2" SUPERCHARGER_STATE="$1" \
      bash "$REPO_DIR/hooks/project-config.sh" >/dev/null 2>&1 || true
}

begin_test "SessionStart records the launch directory"
ST=$(mktemp -d); mkdir -p "$ST/scope"; W=$(newlayout)
fire_session_start "$ST" sid1 "$W"
[ "$(cat "$ST/scope/.session-root-sid1" 2>/dev/null)" = "$W" ] && pass \
  || fail "launch dir not recorded: $(ls -A "$ST/scope" | tr '\n' ' ')"
rm -rf "$ST" "$(dirname "$W")"

begin_test "the recorded root is WRITE-ONCE (SessionStart also fires on resume/compact)"
# If a later SessionStart overwrote it with the moved cwd, the fix would undo
# itself precisely in the situation it exists for.
ST=$(mktemp -d); mkdir -p "$ST/scope"; W=$(newlayout)
fire_session_start "$ST" sid1 "$W"
fire_session_start "$ST" sid1 "$W/free"
[ "$(cat "$ST/scope/.session-root-sid1" 2>/dev/null)" = "$W" ] && pass \
  || fail "root was overwritten after cwd moved: $(cat "$ST/scope/.session-root-sid1" 2>/dev/null)"
rm -rf "$ST" "$(dirname "$W")"

begin_test "roots are per-session, never shared between sessions"
ST=$(mktemp -d); mkdir -p "$ST/scope"; W=$(newlayout)
fire_session_start "$ST" sid1 "$W"
fire_session_start "$ST" sid2 "$W/free"
[ "$(cat "$ST/scope/.session-root-sid2" 2>/dev/null)" = "$W/free" ] && pass \
  || fail "second session inherited the first session's root"
rm -rf "$ST" "$(dirname "$W")"

begin_test "no session id — nothing recorded, guard unaffected"
ST=$(mktemp -d); mkdir -p "$ST/scope"; W=$(newlayout)
printf '{"cwd":"%s"}' "$W" | CLAUDE_CODE_SESSION_ID="" SUPERCHARGER_STATE="$ST" \
  bash "$REPO_DIR/hooks/project-config.sh" >/dev/null 2>&1 || true
[ -z "$(ls -A "$ST/scope" 2>/dev/null | grep '^\.session-root' || true)" ] && pass \
  || fail "wrote a root with no session id"
rm -rf "$ST" "$(dirname "$W")"

# --- Claude Code's own directory authorisation (v2.26.43) ---------------------
# CC has three ways to put a directory in the workspace: --add-dir, /add-dir, and
# permissions.additionalDirectories. path-guard honoured NONE of them, so a user
# who authorised a directory through the product's front door still had every
# write to it denied. Verified by grep before building: zero references.
RECORDER="$REPO_DIR/hooks/dir-added-record.sh"

cc_settings() { # dir, json  -> writes <dir>/.claude/settings.json
  mkdir -p "$1/.claude"
  printf '%s\n' "$2" > "$1/.claude/settings.json"
}

begin_test "permissions.additionalDirectories (project settings) widens the boundary"
W=$(newlayout)
cc_settings "$W/free" "{\"permissions\":{\"additionalDirectories\":[\"$W/pro\"]}}"
edit_from "$W/free" "$W/pro/pro.php"
[ "$RC" -eq 0 ] && pass || fail "CC additionalDirectories ignored: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "without it, the same edit is denied (the setting is doing the work)"
W=$(newlayout)
edit_from "$W/free" "$W/pro/pro.php"
[ "$RC" -eq 2 ] && pass || fail "control failed: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "a relative additionalDirectories entry resolves against the project"
W=$(newlayout)
cc_settings "$W/free" '{"permissions":{"additionalDirectories":["../pro"]}}'
edit_from "$W/free" "$W/pro/pro.php"
[ "$RC" -eq 0 ] && pass || fail "relative CC dir not resolved: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "REFUSES additionalDirectories:[\$HOME] — CC read access is not write consent"
# CC granting visibility into a tree must not silently make it writable here.
W=$(newlayout)
cc_settings "$W/free" "{\"permissions\":{\"additionalDirectories\":[\"$HOME\"]}}"
edit_from "$W/free" "$HOME/sc-ccdir-probe.txt"
[ "$RC" -eq 2 ] && pass || fail "CC-authorised \$HOME made the home dir writable: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "REFUSES additionalDirectories:[/]"
W=$(newlayout); OTHER=$(mktemp -d); OTHER=$(cd "$OTHER" && pwd -P)
cc_settings "$W/free" '{"permissions":{"additionalDirectories":["/"]}}'
edit_from "$W/free" "$OTHER/anywhere.php"
[ "$RC" -eq 2 ] && pass || fail "CC-authorised / opened everything: rc=$RC"
rm -rf "$(dirname "$W")" "$OTHER"

begin_test "credential paths stay blocked with a valid CC directory set"
W=$(newlayout)
cc_settings "$W/free" "{\"permissions\":{\"additionalDirectories\":[\"$W/pro\"]}}"
edit_from "$W/free" "$HOME/.ssh/config"
[ "$RC" -eq 2 ] && pass || fail "CC dir reached the credential list: rc=$RC"
rm -rf "$(dirname "$W")"

begin_test "malformed settings.json does not break the guard"
W=$(newlayout); mkdir -p "$W/free/.claude"
printf '{ not json' > "$W/free/.claude/settings.json"
edit_from "$W/free" "$W/free/free.php"
[ "$RC" -eq 0 ] && pass || fail "malformed CC settings broke an in-project write: rc=$RC"
rm -rf "$(dirname "$W")"

# --- the in-session /add-dir recorder ----------------------------------------
record_dir() { # state_dir, sid, payload_json
  printf '%s' "$3" | CLAUDE_CODE_SESSION_ID="$2" SUPERCHARGER_STATE="$1" \
    bash "$RECORDER" >/dev/null 2>&1 || true
}

begin_test "DirectoryAdded records the added directory"
ST=$(mktemp -d); mkdir -p "$ST/scope"; W=$(newlayout)
record_dir "$ST" sid1 "{\"directory\":\"$W/pro\"}"
grep -Fxq "$W/pro" "$ST/scope/.session-dirs-sid1" 2>/dev/null && pass \
  || fail "not recorded: $(ls -A "$ST/scope" 2>/dev/null | tr '\n' ' ')"
rm -rf "$ST" "$(dirname "$W")"

begin_test "a recorded /add-dir directory becomes writable"
ST=$(mktemp -d); mkdir -p "$ST/scope"; W=$(newlayout)
record_dir "$ST" sid1 "{\"directory\":\"$W/pro\"}"
OUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$W/pro/pro.php" "$W/free" \
  | CLAUDE_CODE_SESSION_ID=sid1 SUPERCHARGER_STATE="$ST" bash "$GUARD" 2>/dev/null); RC=$?
rm -rf "$ST" "$(dirname "$W")"
[ "$RC" -eq 0 ] && pass || fail "recorded /add-dir directory still denied: rc=$RC"

begin_test "the recorder reads alternate payload field names"
ST=$(mktemp -d); mkdir -p "$ST/scope"; W=$(newlayout)
record_dir "$ST" sid1 "{\"path\":\"$W/pro\"}"
grep -Fxq "$W/pro" "$ST/scope/.session-dirs-sid1" 2>/dev/null && pass || fail "'path' field ignored"
rm -rf "$ST" "$(dirname "$W")"

begin_test "a relative added dir is resolved against cwd"
ST=$(mktemp -d); mkdir -p "$ST/scope"; W=$(newlayout)
record_dir "$ST" sid1 "{\"directory\":\"../pro\",\"cwd\":\"$W/free\"}"
grep -q 'pro' "$ST/scope/.session-dirs-sid1" 2>/dev/null && pass || fail "relative dir not resolved"
rm -rf "$ST" "$(dirname "$W")"

begin_test "duplicate /add-dir calls do not grow the file"
ST=$(mktemp -d); mkdir -p "$ST/scope"; W=$(newlayout)
record_dir "$ST" sid1 "{\"directory\":\"$W/pro\"}"
record_dir "$ST" sid1 "{\"directory\":\"$W/pro\"}"
[ "$(wc -l < "$ST/scope/.session-dirs-sid1" | tr -d ' ')" = "1" ] && pass || fail "duplicate appended"
rm -rf "$ST" "$(dirname "$W")"

begin_test "recorded dirs are per-session"
ST=$(mktemp -d); mkdir -p "$ST/scope"; W=$(newlayout)
record_dir "$ST" sid1 "{\"directory\":\"$W/pro\"}"
[ ! -f "$ST/scope/.session-dirs-sid2" ] && pass || fail "leaked into another session"
rm -rf "$ST" "$(dirname "$W")"

begin_test "RECORDING IS NOT TRUST — /add-dir \$HOME is still refused by the guard"
# The recorder is deliberately permissive; path-guard applies the refusals.
ST=$(mktemp -d); mkdir -p "$ST/scope"; W=$(newlayout)
record_dir "$ST" sid1 "{\"directory\":\"$HOME\"}"
OUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$HOME/sc-adddir-probe.txt" "$W/free" \
  | CLAUDE_CODE_SESSION_ID=sid1 SUPERCHARGER_STATE="$ST" bash "$GUARD" 2>/dev/null); RC=$?
rm -rf "$ST" "$(dirname "$W")"
[ "$RC" -eq 2 ] && pass || fail "/add-dir \$HOME made the home dir writable: rc=$RC"

begin_test "no session id — the recorder writes nothing"
ST=$(mktemp -d); mkdir -p "$ST/scope"; W=$(newlayout)
printf '{"directory":"%s"}' "$W/pro" | CLAUDE_CODE_SESSION_ID="" SUPERCHARGER_STATE="$ST" \
  bash "$RECORDER" >/dev/null 2>&1 || true
[ -z "$(ls -A "$ST/scope" 2>/dev/null)" ] && pass || fail "wrote without a session id"
rm -rf "$ST" "$(dirname "$W")"

begin_test "the recorder is NOT registered — DirectoryAdded is not a real event"
# This test used to assert the opposite, and passing is exactly what hid the bug:
# it checked that the registration was WRITTEN, never that Claude Code dispatches
# the event. It does not — CC names the valid set in its own error and
# DirectoryAdded is absent — so the hook never fired and path-guard's in-session
# `/add-dir` support never worked, for four releases, with this test green.
#
# The registration is gone (see lib/hooks.sh). The script stays: its logic is
# tested above and is ready if CC ever ships such an event. What must not come
# back is the REGISTRATION, so that is what this pins.
# Event names are validated wholesale in tests/test-hook-events.sh.
if grep -q 'DirectoryAdded' "$REPO_DIR/lib/hooks.sh" \
   && grep -qE 'hooks\+=\("DirectoryAdded' "$REPO_DIR/lib/hooks.sh"; then
  fail "DirectoryAdded registration is back — the hook cannot fire on that event"
else
  pass
fi

begin_test "session root and additionalRoots compose"
W=$(newlayout); OTHER=$(mktemp -d); OTHER=$(cd "$OTHER" && pwd -P); mkdir -p "$OTHER/third"
cfg "$W/free" "{\"additionalRoots\":[\"$OTHER/third\"]}"
with_session_root "$W" "$W/free" "$OTHER/third/x.php"
[ "$RC" -eq 0 ] && pass || fail "config root lost when a session root is present: rc=$RC"
rm -rf "$(dirname "$W")" "$OTHER"

report
