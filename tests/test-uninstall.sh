#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# --- Test: supercharger files removed ---
begin_test "uninstall: supercharger rule files removed"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/roles"
mkdir -p "$HOME/.claude/supercharger/hooks"

# Simulate installed state
echo "rules" > "$HOME/.claude/rules/supercharger.md"
echo "rules" > "$HOME/.claude/rules/guardrails.md"
echo "rules" > "$HOME/.claude/rules/developer.md"
echo "rules" > "$HOME/.claude/rules/anti-patterns.yml"
echo "role" > "$HOME/.claude/supercharger/roles/developer.md"
echo "hook" > "$HOME/.claude/supercharger/hooks/safety.sh"
echo '{}' > "$HOME/.claude/settings.json"

# Create CLAUDE.md with marker
cat > "$HOME/.claude/CLAUDE.md" << 'EOF'
# User config
my stuff

# --- Claude Supercharger v1.0.0 ---
# Supercharger content
## Verification Gate
EOF

# Run uninstall (pipe yes for confirm, n for no restore)
printf 'y\nn\n' | bash "$REPO_DIR/uninstall.sh" >/dev/null 2>&1 || true

assert_file_not_exists "$HOME/.claude/rules/supercharger.md" &&
assert_file_not_exists "$HOME/.claude/rules/guardrails.md" &&
assert_file_not_exists "$HOME/.claude/rules/developer.md" &&
assert_file_not_exists "$HOME/.claude/rules/anti-patterns.yml" &&
pass
teardown_test_home

# --- Test: user CLAUDE.md content preserved ---
begin_test "uninstall: user content preserved above marker"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/hooks"

cat > "$HOME/.claude/CLAUDE.md" << 'EOF'
# My Custom Config
my important settings

# --- Claude Supercharger v1.0.0 ---
# Supercharger content here
## More supercharger stuff
EOF

echo '{}' > "$HOME/.claude/settings.json"

printf 'y\nn\n' | bash "$REPO_DIR/uninstall.sh" >/dev/null 2>&1 || true

assert_file_exists "$HOME/.claude/CLAUDE.md" &&
assert_file_contains "$HOME/.claude/CLAUDE.md" "My Custom Config" &&
assert_file_contains "$HOME/.claude/CLAUDE.md" "my important settings" &&
assert_file_not_contains "$HOME/.claude/CLAUDE.md" "Claude Supercharger" &&
pass
teardown_test_home

# --- Test: supercharger directory cleaned ---
begin_test "uninstall: supercharger/ directory removed"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/hooks"
mkdir -p "$HOME/.claude/supercharger/roles"
echo "hook" > "$HOME/.claude/supercharger/hooks/safety.sh"
echo "role" > "$HOME/.claude/supercharger/roles/developer.md"
echo '{}' > "$HOME/.claude/settings.json"
touch "$HOME/.claude/CLAUDE.md"

printf 'y\nn\n' | bash "$REPO_DIR/uninstall.sh" >/dev/null 2>&1 || true

if [ ! -d "$HOME/.claude/supercharger" ]; then
  pass
else
  fail "supercharger/ directory still exists"
fi
teardown_test_home

# --- Test: agents removed on uninstall ---
begin_test "uninstall: supercharger agents removed"
setup_test_home
mkdir -p "$HOME/.claude/agents"
for agent in code-helper debugger writer reviewer researcher planner data-analyst general architect; do
  echo "agent" > "$HOME/.claude/agents/$agent.md"
done
echo '{}' > "$HOME/.claude/settings.json"
touch "$HOME/.claude/CLAUDE.md"

printf 'y\nn\n' | bash "$REPO_DIR/uninstall.sh" >/dev/null 2>&1 || true

assert_file_not_exists "$HOME/.claude/agents/code-helper.md" &&
assert_file_not_exists "$HOME/.claude/agents/architect.md" &&
assert_file_not_exists "$HOME/.claude/agents/debugger.md" &&
pass
teardown_test_home

# --- Test: user-added agents preserved on uninstall ---
begin_test "uninstall: user-added agents preserved"
setup_test_home
mkdir -p "$HOME/.claude/agents"
echo "agent" > "$HOME/.claude/agents/code-helper.md"
echo "my custom agent" > "$HOME/.claude/agents/my-custom-agent.md"
echo '{}' > "$HOME/.claude/settings.json"
touch "$HOME/.claude/CLAUDE.md"

printf 'y\nn\n' | bash "$REPO_DIR/uninstall.sh" >/dev/null 2>&1 || true

assert_file_exists "$HOME/.claude/agents/my-custom-agent.md" &&
assert_file_not_exists "$HOME/.claude/agents/code-helper.md" &&
pass
teardown_test_home

# --- Test: commands removed on uninstall ---
begin_test "uninstall: supercharger commands removed"
setup_test_home
mkdir -p "$HOME/.claude/commands"
for cmd in think refactor challenge audit; do
  echo "cmd" > "$HOME/.claude/commands/$cmd.md"
done
echo '{}' > "$HOME/.claude/settings.json"
touch "$HOME/.claude/CLAUDE.md"

printf 'y\nn\n' | bash "$REPO_DIR/uninstall.sh" >/dev/null 2>&1 || true

assert_file_not_exists "$HOME/.claude/commands/think.md" &&
assert_file_not_exists "$HOME/.claude/commands/refactor.md" &&
assert_file_not_exists "$HOME/.claude/commands/challenge.md" &&
assert_file_not_exists "$HOME/.claude/commands/audit.md" &&
pass
teardown_test_home

report
