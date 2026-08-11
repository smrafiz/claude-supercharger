#!/usr/bin/env bash
# fcntl is absent on Windows python (v2.26.73)
#
# budget-cap and subagent-cost both did `import fcntl` unconditionally. On Git Bash
# that raises ModuleNotFoundError and kills the whole python block before it writes
# anything, so on Windows:
#
#   - the per-session token file was never created and the statusline showed
#     `main 0` while context read 214.3K — the reported symptom;
#   - and THE BUDGET CAP NEVER RAN. A cost guard that silently does nothing is the
#     worst failure mode it has.
#
# Reproduced here by putting a module on PYTHONPATH that raises on import, which is
# how a Windows interpreter behaves without needing one.
#
# Degrading to no lock is safe rather than a compromise: budget-cap's acquire is
# already bounded and falls through to a best-effort unlocked write after ~2s, so
# this takes a path the code has always tolerated. os.replace stays atomic.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Stand in for a platform without fcntl.
#
# NOT a fcntl.py on PYTHONPATH: that works on macOS, where fcntl is a shared
# extension resolved through sys.path, and silently does NOTHING on Linux, where it
# is compiled into the interpreter and BuiltinImporter answers first. The first
# version did exactly that and went green on macOS while proving nothing on the
# ubuntu runner — caught by the guard test below, which is the only reason it did
# not ship as five vacuous assertions.
#
# A sitecustomize is imported at startup and can insert a finder ahead of every
# other one, so it intercepts built-ins too. Portable across both.
SHIM=$(mktemp -d)
cat > "$SHIM/sitecustomize.py" <<'PY'
import sys


class _BlockFcntl:
    def find_spec(self, name, path=None, target=None):
        if name == "fcntl":
            raise ImportError("No module named 'fcntl'")
        return None


sys.meta_path.insert(0, _BlockFcntl())
PY

# Each case gets its own state dir. An earlier version of this reused one across
# both runs, so the second saw a consumed transcript offset, produced no delta, and
# reported a working fix as broken.
run_budget_cap() { # use_shim(0|1) -> echoes the scope dir
  local shim="$1" st
  st=$(mktemp -d); mkdir -p "$st/scope" "$st/home"
  python3 - "$st/t.jsonl" <<'PY'
import json, sys
with open(sys.argv[1], "w") as f:
    for _ in range(3):
        f.write(json.dumps({"type": "assistant", "message": {
            "model": "claude-opus-4",
            "usage": {"input_tokens": 1000, "output_tokens": 500,
                      "cache_creation_input_tokens": 200,
                      "cache_read_input_tokens": 50}}}) + "\n")
PY
  local pay
  pay=$(ST="$st" python3 -c '
import json, os
print(json.dumps({"session_id": "fcntlcase", "cwd": os.environ["ST"],
                  "hook_event_name": "PostToolUse", "tool_name": "Bash",
                  "tool_input": {"command": "echo hi"},
                  "transcript_path": os.path.join(os.environ["ST"], "t.jsonl")}))')
  if [ "$shim" = "1" ]; then
    printf '%s' "$pay" | env HOME="$st/home" SUPERCHARGER_STATE="$st" PYTHONPATH="$SHIM" \
      bash "$REPO_DIR/hooks/budget-cap.sh" >/dev/null 2>&1
  else
    printf '%s' "$pay" | env HOME="$st/home" SUPERCHARGER_STATE="$st" \
      bash "$REPO_DIR/hooks/budget-cap.sh" >/dev/null 2>&1
  fi
  printf '%s' "$st"
}

echo "=== fcntl-optional (Windows python) ==="

begin_test "the shim really does break the import"
# Guards the guard: if this stops failing, every case below passes for free.
env PYTHONPATH="$SHIM" python3 -c 'import fcntl' 2>&1 | grep -q 'ImportError' \
  && pass || fail "the shim no longer blocks fcntl — the cases below prove nothing"

begin_test "budget-cap writes the session token file WITH fcntl"
ST=$(run_budget_cap 0)
ls "$ST"/scope/.main-tokens-* >/dev/null 2>&1 && pass || fail "baseline broken: no token file even with fcntl"
rm -rf "$ST"

begin_test "budget-cap writes the session token file WITHOUT fcntl"
# The reported symptom in its own terms: no file here means the statusline shows
# `main 0`.
ST=$(run_budget_cap 1)
ls "$ST"/scope/.main-tokens-* >/dev/null 2>&1 && pass \
  || fail "no token file without fcntl — statusline would show 'main 0'"
rm -rf "$ST"

begin_test "the token count is the same with and without fcntl"
# Degrading the LOCK must not degrade the ACCOUNTING.
A=$(run_budget_cap 0); B=$(run_budget_cap 1)
TA=$(python3 -c "import json,glob,sys;print(json.load(open(glob.glob(sys.argv[1]+'/scope/.main-tokens-*')[0]))['new_tokens'])" "$A" 2>/dev/null)
TB=$(python3 -c "import json,glob,sys;print(json.load(open(glob.glob(sys.argv[1]+'/scope/.main-tokens-*')[0]))['new_tokens'])" "$B" 2>/dev/null)
[ -n "$TA" ] && [ "$TA" = "$TB" ] && pass || fail "token totals differ: with=$TA without=$TB"
rm -rf "$A" "$B"

begin_test "the budget cap itself still runs WITHOUT fcntl"
# The consequence that matters more than the statusline. If the block dies, the
# cost file is never written and nothing is ever compared against a budget.
ST=$(run_budget_cap 1)
[ -f "$ST/scope/.session-cost" ] && pass || fail "no .session-cost — the budget cap is inert"
rm -rf "$ST"

begin_test "subagent-cost imports cleanly without fcntl"
# The sibling. Both lock the SAME file, so fixing one and not the other would drift.
grep -q 'except ImportError' "$REPO_DIR/hooks/subagent-cost.sh" && pass \
  || fail "subagent-cost still imports fcntl unconditionally"

begin_test "no hook imports fcntl unconditionally"
# Meta-check so a future hook cannot reintroduce the class.
BAD=$(grep -ln '^import fcntl' "$REPO_DIR"/hooks/*.sh 2>/dev/null | xargs -r -n1 basename | tr '\n' ' ')
[ -z "$BAD" ] && pass || fail "unconditional fcntl import in: $BAD"

rm -rf "$SHIM"
report
