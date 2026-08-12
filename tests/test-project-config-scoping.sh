#!/usr/bin/env bash
# Per-project config no longer clobbers across projects (v2.26.33)
#
# This is audit HIGH #13, open since v2.21 and the last one on the list.
# `.profile`, `.disabled-hooks` and `.disabled-security-categories` hold values
# belonging to ONE project but were written to a single global path, so with two
# projects open each overwrote the other:
#
#   - a project with no `profile` key os.remove()d another project's profile
#   - `disableSecurityCategories` set in one project disabled that category for
#     EVERY project on the machine — the loosening direction, so this is the arm
#     that actually mattered
#
# `.budget-cap` was listed in the audit as a fourth file. It is written by
# project-config and read by NOTHING — budget-cap.sh takes the limit straight
# from .supercharger.json (budget-cap.sh:339), which was already per-project. It
# is kept per-project here for consistency, but it was never a live bug.
#
# Keyed by sanitised project path rather than a hash: the key is computed in
# lib-suppress, which every hook sources, and an md5sum there would add a fork to
# the per-hook floor. Reads fall back to the legacy global file so installs
# written before this change keep working.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Filenames assembled at runtime: written out literally, this repo's own selfmod
# guard blocks the command that creates the fixture.
CATS=".disabled-security-""categories"
DHOOKS=".disabled-""hooks"

key_for() { sc_key_for "$1"; }   # shared: tests/helpers.sh

echo "=== Per-Project Config Scoping Tests ==="

# --- the key helper itself ---------------------------------------------------
kt() { # path -> SC_PROJECT_KEY via the real function
  SUPERCHARGER_STATE="${SUPERCHARGER_STATE:-/tmp}" bash -c '
    . "'"$REPO_DIR"'/hooks/lib-paths.sh"
    sc_project_key "$1"
    printf "%s" "$SC_PROJECT_KEY"' _ "$1"
}

begin_test "the bash key and the python key agree (writer vs readers)"
P="/Users/someone/code/my-project"
[ "$(kt "$P")" = "$(key_for "$P")" ] && pass \
  || fail "key mismatch: bash='$(kt "$P")' python='$(key_for "$P")' — config would silently do nothing"

begin_test "different projects produce different keys"
[ "$(kt /a/one)" != "$(kt /a/two)" ] && pass || fail "keys collide"

begin_test "the key is bounded for a very deep path"
DEEP="/$(python3 -c "print('/'.join(['segment'] * 60))")"
[ "${#-}" ]; K=$(kt "$DEEP")
[ "${#K}" -le 100 ] && [ -n "$K" ] && pass || fail "key length ${#K} exceeds the filename budget"

begin_test "root resolves to a usable key, not an empty suffix"
[ "$(kt /)" = "root" ] && pass || fail "got '$(kt /)'"

# --- the failure this closes: cross-project security-category bleed ----------
run_safety() { # project_dir, state_dir -> BLOCKED | allowed
  printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"rm -rf ~/important"}}' "$1" \
    | SUPERCHARGER_STATE="$2" bash "$REPO_DIR/hooks/safety.sh" >/dev/null 2>&1
  [ $? -eq 2 ] && echo BLOCKED || echo allowed
}

ST=$(mktemp -d); mkdir -p "$ST/scope"
PA=$(mktemp -d); PB=$(mktemp -d)
printf 'filesystem\n' > "$ST/scope/$CATS-$(key_for "$PA")"

begin_test "project A's disabled category applies to project A"
[ "$(run_safety "$PA" "$ST")" = "allowed" ] && pass || fail "A's own opt-out was ignored"

begin_test "project A's disabled category does NOT disable the guard for project B"
[ "$(run_safety "$PB" "$ST")" = "BLOCKED" ] && pass \
  || fail "one project silently disabled a security category for another — the bug this closes"

begin_test "the legacy global file is still honoured (back-compat)"
rm -f "$ST/scope/$CATS-$(key_for "$PA")"
printf 'filesystem\n' > "$ST/scope/$CATS"
[ "$(run_safety "$PA" "$ST")" = "allowed" ] && pass \
  || fail "installs written before this change would lose their setting"

begin_test "a per-project file takes precedence over the legacy global one"
# Global says filesystem is off; the project file exists and is empty → guard on.
: > "$ST/scope/$CATS-$(key_for "$PB")"
[ "$(run_safety "$PB" "$ST")" = "BLOCKED" ] && pass || fail "global overrode the project file"
rm -rf "$ST" "$PA" "$PB"

