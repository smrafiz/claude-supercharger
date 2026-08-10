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
# which is how C:/Program Files/Git/etc/hosts came back as in-project. The refusal
# now also rejects the MSYS root, derived from the shell's own location rather than
# a hardcoded install path.
#
# WHAT THIS FILE CAN AND CANNOT CHECK, stated plainly. The guard keys on
# os.name == 'nt', which is true only under native Windows python. So the POSITIVE
# case — the MSYS root actually being refused — cannot be exercised here at all, and
# is verified by the Windows recon instead. Everything below pins the half that CAN
# be checked off Windows: that the new branch stays completely inert.
#
# That distinction is the point rather than a caveat. Two earlier attempts used
# weaker discriminators that DID run here — MSYSTEM alone, then the
# <root>/usr/bin/bash layout — and the second passed on macOS while breaking the
# ubuntu suite, because ordinary Linux keeps bash in exactly that layout. A test
# that runs everywhere is worthless if the thing it tests is not the thing that
# ships.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

CFG=".supercharger"".json"   # split: the local self-mod guard reads the literal

# A directory shaped like an MSYS install, including the bash layout that fooled the
# second attempt. On this platform it must be treated as an ordinary directory.
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

echo "=== MSYS root refusal (inertness off Windows) ==="

begin_test "GATE: nothing is derived on this platform, even with MSYSTEM set"
# os.name is 'posix' here, so the branch must not run at all.
[ -z "$(root_of MSYSTEM=MINGW64)" ] \
  && pass || fail "derived a root off Windows: '$(root_of MSYSTEM=MINGW64)'"

begin_test "GATE: an MSYS-shaped bash layout does not trigger it either"
# The exact shape that broke ubuntu: <root>/usr/bin/bash is where Linux keeps bash.
[ -z "$(root_of MSYSTEM=MINGW64 PATH="$MROOT/usr/bin:$PATH")" ] \
  && pass || fail "the /usr/bin/bash layout derived a root: '$(root_of MSYSTEM=MINGW64 PATH="$MROOT/usr/bin:$PATH")'"

begin_test "GATE: nothing is derived when MSYSTEM is unset"
[ -z "$(root_of)" ] && pass || fail "derived a root with MSYSTEM unset: '$(root_of)'"

begin_test "GATE: an ordinary directory is still a valid project root"
# The refusal must not leak into macOS/Linux, where this is just a directory.
[ "$(verdict "$MROOT" MSYSTEM=MINGW64 PATH="$MROOT/usr/bin:$PATH")" = "allow" ] \
  && pass || fail "an ordinary root was refused on a non-Windows platform"

begin_test "GATE: the filesystem root is still refused"
# The original check must keep working — this fix adds to it, not replaces it.
[ "$(verdict "/")" = "allow" ] && fail "'/' was accepted as a root" || pass

begin_test "the guard keys on os.name, not on MSYSTEM or a path layout"
# Pins the discriminator itself, since the two weaker ones each shipped and each
# was wrong. Source-level because the behaviour it guards cannot run here.
grep -q "os.name == 'nt' and os.environ.get('MSYSTEM')" "$REPO_DIR/hooks/path-guard.sh" \
  && pass || fail "the MSYS gate no longer keys on os.name — a weaker test has crept back"

rm -rf "$(dirname "$MROOT")"
report
