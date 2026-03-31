# Claude Supercharger — Ship-Ready Fix Design Specification

**Date:** 2026-03-31
**Status:** Approved
**Author:** smrafiz + Claude
**Scope:** Pre-release fixes for v1.0 launch
**Approach:** Fix critical issues, harden what exists, add test coverage

---

## Context

v1.0 is built but has never been tested against real Claude Code sessions. This spec addresses critical gaps that would undermine credibility on launch. No new features — just making what exists actually work.

### Issues Found

1. All 5 role files installed to `rules/` simultaneously — Claude has no role priority signal
2. Safety hooks are bypassable with trivial variations (`rm -r -f /`, `\rm -rf /`)
3. Prompt validator hardcodes 3 checks, ignores anti-patterns.yml entirely
4. CLAUDE.md merge mode appends a 4-line comment, not actual config content
5. No LICENSE file despite README referencing it
6. No `--non-interactive` flag for CI/dotfiles automation
7. Dead `@` import references in CLAUDE.md template
8. Version strings inconsistent across files
9. No test suite
10. README is 555 lines — too long for first impressions

---

## 1. Role Prioritization Fix

### Problem

All 5 role `.md` files are installed to `~/.claude/rules/`. Claude Code auto-loads everything in `rules/`. With 5 conflicting role instructions loaded simultaneously, Claude has no clear signal which to follow. The "primary role" exists only as a string in a CLAUDE.md comment.

### Design

- Install **only selected roles** to `~/.claude/rules/`
- Store **all role files** in `~/.claude/supercharger/roles/` (not auto-loaded by Claude Code)
- Add role priority line to CLAUDE.md template: `Your default role is {{ROLES}}. Prioritize this role's guidelines unless the user explicitly switches.`
- Mode switching ("as developer") continues to work via conversational cues in CLAUDE.md's Quick Mode Switches section

### Files Changed

- `lib/roles.sh` — `deploy_roles()` installs selected to `rules/`, all to `supercharger/roles/`
- `configs/universal/CLAUDE.md` — add role priority line
- `uninstall.sh` — also clean `supercharger/roles/`
- `claude-check.sh` — distinguish primary roles (in `rules/`) from available roles (in `supercharger/roles/`)

### Rationale

Fewer conflicting instructions = stronger adherence. Mode switching works because Claude understands "as student" conversationally — the role file in `rules/` just reinforces the default.

---

## 2. Safety Hook Hardening

### Problem

Current patterns are near-exact-match regex. Trivial bypasses:
- `rm -r -f /` (split flags)
- `rm  -rf  /` (extra spaces)
- `\rm -rf /` (escaped command)
- `command rm -rf /` (explicit invocation)
- `git push origin main --force` (flag after branch name)

### Design

#### Preprocessing (both safety.sh and git-safety.sh)

