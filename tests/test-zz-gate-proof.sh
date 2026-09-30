#!/usr/bin/env bash
# Throwaway: proves the CI test gate fails on a failing test. Never merge.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
begin_test "ci-gate-proof: deliberate failure"
fail "deliberate"
report
