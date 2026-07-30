#!/usr/bin/env bash
# Matcher validity — a registered matcher must be able to match something (v2.24.15)
#
# The gap this closes, stated precisely: two existing checks pass while a hook is
# completely inert.
#   test-orphan-registration  — asserts the hook IS REGISTERED.
#   test-hook-liveness        — asserts the hook RESPONDS when invoked directly.
#   neither                   — asserts the matcher SELECTS ANY REAL TOOL.
#
# That is exactly how v2.24.5 happened: `mcp-egress-guard` was registered, worked
# when invoked, and never ran, because `matcher: "mcp__"` asks for a tool literally
# NAMED "mcp__". Claude Code decides matcher mode from the matcher's own characters —
# a matcher of only [A-Za-z0-9_,| -] is an EXACT match (optionally a list); anything
# else is an unanchored regex. An unmatched matcher fires nothing and errors nothing,
# so 13 registrations sat dead, including a security guard.
#
# Two rules, deliberately different in strength:
#
#   RULE 1 (structural, version-independent) — every token must be CAPABLE of
#   matching. An `mcp__…` token with no regex metacharacter can only match a tool
#   with that exact literal name, which no server exposes. This is what would have
#   caught v2.24.5, and it holds regardless of which Claude Code version runs.
#
#   RULE 2 (membership, version-sensitive) — every plain token must be a tool name we
#   recognise, which catches typos (`Bahs`, `WriteFile`). Because the tool set differs
#   across Claude Code versions and platforms, tokens kept deliberately for other
#   versions live in COMPAT_TOOLS with a reason, rather than being silently tolerated.
#
# Only PreToolUse/PostToolUse are checked: Notification matchers use their own
# vocabulary (auth_success, idle_prompt) and FileChanged matches FILE PATHS, not tools.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOKS_JSON="${SC_HOOKS_JSON:-$REPO_DIR/hooks/hooks.json}"

echo "=== Matcher Validity Tests ==="

CHECK=$(cat <<'PY'
import json, re, sys

# Tool names Claude Code exposes. Kept explicit rather than derived: the live tool set
# cannot be enumerated from inside a test, and guessing it would turn this into a
# flaky check that breaks on every Claude Code release.
KNOWN = {
    'Bash', 'Read', 'Write', 'Edit', 'NotebookEdit', 'Glob', 'Grep',
    'WebFetch', 'WebSearch', 'Agent', 'Skill', 'Artifact', 'AskUserQuestion',
    'ToolSearch', 'Workflow', 'ScheduleWakeup', 'ReportFindings', 'TodoWrite',
    'BashOutput', 'KillShell', 'Monitor', 'EndConversation',
    'TaskCreate', 'TaskGet', 'TaskList', 'TaskOutput', 'TaskStop', 'TaskUpdate',
    'CronCreate', 'CronDelete', 'CronList',
    'EnterPlanMode', 'ExitPlanMode', 'EnterWorktree', 'ExitWorktree',
    'PushNotification', 'RemoteTrigger', 'SendMessage', 'DesignSync',
    'ListMcpResourcesTool', 'ReadMcpResourceTool', 'ReadMcpResourceDirTool',
}
# Deliberately registered though absent from KNOWN. Each needs a REASON, so that a
# genuine typo cannot be waved through by appending it here.
COMPAT = {
    'MultiEdit':  'legacy tool; present in older Claude Code, absent in newer. '
                  'Harmless where absent, required where present.',
    'PowerShell': 'Windows Claude Code only; never present on macOS/Linux runners.',
}

# Claude Code's documented matcher rule, modelled exactly.
SIMPLE = re.compile(r'^[A-Za-z0-9_,| -]*$')
def is_regex(m):
    return not SIMPLE.match(m)

def tokens(m):
    # In regex mode the separator is '|' (a ',' would be a literal); in list mode
    # both ',' and '|' separate.
    return [t.strip() for t in re.split(r'\|' if is_regex(m) else r'[,|]', m) if t.strip()]

doc = json.load(open(sys.argv[1]))['hooks']
problems = []
for ev in ('PreToolUse', 'PostToolUse'):
    for entry in doc.get(ev, []):
        m = entry.get('matcher', '')
        if not m or m == '*':
            continue
        who = ', '.join(h.get('command', '').split('/')[-1] for h in entry.get('hooks', []))
        for tok in tokens(m):
            if tok.startswith('mcp__'):
                # RULE 1: needs a metacharacter or it can never match mcp__<server>__<tool>.
                if '.' not in tok and '*' not in tok:
                    problems.append('%s [%s] INERT mcp token %r' % (ev, who, tok))
                continue
            base = tok.rstrip('.*')
            if not re.match(r'^[A-Za-z][A-Za-z0-9_]*$', base):
                continue  # a genuine regex fragment, not a tool name
            # RULE 2: a plain tool name must be one we recognise.
            if base not in KNOWN and base not in COMPAT:
                problems.append('%s [%s] UNKNOWN tool %r' % (ev, who, tok))

print('\n'.join(problems))
PY
)

