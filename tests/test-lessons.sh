#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

RECORD_HOOK="$REPO_DIR/hooks/lesson-record.sh"
RECALL_HOOK="$REPO_DIR/hooks/lesson-recall.sh"

echo "=== Reflexion Memory Tests ==="

export SUPERCHARGER_NO_DEDUP=1
export SUPERCHARGER_TIER=standard

begin_test "lessons: lesson-record.sh exists and is executable"
[ -x "$RECORD_HOOK" ] && pass || fail "lesson-record.sh missing or not executable"

begin_test "lessons: lesson-recall.sh exists and is executable"
[ -x "$RECALL_HOOK" ] && pass || fail "lesson-recall.sh missing or not executable"