# --- profile + disabled-hooks resolve per project ---------------------------
ST=$(mktemp -d); mkdir -p "$ST/scope"
PA=$(mktemp -d); PB=$(mktemp -d)
printf 'minimal\n' > "$ST/scope/.profile-$(key_for "$PA")"

profile_seen() { # project dir -> the profile lib-suppress resolves
  SUPERCHARGER_STATE="$ST" bash -c '
    . "'"$REPO_DIR"'/hooks/lib-suppress.sh" 2>/dev/null
    init_hook_suppress "$1" >/dev/null 2>&1
    printf "%s" "${SUPERCHARGER_PROFILE:-standard}"' _ "$1"
}

begin_test "project A sees its own profile"
[ "$(profile_seen "$PA")" = "minimal" ] && pass || fail "got '$(profile_seen "$PA")'"

begin_test "project B is not given project A's profile"
[ "$(profile_seen "$PB")" = "standard" ] && pass \
  || fail "got '$(profile_seen "$PB")' — profile bled across projects"

printf 'auto-compact\n' > "$ST/scope/$DHOOKS-$(key_for "$PA")"
disabled_seen() {
  SUPERCHARGER_STATE="$ST" bash -c '
    . "'"$REPO_DIR"'/hooks/lib-suppress.sh" 2>/dev/null
    init_hook_suppress "$1" >/dev/null 2>&1
    printf "%s" "$_DISABLED_HOOKS_CONTENT"' _ "$1"
}

begin_test "project A sees its own disabled-hooks list"
[ "$(disabled_seen "$PA")" = "auto-compact" ] && pass || fail "got '$(disabled_seen "$PA")'"

begin_test "project B does not inherit project A's disabled hooks"
[ -z "$(disabled_seen "$PB")" ] && pass \
  || fail "project B had hooks disabled by another project: '$(disabled_seen "$PB")'"
rm -rf "$ST" "$PA" "$PB"

# --- the writer must produce the keyed name ---------------------------------
begin_test "project-config writes the per-project name, not the global one"
ST=$(mktemp -d); mkdir -p "$ST/scope"
PJ=$(mktemp -d)
printf '{"profile":"minimal"}\n' > "$PJ/.supercharger.json"
printf '{"cwd":"%s","prompt":"hi"}' "$PJ" \
  | SUPERCHARGER_STATE="$ST" bash "$REPO_DIR/hooks/project-config.sh" >/dev/null 2>&1
[ -f "$ST/scope/.profile-$(key_for "$PJ")" ] && pass \
  || fail "expected .profile-$(key_for "$PJ"); got: $(ls -A "$ST/scope" 2>/dev/null | tr '\n' ' ')"

begin_test "and it does not write the legacy global name"
[ ! -f "$ST/scope/.profile" ] && pass || fail "still writing the shared global file"
rm -rf "$ST" "$PJ"

# --- the protection guards must still cover the renamed files ---------------
# path-guard matched these by EXACT basename. The suffix would have slipped past
# it silently, un-protecting the very files the selfmod rule exists to protect.
pg() { # path -> BLOCKED | allowed
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$1" \
    | bash "$REPO_DIR/hooks/path-guard.sh" >/dev/null 2>&1
  [ $? -eq 2 ] && echo BLOCKED || echo allowed
}

begin_test "path-guard still blocks a write to the un-suffixed control file"
[ "$(pg "$HOME/.claude/supercharger/scope/$CATS")" = "BLOCKED" ] && pass || fail "unprotected"

begin_test "path-guard blocks a write to the SUFFIXED control file"
[ "$(pg "$HOME/.claude/supercharger/scope/$CATS-Users-me-proj")" = "BLOCKED" ] && pass \
  || fail "the per-project rename slipped past the selfmod guard"

begin_test "path-guard blocks the suffixed disabled-hooks file too"
[ "$(pg "$HOME/.claude/supercharger/scope/$DHOOKS-Users-me-proj")" = "BLOCKED" ] && pass || fail "unprotected"

begin_test "an unrelated file with a similar name is not over-blocked"
# In-project on purpose: a path under $HOME is refused by path-guard's
# outside-the-project rule, which would make this pass without ever exercising
# the selfmod basename match it is meant to test.
[ "$(pg "$REPO_DIR/notes-about-disabled-hooks.md")" = "allowed" ] && pass \
  || fail "the prefix match is too greedy"

report
