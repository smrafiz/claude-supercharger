# Hook Latency Budget — Plan

Status: **proposed** · Target: **a 2.x minor** · Last updated: 2026-07-28

Supercharger registers **121 hook entries**, 47 of them on `PreToolUse`. Every agent tool
call pays that chain. Today there is per-hook timing but **no measurement of the sum**, and
the default instrumentation is structurally unable to see it. This plan closes that.

---

## 1. Goal & scope

**Goal:** know what the hook chain costs per tool call, catch regressions in CI, and give
users a defensible number instead of a README estimate.

**Explicitly out of scope:**

- **Optimizing individual hooks.** This plan builds the instrument, not the fix. Optimizing
  before the baseline exists is how you end up tuning the wrong hook.
- **Reducing the hook count.** A separate question, and one that should be answered with
  data this plan produces.
- **Rewriting `lib-timing.sh`.** Its per-hook design is sound. The gap is aggregation.

---

## 2. Measured baseline

Counted 2026-07-28 against `hooks/hooks.json` and `hooks/*.sh`.

| Metric | Value |
|---|---|
| Registered hook entries | 121 |
| `PreToolUse` entries (the hot path) | 47 |
| Non-lib hook scripts | 125 |
| Instrumented via `lib-suppress.sh` | 94 |
| Instrumented via `lib-timing.sh` | 13 |
| **Instrumented total** | **107 / 125 (86%)** |
| Registered but uninstrumented | 14 |
| Not registered (helper / sourced / statusline) | 4 |

Per-hook instrumentation coverage is **already good**. `lib-suppress.sh` provides the same
EXIT-trap timing as `lib-timing.sh` (see `hooks/lib-timing.sh:3,34`), so any audit that greps
only for `lib-timing` undercounts by ~7×.

Of the 14 registered-but-uninstrumented hooks, only **one sits on the hot path**:

| Hook | Event | Matcher | Priority |
|---|---|---|---|
| `enforce-pkg-manager.sh` | `PreToolUse` | `Bash` | **P0** — fires on every Bash call |
| `agent-gate.sh` | `PreToolUse` | `Agent` | P2 — subagent spawn only |
| `learn-from-prompts.sh` | `UserPromptSubmit` | `*` | P2 — once per turn |
| `notify-permission.sh` | `PermissionRequest` | `*` | P3 |
| `stop-verify.sh`, `session-complete.sh`, `session-memory-write.sh`, `notify-stop.sh` | `Stop` | `*` | P2 — once per turn, but four of them |
| `plugin-config-seed.sh`, `update-check.sh` | `SessionStart` | `*` | P3 — once per session |
| `event-logger.sh` | 8 cold events | `*` | P3 |
| `compaction-backup.sh`, `session-end.sh`, `stop-failure.sh` | cold | `*` | P3 |

`statusline.sh` (562 lines) is registered under `statusLine` in `settings.json`, not in
`hooks.json`, and is uninstrumented. It runs on **every render**, which likely makes it the
single largest recurring cost in the system. It needs its own measurement path.

---

## 3. Key finding — the threshold makes the real problem invisible

`hooks/lib-timing.sh:65`:

```bash
if [ "${_HOOK_PERF_FULL:-0}" != 1 ] && [ "$elapsed" -lt "${SUPERCHARGER_PERF_THRESHOLD_MS:-40}" ]; then
  return
fi
```

Outside full-profiling mode, a hook that takes under 40ms **records nothing**.

That is exactly backwards for this architecture. The failure mode here is not one slow hook —
it is 47 fast ones. Forty-seven hooks at 8ms each cost **376ms per tool call** and log
**zero rows**. `/perf` reports "no timing data found" and everything looks fine.

The always-on path is built to catch an outlier. The actual risk is accumulation. Full
profiling (`.profiling` sentinel) does capture every fire, but it is opt-in, undiscoverable,
and nobody turns it on before they already suspect a problem.

**This is the finding the rest of the plan is built around.** The instrument needs to measure
the chain, not the hook.

---

## 4. Phase 1 — Aggregate measurement harness (P0)

Ship `tests/perf-chain.sh`: run the full registered chain for one event against a synthetic
payload and report total wall time.

**Design**

