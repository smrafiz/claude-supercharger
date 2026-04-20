# Contributing to Claude Supercharger

Four ways to contribute: add a hook, add a role, fix a bug, or improve the docs. All follow the same flow — fork, branch, PR.

---

## Ways to contribute

### Add a hook

Read [docs/HOOK_AUTHORING.md](docs/HOOK_AUTHORING.md) first. It covers the contract, exit codes, JSON parsing, and patterns that work. The short version:

1. Create `hooks/<name>.sh` — must be executable (`chmod +x`)
2. Parse stdin JSON via `python3` — never interpolate shell variables directly into `-c` strings (see [Python-in-Bash rules](#python-in-bash-rules))
3. Exit `0` to allow, `2` to block (write reason to stderr before blocking)
4. Register in `lib/hooks.sh` → `get_hooks_for_mode()`
5. Update `count_installed_hooks()` in `lib/hooks.sh` to keep the count accurate
6. Add a test at `tests/test-hookname.sh`

### Add a role

1. Create `configs/roles/<name>.md` — follow the format of an existing role, including the `paths:` frontmatter and `## Token Efficiency` section
2. Add the role name to `AVAILABLE_ROLES` in `lib/roles.sh`
3. Add a constraint entry to `ROLE_CONSTRAINTS` in `lib/economy.sh` (`role|default|floor|ceiling` — empty = unrestricted)
4. Add a row to the role constraints table in `configs/universal/economy.md`
5. Add the role to `get_active_roles()` in `tools/economy-switch.sh`
6. Add a Quick Mode Switch entry to the `configs/universal/CLAUDE.md` template

### Fix a bug

Branch off `master`, fix, verify tests pass, open a PR. Describe what was broken and how you confirmed the fix.

### Improve docs

Same flow. If it's a clear error, skip the issue and send the PR directly.

---

## Development setup

```bash
git clone https://github.com/smrafiz/claude-supercharger.git
cd claude-supercharger
# No build step. Edit files directly.
```

Supercharger is zero-dependency Bash — no npm, pip, or brew required. The installer writes to `~/.claude/`. Everything is reversible via `bash uninstall.sh`.

---

## Running tests

```bash
bash tests/run.sh
```

Tests live in `tests/test-*.sh`. Each file is standalone — run any one with `bash tests/test-foo.sh`. The suite auto-discovers all `test-*.sh` files.

### Writing tests

Match the pattern in an existing test file. Source `helpers.sh` at the top — it provides:

- `begin_test`, `pass`, `fail`
- `assert_exit_code`, `assert_file_exists`, `assert_file_contains`
- `run_hook`, `setup_test_home`, `teardown_test_home`

Use `setup_test_home` / `teardown_test_home` for isolation. This redirects `$HOME` to a temp dir so tests never touch your real `~/.claude`. End each file with `report`.

---

## Pull request checklist

- [ ] `bash tests/run.sh` passes
- [ ] New hooks have a corresponding `tests/test-hookname.sh`
- [ ] No hardcoded paths — use `$HOME` or `$REPO_DIR`
- [ ] Hook handles missing or malformed JSON without crashing (stdin may be empty)
- [ ] Hook exits 0 when it has nothing to say — don't emit empty `additionalContext`

---

## Python-in-Bash rules

Never interpolate shell variables directly into `python3 -c` strings:

```bash
# Wrong — breaks silently
python3 -c "import json; print('$VARIABLE')"

# Right — pass via environment
MY_VAR="$VARIABLE" python3 -c "import os; print(os.environ['MY_VAR'])"
```

All existing hooks follow this pattern. Match it.

---

## Bash compatibility

Scripts must work on Bash 3.2 — the macOS default at `/bin/bash`.

- No associative arrays (`declare -A`) — use pipe-delimited strings or parallel arrays
- Test with `/bin/bash your-script.sh`, not just `bash` (which may resolve to Bash 5 via Homebrew)

---

## Commit conventions

| Prefix | Use for |
|--------|---------|
| `feat:` | New hook, role, tool, or installer feature |
| `fix:` | Bug fix |
| `test:` | New or updated tests |
| `docs:` | Documentation only |
| `chore:` | Maintenance, cleanup |
| `security:` | Security-related changes |
| `refactor:` | Restructuring without behavior change |

One concern per commit. Tests pass before committing.

---

## What not to contribute

- Features that add significant token overhead without a clear opt-out
- Hooks that modify Claude's behavior globally (safety hooks are fine; preference hooks belong in roles or `CLAUDE.md`)
- Breaking changes to the `settings.json` hook format
- External dependencies — no npm, pip, brew, or curl-to-install anything

If you're unsure whether something fits, open an issue before building it.

---

## Reporting bugs

Open a GitHub issue. Include:

- OS and shell
- Claude Code version (`claude --version`)
- The hook that failed
- The JSON it received (redact any secrets)
