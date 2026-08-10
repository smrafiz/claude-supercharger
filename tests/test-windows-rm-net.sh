#!/usr/bin/env bash
# Windows-gated destructive-path net (v2.26.83)
#
# safety.sh's python resolver realpath()s every token before comparing it. On
# Windows that maps `/etc` to `D:\etc`, which never equals the POSIX literal in
# SYS_ROOTS, and os.sep is a backslash so `r + os.sep` builds the nonsense prefix
# `/etc\`. All three of its checks — cwd-ancestor, system root, home — break the
# same way, so everything it is the SOLE guard for failed OPEN.
#
# Proven on a windows-latest runner by the report-only suite recon, not inferred:
#     ALLOWED: rm -rf /etc          (both flag orders)
#     ALLOWED: rm /. -rf
#     ALLOWED: rm -rf <project dir>, and an ancestor of it
# `rm -rf /` kept blocking through the bash arm, which is why the CI smoke test
# stayed green and hid this for the entire port.
#
# The fix is a TEXT match gated to Windows. Text is the right layer: the operator
# typed `/etc` whatever the platform, so no resolution is needed to know what they
# meant. The gate makes macOS/Linux provably unchanged — $OSTYPE is never
# msys/cygwin there, so the block cannot execute.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Testing this on macOS needs the python resolver to be INERT, because otherwise it
# catches these itself and every case passes without the net doing anything — the
# first version of this check was exactly that ambiguous. The stub reproduces what
# the resolver does on Windows: runs, matches nothing, prints nothing, exits 0.
# That is NOT the same as python being absent, which takes a different branch.
STUBDIR=$(mktemp -d)
printf '#!/bin/sh\nexit 0\n' > "$STUBDIR/python3"
chmod +x "$STUBDIR/python3"

probe() { # command, ostype, [cwd] -> BLOCK|allow
  local cmd="$1" ost="$2" wd="${3:-}" st rc payload
  st=$(mktemp -d); mkdir -p "$st/scope" "$st/home"
  payload=$(CMD="$cmd" ST="$st" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]},
                  "cwd": os.environ["ST"]}))')
  if [ -n "$wd" ]; then
    printf '%s' "$payload" | (cd "$wd" && env PATH="$STUBDIR:$PATH" HOME="$st/home" \
      SUPERCHARGER_STATE="$st" OSTYPE="$ost" bash "$REPO_DIR/hooks/safety.sh") >/dev/null 2>&1
  else
    printf '%s' "$payload" | env PATH="$STUBDIR:$PATH" HOME="$st/home" \
      SUPERCHARGER_STATE="$st" OSTYPE="$ost" bash "$REPO_DIR/hooks/safety.sh" >/dev/null 2>&1
  fi
  rc=$?
  rm -rf "$st"
  [ "$rc" -eq 2 ] && printf 'BLOCK' || printf 'allow'
}

echo "=== Windows-gated destructive-path net ==="

begin_test "the stub really does silence the python resolver"
# Guards the guard. If the resolver still fires, every case below passes for free
# and a fail-open would ship reported as fixed.
[ "$(probe 'rm -rf /etc' darwin20)" = "allow" ] && pass \
  || fail "resolver still active under the stub — the cases below prove nothing"

# --- what the runner proved was ALLOWED -------------------------------------
begin_test "rm -rf /etc blocks on Windows"
[ "$(probe 'rm -rf /etc' msys)" = "BLOCK" ] && pass || fail "still fails open"

begin_test "rm /etc -rf blocks on Windows (flags last)"
[ "$(probe 'rm /etc -rf' msys)" = "BLOCK" ] && pass || fail "flag order evades the net"

begin_test "a path UNDER a system root blocks on Windows"
[ "$(probe 'rm -rf /usr/lib/x' msys)" = "BLOCK" ] && pass || fail "subpath not covered"

begin_test "rm /. -rf blocks on Windows"
[ "$(probe 'rm /. -rf' msys)" = "BLOCK" ] && pass || fail "root spelling /. evades the net"

begin_test "rm -rf /.. and // block on Windows"
{ [ "$(probe 'rm -rf /..' msys)" = "BLOCK" ] && [ "$(probe 'rm -rf //' msys)" = "BLOCK" ]; } \
  && pass || fail "root spellings /.. or // evade the net"

begin_test "cygwin is gated in as well as msys"
[ "$(probe 'rm -rf /etc' cygwin)" = "BLOCK" ] && pass || fail "cygwin not gated — OSTYPE is cygwin on Git Bash"

begin_test "the project directory itself blocks on Windows"
WD=$(mktemp -d)
[ "$(probe "rm -rf $WD" msys "$WD")" = "BLOCK" ] && pass || fail "project-dir wipe still allowed"
rm -rf "$WD"

begin_test "an ancestor of the project directory blocks on Windows"
WD=$(mktemp -d); mkdir -p "$WD/sub/dir"
[ "$(probe "rm -rf $WD" msys "$WD/sub/dir")" = "BLOCK" ] && pass || fail "ancestor wipe still allowed"
rm -rf "$WD"

# --- the gate must not change macOS/Linux -----------------------------------
begin_test "GATE: the net is inert on darwin"
# With the resolver stubbed, a darwin run must behave exactly as it did before this
# change — i.e. the net contributes nothing. On a real mac the resolver is not
# stubbed and still blocks these.
R=""
for c in 'rm -rf /etc' 'rm /etc -rf' 'rm -rf /usr/lib/x' 'rm /. -rf'; do
  [ "$(probe "$c" darwin20)" = "BLOCK" ] && R="$R [$c]"
done
[ -z "$R" ] && pass || fail "the net fired on darwin — the gate leaks:$R"

begin_test "GATE: the net is inert on linux"
R=""
for c in 'rm -rf /etc' 'rm /. -rf'; do
  [ "$(probe "$c" linux-gnu)" = "BLOCK" ] && R="$R [$c]"
done
[ -z "$R" ] && pass || fail "the net fired on linux — the gate leaks:$R"

# --- ordinary work must survive on Windows ----------------------------------
begin_test "ordinary deletions still allowed on Windows"
R=""
for c in 'rm -rf build/' 'rm -rf ./dist' 'rm -rf node_modules' 'rm -rf target'; do
  [ "$(probe "$c" msys)" = "BLOCK" ] && R="$R [$c]"
done
[ -z "$R" ] && pass || fail "false positives on Windows:$R"

begin_test "a temp dir under /var is still allowed on Windows"
# SYS_ROOTS deliberately omits /var (macOS mktemp -d lives there); the net mirrors
# that rather than inventing a stricter list.
[ "$(probe 'rm -rf /var/folders/t5/tmp.XYZ' msys)" = "allow" ] && pass \
  || fail "net is stricter than SYS_ROOTS — /var should not be protected"

rm -rf "$STUBDIR"
report
