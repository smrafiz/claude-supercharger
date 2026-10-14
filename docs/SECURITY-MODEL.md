# Security model

[Back to README](../README.md)

## Why hooks instead of prompt rules

Rules written into a prompt are suggestions, and a model can find reasons to set a suggestion aside. You ask for a typo fix and the component gets rewritten. You come back to files overwritten and commands run with no warning. Better prompts do not fix this. Moving enforcement to a place the model cannot reach does.

```
You ──▶ Claude ──▶ Tool call ──▶ [Hook] ──▶ exit 0 or exit 2
                                    │
                                    └── Runs outside Claude's view
```

Supercharger has two layers, with different guarantees:

- Shell hooks run outside Claude's process, before a tool call executes. Claude does not see them and cannot be talked into skipping them. Exit code 2 means the call does not run.
- Prompt rules in `CLAUDE.md` shape behaviour: roles, economy tier, agent routing. Claude follows these reliably, but not unconditionally.

|  | Prompt-only frameworks (`CLAUDE.md` rules) | `/permissions` (inside Claude) | Supercharger hooks (outside Claude) |
|---|---|---|---|
| Claude sees the rules | Yes | Yes | No |
| Can be argued with | Yes | Yes | No: exit code 2 is not a negotiation |
| Advisory or enforced | Advisory | Advisory | Enforced |
| Cost in context tokens | ~5-20K per session | a few hundred | 0 |

Rules written as prompt text are read again every session and shrink the window left for real work. The hook layer lives in the shell and costs no context.

## What this does and does not guarantee

- The mechanism cannot be bypassed by the model. A hook is a separate process; Claude cannot see it, disable it, or argue with its exit code.
- The patterns are best effort. The guards match commands and file writes against known-dangerous shapes. `cmd-normalize.sh` unwraps common obfuscation, but string matching has limits, and someone with shell access who is trying to evade it can.

The threat model is a capable agent that makes mistakes, plus opportunistic prompt injection from tool output. It raises the cost of both. It is not a sandbox, and it does not defend against a targeted attacker who already controls your prompts. For that, put OS-level isolation underneath, such as a container or a VM, and keep using Claude Code's permission deny rules and git.

## What happens when a guard itself fails

| Situation | Result | How you would notice |
|---|---|---|
| A hook gets malformed input, or a helper such as `python3` or a detector script is missing | The hook allows the call (fail open). `safety.sh` falls back to its regex verdict when its Python detector fails | `/sc-doctor` checks registration and deployed-code integrity |
| A hook runs past its timeout | Claude Code kills it and runs the command. Blocking hooks are registered with a 15 s timeout (60 s on Windows; set `SUPERCHARGER_SYNC_TIMEOUT` at install to change it) | Nothing is written to the block ledger; the command just runs |
| A deny's JSON is invalid | Claude Code reads it as no decision. `hooks/lib-deny.sh` escapes every reason for this reason | |
| An `allowPatterns` entry is not valid regex | The command stays blocked (fails closed) | |
| A `customPatterns` entry is not valid regex | It is skipped and reported at session start; built-in rules still run | Session-start message |

Failing open on errors is deliberate. A guard that blocks on its own errors blocks unrelated work: in 2.17.3 a missing detector script denied every command that reached the deep scan ([CHANGELOG-archive.md](CHANGELOG-archive.md)). The cost is that a broken or hung guard looks the same as a clean pass. [HOOK_AUTHORING.md](HOOK_AUTHORING.md#a-guard-that-hangs-is-a-guard-that-is-off) covers how hooks are written to avoid hangs.

## The block ledger

Every block is appended to `~/.claude/supercharger/scope/.blocked-commands` on your machine. Secret-looking tokens are redacted before writing, each command is cut to 400 characters, and the file is trimmed to its last 500 entries whenever it passes 600. `/sc-why` and the session `[BLOCKS]` summary read it. Exemptions made with `allowPatterns` are recorded there too. Some guards also write JSONL records under `~/.claude/supercharger/audit/`. Neither file is sent anywhere.

## Scope of protection

Supercharger guards tool calls the agent makes. Anything the model invokes through Claude Code's tool channel passes through PreToolUse hooks first. Two flows fall outside that channel and cannot be blocked by exit code:

- User `!` shell escapes. Claude Code's `! <cmd>` prompt prefix runs a command directly in your shell, not through the Bash tool, so PreToolUse hooks never fire. `shell-escape-advisor.sh` scans `!` prompts for `rm -rf`, `curl|bash`, `git push --force` and `git reset --hard` and warns, but the shell still runs the command. Treat `!` like a separate terminal.
- Commands you run in your own terminal outside the Claude Code session. This is a Claude Code layer, not a shell-level guard.

If you need shell-level enforcement regardless of source, add it separately (for example an `rm` function in `~/.zshrc`).

Hooks on PostToolUse run after the tool has executed. They can warn, but they cannot undo the call.

Known gaps that are documented but not fixed are tracked in [KNOWN-ISSUES.md](KNOWN-ISSUES.md), including sensitive paths bound to a shell variable and injected instructions that do not use blunt phrasing.

## Standards alignment

Supercharger maps to the [OWASP Top 10 for Agentic Applications 2026](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/):

- Least agency. Every guardrail category can be turned off per project in `.supercharger.json`, so raising autonomy takes an explicit, human-written config change.
- Observability. Every blocked command, Edit/Write/Bash decision and subagent spawn is logged to `~/.claude/supercharger/scope/.blocked-commands` and to JSONL under `audit/`.
- Self-modification defence. The `selfmod` category covers both the Bash channel (`safety.sh`) and the Write/Edit channel (`path-guard.sh`), closing the [March 2026 Ona Security sandbox-bypass pattern](https://www.penligent.ai/hackinglabs/claude-code-sandbox-bypass/).
- Sandbox-bypass detection. `config-scan.sh` checks for three documented CVEs at session start: foreign hook injection ([CVE-2025-59536](https://nvd.nist.gov/vuln/detail/CVE-2025-59536)), `ANTHROPIC_BASE_URL` exfiltration ([CVE-2026-21852](https://nvd.nist.gov/vuln/detail/CVE-2026-21852)), and `defaultMode=bypassPermissions` ([CVE-2026-33068](https://nvd.nist.gov/vuln/detail/CVE-2026-33068)).
