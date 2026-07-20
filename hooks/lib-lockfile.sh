#!/usr/bin/env bash
# Claude Supercharger — Lockfile basename matcher (single source of truth)
# Used by lockfile-integrity-guard.sh (to ask before a hand-edit) AND
# lib-smart-approve.sh (to refuse auto-approval, so autopilot / the in-project
# Write allow-list can't swallow that ask). One list → no sibling-parity drift.
#
# is_lockfile_path "<path>"  → exit 0 if the basename is a known dependency lock,
#                              else exit 1. No output, no side effects.
is_lockfile_path() {
  case "${1##*/}" in
    package-lock.json|npm-shrinkwrap.json|yarn.lock|pnpm-lock.yaml|bun.lockb|bun.lock|\
    Cargo.lock|composer.lock|Gemfile.lock|poetry.lock|Pipfile.lock|go.sum|\
    packages.lock.json|pubspec.lock|mix.lock|flake.lock|gradle.lockfile|deno.lock)
      return 0 ;;
  esac
  return 1
}
