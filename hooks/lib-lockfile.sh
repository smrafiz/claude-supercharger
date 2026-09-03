#!/usr/bin/env bash
# Claude Supercharger — Lockfile basename matcher (single source of truth)
# Used by lockfile-integrity-guard.sh (to ask before a hand-edit) AND
# lib-smart-approve.sh (to refuse auto-approval, so autopilot / the in-project
# Write allow-list can't swallow that ask). One list → no sibling-parity drift.
#
# is_lockfile_path "<path>"  → exit 0 if the basename is a known dependency lock,
#                              else exit 1. No output, no side effects.
# v4.0.25: compared LOWERCASED. macOS (APFS) and Windows (NTFS) are
# case-insensitive by default, so `Package-Lock.json` and `cargo.lock` are the same
# files as `package-lock.json` and `Cargo.lock` — and the case-sensitive list let
# every one of those spellings through, on both callers at once. Third instance of
# this class after editor-config-guard and critical-infra-guard (v4.0.24);
# `cargo.lock` is the one a person actually types.
is_lockfile_path() {
  local lbase="${1##*/}"
  lbase=$(printf '%s' "$lbase" | tr '[:upper:]' '[:lower:]')
  case "$lbase" in
    package-lock.json|npm-shrinkwrap.json|yarn.lock|pnpm-lock.yaml|bun.lockb|bun.lock|\
    cargo.lock|composer.lock|gemfile.lock|poetry.lock|pipfile.lock|go.sum|\
    packages.lock.json|pubspec.lock|mix.lock|flake.lock|gradle.lockfile|deno.lock)
      return 0 ;;
  esac
  return 1
}
