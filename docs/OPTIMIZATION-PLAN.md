# Supercharger Optimization Plan (Cherry-Picked)

**Started:** 2026-05-05
**Updated:** 2026-05-05 — cut maintainer-only work, kept user-perceptible wins
**Goal:** Optimize performance and security without doing work users won't feel
**Success criteria:** Measured hook latency down, security coverage up, real UX improvements, zero regressions

---

## What changed from v1

The original 7-phase plan included consolidation, observability, and SDK work that benefits maintainers but not end users. Honest cost/benefit analysis:

| Phase | Status | Reason |
|---|---|---|
| 1 — Quick Wins | **KEEP** | Zero risk, accuracy + dead-file cleanup |
| 2 — Performance Foundation | **KEEP** | Fixes real cross-session leakage bug; 5–10x I/O cut on hot path |
| 3 — Security Hardening | **KEEP** (tunable) | Closes attack vectors no competitor catches |
| 4 — Consolidation | **DROP** | Same hooks, fewer files. User never sees this. Maintainer-only |
| 5 — Token Economy | **PARTIAL** | Keep suppressOutput; drop session-context inject (overlaps statusline) |
| 6 — Observability | **DROP** | CI perf bench has no user-facing benefit |
| 7 — SDK / Authoring | **PARTIAL** | Keep per-tool rejection chains (real UX); drop TypeScript SDK |

Net: 4 phases instead of 7. Same user value, ~half the work.

---

## Phase 1 — Quick Wins (P0)

**Goal:** Remove dead weight, fix obvious issues. No risk.

### 1.1 Remove dead files from disk
```
hooks/shell-wrapper-guard.sh     — logic in safety.sh, no registration
hooks/exfiltration-guard.sh      — logic in safety.sh, no registration
```
- Verify: `grep -r "shell-wrapper-guard\|exfiltration-guard" lib/ hooks/ configs/`
- Expected: zero references except the explanatory comment in `lib/hooks.sh:20`
- Action: delete both files **and clean the orphaned comment** at `lib/hooks.sh:20` referencing them
- Risk: none — these files are not loaded anywhere

### 1.2 Fix CVE reference
```
hooks/code-security-scanner.sh:132,135 — references CVE-2026-35021 (no public record)
```
- Replace with a generic description: "command injection via path metacharacters"
- Risk: none

### 1.3 Document env-file-guard.sh as active for Read
```
hooks/env-file-guard.sh — guards PreToolUse|Read .env access
```
- `safety.sh` matcher = `Bash,PowerShell` only — no Read coverage
- `env-file-guard.sh` is active at `lib/hooks.sh:23` for Read protection
- Action: add a comment in `lib/hooks.sh` explaining why this hook stays separate from `safety.sh`
- **Do not remove**

### 1.4 Add hook timeouts
- `safety.sh` Python fork: wrap in `timeout 0.5` (500ms cap)
- `lib/hooks.sh`: add `timeout: 30` field to hook command entries where missing
- Risk: low — long-running hooks (typecheck, quality-gate) already have their own limits

### 1.5 Make low-value hooks opt-out via env var
Affected hooks: `lazy-refactor-check`, `comment-replacement-check`, `reentry-detector`, `design-context`
- Add `SUPERCHARGER_ADVISORY_HOOKS=0` env var that disables all four at once
- Default: `1` (enabled — no behavior change)
- Document in README under "Disable individual features"
- Risk: none — adds opt-out, doesn't remove anything

---

## Phase 2 — Performance Foundation (P1)

**Goal:** Hook-level caching with session isolation. Single biggest perf win.

### 2.1 Session-scoped state directory
```
~/.claude/supercharger/scope/sessions/{session_id}/
```
- Create on first hook call per session
- All session-scoped state moves here: tool-history, repetition-flag, cache files
- **Critical:** prevents cross-session data leakage. Two Claude sessions running concurrently currently share `.tool-history` and overwrite each other
- Migration: on first run, detect old flat files in `scope/`, move to current-session subdir or ignore
- Test: verify session A's `.tool-history` does not appear in session B's reads (parallel test)

