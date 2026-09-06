#!/usr/bin/env bash
# Claude Supercharger — shared stdin read for guards (v4.0.28)
#
# Every hook read its payload with this line:
#
#   IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""
#
# `read` returns >128 ONLY on the -t timeout, so the distinction between "the
# payload arrived" and "the payload did not arrive" was available and thrown
# away: on timeout the variable was blanked, every guard hit its fast path,
# exited 0 — and the tool ran anyway, unchecked and unmentioned. Measured
# against the deployed artifact guard, same payload both times:
#
#   writer faster than the timeout   rc=2   deny
#   writer slower than the timeout   rc=0   no stdout, no stderr
#
# That is [[failure-modes-collapse-to-one-verdict]]: the error path and the
# all-clear path shared an exit. Unlike the EACCES case in v4.0.26, this one is
# not self-limiting — a stalled read does not stop the tool, it only stops the
# check.
#
# For a GUARD the honest answer to "I could not read the call" is ASK, not
# silence. `sc_read_input` emits that itself and exits, so a call site is one
# line and cannot forget the failure branch. Recorders and formatters keep the
# inline read: blocking a log write on a slow pipe helps nobody.
#
# Sourced BEFORE the read, which is otherwise the first thing a hook does. That
# ordering is a fast-path decision, and this keeps it cheap: a source of a small
# file is a read, not a fork ([[perf-fork-budget]] — the fork prices are what
# matter, python3 at 20.6ms).

# sc_read_input VARNAME — read the hook payload into VARNAME.
# On the -t timeout: emit a PreToolUse ask and exit 0. Never returns blank
# because the read timed out.
sc_read_input() {
  local _sc_var="$1" _sc_val="" _sc_rc=0
  local _sc_to="${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _sc_t0=$SECONDS
  IFS= read -r -d '' -t "$_sc_to" _sc_val || _sc_rc=$?
  # DO NOT key this on `$? > 128`. That is bash 4+ behaviour; bash 3.2 — which
  # is /bin/bash on every macOS — returns 1 on a -t timeout, indistinguishable
  # from a clean EOF by exit code alone. Measured: 3.2.57 gives rc=1 len=0 after
  # burning the full timeout, and it DISCARDS the bytes it had already read.
  # That is why the old `[ $? -le 128 ] || _INPUT=""` line never fired and the
  # blanking happened anyway. [[two-gate-trap]] — the rule was there and
  # unreachable.
  #
  # Elapsed time is the discriminator that works on both: an empty read that
  # returned instantly is genuinely empty stdin (a test, a manual run) and stays
  # silent as before; an empty or partial read that consumed the whole timeout
  # is a payload that did not arrive.
  if [ $((SECONDS - _sc_t0)) -ge "$_sc_to" ] || [ "$_sc_rc" -gt 128 ]; then
    # No jq, no python: this path exists because the process is already starved,
    # and the reason is a fixed string with nothing to escape.
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Supercharger could not read this tool call within %ss, so it has NOT been checked for anything — secrets, destructive commands, protected paths. Approve only if you already know this call is safe."}}\n' \
      "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}"
    echo "[Supercharger] stdin read timed out after ${SUPERCHARGER_STDIN_TIMEOUT_S:-5}s — call NOT checked" >&2
    exit 0
  fi
  # Strip trailing newlines, as every inline copy did.
  _sc_val="${_sc_val%"${_sc_val##*[!$'\n']}"}"
  printf -v "$_sc_var" '%s' "$_sc_val"
}
