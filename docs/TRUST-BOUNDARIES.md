# Trust boundaries

What Supercharger checks when you add skills, agents, MCP servers and other people's
hooks to Claude Code, and where its checks stop. Short version: it is a strong default
harness with explicit limits. It does not make the rest of your stack safe.

## The one guarantee

Every guard is a separate process with an exit code. The model cannot see it, turn it
off or argue with it. That part is hard. What a guard *matches* is best-effort: known
dangerous shapes, with common obfuscation unwrapped. See "What this does and doesn't
guarantee" in the README.

Guards fire on calls the model makes through Claude Code's tool channel. They do not see
your own `!` commands or anything you run in another terminal.

## Skills

| Check | When | What it does |
|---|---|---|
| `skill-poisoning-scanner` | Each time the `Skill` tool loads a skill | Pattern scan for hidden shell, encoded payloads and injection text. Critical patterns deny. |
| `skill-integrity-guard` | Same | Hashes the skill and compares it with the last load. A changed skill asks before it is used. |

**Trusted on first use means:** the first time a skill loads after Supercharger is
installed, its current content becomes the baseline. That includes skills you already
had. Nothing re-checks where they came from; if one was bad before you installed, the
integrity guard accepts it as it is, and only the pattern scan stands between it and
Claude. Hashes live in `scope/.skills-lock`. There is no lockfile to write by hand,
which is the point: a curation step nobody does is a guard nobody has.

**It does not mean** the skill is safe, or that its behaviour is checked after it loads.
Once loaded, a skill is instructions Claude follows; the normal guards still judge every
tool call those instructions lead to. Turn the integrity check off with
`SUPERCHARGER_SKILL_LOCK=0`.

## Agent definitions and subagents

- `agent-poisoning-scanner` scans `~/.claude/agents/<name>.md` when the `Agent` tool
  spawns one, with the same patterns as the skill scanner. Critical patterns deny; the
  rest warn, because ordinary agent files mention credentials paths and subprocesses.
- Supercharger's hooks fire inside subagents too: their tool calls are checked like the
  main session's. This was measured, not assumed (a subagent's `.env` read was denied).
  The subagent sees the deny reason without Supercharger's usual remediation text.
- Per-agent allowlists (opt-in, `agent-allowlist-guard`, full mode). An agent definition
  can narrow what that subagent may do with the tools it has:

  ```yaml
  ---
  name: reviewer
  supercharger-allow:
    bash: ["git status", "git diff*", "npm test"]   # command prefix, or a glob with * ? [
    webfetch: ["docs.python.org", "*.github.com"]   # host and its subdomains, or a glob
    write: ["src/**", "tests/**"]                   # relative to the project root
  ---
  ```

  Inside that subagent a call outside a declared list is denied, with the agent and the
  list named in the reason. A tool with no list, an agent with no `supercharger-allow`,
  and the main session (including `--agent`) are unaffected. An empty list (`bash: []`)
  allows nothing. Details:
  - The agent is matched by its frontmatter `name` (what Claude Code reports as
    `agent_type`), project definitions first, then `~/.claude/agents`. Plugin agents
    (`plugin:name`) are not resolved.
  - `bash` also covers `Monitor` and `PowerShell`. Every segment of `a && b`, `a | b` and
    multi-line commands must match, after wrappers and `VAR=x` prefixes are stripped.
    Command substitution, process substitution and output redirects are denied (fd
    duplication such as `2>&1` and `>/dev/null` are fine).
  - `write` covers Write, Edit, MultiEdit and NotebookEdit. Paths are resolved (`~`,
    `..`, symlinks) before matching. A bare entry like `src` means `src` and everything
    under it; absolute entries are allowed.
  - While any list is declared the agent may not edit its own definition, and may not
    spawn nested agents or workflows, which would run without the list.
  - A list that cannot be parsed is ignored with a stderr note: it never blocks work.
    Disable the guard with `SUPERCHARGER_AGENT_ALLOWLIST=0`.

## MCP servers

| Check | What it covers |
|---|---|
| Destructive and SQL write gates | GitHub and Postgres MCP tools |
| Outbound secret scan | A tool call whose arguments carry a credential |
| Egress check | URLs in tool arguments |
| Response scans | Secrets, injection text, and results that pose as a tool definition or system turn (`mcp-provenance`) |
| Circuit breaker | Trips a server after repeated 429/503 |
| Elicitation guard | Declines a form that asks for a credential, unless you trusted the server with `/sc-trust-mcp` |
| `/sc-mcp-audit` | Scans each server's tool descriptions and pins them, reporting any that changed |

**The limit:** no hook ever sees an MCP tool's description. Claude Code sends hooks the
tool name, input and response, never the description, and it refetches descriptions
when a server says they changed, with no prompt. So a poisoned description, or one
that changes after you approved it, is invisible to every guard. `/sc-mcp-audit` closes
that by running its own MCP client, but only when you run it. It is not automatic,
because starting every server at session start would mean running their code.

At session start, `config-scan` also flags `.mcp.json` servers whose command is a
relative path or points inside the project.

## Other people's hooks and project settings

Supercharger does not inspect hooks you install from elsewhere in your own user
settings; they run alongside its guards with the same power. At session start,
`config-scan` warns about any hook in the project's `.claude/settings.json` that is not
Supercharger's (the CVE-2025-59536 class), about `ANTHROPIC_BASE_URL` overrides, and
about `defaultMode: bypassPermissions`. It warns; it does not remove them.

Writes to the files that switch Supercharger off (`.claude/settings.json` hooks,
`.supercharger.json`, the disabled-categories file) are blocked as self-modification,
from both Bash and Write/Edit.

## Checking it works

`/sc-health` runs each core guard through the command `settings.json` registers for it,
on a call it must stop, and fails if one lets it through. `/sc-status` shows what is on
this session. `/sc-why` explains the last block.

## Not covered

- Your own `!` commands and other terminals.
- What a trusted skill or agent tells Claude to want; only the resulting tool calls are
  checked.
- MCP tool descriptions, except when you run `/sc-mcp-audit`.
- A targeted attacker who already controls your prompts. Use OS-level isolation for that.
