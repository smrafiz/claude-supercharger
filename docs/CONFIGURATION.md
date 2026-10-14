# Configuration reference

[Back to README](../README.md)

## Project config

Put a `.supercharger.json` in your repo root. Commit it and everyone on the project gets the same behaviour:

```json
{
  "roles": ["developer", "designer"],
  "economy": "lean",
  "budget": 5.00,
  "profile": "fast",
  "hints": "React + Tailwind, use pnpm"
}
```

`economy: lean` tells Claude to answer tersely, without preamble or restating the request. `budget` caps what one session can spend: it warns at 80% and blocks non-read tools at 100%.

For the largest cut in reply length, also run `/output-style concise`. With a tier already active it measured a 45% median cut in prose per turn on this repo ([method](ECONOMY-OUTPUT-STYLE.md)). A style rewrites the system prompt, while the economy tiers arrive as a user message after it.

## Performance profiles

| Profile | Behaviour |
|--|--|
| `standard` | All hooks active (default) |
| `fast` | Skips 7 analytics hooks: `adaptive-economy`, `rate-limit-advisor`, `mcp-tracker`, `failure-tracker`, `session-checkpoint`, `repetition-detector`, `context-advisor` |
| `minimal` | Skips 10 hooks: the `fast` list plus `quality-gate`, `typecheck` and `dep-vuln-scanner`. Security only |

Security hooks run under every profile.

```bash
SUPERCHARGER_PROFILE=fast claude
# or per project: {"profile": "fast"}
```

`/sc-profile [fast|minimal]` shows or switches the profile from inside Claude Code.

## Turn off one feature

| Feature | Env var |
|--|--|
| Reflexion memory | `SUPERCHARGER_LESSONS=0` |
| Stack standards | `SUPERCHARGER_STANDARDS=0` |
| Confidence gate | `SUPERCHARGER_CONFIDENCE=0` |
| Path guard | `SUPERCHARGER_PATH_GUARD=0` |
| Tool preferences | `SUPERCHARGER_TOOL_PREFS=0` |
| Bash output compactor | `SUPERCHARGER_BASH_COMPACTOR=0` |
| All advisory hooks | `SUPERCHARGER_ADVISORY_HOOKS=0` |
| Memory injection | `SUPERCHARGER_NO_MEMORY=1` |
| Daily update check (network) | `SUPERCHARGER_NO_UPDATE_CHECK=1` |
| Cron/wakeup prompt guard | `SUPERCHARGER_CRON_GUARD=0` |
| Cross-session message scan | `SUPERCHARGER_PEER_MESSAGE_SCANNER=0` |
| Outbound secret scan | `SUPERCHARGER_OUTBOUND_SECRET_GUARD=0` (for one server only: `/sc-trust-mcp <server>`) |
| Skill integrity check | `SUPERCHARGER_SKILL_LOCK=0` |

