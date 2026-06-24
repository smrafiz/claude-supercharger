#!/usr/bin/env bash
# Mutation-fuzz harness for hooks/safety.sh
# Generates ~1000 mutated commands across known-dangerous bases + benign
# baselines, runs each through safety.sh, classifies decisions, and reports
# false-negative (dangerous → allowed) and false-positive (benign → blocked).
#
# Not run as part of the normal test suite (slow + non-deterministic);
# invoke manually: bash tests/fuzz-safety.sh [--verbose]

set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/hooks/safety.sh"

VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

# ── Dangerous bases (each MUST block: exit 2) ─────────────────────────────────
DANGEROUS=(
  "rm -rf /"
  "rm -rf /*"
  "rm -rf ~"
  "rm -rf \$HOME"
  "rm -rf \${HOME}"
  "rm -rf \$PWD"
  "rm -rf \$(pwd)"
  "rm -rf .."
  "rm -rf ./"
  "rm -rf ."
  "rm --recursive --force /"
  "rm --force --recursive /"
  "mv / /tmp/x"
  "mv ~ /tmp/x"
  "mv \$HOME /tmp"
  "echo \"sk-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUV\" > /tmp/x"
  "echo \"AKIAIOSFODNN7EXAMPLE\" > /tmp/x"
  "echo \"ghp_abcdefghijklmnopqrstuvwxyz0123456789AB\" > /tmp/x"
  "API_KEY=secret123 echo done"
  "crontab -e"
  "echo evil >> ~/.bashrc"
  "echo evil >> ~/.zshrc"
  "tee -a ~/.bashrc <<< evil"
  "ssh-keygen -t rsa"
  "cat ~/.bash_history"
  "cat ~/.zsh_history"
  "cat ~/Library/Cookies/Cookies.binarycookies"
  "security find-generic-password -s github"
  "osascript -e 'tell app \"System Events\" to keystroke \"x\"'"
  "pbpaste"
  "pbcopy"
)

# ── Benign bases (each MUST allow: exit 0 or 1) ───────────────────────────────
BENIGN=(
  "ls -la"
  "git status"
  "git log --oneline -5"
  "git diff HEAD"
  "cat README.md"
  "pwd"
  "echo hello"
  "npm install"
  "pnpm install"
  "yarn install"
  "node script.js"
  "python3 script.py"
  "make build"
  "cargo build"
  "go test ./..."
  "rm /tmp/somefile.txt"
  "rm -f /tmp/somefile.txt"
  "mv /tmp/a /tmp/b"
  "cd /tmp && ls"
  "find . -name '*.ts'"
  "grep -r 'TODO' src/"
  "docker ps"
  "kubectl get pods"
  "psql -c 'SELECT 1'"
)

# ── Mutators ──────────────────────────────────────────────────────────────────
# Each takes a base command, emits N mutated variants.

mutate_case() {
  local cmd="$1"
  # Random case mutations on common verbs (only safe if uppercased-rm still works on macOS — it doesn't, so this is more like noise than real attack)
  printf '%s\n' "$cmd"
}

mutate_whitespace() {
  local cmd="$1"
  printf '%s\n' "$cmd"
  printf '%s\n' "${cmd// / }"          # double space
  printf '%s\n' "${cmd//-/  -}"        # extra space before flags
  printf '   %s   \n' "$cmd"           # leading/trailing space
  printf '\t%s\n' "$cmd"               # leading tab
}

mutate_compound() {
  local cmd="$1"
  printf '%s\n' "$cmd"
  printf 'echo safe && %s\n' "$cmd"        # &&-chain
  printf '%s; echo done\n' "$cmd"          # ;-chain
  printf 'true || %s\n' "$cmd"             # ||-chain (skipped, but harmless mutation)
  printf 'echo safe; %s; echo done\n' "$cmd"  # interleaved
}

mutate_prefix() {
  local cmd="$1"
  printf '%s\n' "$cmd"
  printf 'sudo %s\n' "$cmd"
  printf 'command %s\n' "$cmd"
  printf 'env FOO=bar %s\n' "$cmd"
  printf 'PATH=/usr/bin %s\n' "$cmd"
}

