#!/usr/bin/env bash
# Suite for block-workaround-check.sh and the deny-side record in lib-deny.sh.
# End to end: a real env-file-guard deny records the file, then later calls in the
# same session that name it are warned about (once), and nothing else is.
# Payloads live in this file so the live installed guard does not block the runner.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/block-workaround-check.sh"
GUARD="$REPO_DIR/hooks/env-file-guard.sh"
export SUPERCHARGER_STATE; SUPERCHARGER_STATE=$(mktemp -d)
trap 'rm -rf "$SUPERCHARGER_STATE"' EXIT

j() {  # j <session> <tool> <tool_input json>
  printf '{"session_id":"%s","tool_name":"%s","cwd":"/tmp/p","tool_input":%s}' "$1" "$2" "$3"
}
warns() { bash "$HOOK" <<<"$1" 2>/dev/null | grep -q '"additionalContext"'; }

begin_test "block-workaround: nothing denied this session -> silent"
warns "$(j s1 Bash '{"command":"cat /tmp/p/.env"}')" && fail "warned with no deny" || pass

begin_test "block-workaround: an env-file-guard deny records the file for the session"
bash "$GUARD" <<<"$(j s1 Read '{"file_path":"/tmp/p/.env"}')" >/dev/null 2>&1
grep -qxF '.env' "$SUPERCHARGER_STATE/scope/.blocked-files-s1" 2>/dev/null && pass || fail "not recorded"

begin_test "block-workaround: python -c reaching the denied file warns"
warns "$(j s1 Bash '{"command":"python3 -c \"open('.env','w').write('K=1')\""}')" && pass || fail "no warning"

begin_test "block-workaround: warns once per file per session"
warns "$(j s1 Bash '{"command":"sed -i s/a/b/ .env"}')" && fail "warned twice" || pass

begin_test "block-workaround: another session is unaffected"
warns "$(j s2 Bash '{"command":"sed -i s/a/b/ .env"}')" && fail "leaked across sessions" || pass

begin_test "block-workaround: a script written to reach the file warns (Write content)"
bash "$GUARD" <<<"$(j s3 Read '{"file_path":"/tmp/p/.env"}')" >/dev/null 2>&1
warns "$(j s3 Write '{"file_path":"/tmp/p/fix.sh","content":"echo K=1 >> .env\n"}')" && pass || fail "no warning"

begin_test "block-workaround: .env.example and my.env are not the denied name"
bash "$GUARD" <<<"$(j s4 Read '{"file_path":"/tmp/p/.env"}')" >/dev/null 2>&1
warns "$(j s4 Bash '{"command":"cp .env.example x && cat my.env"}')" && fail "matched a longer name" || pass

begin_test "block-workaround: SUPERCHARGER_BLOCK_WORKAROUND=0 turns it off"
SUPERCHARGER_BLOCK_WORKAROUND=0 bash "$HOOK" <<<"$(j s4 Bash '{"command":"cat .env"}')" 2>/dev/null | grep -q additionalContext \
  && fail "still warned" || pass

begin_test "block-workaround: an ask records nothing (only a deny does)"
( . "$REPO_DIR/hooks/lib-deny.sh"; _INPUT=$(j s5 Read '{"file_path":"/tmp/p/x.json"}'); sc_decision ask "t" >/dev/null )
[ -e "$SUPERCHARGER_STATE/scope/.blocked-files-s5" ] && fail "ask recorded a file" || pass

report
