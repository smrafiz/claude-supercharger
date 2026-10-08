#!/usr/bin/env bash
# The profile help text quotes how many hooks each profile skips. It said 8/11
# while hook_profile_skip skipped 7/10 — count the real lists instead of trusting it.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

skipped() { # profile -> how many registered hook names hook_profile_skip skips
  local n=0 h
  for h in $(ls "$REPO_DIR"/hooks/*.sh | sed 's#.*/##; s#\.sh$##'); do
    SUPERCHARGER_PROFILE="$1" bash -c '. "$1/hooks/lib-suppress.sh" >/dev/null 2>&1; hook_profile_skip "$2"' _ "$REPO_DIR" "$h" && n=$((n+1))
  done
  echo "$n"
}

for p in fast minimal; do
  begin_test "profile help: '$p' quotes the number of hooks it really skips"
  want=$(skipped "$p")
  grep -q "$p .*skips $want " "$REPO_DIR/tools/profile-switch.sh" && pass \
    || fail "help says: $(grep -o "$p .*skips [0-9]*" "$REPO_DIR/tools/profile-switch.sh"); real: $want"
done

report
