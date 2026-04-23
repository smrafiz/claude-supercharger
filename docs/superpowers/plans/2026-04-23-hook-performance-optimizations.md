# Hook Performance Optimizations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce hook execution latency, eliminate unnecessary subprocess forks, and add hash-based caching and runtime profile gating across 7 optimization areas.

**Architecture:** Purely additive changes to existing shell hooks and lib-suppress.sh. No new files needed. Each optimization is independent and can be validated individually. Tests are updated in-place in `tests/test-hooks.sh` and `tests/test-install.sh`.

**Tech Stack:** Bash, Python 3, existing test harness (`tests/helpers.sh`, `tests/test-hooks.sh`)

---

## Files Modified

| File | Change |
|---|---|
| `hooks/lib-suppress.sh` | #1 `$EPOCHREALTIME` timing; #4 associative array for disabled-hooks |
| `hooks/statusline.sh` | #6 skip redundant `economy.md` scan |
| `hooks/typecheck.sh` | #3 sha256 hash-cache to skip unchanged files |
| `hooks/quality-gate.sh` | #3 sha256 hash-cache to skip unchanged files |
| `lib/hooks.sh` | #2 mark PostToolUse write hooks async; #5 runtime profile gating |
| `hooks/audit-trail.sh` | #2 already async — verify |
| `tests/test-hooks.sh` | add/update tests for #1, #3, #4, #6 |
| `CHANGELOG.md` + `README.md` | version bump note (handled separately) |

---

## Task 1: `$EPOCHREALTIME` replaces python3 timing fork in `lib-suppress.sh`

**Files:**
- Modify: `hooks/lib-suppress.sh:27-30`
- Test: `tests/test-hooks.sh`

Currently `init_hook_suppress` forks a Python interpreter to get millisecond timestamp when profiling is active. `$EPOCHREALTIME` (bash 5+) gives the same result with zero fork.

- [ ] **Step 1: Read current timing code** (already read — lines 27-30 of lib-suppress.sh)

- [ ] **Step 2: Write a failing test**

In `tests/test-hooks.sh`, add inside the lib-suppress section (after existing lib-suppress tests):

```bash
begin_test "lib-suppress: timing uses EPOCHREALTIME not python3"
# Should not contain python3 timing call
assert_file_not_contains "$REPO_DIR/hooks/lib-suppress.sh" 'python3 -c "import time' &&
pass
```

Run: `bash tests/test-hooks.sh 2>&1 | grep "timing uses EPOCHREALTIME"`
Expected: FAIL (python3 call still present)

- [ ] **Step 3: Replace the timing code**

In `hooks/lib-suppress.sh`, replace lines 27-30:

```bash
  # Timing instrumentation — only active when profiler is running
  HOOK_START_MS=0
  if [ -f "$HOME/.claude/supercharger/scope/.profiling" ]; then
    HOOK_START_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "0")
  fi
```

With:

```bash
  # Timing instrumentation — only active when profiler is running
  HOOK_START_MS=0
  if [ -f "$HOME/.claude/supercharger/scope/.profiling" ]; then
    # $EPOCHREALTIME (bash 5+): "seconds.microseconds" — convert to ms, zero fork
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
      HOOK_START_MS=$(( ${EPOCHREALTIME/./} / 1000 ))
    else
      HOOK_START_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "0")
    fi
  fi
```

- [ ] **Step 4: Run the test**

Run: `bash tests/test-hooks.sh 2>&1 | grep "timing uses EPOCHREALTIME"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/lib-suppress.sh tests/test-hooks.sh
git commit -m "perf: use \$EPOCHREALTIME for hook timing — eliminates python3 fork"
```

---

## Task 2: Associative array for `check_hook_disabled` — eliminate grep fork

**Files:**
- Modify: `hooks/lib-suppress.sh:33-39`
- Test: `tests/test-hooks.sh`

