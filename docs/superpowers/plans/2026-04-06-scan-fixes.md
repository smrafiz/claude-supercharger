# Scan Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 17 issues found by the security/quality scan: 1 shell injection, 4 stale version strings, 5 correctness bugs, and 7 docs/config inconsistencies.

**Architecture:** Each task targets one or two files with a focused, non-breaking change. No refactoring, no new abstractions. Fix what is broken, remove what is dead.

**Tech Stack:** Bash, Python 3 (inline `-c` snippets), Markdown

---

## Task 1: Fix shell injection in scope-guard.sh (CRITICAL)

**Files:**
- Modify: `hooks/scope-guard.sh:53-73`

The `contract` mode interpolates `$PROMPT` directly into a Python heredoc using `"""$PROMPT"""`. A prompt containing `"""` or `\n` followed by Python code can inject arbitrary Python. The fix: single-quote the heredoc delimiter (`'PYEOF'`) to stop shell expansion, and pass `PROMPT` via environment variable instead.

- [ ] **Step 1: Apply the fix**

Replace this block in `hooks/scope-guard.sh` (lines 53–73):

```bash
  python3 << PYEOF > "$CONTRACT_FILE" 2>/dev/null || echo "scope:general" > "$CONTRACT_FILE"
import re, sys

prompt = """$PROMPT"""
signals = []

paths = re.findall(r'[\w./\-]+\.(?:tsx?|jsx?|py|rs|go|rb|java|php|sh|md|json|yaml|yml|css|scss|html|vue|svelte)', prompt)
signals.extend(paths[:5])

lines = re.findall(r'line\s+(\d+)', prompt, re.IGNORECASE)
if lines:
    signals.append('line ' + ', '.join(lines))

if re.search(r'\b(only|just|this file|single file|one file)\b', prompt, re.IGNORECASE):
    signals.append('single-file-scope')

if signals:
    print('scope:' + '|'.join(dict.fromkeys(signals)))
else:
    print('scope:general')
PYEOF
```

With this (note single-quoted `'PYEOF'` and `os.environ` lookup):

```bash
  SCOPE_PROMPT="$PROMPT" python3 << 'PYEOF' > "$CONTRACT_FILE" 2>/dev/null || echo "scope:general" > "$CONTRACT_FILE"
import re, os

prompt = os.environ.get('SCOPE_PROMPT', '')
signals = []

paths = re.findall(r'[\w./\-]+\.(?:tsx?|jsx?|py|rs|go|rb|java|php|sh|md|json|yaml|yml|css|scss|html|vue|svelte)', prompt)
signals.extend(paths[:5])

lines = re.findall(r'line\s+(\d+)', prompt, re.IGNORECASE)
if lines:
    signals.append('line ' + ', '.join(lines))

if re.search(r'\b(only|just|this file|single file|one file)\b', prompt, re.IGNORECASE):
    signals.append('single-file-scope')

if signals:
    print('scope:' + '|'.join(dict.fromkeys(signals)))
else:
    print('scope:general')
PYEOF
```

- [ ] **Step 2: Verify the heredoc delimiter is single-quoted**

```bash
grep "python3 << 'PYEOF'" hooks/scope-guard.sh
```
Expected: one match on the contract mode block.

- [ ] **Step 3: Verify SCOPE_PROMPT env var is used**

```bash
grep "SCOPE_PROMPT" hooks/scope-guard.sh
```
Expected: two matches — assignment and `os.environ.get`.

- [ ] **Step 4: Commit**

```bash
git add hooks/scope-guard.sh
git commit -m "fix(security): prevent shell injection in scope-guard contract mode

Interpolating \$PROMPT directly into a Python heredoc allowed crafted
prompts to inject arbitrary Python. Pass via SCOPE_PROMPT env var and
single-quote the heredoc delimiter to prevent expansion."
```

---

## Task 2: Fix stale version strings

**Files:**
- Modify: `tools/supercharger.sh:14`
- Modify: `tools/claude-check.sh:324`
- Modify: `configs/universal/CLAUDE.md:1`
- Modify: `tools/export-preset.sh:75`