Before pattern matching, normalize the command:
1. Strip leading `\`, `command `, `env `, `sudo ` prefixes
2. Collapse multiple whitespace to single space
3. Trim leading/trailing whitespace

#### safety.sh — Smarter Pattern Matching

**rm detection:** Instead of matching `rm -rf /`, detect:
- Command is `rm`
- Flags contain both `-r`/`--recursive` AND `-f`/`--force` (in any position, combined or separate)
- Target is `/`, `~`, `$HOME`, `..`, or `/*`

**Existing patterns kept:** `DROP TABLE`, `DROP DATABASE`, `chmod 777`, `mkfs.`, `dd if=`, `> /dev/sd`, `curl|bash`, `wget|bash`

**New patterns added:**
- `truncate -s 0` (empties files)
- `:(){ :|:& };:` (fork bomb)
- `mv /` or `mv ~/` to arbitrary target (move root/home)
- `kill -9 -1` (kill all processes)

#### git-safety.sh — Position-Independent Matching

- `git push` + `--force` or `-f` anywhere in the command + `main` or `master` anywhere in the command
- `git reset` + `--hard` anywhere after it
- `git checkout .` or `git restore .` (unchanged, already works)
- `git clean` + `-f` or `--force` anywhere after it

### Files Changed

- `hooks/safety.sh` — rewrite with normalization + flag-aware rm detection + new patterns
- `hooks/git-safety.sh` — rewrite with position-independent flag detection

---

## 3. Prompt Validator + Anti-Patterns Integration

### Problem

`prompt-validator.sh` hardcodes 3 regex checks. `anti-patterns.yml` has 35 patterns but sits in `shared/` (not auto-loaded by Claude Code). The hook doesn't read the YAML. The two systems are disconnected.

### Design

**Two complementary layers:**

1. **`rules/anti-patterns.yml` (35 patterns)** — moved from `shared/` to `rules/`. Claude auto-loads it and uses it as behavioral guidance. Full library, applied with judgment.

2. **`prompt-validator.sh` (10-12 checks)** — fast regex subset for the most common/impactful patterns. Deterministic, runs on every prompt (Full mode only). Adds notes, never blocks.

**Hook patterns (10 checks):**

| # | Pattern | Regex Target |
|---|---------|-------------|
| 1 | Vague scope | `^(fix\|update\|change\|improve) (it\|this\|that\|the app\|the code)` |
| 2 | Multiple tasks | Repeated `and also\|and then\|plus\|additionally` |
| 3 | Vague success criteria | `make it better\|improve\|optimize\|clean up` without `should\|must\|ensure` |
| 4 | Emotional description | `totally broken\|fix everything\|nothing works\|completely messed` |
| 5 | Build whole thing | `build me a\|create an entire\|full app\|whole application` |
| 6 | No file path | `update the function\|fix the component\|change the method` without path-like string |
| 7 | Implicit reference | `the thing we discussed\|what we talked about\|the other thing` |
| 8 | Assumed prior knowledge | `continue where we left off\|keep going\|you already know` |
| 9 | Vague aesthetic | `make it look good\|look professional\|look modern\|look nice` |
| 10 | No audience | `write for users\|write documentation\|write a guide` without audience qualifier |

### Files Changed

- `hooks/prompt-validator.sh` — expand to 10 checks
- `shared/anti-patterns.yml` → `rules/anti-patterns.yml` (move)
- `install.sh` — update anti-patterns deploy path
- `uninstall.sh` — update removal path
- `tools/claude-check.sh` — update check path
- `lib/extras.sh` — no change (doesn't reference anti-patterns)

---

## 4. CLAUDE.md Merge Fix

### Problem

Merge mode appends a 4-line comment block with no actual config. The user gets Supercharger behavior from `rules/` files, but CLAUDE.md (the highest-priority config) adds nothing.

### Design

Append the **full Supercharger CLAUDE.md content** below the marker, with variable substitution for roles and mode.

```markdown
# --- Claude Supercharger v1.0.0 ---
# Do not edit below this line. Managed by Supercharger.
# To remove: run uninstall.sh or delete this block.

## Your Environment
- Roles: Developer, PM (default)
- Install mode: Standard
...
(full config content from template)
```

### Implementation

- `install.sh` merge branch — `sed` the template for variable substitution, append full content below marker (instead of just the comment)
- `uninstall.sh` — already handles this correctly (deletes everything from marker to EOF)

### Files Changed

- `install.sh` — merge branch appends full rendered template

---

## 5. Missing Files + Small Fixes

### 5a. LICENSE File

Add MIT license with BSD-3 attribution notice for guardrails content.

**New file:** `LICENSE`

### 5b. Non-Interactive Install

Add CLI flags for automated installation:

```bash
./install.sh --mode standard --roles developer,pm --config merge --settings merge
```

- Each flag is optional — missing flags trigger interactive prompt for that step only
- All flags provided = fully silent install
- `--help` prints usage

**Files changed:** `install.sh` — argument parsing at top, skip prompt for any provided flag

### 5c. Dead @ References

Replace `@rules/supercharger.md` etc. in CLAUDE.md template with:

```markdown
# Active rules loaded from ~/.claude/rules/:
#   supercharger.md, guardrails.md, anti-patterns.yml, [selected roles]
```

**Files changed:** `configs/universal/CLAUDE.md`

### 5d. README Install URL

Verify repo name and default branch. Current URL:
```
https://raw.githubusercontent.com/smrafiz/claude-supercharger/main/install.sh
```

Default branch per git is `master`, not `main`. Fix URL to match.

**Files changed:** `README.md`

### 5e. Version Consistency

Standardize to `1.0.0` everywhere:
- `lib/utils.sh` — already `1.0.0`
- `uninstall.sh` banner — change `v1.0` to `v1.0.0`
- `configs/universal/CLAUDE.md` — change `v1.0` to `v1.0.0`
- `CHANGELOG.md` — already `1.0.0`

---

## 6. Test Suite

### Structure

```
tests/
  run.sh              # Runner — executes all test files, reports summary
  helpers.sh          # Setup/teardown — temp HOME, assertions, cleanup
  test-install.sh     # Fresh, merge, replace, skip, idempotent
  test-uninstall.sh   # Clean removal, backup restore
  test-hooks.sh       # Safety + git-safety with bypass attempts
  test-roles.sh       # Selected vs available role deployment
```

### Key Design Decisions

- **Isolated environment:** Every test creates a temp `$HOME` via `mktemp -d`. Real `~/.claude/` is never touched.
- **No dependencies:** Pure bash. No bats, no shunit2, no tap.
- **Assertions:** `assert_file_exists`, `assert_file_contains`, `assert_exit_code`, `assert_file_not_exists` defined in `helpers.sh`.
- **Hook testing:** Pipe JSON input to hook scripts, check exit codes and stderr output.
- **Runner:** `run.sh` executes each test file, counts pass/fail, exits non-zero on any failure.

### Test Cases

**test-install.sh:**
1. Fresh install (no existing config) — all files in correct locations
2. Merge with existing CLAUDE.md — original preserved, Supercharger content appended below marker
3. Merge with existing settings.json — user hooks preserved, Supercharger hooks added
4. Replace — backup created, originals overwritten
5. Skip — CLAUDE.md untouched, no hooks in settings.json
6. Idempotent — install twice, no duplicate hooks
7. Non-interactive flags — `--mode standard --roles developer --config deploy --settings deploy`

**test-uninstall.sh:**
1. Clean removal — all Supercharger files gone, no orphans
2. User files preserved — non-Supercharger rules and hooks survive
3. Backup restore — restored files match originals

**test-hooks.sh:**
1. Safety: `rm -rf /` → exit 2
2. Safety: `rm -r -f /` → exit 2 (bypass attempt)
3. Safety: `\rm -rf /` → exit 2 (bypass attempt)
4. Safety: `command rm -rf /` → exit 2 (bypass attempt)
5. Safety: `rm -rf ./dist` → exit 0 (legitimate use)
6. Safety: `ls -la` → exit 0 (safe command)
7. Safety: `DROP TABLE users` → exit 2
8. Safety: `chmod 777 /tmp/test` → exit 2
9. Git: `git push --force origin main` → exit 2
10. Git: `git push origin main --force` → exit 2 (flag after branch)
11. Git: `git push origin feature --force` → exit 0 (non-protected branch)
12. Git: `git reset --hard` → exit 2
13. Git: `git reset --soft HEAD~1` → exit 0 (safe reset)

**test-roles.sh:**
1. Single role selected — only that role in `rules/`, all 5 in `supercharger/roles/`
2. Multiple roles selected — selected in `rules/`, all in `supercharger/roles/`
3. Mode switch availability — non-selected roles exist in `supercharger/roles/`

---

## 7. README Trim

### Target

Under 250 lines. First screen shows: value prop, 3 examples, install command.

### Structure

```
# Claude Supercharger
One-line description + badges (version, license, platform)

## The Problem (3-4 lines)

## Before and After (3 best examples: Verification Gate, Scope Discipline, Role: Student)

## Quick Install
curl command

## What You Get
Feature bullet list (grouped by audience)

## Install Modes (table)

## Roles (table)

## Hooks (table)

---
## Details (below the fold)
How it works, existing config handling, verify, uninstall, manual install, FAQ

## More Examples
Link to docs/examples.md

## Credits, License
```

### New File

`docs/examples.md` — receives the 6 moved before/after examples (Safety Hooks, Role: Developer, Role: Writer, Role: Data, Role: PM, Quick Mode Switch, Clarification Mode, Session Handoff)

### Files Changed

- `README.md` — restructure and trim
- `docs/examples.md` — new file

---

## Summary of All File Changes

### New Files
- `LICENSE`
- `tests/run.sh`
- `tests/helpers.sh`
- `tests/test-install.sh`
- `tests/test-uninstall.sh`
- `tests/test-hooks.sh`
- `tests/test-roles.sh`
- `docs/examples.md`

### Modified Files
- `install.sh` — merge fix, non-interactive flags, anti-patterns path
- `uninstall.sh` — version string, supercharger/roles/ cleanup, anti-patterns path
- `lib/roles.sh` — deploy selected to rules/, all to supercharger/roles/
- `lib/hooks.sh` — no changes
- `lib/utils.sh` — no changes
- `lib/backup.sh` — no changes
- `lib/extras.sh` — no changes
- `hooks/safety.sh` — full rewrite (normalization + flag-aware + new patterns)
- `hooks/git-safety.sh` — rewrite (position-independent matching)
- `hooks/prompt-validator.sh` — expand to 10 checks
- `configs/universal/CLAUDE.md` — role priority, dead @ refs, version string
- `tools/claude-check.sh` — role distinction, anti-patterns path
- `README.md` — restructure and trim
- `CHANGELOG.md` — add ship-ready fix entries
- `shared/anti-patterns.yml` → `rules/anti-patterns.yml` (move, not modify content)

### Unchanged Files
- `configs/universal/supercharger.md`
- `configs/universal/guardrails.md`
- `configs/roles/*.md` (all 5 role files)
- `hooks/notify.sh`
- `hooks/auto-format.sh`
- `hooks/compaction-backup.sh`
- `tools/mcp-setup.sh`
- `lib/backup.sh`
- `lib/extras.sh`
- `lib/utils.sh`

---

## Success Criteria

Ship-ready fix is complete when:
- [ ] All tests pass (`tests/run.sh` exits 0)
- [ ] Safety hook blocks all bypass variants in test suite
- [ ] Only selected roles appear in `~/.claude/rules/`
- [ ] Merge mode appends full config content to existing CLAUDE.md
- [ ] Install + uninstall is idempotent and leaves no orphans
- [ ] `--non-interactive` mode works for all flag combinations
- [ ] README is under 250 lines
- [ ] LICENSE file exists
- [ ] Version string is `1.0.0` everywhere