Currently `check_hook_disabled` spawns `grep -qx` on every call. Replace with an in-memory associative array loaded once at `init_hook_suppress` time.

- [ ] **Step 1: Write a failing test**

Add to `tests/test-hooks.sh`:

```bash
begin_test "lib-suppress: check_hook_disabled uses in-memory array not grep"
assert_file_not_contains "$REPO_DIR/hooks/lib-suppress.sh" 'grep -qx' &&
pass
```

Run: `bash tests/test-hooks.sh 2>&1 | grep "in-memory array"`
Expected: FAIL

- [ ] **Step 2: Replace check_hook_disabled with associative array**

Replace the entire `check_hook_disabled` function and the file-read logic in `hooks/lib-suppress.sh`:

Old (lines 33-39):
```bash
check_hook_disabled() {
  local hook_name="${1:-}"
  [ -z "$hook_name" ] && return 1
  local disabled_file="$HOME/.claude/supercharger/scope/.disabled-hooks"
  [ ! -f "$disabled_file" ] && return 1
  grep -qx "$hook_name" "$disabled_file" 2>/dev/null
}
```

New (replace and also update `init_hook_suppress` to load the array):

```bash
# Associative array of disabled hooks — populated once at init time
declare -A _DISABLED_HOOKS=()

_load_disabled_hooks() {
  _DISABLED_HOOKS=()
  local disabled_file="$HOME/.claude/supercharger/scope/.disabled-hooks"
  [ ! -f "$disabled_file" ] && return
  while IFS= read -r line; do
    [[ -n "$line" ]] && _DISABLED_HOOKS["$line"]=1
  done < "$disabled_file"
}

check_hook_disabled() {
  local hook_name="${1:-}"
  [ -z "$hook_name" ] && return 1
  [[ -v _DISABLED_HOOKS["$hook_name"] ]]
}
```

Also add `_load_disabled_hooks` call inside `init_hook_suppress()`, before the `return` at end:

```bash
  _load_disabled_hooks
```

Full updated `init_hook_suppress`:

```bash
init_hook_suppress() {
  local dir="${1:-}"
  HOOK_SUPPRESS=true
  if [ -f "$HOME/.claude/supercharger/scope/.debug-hooks" ]; then
    HOOK_SUPPRESS=false; return
  fi
  if [ -n "$dir" ] && [ -f "${dir}/.supercharger-debug" ]; then
    HOOK_SUPPRESS=false; return
  fi
  [ -f "${PWD}/.supercharger-debug" ] && HOOK_SUPPRESS=false || true

  # Timing instrumentation — only active when profiler is running
  HOOK_START_MS=0
  if [ -f "$HOME/.claude/supercharger/scope/.profiling" ]; then
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
      HOOK_START_MS=$(( ${EPOCHREALTIME/./} / 1000 ))
    else
      HOOK_START_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "0")
    fi
  fi

  _load_disabled_hooks
}
```

- [ ] **Step 3: Verify existing hook-toggle tests still pass**

Run: `bash tests/test-hook-toggle.sh 2>&1 | tail -3`
Expected: all passed, 0 failed

- [ ] **Step 4: Run the new test**

Run: `bash tests/test-hooks.sh 2>&1 | grep "in-memory array"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/lib-suppress.sh tests/test-hooks.sh
git commit -m "perf: replace grep fork in check_hook_disabled with in-memory associative array"
```

---

## Task 3: Hash-cache for typecheck.sh — skip if file unchanged

**Files:**
- Modify: `hooks/typecheck.sh`
- Test: `tests/test-hooks.sh`

Add sha256 fingerprint of file + tsconfig path. Skip tsc run if hash matches last run. Cache file: `~/.claude/supercharger/scope/.typecheck-cache-{project_hash}` (JSON: `{file_path: hash}`).

- [ ] **Step 1: Write a failing test**

Add to `tests/test-hooks.sh`:

```bash
begin_test "typecheck: skips tsc when file hash unchanged"
TMPDIR_TC=$(mktemp -d)
# Create a minimal TS project
mkdir -p "$TMPDIR_TC/src"
echo '{"compilerOptions":{"strict":true}}' > "$TMPDIR_TC/tsconfig.json"
echo 'const x: number = 1;' > "$TMPDIR_TC/src/foo.ts"
# Set up cache with current hash
HASH=$(sha256sum "$TMPDIR_TC/src/foo.ts" 2>/dev/null | cut -d' ' -f1 || shasum -a256 "$TMPDIR_TC/src/foo.ts" 2>/dev/null | cut -d' ' -f1 || echo "")
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
PROJ_HASH=$(echo -n "$TMPDIR_TC" | python3 -c "import sys,hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest()[:8])")
CACHE_FILE="$SCOPE_DIR/.typecheck-cache-${PROJ_HASH}"
echo "{\"$TMPDIR_TC/src/foo.ts\": \"$HASH\"}" > "$CACHE_FILE"
# Run hook — should exit 0 silently (cache hit)
INPUT=$(printf '{"tool_input":{"file_path":"%s"}}' "$TMPDIR_TC/src/foo.ts")
OUT=$(printf '%s' "$INPUT" | bash "$REPO_DIR/hooks/typecheck.sh" 2>&1)
rm -f "$CACHE_FILE"
rm -rf "$TMPDIR_TC"
# Output should be empty (no tsc errors injected, skipped)
[ -z "$OUT" ] && pass || fail "expected empty output on cache hit, got: $OUT"
```

Run: `bash tests/test-hooks.sh 2>&1 | grep "skips tsc"`
Expected: FAIL (no cache logic yet)

- [ ] **Step 2: Add hash-cache logic to typecheck.sh**

After the `[ -z "$TSCONFIG" ] && exit 0` line (line 45) and before `[ -f "$PROJECT_ROOT/.supercharger-no-typecheck" ] && exit 0`, insert:

```bash
# Hash-cache: skip tsc if file content unchanged since last run
_typecheck_hash() {
  sha256sum "$1" 2>/dev/null | cut -d' ' -f1 || shasum -a256 "$1" 2>/dev/null | cut -d' ' -f1 || echo ""
}

SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
PROJ_HASH=$(echo -n "$PROJECT_ROOT" | python3 -c "import sys,hashlib; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest()[:8])" 2>/dev/null || echo "default")
TC_CACHE="$SCOPE_DIR/.typecheck-cache-${PROJ_HASH}"

FILE_HASH=$(_typecheck_hash "$FILE_PATH")
if [ -n "$FILE_HASH" ] && [ -f "$TC_CACHE" ]; then
  CACHED_HASH=$(python3 -c "
import json, os, sys
try:
  with open(os.environ['TC_CACHE']) as f:
    d = json.load(f)
  print(d.get(os.environ['FILE_PATH'], ''))
except Exception:
  print('')
" TC_CACHE="$TC_CACHE" FILE_PATH="$FILE_PATH" 2>/dev/null || echo "")
  if [ "$CACHED_HASH" = "$FILE_HASH" ]; then
    exit 0  # cache hit — file unchanged, skip tsc
  fi
fi
```

After the tsc run (after `ERRORS=$(...)` line), if errors is empty, write the hash to cache:

```bash
[ -z "$ERRORS" ] && {
  # Update cache: store hash for this file
  if [ -n "$FILE_HASH" ]; then
    python3 -c "
import json, os
cache_file = os.environ['TC_CACHE']
file_path = os.environ['FILE_PATH']
file_hash = os.environ['FILE_HASH']
try:
  with open(cache_file) as f:
    d = json.load(f)
except Exception:
  d = {}
d[file_path] = file_hash
with open(cache_file, 'w') as f:
  json.dump(d, f)
" TC_CACHE="$TC_CACHE" FILE_PATH="$FILE_PATH" FILE_HASH="$FILE_HASH" 2>/dev/null || true
  fi
  exit 0
}
```

