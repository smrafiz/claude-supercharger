# Contributing to Claude Supercharger

Claude Supercharger is a zero-dependency Bash toolkit that installs hooks, roles, and economy rules into Claude Code via `~/.claude`. It ships no npm packages, no pip installs — just shell scripts and config files.

The installer writes to `~/.claude/settings.json` (hooks), `~/.claude/rules/` (role and economy files), and `~/.claude/CLAUDE.md` (instructions). Everything is reversible via `bash uninstall.sh`.

---

## Getting Started

```bash
git clone https://github.com/smrafiz/claude-supercharger
cd claude-supercharger
bash tests/run.sh
```

All 227 tests must pass before submitting a PR.

### File Structure

```
configs/    # Role files, economy tiers, universal templates
hooks/      # Hook scripts (run by Claude Code on events)
lib/        # Shared Bash libraries (hooks.sh, economy.sh, roles.sh, utils.sh)
tools/      # User-facing CLI tools (webhook-setup.sh, economy-switch.sh, etc.)
tests/      # Test files and helpers
install.sh  # Main installer
```

---

## Adding a Hook

1. Create `hooks/<name>.sh` — must be executable (`chmod +x`)
2. Parse JSON from stdin via `python3`:

```bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('command',''))" 2>/dev/null || echo "")
```

3. Exit codes: `0` = allow, `2` = block (write reason to stderr first)
4. Register in `lib/hooks.sh` → `get_hooks_for_mode()`:

```bash
hooks+=("PreToolUse|Bash|${hooks_dir}/your-hook.sh")
```

   Format: `event|matcher|command` — leave matcher empty if the event doesn't support it.

5. Update `count_installed_hooks()` in `lib/hooks.sh` to keep the count accurate
6. Tag: the installer appends `#supercharger` to all hook commands automatically — no action needed in your script
7. Add tests in `tests/test-hooks.sh` (or a dedicated `tests/test-<name>.sh`)

---

## Adding a Role

1. Create `configs/roles/<name>.md` with a `## Token Efficiency` section:

```markdown
## Token Efficiency
Default economy: Lean
Economy range: unrestricted
```

2. Add the role name to `AVAILABLE_ROLES` in `lib/roles.sh`
3. Add a constraint entry to `ROLE_CONSTRAINTS` in `lib/economy.sh`:

```bash
ROLE_CONSTRAINTS=(
  ...
  "rolename|lean||"   # role|default|floor|ceiling — empty = unrestricted
)
```

4. Add a row to the role constraints table in `configs/universal/economy.md`
5. Add the role to `get_active_roles()` in `tools/economy-switch.sh`
6. Add a Quick Mode Switch entry to the `configs/universal/CLAUDE.md` template

---

## Adding a Tool

1. Create `tools/<name>.sh`
2. Source shared utilities at the top:

```bash
source "$(dirname "$0")/../lib/utils.sh"
```

3. Include a `show_usage()` function, invoked when `--help` is passed
4. Make executable: `chmod +x tools/<name>.sh`

---

## Python-in-Bash Rules

**Never** interpolate shell variables directly into `python3 -c` strings. Shell escaping inside Python strings is fragile and breaks silently.

**Wrong:**
```bash
python3 -c "import json; print('$VARIABLE')"
```

**Right — pass via environment variables:**
```bash
MY_VAR="$VARIABLE" python3 -c "import os; print(os.environ['MY_VAR'])"
```

For assignments (not inline prefix), use export/unset:
```bash
export MY_VAR="$VARIABLE"
python3 -c "import os; print(os.environ['MY_VAR'])"
unset MY_VAR
```

All existing hooks and lib files follow this pattern. Match it exactly.

---

## Testing Conventions

- Test file: `tests/test-<feature>.sh`
- Source helpers and relevant libs at the top:

```bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$REPO_DIR/lib/utils.sh"
```

- Use `setup_test_home` / `teardown_test_home` for isolation — this redirects `$HOME` to a temp dir so tests never touch your real `~/.claude`
- Available assert functions: `assert_file_exists`, `assert_file_not_exists`, `assert_dir_exists`, `assert_file_contains`, `assert_file_not_contains`, `assert_exit_code`
- Use `run_hook` from helpers.sh to pipe JSON input to a hook and capture its exit code
- End each test file with `report`
- Run all tests: `bash tests/run.sh`

**All tests must pass before committing.**

---

## Bash Compatibility

Scripts must work on **Bash 3.2** (the macOS default at `/bin/bash`).

- No associative arrays (`declare -A`) — use pipe-delimited strings or parallel arrays
- No `set -u` combined with array key access (will error on missing keys in Bash 3.2)
- Test with `/bin/bash your-script.sh`, not just `bash` (which may resolve to Bash 5 via Homebrew)

---

## Commit Conventions

Prefix every commit with one of:

| Prefix | Use for |
|--------|---------|
| `feat:` | New hook, role, tool, or installer feature |
| `fix:` | Bug fix |
| `test:` | New or updated tests |
| `docs:` | Documentation only |
| `chore:` | Maintenance, refactoring, cleanup |
| `security:` | Security-related changes |
| `refactor:` | Code restructuring without behavior change |

One concern per commit. Tests must pass before committing.

---

## What NOT to Do

- **No external dependencies** — no npm, pip, brew, or curl-to-install anything
- **No comments in code** unless the logic is genuinely non-obvious
- **No drive-by changes** — only modify files directly in scope of your PR
- **Never skip tests** — if you break existing behavior, fix it or update the test with justification
