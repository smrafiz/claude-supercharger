# Plugin Distribution — Plan

Status: **proposed** · Target: **a 2.x minor (no 3.0 dependency)** · Last updated: 2026-07-14

Output of a research spike (a `claude-code-guide` subagent against the official plugin docs at
code.claude.com, plus a local audit of the install surface). It scopes what it takes to ship the
**full** Supercharger as an installable Claude Code plugin, and phases the work so the codebase stays
**single-source** — one tree that both `install.sh` and the plugin runtime drive.

---

## 1. Goal & scope

**Goal:** Users can install the full Supercharger — hooks, commands, agents, memory, economy, the
prompt/instructional layer — via native plugin commands:

```
/plugin marketplace add smrafiz/claude-supercharger
/plugin install claude-supercharger@claude-supercharger
```

…and update via `/plugin update`, with no shell script and no manual `settings.json` edits.

**In scope:** a single plugin edition of the entire framework, sharing one codebase with the
installer (no fork).

**Explicitly out of scope:**
- **A separate "lite" plugin.** The earlier dual-track recommendation (plugin = prompt layer only,
  installer = hooks) is **withdrawn** — see §3. The `${CLAUDE_PLUGIN_DATA}` writable-state dir removes
  the reason to split.
- **Dropping `install.sh`.** It stays as the power-user / air-gapped / Windows path. The plugin is an
  *additional* distribution channel, not a replacement.
- **Windows-native plugin testing.** Inherits the Windows→3.0 gate; the plugin edition targets
  macOS/Linux first (same as today).

---

## 2. Key findings — the plugin runtime and its walls

From the official docs (plugins-reference, plugin-marketplaces, sandboxing):

### 2a. What the runtime gives us (maps cleanly)

- **All hook events we use are supported** — PreToolUse, PostToolUse, UserPromptSubmit, Stop,
  SessionStart, PreCompact, PostCompact, SubagentStop, PermissionRequest, Elicitation. Plus
  `async`, `asyncRewake`, and `if` — full parity with our current tuple flags.
- **Plugin hooks run *before* user hooks and *merge*** (no override). A user's own hooks still fire
  alongside ours — no conflict.
- **`${CLAUDE_PLUGIN_ROOT}`** — absolute path to the installed plugin (read-only, changes on update).
  Hook/command paths resolve against it.
- **`${CLAUDE_PLUGIN_DATA}`** — persistent, writable state dir (`~/.claude/plugins/data/{id}/`),
  auto-created, **survives updates**. This is the purpose-built home for our `scope/` + `audit/` state.
- **Commands** (`commands/*.md`) and **agents** (`agents/*.md`) load from the plugin root, namespaced.
- **Versioning/update** — `/plugin update`; explicit `version` in `plugin.json` pins releases (must be
  bumped each release — `bump-version.sh` already does this).

### 2b. The four sandbox walls (need workarounds)

A plugin **cannot** write outside the project dir. Concretely it cannot touch:

1. **`~/.claude/CLAUDE.md`** → our instructional/prompt block can't be installed as a file.
2. **`~/.claude/rules/*.md`** → guardrails.md / economy.md / supercharger.md / anti-patterns.yml can't
   be installed as files.
3. **`~/.claude/settings.json`** → we currently side-write three things here that a plugin can't:
   `statusLine`, `env.ENABLE_PROMPT_CACHING_1H`, and `attribution` (co-author trailer suppression).
4. **No install/uninstall lifecycle script** → the interactive `install.sh` wizard (role / tier /
   MCP-profile selection) has no plugin equivalent.

> ⚠️ **The current `plugin.json` is already wrong on wall #1/#2.** It carries a top-level `"rules": [...]`
> array pointing at `configs/universal/*.md`. **`rules` is not in the documented manifest schema** — it
> is silently ignored (and `claude plugin validate --strict` would reject it). The prompt layer is not
> actually shipping in today's scaffolding. §4 fixes this properly.

