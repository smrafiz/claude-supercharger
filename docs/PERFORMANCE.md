# Performance: what the hooks cost

[Back to README](../README.md)

## Measured cost per tool call

Claude Code runs same-event hooks concurrently (observed about 11 at a time), so the cost you feel on a tool call is the slowest wave of hooks, not the sum of all of them.

Measured with `bash tests/perf-chain.sh` on the PreToolUse chain for a Bash call (19 hooks):

| machine | felt / tool call | chain sum (CPU) | statusline (cold / warm) |
|---|---:|---:|---:|
| M4 Pro, bash 3.2 | 6.8 ms | 66.8 ms | 45.0 / 6.8 ms |
| GitHub ubuntu runner | 10.0 ms | 98.4 ms | 74.8 / 3.0 ms |

Those rows are for a command that takes the fast path. When `safety.sh` has to run its full scan, the M4 Pro baseline is 23.4 ms felt and 86.6 ms chain sum. The committed baseline is [perf-baseline.json](perf-baseline.json); the CI figures come from the 2026-09-07 measurement in [HANDOFF-2026-09-07.md](HANDOFF-2026-09-07.md).

More than half of the chain sum is process start-up. Starting and exiting bash costs 2.00 ms on the M4 Pro, so 19 hooks spend 38 ms creating processes before any of them runs a line: 57% of the 66.8 ms. The per-hook spread is flat (2.4 to 6.8 ms, no outlier), and the cheapest guard is already at that floor. Optimising individual hooks can only reduce the rest.

## Measure it on your machine

From a clone, `bash tests/perf-chain.sh` reports the felt estimate, the sequential sum split into process start-up and hook work, and the slowest single hook. `--target statusline` measures the status bar separately. CI runs both on every push and posts the table to the job summary.

`/sc-perf` (or `/sc-perf --slow`) shows the timing of hooks as they fired in your real sessions. On bash 3.2, the macOS default, its `avg_ms` column is inflated, sometimes 10 to 60 times, because the profiler forks `python` on each hook run to read the clock and that fork lands inside the measurement. `/sc-perf` prints a warning about this. Rank by its Calls column and measure a specific hook on its own before optimising it. On bash 5 and later the clock needs no fork and the numbers are accurate.

## Where slowness usually comes from

Most felt slowness is not the hooks. In rough order of impact:

- Permission prompts. `/sc-autopilot 2h` stops the yes/no prompts for a while; safety hooks still run. Waiting on a prompt costs far more than hook overhead.
- Long commands in the foreground. Run `tsc`, builds, tests and dev servers in the background so they do not block the turn.
- Analytics hooks. `/sc-profile fast` skips 7 of them; `/sc-profile minimal` skips 10 and keeps security only. See [CONFIGURATION.md](CONFIGURATION.md#performance-profiles).
- Type-checking on large projects. A `.supercharger-no-typecheck` file in a repo root skips it for that repo; it is the one real per-edit cost on big projects.
- Long thinking on a simple request. That is Claude's own reasoning effort, not Supercharger. Use `/effort low` or `/effort medium`.

## Tokens

- `/compact` when context is high; `/clear` when switching to unrelated work.
- `/sc-memory-prune` archives resolved memory entries so they stop loading every session.
- Supercharger's own footprint is small: rule files are path-scoped and per-prompt injections are a few tokens. The main token cost is conversation length, not the hooks.
