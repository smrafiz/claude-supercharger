#!/usr/bin/env bash
# Tests for v2.6.84 per-MCP-server safety hooks:
#   - mcp-github-write-gate.sh
#   - mcp-playwright-guard.sh
#   - mcp-sql-guard.sh
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GH="$REPO_DIR/hooks/mcp-github-write-gate.sh"
PW="$REPO_DIR/hooks/mcp-playwright-guard.sh"
SQL="$REPO_DIR/hooks/mcp-sql-guard.sh"

echo "=== MCP Per-Server Guard Tests (v2.6.84) ==="

export SUPERCHARGER_NO_DEDUP=1

# ---------- GitHub write gate ----------
begin_test "github-gate: blocks merge_pull_request"
echo '{"tool_name":"mcp__github__merge_pull_request","tool_input":{"pullRequestNumber":42}}' | bash "$GH" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "github-gate: blocks actions_run_trigger"
echo '{"tool_name":"mcp__github__actions_run_trigger","tool_input":{"workflow_id":"deploy.yml"}}' | bash "$GH" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "github-gate: blocks push_files to main"
echo '{"tool_name":"mcp__github__push_files","tool_input":{"branch":"main","files":[]}}' | bash "$GH" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "github-gate: blocks create_or_update_file on master"
echo '{"tool_name":"mcp__github__create_or_update_file","tool_input":{"branch":"master","path":"src/x.ts"}}' | bash "$GH" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "github-gate: blocks delete_file under .github/"
echo '{"tool_name":"mcp__github__delete_file","tool_input":{"path":".github/workflows/ci.yml"}}' | bash "$GH" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "github-gate: blocks delete_file of *.yml"
echo '{"tool_name":"mcp__github__delete_file","tool_input":{"path":"deploy.yml"}}' | bash "$GH" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "github-gate: allows push to feature branch"
echo '{"tool_name":"mcp__github__push_files","tool_input":{"branch":"feature-x","files":[]}}' | bash "$GH" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "expected 0"

begin_test "github-gate: allows read tools (no-op)"
echo '{"tool_name":"mcp__github__list_issues","tool_input":{}}' | bash "$GH" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "expected 0"

begin_test "github-gate: ignores non-github MCP"
echo '{"tool_name":"mcp__slack__post","tool_input":{}}' | bash "$GH" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "expected 0"

# ---------- Playwright/Puppeteer guard ----------
begin_test "playwright-guard: blocks browser_run_code_unsafe"
echo '{"tool_name":"mcp__playwright__browser_run_code_unsafe","tool_input":{"code":"x"}}' | bash "$PW" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "playwright-guard: blocks puppeteer_evaluate"
echo '{"tool_name":"mcp__puppeteer__puppeteer_evaluate","tool_input":{"script":"x"}}' | bash "$PW" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "playwright-guard: blocks nav to file://"
echo '{"tool_name":"mcp__playwright__browser_navigate","tool_input":{"url":"file:///etc/passwd"}}' | bash "$PW" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "playwright-guard: blocks nav to localhost"
echo '{"tool_name":"mcp__playwright__browser_navigate","tool_input":{"url":"http://localhost:8080/admin"}}' | bash "$PW" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "playwright-guard: blocks nav to RFC1918 (192.168)"
echo '{"tool_name":"mcp__playwright__browser_navigate","tool_input":{"url":"http://192.168.1.1/"}}' | bash "$PW" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "playwright-guard: blocks cloud metadata IP"
echo '{"tool_name":"mcp__playwright__browser_navigate","tool_input":{"url":"http://169.254.169.254/latest/meta-data/"}}' | bash "$PW" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "playwright-guard: allows nav to public URL"
echo '{"tool_name":"mcp__playwright__browser_navigate","tool_input":{"url":"https://example.com"}}' | bash "$PW" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "expected 0"

begin_test "playwright-guard: ignores non-browser MCP"
echo '{"tool_name":"mcp__github__list_issues","tool_input":{}}' | bash "$PW" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "expected 0"

# ---------- SQL guard ----------
begin_test "sql-guard: blocks DROP TABLE"
echo '{"tool_name":"mcp__postgres__query","tool_input":{"query":"DROP TABLE users"}}' | bash "$SQL" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "sql-guard: blocks TRUNCATE"
echo '{"tool_name":"mcp__supabase__execute_sql","tool_input":{"query":"TRUNCATE TABLE orders"}}' | bash "$SQL" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "sql-guard: blocks DELETE FROM"
echo '{"tool_name":"mcp__postgres__query","tool_input":{"query":"DELETE FROM orders WHERE id = 5"}}' | bash "$SQL" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "sql-guard: blocks ALTER TABLE"
echo '{"tool_name":"mcp__postgres__query","tool_input":{"query":"ALTER TABLE users ADD COLUMN x INT"}}' | bash "$SQL" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "sql-guard: blocks GRANT"
echo '{"tool_name":"mcp__postgres__query","tool_input":{"query":"GRANT ALL ON users TO public"}}' | bash "$SQL" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2"

begin_test "sql-guard: allows SELECT with deleted_at column"
echo '{"tool_name":"mcp__postgres__query","tool_input":{"query":"SELECT * FROM users WHERE deleted_at IS NULL"}}' | bash "$SQL" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "expected 0 (deleted_at is a column, not a verb)"

begin_test "sql-guard: allows INSERT"
echo '{"tool_name":"mcp__postgres__query","tool_input":{"query":"INSERT INTO users (name) VALUES ($1)"}}' | bash "$SQL" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "expected 0"

