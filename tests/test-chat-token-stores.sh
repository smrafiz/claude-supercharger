#!/usr/bin/env bash
# 2026-11-24 (agent-white-hat delta): Discord keeps its login token in Local Storage
# and Telegram Desktop its session in tdata; a copy of either logs in as the user.
# Neither the Read guard nor the Bash guard knew these paths.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== chat-app token stores ==="

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home"
n=0
# check <hook> <deny|allow> <name> <tool> <value: command or file_path>
check() {
  n=$((n+1))
  V="$5" T="$4" python3 -c "import json,os;t=os.environ['T'];k='command' if t=='Bash' else 'file_path';print(json.dumps({'tool_name':t,'tool_input':{k:os.environ['V']},'cwd':'/tmp','session_id':'cts$n'}))" > "$TMP/in$n"
  begin_test "$3"
  local out rc got=allow
  out=$(HOME="$TMP/home" SUPERCHARGER_STATE="$TMP/state$n" bash "$REPO_DIR/hooks/$1" < "$TMP/in$n" 2>/dev/null); rc=$?
  [ "$rc" -eq 2 ] && got=deny
  case "$out" in *'"deny"'*) got=deny ;; esac
  [ "$got" = "$2" ] && pass || fail "expected $2, got $got — $4 $5"
}
AS="Application Support"; LS="Local Storage"

# Read (env-file-guard.sh)
check env-file-guard.sh deny  "Read: macOS Discord token store"     Read "/Users/u/Library/$AS/discord/$LS/leveldb/000003.log"
check env-file-guard.sh deny  "Read: Discord Canary token store"    Read "/Users/u/Library/$AS/discordcanary/$LS/leveldb/x.ldb"
check env-file-guard.sh deny  "Read: Linux Discord token store"     Read "/home/u/.config/discord/$LS/leveldb/x.ldb"
check env-file-guard.sh deny  "Read: Windows Discord token store"   Read 'C:\Users\u\AppData\Roaming\discord\Local Storage\leveldb\x.ldb'
check env-file-guard.sh deny  "Read: macOS Telegram tdata"          Read "/Users/u/Library/$AS/Telegram Desktop/tdata/key_datas"
check env-file-guard.sh deny  "Read: Linux Telegram tdata"          Read "/home/u/.local/share/TelegramDesktop/tdata/key_datas"
check env-file-guard.sh allow "Read: Discord settings.json"         Read "/Users/u/Library/$AS/discord/settings.json"
check env-file-guard.sh allow "Read: a discord bot project"         Read "/proj/discord-bot/src/index.js"
check env-file-guard.sh allow "Read: a file named tdata.csv"        Read "/proj/data/tdata.csv"

# Bash (safety.sh)
check safety.sh deny  "Bash: escaped-space Discord leveldb"   Bash "cat ~/Library/Application\\ Support/discord/Local\\ Storage/leveldb/000003.log"
check safety.sh deny  "Bash: quoted Discord Local Storage"    Bash "strings ~/.config/discord/\"$LS\"/leveldb/*.ldb"
check safety.sh deny  "Bash: copy Telegram tdata"             Bash "cp -r ~/Library/\"$AS\"/\"Telegram Desktop\"/tdata /tmp/t"
check safety.sh deny  "Bash: Linux TelegramDesktop tdata"     Bash "tar czf /tmp/t.tgz ~/.local/share/TelegramDesktop/tdata"
check safety.sh allow "Bash: grep a discord bot project"      Bash "grep -rn token discord-bot/src"
check safety.sh allow "Bash: Discord settings.json"           Bash "cat ~/.config/discord/settings.json"

report
