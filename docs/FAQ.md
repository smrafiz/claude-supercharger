# FAQ

[Back to README](../README.md)

### Will this break my existing Claude setup?

The installer backs up your `~/.claude` Markdown files, `rules/`, `shared/` and `settings.json` to `~/.claude/backups/<timestamp>/` before touching anything. `./uninstall.sh` removes what it installed and offers to restore that backup.

### `/sc-notifier` fails with `redefinition of module 'SwiftBridging'`

Your Command Line Tools install is damaged, so nothing Swift can build on that Mac. Fix it, check with `swift --version`, then run `/sc-notifier install` again:

- with Xcode installed: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- without Xcode: `sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install`

### A hook blocked something I actually need

Run `/sc-why` to see what fired and why. Then either run `bash tools/hook-toggle.sh <hook-name> off`, or run the command yourself in your terminal outside Claude. The README lists the [ways through a block](../README.md#false-positives-and-ways-through), from narrowest to widest.

### My script copies a file into `~/.claude/supercharger/hooks/` and is now denied

This is expected as of 2.24.14. Writing over an installed hook is how the guardrail layer gets torn down, so `cp`, `install`, `rsync`, `curl -o` and `wget -O` aimed into the install dir are blocked, as are `rm` and `>`. Use `./install.sh` or `tools/update.sh`, which the guard does not intercept. Reading and copying out (`cp <hook> /tmp/`) still work.

### Can I temporarily switch back to plain Claude Code?

Yes. `/sc off` deactivates Supercharger globally. Every hook honours it at once: no guards, no injected context, no statusline. `/sc on` restores it. Nothing is uninstalled; the files stay dormant and a timestamped backup is written first. It also moves Supercharger's own MCP servers aside so they stop loading and stop costing context. MCP servers you added yourself are left alone.

Two caveats. Hooks stop immediately, but the `CLAUDE.md` prompt rules and the MCP change take effect on your next session. And while it is off, the security guards are off too: you are on stock Claude Code with no safety net until you run `/sc on`.

### How does this compare to SuperClaude, agent-os, or BMad?

Those are Markdown files that Claude reads and chooses to follow, and every rule costs context tokens on every session. Supercharger's enforcement is a separate process with an exit code. It costs no context and the model cannot opt out of it. The prompt-based layer here (roles, economy tiers) works the same way theirs does; the hook layer is what differs. See the [security model](SECURITY-MODEL.md) for the limits.

### How do I debug what hooks are doing?

Hook output is hidden by default. Per project, run `touch .supercharger-debug` in your repo root. Globally, run `touch ~/.claude/supercharger/scope/.debug-hooks`.

### How do I upgrade?

`bash ~/.claude/supercharger/tools/update.sh`

### Does this send any data anywhere?

There is no telemetry and no analytics. It reads no API keys, and no user data leaves your machine. The only automatic network call is an optional once-daily version check (`update-check.sh`, Full mode). It fetches this project's public version string from GitHub and sends nothing but a static `User-Agent`. Turn it off with `SUPERCHARGER_NO_UPDATE_CHECK=1`, `--mode safe`, or `hook-toggle.sh update-check off`. `tools/update.sh` also contacts GitHub, but only when you run it. Webhook notifications, if you opt in, POST to URLs you configure. Nothing else makes network calls.

### Can I write my own hooks?

```bash
bash tools/hook-new.sh my-hook PostToolUse Bash
bash tools/hook-toggle.sh my-hook on
```

Full guide: [HOOK_AUTHORING.md](HOOK_AUTHORING.md)

### Windows?

Use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash. Claude Code picks Git Bash as its hook interpreter on Windows, so the hooks run as they are. Git Bash is a requirement, not a preference: Claude Code falls back to PowerShell when it is absent, and every hook here is a bash script, so none of them would run.

Every push to `master` runs a `windows-latest` CI job under Git Bash (pull requests skip it because it takes about 80 minutes). It checks that hooks execute, that `rm -rf /` is still blocked, that the hashing used for per-project state works, that the platform is detected for notifications, and that `.sh` files check out with LF endings rather than CRLF. Install prerequisites: Git for Windows, Python (the `py` launcher is fine), and `jq` (`winget install jqlang.jq` or `choco install jq`, then reopen Git Bash).

Two things are not verified. Nobody has watched a desktop notification render on Windows: the CI job proves the right backend is selected, not that a toast appears. And no person has run a full install on a Windows desktop, only the scripted CI path. If you try it, please [open an issue](https://github.com/smrafiz/claude-supercharger/issues) either way.

Alpine Linux is not supported (it ships `ash`, not `bash`). Run inside a Debian, Ubuntu or Fedora container, or install GNU bash first.
