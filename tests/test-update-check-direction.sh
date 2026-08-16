#!/usr/bin/env bash
# An update notice must only fire when the remote is genuinely NEWER.
#
# The check was `[ "$REMOTE" != "$LOCAL" ]` — it announced an update whenever the
# two strings merely differed, including when the local install was newer. That
# is not a corner case. The result is cached for 24 hours, so after ANY successful
# update the notice pointed BACKWARDS at the version the user had just left, for
# the rest of the day:
#
#     installed 2.27.20, cached "latest" 2.27.14
#     ║  Supercharger update: v2.27.20 → v2.27.14
#
# Found on the development machine, whose install was twenty releases behind while
# the notifier was technically working — a gate that cries wolf gets ignored, and
# this one had been telling the truth and lies interchangeably.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/update-check.sh"

echo "=== update-check direction Tests ==="

UC=$(mktemp -d)
printf '{"session_id":"t","cwd":"/tmp"}' > "$UC/pay.json"

# The cache is consulted only while fresh, so these fixtures write it directly:
# a freshly-created file is inside the 24h TTL by definition.
notice_for() {  # $1=installed $2=cached-remote -> the notice line, or empty
  local d="$UC/case"
  rm -rf "$d"; mkdir -p "$d"
  printf '%s\n' "$1" > "$d/.version"
  printf '%s\n' "$2" > "$d/.update-cache"
  SUPERCHARGER_STATE="$d" bash "$HOOK" < "$UC/pay.json" 2>&1 | grep -F 'Supercharger update:' || true
}

begin_test "silent when the installed version is NEWER than the remote"
OUT=$(notice_for 2.27.20 2.27.14)
[ -z "$OUT" ] && pass || fail "announced a downgrade: $OUT"

begin_test "silent when the versions match"
OUT=$(notice_for 2.27.20 2.27.20)
[ -z "$OUT" ] && pass || fail "announced an update to the same version: $OUT"

begin_test "notifies when the remote is genuinely newer (patch)"
OUT=$(notice_for 2.27.19 2.27.20)
printf '%s' "$OUT" | grep -q '2.27.20' && pass || fail "missed a real update: ${OUT:-<silent>}"

begin_test "notifies when the remote is newer (minor)"
OUT=$(notice_for 2.27.20 2.28.0)
printf '%s' "$OUT" | grep -q '2.28.0' && pass || fail "missed a real update: ${OUT:-<silent>}"

# Numeric per field, not lexical: "9" < "10" as versions, but "9" > "10" as text.
# A string compare gets this backwards and would go silent on a real update.
begin_test "compares fields numerically, not lexically"
OUT=$(notice_for 2.27.9 2.27.10)
printf '%s' "$OUT" | grep -q '2.27.10' && pass || fail "lexical compare hid a real update: ${OUT:-<silent>}"

begin_test "and does not invent one in the other direction"
OUT=$(notice_for 2.27.10 2.27.9)
[ -z "$OUT" ] && pass || fail "lexical compare invented a downgrade: $OUT"

begin_test "differing field counts do not produce a false notice"
OUT=$(notice_for 2.27 2.27.0)
[ -z "$OUT" ] && pass || fail "2.27 vs 2.27.0 announced: $OUT"

rm -rf "$UC"

report
