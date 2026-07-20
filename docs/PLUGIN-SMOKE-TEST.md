# Plugin Smoke Test

A ~10-minute manual check that the plugin edition actually works on a real Claude Code
install. It exists to verify the **two behaviors that can't be unit-tested**:

1. `${CLAUDE_PLUGIN_ROOT}` is substituted inside slash-command markdown bodies (so a command
   that runs a bundled script resolves the right path).
2. `CLAUDE_PLUGIN_OPTION_*` reaches hook processes (so the first-run seeder applies the
   role / tier / MCP-profile you pick at enable time).

Everything else (hook policies, generators) is covered by `tests/run.sh`. Run this before
announcing the plugin, and after any change to `plugin.json`, `gen-plugin-commands.sh`,
`prompt-layer-inject.sh`, or `plugin-config-seed.sh`.

Type the `/plugin …` and `/supercharger:…` lines **in Claude Code**; the `!`-prefixed
lines run in your shell.

---

## 0. Isolate (pick one)

The `install.sh` copy and the plugin both fire hooks — running both at once double-fires (noisy,
not harmful). For a clean read:

- **Best:** a spare machine or fresh user account, **or**
- **Here:** temporarily uninstall the shell version, test, reinstall after:
  ```
  ! cd /Users/radiustheme/GithubRepos/claude-supercharger && ./uninstall.sh
  ```
  (State is isolated regardless — the plugin keeps its state under `~/.claude/plugins/data/…`,
  the installer under `~/.claude/supercharger/…` — so this is only to silence double firing.)

Make sure the branch you want to test is checked out (`master` for the released build).

## 1. Install from the local repo

```
/plugin marketplace add /Users/radiustheme/GithubRepos/claude-supercharger
/plugin install supercharger@claude-supercharger
```

- [ ] At enable time you're **prompted for `role`, `economy_tier`, `mcp_profile`**. Pick
      **non-defaults** on purpose (e.g. `writer`, `minimal`, `full`) so check #3 is meaningful.
- [ ] Install completes with no manifest error. (If it errors, run `claude plugin validate .`
      in the repo.)

Then restart Claude Code (or `/reload-plugins`).

## 2. Commands load (namespacing)

- [ ] Type `/` and confirm the plugin commands appear, **namespaced**:
      `/supercharger:status`, `:audit`, `:autopilot`, `:readonly`, `:strict`, …
- [ ] `/supercharger:sc-update` and the `/sc` toggle are **absent** (dropped in favor of native
      `/plugin` verbs).

## 3. ⭐ `${CLAUDE_PLUGIN_ROOT}` substitution in command bodies

The make-or-break check for the tool-invoking commands.

```
/supercharger:perf
```

- [ ] **PASS** — it runs `hook-perf.sh` and prints a timing report or "no timing data found".
- [ ] **FAIL** — an error mentioning a literal `${CLAUDE_PLUGIN_ROOT}`, or `…/tools/hook-perf.sh:
      No such file or directory`. → the command-body path substitution isn't happening; the fix is
      `tools/gen-plugin-commands.sh` (path strategy) — reopen before shipping.

## 4. ⭐ `CLAUDE_PLUGIN_OPTION_*` reaches hooks (first-run seeder)

After one full session (so `SessionStart` fired), check the plugin's data dir:

```
! ls ~/.claude/plugins/data/*supercharger*/scope/ 2>/dev/null
! cat ~/.claude/plugins/data/*supercharger*/scope/.economy-tier \
      ~/.claude/plugins/data/*supercharger*/scope/.mcp-profile \
      ~/.claude/plugins/data/*supercharger*/scope/.roles 2>/dev/null
```

- [ ] **PASS** — the three files exist and hold the values you picked at enable time
      (`minimal` / `full` / `writer`).
- [ ] **FAIL** — files missing, or all defaults (`standard` / `light` / `developer`) despite
      picking others. → `CLAUDE_PLUGIN_OPTION_*` isn't reaching `plugin-config-seed.sh`; revisit
      how the seeder reads the option before shipping.

