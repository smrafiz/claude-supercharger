#!/usr/bin/env bash
# Claude Supercharger — Hook-chain latency harness (HOOK-LATENCY-PLAN Phase 1)
#
# Measures the cost of the WHOLE registered hook chain for one event+tool, not one
# hook — the thing /perf's per-hook, >40ms-threshold instrument is structurally blind
# to (47 fast hooks logging zero rows is the real failure mode, not one slow one).
#
# Selects the hooks.json entries that fire for a given event + tool, runs each (in
# registration order) against a synthetic payload, and reports:
#   - per-hook mean ms
#   - CHAIN SUM  — sequential total = fork-pressure / CPU cost per tool call
#   - SLOWEST    — the single costliest hook = the felt-latency floor IF Claude Code
#                  runs same-event hooks in parallel (it may; measure both, assume
#                  neither).
# Timing uses the bash `time` builtin (fork-free), K iterations, aggregated once.
#
# Usage:
#   bash tests/perf-chain.sh [--event PreToolUse] [--tool Bash] [--cmd "..."]
#                            [--iterations N] [--json] [--write-baseline]
#   bash tests/perf-chain.sh --target statusline [--iterations N] [--json]
#                            [--write-baseline]
#
# --target statusline measures hooks/statusline.sh, which is registered under
# settings.json -> statusLine rather than hooks.json and so is invisible to the
# chain path — on a script that runs on every render. Reports cold (cache miss)
# and warm (cache hit) separately; see the block above the implementation.
# Default: PreToolUse/Bash, two payloads (a fast-pathed `git status` and a
# non-fast-pathed `npm install lodash` — measuring only the former understates the
# chain because safety.sh & friends bail early on trivially-safe commands).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVENT="PreToolUse"; TOOL="Bash"; CMD=""; ITERS=5; JSON=0; WRITE_BASELINE=0
TARGET="chain"
BASELINE_FILE="$REPO/docs/perf-baseline.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --event) EVENT="$2"; shift 2 ;;
    --tool) TOOL="$2"; shift 2 ;;
    --cmd) CMD="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --iterations) ITERS="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --write-baseline) WRITE_BASELINE=1; shift ;;
    -h|--help) sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Ordered list of "<script.sh>|<args>" that fire for EVENT + TOOL.
_hooks_for() {
  EVENT="$EVENT" TOOL="$TOOL" python3 - "$REPO/hooks/hooks.json" <<'PY'
import json, os, re, sys
d = json.load(open(sys.argv[1]))
event = os.environ["EVENT"]; tool = os.environ["TOOL"]
def matches(mt):
    if not mt or mt == "*":
        return True
    return tool in [t.strip() for t in mt.split(",")]
for entry in d.get("hooks", {}).get(event, []):
    if not matches(entry.get("matcher", "")):
        continue
    for h in entry.get("hooks", []):
        cmd = h.get("command", "")
        m = re.search(r'/hooks/([A-Za-z0-9_.-]+\.sh)(.*)$', cmd)
        if m:
            print("%s|%s" % (m.group(1), m.group(2).strip()))
PY
}

