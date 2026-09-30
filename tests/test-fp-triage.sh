#!/usr/bin/env bash
# tools/fp-triage — the text-blanking oracle and the end-to-end verdicts.
#
# fp-triage calls a block "text-only" when it disappears once quoted strings and
# heredoc bodies are blanked. That is only sound if code that EXECUTES is left
# intact: blanking `sh -c '...'` or a python heredoc hides a real command and
# reports a true block as a false positive. The first draft did exactly that on
# the live ledger (a python heredoc writing ~/.claude/settings.json, and
# `sh -cm '...'`), so both shapes are pinned here.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
echo "=== fp-triage ==="

_blank() {  # $1 = command -> blank_text(command)
  C="$1" PYTHONPATH="$REPO_DIR/tools" python3 -c '
import importlib.util, os
s = importlib.util.spec_from_file_location("t", os.path.join(os.environ["PYTHONPATH"], "fp-triage.py"))
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.blank_text(os.environ["C"]), end="")'
}

begin_test "fp-triage: a commit message is blanked"
OUT=$(_blank 'git commit -m "stop editing settings.json"')
[ "$OUT" = 'git commit -m "x"' ] && pass || fail "got: $OUT"

begin_test "fp-triage: sh -c code is kept (clustered -cm too)"
OUT=$(_blank "sh -cm 'echo x > .claude/settings.json'")
case "$OUT" in *settings.json*) pass ;; *) fail "blanked executing code: $OUT" ;; esac

begin_test "fp-triage: an interpreter heredoc keeps its quoted strings"
OUT=$(_blank "python3 - <<'PY'
p = open('/tmp/x/.claude/settings.json', 'w')
PY")
case "$OUT" in *settings.json*) pass ;; *) fail "blanked python code: $OUT" ;; esac

begin_test "fp-triage: a heredoc written to a file is blanked"
OUT=$(_blank "cat > notes.md <<'EOF'
never run rm -rf / here
EOF")
case "$OUT" in *rm*) fail "kept data: $OUT" ;; *) pass ;; esac

# End to end on a throwaway ledger: one text-only block, one real one.
begin_test "fp-triage: classifies a text-only block and a real block"
T=$(mktemp -d); mkdir -p "$T/scope" "$T/projects"
{
  # A SQL keyword written into a file: still blocked on 2026-09-29 (a live FP).
  echo '[2026-01-01 00:00] dangerous pattern: DROP TABLE — echo "DROP TABLE users" > q.txt'
  echo '[2026-01-01 00:00] recursive force rm on dangerous target — rm -rf ~'
} > "$T/scope/.blocked-commands"
OUT=$(bash "$REPO_DIR/tools/fp-triage.sh" --ledger "$T/scope/.blocked-commands" --projects "$T/projects" 2>/dev/null)
rm -rf "$T"
if printf '%s' "$OUT" | grep -q 'text-only (likely FP): 1' && printf '%s' "$OUT" | grep -q 'still blocks on a command: 1'; then pass
else fail "unexpected summary: $OUT"; fi

# 2026-09-30: on Windows CI the guards never ran (a bare `bash` from Python can be
# WSL's), so every block read as "fixed" and the tool reported nothing. It must
# refuse to report when a known-bad command is not blocked.
begin_test "fp-triage: refuses to report when the guards do not run"
T=$(mktemp -d); mkdir -p "$T/projects"
printf '[2026-01-01 00:00] r — rm -rf ~\n' > "$T/ledger"
printf '#!/bin/sh\nexit 0\n' > "$T/nobash"; chmod +x "$T/nobash"
OUT=$(FPT_BASH="$T/nobash" bash "$REPO_DIR/tools/fp-triage.sh" --ledger "$T/ledger" --projects "$T/projects" 2>&1); RC=$?
rm -rf "$T"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'did not block a known-bad command'; then pass
else fail "rc=$RC out=$OUT"; fi

report
