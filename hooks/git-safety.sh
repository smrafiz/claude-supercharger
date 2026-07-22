#!/usr/bin/env bash
# Claude Supercharger — Git Safety Hook
# Event: PreToolUse | Matcher: Bash (git *)
set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)

# v2.6.16: bash fast-path before jq + sourcing cmd-normalize. Only the
# destructive git verbs (push/reset/checkout/restore/clean/branch -D/
# stash drop|clear) and `git commit` (for the checkpoint message at the
# bottom) can trigger any output. If none of those tokens appears in the
# raw stdin, exit immediately — no jq, no python, no source.
case "$_INPUT" in
  *push*|*reset*|*checkout*|*restore*|*clean*|*"branch -D"*|*"stash drop"*|*"stash clear"*|*commit*) ;;
  *) exit 0 ;;
esac

PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
if [ -z "$COMMAND" ]; then
  COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
fi

if [ -z "$COMMAND" ]; then
  exit 0
fi

source "${BASH_SOURCE[0]%/*}/cmd-normalize.sh"
CMD=$(normalize_cmd "$COMMAND")

# Per-segment view for ^-anchored git checks — protects against compound bypass
# like `safe && git push --force origin main`. Falls back to CMD if split fails.
SEGMENTS=$(split_segments "$CMD")
[ -z "$SEGMENTS" ] && SEGMENTS="$CMD"

block() {
  echo "" >&2
  echo "Supercharger blocked this git operation." >&2
  echo "  Reason : $1" >&2
  echo "  Command: $COMMAND" >&2
  echo "  Override: if this is intentional, run it in your terminal directly. Git-safety" >&2
  echo "            blocks are absolute by design — destructive git ops have no per-project" >&2
  echo "            opt-out (the whole point is they should never run from an agent)." >&2
  echo "" >&2
  local blocks_log="$SUPERCHARGER_STATE/scope/.blocked-commands"
  mkdir -p "$(dirname "$blocks_log")" 2>/dev/null || true
  local safe_cmd="${COMMAND:0:120}"
  printf '[%s] %s — %s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" "$safe_cmd" >> "$blocks_log" 2>/dev/null || true
  # v2.7.23: cap the log (was unbounded append — grew to 3.4MB). Keep last 500.
  if [ "$(wc -l < "$blocks_log" 2>/dev/null || echo 0)" -gt 600 ]; then
    tail -n 500 "$blocks_log" > "$blocks_log.tmp" 2>/dev/null && mv "$blocks_log.tmp" "$blocks_log" 2>/dev/null || true
  fi
  RSN=$(printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$1")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

# INVARIANT: this is the only hook in the codebase that emits
# `hookSpecificOutput.updatedInput`. Per CC architecture chapter 05 §7,
# `updatedInput` is LAST-WRITE-WINS across hooks on the same event — if
# another hook on PreToolUse:Bash later emits updatedInput, this rewrite
# is silently discarded with no error. Before adding a second updatedInput
# emitter, verify the registration order in lib/hooks.sh and either: (a)
# coordinate the rewrites, or (b) move git-safety.sh to be registered last
# so its rewrite is the surviving one.
rewrite() {
  local safe_cmd="$1" reason="$2"
  echo "[Supercharger] git-safety: rewrote unsafe command — ${reason}" >&2
  local cmd_json
  cmd_json=$(printf '%s' "$safe_cmd" | jq -Rs '.' 2>/dev/null || \
             printf '%s' "$safe_cmd" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)
  if [ -z "$cmd_json" ]; then
    # Last-resort fallback: deny instead of emitting malformed JSON
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"git-safety: %s (rewriter unavailable, please run safely)"}}\n' "$reason"
    exit 2
  fi
  # v2.7.55: include hookEventName — a hookSpecificOutput without it is dropped by
  # CC (verified class, v2.7.30), which would silently discard this rewrite and let
  # the original unsafe command run. The deny/fallback paths above already carry it.
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":%s}}}\n' "$cmd_json"
  exit 0
}

