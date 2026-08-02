#!/usr/bin/env bash
# release.sh must find the CHANGELOG insert point regardless of file size (v2.26.25)
#
# The extraction was `grep -n '^\- \[' "$CHANGELOG" | head -1 | cut -d: -f1`.
# Once the CHANGELOG grew past the 64KB pipe buffer (it is ~122KB of matching
# lines now), head -1 exited before grep finished, grep took SIGPIPE, and
# `set -o pipefail` turned that into a non-zero pipeline that `set -e` killed the
# release on — silently, immediately after the version files had been bumped and
# before the commit. The tree was left half-released with no error printed.
#
# Size-dependent failures do not announce themselves, so the size is the test:
# the small case passed for every release right up until the day it didn't.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== release.sh CHANGELOG Anchor Tests ==="

# Extract the real line from release.sh — not a copy of it. A copy would pass
# whatever the tool does, which is how this class of bug survives its own test.
EXTRACT=$(grep -n 'FIRST_ENTRY=' "$REPO_DIR/tools/release.sh" | grep -v '^\s*#' | head -1 | cut -d: -f2-)

begin_test "the FIRST_ENTRY line was located in release.sh"
printf '%s' "$EXTRACT" | grep -q 'grep' && pass || fail "could not find FIRST_ENTRY in release.sh"

# Build CHANGELOGs of both sizes. Entry text is padded to make the small file
# comfortably under the pipe buffer and the large one comfortably over it.
mk_changelog() { # path, entry-count
  local path="$1" n="$2" i pad
  pad=$(printf 'x%.0s' $(seq 1 600))
  {
    printf '# Changelog\n\n## Contents\n\n'
    for ((i = n; i > 0; i--)); do
      printf -- '- [1.0.%d] - 2026-01-01 — entry %d %s\n' "$i" "$i" "$pad"
    done
  } > "$path"
}

run_extract() { # changelog-path -> prints line number, or nothing on failure
  local cl="$1" script
  script=$(mktemp)
  {
    printf 'set -euo pipefail\n'
    printf 'CHANGELOG=%q\n' "$cl"
    printf '%s\n' "$EXTRACT"
    printf 'printf "%%s" "$FIRST_ENTRY"\n'
  } > "$script"
  bash "$script" 2>/dev/null
  rm -f "$script"
}

TD=$(mktemp -d)

begin_test "small CHANGELOG (under the pipe buffer) resolves the anchor"
mk_changelog "$TD/small.md" 20
[ "$(run_extract "$TD/small.md")" = "5" ] && pass || fail "expected line 5, got '$(run_extract "$TD/small.md")'"

begin_test "large CHANGELOG (over the 64KB pipe buffer) resolves the anchor"
mk_changelog "$TD/large.md" 400
SZ=$(grep -c '^- \[' "$TD/large.md")
GOT=$(run_extract "$TD/large.md")
[ "$GOT" = "5" ] && pass \
  || fail "anchor lost on a ${SZ}-entry CHANGELOG (got '$GOT') — release.sh will die after bumping versions"

begin_test "the repo's own CHANGELOG resolves the anchor"
GOT=$(run_extract "$REPO_DIR/CHANGELOG.md")
printf '%s' "$GOT" | grep -qE '^[0-9]+$' && pass || fail "real CHANGELOG.md yields no anchor (got '$GOT')"

begin_test "extraction does not pipe grep into head (the SIGPIPE shape)"
printf '%s' "$EXTRACT" | grep -q '|[[:space:]]*head' \
  && fail "grep is piped to head again — reintroduces the size-dependent failure" || pass

rm -rf "$TD"
report