# Build the tool payload for a command; write to $1.
# Build the payload for EVENT. v2.26.13: shaped per event, because a hook that
# cannot find the field it reads exits on its first line, and the harness then
# reports the cost of bailing rather than the cost of working. Feeding a Bash tool
# payload to MessageDisplay measures a hook that found no message.
_payload() {
  TOOL="$TOOL" C="$2" REPO="$REPO" EVENT="$EVENT" python3 - "$1" <<'PY'
import json, os, sys
tool, cmd, repo, event = os.environ["TOOL"], os.environ["C"], os.environ["REPO"], os.environ["EVENT"]
base = {"session_id": "perfchain", "cwd": repo, "hook_event_name": event}
prose = ("Here is a representative assistant reply about refactoring the parser "
         "and updating the tests so the suite stays green. ") * 6
extra = {
    "MessageDisplay":      {"message_text": prose},
    "UserPromptSubmit":    {"user_prompt": cmd},
    "UserPromptExpansion": {"command_name": "deploy", "expanded_prompt": prose},
    "CwdChanged":          {"previous_cwd": "/tmp"},
    "Stop":                {"last_assistant_message": prose},
    "SubagentStop":        {"subagent_name": "explorer", "subagent_type": "explorer",
                            "last_assistant_message": prose},
    "SubagentStart":       {"subagent_name": "explorer", "subagent_type": "explorer"},
    "Notification":        {"notification_type": "idle_prompt", "message": "waiting"},
    "PostToolUse":         {"tool_name": tool, "tool_input": {"command": cmd},
                            "tool_response": {"output": "ok"}},
    "PostToolUseFailure":  {"tool_name": tool, "tool_input": {"command": cmd},
                            "error": "boom"},
    "SessionStart":        {"source": "startup"},
    "SessionEnd":          {"end_reason": "other"},
    "PreCompact":          {"compaction_trigger": "auto"},
    "PostCompact":         {"compaction_trigger": "auto"},
}.get(event, {"tool_name": tool, "tool_input": {"command": cmd}})
base.update(extra)
open(sys.argv[1], "w").write(json.dumps(base))
PY
}

# ── statusline target (HOOK-LATENCY-PLAN Phase 2, item 2) ─────────────────────
# statusline.sh is registered under settings.json -> statusLine, NOT in hooks.json,
# so the chain path above cannot see it — and it is uninstrumented, on a script that
# runs on EVERY render. The plan offers two ways to close that: add lib-timing to it,
# or measure it from here. Measuring wins on three counts: it adds no per-render
# overhead to the hottest recurring script in the system, it avoids changing that
# script's `/sc off` behaviour (lib-timing exits at SOURCE time when the kill-switch
# is set — statusline already handles that itself, deliberately, at :19), and an
# EXIT-trap write on every render would cost a meaningful share of what it measures.
#
# Both sides of the v2.23.45 render cache are reported, because only measuring one
# is how you get a number that is true and useless: cold is what a new session pays,
# warm is what a 300ms debounce burst pays, and the gap is the cache's whole value.
if [ "$TARGET" = "statusline" ]; then
  SL="$REPO/hooks/statusline.sh"
  [ -f "$SL" ] || { echo "statusline.sh not found at $SL" >&2; exit 1; }
  TMPD=$(mktemp -d); TF="$TMPD/t"; TIMEFORMAT='%R'
  export SUPERCHARGER_HOME="$REPO"
  export SUPERCHARGER_STATE="$TMPD/state"; mkdir -p "$SUPERCHARGER_STATE/scope"

  _sl_payload() {  # $1=outfile $2=session_id
    SID="$2" REPO="$REPO" python3 -c 'import json,os,sys;open(sys.argv[1],"w").write(json.dumps({"session_id":os.environ["SID"],"cwd":os.environ["REPO"],"workspace":{"current_dir":os.environ["REPO"]},"model":{"display_name":"Opus"}}))' "$1"
  }

  # Warmup: page in bash + python before any timed render.
  _sl_payload "$TMPD/warm" "warmup"; bash "$SL" < "$TMPD/warm" >/dev/null 2>&1 || true

  COLD=""; WARM=""
  i=0
  while [ "$i" -lt "$ITERS" ]; do
    # COLD: a fresh session id every iteration, so the cache key never matches.
    _sl_payload "$TMPD/p" "cold$i$$"
    { time bash "$SL" < "$TMPD/p" >/dev/null 2>/dev/null ; } 2>"$TF"
    COLD="$COLD$(<"$TF") "
    # WARM: prime, then time an immediate repeat with the same id. A render that
    # crosses a wall-clock second boundary misses the cache, so the MEAN can include
    # misses — the min is the true cache-hit floor and both are reported.
    _sl_payload "$TMPD/p" "warmfixed$$"
    bash "$SL" < "$TMPD/p" >/dev/null 2>&1 || true
    { time bash "$SL" < "$TMPD/p" >/dev/null 2>/dev/null ; } 2>"$TF"
    WARM="$WARM$(<"$TF") "
    i=$((i+1))
  done

  COLD="$COLD" WARM="$WARM" ITERS="$ITERS" JSON="$JSON" \
  WRITE_BASELINE="$WRITE_BASELINE" BASELINE_FILE="$BASELINE_FILE" python3 - <<'PY'
