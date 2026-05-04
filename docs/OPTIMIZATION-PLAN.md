# Supercharger Optimization Plan

**Started:** 2026-05-05
**Goal:** Optimize performance, remove dead code, add security features — no feature cuts
**Success criteria:** Measured hook latency down, hook count down, security coverage up, zero user-facing regressions

---

## Phase 1 — Quick Wins (P0)

**Goal:** Remove dead weight, fix obvious issues. No risk.

### 1.1 Remove dead files from disk
```
hooks/shell-wrapper-guard.sh     — logic in safety.sh, no registration
hooks/exfiltration-guard.sh      — logic in safety.sh, no registration
```
- Verify: `grep -r "shell-wrapper-guard\|exfiltration-guard" lib/ hooks.sh configs/`
- Expected: zero references. Delete both files.
- Risk: none — these files are not loaded anywhere.

### 1.2 Fix CVE reference
```
hooks/code-security-scanner.sh — references CVE-2026-35021 (no public record)
```
- Search file for the CVE string. Replace with generic description or remove.
- Risk: none.

### 1.3 Verify env-file-guard.sh is NOT dead
```
hooks/env-file-guard.sh — guards PreToolUse|Read .env access
```
- `safety.sh` has matcher `Bash,PowerShell` — no Read coverage.
- Confirm: `env-file-guard.sh` has Read-specific logic and is registered at `hooks.sh:23`.
- **Keep it.** The audit initially flagged it as dead — incorrect. Document this in a comment in `hooks.sh`.

### 1.4 Add hook timeouts
- `safety.sh` Python fork: add `timeout 0.5` wrapper (500ms max).
- All hook registrations in `hooks.sh`: add `timeout: 30` to command entries where missing.
- Risk: low — hooks that legitimately take long (typecheck, quality-gate) already have their own limits.

### 1.5 Make low-value hooks opt-in via env var
Affected hooks: `lazy-refactor-check`, `comment-replacement-check`, `reentry-detector`, `design-context`.
- Each has existing enable/disable via hook-suppress or scope disable.
- Add `SUPERCHARGER_ADVISORY_HOOKS=0` env var that toggles all of them off at once.
- Default: `1` (enabled) so no behavior change.
- Risk: none — adds an opt-out, doesn't remove anything.

---

## Phase 2 — Performance Foundation (P1)

**Goal:** Hook-level caching. This is the single biggest perf win.

### 2.1 Session-scoped state directory
```
~/.claude/supercharger/scope/sessions/{session_id}/
```
- Create on first hook call per session.
- All session-scoped state (tool-history, repetition-flag, cache keys) moves here.
- **Critical:** prevents cross-session data leakage. Tool A cannot read tool B's history.
- Migration: on session start, detect old flat files in `scope/`, ignore or migrate.
- Test: verify session A's `.tool-history` does not appear in session B's reads.

### 2.2 Cache layer for tool-history-tracker reads
```
scope/sessions/{session_id}/.tool-history      — append-only log
scope/sessions/{session_id}/.tool-history.cache — 60s TTL cache of last N entries
```
- On `tool-history-tracker` PostToolUse: append to log (unchanged).
- On `confidence-gate` PreToolUse: read from cache. If cache miss or expired, rebuild from log.
- Cache entry: `{timestamp, session_id, tool, success}`. TTL: 60s.
- Key point: cache only affects *reads*. Writes always append to log.
- Performance: ~1ms reads instead of ~5ms for log parse.

### 2.3 Cache layer for detect-stack
```
scope/sessions/{session_id}/.stack — cache of detected stack info
```
- On `detect-stack` run: store result with `cwd` + `timestamp`.
- On subsequent runs (e.g., `cwd-changed`): check cache. If `cwd` matches and < 24h old, skip detection.
- No TTL needed for a single session — `cwd-changed` is the invalidation signal.

### 2.4 Cache layer for config-scan
```
scope/sessions/{session_id}/.config-scan — cached CLAUDE.md scan result
```
- Scan result is stable within a session. Cache for session duration.
- Invalidate: `file-watcher` triggers on `.claude/` changes.

### 2.5 Add agent-router TTL to existing dedup
- `agent-router.sh` already has prompt hash dedup.
- Add 30s TTL: store `{hash, result, timestamp}`. Skip re-injection if fresh.
- Invalidate on session boundary.

### 2.6 Benchmark the cache impact
- Before: measure `confidence-gate` latency on 100 tool calls.
- After: measure same. Target: 50%+ reduction in I/O time.
- Log results in `docs/PERF-BENCHMARKS.md`.

---

## Phase 3 — Security Hardening (P1)

**Goal:** Fill the gaps identified in the audit. No feature cuts.

