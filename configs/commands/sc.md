Activate or deactivate Claude Supercharger. Arguments: $ARGUMENTS (off | on | status)

Deactivate to get plain default Claude Code behavior on demand; reactivate when you want the guards, memory, economy, and statusline back. Nothing is uninstalled — `off` just switches everything off and keeps the files dormant on disk so `on` can restore them.

**Run it** (pass the argument straight through; default to `status` if none given):

```bash
bash ~/.claude/supercharger/tools/sc-toggle.sh $ARGUMENTS
```

Then report the tool's output verbatim.

- `/sc off` — switch to default Claude behavior. Sets a global kill-switch so **every hook exits immediately** (no enforcement, no context injection, no statusline), removes the Supercharger block from `~/.claude/CLAUDE.md`, and moves Supercharger's own `~/.claude/rules/*.md` aside. **Security note:** while off, ALL guards are inactive — destructive-command blocking, path-guard, credential/env-file guards, git-safety. State this clearly to the user.
- `/sc on` — re-enable Supercharger: removes the flag, restores the CLAUDE.md block and the rules files. Hooks are active on the next tool call; the prompt rules re-enter context next session.
- `/sc status` — report whether Supercharger is ACTIVE or DISABLED.

Notes to surface to the user:
- Hooks deactivate **immediately** (next tool call). The CLAUDE.md prompt layer changes take effect **next session** (it's loaded once at session start).
- `off` writes a timestamped backup under `~/.claude/backups/` before changing anything.
- `off` also moves Supercharger's **own** `~/.claude/rules/*.md` aside — `supercharger.md`, `guardrails.md`, `economy.md`, `anti-patterns.yml` and your active role file. Claude Code auto-loads that directory with no import, so stripping only the CLAUDE.md block used to leave ~9KB of Supercharger instructions entering every session while it claimed to be off. A rules file you wrote yourself is never touched; role files are identified against the installed sources in `~/.claude/supercharger/roles/`. `on` puts them back, and refuses to overwrite anything that took the name while off.
- `off` also moves Supercharger's **own** MCP servers aside — the `#supercharger`-tagged entries in both `~/.claude.json` and `~/.claude/settings.json` — so they stop loading and stop costing context; `on` restores each one to the file it came from. Your own MCP servers are never touched. MCP loads at session start, so this takes effect next session.