To turn off a hook by name, add it to `disableHooks` in `.supercharger.json`, or list it in `~/.claude/supercharger/scope/.disabled-hooks` for all projects. See [HOOKS.md](HOOKS.md#how-to-disable-a-hook). `bash tools/hook-toggle.sh <hook-name> off` does the same from the shell.

## Tune behaviour

| Setting | Env var | Default |
|--|--|--|
| Lesson-recall match threshold (Jaccard overlap) | `SUPERCHARGER_LESSON_THRESHOLD` | `0.35` |
| Pricing model override (cost trackers) | `SUPERCHARGER_PRICING_MODEL` | detected from the payload |
| Performance profile | `SUPERCHARGER_PROFILE` | `standard` (or `fast`, `minimal`) |
| Economy tier | `SUPERCHARGER_TIER` | `standard` (or `lean`, `minimal`) |
| Native terminal notifications instead of OS pop-ups | `SUPERCHARGER_NOTIFY_MODE` | unset (or `osc9` for iTerm2, WezTerm, Ghostty, Windows Terminal; `osc777` for foot, urxvt) |
| Never build or update the macOS notifier app, even if accepted before | `SUPERCHARGER_NO_NOTIFIER=1` at install | unset: the app is opt-in (`/sc-notifier`, or yes at install) and only kept up to date once accepted |
| macOS notifier app: notify even while the terminal or IDE Claude runs in is the frontmost app | `SUPERCHARGER_NOTIFY_WHEN_FOCUSED=1` | unset: the app stays quiet while you are looking at that app |
| Per-tier price, USD per million tokens (Bedrock, Vertex, gateways) | `SUPERCHARGER_PRICE_<TIER>`, e.g. `_OPUS` | first-party rates; format `"input,cache_write,cache_read,output"` |
| Timeout for blocking hooks, in seconds | `SUPERCHARGER_SYNC_TIMEOUT` at install | `15` (`60` on Windows) |

Lower `SUPERCHARGER_LESSON_THRESHOLD` to 0.2 if lessons rarely surface; raise it to 0.5 if they are noisy.

Notifications can be switched off with `bash ~/.claude/supercharger/tools/notify-toggle.sh off` (`sound` for a bell only, `on` to restore).

## Security categories

Turn off whole categories of `safety.sh` rules for one project:

```json
{"disableSecurityCategories": ["clipboard", "build-artifacts"]}
```

Categories: `filesystem`, `database`, `destructive`, `network`, `credentials`, `persistence`, `clipboard`, `browser`, `history`, `selfmod`, `path-traversal`, `symlink`, `git-internals`, `abs-path`, `build-artifacts`.

## Add your own blocks

```json
{"customPatterns": ["terraform[[:space:]]+apply", "kubectl[[:space:]]+delete"]}
```

These are extended regexes, matched case-insensitively against the command by the same engine the built-in patterns use. Commit the file and the whole team inherits the rule. The cap is 50 patterns of 200 characters each. A pattern that is not valid regex is reported at session start and skipped. It cannot disable the built-in guards, which are evaluated separately for that reason.

## Exempt one command

```json
{"allowPatterns": ["rm -rf .*/Library/Caches/"]}
```

Use this for a false positive you hit repeatedly. Without it the only option is `disableSecurityCategories`, which switches a whole category off. `allowPatterns` is the narrower tool: it can only reach blocks that setting would already remove. Three limits are enforced in code:

- It can never exempt a self-modification block. These patterns live in `.supercharger.json`, which the `selfmod` rule protects. A pattern able to exempt `selfmod` could authorise edits to the file that grants it that power.
- `git-safety`, `path-guard` and `harness-tamper-guard` are not affected. The human-approval floor cannot be changed from a config file.
- An invalid regex fails safe. The command stays blocked; a broken allow rule never widens the guard.

Every exemption is written to the block ledger, so `/sc-why` and the session `[BLOCKS]` summary show what was let through.

## Work across directories outside the project

```json
{"additionalRoots": ["/path/to/parent"]}
```

Add one entry per parent directory, not one per directory. Everything under a root counts as in-project, including directories created later. If you keep many sibling directories (WordPress themes across Local sites, a plugins folder, a monorepo's packages), that is one line:

```json
{"additionalRoots": ["/Users/you/Local Sites"]}
```

A single sibling works the same way, `{"additionalRoots": ["../my-pro-plugin"]}`, for a wrapper directory holding two repos that change together (a free/pro plugin pair, an SDK and its example app).

You can also use Claude Code's own authorisation. Since v2.26.43, path-guard honours `--add-dir`, the `/add-dir` command, and `permissions.additionalDirectories` in `settings.json`. If you have told Claude Code a directory is in your workspace, writes to it are allowed. For a one-off directory in one session, `/add-dir ../sibling-repo` is the quickest route.

Which one to use depends on how often you come back. `/add-dir` is recorded per session, so directories you edit regularly have to be added again every time you start Claude. `additionalRoots` is committed with the project and shared with the team. `permissions.additionalDirectories` persists but is per user. Use a root for directories you return to.

Since v2.26.42 the project boundary is pinned to the directory you launched Claude in, and stays there for the whole session. Open Claude in the wrapper directory and both repos stay in scope, even after `cd` moves the working directory into one of them. Before that change the boundary followed `cwd`, so a mid-session `cd` pushed the sibling out of the project and writes that worked at the start began failing with no explanation.

`additionalRoots` covers the case the launch directory cannot: repos that are not under one parent, or a session started inside one repo. Widening to the enclosing git repo does not help there, because each repo is its own git root.

Paths are relative to the project root, or absolute. Put one in each repo pointing at the other and commit them. Launching Claude from the wrapper directory needs no config at all, because both repos are then inside the boundary.

It only widens the "is this inside my project" test. It never removes a protection:

- `/`, `$HOME`, any ancestor of `$HOME`, and `~/.claude` are refused. A root that resolves to any of them would disable the guard while looking like a whitelist. The same refusals apply to the launch directory and to Claude Code's own added directories, so starting Claude from `~` or running `/add-dir ~` does not make your home directory writable. Claude Code granting read access to a tree is not consent to write to it.
- The credential and system list stays blocked. `~/.ssh`, `~/.aws`, `~/.config`, `/etc/` and the rest are checked before the boundary test, so no whitelist reaches them.
- Roots are resolved through symlinks before they are trusted, and a path that does not exist (or is not a directory) is ignored rather than accepted.

This is the supported way to customise enforcement. Editing the installed hooks is not: `harness-tamper-guard` blocks it, and a forked guard stops receiving security updates.

## Tool preferences

A `toolPreferences` map redirects one tool to another, for example `npm` to `pnpm`, `jest` to `vitest`, `pip` to `uv pip`. It suggests the replacement rather than denying outright, and it catches `npx`/`bunx` wrappers. `preferGhCli: true` (opt-in) redirects GitHub `curl`/`wget`/`WebFetch` calls to the matching `gh` subcommand, which uses your real auth token.

## Project verify hook

Put a `.claude/verify.sh` in your repo. Claude runs it when it stops, and failures keep it working on the fix.

```bash
cp ~/.claude/supercharger/docs/templates/verify.sh .claude/verify.sh
chmod +x .claude/verify.sh
```

Put a `.supercharger-no-typecheck` file in a repo root to skip type-checking on just that repo.

## MCP profiles

| Profile | Servers | Context cost |
|--|--|--|
| `light` (default) | context7 | ~300 tokens |
| `dev` | + Playwright, GitHub, Magic UI | ~1,200 tokens |
| `research` | + Memory, Sequential Thinking | ~1,500 tokens |
| `full` | everything (dev + research) | ~3,500 tokens |

Supercharger tags its entries `#supercharger` and never touches your existing servers. Heavy servers are opt-in via `SUPERCHARGER_MCP_EXTRAS="playwright,github"`.

```bash
bash tools/mcp-profile.sh [profile]
```

Adding an MCP server is Claude Code's job (`claude mcp add <name> -- <cmd>`, or `--transport http <name> <url>`), and Supercharger does not reimplement it. What it adds is profile awareness: register a server you already added, pick which profiles it belongs to, and it is configured only while one of those is active (and moved aside by `/sc off`).

```bash
claude mcp add my-thing -- npx -y my-mcp-server     # Claude Code adds it
bash tools/mcp-custom.sh adopt my-thing dev,full    # only loaded in dev + full
bash tools/mcp-custom.sh list
bash tools/mcp-custom.sh remove my-thing            # hands it back, untagged
```

Adopting takes ownership: the entry moves into a Supercharger registry so a profile switch can add or remove it, and it is restored to you unchanged on `remove`. Servers you do not adopt are never modified.

On the plugin channel, MCP profiles do not apply. See [INSTALL.md](INSTALL.md#install-as-a-plugin).