---

## 3. Architecture decision — single, dual-runnable codebase

**Decision:** one codebase, two entry points. Every hook script resolves its code root and its state
root from env vars with installer-compatible fallbacks:

```bash
SC_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/supercharger}"   # code + assets (read-only)
SC_DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}"    # mutable state (scope/, audit/)
```

- Under **plugin** runtime: `CLAUDE_PLUGIN_ROOT`/`CLAUDE_PLUGIN_DATA` are set → code from the cache dir,
  state in the data dir.
- Under **install.sh**: neither var is set → both fall back to `~/.claude/supercharger` → **behaves
  exactly as today**.

This is why the split from §2 does not force a fork: the *same* scripts run both ways. The migration is
mostly a mechanical path-reference rewrite (§7).

**Rejected alternative — dual-track (lite plugin + full installer).** Withdrawn because
`${CLAUDE_PLUGIN_DATA}` gives plugins a legitimate writable state location, so the full hook set *can*
run as a plugin. Shipping a deliberately crippled plugin would just create a support-confusing second
artifact. One full plugin, one installer, one codebase.

---

## 4. Delivering the prompt layer without file writes (wall #1/#2)

The instructional layer is **static standing text**. Under the plugin model it moves from a file into a
hook that emits it as context:

- A **SessionStart hook** prints the block (response principles, verification gate, safety boundaries,
  anti-patterns, economy tier, role) to stdout as `additionalContext`.
- This is **already how Supercharger injects** per-turn economy/role/think context — we are extending an
  existing, proven mechanism, not inventing one.
- Source of truth stays `configs/universal/*.md`; a small emitter concatenates them into the hook's
  output. No duplication.

Net: the prompt layer ships **fully** via the plugin — just as runtime-injected context instead of a
CLAUDE.md edit. (Subtle behavioral difference: injected context is re-emitted each session rather than
living permanently in CLAUDE.md — functionally equivalent for our rules, and it means uninstalling the
plugin cleanly removes the layer with zero residue.)

---

## 5. Casualties — what the plugin edition loses vs. install.sh

Explicit, so it's a conscious tradeoff and documented for users:

| Lost / changed | Why | Mitigation |
|---|---|---|
| **Statusline** | No `statusLine` manifest field; can't write settings.json | Ship a one-line copy-paste snippet in the plugin README; or a `/claude-supercharger:statusline` command that prints it |
| **`env.ENABLE_PROMPT_CACHING_1H`** | settings.json side-write | Document as a recommended manual setting |
| **`attribution` (no co-author trailer)** | settings.json side-write | Our `commit-coauthor-guard` hook already covers the enforcement path; document the setting |
| **Command names** | Plugin namespacing | `/audit` → `/claude-supercharger:audit`, etc. (26 commands). `/sc-update` → native `/plugin update`; `/sc on\|off` → native `/plugin enable\|disable` |
| **Interactive install wizard** | No lifecycle script | `userConfig` prompts at enable time (role/tier/MCP-profile) → `${CLAUDE_PLUGIN_OPTION_*}` env into hooks; lazy first-run init on SessionStart |
| **`jq` / `python3` auto-check** | No install script | SessionStart preflight hook warns if missing (81 hooks use `jq`, 98 use `python3`) |

None are load-bearing for enforcement. The guards themselves transfer intact.

---

## 6. Phased implementation

Ordered so each phase is independently verifiable and value/risk-front-loaded.

### Phase 0 — Portability spike (proof) — ✅ **DONE** (2026-07-14)
- Shim landed as `hooks/lib-paths.sh` (vars named `SUPERCHARGER_HOME`/`SUPERCHARGER_STATE`, not
  `SC_ROOT`/`SC_DATA` — matches the existing `SUPERCHARGER_*` namespace).
- Applied to `lib-suppress.sh`, `lib-timing.sh` (the two most-sourced libs, with an inline `:=`
  resilience fallback so the security kill-switch resolves even if lib-paths is absent) and the
  state-writing `audit-trail.sh`.