### 2.2 Cache layer for tool-history-tracker reads
```
scope/sessions/{session_id}/.tool-history       — append-only log
scope/sessions/{session_id}/.tool-history.cache — 60s TTL cache of last N entries
```
- `tool-history-tracker` PostToolUse: append to log (unchanged)
- `confidence-gate` PreToolUse: read from cache; rebuild on miss/expiry
- Cache only affects reads. Writes always append to log
- Performance: ~1ms read vs ~5ms log parse

### 2.3 Cache layer for detect-stack
```
scope/sessions/{session_id}/.stack — cached stack info keyed by cwd
```
- Single session = single cwd usually. Cache forever per session
- `cwd-changed` invalidates the cache key on directory change
- No TTL needed within a session

### 2.4 Cache layer for config-scan
```
scope/sessions/{session_id}/.config-scan — cached CLAUDE.md scan result
```
- CLAUDE.md scan is stable within a session. Cache for full session
- Invalidate when `file-watcher` reports `.claude/` changes

### 2.5 Add agent-router TTL to existing dedup
- `agent-router.sh:153-161` already has prompt-hash dedup
- Add 30s TTL: store `{hash, result, timestamp}`. Skip re-injection if fresh
- Invalidate on session boundary

### 2.6 Benchmark the cache impact
- Before: measure `confidence-gate` latency on 100 tool calls
- After: same benchmark. Target: ≥50% I/O time reduction
- Log results in `docs/PERF-BENCHMARKS.md`

---

## Phase 3 — Security Hardening (P1, tunable)

**Goal:** Close attack vectors. **Each rule must be opt-out per project to prevent false-positive friction.**

### 3.1 Path traversal in Write/Edit
Add to `code-security-scanner.sh` or new `path-guard.sh`:
```
Patterns to detect:
- .. sequences (normalized)
- URL encoding: %2e, %252e (double encode)
- Null byte: %00, \x00
- Mixed path: /./ /../
- Trailing null byte

Implementation:
1. Decode URL encoding (single + double)
2. Strip null bytes
3. Normalize path (Python os.path.normpath)
4. Resolve symlinks (readlink -f)
5. Check: resolved path under project root?
```
- Opt-out: `{"disableSecurityCategories": ["path-traversal"]}` in `.supercharger.json`

### 3.2 Symlink attack detection
Add to `code-security-scanner.sh` or `scope-guard.sh check`:
```
For Write/Edit:
1. Resolve target: readlink -f {file_path}
2. If resolved path is outside project root → block
3. Edge case: symlink created mid-operation. realpath resolves it
```
- Opt-out: `{"disableSecurityCategories": ["symlink"]}` in `.supercharger.json`

### 3.3 Git hooks modification detection
Add to `code-security-scanner.sh` or new `git-guard.sh`:
```
Block Write/Edit to:
- .git/hooks/
- .githooks/
- $(git rev-parse --git-common-dir)/hooks/
- ~/.claude/hooks/  (supercharger hooks — compromise = disable all security)
- .git/refs/, .git/objects/

Implementation:
1. Get project root: git rev-parse --show-toplevel
2. Get git dir: git rev-parse --git-dir
3. Compare target path prefix
4. Block with clear reason
```
- Opt-out: `{"disableSecurityCategories": ["git-internals"]}` in `.supercharger.json`

### 3.4 Absolute-path writes outside project
Add to `code-security-scanner.sh`:
```
Block Write/Edit to:
- ~/.ssh/
- ~/.aws/
- ~/.config/
- ~/.npmrc, ~/.gitconfig, ~/.bashrc, ~/.zshrc
- /etc/
- /usr/local/etc/

Implementation:
1. Resolve absolute path
2. If absolute AND not under project root → block
```
- Opt-out: `{"disableSecurityCategories": ["abs-path"]}` in `.supercharger.json`

### 3.5 Build artifact injection detection
Add to `code-security-scanner.sh`:
```
Block writes to persistence directories:
- node_modules/.bin/
- __pycache__/
- .next/
- .venv/
- vendor/  (PHP/Go/Ruby — context-dependent)

Implementation:
1. Match file path prefix
2. Block with reason: "dependency trojaning risk"
3. Allow override: developer working in monorepo's node_modules
```
- Opt-out: `{"disableSecurityCategories": ["build-artifacts"]}` in `.supercharger.json` — **likely to be opted out by monorepo users**

