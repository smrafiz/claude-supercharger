#!/usr/bin/env bash
# Claude Supercharger — Harness Tamper Guard
# Event: PreToolUse | Matcher: Bash
#
# Self-defense on the BASH channel. path-guard protects .claude/settings.json and
# the hooks on the Write/Edit channel; safety.sh's `selfmod` category blocks Bash
# edits to the CONFIG files (settings.json / .supercharger.json / .disabled-hooks
# / …). Two gaps remain on the Bash channel, closed here:
#   1. `claude --dangerously-skip-permissions` (or --permission-mode bypassPermissions)
#      spawns an UNGUARDED sub-instance — an agent must not launch one.
#   2. rm / mv / chmod -x / truncate / redirect against the HOOK SCRIPTS or the
#      install dir (…/supercharger/hooks/*, .claude/hooks/*, plugin hooks dir) or
#      the kill-switch file (.supercharger-disabled) tears the layer down — the
#      selfmod filename list does not cover the scripts/dir themselves.
# Blocks (deny). Fail-open; disable with SUPERCHARGER_HARNESS_TAMPER_GUARD=0.
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_HARNESS_TAMPER_GUARD:-1}" = "0" ] && exit 0

_INPUT=$(cat)

# Fast-path: only the commands that could plausibly tamper carry one of these
# tokens. Everything else exits before the (cheap) parse. Fail-safe: the tokens
# are a superset of every target pattern matched below.
# v2.23.10: use the SPECIFIC install-path forms, not a bare `*supercharger*` —
# that matched the "supercharger" substring in the cwd field for anyone working
# in this repo or the install dir (~/.claude/supercharger), defeating the early
# exit (~6ms tax on every Bash call there). These forms still cover every
# _HT_TARGET pattern below but no longer match a plain `claude-supercharger` cwd.
case "$_INPUT" in
  *dangerously-skip-permissions*|*permission-mode*|*--settings*|*--mcp-config*|*supercharger/hooks*|*supercharger-disabled*|*.claude/supercharger*|*.claude/hooks*|*.claude/plugins*) : ;;
  *) exit 0 ;;
esac

check_hook_disabled "harness-tamper-guard" 2>/dev/null && exit 0

CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // .tool_input.script // empty' 2>/dev/null || true)
if [ -z "$CMD" ]; then
  CMD=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json;ti=json.load(sys.stdin).get('tool_input',{});print(ti.get('command') or ti.get('script') or '')" 2>/dev/null || echo "")
fi
[ -z "$CMD" ] && exit 0

REASON=""

# (1) Launching an unguarded / reconfigured Claude instance.
case "$CMD" in
  *--dangerously-skip-permissions*|*--allow-dangerously-skip-permissions*)  # v2.23.26: +allow- variant
    REASON="launches Claude with a dangerously-skip-permissions flag, which spawns an instance with NO permission prompts and NO guardrails. An agent must not start an unguarded sub-instance." ;;
esac
if [ -z "$REASON" ]; then
  # --permission-mode bypassPermissions (flag + value, any spacing/quoting)
  if printf '%s' "$CMD" | grep -Eq -- '--permission-mode[[:space:]=]+["'\'']?bypassPermissions'; then
    REASON="sets --permission-mode bypassPermissions — spawns an unguarded Claude instance. An agent must not disable its own permission layer."
  fi
