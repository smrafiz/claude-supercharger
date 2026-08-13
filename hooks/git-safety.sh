#!/usr/bin/env bash
# Claude Supercharger — Git Safety Hook
# Event: PreToolUse | Matcher: Bash (git *)
set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# v2.6.16: bash fast-path before jq + sourcing cmd-normalize. Only the
# destructive git verbs (push/reset/checkout/restore/clean/branch -D/
# stash drop|clear) and `git commit` (for the checkpoint message at the
# bottom) can trigger any output. If none of those tokens appears in the
# raw stdin, exit immediately — no jq, no python, no source.
# v2.26.30: the work-destroying family below adds verbs. A rule the gate does not
# admit never runs — the gate is the first thing to extend, not the last.
case "$_INPUT" in
  *push*|*reset*|*checkout*|*restore*|*clean*|*"branch -D"*|*"branch --delete"*|\
  *"stash drop"*|*"stash clear"*|*switch*|*reflog*|*prune*|*filter-branch*|\
  *filter-repo*|*worktree*|*rebase*|*"git replace"*|*update-ref*|*commit*) ;;
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
  # v2.26.17: collapse newlines/tabs BEFORE shortening. The ledger is line-based —
  # /why reads the last N lines and learn-from-blocks parses it into the [BLOCKS]
  # summary injected into every session. A multi-line command wrote a multi-line
  # entry, so a fragment like `rm -rf .` appeared as its own row and read as a real
  # destructive block. Shortening alone would still leave an embedded newline.
  local safe_cmd="$COMMAND"
  safe_cmd="${safe_cmd//$'\n'/ }"; safe_cmd="${safe_cmd//$'\r'/ }"; safe_cmd="${safe_cmd//$'\t'/ }"
  safe_cmd="${safe_cmd:0:400}"   # v2.26.67: see safety.sh — 120 starved /why, not context
  printf '[%s] %s — %s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" "$safe_cmd" >> "$blocks_log" 2>/dev/null || true
  # v2.7.23: cap the log (was unbounded append — grew to 3.4MB). Keep last 500.
  if [ "$(wc -l < "$blocks_log" 2>/dev/null || echo 0)" -gt 600 ]; then
    tail -n 500 "$blocks_log" > "$blocks_log.tmp" 2>/dev/null && mv "$blocks_log.tmp" "$blocks_log" 2>/dev/null || true
  fi
  RSN=$(printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$1")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

# v2.26.30: ASK, not deny, for operations that destroy work but have a real
# legitimate use (deleting a merged branch, rewriting history to strip a secret).
# Denying those trades one class of lost work for daily friction, and friction is
# what makes people uninstall a guard layer.
#
# The reason is RECORDED, not emitted, and the decision is issued after every
# segment has been examined. Emitting on the spot would exit the loop early, so
# `git gc --prune=now && git reflog expire --expire=now` would ask (soft) instead
# of blocking (hard) on the second half. block() still exits immediately, so a
# hard rule found in any later segment always wins over a recorded ask.
ASK_REASON=""
ask() {
  if [ -z "$ASK_REASON" ]; then ASK_REASON="$1"; fi
  return 0
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
    # 2.22.3: also treat a `:`-prefixed target as protected — `git push --force
    # origin HEAD:main` put `main` after a colon, so the space-anchored check
    # missed it and the (single-command-only) de-force rewrite let the compound
    # `git fetch && git push --force origin HEAD:main` through unmodified.
    if [[ "$seg" =~ (^|[[:space:]]|:)(main|master|production|prod|release)([[:space:]]|$) ]]; then
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

  if [[ "$seg" =~ ^git\ branch[[:space:]] ]] \
     && [[ "$seg" =~ (^|[[:space:]])(-D|--delete[[:space:]]+--force|--force[[:space:]]+--delete)([[:space:]]|$) ]]; then
    if [[ "$seg" =~ (^|[[:space:]])(main|master)([[:space:]]|$) ]]; then
      block "force-deleting a protected branch (main/master)"
    fi
    # v2.26.30: -D was only guarded for main/master. On any other branch it still
    # deletes unmerged commits — which is the entire difference from -d, since -d
    # refuses exactly that case.
    ask "git branch -D deletes the branch even if it holds unmerged commits (-d refuses in that case). Use -d unless you mean to discard them."
  fi

  if [[ "$seg" =~ ^git\ stash\ (drop|clear)([[:space:]]|$) ]]; then
    block "git stash drop/clear permanently removes stashed changes"
  fi

  # ---------------------------------------------------------------------------
  # v2.26.30: the rest of the work-destroying family. git-safety already owned
  # "do not destroy uncommitted work" (reset --hard, checkout -- ., restore,
  # stash drop, clean -f) but only some arms of it — these are the siblings that
  # reach the same outcome by another spelling.
  # ---------------------------------------------------------------------------

  # Force checkout/switch — identical effect to `git checkout -- .` (blocked
  # above), reached with a flag instead of a pathspec.
  if [[ "$seg" =~ ^git\ (checkout|switch)[[:space:]] ]] \
     && [[ "$seg" =~ (^|[[:space:]])(--force|--discard-changes|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$) ]]; then
    block "git checkout/switch --force overwrites the working tree, discarding all uncommitted changes"
  fi

  # THE recovery net. reset --hard, branch -D and a bad rebase are all survivable
  # because the reflog still points at the old commits. This is the command that
  # takes that away — and it is why blocking reset --hard alone was never enough.
  if [[ "$seg" =~ ^git\ reflog[[:space:]]+expire ]] \
     && [[ "$seg" =~ --expire(-unreachable)?=(now|all) ]]; then
    block "git reflog expire --expire=now destroys the reflog — the safety net that makes reset --hard, branch -D and a bad rebase recoverable"
  fi

  # Deleting a ref by hand bypasses every branch-deletion check above.
  if [[ "$seg" =~ ^git\ update-ref[[:space:]] ]] && [[ "$seg" =~ (^|[[:space:]])-d([[:space:]]|$) ]]; then
    block "git update-ref -d deletes a ref directly, bypassing branch-deletion safety"
  fi

  # Remote branch deletion — affects everyone else on the repo, not just here.
  if [[ "$seg" =~ ^git\ push[[:space:]] ]]; then
    if [[ "$seg" =~ (^|[[:space:]])(--delete|-d)([[:space:]]|$) ]]; then
      ask "git push --delete removes that branch on the remote, for everyone."
    elif [[ "$seg" =~ [[:space:]]:[^[:space:]]+ ]]; then
      # `git push origin :branch` is the older spelling of --delete. Anchored on a
      # LEADING space so `git push origin HEAD:main` (a normal push) is untouched.
      ask "git push origin :<branch> is the old spelling of --delete — it removes that branch on the remote."
    fi
  fi

  # Prunes unreachable objects immediately instead of after the grace period.
  if [[ "$seg" =~ ^git\ gc([[:space:]]|$) ]] && [[ "$seg" =~ --prune= ]]; then
    ask "git gc --prune=<now> discards unreachable objects immediately — anything not on a branch or in the reflog stops being recoverable."
  fi

  if [[ "$seg" =~ ^git\ (filter-branch|filter-repo)([[:space:]]|$) ]]; then
    ask "history rewrite: every downstream commit is replaced, and collaborators' clones diverge permanently."
  fi

  if [[ "$seg" =~ ^git\ worktree[[:space:]]+remove ]] \
     && [[ "$seg" =~ (^|[[:space:]])(--force|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$) ]]; then
    ask "git worktree remove --force discards uncommitted changes in that worktree."
  fi

  if [[ "$seg" =~ ^git\ rebase[[:space:]] ]] && [[ "$seg" =~ (^|[[:space:]])--skip([[:space:]]|$) ]]; then
    ask "git rebase --skip drops the current commit from the rebase entirely."
  fi

  if [[ "$seg" =~ ^git\ replace[[:space:]] ]] && [[ "$seg" =~ (^|[[:space:]])(--graft|-g)([[:space:]]|$) ]]; then
    ask "git replace --graft rewrites what history looks like without changing the objects — easy to forget it is in effect."
  fi
done <<< "$SEGMENTS"

# Issued only after every segment has been checked, so a hard block anywhere in a
# compound command still wins over an ask recorded earlier.
if [ -n "$ASK_REASON" ]; then
  echo "[Supercharger] git-safety: $ASK_REASON" >&2
  ASK_JSON=$(printf '%s' "$ASK_REASON" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
    || printf '"%s"' "$(printf '%s' "$ASK_REASON" | tr -d '"\\' | tr '\n' ' ')")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$ASK_JSON"
  exit 0
fi


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
