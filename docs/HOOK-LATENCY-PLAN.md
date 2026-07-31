# Hook Latency Budget — Plan

Status: **Phases 1–2 shipped · Phase 3 blocked · Phase 4 open** · Last updated: 2026-07-31

| Phase | State |
|---|---|
| 1 — aggregate harness | **done** — `tests/perf-chain.sh`, `docs/perf-baseline.json` |
| 2 — instrumentation gaps | **done** — 123/123 registered hooks instrumented; `statusline.sh` measured via the harness (see §5) |
| 3 — CI regression gate | **done (report-only)** — `perf` job + `tools/perf-report.sh`; see §6 |
| 4 — act on the data | open — see §7; the first number to act on is in §5 |

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

## 3b. SETTLED — Claude Code runs same-event hooks in PARALLEL (measured 2026-07-29)

The open question behind this whole plan — is the chain **sum** or the **slowest hook** the
number users feel? — is now answered empirically, not from docs.

**Method:** enable full profiling (`.profiling`), fire one Bash tool call, then reconstruct
each hook's `[start, end]` interval from the audit log (`start = ts - elapsed_ms`) and test
for overlap. No hook was modified; this uses the shipped instrumentation.

**Result — unambiguously parallel:**

| Measure | Value |
|---|---|
| Hooks in the chain | 29 |
| Overlapping interval pairs | **152 / 406** |
| Wall-clock span (first start → last end) | 1597 ms |
| Sum of elapsed (what sequential would cost) | 5059 ms |
| **Max concurrency (parallel width)** | **11** |
| Speedup vs serial | **3.2×** |

Eleven hooks started within 54 ms of each other, then a second wave — so parallelism is real
but **bounded** (width ≈ 11), not unlimited.

> Absolute ms above are inflated: profiling forks python twice per hook to timestamp. The
> *structure* — parallel, width ≈ 11 — is the finding; the ms are not a latency claim.

**What this changes:**

- **Felt latency ≈ the span, not the sum.** With ~18 Bash hooks and width ≈ 11, a tool call is
  ~2 waves — so felt cost is closer to `2 × (mean hook)` than to `18 × (mean hook)`.
- **The chain sum is still a real cost — just a different one.** It is fork-pressure: CPU and
  battery, and contention on a loaded machine. Worth tracking, worth not inflating; but it is
  not the number a user perceives as "Claude feels slow."
- **§3's framing needs this qualifier.** "47 fast hooks = 376 ms per tool call" is the
  *sequential* reading. Under width-11 parallelism the perceived figure is several times
  lower. The instrument is still blind to accumulation (the <40 ms threshold finding stands) —
  but what it is blind to is CPU pressure, not primarily wall-clock latency.
- **Phase 3 should gate on the span** (and report the sum as a secondary CPU metric), since the
  span is what regresses user experience.
- **Phase 4 re-prioritises:** shaving one 100 ms hook that runs *concurrently* with ten others
  buys nothing perceptible. The wins are (a) reducing hooks in the widest wave, (b) cutting the
  *slowest* hook in each wave, (c) reducing total forks for CPU/battery.

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

## 5. Phase 2 — Close instrumentation gaps (P1) — **DONE**

1. **`enforce-pkg-manager.sh`** — instrumented (`hooks/enforce-pkg-manager.sh:14`).
2. **The 12 cold-path hooks** — instrumented. Re-counted 2026-07-31 against
   `hooks/hooks.json`: **123 registered hooks, 0 uninstrumented.** The §2 table's "14
   registered but uninstrumented" is historical.
3. **`statusline.sh`** — **measured, not instrumented**, via `perf-chain.sh --target statusline`.

The plan offered a choice for `statusline.sh`: add `lib-timing.sh` to it, or fold it into the
harness. The harness won on three counts. It adds no per-render overhead to the hottest
recurring script in the system — an EXIT-trap write on every render would cost a real share of
what it measures. It avoids changing that script's `/sc off` behaviour: `lib-timing.sh` exits
at *source* time when the kill-switch is set (`:26-28`), and `statusline.sh` already handles
the kill-switch itself, deliberately, at `:19`. And it produces the number without editing a
script whose failure is immediately visible to the user.

**First measured figure (macOS, 10 iterations, 2026-07-31):**

| Render | mean | min | max |
|---|---|---|---|
| cold (cache miss) | **36.2 ms** | 34.0 | 38.0 |
| warm (cache hit) | **6.4 ms** | 6.0 | 8.0 |

**Cache speedup 5.66×.** Both sides are reported because only measuring one gives a number
that is true and useless: cold is what a new session pays, warm is what Claude Code's 300 ms
debounce burst pays, and the gap is the entire value of the v2.23.45 render cache. This also
confirms that file's own comment (`~45ms → ~10ms`) as an estimate — now it is a measurement,
committed to `docs/perf-baseline.json`.

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

### Shipped (2.26.6) — report-only, as planned

`.github/workflows/ci.yml` gains a `perf` job running `tests/perf-chain.sh` for both targets and
piping the JSON into `tools/perf-report.sh`, which writes a markdown table to the job summary.

**The numbers never fail the job. A missing measurement does.** That distinction is the whole
design: report-only means a slow reading is information, not an alarm — but a perf job that
measured nothing and stayed green would be the exact failure this repo keeps finding, an
instrument reporting "fine" because it never ran. So the report exits non-zero on absent,
unparseable, or empty input, and `tests/test-perf-report.sh` (+8) pins both halves, including a
doubled reading that must be *flagged and still exit 0*.

Deltas ≥ 25% are marked ⚠ — **except across platforms**. The baseline is recorded on a dev mac
and CI runs ubuntu; that gap is larger than any regression worth catching, so `perf-chain.sh`
now stamps `platform` into its output and the report labels a cross-platform comparison
"indicative only" rather than decorating it with a warning nobody can act on. A mark that fires
on something unactionable trains people to ignore the mark.

**Next step for this phase** is mitigation (1) — calibrate in-job against a fixed reference
workload and gate on the ratio — once a few weeks of report-only history show the noise floor.

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

- [x] `tests/perf-chain.sh` reports total PreToolUse:Bash chain cost, fast-pathed and not
- [x] `docs/perf-baseline.json` committed — now carries both the chain and statusline sections
- [x] CI surfaces the number on every PR — `perf` job, report-only (§6)
- [x] `enforce-pkg-manager.sh` instrumented; `statusline.sh` measured via the harness (§5)
- [x] The 12 cold-path hooks instrumented — 123/123 registered hooks, 0 gaps
- [ ] README's hook-cost claim replaced with a measured figure (Phase 4)
- [x] Full suite still green

---

## 9. Sequencing

Phase 1 is self-contained and touches no hook — it can land alone and is worth landing alone.
Phase 2 modifies security-adjacent files and should not begin until Phase 1 can prove the
change was neutral. Phase 3 depends on Phase 1's baseline format. Phase 4 depends on all three.

**Recommended first commit:** Phase 1 only.