## 5. Enforcement + prompt layer fire

- [ ] **SessionStart prompt layer** — the guardrail/economy/role context is present at session
      start (the plugin injects it as `additionalContext`, since it can't write `CLAUDE.md`).
- [ ] **A guard blocks.** In a scratch dir:
      ```
      ! echo "SECRET=x" > /tmp/sctest.env
      ```
      Then ask Claude to `Read /tmp/sctest.env` — `env-file-guard` should **deny** it.
- [ ] **A mode works.** `/supercharger:readonly 5m`, then ask Claude to edit any file —
      it should be **blocked**; `/supercharger:readonly off` to clear.

## 6. Cleanup

```
/plugin uninstall claude-supercharger
/plugin marketplace remove claude-supercharger
```
Then restore your normal copy if you uninstalled it:
```
! cd /Users/radiustheme/GithubRepos/claude-supercharger && ./install.sh
```

---

## Verdict

| Check | Gate |
|---|---|
| 3 — `${CLAUDE_PLUGIN_ROOT}` substitution | **Blocker** — tool-invoking commands are broken without it |
| 4 — `CLAUDE_PLUGIN_OPTION_*` seeding | **Blocker** — role/tier/profile won't apply |
| 2, 5 — commands load / guards fire | Should pass; covered indirectly by the suite |

**All green → the plugin release is verified; announce it.**
**3 or 4 red → contained fix + a patch release before announcing.** Both are documented-but-untested
Claude Code behaviors, so a failure is a Supercharger-side wiring change, not a dead end.

---

## Result — VERIFIED 2026-07-20 (v2.16.2)

Ran end-to-end on macOS against a real `/plugin install` from the local marketplace, confirmed
in a post-restart session. **All 5 checks green** — both ⭐ blockers (#3 `${CLAUDE_PLUGIN_ROOT}`
substitution, #4 `CLAUDE_PLUGIN_OPTION_*` → seeder) pass. `.economy-tier=minimal` and
`.mcp-profile=full` seeded correctly (non-defaults), the plugin's `safety.sh` blocked and logged a
command to `CLAUDE_PLUGIN_DATA`, and `prompt-layer-inject` fired at SessionStart. The two behaviors
that shipped unverified since v2.11.0 are now confirmed working.

## Known plugin-edition limitations (vs the installer)

These are inherent to Claude Code's plugin sandbox (plugins cannot write `~/.claude/settings.json`,
`CLAUDE.md`, or `rules/*.md`) — surfaced by the smoke test:

1. **No main status line.** The status line is set via `statusLine` in user `settings.json`; CC only
   honours the `agent` / `subagentStatusLine` keys from a plugin's bundled settings.json, so a plugin
   **cannot** install the main status bar. `statusline.sh` ships but nothing can wire it.
   *Workaround (power user):* add it to your own `settings.json` with `CLAUDE_PLUGIN_DATA` pinned —
   CC does NOT set that var for a user-settings statusLine command, so it must be hard-coded:
   ```json
   "statusLine": { "type": "command",
     "command": "CLAUDE_PLUGIN_DATA=~/.claude/plugins/data/claude-supercharger-supercharger ~/.claude/plugins/<…>/hooks/statusline.sh" }
   ```
   *Recommended:* if you want the status line, use the **installer edition** (`./install.sh`).

2. **Role-specific rules — FIXED in v2.17.0.** (Was a bug: the plugin injected only the role *name*
   via `{{ROLES}}`, never the role's rules file, so role behavior was a label with no substance.)
   `prompt-layer-inject.sh` now reads `configs/roles/<active-role>.md` (from `.roles` /
   `CLAUDE_PLUGIN_OPTION_ROLE`) and injects it — plugin role behavior matches the installer.

3. **`claude-check` diagnostic** is installer-only (the plugin has `claude plugin validate` + the
   test suite). Minor.

`/sc` and `/sc-update` are intentionally dropped in the plugin edition (native `/plugin` verbs
replace them) — not a limitation.