while IFS= read -r seg; do
  [ -z "$seg" ] && continue

  # v2.9.6: block git hook-bypass — an agent must not skip the repo's
  # pre-commit/pre-push verification (lint/test/format). Two vectors:
  #   (a) --no-verify / -n (commit) and --no-verify (push)
  #   (b) `-c core.hooksPath=<x>` inline-config override that disables ALL git hooks
  # Test flags on a quote-stripped copy so a commit MESSAGE mentioning "-n" or
  # "--no-verify" (e.g. -m "document --no-verify") is not falsely blocked. NOTE:
  # `git push -n` is --dry-run (harmless), so -n is blocked for commit only.
  seg_flags=$(printf '%s' "$seg" | sed -E 's/"[^"]*"//g; s/'\''[^'\'']*'\''//g')
  if [[ "$seg" =~ ^git[[:space:]] ]]; then
    seg_lc=$(printf '%s' "$seg_flags" | tr '[:upper:]' '[:lower:]')
    if [[ "$seg_lc" =~ (^|[[:space:]])-c[[:space:]]+core\.hookspath[=[:space:]] ]]; then
      block "git -c core.hooksPath= disables git hooks — verification bypass"
    fi
  fi
  if [[ "$seg" =~ ^git\ commit([[:space:]]|$) ]] && \
     { [[ "$seg_flags" =~ (^|[[:space:]])--no-verify([[:space:]]|$) ]] || \
       [[ "$seg_flags" =~ (^|[[:space:]])-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$) ]]; }; then
    block "git commit --no-verify/-n skips pre-commit hooks — verification bypass"
  fi
  if [[ "$seg" =~ ^git\ push([[:space:]]|$) ]] && \
     [[ "$seg_flags" =~ (^|[[:space:]])--no-verify([[:space:]]|$) ]]; then
    block "git push --no-verify skips pre-push hooks — verification bypass"
  fi

  if [[ "$seg" =~ ^git\ push[[:space:]] ]]; then
    has_force=false
    has_protected=false

    # v2.6.77: also match --force-with-lease=<ref> form. Previously the
    # trailing `([[:space:]]|$)` required a space/EOL after the flag, so
    # `git push --force-with-lease=origin/main main` was not detected and
    # force-push to protected branches bypassed the gate.
    if [[ "$seg" =~ (^|[[:space:]])(--force|--force-with-lease(=[^[:space:]]*)?|-f)([[:space:]]|$) ]]; then
      has_force=true
    fi
    # v2.7.41: `git push origin +main` / `+HEAD:master` — the leading-`+` refspec
    # is git's native force-push and needs no --force flag, so it slipped past the
    # flag check above and force-pushed to protected branches.
    if [[ "$seg" =~ push ]] && [[ "$seg" =~ (^|[[:space:]])[+][A-Za-z0-9_/.:-]+([[:space:]]|$) ]]; then
      has_force=true
      # v2.8.8: parity with mcp-github-write-gate's protected set — the leading-`+`
      # refspec is a native force-push the de-force rewrite CAN'T neutralize (it
      # strips flags, not the `+`), so `git push origin +production` slipped through
      # while `+main`/`+master` were caught. Match production/prod/release too.
      if [[ "$seg" =~ [+]([^[:space:]]*:)?(refs/heads/)?(main|master|production|prod|release)(/[A-Za-z0-9._-]+)?([[:space:]]|$) ]]; then
        has_protected=true
      fi
    fi

    # 2.21.10: match the SAME protected set as the leading-`+` refspec path above,
    # so `git push --force origin production` is blocked, not just `+production`.
    # Previously this bare-name check was main|master only, so a `--force`/`-f`
    # push to production/prod/release slipped through (de-forced, but the parity
    # gap meant the deliberate-block intent didn't fire).
    if [[ "$seg" =~ (^|[[:space:]])(main|master|production|prod|release)([[:space:]]|$) ]]; then
      has_protected=true
    fi

    if $has_force && $has_protected; then
      block "force push to protected branch"
    elif $has_force; then
      # Non-protected branch — strip force flag, push safely.
      # Only rewrite when the whole command is the single git push (no compound).
      if [ "$CMD" = "$seg" ]; then
        safe=$(printf '%s\n' "$CMD" | sed -E 's/(^|[[:space:]])(--force-with-lease|--force|-f)([[:space:]]|$)/ /g' | tr -s ' ' | sed 's/[[:space:]]*$//')
        rewrite "$safe" "stripped --force from non-protected branch push"
      fi
    fi
  fi

  if [[ "$seg" =~ ^git\ reset[[:space:]] ]] && [[ "$seg" =~ (^|[[:space:]])--hard([[:space:]]|$) ]]; then
    block "git reset --hard can destroy uncommitted work"
  fi

  if [[ "$seg" =~ ^git\ (checkout|restore)[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$) ]]; then
    block "discards all unstaged changes"
  fi

  # git checkout <ref> -- .   /   git checkout <ref> .  → overwrites working tree from <ref>,
  # silently destroying unstaged work. Real-world loss reported in claude-code#55024.
  if [[ "$seg" =~ ^git\ checkout[[:space:]]+[^[:space:]-][^[:space:]]*[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$) ]]; then
    block "git checkout <ref> -- . overwrites all working-tree files from <ref>, destroying unstaged work"
  fi

  # v2.10.8: git checkout -- <path>  (NO ref before `--`) → discards uncommitted
  # changes to a specific file. This is pure local-work destruction with no
  # constructive intent, unlike `git checkout <ref> -- <path>` (grab a file from
  # another ref), which is deliberately left allowed above. The `--[[:space:]]`
  # requirement stays clear of `--patch`/`--theirs` (no space after `--`) and of
  # branch ops (`checkout -b`, `checkout <branch>`). From kenryu42/cc-safety-net.
  if [[ "$seg" =~ ^git\ checkout[[:space:]]+--[[:space:]]+[^[:space:]] ]]; then
    block "git checkout -- <path> discards uncommitted changes to those files"
  fi

  # git restore --source=<ref> .   → overwrites the WHOLE working tree from <ref>
  # (whole-tree form stays blocked; `--source=<ref> <file>` grab is allowed below).
  if [[ "$seg" =~ ^git\ restore[[:space:]] ]] && [[ "$seg" =~ --source[=[:space:]] ]] && [[ "$seg" =~ [[:space:]]\.([[:space:]]|$) ]]; then
    block "git restore --source=<ref> . overwrites working tree from <ref>, destroying unstaged work"
  fi

  # v2.10.8: git restore <path>  (no --source, no --staged) → the modern form of
  # `checkout -- <path>`: discards working-tree changes. `--source=<ref>` (grab from
  # a ref, mirrors the allowed checkout <ref> -- <path>) and `--staged` (unstage,
  # worktree untouched) are both left allowed; whole-tree `.` forms are caught above.
  if [[ "$seg" =~ ^git\ restore[[:space:]] ]] \
     && ! [[ "$seg" =~ (^|[[:space:]])--staged([[:space:]]|$) ]] \
     && ! [[ "$seg" =~ (^|[[:space:]])--source[=[:space:]] ]]; then
    block "git restore <path> discards uncommitted working-tree changes"
  fi

  if [[ "$seg" =~ ^git\ clean[[:space:]] ]] && [[ "$seg" =~ (^|[[:space:]])(--force|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$) ]]; then
    block "git clean with force permanently removes untracked files"
  fi

  if [[ "$seg" =~ ^git\ branch[[:space:]] ]] && [[ "$seg" =~ (^|[[:space:]])-D([[:space:]]|$) ]]; then
    if [[ "$seg" =~ (^|[[:space:]])(main|master)([[:space:]]|$) ]]; then
      block "force-deleting a protected branch (main/master)"
    fi
  fi

  if [[ "$seg" =~ ^git\ stash\ (drop|clear)([[:space:]]|$) ]]; then
    block "git stash drop/clear permanently removes stashed changes"
  fi
done <<< "$SEGMENTS"


# Checkpoint before commit — warn if unstaged/untracked work exists
if [[ "$CMD" =~ ^git\ commit([[:space:]]|$) ]]; then
  UNSTAGED=$(git diff --name-only 2>/dev/null | grep -v '^$' || true)
  UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | grep -v '^$' | head -10 || true)
  WARNINGS=()
  [ -n "$UNSTAGED" ] && WARNINGS+=("Unstaged changes: $(printf '%s' "$UNSTAGED" | tr '\n' ' ' | sed 's/ *$//')")
  [ -n "$UNTRACKED" ] && WARNINGS+=("Untracked files: $(printf '%s' "$UNTRACKED" | tr '\n' ' ' | sed 's/ *$//')")
  if [ ${#WARNINGS[@]} -gt 0 ]; then
    MSG="[CHECKPOINT] Committing with uncommitted work present. ${WARNINGS[*]} — confirm these are intentionally excluded."
    CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
      || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
    printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$CONTEXT_JSON" "$HOOK_SUPPRESS"
    echo "[Supercharger] git-safety: checkpoint — unstaged/untracked work at commit time" >&2
  fi
fi

exit 0
