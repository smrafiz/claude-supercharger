#!/usr/bin/env bash
# A command handed to the OS from inside an interpreter heredoc body
# (`os.system('...')`, `subprocess.run([...])`, perl `system(...)`, node
# `execSync(...)`) was invisible to every shell rule: those rules match a command
# in command position, and inside the body it sits in a string. Measured on master
# 2026-10-14: 6 of 7 such cases allowed by all 20 installed Bash hooks, while the
# same command in a `bash` heredoc was denied. strip_heredoc_bodies now writes each
# shell-out's argument out on its own line, so the shell rules see what runs.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Assembled at runtime so the deployed guard does not fire on this file's own text.
CT="cron""tab"

probe() { # command -> "BLOCK" | "allow"
  local st rc
  st=$(mktemp -d); mkdir -p "$st/scope" "$st/home"
  ST="$st" CMD="$1" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]},
                  "cwd": os.environ["ST"]}))' \
    | env HOME="$st/home" SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/safety.sh" >/dev/null 2>&1
  rc=$?
  rm -rf "$st"
  [ "$rc" -eq 2 ] && printf 'BLOCK' || printf 'allow'
}
denies() { local g; g=$(probe "$2"); [ "$g" = BLOCK ] && pass || fail "$1: expected BLOCK, got allow - GUARD GAP"; }
allows() { local g; g=$(probe "$2"); [ "$g" = allow ] && pass || fail "$1: expected allow, got BLOCK"; }

NL=$'\n'
begin_test "perl heredoc: system('<cron install>') is denied"
denies perl "perl <<'EOF'${NL}system('$CT /tmp/x');${NL}EOF"
begin_test "python heredoc: os.system('<cron install>') is denied"
denies py-system "python3 - <<'EOF'${NL}import os${NL}os.system('$CT /tmp/x')${NL}EOF"
begin_test "python heredoc: subprocess list form is denied"
denies py-list "python3 - <<'EOF'${NL}import subprocess${NL}subprocess.run(['$CT', '/tmp/x'])${NL}EOF"
begin_test "python heredoc: subprocess list with -e is denied"
denies py-list-e "python3 - <<'EOF'${NL}import subprocess${NL}subprocess.run(['$CT', '-e'])${NL}EOF"
begin_test "ruby heredoc: system(\"rm -rf /\") is denied"
denies ruby-rm "ruby <<'EOF'${NL}system(\"rm -rf /\")${NL}EOF"
begin_test "node heredoc: execSync('<cron install>') is denied"
denies node "node <<'EOF'${NL}require('child_' + 'process').execSync('$CT /tmp/x')${NL}EOF"
begin_test "perl heredoc: backticks still denied (control)"
denies perl-ticks "perl <<'EOF'${NL}my \$o = \`$CT /tmp/x\`;${NL}EOF"

begin_test "python heredoc printing prose that names the command is allowed"
allows py-prose "python3 - <<'EOF'${NL}print('add a $CT entry: 17 3 * * *')${NL}EOF"
begin_test "python heredoc running git status is allowed"
allows py-git "python3 - <<'EOF'${NL}import subprocess${NL}print(subprocess.run(['git', 'status'], capture_output=True).stdout)${NL}EOF"
begin_test "python heredoc listing the table (-l) is allowed"
allows py-list-l "python3 - <<'EOF'${NL}import subprocess${NL}subprocess.run(['$CT', '-l'])${NL}EOF"
begin_test "python heredoc asyncio.run(main()) is allowed"
allows py-asyncio "python3 - <<'EOF'${NL}import asyncio${NL}asyncio.run(main())${NL}EOF"
begin_test "cat heredoc into a doc that quotes a shell-out is allowed"
allows cat-doc "cat > notes.md <<'EOF'${NL}os.system('$CT /tmp/x') is how the attack works${NL}EOF"

report