begin_test "every PreToolUse/PostToolUse matcher token can actually match a tool"
OUT=$(python3 -c "$CHECK" "$HOOKS_JSON" 2>&1)
if [ -z "$OUT" ]; then pass; else fail "inert or unknown matcher tokens: $(printf '%s' "$OUT" | tr '\n' '; ')"; fi

# Guard the guard: reconstruct the v2.24.5 shape and a typo, and confirm both are
# caught. A validity check that cannot fail is worse than none — it reads as proof.
TD=$(mktemp -d)

begin_test "the checker flags a bare mcp__ matcher (the v2.24.5 regression)"
python3 - "$TD/inert.json" <<'PY'
import json, sys
json.dump({"hooks": {"PreToolUse": [
    {"matcher": "mcp__", "hooks": [{"type": "command", "command": "/h/mcp-egress-guard.sh"}]}]}},
    open(sys.argv[1], "w"))
PY
OUT=$(python3 -c "$CHECK" "$TD/inert.json" 2>&1)
printf '%s' "$OUT" | grep -q 'INERT' && pass || fail "missed a bare mcp__ matcher: $OUT"

begin_test "the checker flags a typo'd tool name"
python3 - "$TD/typo.json" <<'PY'
import json, sys
json.dump({"hooks": {"PreToolUse": [
    {"matcher": "Bahs,Write", "hooks": [{"type": "command", "command": "/h/safety.sh"}]}]}},
    open(sys.argv[1], "w"))
PY
OUT=$(python3 -c "$CHECK" "$TD/typo.json" 2>&1)
printf '%s' "$OUT" | grep -q 'UNKNOWN' && pass || fail "missed a typo'd tool name: $OUT"

begin_test "the checker accepts the corrected mcp__.* form"
python3 - "$TD/ok.json" <<'PY'
import json, sys
json.dump({"hooks": {"PreToolUse": [
    {"matcher": "mcp__.*", "hooks": [{"type": "command", "command": "/h/mcp-egress-guard.sh"}]},
    {"matcher": "Bash,PowerShell", "hooks": [{"type": "command", "command": "/h/safety.sh"}]},
    {"matcher": "Bash|Read|WebFetch|mcp__.*", "hooks": [{"type": "command", "command": "/h/x.sh"}]}]}},
    open(sys.argv[1], "w"))
PY
OUT=$(python3 -c "$CHECK" "$TD/ok.json" 2>&1)
[ -z "$OUT" ] && pass || fail "false positive on valid matchers: $OUT"

begin_test "the checker ignores events whose matcher is not a tool name"
python3 - "$TD/ev.json" <<'PY'
import json, sys
json.dump({"hooks": {
    "FileChanged":  [{"matcher": ".env,.envrc,package.json", "hooks": [{"type": "command", "command": "/h/file-watcher.sh"}]}],
    "Notification": [{"matcher": "idle_prompt", "hooks": [{"type": "command", "command": "/h/notify.sh"}]}]}},
    open(sys.argv[1], "w"))
PY
OUT=$(python3 -c "$CHECK" "$TD/ev.json" 2>&1)
[ -z "$OUT" ] && pass || fail "flagged a non-tool matcher vocabulary: $OUT"
rm -rf "$TD"

report
