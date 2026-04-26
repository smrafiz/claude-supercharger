#!/usr/bin/env bash
set -euo pipefail

# Claude Supercharger — Switch Performance Profile
# Usage: profile-switch.sh [standard|fast|minimal]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

source "$REPO_DIR/lib/utils.sh"

SCOPE_DIR="$HOME/.claude/supercharger/scope"
PROFILE_FILE="$SCOPE_DIR/.profile"
ENV_VAR="${SUPERCHARGER_PROFILE:-}"

show_current() {
  local current="standard (default)"
  if [ -n "$ENV_VAR" ]; then
    current="$ENV_VAR (env var — overrides file)"
  elif [ -f "$PROFILE_FILE" ]; then
    current="$(cat "$PROFILE_FILE")"
  fi
  echo ""
  echo -e "  Current profile: ${GREEN}${current}${NC}"
  echo ""
  echo "  Profiles:"
  echo "    standard  — all hooks active (default)"
  echo "    fast      — skips 8 analytics hooks; keeps quality-gate + typecheck"
  echo "    minimal   — skips 11 non-security hooks; fastest response"
  echo ""
  echo "  Usage: profile-switch.sh [standard|fast|minimal]"
  echo ""
}

if [ $# -eq 0 ] || [[ "$1" == "--help" ]]; then
  show_current
  exit 0
fi

PROFILE=$(echo "$1" | tr '[:upper:]' '[:lower:]')

case "$PROFILE" in
  standard|fast|minimal) ;;
  *)
    error "Unknown profile: $PROFILE"
    echo "  Valid: standard, fast, minimal"
    exit 1
    ;;
esac

mkdir -p "$SCOPE_DIR"

if [ "$PROFILE" = "standard" ]; then
  rm -f "$PROFILE_FILE"
  success "Profile reset to standard (default)"
else
  echo "$PROFILE" > "$PROFILE_FILE"
  success "Profile switched to $PROFILE"
fi

info "Takes effect immediately (next hook invocation)."

if [ -n "$ENV_VAR" ]; then
  warn "SUPERCHARGER_PROFILE env var is set to '$ENV_VAR' — it overrides this setting."
fi