### 3.6 Security scan result caching with content hash
When Phase 2 caches reach security-critical paths:
```
Cache key = SHA256(target_file_content), not just file_path
```
- Prevents stale security decisions when content changes within TTL
- Apply to: code-security-scanner, output-secrets-scanner

---

## Phase 4 — Selective UX Wins (cherry-picked from old Phases 5 + 7)

**Goal:** Token noise reduction + better override UX. No SDK rewrite.

### 4.1 Hook output suppression on advisory-only hooks
Add `suppressOutput: true` to:
- `lazy-refactor-check.sh`
- `comment-replacement-check.sh`
- `context-advisor.sh`
- `rate-limit-advisor.sh`
- `cache-health.sh`
- `cost-forecast.sh`
- `tool-call-limiter.sh`

Impact: advisory text no longer enters context, reducing noise. Useful in long sessions.

### 4.2 Per-tool rejection chains (suggest alternatives)
```
hooks/tool-preferences.sh — PreToolUse on Bash
```
Replace blanket deny with suggestion:
- `npm install` → "Use `pnpm install` per `.supercharger.json` toolPreferences"
- `jest <args>` → "Use `vitest <args>` per `.supercharger.json` toolPreferences"
- `pip install` → "Use `uv pip install` per `.supercharger.json` toolPreferences"

Config in `.supercharger.json`:
```json
{
  "toolPreferences": {
    "npm": "pnpm",
    "jest": "vitest",
    "pip": "uv pip"
  }
}
```

User benefit: no more "denied — what do I use instead?" loop.

---

## What's NOT in this plan (and why)

### Dropped from old Phase 4 (Consolidation)
- `notify-hub.sh`, `agent-orchestrator.sh`, `advisor.sh`, `cost-manager.sh`, `session-lifecycle.sh`
- **Reason:** zero user-perceptible benefit. Same hooks fire same way. Only "fewer files in tree" — invisible to users
- **Risk if done anyway:** event-logger `set -e` rewrite, advisor event-routing, multi-handler dispatchers — high regression risk for no user gain

### Dropped from old Phase 5 (Token Economy)
- **`session-context-inject`** — overlaps existing `cwd-changed` + statusline data; 50–100 tokens/prompt savings is pennies/day
- **Prompt cache awareness for standards-inject** — only meaningful at scale; marginal for single-user
- **Adaptive economy threshold tuning** — `adaptive-economy.sh` already exists; this is fine-tuning, not a feature

### Dropped Phase 6 (Observability)
- CI perf benchmarks, cache hit dashboard, hook activation map
- **Reason:** no user-facing impact. Regressions current users don't notice
- Defer until repo size or contributor count justifies CI investment

### Dropped from Phase 7 (SDK)
- **TypeScript SDK** — adds tooling complexity; zero benefit for end users; existing 82 bash hooks unchanged so creates two-track maintenance

---

## Execution Order

```
Week 1: Phase 1 (Quick Wins)         — 1.1 → 1.2 → 1.3 → 1.4 → 1.5
Week 2-3: Phase 2 (Performance)      — 2.1 → 2.2 → 2.3 → 2.4 → 2.5 → 2.6
Week 4-6: Phase 3 (Security, tunable) — 3.1 → 3.2 → 3.3 → 3.4 → 3.5 → 3.6
Week 7: Phase 4 (UX wins)            — 4.1 → 4.2
```

No parallelism between phases. Each phase validates the previous before continuing. Security (3) ships *before* UX (4) so rejection chains build on the new infrastructure.

**Total scope:** ~6 weeks (down from ~8 weeks for original plan).

---

## Anti-Goals

- Removing `confidence-gate.sh`, `reflexion-memory`, `standards-inject`, or any enforcement hook
- Converting enforcement hooks to advisory-only
- Breaking backward compatibility in `.supercharger.json` schema
- Reducing Safe-mode coverage
- Adding telemetry or external data collection
- Adding TypeScript dependency
- File consolidation for its own sake
