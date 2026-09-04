#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# --- Test: non-interactive fresh install ---
begin_test "install: non-interactive fresh install"
setup_test_home

# Keep the installer's output: this assertion has failed intermittently under a
# parallel suite run, and discarding the output of the thing under test made the
# failure undiagnosable. BOTH streams, not just stderr — error() writes to stdout,
# and merge_hooks_into_settings folds python3's stderr into stdout with `2>&1`,
# so a failure there leaves stderr empty. Echoed only when an assertion fails.
INSTALL_ERR="$HOME/.install-output"
bash "$REPO_DIR/install.sh" --mode full --roles developer --config deploy --settings deploy --economy lean >"$INSTALL_ERR" 2>&1

{ assert_file_exists "$HOME/.claude/CLAUDE.md" &&
assert_file_exists "$HOME/.claude/rules/supercharger.md" &&
assert_file_exists "$HOME/.claude/rules/guardrails.md" &&
assert_file_exists "$HOME/.claude/rules/developer.md" &&
assert_file_exists "$HOME/.claude/rules/anti-patterns.yml" &&
assert_file_not_exists "$HOME/.claude/rules/writer.md" &&
assert_file_exists "$HOME/.claude/supercharger/roles/writer.md" &&
assert_file_exists "$HOME/.claude/settings.json" &&
assert_file_exists "$HOME/.claude/rules/economy.md" &&
pass ; } || { echo "    install.sh output:"; sed 's/^/      /' "$INSTALL_ERR" | tail -25; }
teardown_test_home

# --- Test: Quick install fork applies defaults with minimal prompts ---
begin_test "install: Quick fork (Enter) applies full/developer/minimal/light/commits-on"
setup_test_home
# Enter = Quick, then 1 = notify on. No existing config => no safety prompts.
printf '\n1\n' | bash "$REPO_DIR/install.sh" >/dev/null 2>&1
QV=$(cat "$HOME/.claude/supercharger/.version" 2>/dev/null)
QR=$(cat "$HOME/.claude/supercharger/.roles" 2>/dev/null)
QE=$(cat "$HOME/.claude/supercharger/scope/.economy-tier" 2>/dev/null)
QM=$(cat "$HOME/.claude/supercharger/scope/.mcp-profile" 2>/dev/null)
if [ -n "$QV" ] && [ "$QR" = "developer" ] && [ "$QE" = "minimal" ] && [ "$QM" = "light" ] && \
   [ -f "$HOME/.claude/supercharger/.conventional-commits" ]; then pass
else fail "Quick defaults wrong: ver=$QV role=$QR eco=$QE mcp=$QM commits=$([ -f "$HOME/.claude/supercharger/.conventional-commits" ] && echo on || echo off)"; fi
teardown_test_home

# --- Test: Custom fork routes to the full wizard and honors choices ---
begin_test "install: Custom fork (c) runs wizard and honors choices"
setup_test_home
# c=custom, 2=full, 1=developer, 3=minimal, 1=light, 1=notify on, 1=commits off, n=skip mcp-setup
printf 'c\n2\n1\n3\n1\n1\n1\nn\n' | bash "$REPO_DIR/install.sh" >/dev/null 2>&1
CR=$(cat "$HOME/.claude/supercharger/.roles" 2>/dev/null)
CE=$(cat "$HOME/.claude/supercharger/scope/.economy-tier" 2>/dev/null)
if [ "$CR" = "developer" ] && [ "$CE" = "minimal" ] && \
   [ ! -f "$HOME/.claude/supercharger/.conventional-commits" ]; then pass
else fail "Custom wizard wrong: role=$CR eco=$CE commits=$([ -f "$HOME/.claude/supercharger/.conventional-commits" ] && echo on || echo off)"; fi
teardown_test_home

