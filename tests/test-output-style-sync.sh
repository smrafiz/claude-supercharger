#!/usr/bin/env bash
# hooks/lib-output-style.sh: the minimal tier sets the Concise output style,
# never over a user's own style, and removes only what it set.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

unset SUPERCHARGER_STATE CLAUDE_PLUGIN_DATA
LIB="$REPO_DIR/hooks/lib-output-style.sh"
S() { printf '%s' "$HOME/.claude/settings.json"; }
style() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("outputStyle",""))' "$(S)" 2>/dev/null; }
sync() { ( source "$LIB"; sync_output_style "$1" ); }

begin_test "output-style: minimal sets Concise when none is set, keeps other keys"
setup_test_home
printf '{"model":"opus","hooks":{}}\n' > "$(S)"
sync minimal
if [ "$(style)" = "Concise" ] && grep -q '"model": "opus"' "$(S)"; then pass
else fail "got style='$(style)' settings=$(cat "$(S)")"; fi
teardown_test_home

begin_test "output-style: minimal treats \"default\" as unset"
setup_test_home
printf '{"outputStyle":"default"}\n' > "$(S)"
sync minimal
if [ "$(style)" = "Concise" ]; then pass; else fail "got '$(style)'"; fi
teardown_test_home

begin_test "output-style: minimal never replaces a user's own style"
setup_test_home
printf '{"outputStyle":"Explanatory"}\n' > "$(S)"
sync minimal
if [ "$(style)" = "Explanatory" ]; then pass; else fail "got '$(style)'"; fi
teardown_test_home

begin_test "output-style: leaving minimal removes the style it set"
setup_test_home
printf '{"model":"opus"}\n' > "$(S)"
sync minimal; sync lean
if [ -z "$(style)" ] && grep -q '"model": "opus"' "$(S)"; then pass
else fail "got '$(style)' settings=$(cat "$(S)")"; fi
teardown_test_home

begin_test "output-style: leaving minimal keeps a Concise the user set themselves"
setup_test_home
printf '{"outputStyle":"Concise"}\n' > "$(S)"
sync minimal; sync standard
if [ "$(style)" = "Concise" ]; then pass; else fail "got '$(style)'"; fi
teardown_test_home

begin_test "output-style: leaving minimal keeps a style the user switched to after us"
setup_test_home
printf '{}\n' > "$(S)"
sync minimal
printf '{"outputStyle":"Explanatory"}\n' > "$(S)"
sync lean
if [ "$(style)" = "Explanatory" ]; then pass; else fail "got '$(style)'"; fi
teardown_test_home

begin_test "output-style: a re-run at minimal does not re-set a style the user turned off"
setup_test_home
printf '{}\n' > "$(S)"
sync minimal
printf '{"outputStyle":"default"}\n' > "$(S)"
sync minimal
if [ "$(style)" = "default" ]; then pass; else fail "got '$(style)'"; fi
teardown_test_home

begin_test "output-style: invalid settings JSON is left byte-identical"
setup_test_home
printf '{"model": "opus",,}\n' > "$(S)"
before=$(cat "$(S)")
sync minimal
if [ "$(cat "$(S)")" = "$before" ]; then pass; else fail "file changed: $(cat "$(S)")"; fi
teardown_test_home

begin_test "output-style: a symlinked settings.json stays a symlink"
setup_test_home
mkdir -p "$HOME/dotfiles"; printf '{}\n' > "$HOME/dotfiles/settings.json"
ln -s "$HOME/dotfiles/settings.json" "$(S)" 2>/dev/null
if [ ! -L "$(S)" ]; then echo "    (skipped: Git Bash created no symlink — nothing to keep)"; pass
else sync minimal
if [ -L "$(S)" ] && [ "$(style)" = "Concise" ]; then pass
else fail "symlink=$([ -L "$(S)" ] && echo y || echo n) style='$(style)'"; fi; fi
teardown_test_home

begin_test "output-style: economy-switch.sh minimal sets Concise"
setup_test_home
mkdir -p "$HOME/.claude/rules" "$HOME/.claude/supercharger/economy"
cp "$REPO_DIR"/configs/economy/*.md "$HOME/.claude/supercharger/economy/"
cp "$REPO_DIR/configs/economy/lean.md" "$HOME/.claude/rules/economy.md"
printf '{}\n' > "$(S)"
bash "$REPO_DIR/tools/economy-switch.sh" minimal >/dev/null 2>&1
if [ "$(style)" = "Concise" ]; then pass; else fail "got '$(style)'"; fi
teardown_test_home

begin_test "output-style: the \"eco minimal\" phrase sets Concise"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
printf '{}\n' > "$(S)"
printf '{"prompt":"eco minimal","cwd":"%s","session_id":"t"}' "$HOME" \
  | bash "$REPO_DIR/hooks/economy-reinforce.sh" >/dev/null 2>&1
if [ "$(style)" = "Concise" ]; then pass; else fail "got '$(style)'"; fi
teardown_test_home

report
