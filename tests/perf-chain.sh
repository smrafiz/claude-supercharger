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
# Default: PreToolUse/Bash, two payloads (a fast-pathed `git status` and a
# non-fast-pathed `npm install lodash` — measuring only the former understates the
# chain because safety.sh & friends bail early on trivially-safe commands).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVENT="PreToolUse"; TOOL="Bash"; CMD=""; ITERS=5; JSON=0; WRITE_BASELINE=0
BASELINE_FILE="$REPO/docs/perf-baseline.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --event) EVENT="$2"; shift 2 ;;
    --tool) TOOL="$2"; shift 2 ;;
    --cmd) CMD="$2"; shift 2 ;;
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
_payload() {
  TOOL="$TOOL" C="$2" REPO="$REPO" python3 -c 'import json,os,sys;open(sys.argv[1],"w").write(json.dumps({"session_id":"perfchain","tool_name":os.environ["TOOL"],"tool_input":{"command":os.environ["C"]},"cwd":os.environ["REPO"]}))' "$1"
}

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

# Aggregate once.
NHOOKS="$NHOOKS" ITERS="$ITERS" EVENT="$EVENT" TOOL="$TOOL" JSON="$JSON" \
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

report = {"event": os.environ["EVENT"], "tool": os.environ["TOOL"],
          "hooks": nh, "iterations": iters, "payloads": {}}
for label in labels:
    means = {h: (t / iters) * 1000.0 for h, t in by[label].items()}
    ranked = sorted(means.items(), key=lambda kv: kv[1], reverse=True)
    chain_sum = sum(means.values())
    slowest = ranked[0] if ranked else ("-", 0.0)
    report["payloads"][label] = {
        "chain_sum_ms": round(chain_sum, 1),
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
        print("\n[%s]  chain sum = %.1f ms  (fork-pressure/CPU)   slowest = %s @ %.1f ms  (parallel floor)" % (
            label, p["chain_sum_ms"], p["slowest_hook"], p["slowest_ms"]))
        print("  %-32s %8s" % ("hook", "mean ms"))
        for h, v in list(p["per_hook_ms"].items())[:8]:
            print("  %-32s %8.1f" % (h, v))
        rest = len(p["per_hook_ms"]) - 8
        if rest > 0: print("  … %d more" % rest)
    print("\nchain sum = sequential total (CPU/fork pressure per tool call).")
    print("slowest   = felt wall-clock floor IF Claude Code runs these in parallel.")

if os.environ["WRITE_BASELINE"] == "1":
    import datetime  # noqa (date is fine here, not in a workflow script)
    report["_note"] = "Regenerate deliberately: bash tests/perf-chain.sh --write-baseline"
    open(os.environ["BASELINE_FILE"], "w").write(json.dumps(report, indent=2) + "\n")
    print("\nwrote baseline -> %s" % os.environ["BASELINE_FILE"], file=sys.stderr)
PY

rm -rf "$TMPD"