import os, json, sys
def stats(s):
    v = [float(x) * 1000.0 for x in s.split() if x]
    return {"mean_ms": round(sum(v) / len(v), 1), "min_ms": round(min(v), 1),
            "max_ms": round(max(v), 1), "samples": len(v)} if v else {}
cold, warm = stats(os.environ["COLD"]), stats(os.environ["WARM"])
report = {"target": "statusline", "iterations": int(os.environ["ITERS"]),
          "platform": os.uname().sysname,
          "cold_render": cold, "warm_render": warm}
if cold and warm and warm["mean_ms"] > 0:
    report["cache_speedup"] = round(cold["mean_ms"] / warm["mean_ms"], 2)
# v2.26.15: min-over-min as well as mean-over-mean. A warm render that crosses a
# wall-clock second boundary MISSES the cache and costs a full cold render, so the
# warm mean legitimately includes misses — on a slow runner one miss in two samples
# halves the apparent speedup. Measured on macOS CI: warm min 15 ms, max 82 ms,
# mean 48.5, mean-speedup 1.46 while the hit path was doing 70 -> 15 ms (4.7x).
# The min is the true cache-hit floor, which is what "does the cache work" means.
if cold and warm and warm["min_ms"] > 0:
    report["cache_speedup_min"] = round(cold["min_ms"] / warm["min_ms"], 2)

if os.environ["JSON"] == "1":
    print(json.dumps(report, indent=2))
else:
    print("Statusline Render Latency   (%d iterations)" % report["iterations"])
    print("  %-14s %8s %8s %8s" % ("", "mean ms", "min ms", "max ms"))
    for k, lab in (("cold_render", "cold (miss)"), ("warm_render", "warm (hit)")):
        d = report[k]
        print("  %-14s %8.1f %8.1f %8.1f" % (lab, d["mean_ms"], d["min_ms"], d["max_ms"]))
    if "cache_speedup" in report:
        print("\ncache speedup = %.2fx" % report["cache_speedup"])
    print("cold = new session / first render of a second: pays bash + python3 startup.")
    print("warm = repeat render inside the same wall-clock second (the 300ms debounce")
    print("       burst Claude Code actually generates) — served by the v2.23.45 cache,")
    print("       builtins only, no fork. A warm MEAN above the min means some renders")
    print("       crossed a second boundary and missed; that is real, not measurement noise.")

if os.environ["WRITE_BASELINE"] == "1":
    # Merge, never overwrite: the chain baseline and this one live in one file and
    # are written by separate invocations. A plain write would silently drop the other.
    path = os.environ["BASELINE_FILE"]
    try:
        existing = json.load(open(path))
    except Exception:
        existing = {}
    existing["statusline"] = report
    existing["_note"] = "Regenerate deliberately: bash tests/perf-chain.sh [--target statusline] --write-baseline"
    open(path, "w").write(json.dumps(existing, indent=2) + "\n")
    print("\nwrote statusline baseline -> %s" % path, file=sys.stderr)
PY
  rm -rf "$TMPD"
  exit 0
fi

