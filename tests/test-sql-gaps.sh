#!/usr/bin/env bash
# SQL spellings that wiped a table and passed safety.sh (randommonicle/claude-skills
# audit, 2026-10-28): a WHERE that matches every row, UPDATE with no WHERE, and SQL
# run from a file, whose statements the command line never shows.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== SQL gaps ==="

TMP=$(mktemp -d)
mkdir -p "$TMP/db"
printf 'BEGIN;\nDELETE FROM users;\nCOMMIT;\n' > "$TMP/db/wipe.sql"
printf -- '-- clean up\nDELETE FROM sessions\nWHERE expires_at < now();\nUPDATE users\n  SET active = false\n  WHERE id = 7;\n' > "$TMP/db/routine.sql"
printf -- '-- DROP TABLE users; (kept for reference)\nSELECT 1;\n' > "$TMP/db/commented.sql"
printf 'UPDATE accounts SET balance = 0;\n' > "$TMP/db/zero.sql"

python3 - "$TMP/cases" "$TMP/db" <<'PY'
import json, sys
cwd = sys.argv[2]
cases = [
    # a WHERE that keeps every row
    ("DELETE WHERE 1=1", "psql -c \"DELETE FROM users WHERE 1=1\"", "DENY"),
    ("DELETE WHERE true", "psql -c 'DELETE FROM users WHERE true;'", "DENY"),
    ("DELETE WHERE 1", "mysql -e 'DELETE FROM users WHERE 1'", "DENY"),
    ("UPDATE WHERE 1 = 1", "psql -c \"UPDATE users SET admin = true WHERE 1 = 1;\"", "DENY"),
    # UPDATE with no WHERE
    ("UPDATE, no WHERE", "psql -c \"UPDATE users SET password_hash = 'x';\"", "DENY"),
    ("UPDATE, two columns", "sqlite3 app.db 'UPDATE users SET a = 1, b = NULL'", "DENY"),
    ("UPDATE schema.table, no WHERE", "psql -c \"UPDATE public.users SET active = false\"", "DENY"),
    # SQL from a file
    ("psql -f wipes a table", "psql -d app -f wipe.sql", "ASK"),
    ("psql --file= absolute", "psql --file=" + cwd + "/wipe.sql", "ASK"),
    ("mysql < file", "mysql app < zero.sql", "ASK"),
    ("sqlite3 .read", "sqlite3 app.db \".read wipe.sql\"", "ASK"),
    # still allowed
    ("DELETE with a real WHERE", "psql -c \"DELETE FROM users WHERE id = 1\"", "ALLOW"),
    ("DELETE WHERE id = 1 is not 1", "psql -c 'DELETE FROM t WHERE id = 1;'", "ALLOW"),
    ("UPDATE with WHERE", "psql -c \"UPDATE users SET active = false WHERE id = 3\"", "ALLOW"),
    ("prose: update the docs", "git commit -m 'update docs set up guide'", "ALLOW"),
    ("ORM update call", "node -e \"db.update(users).set({a:1})\"", "ALLOW"),
    ("psql -f routine migration", "psql -f routine.sql", "ALLOW"),
    ("psql -f commented DROP", "psql -f commented.sql", "ALLOW"),
    ("psql -f missing file", "psql -f nope.sql", "ALLOW"),
    ("SELECT", "psql -c 'SELECT * FROM users WHERE 1=1'", "ALLOW"),
]
with open(sys.argv[1], "w") as f:
    for name, cmd, want in cases:
        f.write(json.dumps({"name": name, "want": want,
                            "payload": {"tool_name": "Bash", "cwd": cwd, "tool_input": {"command": cmd}}}) + "\n")
PY

run_cases() {
  local i=0 line name want out rc st got
  while IFS= read -r line; do
    i=$((i+1))
    name=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')
    want=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["want"])')
    printf '%s' "$line" | python3 -c 'import json,sys;print(json.dumps(json.load(sys.stdin)["payload"]))' > "$TMP/p$i.json"
    st=$(mktemp -d)
    out=$(SUPERCHARGER_STATE="$st" SUPERCHARGER_NO_DEDUP=1 "$@" bash "$REPO_DIR/hooks/safety.sh" < "$TMP/p$i.json" 2>/dev/null); rc=$?
    rm -rf "$st"
    case "$rc:$out" in 2:*|*'"permissionDecision":"deny"'*) got=DENY ;; *'"permissionDecision":"ask"'*) got=ASK ;; *) got=ALLOW ;; esac
    begin_test "sql: $name -> $want"
    [ "$got" = "$want" ] && pass || fail "got $got"
  done < "$TMP/cases"
}
run_cases env

# Opt-in: ask on every DELETE, even a filtered one.
python3 - "$TMP/cases" "$TMP/db" <<'PY'
import json, sys
cases = [
    ("opt-in: filtered DELETE asks", "psql -c \"DELETE FROM users WHERE id = 1\"", "ASK"),
    ("opt-in: SELECT still allowed", "psql -c 'SELECT 1'", "ALLOW"),
]
with open(sys.argv[1], "w") as f:
    for name, cmd, want in cases:
        f.write(json.dumps({"name": name, "want": want,
                            "payload": {"tool_name": "Bash", "cwd": sys.argv[2], "tool_input": {"command": cmd}}}) + "\n")
PY
run_cases env SUPERCHARGER_ASK_SQL_DELETE=1

rm -rf "$TMP"
report