- Verified: (a) plugin runtime routes state to `CLAUDE_PLUGIN_DATA`, no leak to ROOT/HOME; (b) vars
  unset → byte-identical installer behavior; (c) full suite green.

### Phase 1 — Path indirection sweep — ✅ **DONE for all runtime hooks** (2026-07-14)
- Centralized in `hooks/lib-paths.sh`; the 53 hooks that source `lib-suppress`/`lib-timing` inherit the
  vars, and a resolver block (source + inline `:=` fallback) was threaded into the **13** hooks that
  used the vars but sourced no resolving lib.
- Swept **68 hook files**: state prefixes → `$SUPERCHARGER_STATE`, code (`/tools`) → `$SUPERCHARGER_HOME`,
  the `SUPERCHARGER_DIR="$HOME/..."` base-dir idiom → `$SUPERCHARGER_STATE`.
- **Regression gate green:** full suite **1509 passed / 0 failed** with plugin vars unset (installer path
  byte-identical). Cross-runtime parity spot-checked (`event-logger`: state → DATA under plugin, → HOME
  under installer).
- **Intentionally left as-is (correct):** project-scoped refs (`$PROJECT_DIR/.claude/supercharger*`,
  per-repo lessons + `supercharger-memory.md`) resolve correctly under both runtimes.
- **Deferred remainders (non-load-bearing, tracked):**
  - 3 python debug-flag reads (`config-scan`, `mcp-provenance`, `prompt-injection-scanner`) use
    `expanduser('~/.claude/supercharger/scope/.debug-hooks')`. Default-off flag; 2 are security scanners
    — convert deliberately alongside Phase 2 mode-gating with focused tests, not via a blind sweep.
  - Comment/help-string paths (`~/.claude/supercharger/...` in echoes, REASON text, doc comments) →
    Phase 6 docs pass.
- **Not touched (installer-side, must stay literal):** `lib/hooks.sh` install-destination refs (the
  plugin never runs the installer); `lib/roles.sh`, `lib/economy.sh`, `tools/*`, `configs/*` → Phase 3/4.

### Phase 2 — `hooks/hooks.json` emitter
- The tuple→JSON logic **already exists** in `lib/hooks.sh` (`merge_hooks_into_settings`). Factor it into
  a generator that emits a standalone `hooks/hooks.json` using `${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh`
  paths and the `async`/`asyncRewake`/`if` flags.
- Decide mode handling: plugin ships **full mode**; gate optional/`developer`-only hooks via a runtime
  check reading `userConfig`, not via emit-time selection.
- Generator runs at build/release time (add to `bump-version.sh`), committing `hooks/hooks.json`.

### Phase 3 — Prompt layer as SessionStart context (§4)
- New hook `hooks/prompt-layer-inject.sh` (or extend an existing SessionStart hook) that emits the
  `configs/universal/*.md` content as `additionalContext`.
- Remove the bogus `"rules"` array from `plugin.json`.
- Verify the injected block appears once per session and respects the active tier/role.

### Phase 4 — Commands & agents into plugin layout
- Copy/symlink `configs/commands/*.md` → `commands/`, `configs/agents/*.md` → `agents/` at plugin root.
- Update any command/agent body that references `~/.claude/supercharger/...` paths to `${CLAUDE_PLUGIN_ROOT}`.
- Reconcile meta-commands: retire `/sc-update`, remap `/sc` semantics to native enable/disable, keep
  `/sc-status` (reads `SC_DATA`).

### Phase 5 — Packaging, config, CI
- `userConfig` in `plugin.json`: `role`, `economy_tier`, `mcp_profile` (+ optional `notify` prefs).
- Finalize `marketplace.json` (source `./`, explicit `version`).
- CI: add `claude plugin validate --strict` + a plugin-runtime smoke test (env vars set) to the matrix
  alongside the existing installer suite.

