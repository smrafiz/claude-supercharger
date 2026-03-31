#!/usr/bin/env bash
# Claude Supercharger — Backup/Restore Functions

create_backup() {
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  BACKUP_DIR="$HOME/.claude/backups/$timestamp"
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"

  if [ -d "$HOME/.claude" ]; then
    cp "$HOME/.claude/"*.md "$BACKUP_DIR/" 2>/dev/null || true
    if [ -d "$HOME/.claude/rules" ]; then
      cp -r "$HOME/.claude/rules" "$BACKUP_DIR/" 2>/dev/null || true
    fi
    if [ -d "$HOME/.claude/shared" ]; then
      cp -r "$HOME/.claude/shared" "$BACKUP_DIR/" 2>/dev/null || true
    fi
    if [ -f "$HOME/.claude/settings.json" ]; then
      cp "$HOME/.claude/settings.json" "$BACKUP_DIR/" 2>/dev/null || true
    fi
  fi

  success "Backed up ~/.claude/ to $BACKUP_DIR/"
}

find_latest_backup() {
  local latest=""
  if [ -d "$HOME/.claude/backups" ]; then
    for d in "$HOME/.claude/backups"/*/; do
      [ -d "$d" ] && latest="$d"
    done
  fi
  echo "$latest"
}

restore_backup() {
  local backup_dir="$1"
  if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
    warn "No backup found to restore"
    return 1
  fi

  cp "$backup_dir"*.md "$HOME/.claude/" 2>/dev/null || true
  if [ -d "${backup_dir}rules" ]; then
    cp -r "${backup_dir}rules" "$HOME/.claude/" 2>/dev/null || true
  fi
  if [ -d "${backup_dir}shared" ]; then
    cp -r "${backup_dir}shared" "$HOME/.claude/" 2>/dev/null || true
  fi
  if [ -f "${backup_dir}settings.json" ]; then
    cp "${backup_dir}settings.json" "$HOME/.claude/" 2>/dev/null || true
  fi

  success "Restored from backup"
}
