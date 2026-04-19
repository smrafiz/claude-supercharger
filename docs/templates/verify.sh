#!/usr/bin/env bash
# Project verification script for Claude Supercharger
# Place this file at .claude/verify.sh in your project root.
#
# Claude runs this automatically when it stops after modifying files.
# If it exits non-zero, Claude sees the output and continues fixing.
#
# Uncomment and adapt the lines that match your project:

set -euo pipefail

# --- Node / JavaScript ---
# npm test
# npm run lint
# pnpm test && pnpm run lint
# npx tsc --noEmit

# --- Python ---
# pytest
# ruff check .
# mypy .

# --- Go ---
# go test ./...
# go vet ./...

# --- Rust ---
# cargo test
# cargo clippy -- -D warnings

# --- Ruby ---
# bundle exec rspec
# bundle exec rubocop

# --- Generic make ---
# make test
# make lint

# Example: run tests then type-check
# npm test && npx tsc --noEmit
