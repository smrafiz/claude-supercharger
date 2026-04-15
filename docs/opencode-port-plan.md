# OpenCode Supercharger — Port Plan

## Overview

Port Claude Supercharger's safety, token optimization, and workflow features to OpenCode's plugin system. OpenCode plugins are JavaScript/TypeScript (not bash). The plugin would ship as `@opencode-supercharger/plugin` on npm.

## Architecture Difference

| Aspect | Claude Code (current) | OpenCode (target) |
|---|---|---|
| Hook language | Bash scripts | JavaScript/TypeScript |
| Hook config | `~/.claude/settings.json` | `.opencode/plugins/` or npm package |
| Blocking mechanism | `exit 2` | `throw new Error()` |
| Context injection | `hookSpecificOutput.additionalContext` | **Not available** (issue #17412 open) |
| Permission control | `PermissionRequest` event + JSON decision | `permission.asked` event |
| Status bar | Custom statusline command | OpenCode's built-in TUI |
| Config files | `CLAUDE.md` + `~/.claude/rules/` | OpenCode reads `CLAUDE.md` natively |
| Agent system | `.claude/agents/*.md` | OpenCode has its own agent system |

## Hook Event Mapping

| Claude Code | OpenCode | Notes |
|---|---|---|
| `PreToolUse` | `tool.execute.before` | Can modify args, throw to block |
| `PostToolUse` | `tool.execute.after` | Can read output, cannot modify |
| `PermissionRequest` | `permission.asked` | Different API shape |
| `SessionStart` | `session.created` | Available |
| `SessionEnd` | `session.deleted` | Partial support |
| `Stop` | `session.idle` | Available |
| `UserPromptSubmit` | **None** | Critical gap — no per-prompt hook |
| `PreCompact` | `experimental.session.compacting` | Can inject context into compaction |
| `Notification` | `tui.toast.show` | Toast notification in TUI |
| `StatusLine` | **None** | OpenCode has its own TUI |
| `SubagentStart/Stop` | **None** | Not applicable |

## Feature Port Status

### Phase 1 — Safety Layer (portable now)

| Feature | Claude Code hook | OpenCode hook | Complexity |
|---|---|---|---|
| Destructive command blocking (rm -rf, DROP TABLE, etc.) | `PreToolUse\|Bash` / `exit 2` | `tool.execute.before` / `throw` | Low |
| Git safety (force-push, reset --hard) | `PreToolUse\|Bash` / `exit 2` | `tool.execute.before` / `throw` | Low |
| Package manager enforcement | `PreToolUse\|Bash` / `exit 2` | `tool.execute.before` / `throw` | Low |
| Credential detection in commands | `PreToolUse\|Bash` / `exit 2` | `tool.execute.before` / `throw` | Low |
| Clipboard/browser/history blocking | `PreToolUse\|Bash` / `exit 2` | `tool.execute.before` / `throw` | Low |
| Code security scanner (eval, innerHTML, SQL injection) | `PreToolUse\|Write,Edit` | `tool.execute.before` on edit/write | Low |
| File path metacharacter check (CVE-2026-35021) | `PreToolUse\|Write,Edit` | `tool.execute.before` on edit/write | Low |
| Audit trail (JSONL logging) | `PostToolUse\|Bash,Write,Edit` | `tool.execute.after` + file write | Low |
| Output secrets scanner | `PostToolUse\|Bash,Read` | `tool.execute.after` | Low |
| Traceback compressor | `PostToolUse\|Bash` | `tool.execute.after` | Medium |
| Config scan (CLAUDE.md injection patterns) | `SessionStart` | `session.created` | Low |

### Phase 2 — Token Optimization (partially portable)

| Feature | Claude Code hook | OpenCode hook | Portable? |
|---|---|---|---|
| Loop detector (repeated tool calls) | `PostToolUse\|Bash,Read` | `tool.execute.after` + state | ✅ Detection works, ❌ can't nudge model |
| Re-read detector (unchanged file re-reads) | `PostToolUse\|Read` | `tool.execute.after` + mtime check | ✅ Detection works, ❌ can't nudge model |
| Failure tracker (3x same failure) | `PostToolUse\|Bash` | `tool.execute.after` + counter | ✅ Detection works, ❌ can't nudge model |
| Context advisor (compact warnings) | `UserPromptSubmit` | **None** | ❌ Blocked — no per-prompt hook |
| Compaction backup | `PreCompact` | `experimental.session.compacting` | ✅ |

### Phase 3 — Intelligence Layer (blocked by issue #17412)

| Feature | Why blocked |
|---|---|
| Agent routing (task classification + context hint) | Cannot inject additionalContext |
| Self-teaching (corrections, reinforcements at session start) | Cannot inject into conversation |
| Economy tier enforcement (per-prompt verbosity) | No UserPromptSubmit event |
| Verify-on-stop (test/build check) | Can detect but can't warn the model |
| Prompt injection scanner (MCP output) | Can detect but can't warn the model |

### Phase 4 — UX Layer (requires TUI integration)

| Feature | Status |
|---|---|
| Custom statusline | Not portable — OpenCode has its own TUI |
| Desktop notifications (task complete, idle, permission) | Use `tui.toast.show` or OS-level `osascript`/`notify-send` |
| Smart auto-approve with session rules | `permission.asked` — different API, needs investigation |

## Plugin Skeleton

```typescript
import { type Plugin } from "@opencode-ai/plugin"

export const supercharger: Plugin = async (ctx) => {
  return {
    // Block dangerous commands
    "tool.execute.before": async (input, output) => {
      if (input.tool === "bash") {
        const cmd = output.args.command || ""

        // Destructive patterns
        if (/rm\s+-rf\s+(\/|~|\$HOME)/.test(cmd)) {
          throw new Error("[Supercharger] Blocked: rm -rf on root/home directory")
        }

        // Git safety
        if (/git\s+push\s+.*--force.*\s+(main|master)/.test(cmd)) {
          throw new Error("[Supercharger] Blocked: force push to protected branch")
        }

        // Credential patterns
        if (/AKIA[0-9A-Z]{16}/.test(cmd)) {
          throw new Error("[Supercharger] Blocked: AWS key in command")
        }
      }

      // Code security scanner for write/edit
      if (input.tool === "edit" || input.tool === "write") {
        const content = output.args.content || output.args.new_string || ""
        if (/eval\(/.test(content)) {
          // Can't inject warning — throw blocks entirely
          // When #17412 lands, switch to context injection
          console.error("[Supercharger] Warning: eval() in written code")
        }
      }
    },

    // Audit trail + output scanning
    "tool.execute.after": async (input, output) => {
      // Log to JSONL
      const entry = {
        timestamp: new Date().toISOString(),
        tool: input.tool,
        args: input.tool === "bash" ? { command: output.args?.command } : { file: output.args?.filePath },
      }
      // Write to audit file...

      // Secret detection in output
      const result = output.result || ""
      if (/AKIA[0-9A-Z]{16}|ghp_[0-9a-zA-Z]{36}|sk-[0-9a-zA-Z]{48}/.test(result)) {
        console.error("[Supercharger] SECRET DETECTED in tool output")
        // Cannot warn model — issue #17412
      }
    },

    // Config scan at session start
    event: async ({ event }) => {
      if (event.type === "session.created") {
        // Scan CLAUDE.md for injection patterns
      }
    },
  }
}
```

## Dependencies

- `@opencode-ai/plugin` — plugin framework
- No other dependencies (keep zero-dep philosophy)
- Bun runtime (OpenCode uses Bun internally)

## File Structure

```
opencode-supercharger/
├── package.json
├── README.md
├── src/
│   ├── index.ts          # Plugin entry point
│   ├── safety/
│   │   ├── commands.ts   # Destructive command patterns
│   │   ├── git.ts        # Git safety rules
│   │   ├── credentials.ts # Credential detection
│   │   └── code-scan.ts  # Code security scanner
│   ├── audit/
│   │   ├── trail.ts      # JSONL audit logging
│   │   └── secrets.ts    # Output secret detection
│   ├── optimization/
│   │   ├── loop.ts       # Loop detector
│   │   ├── reread.ts     # Re-read detector
│   │   └── compactor.ts  # Traceback compressor
│   └── config/
│       └── scan.ts       # Config injection scanner
├── configs/
│   ├── economy.md        # Token economy rules
│   └── agents/           # Agent definitions (if OpenCode supports)
└── tests/
```

## Blockers

1. **Issue #17412** — Plugin hooks cannot inject AI-visible messages. This blocks the entire intelligence layer (routing, teaching, nudging). Without this, the plugin is safety-only.

2. **No UserPromptSubmit** — Can't run per-prompt hooks. Blocks economy tier enforcement and context advisor.

3. **Tool name differences** — OpenCode uses lowercase tool names (`bash`, `edit`, `read`). Claude Code uses PascalCase (`Bash`, `Edit`, `Read`). Need mapping layer.

4. **No statusline** — OpenCode's TUI is not customizable via plugins. Can't port the statusline.

## Timeline

| Phase | When | What |
|---|---|---|
| Phase 1 (Safety) | Now | All blocking/scanning features port cleanly |
| Phase 2 (Token opt) | Now (detection only) | Detection works, nudging waits for #17412 |
| Phase 3 (Intelligence) | After #17412 ships | Agent routing, self-teaching, economy enforcement |
| Phase 4 (UX) | TBD | Notifications, statusline equivalent |

## Decision: When to Start

Start Phase 1 when you want to expand Supercharger's user base beyond Claude Code. The safety plugin alone is valuable — it's the feature most Claude Code users install Supercharger for.

Wait for #17412 before marketing it as a full Supercharger port. Without context injection, it's "Supercharger Safety" not "Supercharger."
