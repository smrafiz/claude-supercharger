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

report