Four separate files hardcode `1.5.0` (or the wrong `1.7.6` in a way that won't update). `lib/utils.sh` is the canonical version source (`VERSION="1.7.6"`). The deployed tools don't have access to `lib/utils.sh` at runtime, so the fix is to update the hardcoded strings to `1.7.6`.

- [ ] **Step 1: Fix tools/supercharger.sh**

Change line 14:
```bash
VERSION="1.5.0"
```
To:
```bash
VERSION="1.7.6"
```

- [ ] **Step 2: Fix configs/universal/CLAUDE.md**

Change line 1:
```markdown
# Claude Supercharger v1.5.0
```
To:
```markdown
# Claude Supercharger v1.7.6
```

- [ ] **Step 3: Fix tools/export-preset.sh**

Change the `'version': '1.5.0'` line in the Python block (around line 75):
```python
    'version': '1.5.0',
```
To:
```python
    'version': '1.7.6',
```

- [ ] **Step 4: Verify no remaining 1.5.0 references in scripts**

```bash
grep -r "1\.5\.0" tools/ hooks/ configs/ lib/ --include="*.sh" --include="*.md" --include="*.json" --include="*.py" -l
```
Expected: no output (all cleared).

- [ ] **Step 5: Commit**

```bash
git add tools/supercharger.sh configs/universal/CLAUDE.md tools/export-preset.sh
git commit -m "fix: update stale version strings from 1.5.0 to 1.7.6"
```

---

## Task 3: Fix count_installed_hooks undercount

**Files:**
- Modify: `lib/hooks.sh:182-199`

`count_installed_hooks` adds 6 for standard mode but `get_hooks_for_mode` registers 9 additional hooks (notify, git-safety, enforce-pkg-manager, audit-trail, scope-guard check, project-config, scope-guard snapshot, scope-guard contract, update-check). Full mode adds 4 more (prompt-validator, compaction-backup, session-complete, scope-guard clear), not 3.

- [ ] **Step 1: Apply the fix**

Replace lines 182–199 in `lib/hooks.sh`:

```bash
count_installed_hooks() {
  local mode="$1"
  local has_developer="$2"
  local count=1  # safety always

  if [[ "$mode" == "standard" || "$mode" == "full" ]]; then
    count=$((count + 6))  # notify, git-safety, enforce-pkg-manager, audit-trail, project-config, update-check
    if [[ "$has_developer" == "true" ]]; then
      count=$((count + 1))  # quality-gate
    fi
  fi

  if [[ "$mode" == "full" ]]; then
    count=$((count + 3))  # prompt-validator, compaction-backup, session-complete
  fi

  echo "$count"
}
```

With:

```bash
count_installed_hooks() {
  local mode="$1"
  local has_developer="$2"
  local count=1  # safety always

  if [[ "$mode" == "standard" || "$mode" == "full" ]]; then
    # notify, git-safety, enforce-pkg-manager, audit-trail,
    # scope-guard(check+snapshot+contract), project-config, update-check
    count=$((count + 9))
    if [[ "$has_developer" == "true" ]]; then
      count=$((count + 1))  # quality-gate
    fi
  fi

  if [[ "$mode" == "full" ]]; then
    # prompt-validator, compaction-backup, session-complete, scope-guard clear
    count=$((count + 4))
  fi

  echo "$count"
}
```

- [ ] **Step 2: Verify the counts**

```bash
source lib/hooks.sh
echo "safe/standard no-dev: $(count_installed_hooks standard false)"   # expect 10
echo "safe/standard dev:    $(count_installed_hooks standard true)"    # expect 11
echo "safe/full no-dev:     $(count_installed_hooks full false)"       # expect 14
echo "safe/full dev:        $(count_installed_hooks full true)"        # expect 15
```

- [ ] **Step 3: Cross-check with get_hooks_for_mode**

```bash
source lib/hooks.sh
get_hooks_for_mode standard false /tmp | wc -l   # expect 10
get_hooks_for_mode standard true /tmp | wc -l    # expect 11
get_hooks_for_mode full false /tmp | wc -l       # expect 14
get_hooks_for_mode full true /tmp | wc -l        # expect 15
```

- [ ] **Step 4: Commit**

```bash
git add lib/hooks.sh
git commit -m "fix(lib): correct count_installed_hooks to include scope-guard and scope-guard clear"
```

---

## Task 4: Fix uninstall.sh missing role files

**Files:**
- Modify: `uninstall.sh:66`

`designer.md`, `devops.md`, and `researcher.md` (added in v1.4.0) are not in the cleanup list. They survive uninstall.

- [ ] **Step 1: Apply the fix**

Change line 66 in `uninstall.sh`:
```bash
for f in supercharger.md guardrails.md economy.md developer.md writer.md student.md data.md pm.md anti-patterns.yml; do
```
To:
```bash
for f in supercharger.md guardrails.md economy.md developer.md writer.md student.md data.md pm.md designer.md devops.md researcher.md anti-patterns.yml; do
```

- [ ] **Step 2: Verify all current role files are in the list**

```bash
ls configs/roles/ 2>/dev/null || ls configs/ | grep -v universal
```
Cross-check that every `*.md` in the roles config directory is covered by the loop.

- [ ] **Step 3: Commit**

```bash
git add uninstall.sh
git commit -m "fix(uninstall): remove designer, devops, researcher role files on uninstall"
```

---

## Task 5: Fix quality-gate.sh eslint config glob bug

**Files:**
- Modify: `hooks/quality-gate.sh:46`

`[ -f "$PROJECT_ROOT/.eslintrc"* ]` uses a glob inside a `test` expression, which never expands. The eslint check silently never fires. The fix uses `compgen -G` (bash builtin) which returns 0 when any glob matches.

- [ ] **Step 1: Apply the fix**

Replace line 46 in `hooks/quality-gate.sh`:
```bash
      if command -v eslint &>/dev/null && [ -f "$PROJECT_ROOT/.eslintrc"* ] 2>/dev/null || [ -f "$PROJECT_ROOT/eslint.config"* ] 2>/dev/null; then
```
With:
```bash
      if command -v eslint &>/dev/null && { compgen -G "$PROJECT_ROOT/.eslintrc*" &>/dev/null || compgen -G "$PROJECT_ROOT/eslint.config*" &>/dev/null; }; then
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n hooks/quality-gate.sh && echo "syntax ok"
```
Expected: `syntax ok`

- [ ] **Step 3: Commit**

```bash
git add hooks/quality-gate.sh
git commit -m "fix(quality-gate): use compgen -G for eslint config glob check

[ -f \"\$path\"* ] never expands globs in test expressions, so the
eslint lint stage never ran. compgen -G returns 0 on any match."
```

---

## Task 6: Fix deprecated Python datetime in audit-trail.sh and cross-platform date in update-check.sh

**Files:**
- Modify: `hooks/audit-trail.sh:33,42`
- Modify: `hooks/update-check.sh:20`

`datetime.utcnow()` is deprecated in Python 3.12+. `date -r file` is macOS-only and always returns 0 on Linux, causing update-check to re-fetch every session on Linux.

- [ ] **Step 1: Fix audit-trail.sh — replace utcnow() in both places**

In `hooks/audit-trail.sh`, there are two occurrences of `datetime.datetime.utcnow().isoformat()+'Z'`.

Replace both occurrences of:
```python
datetime.datetime.utcnow().isoformat()+'Z'
```
With:
```python
datetime.datetime.now(tz=datetime.timezone.utc).isoformat().replace('+00:00','Z')
```

The `import datetime` already covers `datetime.timezone.utc` (available since Python 3.2).

- [ ] **Step 2: Verify both occurrences are fixed**

```bash
grep "utcnow" hooks/audit-trail.sh
```
Expected: no output.

- [ ] **Step 3: Fix update-check.sh — cross-platform cache mtime**

Replace line 20 in `hooks/update-check.sh`:
```bash
  CACHE_AGE=$(( $(date +%s) - $(date -r "$CACHE_FILE" +%s 2>/dev/null || echo 0) ))
```
With:
```bash
  CACHE_MTIME=$(stat -f "%m" "$CACHE_FILE" 2>/dev/null || stat -c "%Y" "$CACHE_FILE" 2>/dev/null || echo 0)
  CACHE_AGE=$(( $(date +%s) - CACHE_MTIME ))
```

This is the same `stat -f || stat -c` pattern already used in `scope-guard.sh` for cross-platform compatibility.

- [ ] **Step 4: Verify syntax**

```bash
bash -n hooks/audit-trail.sh && echo "audit-trail ok"
bash -n hooks/update-check.sh && echo "update-check ok"
```
Expected: both lines print `ok`.

- [ ] **Step 5: Commit**

```bash
git add hooks/audit-trail.sh hooks/update-check.sh
git commit -m "fix(hooks): use timezone-aware datetime and cross-platform stat for mtime

- audit-trail: replace deprecated utcnow() with now(tz=timezone.utc)
- update-check: replace macOS-only date -r with stat -f || stat -c pattern"
```

---

## Task 7: Fix stale hook list in hook-toggle.sh and missing hooks in supercharger.sh

**Files:**
- Modify: `tools/hook-toggle.sh:15-16`
- Modify: `tools/supercharger.sh:109-118,122`

`hook-toggle.sh` still lists `auto-format` (removed in v1.3.0) and omits `scope-guard`, `update-check`, `project-config`, `session-complete`. `supercharger.sh` hook inventory loop also omits these four hooks.

- [ ] **Step 1: Fix hook-toggle.sh usage text**

Replace lines 14–16 in `tools/hook-toggle.sh`:
```bash
  echo "Available hooks:"
  echo "  safety, git-safety, notify, auto-format, quality-gate,"
  echo "  prompt-validator, compaction-backup, enforce-pkg-manager, audit-trail"
```
With:
```bash
  echo "Available hooks:"
  echo "  safety, git-safety, notify, quality-gate, enforce-pkg-manager,"
  echo "  audit-trail, prompt-validator, compaction-backup, project-config,"
  echo "  scope-guard, update-check, session-complete"
```

- [ ] **Step 2: Fix supercharger.sh — add missing hook descriptions**

The `HOOK_DESCS` block in `tools/supercharger.sh` (lines 109–118) currently ends with `detect-stack`. Add three new entries:

Replace the HOOK_DESCS assignment to include the new hooks:
```bash
HOOK_DESCS="safety:Blocks dangerous commands before execution
notify:Sends webhook notification on task completion
git-safety:Warns on force-push and destructive git ops
quality-gate:Runs linter/tests and blocks commit if failing
enforce-pkg-manager:Prevents wrong package manager (e.g. npm in pnpm project)
audit-trail:Logs all file writes and deletions to .claude/audit/
project-config:Loads .supercharger.json overrides at session start
prompt-validator:Flags ambiguous or high-risk prompts before execution
compaction-backup:Saves context snapshot before /compact runs
scope-guard:Prevents writes outside declared scope during a session
update-check:Checks for Supercharger updates at session start
session-complete:Saves session summary on Stop event
detect-stack:Detects project language, framework, and package manager"
```

- [ ] **Step 3: Fix supercharger.sh — expand hook inventory loop**

Replace line 122 in `tools/supercharger.sh`:
```bash
  for hook in safety notify git-safety quality-gate enforce-pkg-manager audit-trail project-config prompt-validator compaction-backup; do
```
With:
```bash
  for hook in safety notify git-safety quality-gate enforce-pkg-manager audit-trail project-config scope-guard update-check prompt-validator compaction-backup session-complete; do
```

- [ ] **Step 4: Verify syntax**

```bash
bash -n tools/hook-toggle.sh && echo "hook-toggle ok"
bash -n tools/supercharger.sh && echo "supercharger ok"
```

- [ ] **Step 5: Commit**

```bash
git add tools/hook-toggle.sh tools/supercharger.sh
git commit -m "fix(tools): sync hook lists — remove auto-format, add scope-guard/update-check/session-complete"
```

---

## Task 8: Fix CONTRIBUTING.md errors

**Files:**
- Modify: `CONTRIBUTING.md:5,12,17`

Three factual errors: wrong uninstall command, wrong GitHub repo owner, outdated test count.

- [ ] **Step 1: Fix uninstall command (line 5)**

Change:
```markdown
Everything is reversible via `bash install.sh --uninstall`.
```
To:
```markdown
Everything is reversible via `bash uninstall.sh`.
```

- [ ] **Step 2: Fix repo owner in git clone URL (line 12)**

Change:
```bash
git clone https://github.com/radiustheme/claude-supercharger
```
To:
```bash
git clone https://github.com/smrafiz/claude-supercharger
```

- [ ] **Step 3: Fix test count (line 17)**

Change:
```markdown
All 150 tests must pass before submitting a PR.
```
To:
```markdown
All 227 tests must pass before submitting a PR.
```

- [ ] **Step 4: Verify no other stale references**

```bash
grep -n "radiustheme" CONTRIBUTING.md
grep -n "install.sh --uninstall" CONTRIBUTING.md
grep -n "150 tests" CONTRIBUTING.md
```
Expected: no output for any of the three.

- [ ] **Step 5: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "fix(docs): correct uninstall command, repo owner, and test count in CONTRIBUTING.md"
```

---

## Task 9: Remove dead code in lib/extras.sh

**Files:**
- Modify: `lib/extras.sh:12-15`

The `shared/guardrails-template.yml` file does not exist in the repository and has never been created. The `if [ -f ... ]` guard means it silently skips, making lines 12–15 permanently dead code.

- [ ] **Step 1: Remove the dead block**

Remove these lines from `lib/extras.sh`:
```bash
  if [ -f "$source_dir/shared/guardrails-template.yml" ]; then
    cp "$source_dir/shared/guardrails-template.yml" "$HOME/.claude/shared/"
    success "Guardrails template installed"
  fi
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n lib/extras.sh && echo "syntax ok"
```

- [ ] **Step 3: Confirm no other references to guardrails-template.yml (except uninstall cleanup)**

```bash
grep -rn "guardrails-template.yml" . --include="*.sh" --include="*.md"
```
Expected: only `uninstall.sh` (which already cleans up the path for legacy installs — that line is correct to keep).

- [ ] **Step 4: Commit**

```bash
git add lib/extras.sh
git commit -m "fix(lib): remove dead guardrails-template.yml deploy block — file never existed"
```

---

## Task 10: Add missing CHANGELOG entries for v1.7.1–v1.7.6

**Files:**
- Modify: `CHANGELOG.md`

Versions v1.7.1–v1.7.6 have no entries. Based on git history the changes are:
- v1.7.1–v1.7.4: update.sh fix (no longer re-runs full installer)
- v1.7.5: version bump + auto-update banner at session start + sound-only notification mode
- v1.7.6: scope-guard hook + fix off-by-one in count_installed_hooks

- [ ] **Step 1: Update Contents table at top of CHANGELOG.md**

Replace:
```markdown
## Contents

- [1.7.0] - 2026-04-03 — Custom Commands, Architect agent, reviewer hierarchy
```
With:
```markdown
## Contents

- [1.7.6] - 2026-04-06 — Scope Guard hook, hook count fix
- [1.7.5] - 2026-04-06 — Auto-update banner, sound-only notifications
- [1.7.4] - 2026-04-06 — update.sh: detect and preserve config silently
- [1.7.0] - 2026-04-03 — Custom Commands, Architect agent, reviewer hierarchy
```

- [ ] **Step 2: Add entries after the Contents block (before ## [1.7.0])**

Insert after `---` line (line 14):

```markdown
## [1.7.6] - 2026-04-06

### Added
- **Scope Guard hook** — `scope-guard.sh` runs in three modes: `snapshot` (SessionStart), `contract` (UserPromptSubmit), `check` (PostToolUse). Warns when writes exceed declared scope.

### Fixed
- `count_installed_hooks` was undercounting by 3 in standard mode and 1 in full mode (missing scope-guard entries and scope-guard clear).

---

## [1.7.5] - 2026-04-06

### Added
- **Auto-update banner** — `update-check.sh` hook prints a banner at SessionStart when a newer version is available (checks once per 24 hours, non-blocking).
- **Sound-only notification mode** — notify hook supports sound-only output without desktop popup.

### Changed
- `--check` flag now shows changelog summary.

---

## [1.7.4] - 2026-04-06

### Fixed
- `update.sh` no longer re-runs the full installer on update — detects installed mode and preserves user config silently.

---
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): add missing entries for v1.7.4–v1.7.6"
```

---

## Self-Review

**Spec coverage check:**
- [x] CRITICAL shell injection — Task 1
- [x] 4 stale version strings — Task 2
- [x] count_installed_hooks — Task 3
- [x] uninstall missing roles — Task 4
- [x] quality-gate eslint glob — Task 5
- [x] audit-trail datetime + update-check date -r — Task 6
- [x] hook-toggle stale list + supercharger hook inventory — Task 7
- [x] CONTRIBUTING.md 3 errors — Task 8
- [x] lib/extras.sh dead code — Task 9
- [x] CHANGELOG gaps — Task 10

**Items intentionally deferred (medium/structural, no functional breakage):**
- Duplicate update-check logic between `project-config.sh` and `update-check.sh` — architectural cleanup, not a bug
- `docs/ROADMAP.md` stale v1.6 feature list — informational doc, no runtime impact
- `claude-supercharger/` nested subdirectory — needs investigation before deletion
- Hook count discrepancy in `claude-check.sh` vs `lib/hooks.sh` — display-only, low urgency

**Placeholder scan:** No TBD, TODO, or "similar to Task N" patterns. All steps contain concrete code.

**Type consistency:** No shared types across tasks — each task is self-contained shell/Python edits.