### 3.1 Path traversal in Write/Edit
Add to `code-security-scanner.sh` or create `path-guard.sh`:
```
Patterns to detect:
- .. sequences (normalized)
- URL encoding: %2e, %252e (double encode)
- Null byte: %00, \x00
- Mixed path: /./ /../
- Trailing null byte

Implementation:
1. Decode URL encoding (single + double)
2. Remove null bytes
3. Normalize path (Python: os.path.normpath or realpath)
4. Resolve symlinks (readlink -f)
5. Check: is resolved path under project root?
```

### 3.2 Symlink attack detection
Add to `code-security-scanner.sh` or `scope-guard.sh check`:
```
For Write/Edit tool calls:
1. Resolve target path: readlink -f {file_path}
2. Check: is resolved path under project root?
3. If not → block with reason

Edge case: symlink created during operation. realpath resolves it.
```

### 3.3 Git hooks modification detection
Add to `code-security-scanner.sh` or create `git-guard.sh`:
```
Block Write/Edit to:
- .git/hooks/
- .githooks/
- $(git rev-parse --git-common-dir)/hooks/
- ~/.claude/hooks/  (supercharger hooks)
- .git/ (refs, objects — broad match)

Implementation:
1. Get project root: git rev-parse --show-toplevel
2. Get git dir: git rev-parse --git-dir
3. Check target path prefix against both
4. Block with clear reason
```

### 3.4 Absolute-path writes outside project
Add to `code-security-scanner.sh`:
```
Block Write/Edit to absolute paths outside project root:
- ~/.ssh/
- ~/.aws/
- ~/.config/
- ~/.npmrc
- ~/.gitconfig
- /etc/
- /usr/local/etc/

Implementation:
1. Resolve absolute path
2. Check: does it start with project root?
3. If not and is absolute → block
```

### 3.5 Build artifact injection detection
Add to `code-security-scanner.sh`:
```
Block writes to persistence directories:
- node_modules/.bin/
- __pycache__/
- .next/
- .venv/
- vendor/ (PHP/Go/Ruby — check context)
- dist/
- build/ (if in project root, not user workspace)

Implementation:
1. Check file path prefix against known persistence dirs
2. If matched → block with reason: dependency trojaning risk
```

### 3.6 Security scan result caching
When caching (Phase 2), security-critical results must use content-hash keys:
```
Cache key = SHA256(target_file_content) not just file_path
```
- Prevents stale security decisions when file content changes within TTL.

---

## Phase 4 — Cleanup & Consolidation (P2)

**Goal:** Reduce maintenance surface. These are restructured merges, not removals.

### 4.1 Consolidate notifications
```
notify.sh + notify-stop.sh + notify-permission.sh → notify-hub.sh
```
- `notify-helper.sh` is a library — stays as-is.
- Dispatcher: reads event type from input JSON, routes to appropriate handler.
- Test: verify all 3 notification types still fire correctly.
- Note: all are async — no latency impact.

### 4.2 Consolidate agent routing
```
agent-gate.sh + agent-router.sh + subagent-safety.sh +
subagent-stop-check.sh + agent-handoff-gate.sh → agent-orchestrator.sh
```
- Events handled: PreToolUse|Agent, UserPromptSubmit, SubagentStart, SubagentStop.
- Each uses fast-path early exits — consolidated script evaluates each concern in sequence.
- **Must test:** SubagentStart/SubagentStop events still fire correctly.

### 4.3 Consolidate advisors (requires event routing)
```
tool-failure-advisor.sh (PostToolUseFailure) +
slow-tool-detector.sh (PostToolUse) +
permission-denied-advisor.sh (PermissionDenied) → advisor.sh
```
- Different hook events — requires event-type routing in the dispatcher.
- Each handler is independent (different signals, different JSON paths).
- Not a simple merge — rewrite as a multi-handler dispatcher.

### 4.4 Consolidate cost management (exclude cache-health)
```
budget-cap.sh + cost-forecast.sh + subagent-cost.sh → cost-manager.sh
```
- `cache-health.sh` stays separate (observability, not cost signal).
- Shared state file: one JSON file per session, incremental updates.
- Test: budget cap still blocks at 100%, cost forecast still fires before agents.

### 4.5 Consolidate session lifecycle (requires set +e)
```
event-logger.sh + session-end.sh + session-complete.sh + session-checkpoint.sh
```
- `event-logger.sh` has `set -euo pipefail` — breaks on unhandled event types.
- **Must rewrite** `event-logger.sh` with `set +e` before merging.
- Multi-registration pattern or event-type dispatch inside the dispatcher.
- `session-checkpoint.sh` is architecturally distinct — include explicitly or keep separate.

### 4.6 Test suite for consolidated hooks
For each consolidation:
1. Unit test: each original concern still produces correct output
2. Integration test: hook still fires on correct event + matcher
3. Regression test: no behavior change for end users

---

## Phase 5 — Token Economy (P2)

**Goal:** Reduce token burn without cutting features.

