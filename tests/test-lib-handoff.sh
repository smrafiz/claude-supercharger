#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

. "$REPO_DIR/hooks/lib-handoff.sh"

echo "=== Handoff file selector (session-scoping) Tests ==="

SID="aaaaaaaa-1111-2222-3333-444444444444"
OTHER="bbbbbbbb-5555-6666-7777-888888888888"

fresh_setup() { # returns a clean project dir with a .claude subdir
  local d; d=$(mktemp -d); mkdir -p "$d/.claude"; printf '%s' "$d"
}
# make a handoff file with content = its own name, at an mtime N seconds in the past
mkho() { printf 'brief:%s\n' "$2" > "$1"; }
age()  { local t; t=$(( $(date +%s) - $2 )); touch -t "$(date -r "$t" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$t" +%Y%m%d%H%M.%S)" "$1"; }

# 1. own-SID wins even when another session's file is newer
D=$(fresh_setup)
mkho "$D/.claude/handoff-$SID.md" own;  age "$D/.claude/handoff-$SID.md" 100
mkho "$D/.claude/handoff-$OTHER.md" other; age "$D/.claude/handoff-$OTHER.md" 10   # newer
begin_test "own-SID preferred over a newer other-session file"
GOT=$(select_handoff_file "$D" "$SID" 604800)
[ "$GOT" = "$D/.claude/handoff-$SID.md" ] && pass || fail "got $GOT"

# 2. no own-SID → newest session-scoped wins
D=$(fresh_setup)
mkho "$D/.claude/handoff-$OTHER.md" other; age "$D/.claude/handoff-$OTHER.md" 50
mkho "$D/.claude/handoff-cccccccc.md" ccc;  age "$D/.claude/handoff-cccccccc.md" 5   # newest
begin_test "no own-SID → newest scoped file"
GOT=$(select_handoff_file "$D" "$SID" 604800)
[ "$GOT" = "$D/.claude/handoff-cccccccc.md" ] && pass || fail "got $GOT"

# 3. legacy unsuffixed fallback when no scoped file exists
D=$(fresh_setup)
mkho "$D/.claude/handoff.md" legacy; age "$D/.claude/handoff.md" 100
begin_test "legacy handoff.md fallback"
GOT=$(select_handoff_file "$D" "$SID" 604800)
[ "$GOT" = "$D/.claude/handoff.md" ] && pass || fail "got $GOT"

# 4. scoped file beats legacy when scoped is newer
D=$(fresh_setup)
mkho "$D/.claude/handoff.md" legacy;         age "$D/.claude/handoff.md" 100
mkho "$D/.claude/handoff-$SID.md" own;        age "$D/.claude/handoff-$SID.md" 10
begin_test "own scoped beats legacy"
GOT=$(select_handoff_file "$D" "$SID" 604800)
[ "$GOT" = "$D/.claude/handoff-$SID.md" ] && pass || fail "got $GOT"

# 5. stale own-SID (older than gate) → falls back to a fresh other-session file
D=$(fresh_setup)
mkho "$D/.claude/handoff-$SID.md" own;   age "$D/.claude/handoff-$SID.md" 700000   # >7d
mkho "$D/.claude/handoff-$OTHER.md" other; age "$D/.claude/handoff-$OTHER.md" 10
begin_test "stale own-SID falls back to fresh other under gate"
GOT=$(select_handoff_file "$D" "$SID" 604800)
[ "$GOT" = "$D/.claude/handoff-$OTHER.md" ] && pass || fail "got $GOT"

# 6. gate=0 (compaction) → stale own-SID still returned
D=$(fresh_setup)
mkho "$D/.claude/handoff-$SID.md" own; age "$D/.claude/handoff-$SID.md" 700000
begin_test "gate=0 returns own-SID regardless of age"
GOT=$(select_handoff_file "$D" "$SID" 0)
[ "$GOT" = "$D/.claude/handoff-$SID.md" ] && pass || fail "got $GOT"

# 7. everything stale under a 7d gate → empty
D=$(fresh_setup)
mkho "$D/.claude/handoff-$OTHER.md" other; age "$D/.claude/handoff-$OTHER.md" 700000
begin_test "all stale under gate → empty"
GOT=$(select_handoff_file "$D" "$SID" 604800)
[ -z "$GOT" ] && pass || fail "expected empty, got $GOT"

# 8. no files at all → empty, no error
D=$(fresh_setup)
begin_test "no handoff files → empty"
GOT=$(select_handoff_file "$D" "$SID" 604800)
[ -z "$GOT" ] && pass || fail "expected empty, got $GOT"

# 9. empty SID → still returns newest scoped (no own-SID match)
D=$(fresh_setup)
mkho "$D/.claude/handoff-$OTHER.md" other; age "$D/.claude/handoff-$OTHER.md" 20
begin_test "empty SID → newest scoped"
GOT=$(select_handoff_file "$D" "" 604800)
[ "$GOT" = "$D/.claude/handoff-$OTHER.md" ] && pass || fail "got $GOT"

report
