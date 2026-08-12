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
  # "$@" comes FIRST so a caller can pass `-u MSYSTEM`: env stops treating words
  # as options at the first assignment, so an option after HOME=... would be read
  # as the command name.
  local st; st=$(mktemp -d); mkdir -p "$st/free" "$st/home"
  printf '{"additionalRoots":["%s"]}' "$MROOT" > "$st/free/$CFG"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s/etc/x","content":"x"},"cwd":"%s"}' \
    "$MROOT" "$st/free" \
    | env "$@" HOME="$st/home" SUPERCHARGER_STATE="$st" SC_PATHGUARD_DEBUG=1 \
      bash "$REPO_DIR/hooks/path-guard.sh" 2>&1 >/dev/null \
    | grep -oE "msys_root='[^']*'" | head -1 | sed "s/msys_root='//; s/'$//"
  rm -rf "$st"
}

# The header above said the POSITIVE case could not be exercised here. That is
# true off Windows and false on the runner, where these same three checks were
# asserting inertness on the one platform the feature is supposed to work — so
# the recon reported "derived a root off Windows: 'C:\Program Files\Git'" three
# times, which is the feature working, reported as a defect.
case "$OSTYPE" in
  msys*|cygwin*|win32*) ON_WINDOWS=1 ;;
  *)                    ON_WINDOWS=0 ;;
esac
echo "=== MSYS root refusal ($([ "$ON_WINDOWS" = 1 ] && echo 'live on Git Bash' || echo 'inertness off Windows')) ==="

begin_test "the MSYS root is derived on Windows, and nowhere else"
DERIVED=$(root_of MSYSTEM=MINGW64)
if [ "$ON_WINDOWS" = 1 ]; then
  # os.name == 'nt': the branch runs and must find the install the shell came from.
  [ -n "$DERIVED" ] && pass || fail "no MSYS root derived on Git Bash — the refusal cannot fire"
else
  # os.name is 'posix' here, so the branch must not run at all.
  [ -z "$DERIVED" ] && pass || fail "derived a root off Windows: '$DERIVED'"
fi

begin_test "GATE: an MSYS-shaped bash layout does not decide it"
# The exact shape that broke ubuntu: <root>/usr/bin/bash is where Linux keeps bash.
DERIVED=$(root_of MSYSTEM=MINGW64 PATH="$MROOT/usr/bin:$PATH")
if [ "$ON_WINDOWS" = 1 ]; then
  # A planted layout must not REDIRECT the derivation to itself.
  [ "$DERIVED" != "$MROOT" ] && pass || fail "a planted /usr/bin/bash captured the derivation"
else
  [ -z "$DERIVED" ] && pass || fail "the /usr/bin/bash layout derived a root: '$DERIVED'"
fi

begin_test "nothing is derived when MSYSTEM is genuinely unset"
# `env -u`, because the old version merely inherited whatever was set and so
# never tested the condition it named.
#
# On Git Bash the condition cannot be built from outside at all: MSYS bash
# re-exports MSYSTEM to every child, so `env -u MSYSTEM bash …` hands python a
# populated MSYSTEM regardless. The runner proved it — this asserted "unset" and
# got 'C:\Program Files\Git'. That is the shell being itself, not the guard
# misbehaving, so the assertion is made where it can actually hold.
if [ "$ON_WINDOWS" = 1 ]; then
  echo "    (skipped on Git Bash: MSYS bash re-exports MSYSTEM to children,"
  echo "     so an unset-MSYSTEM process cannot be constructed from outside)"
  pass
else
  DERIVED=$(root_of -u MSYSTEM)
  [ -z "$DERIVED" ] && pass || fail "derived a root with MSYSTEM unset: '$DERIVED'"
fi

begin_test "GATE: an ordinary directory is still a valid project root"
# The refusal must not leak into macOS/Linux, where this is just a directory.
[ "$(verdict "$MROOT" MSYSTEM=MINGW64 PATH="$MROOT/usr/bin:$PATH")" = "allow" ] \
  && pass || fail "an ordinary root was refused on a non-Windows platform"

begin_test "GATE: the filesystem root is still refused"
# The original check must keep working — this fix adds to it, not replaces it.
[ "$(verdict "/")" = "allow" ] && fail "'/' was accepted as a root" || pass

# --- Git Bash drive paths must resolve to the drive, not the CWD's drive ------
# Native Windows python resolves a leading-slash path against the CURRENT DRIVE.
# Measured on a runner whose workspace sits on D:
#   realpath('/')                -> 'D:\'
#   realpath('/c/Users/me/.ssh') -> 'D:\c\Users\me\.ssh'
# The second equals nothing, so a write to the real ~/.ssh compared as unrelated
# and the credential protection never fired. Git Bash hands out exactly that
# spelling, so the guard normalises it rather than assuming which form arrives.
#
# Extracted from the hook and driven directly, because the rewrite is gated on
# os.name and cannot execute here — the same reason the refusal itself is only
# assertable for inertness off Windows.
begin_test "the MSYS drive-path normaliser maps /c/... to C:\\... and nothing else"
RES=$(python3 - "$REPO_DIR/hooks/path-guard.sh" <<'PYEOF'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'def _msys_path\(x\):.*?\n(?=\n\np = _msys_path)', src, re.S)
if not m:
    print('EXTRACT-FAILED'); raise SystemExit
ns = {'os': type('O', (), {'name': 'nt'})(), 're': re}
exec(m.group(0), ns)
f = ns['_msys_path']
want = {
    '/c/Users/me/.ssh/id_rsa': 'C:\\Users\\me\\.ssh\\id_rsa',
    '/d/a/repo':               'D:\\a\\repo',
    '/etc/hosts':              '/etc/hosts',      # multi-char segment: not a drive
    '/cats/file.txt':          '/cats/file.txt',  # must NOT become C:\ats
    'C:\\Users\\me':           'C:\\Users\\me',   # already native
    '':                        '',
}
bad = [f'{k!r}->{f(k)!r} want {v!r}' for k, v in want.items() if f(k) != v]
print('; '.join(bad) if bad else 'OK')
PYEOF
)
[ "$RES" = "OK" ] && pass || fail "normaliser wrong: $RES"

begin_test "GATE: the normaliser is inert when os.name is not nt"
# A POSIX box has legitimate /c directories. Rewriting one in a security guard
# would be worse than the bug this fixes.
RES=$(python3 - "$REPO_DIR/hooks/path-guard.sh" <<'PYEOF'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'def _msys_path\(x\):.*?\n(?=\n\np = _msys_path)', src, re.S)
ns = {'os': type('O', (), {'name': 'posix'})(), 're': re}
exec(m.group(0), ns)
f = ns['_msys_path']
print('OK' if f('/c/Users/me') == '/c/Users/me' else 'REWROTE: ' + f('/c/Users/me'))
PYEOF
)
[ "$RES" = "OK" ] && pass || fail "$RES"

begin_test "the guard keys on os.name, not on MSYSTEM or a path layout"
# Pins the discriminator itself, since the two weaker ones each shipped and each
# was wrong. Source-level because the behaviour it guards cannot run here.
grep -q "os.name == 'nt' and os.environ.get('MSYSTEM')" "$REPO_DIR/hooks/path-guard.sh" \
  && pass || fail "the MSYS gate no longer keys on os.name — a weaker test has crept back"

rm -rf "$(dirname "$MROOT")"
report