mutate_flag_split() {
  local cmd="$1"
  printf '%s\n' "$cmd"
  # If command is "rm -rf X", try "rm -r -f X" and "rm -f -r X"
  if [[ "$cmd" =~ ^rm[[:space:]]+-rf[[:space:]] ]]; then
    printf '%s\n' "${cmd/-rf /-r -f }"
    printf '%s\n' "${cmd/-rf /-f -r }"
    printf '%s\n' "${cmd/-rf /--recursive --force }"
  fi
}

# ── Run + classify ────────────────────────────────────────────────────────────
run_safety() {
  local cmd="$1"
  # Build minimal PreToolUse:Bash payload
  local payload
  payload=$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]},'cwd':'/tmp'}))" "$cmd")
  echo "$payload" | bash "$HOOK" >/dev/null 2>&1
  echo $?
}

# Aggregate counters
TOTAL=0
FN_COUNT=0   # dangerous but allowed (exit 0/1)
FP_COUNT=0   # benign but blocked (exit 2)
FN_CMDS=()
FP_CMDS=()

check_dangerous() {
  local cmd="$1"
  TOTAL=$((TOTAL + 1))
  local exit_code
  exit_code=$(run_safety "$cmd")
  if [ "$exit_code" != "2" ]; then
    FN_COUNT=$((FN_COUNT + 1))
    FN_CMDS+=("[exit=$exit_code] $cmd")
    [ "$VERBOSE" = "1" ] && echo "FN: [exit=$exit_code] $cmd" >&2
  fi
}

check_benign() {
  local cmd="$1"
  TOTAL=$((TOTAL + 1))
  local exit_code
  exit_code=$(run_safety "$cmd")
  if [ "$exit_code" = "2" ]; then
    FP_COUNT=$((FP_COUNT + 1))
    FP_CMDS+=("$cmd")
    [ "$VERBOSE" = "1" ] && echo "FP: $cmd" >&2
  fi
}

echo "=== Safety.sh Mutation Fuzz Harness ==="
echo "Bases: ${#DANGEROUS[@]} dangerous, ${#BENIGN[@]} benign"
echo "Mutators: whitespace × compound × prefix × flag-split"
echo ""

# Cross-product mutations on dangerous bases
for base in "${DANGEROUS[@]}"; do
  for ws in $(mutate_whitespace "$base"); do :; done  # noop, just exercise
  while IFS= read -r ws_cmd; do
    while IFS= read -r cp_cmd; do
      while IFS= read -r pf_cmd; do
        while IFS= read -r fs_cmd; do
          check_dangerous "$fs_cmd"
        done < <(mutate_flag_split "$pf_cmd")
      done < <(mutate_prefix "$cp_cmd")
    done < <(mutate_compound "$ws_cmd")
  done < <(mutate_whitespace "$base")
done

# Same for benign (smaller cross-product — skip compound mutator since chaining benign with itself is still benign and would explode counts)
for base in "${BENIGN[@]}"; do
  while IFS= read -r ws_cmd; do
    while IFS= read -r pf_cmd; do
      check_benign "$pf_cmd"
    done < <(mutate_prefix "$ws_cmd")
  done < <(mutate_whitespace "$base")
done

echo ""
echo "=== Results ==="
echo "Total runs:     $TOTAL"
echo "False neg (dangerous → ALLOWED):  $FN_COUNT"
echo "False pos (benign → BLOCKED):     $FP_COUNT"

if [ "$FN_COUNT" -gt 0 ]; then
  echo ""
  echo "── BYPASSES (dangerous patterns that slipped through) ──"
  printf '  %s\n' "${FN_CMDS[@]}" | head -50
fi

if [ "$FP_COUNT" -gt 0 ]; then
  echo ""
  echo "── OVER-BLOCKS (benign commands blocked) ──"
  printf '  %s\n' "${FP_CMDS[@]}" | head -50
fi

# Exit non-zero if either count is non-trivial
if [ "$FN_COUNT" -gt 0 ] || [ "$FP_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