### Phase 6 — Docs & release
- README "Install as a plugin" section; casualty list from §5; migration note for existing installer
  users (don't run both against the same state dir).
- `docs/DISTRIBUTION.md` update. Ship as a 2.x minor.

---

## 7. Path-rewrite specification

The 92 files referencing `$HOME/.claude/supercharger` split into exactly two rewrites:

| Reference (today) | Class | Rewrite |
|---|---|---|
| `$HOME/.claude/supercharger/hooks` | code | `$SC_ROOT/hooks` |
| `$HOME/.claude/supercharger/lib` | code | `$SC_ROOT/lib` |
| `$HOME/.claude/supercharger/rules/stacks` | code | `$SC_ROOT/rules/stacks` |
| `$HOME/.claude/supercharger/economy` | code | `$SC_ROOT/economy` |
| `$HOME/.claude/supercharger/roles` | code | `$SC_ROOT/roles` |
| `$HOME/.claude/supercharger/scope/*` | **state** | `$SC_DATA/scope/*` |
| `$HOME/.claude/supercharger/audit` | **state** | `$SC_DATA/audit` |
| `$HOME/.claude/supercharger/.version` | **state** | `$SC_DATA/.version` |
| `$HOME/.claude/supercharger` (bare, config flags) | **state** | `$SC_DATA` |

Rule of thumb: **anything read-only and shipped = `SC_ROOT`; anything written at runtime = `SC_DATA`.**
Both default to `~/.claude/supercharger` when the plugin vars are unset, preserving installer behavior.

---

## 8. Testing strategy

- **Regression gate (every phase):** full suite green with plugin vars **unset** (installer path
  unchanged). This is non-negotiable — the installer must not regress.
- **Plugin-runtime suite:** re-run the deny-path and state-writing tests with
  `CLAUDE_PLUGIN_ROOT`/`CLAUDE_PLUGIN_DATA` set to temp dirs; assert deny still fires and state lands in
  `SC_DATA`, not `SC_ROOT`.
- **Manifest validation:** `claude plugin validate --strict` in CI (catches the `rules`-style
  schema drift).
- **Cross-runtime parity:** a smoke test asserting the same hook produces the same decision under both
  runtimes for a fixed input.

---

## 9. Risks & open questions

- **Command-name break is user-visible.** `/audit` → `/claude-supercharger:audit`. Acceptable (native
  plugin convention) but must be loud in docs. *Open:* is a shorter plugin `name` worth it for terser
  namespacing (e.g. `sc` → `/sc:audit`)? Trades discoverability for brevity.
- **Running installer + plugin simultaneously** could double-fire hooks and split state across two dirs.
  Docs must tell users to pick one channel. *Open:* should a SessionStart preflight detect both and warn?
- **`rules` field** — confirm empirically it's ignored (not a newer undocumented feature) before deleting;
  the manifest schema says it is, but verify against a live `--debug` load.
- **Statusline** — confirm no manifest field exists in the current CC version before accepting the loss
  (docs reviewed 2026-07-14; recheck at build time).
- **Windows** — plugin edition inherits the Windows→3.0 gate; do not claim Windows plugin support until
  the box exists.

---

## 10. Effort estimate

| Phase | Effort | Risk |
|---|---|---|
| 0 — Spike | low (hours) | none (non-destructive) |
| 1 — Path sweep (92 files) | medium (mechanical) | low — regression suite catches drift |
| 2 — hooks.json emitter | low — logic already exists | low |
| 3 — Prompt-layer hook | medium — real design work | medium — behavioral parity to verify |
| 4 — Commands/agents | low | low |
| 5 — Packaging/CI | low–medium | low |
| 6 — Docs/release | low | none |

**Critical path:** Phase 0 → 1 → 3. Phases 2/4/5 parallelize once 1 lands. No 3.0 dependency — ships as a
2.x minor.