# ── all-events sweep (v2.26.13) ───────────────────────────────────────────────
# The instrument built to catch accumulation only ever looked at PreToolUse/Bash
# and the statusline, so a 27.7 ms BLOCKING hook on every assistant message was
# invisible to it for four releases (2.26.8 -> 2.26.12) and surfaced only because
# someone asked. Measuring one hot path is how you miss the next one.
#
# This sweeps every event registered in hooks.json and ranks them worst-first, so
# a new recurring cost has to be looked at rather than found.
if [ "$TARGET" = "all" ]; then
  EVENTS=$(python3 -c "
import json,sys
print('\n'.join(sorted(json.load(open('$REPO/hooks/hooks.json'))['hooks'])))")
  echo "Hook cost by event — every registered event, worst BLOCKING first  (${ITERS} iters each)"
  echo ""
  printf '  %-22s %6s %11s %9s  %s\n' "event" "hooks" "blocking ms" "sum ms" "slowest blocking hook"
  for ev in $EVENTS; do
    line=$(EVENT="$ev" bash "${BASH_SOURCE[0]}" --event "$ev" --iterations "$ITERS" --json 2>/dev/null \
      | EV="$ev" REPO="$REPO" python3 -c "
import json,os,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
# Rank on BLOCKING cost, not the sum. An async hook stalls nobody, and ranking by
# sum sends the reader optimising something no user waits for — the exact error
# HOOK-LATENCY-PLAN Phase 4 warned about. The sum stays visible as the CPU story.
reg = json.load(open(os.path.join(os.environ['REPO'], 'hooks', 'hooks.json')))
blocking = set()
for e in reg['hooks'].get(os.environ['EV'], []):
    for h in e.get('hooks', []):
        if not (h.get('async') or h.get('asyncRewake')):
            n = h['command'].split('/hooks/')[-1].split()[0]
            blocking.add(n)
p = d['payloads'].get('non-fast-pathed') or list(d['payloads'].values())[0]
per = p['per_hook_ms']
bsum = sum(v for k, v in per.items() if k in blocking)
bslow = max(((k, v) for k, v in per.items() if k in blocking), key=lambda kv: kv[1], default=('-', 0.0))
print('%09.3f|  %-22s %6d %11.1f %9.1f  %s @ %.1f ms' % (
    bsum, d['event'], d['hooks'], bsum, p['chain_sum_ms'], bslow[0], bslow[1]))" 2>/dev/null)
    [ -n "$line" ] && printf '%s\n' "$line"
  done | sort -rn | cut -d'|' -f2-
  echo ""
  echo "blocking ms = the hooks the user actually waits behind. This is the ranking column."
  echo "sum ms      = every hook including async ones: CPU / fork pressure, not felt latency."
  echo "Weigh both against FREQUENCY: per-tool-call and per-message events matter far more"
  echo "than once-per-session ones at the same cost."
  exit 0
fi

HOOK_LINES=$(_hooks_for)
[ -z "$HOOK_LINES" ] && { echo "No hooks fire for $EVENT/$TOOL" >&2; exit 1; }
NHOOKS=$(printf '%s\n' "$HOOK_LINES" | grep -c .)

export SUPERCHARGER_HOME="$REPO"
TMPD=$(mktemp -d); TF="$TMPD/t"; DATA="$TMPD/data"; : > "$DATA"
TIMEFORMAT='%R'

# Which commands to run.
if [ -n "$CMD" ]; then CMDS=("$CMD"); LABELS=("custom");
else CMDS=("git status" "npm install lodash"); LABELS=("fast-pathed" "non-fast-pathed"); fi

run_chain() {  # $1=cmd  $2=label -> appends "label<TAB>hook<TAB>seconds" per hook per iter
  local cmd="$1" label="$2" pay="$TMPD/pay" line script args i
  _payload "$pay" "$cmd"
  i=0
  while [ "$i" -lt "$ITERS" ]; do
    # One state dir per iteration (created OUTSIDE the timed region, shared across the
    # chain like a real session) — keeps the mktemp fork out of the measurement.
    local st; st=$(mktemp -d); export SUPERCHARGER_STATE="$st"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      script="${line%%|*}"; args="${line#*|}"; [ "$args" = "$line" ] && args=""
      # shellcheck disable=SC2086
      { time bash "$REPO/hooks/$script" $args < "$pay" >/dev/null 2>/dev/null ; } 2>"$TF"
      printf '%s\t%s\t%s\n' "$label" "$script" "$(<"$TF")" >> "$DATA"
    done <<EOF
$HOOK_LINES
EOF
    rm -rf "$st"
    i=$((i+1))
  done
}

# Warmup (page in interpreters) then measure.
for idx in "${!CMDS[@]}"; do
  _payload "$TMPD/warm" "${CMDS[$idx]}"
  while IFS= read -r line; do s="${line%%|*}"; a="${line#*|}"; [ "$a" = "$line" ] && a=""
    # shellcheck disable=SC2086
    SUPERCHARGER_STATE="$(mktemp -d)" bash "$REPO/hooks/$s" $a < "$TMPD/warm" >/dev/null 2>&1 || true
  done <<EOF
$HOOK_LINES
EOF
  run_chain "${CMDS[$idx]}" "${LABELS[$idx]}"
done

# ── Spawn floor (HOOK-LATENCY-PLAN Phase 4) ───────────────────────────────────
# The cost of starting bash and exiting, doing nothing. Without it, "chain sum
# 70 ms across 17 hooks" reads as 70 ms of hook work that someone could optimise
# away — and most of it is not. Measured here rather than assumed, on the same
# machine and in the same run, because it is hardware- and shell-dependent.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMPD/floor.sh"
bash "$TMPD/floor.sh" < /dev/null >/dev/null 2>&1   # warm
FLOOR_TOTAL=0; fi_=0
while [ "$fi_" -lt 15 ]; do
  { time bash "$TMPD/floor.sh" < /dev/null >/dev/null 2>/dev/null ; } 2>"$TF"
  FLOOR_TOTAL="$FLOOR_TOTAL $(<"$TF")"
  fi_=$((fi_+1))
done

# Aggregate once.
NHOOKS="$NHOOKS" ITERS="$ITERS" EVENT="$EVENT" TOOL="$TOOL" JSON="$JSON" \
FLOOR_TOTAL="$FLOOR_TOTAL" \
WRITE_BASELINE="$WRITE_BASELINE" BASELINE_FILE="$BASELINE_FILE" \
python3 - "$DATA" <<'PY'
import os, sys, json, collections
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
iters = int(os.environ["ITERS"]); nh = int(os.environ["NHOOKS"])
labels = []
by = collections.defaultdict(lambda: collections.defaultdict(float))  # label -> hook -> total_s
for label, hook, sec in rows:
    if label not in labels: labels.append(label)
    try: by[label][hook] += float(sec)
    except ValueError: pass

# Stamped because these numbers are only comparable within a platform: a baseline
# written on a dev mac and a reading taken on an ubuntu runner differ by more than
# any regression would, and a delta computed across the two means nothing.
report = {"event": os.environ["EVENT"], "tool": os.environ["TOOL"],
          "hooks": nh, "iterations": iters, "platform": os.uname().sysname,
          "payloads": {}}

# Median, not mean: process spawn is occasionally interrupted by scheduling and a
# single outlier would overstate the floor, which is the one number here that must
# not be flattering.
_floor = sorted(float(x) * 1000.0 for x in os.environ.get("FLOOR_TOTAL", "").split() if x)
floor_ms = _floor[len(_floor) // 2] if _floor else 0.0
report["spawn_floor_ms"] = round(floor_ms, 2)
for label in labels:
    means = {h: (t / iters) * 1000.0 for h, t in by[label].items()}
    ranked = sorted(means.items(), key=lambda kv: kv[1], reverse=True)
    chain_sum = sum(means.values())
    slowest = ranked[0] if ranked else ("-", 0.0)
    # Claude Code runs same-event hooks CONCURRENTLY, measured width ~11 (see
    # docs/HOOK-LATENCY-PLAN.md §3b). Model the felt cost as list-scheduling over
    # WIDTH workers: assign each hook (longest first) to the earliest-free worker;
    # the makespan is the estimate. Falls back to the true lower bound (the slowest
    # single hook) when the chain fits in one wave.
    width = int(os.environ.get("SUPERCHARGER_HOOK_CONCURRENCY", "11"))
    workers = [0.0] * max(1, width)
    for _, v in ranked:                     # already longest-first
        i = workers.index(min(workers))
        workers[i] += v
    makespan = max(workers) if workers else 0.0
    # Split the sequential total into the part that is process creation and the part
    # that is the hooks doing something. Only the second is optimisable: a hook that
    # exits on its first line still costs a spawn.
    spawn_ms = floor_ms * nh
    report["payloads"][label] = {
        "chain_sum_ms": round(chain_sum, 1),
        "spawn_ms": round(spawn_ms, 1),
        "work_ms": round(max(0.0, chain_sum - spawn_ms), 1),
        "spawn_share": round(spawn_ms / chain_sum, 2) if chain_sum else 0.0,
        "parallel_est_ms": round(makespan, 1),
        "parallel_width": width,
        "slowest_hook": slowest[0], "slowest_ms": round(slowest[1], 1),
        "per_hook_ms": {h: round(v, 1) for h, v in ranked},
    }

if os.environ["JSON"] == "1":
    print(json.dumps(report, indent=2));
else:
    print("Hook-Chain Latency — %s / %s   (%d hooks, %d iters/payload)" % (
        report["event"], report["tool"], nh, iters))
    for label in labels:
        p = report["payloads"][label]
        print("\n[%s]  FELT ~%.1f ms  (parallel, width %d)   |   chain sum %.1f ms (CPU/fork)   slowest %s @ %.1f ms" % (
            label, p["parallel_est_ms"], p["parallel_width"],
            p["chain_sum_ms"], p["slowest_hook"], p["slowest_ms"]))
        print("  of that chain sum: %.1f ms is process spawn (%d x %.2f ms, irreducible), %.1f ms is hook work" % (
            p["spawn_ms"], nh, report["spawn_floor_ms"], p["work_ms"]))
        print("  %-32s %8s" % ("hook", "mean ms"))
        for h, v in list(p["per_hook_ms"].items())[:8]:
            print("  %-32s %8.1f" % (h, v))
        rest = len(p["per_hook_ms"]) - 8
        if rest > 0: print("  … %d more" % rest)
    print("\nFELT      = list-scheduling estimate over %s concurrent workers — Claude Code runs" % (
        os.environ.get("SUPERCHARGER_HOOK_CONCURRENCY", "11")))
    print("            same-event hooks in PARALLEL (measured; plan §3b). This is the number")
    print("            a user perceives. Override the width with SUPERCHARGER_HOOK_CONCURRENCY.")
    print("chain sum = sequential total: CPU / fork pressure per tool call (battery, load), not felt latency.")
    print("slowest   = hard lower bound — no amount of parallelism beats the single slowest hook.")
    print("spawn     = %.2f ms x %d hooks. Starting bash and exiting costs this much before a hook" % (
        report["spawn_floor_ms"], nh))
    print("            runs a single line, so it is the floor for hook COUNT, not hook content.")
    print("            Optimising a hook can only ever recover the `hook work` figure.")

if os.environ["WRITE_BASELINE"] == "1":
    # Preserve the statusline section, the way the statusline branch preserves this
    # one. 2.26.5 added merging on that side only, so regenerating the chain baseline
    # silently deleted the statusline numbers — caught by the test written in the same
    # release for exactly this, which is the whole reason it exists.
    path = os.environ["BASELINE_FILE"]
    try:
        keep = json.load(open(path)).get("statusline")
    except Exception:
        keep = None
    if keep is not None:
        report["statusline"] = keep
    report["_note"] = "Regenerate deliberately: bash tests/perf-chain.sh [--target statusline] --write-baseline"
    open(path, "w").write(json.dumps(report, indent=2) + "\n")
    print("\nwrote baseline -> %s" % path, file=sys.stderr)
PY

rm -rf "$TMPD"
