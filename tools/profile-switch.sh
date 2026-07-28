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
  local current="standard (default)" _sd
  if [ -n "$ENV_VAR" ]; then
    current="$ENV_VAR (env var — overrides file)"
  else
    while IFS= read -r _sd; do
      if [ -f "$_sd/.profile" ]; then current="$(cat "$_sd/.profile")"; break; fi
    done <<EOF
$(sc_scope_dirs)
EOF
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

# Write/clear .profile in EVERY scope dir a hook reads (classic + plugin), else the
# switch is a no-op on plugin installs (hooks read $CLAUDE_PLUGIN_DATA/scope).
while IFS= read -r _sd; do
  [ -n "$_sd" ] || continue
  mkdir -p "$_sd" 2>/dev/null || true
  if [ "$PROFILE" = "standard" ]; then
    rm -f "$_sd/.profile" 2>/dev/null || true
  else
    echo "$PROFILE" > "$_sd/.profile" 2>/dev/null || true
  fi
done <<EOF
$(sc_scope_dirs)
EOF

if [ "$PROFILE" = "standard" ]; then
  success "Profile reset to standard (default)"
else
  success "Profile switched to $PROFILE"
fi

info "Takes effect immediately (next hook invocation)."

if [ -n "$ENV_VAR" ]; then
  warn "SUPERCHARGER_PROFILE env var is set to '$ENV_VAR' — it overrides this setting."
fi
