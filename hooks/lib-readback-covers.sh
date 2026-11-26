#!/usr/bin/env bash
# Claude Supercharger — readback covers file (sourced by project-config.sh at SessionStart).
#
# Contract with the readback plugin: when READBACK.md is at ${CLAUDE_PROJECT_DIR:-$PWD},
# write $HOME/.claude/readback-covers/<sid> (sid = session id with only [A-Za-z0-9-]),
# one guard name per line, listing only guards that are ACTIVE for this project after
# every disable. Readback stands down for a name that is present. Empty file = nothing
# covered (safe: readback keeps its own hooks). The file is a start-of-session snapshot;
# /sc off and /sc on empty it (tools/sc-toggle.sh).
#
# Each predicate below mirrors that hook's OWN disable logic, nothing more:
#   test-integrity-guard  env SUPERCHARGER_TEST_INTEGRITY_GUARD=0, .disabled-hooks
#   test-mask-guard       env SUPERCHARGER_TEST_MASK_GUARD=0, .disabled-hooks, hook_profile_skip
#   claim-evidence-gate   env SUPERCHARGER_CLAIM_EVIDENCE_GATE=0 only (it does not read .disabled-hooks)
#   failure-tracker       .disabled-hooks, profile fast/minimal
# All four also need a live registration (sc_rb_registered) and no disableAllHooks.
# Needs lib-suppress.sh (check_hook_disabled, hook_profile_skip, _load_disabled_hooks) and
# lib-readback.sh (sc_rb_dir) sourced first.

# 0 when the hook can fire: plugin runtime, or an active (not "# "-commented by
# tools/hook-toggle.sh) command naming it in the user's settings.json.
sc_rb_registered() {
  [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && return 0
  local f="$HOME/.claude/settings.json" l
  [ -f "$f" ] || return 1
  while IFS= read -r l; do
    case "$l" in
      *'"command"'*)
        case "$l" in
          *'"command": "# '*|*'"command":"# '*) ;;
          *) return 0 ;;
        esac ;;
    esac
  done < <(grep -F "/$1.sh" "$f" 2>/dev/null || true)
  return 1
}

# 0 when any settings file turns every hook off ("disableAllHooks": true).
sc_rb_all_hooks_off() {
  local f
  for f in "$HOME/.claude/settings.json" "$1/.claude/settings.json" "$1/.claude/settings.local.json"; do
    [ -f "$f" ] || continue
    if grep -Eq '"disableAllHooks"[[:space:]]*:[[:space:]]*true' "$f" 2>/dev/null; then return 0; fi
  done
  return 1
}

# sc_rb_write_covers PROJECT_DIR SID...   (SIDs are untrusted: sanitised; blanks and dups skipped)
sc_rb_write_covers() {
  local dir="$1"; shift
  sc_rb_dir
  [ -n "$SC_RB_DIR" ] || return 0

  local names="" prof=""
  if ! sc_rb_all_hooks_off "$SC_RB_DIR"; then
    _load_disabled_hooks "$dir"
    # The profile file is rewritten by project-config just before this runs, so the value
    # lib-suppress cached at source time can be stale. An exported env value still wins.
    case "$(declare -p SUPERCHARGER_PROFILE 2>/dev/null)" in
      "declare -x"*) prof="${SUPERCHARGER_PROFILE:-}" ;;
    esac
    if [ -z "$prof" ] && type sc_scope_resolve >/dev/null 2>&1; then
      sc_scope_resolve ".profile" "$dir"
      [ -f "$SC_SCOPE_FILE" ] && prof=$(<"$SC_SCOPE_FILE")
    fi
    SUPERCHARGER_PROFILE="$prof"

    if [ "${SUPERCHARGER_TEST_INTEGRITY_GUARD:-1}" != "0" ] \
       && ! check_hook_disabled "test-integrity-guard" && sc_rb_registered "test-integrity-guard"; then
      names="${names}test-integrity-guard"$'\n'
    fi
    if [ "${SUPERCHARGER_TEST_MASK_GUARD:-1}" != "0" ] \
       && ! check_hook_disabled "test-mask-guard" && ! hook_profile_skip "test-mask-guard" \
       && sc_rb_registered "test-mask-guard"; then
      names="${names}test-mask-guard"$'\n'
    fi
    if [ "${SUPERCHARGER_CLAIM_EVIDENCE_GATE:-1}" != "0" ] && sc_rb_registered "claim-evidence-gate"; then
      names="${names}claim-evidence-gate"$'\n'
    fi
    if ! check_hook_disabled "failure-tracker" && ! hook_profile_skip "failure-tracker" \
       && sc_rb_registered "failure-tracker"; then
      names="${names}failure-tracker"$'\n'
    fi
  fi

  local cdir="$HOME/.claude/readback-covers" s seen=" "
  mkdir -p "$cdir" 2>/dev/null || return 0
  for s in "$@"; do
    s="${s//[!A-Za-z0-9-]/}"
    [ -z "$s" ] && continue
    case "$seen" in *" $s "*) continue ;; esac
    seen="$seen$s "
    # temp + mv so a reader never sees a half-written list
    if printf '%s' "$names" > "$cdir/.$s.$$" 2>/dev/null; then
      mv -f "$cdir/.$s.$$" "$cdir/$s" 2>/dev/null || rm -f "$cdir/.$s.$$" 2>/dev/null
    fi
  done
  # Prune: a session file older than 7 days is dead weight.
  find "$cdir" -type f -mtime +7 -delete 2>/dev/null || true
  return 0
}