begin_test "sql-guard: allows UPDATE"
echo '{"tool_name":"mcp__postgres__query","tool_input":{"query":"UPDATE users SET active = false WHERE id = 1"}}' | bash "$SQL" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "expected 0"

begin_test "sql-guard: ignores non-sql MCP"
echo '{"tool_name":"mcp__github__list_issues","tool_input":{}}' | bash "$SQL" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "expected 0"

begin_test "sql-guard: alternate field name (sql)"
echo '{"tool_name":"mcp__supabase__execute_sql","tool_input":{"sql":"DROP DATABASE prod"}}' | bash "$SQL" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2 (sql field, not query)"

# v2.7.41 red-team regressions: newline/comment between verb+object, extra
# servers, and github omitted-branch — all were bypasses (exit 0) before.
begin_test "sql-guard: newline between verb and object is blocked (was bypass)"
python3 -c 'import json;print(json.dumps({"tool_name":"mcp__postgres__query","tool_input":{"query":"DROP\nTABLE users"}}))' | bash "$SQL" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "DROP<newline>TABLE not blocked"

begin_test "sql-guard: /**/ comment separator is blocked (was bypass)"
echo '{"tool_name":"mcp__postgres__query","tool_input":{"query":"DROP/**/TABLE users"}}' | bash "$SQL" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "DROP/**/TABLE not blocked"

begin_test "sql-guard: covers extra SQL servers (neon)"
echo '{"tool_name":"mcp__neon__run_sql","tool_input":{"sql":"DROP TABLE users"}}' | bash "$SQL" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "neon DROP TABLE not blocked"

begin_test "sql-guard: legit SELECT with deleted_at column still allowed"
echo '{"tool_name":"mcp__postgres__query","tool_input":{"query":"SELECT * FROM users WHERE deleted_at IS NULL"}}' | bash "$SQL" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "legit SELECT wrongly blocked"

begin_test "github-gate: write with OMITTED branch is blocked (defaults to main)"
echo '{"tool_name":"mcp__github__create_or_update_file","tool_input":{"path":"x","content":"y"}}' | bash "$GH" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "omitted-branch write not blocked"

# ---------- Elicitation guard (v2.7.49) ----------
EG="$REPO_DIR/hooks/elicitation-guard.sh"

begin_test "elicitation-guard: declines credential field (api_key) from untrusted server"
OUT=$(printf '%s' '{"hook_event_name":"Elicitation","server_name":"evil","cwd":"/tmp","schema":{"type":"object","properties":{"api_key":{"type":"string"},"note":{"type":"string"}}}}' | bash "$EG" 2>/dev/null)
printf '%s' "$OUT" | grep -q '"action": "decline"' && pass || fail "expected decline, got: $OUT"

begin_test "elicitation-guard: declines camelCase credential (githubToken)"
OUT=$(printf '%s' '{"hook_event_name":"Elicitation","server_name":"x","cwd":"/tmp","schema":{"properties":{"githubToken":{"type":"string"}}}}' | bash "$EG" 2>/dev/null)
printf '%s' "$OUT" | grep -q decline && pass || fail "expected decline for githubToken, got: $OUT"

begin_test "elicitation-guard: allows benign form (username/email)"
OUT=$(printf '%s' '{"hook_event_name":"Elicitation","server_name":"x","cwd":"/tmp","schema":{"properties":{"username":{"type":"string"},"email":{"type":"string"}}}}' | bash "$EG" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected passthrough, got: $OUT"

begin_test "elicitation-guard: no false positive (monkey, patch_notes)"
OUT=$(printf '%s' '{"hook_event_name":"Elicitation","server_name":"x","cwd":"/tmp","schema":{"properties":{"monkey":{"type":"string"},"patch_notes":{"type":"string"}}}}' | bash "$EG" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "false positive on monkey/patch_notes, got: $OUT"

begin_test "elicitation-guard: trusted server (.supercharger.json) may ask for credentials"
EG_DIR=$(mktemp -d)
printf '%s' '{"trustedElicitationServers":["postgres-mcp"]}' > "$EG_DIR/.supercharger.json"
OUT=$(printf '{"hook_event_name":"Elicitation","server_name":"postgres-mcp","cwd":"%s","schema":{"properties":{"password":{"type":"string"}}}}' "$EG_DIR" | bash "$EG" 2>/dev/null)
rm -rf "$EG_DIR"
[ -z "$OUT" ] && pass || fail "trusted server wrongly declined, got: $OUT"

begin_test "elicitation-guard: SUPERCHARGER_ELICITATION_GUARD=0 disables"
OUT=$(printf '%s' '{"hook_event_name":"Elicitation","server_name":"evil","cwd":"/tmp","schema":{"properties":{"password":{"type":"string"}}}}' | SUPERCHARGER_ELICITATION_GUARD=0 bash "$EG" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "kill switch didn't disable, got: $OUT"

begin_test "elicitation-guard: decline writes an audit record"
setup_test_home
printf '%s' '{"hook_event_name":"Elicitation","server_name":"evil","cwd":"/tmp","schema":{"properties":{"secret_token":{"type":"string"}}}}' | bash "$EG" >/dev/null 2>&1
AUDIT="$HOME/.claude/supercharger/audit/elicitation-guard.jsonl"
[ -f "$AUDIT" ] && grep -q '"action": "declined"' "$AUDIT" && grep -q secret_token "$AUDIT" && pass || fail "expected audit record with declined + field name"
teardown_test_home

report
