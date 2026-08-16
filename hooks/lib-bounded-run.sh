#!/usr/bin/env bash
# Claude Supercharger — bounded command execution
#
# `timeout` is a GNU coreutils binary. macOS does not ship it, and neither does
# Git Bash; `gtimeout` only exists if the user installed coreutils by hand. So
# every hook that "wrapped" a subprocess in $TIMEOUT_CMD resolved that variable
# to the EMPTY STRING on a stock Mac and ran the command with no bound at all —
# a wrapper that reads as protection in the source and is absent at runtime on
# the primary development platform. typecheck (tsc) and quality-gate (eslint,
# prettier, ruff, golangci-lint) both did this, and both run project-owned
# toolchains that can hang on a bad config or a watch flag.
#
#   sc_bounded_run <seconds> <command> [args...]
#
# Returns the command's own exit status, or 124 (the convention `timeout` uses)
# when the bound fired. stdout and stderr pass straight through, so this is a
# drop-in prefix at a call site that captures output.
#
# Implementation notes:
#   * A real `timeout`/`gtimeout` is used when present — it kills more reliably
#     (process group, TERM then KILL) than anything shell-level.
#   * The fallback does NOT poll. A `while kill -0; do sleep 1; done` loop costs
#     every call up to a full second even when the command returns instantly,
#     and quality-gate makes several calls per edit. Backgrounding a killer and
#     `wait`ing on the command returns the moment the command does.
#   * Timeout is detected from the killer still being alive, not from the exit
#     status: a command killed by an unrelated signal also exits >128, and
#     reporting that as a timeout would send a hook chasing the wrong cause.

# Guard against double-sourcing (hooks source several libs, some transitively).
if [ -z "${_SC_BOUNDED_RUN_LOADED:-}" ]; then
_SC_BOUNDED_RUN_LOADED=1

sc_bounded_run() {
  local _secs="$1"; shift
  [ "$#" -eq 0 ] && return 0

  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$_secs" "$@"
    return $?
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout "$_secs" "$@"
    return $?
  fi

  # Job control gives the background job its own process GROUP, which is what
  # makes the kill effective. Killing the direct child alone is not enough and
  # measured as not enough: a shim that execs the real linter, or any wrapper
  # that spawns a worker, leaves a grandchild holding the write end of the
  # capture pipe — so `issues=$(sc_bounded_run 2 eslint …)` sat for the full 20s
  # of the grandchild even though the child had been signalled. Negating the pid
  # signals the group.
  # The killer STAMPS A MARKER before it signals, and the marker — not the
  # killer's liveness — is what says a timeout happened.
  #
  # The first version inferred it from `kill -0 $_kpid`: killer still alive =>
  # still sleeping => the command must have finished on its own. That is a race,
  # and a loaded CI runner lost it: the killer had already fired and had not yet
  # exited, so an overrun was reported as the command's own status (rc=143,
  # SIGTERM) instead of 124. It passed on an idle laptop every time.
  #
  # Stamping BEFORE the signal makes the marker's presence a fact rather than a
  # guess: if the command died from our TERM, the file was written first.
  # A temp DIRECTORY, so the marker path does not exist until the killer writes
  # it — `mktemp` alone creates its file, which would make the marker true from
  # the start and report every run as a timeout.
  local _mdir="" _mark=""
  _mdir=$(mktemp -d 2>/dev/null) || _mdir=""
  [ -n "$_mdir" ] && _mark="$_mdir/fired"

  set -m 2>/dev/null || true
  "$@" &
  local _cpid=$!
  set +m 2>/dev/null || true
  ( sleep "$_secs"
    [ -n "$_mark" ] && : > "$_mark" 2>/dev/null
    kill -TERM -"$_cpid" 2>/dev/null || kill -TERM "$_cpid" 2>/dev/null ) &
  local _kpid=$!

  local _rc=0
  wait "$_cpid" 2>/dev/null || _rc=$?

  kill "$_kpid" 2>/dev/null || true
  wait "$_kpid" 2>/dev/null || true

  local _fired=1
  if [ -n "$_mark" ] && [ -e "$_mark" ]; then
    _fired=0
  fi
  [ -n "$_mdir" ] && rm -rf "$_mdir" 2>/dev/null

  # Timeout only when the killer stamped AND the command died from a signal.
  # Without mktemp there is no marker, so fall back to the command's own status
  # rather than claiming a timeout that cannot be evidenced.
  if [ "$_fired" -eq 0 ] && [ "$_rc" -gt 128 ]; then
    return 124
  fi
  return "$_rc"
}

fi
