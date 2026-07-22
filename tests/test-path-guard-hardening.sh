#!/usr/bin/env bash
# Suite for path-guard.sh hardening (v2.22.1) — case-insensitive FS bypasses and
# symlink-redirected writes found by the adversarial audit.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/path-guard.sh"

PROJ=$(mktemp -d); OUT=$(mktemp -d)
(cd "$PROJ" && git init -q 2>/dev/null)
ln -s "$OUT/authorized_keys" "$PROJ/innocent.json"   # basename symlink → outside
ln -s ".git" "$PROJ/g"                                # dir alias → .git

# deny? <file_path> → DENY|ALLOW  (file_path may be relative to PROJ or absolute)
verdict() {
  local j; j=$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s","content":"x"}}' "$PROJ" "$1")
  bash "$H" <<<"$j" 2>&1 | grep -q '"deny"' && echo DENY || echo ALLOW
}

# ---- case-insensitive FS bypasses (must DENY) ----
begin_test "path-guard: .GIT/config (case) is denied"
[ "$(verdict ".GIT/config")" = DENY ] && pass || fail "case .GIT/config allowed"
begin_test "path-guard: .SUPERCHARGER.json (case) is denied"
[ "$(verdict ".SUPERCHARGER.json")" = DENY ] && pass || fail "case .SUPERCHARGER.json allowed (could disable guards)"
begin_test "path-guard: .CLAUDE/settings.json (case) is denied"
[ "$(verdict ".CLAUDE/settings.json")" = DENY ] && pass || fail "case .CLAUDE/settings.json allowed"
begin_test "path-guard: .NEXT/ artifact (case) is denied"
[ "$(verdict ".NEXT/evil.js")" = DENY ] && pass || fail "case .NEXT/ allowed"

# ---- symlink-redirected writes (must DENY) ----
begin_test "path-guard: absolute basename symlink to outside is denied"
[ "$(verdict "$PROJ/innocent.json")" = DENY ] && pass || fail "basename symlink escape allowed"
begin_test "path-guard: relative dir-alias g/config (→.git) is denied"
[ "$(verdict "g/config")" = DENY ] && pass || fail "dir-alias to .git allowed (rel)"
begin_test "path-guard: absolute dir-alias g/config (→.git) is denied"
[ "$(verdict "$PROJ/g/config")" = DENY ] && pass || fail "dir-alias to .git allowed (abs)"

# ---- regressions: still deny the lowercase forms ----
begin_test "path-guard: plain .git/config still denied"
[ "$(verdict ".git/config")" = DENY ] && pass || fail ".git/config regressed"
begin_test "path-guard: plain .supercharger.json still denied"
[ "$(verdict ".supercharger.json")" = DENY ] && pass || fail ".supercharger.json regressed"

# ---- regressions: normal in-project writes still allowed ----
begin_test "path-guard: normal relative in-project write allowed"
[ "$(verdict "src/index.ts")" = ALLOW ] && pass || fail "normal rel write over-blocked"
begin_test "path-guard: normal absolute in-project write allowed"
[ "$(verdict "$PROJ/src/app.ts")" = ALLOW ] && pass || fail "normal abs write over-blocked"

# ---- memory-store allowance intact (absolute, outside proj, but permitted) ----
ENC="-$(echo "$PROJ" | sed 's|/|-|g; s|^-||')"
MEMDIR="$HOME/.claude/projects/$ENC/memory"; mkdir -p "$MEMDIR"
begin_test "path-guard: Claude file-memory write still allowed"
[ "$(verdict "$MEMDIR/note.md")" = ALLOW ] && pass || fail "memory-store write wrongly blocked"
rm -rf "$HOME/.claude/projects/$ENC" 2>/dev/null

rm -rf "$PROJ" "$OUT"
report
