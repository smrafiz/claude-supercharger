#!/usr/bin/env bash
# Claude Supercharger — Extras Deployment (Full mode)

deploy_extras() {
  local source_dir="$1"
  local mode="$2"

  if [[ "$mode" != "full" ]]; then
    return 0
  fi

  if [ -f "$source_dir/shared/guardrails-template.yml" ]; then
    cp "$source_dir/shared/guardrails-template.yml" "$HOME/.claude/shared/"
    success "Guardrails template installed"
  fi

  if [ -f "$source_dir/tools/claude-check.sh" ]; then
    cp "$source_dir/tools/claude-check.sh" "$HOME/.claude/claude-check.sh"
    chmod +x "$HOME/.claude/claude-check.sh"
    success "claude-check diagnostic installed"
  fi

  echo ""
  info "MCP Server Setup"
  echo -e "  Configure MCP servers for enhanced Claude Code capabilities?"
  read -rp "  Run MCP setup? (y/N): " mcp_choice
  echo
  if [[ "$mcp_choice" =~ ^[Yy]$ ]]; then
    if [ -f "$source_dir/tools/mcp-setup.sh" ]; then
      bash "$source_dir/tools/mcp-setup.sh"
    else
      warn "MCP setup script not found"
    fi
  else
    info "Skipped MCP setup. Run tools/mcp-setup.sh later if needed."
  fi
}