- Read `hooks/hooks.json`, select entries for a given event + matcher (default `PreToolUse` / `Bash`).
- Build a representative payload (a benign `git status`, plus a second run with a
  non-fast-pathed command like `npm install lodash` — `safety.sh:41` fast-paths the former,
  so measuring only that understates the chain badly).
- Execute each hook in registration order, capture per-hook and total ms.
- Emit both a human table and `--json` for machine consumption.

**Deliverables**

- `tests/perf-chain.sh`
- `docs/perf-baseline.json` — committed baseline, regenerated deliberately via `--write-baseline`
- `/perf --chain` surfaces it to users

**Acceptance:** running it prints a total-ms figure for the PreToolUse:Bash chain on both a
fast-pathed and a non-fast-pathed command. That number does not exist today.

---

## 5. Phase 2 — Close instrumentation gaps (P1)

Ordered by hot-path impact, not by count.

1. **`enforce-pkg-manager.sh`** — add `. lib-timing.sh`. One line, the only hot-path gap.
2. **`statusline.sh`** — needs a different mechanism (not a `hooks.json` entry). Either a
   dedicated timing write on render, or fold it into Phase 1's harness as a separate target.
   Given it runs per render, treat this as equal priority to the hot-path hook.
3. **The remaining 12 cold-path hooks** — mechanical, low risk, do them in one batch. Each is
   a single sourced line at the top; `lib-timing.sh` already no-ops when an EXIT trap exists
   (`:35`), so it is safe to add blindly.

**Risk note:** `lib-timing.sh` exits at source time when `/sc off` is set (`:26-28`). Adding it
to a hook changes that hook's kill-switch behavior. For the 12 cold-path hooks, confirm each
should honor `/sc off` before adding — most should, but this is a behavior change, not
pure instrumentation. **Do not batch this without checking.**

---

## 6. Phase 3 — CI regression gate (P1)

Add a `perf` job to `.github/workflows/ci.yml` running `tests/perf-chain.sh` against the
committed baseline.

**The hard part is flakiness.** GitHub runners vary enough that an absolute ms ceiling will
produce false failures and get muted within a month — which is worse than no gate.

Mitigation, in order of preference:

1. **Calibrate in-job.** Run a fixed reference workload, express hook cost as a ratio to it,
   and gate on the ratio. Survives runner variance.
2. **Generous ceiling.** Gate at ~2× baseline. Catches "someone added a `curl` to a
   PreToolUse hook", misses 15% creep. Acceptable as a first cut.
3. **Report-only.** Post the number as a PR comment, no failure. Weakest, but zero flake and
   still creates the feedback loop.

Start at (3), move to (1) once there is enough data to know the noise floor. Do **not** start
at (2) — a gate that cries wolf gets deleted.

---

## 7. Phase 4 — Act on the data (P2)

Only after Phases 1–3. Options, to be chosen by what the baseline shows:

- Re-tune `SUPERCHARGER_PERF_THRESHOLD_MS` default, or make the always-on path record a
  per-tool-call *sum* rather than per-hook outliers.
- Extend the `safety.sh:41` fast-path pattern to other hot-path hooks, if the chain shows
  they do redundant work on trivially-safe commands.
- Revisit what `profile: fast` and `profile: minimal` skip, based on measured cost rather
  than assumed cost.
- Publish a real number in the README, replacing the current `/perf` pointer.

---

## 8. Success criteria

- [ ] `tests/perf-chain.sh` reports total PreToolUse:Bash chain cost, fast-pathed and not
- [ ] `docs/perf-baseline.json` committed
- [ ] CI surfaces the number on every PR
- [ ] `enforce-pkg-manager.sh` and `statusline.sh` instrumented
- [ ] The 12 cold-path hooks instrumented, each `/sc off` behavior change reviewed
- [ ] README's hook-cost claim replaced with a measured figure
- [ ] Full suite still green (baseline: **2374 passed, 0 failed**)

---

## 9. Sequencing

Phase 1 is self-contained and touches no hook — it can land alone and is worth landing alone.
Phase 2 modifies security-adjacent files and should not begin until Phase 1 can prove the
change was neutral. Phase 3 depends on Phase 1's baseline format. Phase 4 depends on all three.

**Recommended first commit:** Phase 1 only.