# --- Test: non-interactive merge preserves existing content ---
begin_test "install: non-interactive merge preserves existing content"
setup_test_home
mkdir -p "$HOME/.claude"
echo "# My Existing Config" > "$HOME/.claude/CLAUDE.md"
echo "keep this" >> "$HOME/.claude/CLAUDE.md"

bash "$REPO_DIR/install.sh" --mode safe --roles writer --config merge --settings deploy --economy standard >/dev/null 2>&1

assert_file_contains "$HOME/.claude/CLAUDE.md" "My Existing Config" &&
assert_file_contains "$HOME/.claude/CLAUDE.md" "keep this" &&
assert_file_contains "$HOME/.claude/CLAUDE.md" "Claude Supercharger" &&
assert_file_contains "$HOME/.claude/CLAUDE.md" "Verification Gate" &&
pass
teardown_test_home

# --- Test: non-interactive skip leaves CLAUDE.md untouched ---
begin_test "install: non-interactive skip leaves CLAUDE.md untouched"
setup_test_home
mkdir -p "$HOME/.claude"
echo "# Untouched" > "$HOME/.claude/CLAUDE.md"

bash "$REPO_DIR/install.sh" --mode safe --roles developer --config skip --settings skip --economy lean >/dev/null 2>&1

assert_file_contains "$HOME/.claude/CLAUDE.md" "Untouched" &&
assert_file_not_contains "$HOME/.claude/CLAUDE.md" "Supercharger" &&
assert_file_exists "$HOME/.claude/rules/supercharger.md" &&
pass
teardown_test_home

# --- Test: idempotent install ---
begin_test "install: idempotent — no duplicate hooks after double install"
setup_test_home

bash "$REPO_DIR/install.sh" --mode full --roles developer --config deploy --settings deploy --economy lean >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --mode full --roles developer --config deploy --settings deploy --economy lean >/dev/null 2>&1

