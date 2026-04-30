# Stack-Derived Standards Auto-Injection — Design

**Date:** 2026-04-30
**Status:** Spec / pre-implementation
**Owner:** smrafiz

## Goal

Inject stack-specific coding standards (forbidden patterns, toolchain commands, pitfalls) into Claude's session context automatically, scaled by active economy tier, with user override support.

## Motivation

Competitor diff (agent-os 3.0, SuperClaude) showed lean per-project convention injection is the highest-ROI feature claude-supercharger lacks. Current state ships role files (developer/writer/etc.) but nothing stack-aware. Result: Claude generates JS-style React code in a Vue project, suggests `npm` in a `pnpm` project, etc.

## Decisions

| # | Decision | Why |
|---|---|---|
| D1 | Stack-derived (auto via `lib/detect_stack.py`) | Reuses shipped detector; zero user setup |
| D2 | SessionStart hook injection | Predictable, full-session coverage, fits existing CLAUDE.md pattern |
| D3 | Bundled + user override | Defaults ship; `~/.claude/rules/stacks/<name>.md` wins if present (matches role-override pattern) |
| D4 | Content = forbidden + toolchain + pitfalls | Highest signal/token. Skip idiomatic (Claude knows) and structure (project-specific) |
| D5 | v1 stacks: React, Next.js, Python, Go | Top 3 by usage; override path enables community additions |
| D6 | Tier-scaled output (minimal/lean/standard) | Honors token economy; minimal users still get stack tag |

## Architecture

```
SessionStart event
   │
   ▼
hooks/standards-inject.sh
   │
   ├─ run lib/detect_stack.py → list of matched stacks (ordered by signal)
   ├─ for each stack: resolve file (user override > bundled)
   ├─ read SUPERCHARGER_TIER from scope/.economy-tier
   ├─ filter content per tier
   └─ emit injected block to stdout
```

## Components

### `hooks/standards-inject.sh` (new)
- Hook event: `SessionStart`
- Runs once per session
- Reads tier from `scope/.economy-tier`
- Calls `lib/detect_stack.py` (cached result if available)
- Resolves stack files in this order:
  1. `~/.claude/rules/stacks/<stack>.md` (user override)
  2. `<repo>/rules/stacks/<stack>.md` (bundled)
- Concatenates matched stacks, primary first
- Tier-filters output
- Respects `SUPERCHARGER_STANDARDS=0` to disable

### `rules/stacks/<stack>.md` (4 new files for v1)
Structured frontmatter + 3 sections.

```markdown
---
stack: react
detect:
  - package.json:react
  - "**/*.tsx"
priority: high
---

## Forbidden
- Class components in new code
- Direct DOM mutation outside refs
- setState in render path

## Toolchain
- test: vitest
- lint: eslint --fix
- typecheck: tsc --noEmit

## Pitfalls
- useEffect deps: include every referenced state/prop
- key prop: stable id, never array index
- useState lazy init for expensive defaults
```

### `lib/detect_stack.py` (no changes)
Already exists. Returns list of detected stacks with confidence.

## Tier Output Format

### Minimal (~15 tokens)
```
[stack: react+nextjs]
```

### Lean (~150 tokens per stack)
Emits `## Forbidden` + `## Toolchain` sections only.

### Standard (~400 tokens per stack)
Emits full content of all matched stack files, primary first.

## Multi-Stack Handling

Project may match multiple stacks (e.g., React frontend + Python backend in monorepo).

Rule: emit all matched, ordered by `lib/detect_stack.py` signal strength (file count + manifest weight). Primary first. No deduplication of toolchain commands — each stack section retains its own.

## Disable Path

`SUPERCHARGER_STANDARDS=0` env var → hook exits 0 without emitting.

Useful for:
- Users with own injection mechanism
- Debugging token cost attribution
- Per-project disable (set in `.envrc` or shell rc)

## File Layout

```
claude-supercharger/
├── hooks/
│   └── standards-inject.sh           ← new
├── lib/
│   └── detect_stack.py               ← reused, no changes
├── rules/
│   └── stacks/                       ← new dir
│       ├── react.md
│       ├── nextjs.md
│       ├── python.md
│       └── go.md
└── docs/
    └── HOOKS.md                      ← add standards-inject row
```

User override location:
```
~/.claude/rules/stacks/<stack>.md
```

## Configuration

Settings.json registration (added by `lib/hooks.sh`):
```json
{
  "hooks": {
    "SessionStart": [
      { "command": "$SUPERCHARGER_HOME/hooks/standards-inject.sh" }
    ]
  }
}
```

## Performance

- Hook runs once per session (SessionStart, not per-tool)
- `detect_stack.py` already runs ~50ms; cache result for session
- File reads: 1-3 small files (~5KB each)
- Total overhead: <100ms

## Testing

- `tests/test-standards-inject.sh`: Verify
  - Detects react in fixture project, emits react.md content
  - Tier=minimal emits only stack tag
  - Tier=lean emits forbidden + toolchain
  - User override at `~/.claude/rules/stacks/react.md` wins over bundled
  - `SUPERCHARGER_STANDARDS=0` produces empty output
  - Multi-stack project (react + python) emits both, ordered

## Out of Scope (v2 candidates)

- PreToolUse path-matched injection (lazier, but timing-late)
- Runtime convention extraction from existing code
- Stack standards registry / fetch from remote
- LSP-style "live" rule updates as user edits

## Risks

| Risk | Mitigation |
|---|---|
| Token bloat in standard tier | Tier-scaling enforces; cap stack files at 60 lines |
| Stale standards drift from community best practice | Public PRs welcome; maintainer review |
| False stack detection | `detect_stack.py` is conservative; explicit override path exists |
| User has multiple frameworks, only wants one | `SUPERCHARGER_STANDARDS_ONLY=react` env var (v2) |

## Acceptance Criteria

- [ ] 4 stack files exist with curated content (forbidden + toolchain + pitfalls)
- [ ] `hooks/standards-inject.sh` registers as SessionStart hook
- [ ] Tier filtering verified at all 3 tiers
- [ ] User override path verified
- [ ] `SUPERCHARGER_STANDARDS=0` disables cleanly
- [ ] Multi-stack project emits all matched
- [ ] Test suite covers the above
- [ ] `docs/HOOKS.md` regenerated to include new hook
- [ ] Performance: <100ms session-start overhead measured in `tests/test-perf.sh`