fi
if [ -z "$REASON" ]; then
  # v2.23.26: inline --settings/--mcp-config JSON to `claude` DEFINES hooks / MCP
  # servers (code execution) WITHOUT writing a file — bypassing path-guard's
  # settings.json/.mcp.json write guards. The value being inline JSON (starts with
  # `{`) is the smuggling signal; a plain `--settings ./file.json` is left alone.
  if printf '%s' "$CMD" | grep -Eq -- 'claude\b[^|;&]*--(settings|mcp-config)[[:space:]=]+["'\'']?\{'; then
    REASON="passes inline --settings/--mcp-config JSON to claude — this defines hooks or MCP servers (arbitrary code execution) on a sub-instance without writing a file, bypassing the file-write guardrails. Use a reviewed settings/config FILE, not inline JSON."
  fi
fi

# (2) Destroying / disabling the hook scripts, install dir, or kill-switch file.
if [ -z "$REASON" ]; then
  # Target: the installed hook scripts / supercharger dir / plugin hooks / kill switch.
  # Scoped to installed locations (.claude / …/supercharger/…) so a repo-relative
  # `chmod +x hooks/foo.sh` during development does NOT match.
  # v2.24.9: the install-dir arm was `\.claude/supercharger([/[:space:]]|$)`, i.e.
  # ANY path beneath the install dir — including the audit LOGS and the scope
  # SENTINELS, neither of which is part of the guardrail layer. Combined with the
  # verb/target tests matching independently (and on different LINES of a compound
  # command), reading an audit log in the same command as any `touch`/`rm` was
  # denied. Now: the CODE dirs (hooks/lib/tools) match per-file, the install dir and
  # the data dirs match only as whole DIRECTORIES, and the kill-switch keeps its own
  # arm. So `rm -rf …/supercharger`, `rm -rf …/scope` and overwriting a hook are all
  # still blocked, while reading …/audit/<log> and writing …/scope/<sentinel> pass.
  # v2.24.14: the code-dir arms required a trailing slash, so the bare directory
  # (`cd ~/.claude/supercharger/hooks`) did not match and the two-step `cd … ; rm -rf .`
  # attack slipped past. Now `(hooks|lib|tools)` also matches at a space or end.
  _HT_TARGET='(\.claude/supercharger/(hooks|lib|tools)(/|[[:space:]]|$)|/supercharger/(hooks|lib|tools)(/|[[:space:]]|$)|\.claude/hooks/|\.claude/plugins/[^;&|]*/hooks/|\.claude/supercharger/?([[:space:]]|$)|\.claude/supercharger/(scope|audit)/?([[:space:]]|$)|\.supercharger-disabled)'
  # v2.23.22: PowerShell cmdlet verbs added for cross-channel parity (matcher now
  # Bash,PowerShell) — Remove-Item/Move-Item/Rename-Item/Clear-Content/Set-Content/
  # Out-File are the PowerShell equivalents of rm/mv/truncate/redirect over the hooks.
  # v2.24.6: `ln` required a following `-flag` or a `/`-bearing path. As a bare
  # two-letter alternation it matched the extremely common loop variable in an
  # inlined script (`for ln in open(f):`), and since the verb and target tests are
  # independent — either may match on ANY line — a purely READ-ONLY command that
  # merely mentioned the install dir was denied. Same class as the `cat
  # scope/.disabled-hooks` false positive already fixed in safety.sh's selfmod.
  # v2.24.14: the verb list only covered DELETE/EDIT-in-place. Every way of writing a
  # NEW file over a hook was missing, so each of these replaced safety.sh outright and
  # no guard in the chain objected:
  #   cp / install / rsync / scp <evil> …/hooks/safety.sh
  #   curl -o …/hooks/safety.sh https://…      wget -O …
  #   perl -pi -e … …/hooks/safety.sh
  #   python3 -c "open('…/hooks/safety.sh','w').write(…)"
  # The download forms are the sharpest: one command swaps a guard for attacker
  # content. Interpreter one-liners are only a verb when the segment ALSO carries a
  # write indicator, so reading a hook through python stays allowed.
  # cp/install/rsync/scp are handled separately (see _HT_COPY) because for those the
  # protected path is only dangerous as the DESTINATION — `cp <hook> /tmp/inspect.sh`
  # copies a hook OUT, which is a read. `mv` stays here: moving a hook out removes it
  # from hooks/, so either position is destructive.
  _HT_VERB='(^|[[:space:];&|(])(rm|unlink|mv|truncate|shred|chmod|chattr|touch|sed[[:space:]]+-i|tee|dd[[:space:]]+of=|:[[:space:]]*>|>>?|Remove-Item|Move-Item|Rename-Item|Copy-Item|Clear-Content|Set-Content|Add-Content|Out-File|Invoke-WebRequest)([[:space:]]|>)'
  # Copy-family: destination-sensitive, checked against the final token of the segment.
  _HT_COPY='(^|[[:space:];&|(])(cp|install|rsync|scp)([[:space:]])'
  _HT_VERB="$_HT_VERB"'|(^|[[:space:];&|(])ln[[:space:]]+(-|[^[:space:]]*/)'
  _HT_VERB="$_HT_VERB"'|(^|[[:space:];&|(])curl[^;&|]*[[:space:]]-(o|O|-output)([[:space:]]|=)'
  _HT_VERB="$_HT_VERB"'|(^|[[:space:];&|(])wget[^;&|]*[[:space:]]-(O|-output-document)([[:space:]]|=)'
  _HT_VERB="$_HT_VERB"'|(^|[[:space:];&|(])perl[[:space:]]+-[a-zA-Z]*i'
  _HT_VERB="$_HT_VERB"'|(^|[[:space:];&|(])(python3?|node|ruby)[[:space:]]+-[ce][^;&|]*(open\([^)]*,[[:space:]]*.(w|a)|\.write\(|writeFileSync|truncate)'
  # Writing a scope SENTINEL is normal, documented operation — /perf tells users to
  # `touch …/scope/.profiling`, and autopilot/readonly/strict/profile write flags
  # there constantly. That is handled by _HT_TARGET above matching scope/ only as a
  # whole directory, so no separate stripping pass is needed.
  # .disabled-hooks / .disabled-security-categories stay covered by safety.sh's
  # selfmod category, which is independent of this guard.
  # v2.24.14: pair the verb with the target in the SAME command segment.
  #
  # The two tests used to run independently over the whole command — verb anywhere,
  # target anywhere, including on different lines. That is why an unrelated `rm` in a
  # compound command turned a legitimate write into a denial (hit repeatedly while
  # deploying), and it is the same looseness that made the guard feel arbitrary: it
  # was not checking what was written where, only that both words appeared.
  #
  # Segments split on ; && || | and newline. A destructive verb aimed at a protected
  # path now has to actually be aimed at it.
  #
  # The one thing segment-scoping would otherwise lose is the two-step form:
  #     cd ~/.claude/supercharger/hooks
  #     rm -rf .
  # where no single segment names the target. That is handled explicitly: once a
  # segment cd's INTO a protected directory, any later destructive verb counts.
  # Patterns go through ENVIRON, NOT awk -v: -v runs escape processing on the value,
  # which rewrote `open\(` to `open(` — an unbalanced group. awk then died on the
  # invalid regex and printed nothing, so the guard silently allowed EVERYTHING,
  # including `rm <hook>`. ENVIRON values are passed through verbatim.
  _HT_HIT=$(_HT_V="$_HT_VERB" _HT_T="$_HT_TARGET" _HT_C="$_HT_COPY" ; export _HT_V _HT_T _HT_C; printf '%s' "$CMD" \
    | sed -E 's/(&&|\|\||;|\|)/\'$'\n''/g' \
    | awk '
        BEGIN { v = ENVIRON["_HT_V"]; t = ENVIRON["_HT_T"]; c = ENVIRON["_HT_C"]
                cd_in = 0; hit = 0 }
        {
          seg = $0
          # `cd` INTO a protected dir arms the next destructive verb (the two-step
          # form no single segment names).
          if (seg ~ /(^|[[:space:]])cd[[:space:]]/ && seg ~ t) { cd_in = 1; next }
          if (cd_in && (seg ~ v || seg ~ c)) { hit = 1 }
          if (seg ~ c) {
            # Copy-family: only the DESTINATION counts. Strip a trailing redirect so
            # `cp a b > log` still resolves the destination correctly.
            n = split(seg, a, /[[:space:]]+/)
            if (n > 0 && a[n] ~ t) { hit = 1 }
          } else if (seg ~ v && seg ~ t) { hit = 1 }
        }
        END { print hit }')
  if [ "$_HT_HIT" = "1" ]; then
    REASON="removes, disables, or overwrites Supercharger hook scripts / install dir / kill-switch — this tears down the guardrail layer. Use the documented controls (/sc off, hook-toggle.sh, SUPERCHARGER_* env) instead of editing the harness from the shell."
  fi
fi

[ -z "$REASON" ] && exit 0

RSN=$(printf '%s' "harness-tamper: $REASON" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$REASON")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
echo "[Supercharger] harness-tamper-guard: DENY — $REASON" >&2

# Log to the block ledger for /why and audits (best-effort).
_BLK="$SUPERCHARGER_STATE/scope/.blocked-commands"
mkdir -p "$(dirname "$_BLK")" 2>/dev/null || true
printf '[%s] harness-tamper — %s — %.120s\n' "$(date '+%Y-%m-%dT%H:%M:%SZ')" "guardrail teardown" "$CMD" >> "$_BLK" 2>/dev/null || true

exit 2
