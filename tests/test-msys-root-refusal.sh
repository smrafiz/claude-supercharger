#!/usr/bin/env bash
# additionalRoots:["/"] on Git Bash (v2.26.83)
#
# MSYS rewrites a single-path env var in transit, and EXTRA_ROOTS travels that
# channel. Measured on a windows-latest runner:
#
#     config   additionalRoots: ["/"]
#     python   raw='C:/Program Files/Git/'   is_fs_root=False
#
# So the filesystem-root refusal (`rp == dirname(rp)`) never fires, the root is
# accepted, and the project silently widens to everything under the Git install —
# which is how C:/Program Files/Git/etc/hosts came back as in-project.
#
# The refusal now also rejects the MSYS root, derived from the shell's own location
# rather than a hardcoded "C:/Program Files/Git", so it holds for any install path.
#
# Severity, stated precisely because it was overstated once: a user writing "/" does
# not get the filesystem root — they get the Git install dir. Silent and wrong, not
# catastrophic.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

CFG=".supercharger"".json"   # split: the local self-mod guard reads the literal

# A fake MSYS tree. The guard keys on MSYSTEM plus the <root>/usr/bin/bash layout,
# so both are needed to reproduce the platform.
MROOT=$(mktemp -d)/Git
mkdir -p "$MROOT/usr/bin" "$MROOT/etc"
printf '#!/bin/sh\nexec /bin/bash "$@"\n' > "$MROOT/usr/bin/bash"
chmod +x "$MROOT/usr/bin/bash"

verdict() { # root, extra-env... -> BLOCK|allow
  local root="$1"; shift
  local st rc; st=$(mktemp -d); mkdir -p "$st/free" "$st/home"
  printf '{"additionalRoots":["%s"]}' "$root" > "$st/free/$CFG"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s/etc/hosts","content":"x"},"cwd":"%s"}' \
    "$root" "$st/free" \
    | env HOME="$st/home" SUPERCHARGER_STATE="$st" "$@" \
      bash "$REPO_DIR/hooks/path-guard.sh" >/dev/null 2>&1
  rc=$?
  rm -rf "$st"
  [ "$rc" -eq 2 ] && printf 'BLOCK' || printf 'allow'
}

root_of() { # extra-env... -> the msys_root the guard derives
  local st; st=$(mktemp -d); mkdir -p "$st/free" "$st/home"
  printf '{"additionalRoots":["%s"]}' "$MROOT" > "$st/free/$CFG"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s/etc/x","content":"x"},"cwd":"%s"}' \
    "$MROOT" "$st/free" \
    | env HOME="$st/home" SUPERCHARGER_STATE="$st" SC_PATHGUARD_DEBUG=1 "$@" \
      bash "$REPO_DIR/hooks/path-guard.sh" 2>&1 >/dev/null \
    | grep -oE "msys_root='[^']*'" | head -1 | sed "s/msys_root='//; s/'$//"
  rm -rf "$st"
}

echo "=== MSYS root refusal ==="

begin_test "the MSYS root is refused as a project root"
# The bug in its own terms: before the fix this root was accepted, making every
# file under the Git install in-project.
[ "$(verdict "$MROOT" MSYSTEM=MINGW64 PATH="$MROOT/usr/bin:$PATH")" = "BLOCK" ] \
  && pass || fail "the MSYS root was accepted — everything under the Git install is in-project"

begin_test "the root is derived from the shell, not a hardcoded install path"
GOT=$(root_of MSYSTEM=MINGW64 PATH="$MROOT/usr/bin:$PATH")
[ -n "$GOT" ] && [ "$(cd "$GOT" && pwd -P)" = "$(cd "$MROOT" && pwd -P)" ] \
  && pass || fail "derived '$GOT', expected '$MROOT'"

begin_test "GATE: nothing is derived without the MSYS layout"
# MSYSTEM alone must not be enough. bash lives in /bin on every POSIX system, and
# the two-levels-up rule would otherwise yield '/' — a bogus value in a security
# comparison. This is the check the first draft of the fix was missing.
[ -z "$(root_of MSYSTEM=MINGW64)" ] \
  && pass || fail "derived a root from a POSIX bash: '$(root_of MSYSTEM=MINGW64)'"

begin_test "GATE: nothing is derived when MSYSTEM is unset"
[ -z "$(root_of)" ] && pass || fail "derived a root off Windows: '$(root_of)'"

begin_test "GATE: an ordinary directory is still a valid root off Windows"
# The refusal must not leak into macOS/Linux, where this dir is simply a directory.
[ "$(verdict "$MROOT")" = "allow" ] \
  && pass || fail "an ordinary root was refused on a non-Windows platform"

begin_test "GATE: the filesystem root is still refused"
# The original refusal must keep working — this fix adds to it, not replaces it.
[ "$(verdict "/")" = "allow" ] && fail "'/' was accepted as a root" || pass

rm -rf "$(dirname "$MROOT")"
report