### 5.1 Session context injection
```
hooks/session-context.sh — UserPromptSubmit, sync
```
Injects on every prompt:
```
Session: {session_name} [{session_id}]
Git branch: {branch}
Time: {time}
```
- Saves 50–100 tokens per request vs Claude using tool calls for this info.
- Based on [claude-hooks-sdk pattern](https://github.com/hgeldenhuys/claude-hooks-sdk).
- Replaces: partial coverage from `session-memory-inject` (SessionStart only).

### 5.2 Hook output suppression
Add `suppressOutput: true` to all advisory-only hooks:
- `lazy-refactor-check.sh`
- `comment-replacement-check.sh`
- `context-advisor.sh`
- `rate-limit-advisor.sh`
- `cache-health.sh` (warnings only)
- `cost-forecast.sh`
- `tool-call-limiter.sh`

Impact: advisory text no longer enters context, saving tokens on every hook invocation.

### 5.3 Prompt cache awareness for standards-inject
```
SessionStart → standards-inject.sh
  1. Check: is cache warm? (ENABLE_PROMPT_CACHING_1H is set)
  2. If warm → skip or reduce injection to minimal diff
  3. If cold → full injection
```
- 1-hour prompt cache TTL is already enabled (`hooks.sh:221`). Standards reinject on every `SessionStart` regardless.
- Gate on cache state or make injection idempotent.

### 5.4 Adaptive economy at lower thresholds
Current `adaptive-economy.sh` thresholds may be too conservative:
- Review current context % thresholds.
- Test: at what context % does token burn become significant?
- Adjust: switch to `lean` at 50% context (not 70%) to front-load savings.

---

## Phase 6 — Observability (P2)

### 6.1 Hook performance benchmarks in CI
```
tools/hook-perf.sh → integrated into release.sh
```
- Run perf report on every PR.
- Fail if any hook exceeds baseline by 20%+.
- Baseline: current median from `tools/hook-perf.sh` output stored in `docs/PERF-BASELINE.md`.

### 6.2 Cache hit rate dashboard
- `cache-health.sh` already tracks hit rate.
- Expose: sessions with < 60% cache hit rate get a transient warning.
- Log: per-session cache efficiency to `scope/events.log`.

### 6.3 Hook activation map
- Generate `docs/HOOK_ACTIVATION.md` — which hooks fire how often across sessions.
- Run `tools/session-analytics.sh` with `--hooks` flag.
- Identify: hooks that fire < 1% of sessions → candidates for opt-in.

---

## Phase 7 — SDK / Authoring (P3)

**Goal:** Better hooks, not more hooks.

### 7.1 Hook authoring SDK
```
tools/hook-new.sh → generates Python or TypeScript hooks
tools/hook-scaffold/ → shared testing utilities
```
- Instead of raw bash, generate hooks with typed input validation.
- Based on [mizunashi-mana/claude-code-hook-sdk](https://github.com/mizunashi-mana/claude-code-hook-sdk) patterns.
- Not a rewrite of existing hooks — new hooks use the SDK.

### 7.2 Per-tool rejection chains
```
hooks/tool-preferences.sh — PreToolUse
```
- Instead of blanket deny on `jest`, suggest `vitest`.
- Instead of blanket deny on `npm install`, suggest `pnpm install`.
- Based on [mizunashi-mana/claude-code-hook-sdk](https://github.com/mizunashi-mana/claude-code-hook-sdk)'s `preferAnotherTools` pattern.
- Config via `.supercharger.json`: `{"toolPreferences": {"npm": "pnpm", "jest": "vitest"}}`.

---

## Execution Order

```
Week 1-2: Phase 1 (Quick Wins)
  1.1 → 1.2 → 1.3 → 1.4 → 1.5

Week 3-4: Phase 2 (Performance Foundation)
  2.1 → 2.2 → 2.3 → 2.4 → 2.5 → 2.6

Week 5-7: Phase 3 (Security Hardening)
  3.1 → 3.2 → 3.3 → 3.4 → 3.5 → 3.6

Week 8+: Phase 4 (Consolidation) — one merge at a time
  4.1 → 4.2 → 4.4 → 4.3 → 4.5 → 4.6

Ongoing: Phase 5 (Token Economy) — parallel, lower priority
Ongoing: Phase 6 (Observability) — builds on all above
Ongoing: Phase 7 (SDK) — when capacity allows
```

**No parallelism between phases 1-4** — each phase validates the previous. Security hardening (3) should complete before consolidation (4), because consolidation changes hook structure.

---

## Anti-Goals (What this plan does NOT include)

- Removing `confidence-gate.sh`
- Removing `reflexion-memory` system
- Removing any enforcement hook → conversion to advisory-only
- Breaking backward compatibility in `.supercharger.json`
- Removing Safe mode coverage
- Adding telemetry or external data collection