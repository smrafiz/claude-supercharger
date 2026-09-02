#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/commit-guard.sh"

echo "=== commit-coauthor-guard Tests ==="
export SUPERCHARGER_NO_DEDUP=1

# These cases pass no `cwd`, so PROJECT_DIR falls back to $PWD — this repo, on its
# default branch — and commit-guard's default-branch check would answer a test
# about co-authors. SUPERCHARGER_DEFAULT_BRANCH_GUARD=0 keeps each case on its
# own subject; the branch check has its own suite.
# Run with the guard ENABLED via env (isolated HOME so the flag file check is clean).
_on() { # <command>
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" \
    | HOME="$(mktemp -d)" SUPERCHARGER_COAUTHOR_GUARD=1 SUPERCHARGER_DEFAULT_BRANCH_GUARD=0 bash "$HOOK" 2>/dev/null
}

begin_test "coauthor-guard: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "coauthor-guard: OFF by default (no env, no flag) — commit with trailer allowed"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x Co-Authored-By: Claude <a@b>"}}' \
  | HOME="$(mktemp -d)" SUPERCHARGER_DEFAULT_BRANCH_GUARD=0 bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent when disabled, got: $OUT"

begin_test "coauthor-guard: ON — commit with Co-Authored-By is blocked"
OUT=$(_on "git commit -m msg Co-Authored-By: Claude <noreply@anthropic.com>")
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected block, got: $OUT"

begin_test "coauthor-guard: ON — case-insensitive (co-authored-by) blocked"
OUT=$(_on "git commit -m fix co-authored-by: someone <x@y>")
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected case-insensitive block, got: $OUT"

begin_test "coauthor-guard: ON — clean commit (no trailer) is allowed"
OUT=$(_on "git commit -m \"fix: normal message\"")
[ -z "$OUT" ] && pass || fail "expected clean commit allowed, got: $OUT"

begin_test "coauthor-guard: ON — non-commit git command is ignored"
OUT=$(_on "git log --format=%an Co-Authored-By")
[ -z "$OUT" ] && pass || fail "expected non-commit ignored, got: $OUT"

begin_test "coauthor-guard: ON — git commit --help is ignored"
OUT=$(_on "git commit --help")
[ -z "$OUT" ] && pass || fail "expected --help ignored, got: $OUT"

begin_test "coauthor-guard: enabled via flag file (no env)"
H=$(mktemp -d); mkdir -p "$H/.claude/supercharger/scope"; touch "$H/.claude/supercharger/scope/.coauthor-guard"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x Co-Authored-By: Claude"}}' \
  | HOME="$H" bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected flag-file enable, got: $OUT"
rm -rf "$H"

begin_test "coauthor-guard: env=0 force-disables even with flag file"
H=$(mktemp -d); mkdir -p "$H/.claude/supercharger/scope"; touch "$H/.claude/supercharger/scope/.coauthor-guard"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x Co-Authored-By: Claude"}}' \
  | HOME="$H" SUPERCHARGER_COAUTHOR_GUARD=0 SUPERCHARGER_DEFAULT_BRANCH_GUARD=0 bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected env=0 to override flag, got: $OUT"
rm -rf "$H"

begin_test "coauthor-guard: fail-open on malformed JSON"
OUT=$(printf 'not json' | HOME="$(mktemp -d)" SUPERCHARGER_COAUTHOR_GUARD=1 SUPERCHARGER_DEFAULT_BRANCH_GUARD=0 bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected fail-open, got: $OUT"

report