- [ ] **Step 3: Run the test**

Run: `bash tests/test-hooks.sh 2>&1 | grep "skips tsc"`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add hooks/typecheck.sh tests/test-hooks.sh
git commit -m "perf: hash-cache in typecheck.sh — skip tsc when file unchanged"
```

---

## Task 4: Hash-cache for quality-gate.sh — skip lint when file unchanged

**Files:**
- Modify: `hooks/quality-gate.sh`
- Test: `tests/test-hooks.sh`

Same sha256 cache pattern as Task 3, but for quality-gate. Cache key: file hash. If hash matches last run with no issues, skip. Invalidate on any lint output.

- [ ] **Step 1: Write a failing test**

Add to `tests/test-hooks.sh`:

```bash
begin_test "quality-gate: skips lint when file hash unchanged and no prior issues"
TMPDIR_QG=$(mktemp -d)
echo 'x = 1' > "$TMPDIR_QG/clean.py"
HASH=$(sha256sum "$TMPDIR_QG/clean.py" 2>/dev/null | cut -d' ' -f1 || shasum -a256 "$TMPDIR_QG/clean.py" 2>/dev/null | cut -d' ' -f1 || echo "")
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
PROJ_HASH=$(echo -n "$TMPDIR_QG" | python3 -c "import sys,hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest()[:8])")
CACHE_FILE="$SCOPE_DIR/.quality-gate-cache-${PROJ_HASH}"
echo "{\"$TMPDIR_QG/clean.py\": \"$HASH\"}" > "$CACHE_FILE"
INPUT=$(printf '{"tool_input":{"file_path":"%s"}}' "$TMPDIR_QG/clean.py")
OUT=$(printf '%s' "$INPUT" | bash "$REPO_DIR/hooks/quality-gate.sh" 2>&1)
rm -f "$CACHE_FILE"
rm -rf "$TMPDIR_QG"
[ -z "$OUT" ] && pass || fail "expected silent cache hit, got: $OUT"
```

Run: `bash tests/test-hooks.sh 2>&1 | grep "quality-gate: skips lint"`
Expected: FAIL

- [ ] **Step 2: Add hash-cache to quality-gate.sh**

After `check_hook_disabled "quality-gate" && exit 0` (line 24), before `EXT=`, insert:

```bash
# Hash-cache: skip lint if file unchanged since last clean run
_qg_hash() {
  sha256sum "$1" 2>/dev/null | cut -d' ' -f1 || shasum -a256 "$1" 2>/dev/null | cut -d' ' -f1 || echo ""
}

SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
QG_PROJ_HASH=$(echo -n "$PROJECT_ROOT" | python3 -c "import sys,hashlib; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest()[:8])" 2>/dev/null || echo "default")
QG_CACHE="$SCOPE_DIR/.quality-gate-cache-${QG_PROJ_HASH}"
QG_FILE_HASH=$(_qg_hash "$FILE_PATH")