HOOK_COUNT=$(SETTINGS="$HOME/.claude/settings.json" python3 -c "
import json, os
with open(os.environ['SETTINGS']) as f:
    s = json.load(f)
hooks = s.get('hooks', {})
count = sum(1 for event in hooks.values() for entry in event
            for h in entry.get('hooks', [])
            if '#supercharger' in h.get('command','') or '#supercharger' in h.get('prompt',''))
print(count)
")
# Full mode + developer = 119 hooks total (118 after thinking-budget removal in 2.18.0; +redirect-clobber-guard in 2.20.0) — was previously redundant
# with native Claude effort levels + adaptive reasoning). commit-* trio consolidated into commit-guard;
# plugin-inject/seed are plugin-only self-noop under the installer but still registered; commit-check opt-in, not counted)
if [ "$HOOK_COUNT" -eq 159 ]; then
  pass
else
  fail "expected 159 hooks in full mode, got $HOOK_COUNT"
fi
teardown_test_home

# --- Test: statusline is registered in settings.json ---
begin_test "install: statusline registered in settings.json"
setup_test_home

bash "$REPO_DIR/install.sh" --mode full --roles developer --config deploy --settings deploy --economy lean >/dev/null 2>&1

HAS_STATUSLINE=$(SETTINGS="$HOME/.claude/settings.json" python3 -c "
import json, os
with open(os.environ['SETTINGS']) as f:
    s = json.load(f)
sl = s.get('statusLine', {}).get('command', '')
print('yes' if '#supercharger' in sl else 'no')
")
[ "$HAS_STATUSLINE" = "yes" ] && pass || fail "statusLine not found in settings.json"
teardown_test_home

# --- Test: agents deployed on install ---
begin_test "install: agents deployed to ~/.claude/agents/"
setup_test_home

bash "$REPO_DIR/install.sh" --mode full --roles developer --config deploy --settings deploy --economy lean >/dev/null 2>&1

assert_dir_exists "$HOME/.claude/agents" &&
assert_file_exists "$HOME/.claude/agents/code-helper.md" &&
assert_file_exists "$HOME/.claude/agents/debugger.md" &&
assert_file_exists "$HOME/.claude/agents/writer.md" &&
assert_file_exists "$HOME/.claude/agents/reviewer.md" &&
assert_file_exists "$HOME/.claude/agents/researcher.md" &&
assert_file_exists "$HOME/.claude/agents/planner.md" &&
assert_file_exists "$HOME/.claude/agents/data-analyst.md" &&
assert_file_exists "$HOME/.claude/agents/general.md" &&
assert_file_exists "$HOME/.claude/agents/architect.md" &&
assert_file_exists "$HOME/.claude/agents/explorer.md" &&
pass
teardown_test_home

# --- Test: python deep-scanners deployed on install (2.17.3 regression) ---
# hooks/*.py were previously never copied (only hooks/*.sh), so safety.sh and
# env-file-guard.sh invoked a missing python file → python exits 2 → set -e →
# phantom "No stderr output" deny on every deep-scan-gated command.
begin_test "install: python deep-scanners deployed to hooks dir"
setup_test_home

bash "$REPO_DIR/install.sh" --mode full --roles developer --config deploy --settings deploy --economy lean >/dev/null 2>&1

assert_file_exists "$HOME/.claude/supercharger/hooks/safety-detect.py" &&
assert_file_exists "$HOME/.claude/supercharger/hooks/env-file-detect.py" &&
pass
teardown_test_home

# --- Test: commands deployed on install ---
begin_test "install: commands deployed to ~/.claude/commands/"
setup_test_home

bash "$REPO_DIR/install.sh" --mode full --roles developer --config deploy --settings deploy --economy lean >/dev/null 2>&1

assert_dir_exists "$HOME/.claude/commands" &&
assert_file_exists "$HOME/.claude/commands/think.md" &&
assert_file_exists "$HOME/.claude/commands/security.md" &&
assert_file_exists "$HOME/.claude/commands/challenge.md" &&
assert_file_exists "$HOME/.claude/commands/audit.md" &&
pass
teardown_test_home

# --- Test: safe mode installs base hooks only ---
begin_test "install: safe mode installs 7 base hooks"
setup_test_home

bash "$REPO_DIR/install.sh" --mode safe --roles developer --config deploy --settings deploy --economy lean >/dev/null 2>&1

HOOK_COUNT=$(SETTINGS="$HOME/.claude/settings.json" python3 -c "
import json, os
with open(os.environ['SETTINGS']) as f:
    s = json.load(f)
hooks = s.get('hooks', {})
count = sum(1 for event in hooks.values() for entry in event
            for h in entry.get('hooks', [])
            if '#supercharger' in h.get('command','') or '#supercharger' in h.get('prompt',''))
print(count)
")
# Safe mode = safety + smart-approve + audit-trail + trace-compactor + injection-scanner
# + per-MCP guards + memory-guard + mcp-provenance + elicitation-guard + prompt-layer-inject
# + plugin-config-seed + readonly-guard + critical-infra-guard + webfetch-egress-guard = 30
if [ "$HOOK_COUNT" -eq 43 ]; then
  pass
else
  fail "expected 43 hooks in safe mode, got $HOOK_COUNT"
fi
teardown_test_home

# --- Test: full mode deploys claude-check diagnostic ---
begin_test "install: full mode deploys claude-check.sh"
setup_test_home

echo "n" | bash "$REPO_DIR/install.sh" --mode full --roles developer --config deploy --settings deploy --economy lean >/dev/null 2>&1

assert_file_exists "$HOME/.claude/claude-check.sh" && pass
teardown_test_home

# --- Test: backward compat — standard maps to full ---
begin_test "install: --mode standard maps to full"
setup_test_home

bash "$REPO_DIR/install.sh" --mode standard --roles developer --config deploy --settings deploy --economy lean >/dev/null 2>&1

HOOK_COUNT=$(SETTINGS="$HOME/.claude/settings.json" python3 -c "
import json, os
with open(os.environ['SETTINGS']) as f:
    s = json.load(f)
hooks = s.get('hooks', {})
count = sum(1 for event in hooks.values() for entry in event
            for h in entry.get('hooks', [])
            if '#supercharger' in h.get('command','') or '#supercharger' in h.get('prompt',''))
print(count)
")
# standard maps to full = 119 hooks (thinking-budget removed 2.18.0; +redirect-clobber-guard 2.20.0; with developer, commit-check opt-in)
if [ "$HOOK_COUNT" -eq 159 ]; then
  pass
else
  fail "expected 159 hooks (standard→full), got $HOOK_COUNT"
fi
teardown_test_home

# v2.7.28: regression guard. WorktreeCreate/WorktreeRemove are PROVIDER hooks —
# CC delegates worktree creation to a hook registered there and requires a
# returned path, so a passive hook registered on those events BREAKS
# `isolation: worktree` for every agent (shipped + reverted, v2.7.26→.27). No
# unit test spawns a live worktree, so nothing caught it. This asserts the
# anti-pattern never returns: lib/hooks.sh must not register any hook on those
# two events.
begin_test "hooks: no passive hook registered on WorktreeCreate/WorktreeRemove (provider events)"
if grep -qE 'hooks\+=\("Worktree(Create|Remove)' "$REPO_DIR/lib/hooks.sh"; then
  fail "lib/hooks.sh registers a hook on a Worktree* provider event — this breaks isolation:worktree"
else
  pass
fi

# --- Test: help flag ---
begin_test "install: --help prints usage and exits"
OUTPUT=$(bash "$REPO_DIR/install.sh" --help 2>&1) || true
echo "$OUTPUT" | grep -qi "usage" && pass || fail "no usage text"

# --- Test: count_installed_hooks dedups by script (v2.9.4) ---
# The install banner counts DISTINCT hook scripts, not event registrations —
# a hook bound to N events is still one installed hook. Must be < raw tuple count.
begin_test "install: count_installed_hooks dedups multi-registered hooks"
DEDUP=$(. "$REPO_DIR/lib/hooks.sh"; count_installed_hooks full true)
RAW=$(. "$REPO_DIR/lib/hooks.sh"; get_hooks_for_mode full true "$HOME/.claude/supercharger/hooks" | awk 'NF{c++} END{print c+0}')
if [ "$DEDUP" -gt 0 ] && [ "$DEDUP" -lt "$RAW" ]; then
  pass
else
  fail "expected 0 < deduped ($DEDUP) < raw registrations ($RAW)"
fi

# --- statusLine path portability (v2.26.57) -----------------------------------
# Measured on a windows-latest runner: lib/hooks.sh built statusline_path with
# Python's expanduser+join. Under Git Bash python3 is WINDOWS python, so that
# returned `C:\Users\name\...` — written verbatim into settings.json as
# statusLine.command, which Git Bash cannot execute. The statusline silently
# never ran, and nothing on macOS or Linux could show it: both produce forward
# slashes, so the bug was invisible to the entire test suite.
#
# The path now comes from bash, whose $HOME is POSIX on Git Bash. This asserts
# the OUTCOME (no backslash in the emitted command) rather than the mechanism,
# so a future refactor that reintroduces a native path still fails here.
begin_test "install: statusLine.command contains no backslash (Git Bash portability)"
SLT=$(mktemp -d)
mkdir -p "$SLT/.claude/supercharger/hooks"
printf '#!/usr/bin/env bash\necho x\n' > "$SLT/.claude/supercharger/hooks/statusline.sh"
chmod +x "$SLT/.claude/supercharger/hooks/statusline.sh"
( export HOME="$SLT"; . "$REPO_DIR/lib/hooks.sh"; merge_hooks_into_settings full true ) >/dev/null 2>&1
SL_CMD=$(python3 -c "
import json, os, sys
try:
    d = json.load(open(os.path.join(sys.argv[1], '.claude', 'settings.json')))
except Exception:
    print(''); sys.exit(0)
print((d.get('statusLine') or {}).get('command', ''))" "$SLT" 2>/dev/null)
rm -rf "$SLT"
case "$SL_CMD" in
  "")     fail "statusLine was not written at all — the path now resolves to nothing" ;;
  *\\*)   fail "backslash in statusLine.command: $SL_CMD" ;;
  *statusline.sh*) pass ;;
  *)      fail "statusLine.command does not point at statusline.sh: $SL_CMD" ;;
esac

# --- G4: prerequisite gates run AFTER platform detection (v2.26.58) ----------
# The gates used to sit ~76 lines above the detect_platform call. detect_platform
# is where the Windows python handling lives (`py` launcher → `python` → `py3`,
# then a shim). So on a Windows box with `py` but no `python3` on PATH, install
# died with "ERROR: python3 is required" while the code that would have fixed it
# sat unreachable in the same file — including its App-Execution-Aliases advice.
gate_out() { # OSTYPE, path-dir -> installer stderr+stdout, first lines
  PATH="$2" OSTYPE="$1" HOME="$2/../home" bash "$REPO_DIR/install.sh" \
    --mode full --roles developer --config skip --settings skip \
    --economy lean --notify off --commits off --mcp-profile light 2>&1 | head -12
}
mk_pathdir() { # tools... -> echoes a bin dir containing only those
  local d; d=$(mktemp -d); mkdir -p "$d/bin" "$d/home"
  shim_tools "$d/bin" "$@"
  printf '%s' "$d/bin"
}

begin_test "install: missing jq on Windows names winget/choco, not 'your package manager'"
PD=$(mk_pathdir bash sed grep cat mktemp dirname uname tr head cut python3 chmod mkdir rm cp ln find sort awk)
OUT=$(gate_out msys "$PD")
rm -rf "$(dirname "$PD")"
printf '%s' "$OUT" | grep -qi 'winget\|choco' && pass \
  || fail "Windows jq guidance missing — Git Bash has no brew/apt/dnf/pacman, so the generic line was all a Windows user ever saw"

begin_test "install: missing jq on Linux keeps the generic guidance"
PD=$(mk_pathdir bash sed grep cat mktemp dirname uname tr head cut python3 chmod mkdir rm cp ln find sort awk)
OUT=$(gate_out linux-gnu "$PD")
rm -rf "$(dirname "$PD")"
printf '%s' "$OUT" | grep -qi 'winget\|choco' \
  && fail "Windows text leaked onto Linux" || pass

begin_test "install: no bare python3 gate before detect_platform"
# A second `command -v python3 ... exit 1` above the detect_platform call would
# re-introduce the exact bug: the shim becomes unreachable again.
python3 -c "
import re, sys
src = open(sys.argv[1]).read()
dp = src.find('\ndetect_platform')
if dp < 0:
    print('detect_platform never called'); sys.exit(1)
head = src[:dp]
sys.exit(1 if re.search(r'command -v python3.*\n.*exit 1', head, re.S) else 0)" "$REPO_DIR/install.sh" 2>/dev/null \
  && pass || fail "a python3 gate runs before detect_platform — the Windows py-launcher shim is unreachable"

begin_test "install: detect_platform is called exactly once"
N=$(grep -c '^detect_platform$' "$REPO_DIR/install.sh")
[ "$N" = "1" ] && pass || fail "called $N times — a second call builds another python shim dir and re-prepends PATH"

begin_test "install: the statusLine path is taken from bash, not python expanduser"
# Mechanism check alongside the outcome check: expanduser is correct for OPENING
# a file with python and wrong for BUILDING a string another program executes.
grep -q "statusline_path = os.environ.get('STATUSLINE_PATH'" "$REPO_DIR/lib/hooks.sh" && pass \
  || fail "statusline_path is computed in python again — it will be a native path on Windows"

report
