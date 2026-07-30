#!/usr/bin/env bash
# Shebang stamping (v2.25.1)
#
# `#!/usr/bin/env bash` costs a PATH search on every hook exec — measured at ~1.8 ms
# (env 4.1–4.8 ms vs absolute 2.3–3.2 ms over three interleaved rounds, with bash 12
# entries deep in PATH). Hooks fire in parallel waves of ~11, so stamping the
# installed copies takes ~1.8 ms off a wave's felt latency and ~20 ms of CPU off it.
#
# The danger is not the saving, it is the failure mode: a wrong interpreter path
# means the hook cannot exec at all — a guard that silently stops running, which is
# the class this repo keeps getting bitten by. These tests pin the three constraints
# that make it safe, not just the happy path.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# shellcheck source=lib/hooks.sh
. "$REPO_DIR/lib/hooks.sh"

echo "=== Shebang Stamp Tests ==="

mk() { # dir n  — n fake hooks with the portable shebang
  local d="$1" n="$2" i
  mkdir -p "$d"
  for ((i=1;i<=n;i++)); do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/h$i.sh"
    chmod 700 "$d/h$i.sh"
  done
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/lib-suppress.sh"
  chmod 700 "$d/lib-suppress.sh"
}

BASHP=$(command -v bash)
SYSTEM_BASH=0
case "$BASHP" in /bin/bash|/usr/bin/bash) SYSTEM_BASH=1 ;; esac

begin_test "stamps the portable shebang to an absolute interpreter path"
D=$(mktemp -d); mk "$D" 3
stamp_hook_shebangs "$D"
if [ "$SYSTEM_BASH" = "1" ]; then
  head -1 "$D/h1.sh" | grep -q "^#!$BASHP$" && pass || fail "not stamped: $(head -1 "$D/h1.sh")"
else
  # Non-system bash must be left alone (constraint 2) — that is also a pass.
  head -1 "$D/h1.sh" | grep -q '^#!/usr/bin/env bash$' && pass || fail "stamped a non-system bash path"
fi
rm -rf "$D"

begin_test "stamped hooks still EXECUTE (the failure mode that matters)"
D=$(mktemp -d); mk "$D" 2
stamp_hook_shebangs "$D"
"$D/h1.sh"; [ $? -eq 0 ] && pass || fail "a stamped hook no longer executes"
rm -rf "$D"

begin_test "stamps every hook in the directory, not just the first"
D=$(mktemp -d); mk "$D" 5
stamp_hook_shebangs "$D"
if [ "$SYSTEM_BASH" = "1" ]; then
  N=$(grep -l "^#!$BASHP$" "$D"/*.sh 2>/dev/null | wc -l | tr -d ' ')
  [ "$N" -eq 6 ] && pass || fail "expected 6 stamped (5 hooks + lib-suppress), got $N"
else
  pass
fi
rm -rf "$D"

begin_test "leaves a non-bash shebang untouched (python scanners keep theirs)"
D=$(mktemp -d); mk "$D" 1
printf '#!/usr/bin/env python3\nimport sys\n' > "$D/scan.sh"; chmod 700 "$D/scan.sh"
stamp_hook_shebangs "$D"
head -1 "$D/scan.sh" | grep -q 'python3' && pass || fail "rewrote a python shebang"
rm -rf "$D"

begin_test "is idempotent — re-stamping an already-stamped dir is a no-op"
D=$(mktemp -d); mk "$D" 2
stamp_hook_shebangs "$D"; A=$(cat "$D/h1.sh")
stamp_hook_shebangs "$D"; B=$(cat "$D/h1.sh")
[ "$A" = "$B" ] && pass || fail "second stamp changed the file"
rm -rf "$D"

begin_test "leaves the file body byte-identical (only line 1 changes)"
D=$(mktemp -d); mkdir -p "$D"
printf '#!/usr/bin/env bash\n# comment\nset -e\necho "body $USER"\n' > "$D/h1.sh"; chmod 700 "$D/h1.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$D/lib-suppress.sh"; chmod 700 "$D/lib-suppress.sh"
BEFORE=$(tail -n +2 "$D/h1.sh")
stamp_hook_shebangs "$D"
[ "$(tail -n +2 "$D/h1.sh")" = "$BEFORE" ] && pass || fail "body changed during stamping"
rm -rf "$D"

begin_test "SUPERCHARGER_STAMP_SHEBANG=0 opts out"
D=$(mktemp -d); mk "$D" 2
SUPERCHARGER_STAMP_SHEBANG=0 stamp_hook_shebangs "$D"
head -1 "$D/h1.sh" | grep -q '^#!/usr/bin/env bash$' && pass || fail "opt-out ignored"
rm -rf "$D"

begin_test "hooks stay executable after stamping (mode preserved)"
D=$(mktemp -d); mk "$D" 2
stamp_hook_shebangs "$D"
[ -x "$D/h1.sh" ] && pass || fail "stamping dropped the executable bit"
rm -rf "$D"

begin_test "repo sources keep the portable shebang (only installed copies stamped)"
BAD=$(head -1 "$REPO_DIR"/hooks/*.sh 2>/dev/null | grep -c '^#!/bin/bash$' || true)
[ "${BAD:-0}" -eq 0 ] && pass || fail "a repo hook was stamped; sources must stay portable"

report