if [ -n "$QG_FILE_HASH" ] && [ -f "$QG_CACHE" ]; then
  QG_CACHED=$(python3 -c "
import json, os
try:
  with open(os.environ['QG_CACHE']) as f:
    d = json.load(f)
  print(d.get(os.environ['FILE_PATH'], ''))
except Exception:
  print('')
" QG_CACHE="$QG_CACHE" FILE_PATH="$FILE_PATH" 2>/dev/null || echo "")
  if [ "$QG_CACHED" = "$QG_FILE_HASH" ]; then
    exit 0  # cache hit — file unchanged, skip lint
  fi
fi
```

At the end of the file, before `exit 0`, add cache write on clean run:

```bash
# Write cache on clean exit (no remaining issues)
if [ -z "$REMAINING" ] && [ -n "$QG_FILE_HASH" ]; then
  python3 -c "
import json, os
cache_file = os.environ['QG_CACHE']
file_path = os.environ['FILE_PATH']
file_hash = os.environ['QG_FILE_HASH']
try:
  with open(cache_file) as f:
    d = json.load(f)
except Exception:
  d = {}
d[file_path] = file_hash
with open(cache_file, 'w') as f:
  json.dump(d, f)
" QG_CACHE="$QG_CACHE" FILE_PATH="$FILE_PATH" QG_FILE_HASH="$QG_FILE_HASH" 2>/dev/null || true
fi
```

- [ ] **Step 3: Run the test**

Run: `bash tests/test-hooks.sh 2>&1 | grep "quality-gate: skips lint"`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add hooks/quality-gate.sh tests/test-hooks.sh
git commit -m "perf: hash-cache in quality-gate.sh — skip lint when file unchanged"
```

---

## Task 5: Skip redundant `economy.md` scan in statusline when `.economy-tier` exists

**Files:**
- Modify: `hooks/statusline.sh:194-203`

The economy tier fallback (`if not eco:` block reading economy.md line by line) is dead code whenever `.economy-tier` file exists. Since `economy-tier` is written at SessionStart and on every tier switch, the fallback is only needed on first-ever launch before any session. Guard it with a staleness check: skip if `.economy-tier` was written in the last 7 days.

- [ ] **Step 1: Write a failing test** (no test needed — this is a pure performance guard with no behavior change when `.economy-tier` is present; the fallback path still works)

- [ ] **Step 2: Add early-exit guard to economy.md scan**

In `hooks/statusline.sh`, replace the eco section (lines 184-204):

```python
 # Economy tier
 eco = ''
 try:
     scope = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
     tier_file = os.path.join(scope, '.economy-tier')
     if os.path.isfile(tier_file):
         with open(tier_file) as f:
             tier = f.read().strip().lower()
         if tier:
             eco = f' {DIM}|{RESET} {DIM}Eco: {tier.capitalize()}{RESET}'
     if not eco:
         economy_md = os.path.join(os.path.expanduser('~'), '.claude', 'rules', 'economy.md')
         if os.path.isfile(economy_md):
             with open(economy_md) as f:
                 for ln in f:
                     if ln.startswith('### Active Tier:'):
                         tier = ln.split(':', 1)[1].strip().split()[0]
                         eco = f' {DIM}|{RESET} {DIM}Eco: {tier}{RESET}'
                         break
 except Exception:
     pass
```

With:

```python
 # Economy tier
 eco = ''
 try:
     scope = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
     tier_file = os.path.join(scope, '.economy-tier')
     tier_file_fresh = os.path.isfile(tier_file) and (time.time() - os.path.getmtime(tier_file) < 604800)  # 7 days
     if os.path.isfile(tier_file):
         with open(tier_file) as f:
             tier = f.read().strip().lower()
         if tier:
             eco = f' {DIM}|{RESET} {DIM}Eco: {tier.capitalize()}{RESET}'
     if not eco and not tier_file_fresh:
         # Fallback: scan economy.md — only if .economy-tier is missing or very stale
         economy_md = os.path.join(os.path.expanduser('~'), '.claude', 'rules', 'economy.md')
         if os.path.isfile(economy_md):
             with open(economy_md) as f:
                 for ln in f:
                     if ln.startswith('### Active Tier:'):
                         tier = ln.split(':', 1)[1].strip().split()[0]
                         eco = f' {DIM}|{RESET} {DIM}Eco: {tier}{RESET}'
                         break
 except Exception:
     pass
```

- [ ] **Step 3: Verify statusline tests still pass**

Run: `bash tests/test-hooks.sh 2>&1 | grep "statusline"` — all should pass.

- [ ] **Step 4: Commit**

```bash
git add hooks/statusline.sh
git commit -m "perf: skip economy.md line-scan in statusline when .economy-tier is fresh"
```

---

## Task 6: Runtime profile gating via `SUPERCHARGER_PROFILE` env var

**Files:**
- Modify: `hooks/lib-suppress.sh`
- Modify: `lib/hooks.sh` (documentation comment only)
- Test: `tests/test-hooks.sh`

When `SUPERCHARGER_PROFILE=minimal`, PostToolUse non-security hooks exit early. When `=standard` (default), all hooks run. This is additive — does not change existing behavior unless env var is set.

Profile levels:
- `minimal` — skip: quality-gate, typecheck, repetition-detector, dep-vuln-scanner, mcp-tracker, failure-tracker, session-checkpoint, context-advisor, rate-limit-advisor, thinking-budget
- `standard` (default) — all hooks run

Add a helper to `lib-suppress.sh`:

- [ ] **Step 1: Write a failing test**

Add to `tests/test-hooks.sh`:

```bash
begin_test "lib-suppress: SUPERCHARGER_PROFILE=minimal skips quality-gate"
TMPDIR_PROF=$(mktemp -d)
echo 'x = 1' > "$TMPDIR_PROF/test.py"
INPUT=$(printf '{"tool_input":{"file_path":"%s"}}' "$TMPDIR_PROF/test.py")
OUT=$(SUPERCHARGER_PROFILE=minimal printf '%s' "$INPUT" | bash "$REPO_DIR/hooks/quality-gate.sh" 2>&1)
rm -rf "$TMPDIR_PROF"
[ -z "$OUT" ] && pass || fail "expected skip under minimal profile, got: $OUT"
```

Run: `bash tests/test-hooks.sh 2>&1 | grep "SUPERCHARGER_PROFILE=minimal"`
Expected: FAIL

- [ ] **Step 2: Add profile helper to lib-suppress.sh**

Add after `check_hook_disabled()`:

```bash
# Returns 0 (true) if the given hook should be skipped in the current profile
# Usage: hook_profile_skip "quality-gate" && exit 0
hook_profile_skip() {
  local hook_name="${1:-}"
  local profile="${SUPERCHARGER_PROFILE:-standard}"
  [ "$profile" = "standard" ] && return 1  # nothing skipped

  # Hooks skipped in minimal profile (non-security, high-latency)
  local -a MINIMAL_SKIP=(
    quality-gate typecheck repetition-detector dep-vuln-scanner
    mcp-tracker failure-tracker session-checkpoint context-advisor
    rate-limit-advisor thinking-budget adaptive-economy
  )
  if [ "$profile" = "minimal" ]; then
    for s in "${MINIMAL_SKIP[@]}"; do
      [ "$s" = "$hook_name" ] && return 0
    done
  fi
  return 1
}
```

- [ ] **Step 3: Add profile skip call to quality-gate.sh**

After `check_hook_disabled "quality-gate" && exit 0` in `hooks/quality-gate.sh`, add:

```bash
hook_profile_skip "quality-gate" && exit 0
```

(The lib-suppress.sh is already sourced at this point.)

- [ ] **Step 4: Add profile skip to other skippable hooks**

In each of the following hooks, add `hook_profile_skip "hookname" && exit 0` after the `check_hook_disabled` line:

- `hooks/typecheck.sh` → `hook_profile_skip "typecheck" && exit 0`
- `hooks/repetition-detector.sh` → `hook_profile_skip "repetition-detector" && exit 0`
- `hooks/dep-vuln-scanner.sh` → `hook_profile_skip "dep-vuln-scanner" && exit 0`
- `hooks/session-checkpoint.sh` → `hook_profile_skip "session-checkpoint" && exit 0`
- `hooks/context-advisor.sh` → `hook_profile_skip "context-advisor" && exit 0`

First read each file to confirm the `check_hook_disabled` line exists and where it is, then add the profile skip immediately after.

- [ ] **Step 5: Run the failing test**

Run: `bash tests/test-hooks.sh 2>&1 | grep "SUPERCHARGER_PROFILE=minimal"`
Expected: PASS

- [ ] **Step 6: Run full test suite**

Run: `bash tests/test-hooks.sh 2>&1 | tail -3`
Expected: 0 failed

- [ ] **Step 7: Commit**

```bash
git add hooks/lib-suppress.sh hooks/quality-gate.sh hooks/typecheck.sh hooks/repetition-detector.sh hooks/dep-vuln-scanner.sh hooks/session-checkpoint.sh hooks/context-advisor.sh tests/test-hooks.sh
git commit -m "perf: add SUPERCHARGER_PROFILE=minimal to skip high-latency non-security hooks"
```

---

## Task 7: Consolidate failed-jq path to single python3 (skip double fork)

**Files:**
- Modify: hooks that use the `jq || python3` fallback pattern
- Test: `tests/test-hooks.sh`

The pattern `jq -r '.field' | python3 fallback` works fine, but some hooks attempt jq first even when absent, causing a fork + failure before the python3 fork. Add a session-scoped `JQ_AVAILABLE` sentinel so the jq fork is skipped on systems without jq, after the first miss.

This is additive — the `jq || python3` pattern is kept; we only prevent the repeated failed jq fork.

- [ ] **Step 1: Add jq availability check to lib-suppress.sh**

Add at the bottom of `lib-suppress.sh`, after `_load_disabled_hooks`:

```bash
# Cache jq availability for this session — avoids repeated failed fork on jq-less systems
if [ -z "${_JQ_AVAILABLE+set}" ]; then
  command -v jq &>/dev/null && _JQ_AVAILABLE=1 || _JQ_AVAILABLE=0
  export _JQ_AVAILABLE
fi

# Wrapper: use jq if available, else python3 directly (avoids double fork on jq-less systems)
jq_or_python() {
  local jq_filter="$1"
  local py_expr="$2"
  local input="$3"
  if [ "${_JQ_AVAILABLE:-0}" = "1" ]; then
    printf '%s\n' "$input" | jq -r "$jq_filter" 2>/dev/null
  else
    printf '%s\n' "$input" | python3 -c "import sys,json; $py_expr" 2>/dev/null || echo ""
  fi
}
```

- [ ] **Step 2: No test needed for this** (transparent wrapper, existing tests cover all hooks)

- [ ] **Step 3: Commit**

```bash
git add hooks/lib-suppress.sh
git commit -m "perf: cache jq availability in lib-suppress — avoid double fork on jq-less systems"
```

---

## Final Verification

- [ ] **Run full hook test suite**

```bash
bash tests/test-hooks.sh 2>&1 | tail -3
```
Expected: `N passed, 0 failed`

- [ ] **Run install tests**

```bash
bash tests/test-install.sh 2>&1 | tail -3
```
Expected: `11 passed, 0 failed`

- [ ] **Run full suite**

```bash
for f in tests/test-*.sh; do bash "$f" 2>&1 | tail -1; done
```
Expected: all show `N passed, 0 failed`

---

## Self-Review

**Spec coverage:**
- #1 `$EPOCHREALTIME` — Task 1 ✓
- #2 async PostToolUse hooks — already async in `lib/hooks.sh` (lines 20, 21, etc.) — no change needed, already done ✓
- #3 hash-cache typecheck — Task 3 ✓
- #4 associative array disabled-hooks — Task 2 ✓
- #5 runtime profile gating — Task 6 ✓
- #6 skip redundant economy.md scan — Task 5 ✓
- #7 single python3 fallback for jq — Task 7 ✓

**Async PostToolUse note:** Reviewing `lib/hooks.sh`: audit-trail (async), trace-compactor (async), mcp-output-truncator (async), cache-health (async). All PostToolUse write hooks already have `async` flag. Optimization #2 from research is already implemented. ✓

**Placeholder scan:** No TBD/TODO. All steps have actual code.

**Type consistency:** No new types introduced. All bash variable names are consistent across tasks.
