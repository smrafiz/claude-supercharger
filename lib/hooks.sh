#!/usr/bin/env bash
# Claude Supercharger — Hook Assembly & settings.json Merge

SUPERCHARGER_TAG="#supercharger"

get_hooks_for_mode() {
  local mode="$1"
  local has_developer="$2"
  local hooks_dir="$3"
  local hooks=()

  # Format: event|matcher|command|flags
  # matcher is empty for events that don't support it
  # flags: "async" = non-blocking background execution (for fire-and-forget hooks)

  # ── Safe mode: core safety + smart UX (always on) ──
  # safety.sh is the consolidated security hook for Bash. It runs:
  #   destructive patterns, credentials, persistence, clipboard, browser, history,
  #   shell-wrapper detection (python/node/perl/ruby -c/-e), .env access, exfiltration.
  # env-file-guard.sh stays separate because safety.sh's matcher is Bash,PowerShell
  # only — env-file-guard catches direct .env reads (PreToolUse|Read), which safety.sh
  # cannot match. Do not consolidate without expanding safety.sh's matcher.
  # 2.22.12: also route shell-exec MCP servers through safety.sh — they run
  # arbitrary OS commands (execute_command / run / exec) that never reached the
  # Bash channel, so rm -rf / curl|bash / DB-drop / persistence were unguarded.
  hooks+=("PreToolUse|Bash,PowerShell,mcp__desktop-commander__,mcp__mcp-server-commands__,mcp__iterm__,mcp__iterm-mcp__,mcp__ssh__,mcp__shell__,mcp__terminal__,mcp__windows-cli__,mcp__cli-mcp-server__|${hooks_dir}/safety.sh|")
  hooks+=("PreToolUse|Read|${hooks_dir}/env-file-guard.sh|")
  # v2.23.6: Bash-channel self-defense. path-guard covers the Write/Edit channel and
  # safety.sh's selfmod blocks Bash edits to the config FILES; this closes the two
  # remaining gaps — `claude --dangerously-skip-permissions`/bypassPermissions, and
  # rm/mv/chmod-x/truncate/touch of the hook SCRIPTS, install dir, or kill-switch.
  # Disable: SUPERCHARGER_HARNESS_TAMPER_GUARD=0.
  hooks+=("PreToolUse|Bash|${hooks_dir}/harness-tamper-guard.sh|")
  hooks+=("PreToolUse|Write,Edit,MultiEdit,NotebookEdit|${hooks_dir}/path-guard.sh|")
  # Critical-infra write gate: forces a confirm before editing CI/CD, container,
  # DB-migration, or auth files (guardrails.md's documented review triggers). Emits
  # permissionDecision "ask" — not a hard block; asks once per file per session.
  # Fast-path exits before sourcing libs on any non-critical path.
  hooks+=("PreToolUse|Write,Edit,MultiEdit,NotebookEdit|${hooks_dir}/critical-infra-guard.sh|")
  # Read-only mode (/sc-readonly): time-boxed "look, don't touch". Near-zero overhead
  # when off (fast-path exits before parsing). A PreToolUse deny → beats autopilot's
  # auto-approve automatically (tighten > loosen).
  hooks+=("PreToolUse|Write,Edit,MultiEdit,NotebookEdit,Bash|${hooks_dir}/readonly-guard.sh|")
  # v2.7.2: block memory-poisoning writes (OWASP ASI06). Persistent memory is
  # auto-loaded every SessionStart, so a poisoned write compromises all future
  # sessions — must be in safe mode, not just full.
  hooks+=("PreToolUse|Write,Edit,MultiEdit|${hooks_dir}/memory-write-guard.sh|")
  hooks+=("PreToolUse|Bash|${hooks_dir}/tool-preferences.sh|")
  hooks+=("PreToolUse|Write,Edit,MultiEdit,NotebookEdit|${hooks_dir}/code-security-scanner.sh|asyncRewake")
  # v2.23.5: a Jupyter cell shells out through the kernel (!cmd, %%bash, %pip,
  # os.system, subprocess) and never hits the Bash matcher — safety.sh never sees
  # it. Route the cell's shell content through safety.sh (parity, no drift) and ask
  # on package installs. Security floor → safe mode. Disable: SUPERCHARGER_NOTEBOOK_EXEC_GUARD=0.
  hooks+=("PreToolUse|NotebookEdit|${hooks_dir}/notebook-exec-guard.sh|")
  hooks+=("PermissionRequest||${hooks_dir}/smart-approve.sh|")
  hooks+=("PostToolUse|Bash,PowerShell,Write,Edit,NotebookEdit|${hooks_dir}/audit-trail.sh|async")
  hooks+=("PostToolUse|Bash|${hooks_dir}/trace-compactor.sh|async")
  hooks+=("PostToolUse|Bash|${hooks_dir}/bash-output-compactor.sh|")
  hooks+=("PostToolUse|mcp__|${hooks_dir}/mcp-output-truncator.sh|async")
  # v2.6.84: per-server MCP write gates. Real CVEs / incidents:
  # github write-gate → Invariant Labs May 2025 cross-repo exfil;
  # playwright guard → CVE-2025-9611 + GH #1495 / #1651;
  # sql guard → Supabase 2025 service-role injection.
  hooks+=("PreToolUse|mcp__github__|${hooks_dir}/mcp-github-write-gate.sh|")
  hooks+=("PreToolUse|mcp__playwright__,mcp__puppeteer__,mcp__browserbase__,mcp__browser-use__,mcp__browsermcp__,mcp__chrome-devtools__,mcp__stagehand__|${hooks_dir}/mcp-playwright-guard.sh|")
  hooks+=("PreToolUse|mcp__postgres__,mcp__supabase__,mcp__mysql__,mcp__sqlite__,mcp__neon__,mcp__mssql__,mcp__sqlserver__,mcp__mariadb__,mcp__bigquery__,mcp__snowflake__,mcp__clickhouse__,mcp__planetscale__,mcp__cockroach__,mcp__cockroachdb__,mcp__redshift__,mcp__oracle__,mcp__duckdb__,mcp__motherduck__,mcp__turso__,mcp__libsql__,mcp__timescale__,mcp__singlestore__|${hooks_dir}/mcp-sql-guard.sh|")
  # 2.22.14: destructive ops on infra/filesystem/git MCP servers (structured
  # tool calls that never hit the shell-channel guards) — ASK to confirm.
  hooks+=("PreToolUse|mcp__filesystem__,mcp__aws__,mcp__kubernetes__,mcp__k8s__,mcp__docker__,mcp__gcloud__,mcp__gcp__,mcp__azure__,mcp__git__,mcp__terraform__|${hooks_dir}/mcp-destructive-guard.sh|")
  # v2.7.49: block credential-harvesting Elicitation forms — an MCP server asking
  # for a password/token/api-key in a routine-looking form. Declines when the
  # schema has credential-style fields and the server isn't in
  # trustedElicitationServers (.supercharger.json). SYNC — must run to block.
  hooks+=("Elicitation|*|${hooks_dir}/elicitation-guard.sh|")
  # v2.6.83: include Read so file content (issue bodies, PRs, docs) is scanned
  # for injection markers — OWASP ASI01 + multiple real-world incidents where
  # the agent followed instructions embedded in a Read file (e.g. GitHub issue
  # title prompt-injecting `npm publish` with a stolen token).
  hooks+=("PostToolUse|mcp__,WebFetch,WebSearch,Read|${hooks_dir}/prompt-injection-scanner.sh|asyncRewake")
  # v2.7.2: structural provenance check on MCP results — forged tool-call/system
  # framing the prompt-injection-scanner's persuasion patterns don't cover (ASI04).
  hooks+=("PostToolUse|mcp__|${hooks_dir}/mcp-provenance.sh|asyncRewake")
  # WebFetch egress guard: the native WebFetch/WebSearch tool is a network-egress
  # channel with NO PreToolUse guard — an injection can steer it at cloud metadata
  # (169.254.169.254 → cred theft) or an internal IP (SSRF). safety.sh:288 covers
  # this on Bash and mcp-egress-guard on MCP; this is the un-mirrored WebFetch
  # sibling (cross-channel parity). Only fires on WebFetch/WebSearch → ~zero hot-path
  # cost. Fail-open. Disable: SUPERCHARGER_WEBFETCH_EGRESS=0.
  hooks+=("PreToolUse|WebFetch,WebSearch|${hooks_dir}/webfetch-egress-guard.sh|")
  # v2.9.17: +mcp__ matcher — MCP tool RESPONSES were never secret-scanned (real
  # channel gap; a server can return a leaked credential). (from efij Stallion)
  # +WebFetch,WebSearch — fetched pages/results were never secret-scanned either.
  hooks+=("PostToolUse|Bash,Read,WebFetch,WebSearch,mcp__|${hooks_dir}/output-secrets-scanner.sh|asyncRewake")
  # Plugin-only first-run seeder: writes role/tier/mcp-profile scope files from
  # userConfig (CLAUDE_PLUGIN_OPTION_*) — the plugin equivalent of the installer
  # wizard. Runs first so later SessionStart hooks see the seeded files. No-ops
  # under the installer (CLAUDE_PLUGIN_ROOT unset); never clobbers an existing file.
  hooks+=("SessionStart||${hooks_dir}/plugin-config-seed.sh|")
  hooks+=("SessionStart||${hooks_dir}/config-scan.sh|")
  hooks+=("SessionStart||${hooks_dir}/standards-inject.sh|")
  # Plugin-only prompt-layer delivery: emits configs/universal/*.md as SessionStart
  # additionalContext when running under the plugin runtime (CLAUDE_PLUGIN_ROOT set).
  # No-ops under the installer, where the same content is persistent files.
  hooks+=("SessionStart||${hooks_dir}/prompt-layer-inject.sh|")
  hooks+=("Stop|*|${hooks_dir}/lesson-record.sh|async")
  hooks+=("UserPromptSubmit||${hooks_dir}/lesson-recall.sh|")
  hooks+=("PostToolUse||${hooks_dir}/tool-history-tracker.sh|async")
  hooks+=("PreToolUse|Edit,Write,Bash,MultiEdit,NotebookEdit|${hooks_dir}/confidence-gate.sh|")
  hooks+=("PostToolUse||${hooks_dir}/cache-health.sh|async")

  # ── Full mode: everything ──
  if [[ "$mode" == "full" ]]; then
    # v2.9.4: advisory concurrent-session write guard — warns (never denies) when a
    # peer live session holds a fresh lease on the same file. Fail-open, TTL-expiring.
    hooks+=("PreToolUse|Write,Edit,MultiEdit,NotebookEdit|${hooks_dir}/file-lease.sh|")
    # v2.9.6: opt-in first-touch investigation gate (default OFF via SUPERCHARGER_FACT_GATE).
    hooks+=("PreToolUse|Write,Edit,MultiEdit,NotebookEdit|${hooks_dir}/fact-gate.sh|")
    # Lockfile integrity: ask before hand-editing a machine-generated dependency
    # lockfile (package-lock/yarn.lock/Cargo.lock/go.sum/…) — regenerate via the
    # package manager instead. Once per lockfile per session. Disable:
    # SUPERCHARGER_LOCKFILE_GUARD=0.
    hooks+=("PreToolUse|Write,Edit,MultiEdit,NotebookEdit|${hooks_dir}/lockfile-integrity-guard.sh|")
    # v2.23.4: test-integrity guard — ASK before an edit to a test file removes
    # assertions or adds skip/only markers (it.skip, @pytest.mark.skip, @Ignore,
    # t.Skip, xit, .only, #[ignore]). Defends the Verification Gate against an
    # agent gaming the tests to go green. Disable: SUPERCHARGER_TEST_INTEGRITY_GUARD=0.
    hooks+=("PreToolUse|Edit,MultiEdit,Write|${hooks_dir}/test-integrity-guard.sh|")
    # v2.9.6: reactive MCP circuit-breaker — PostToolUse trips on 429/503/etc,
    # PreToolUse blocks calls to that server during cooldown. Default ON, fail-open.
    hooks+=("PreToolUse|mcp__|${hooks_dir}/mcp-circuit-breaker.sh|")
    hooks+=("PostToolUse|mcp__|${hooks_dir}/mcp-circuit-breaker.sh|async")
    # v2.9.17: classify URLs in MCP tool args — block metadata-SSRF / webhook /
    # paste-site egress, warn on private-network targets. (from efij Stallion)
    hooks+=("PreToolUse|mcp__|${hooks_dir}/mcp-egress-guard.sh|")
    hooks+=("Notification|idle_prompt|${hooks_dir}/notify.sh|async")
    hooks+=("Notification|auth_success|${hooks_dir}/notify.sh|async")
    hooks+=("Notification|elicitation_dialog|${hooks_dir}/notify.sh|async")
    hooks+=("Stop|*|${hooks_dir}/notify-stop.sh|async")
    hooks+=("PermissionRequest||${hooks_dir}/notify-permission.sh|async")
    hooks+=("PreToolUse|Bash|${hooks_dir}/git-safety.sh||git *")
    # Git remote exfil guard: git-safety checks HOW you push; this checks WHERE —
    # asks before pushing the whole repo to a non-origin host or hijacking origin's
    # URL to a foreign host (whole-repo exfiltration). Ask (not deny) — forks/mirrors
    # are legit — once per host per session. Disable: SUPERCHARGER_GIT_REMOTE_GUARD=0.
    hooks+=("PreToolUse|Bash|${hooks_dir}/git-remote-guard.sh||git *")
    # Redirect clobber guard: the Write/Edit review path is guarded, but a Bash
    # redirect (`echo x > app.ts`, `sed -i`, `tee`) overwrites tracked source and
    # bypasses ALL of it. Asks (not deny) ONLY when the target is git-tracked, once
    # per file per session. Fork-free fast-path; parser in redirect-clobber-detect.py.
    # Disable: SUPERCHARGER_REDIRECT_CLOBBER_GUARD=0.
    hooks+=("PreToolUse|Bash|${hooks_dir}/redirect-clobber-guard.sh|")
    # v2.14.3: consolidated commit guard — ONE hook runs three self-gating checks on
    # `git commit`: secret-in-staged-diff (default on), Co-Authored-By trailer (opt-in),
    # and Conventional Commit format (opt-in via .conventional-commits). Merged from
    # three separate hooks (commit-secret-guard/commit-coauthor-guard/commit-check) to
    # drop 2 process forks from EVERY Bash call. Each check keeps its own runtime flag,
    # so opt-in semantics are preserved on both channels — always registered, self-gating.
    hooks+=("PreToolUse|Bash|${hooks_dir}/commit-guard.sh|")
    hooks+=("PreToolUse|Bash|${hooks_dir}/enforce-pkg-manager.sh|")
    hooks+=("PostToolUse|Write,Edit|${hooks_dir}/scope-guard.sh check|async")
    hooks+=("PostToolUse|Edit,MultiEdit|${hooks_dir}/comment-replacement-check.sh|async")
    hooks+=("PostToolUse|Edit,MultiEdit|${hooks_dir}/lazy-refactor-check.sh|async")
    hooks+=("SessionStart||${hooks_dir}/project-config.sh|")
    hooks+=("SessionStart||${hooks_dir}/scope-guard.sh snapshot|async")
    hooks+=("SessionStart||${hooks_dir}/update-check.sh|async")
    hooks+=("SessionStart||${hooks_dir}/learn-from-blocks.sh|async")
    hooks+=("SessionStart||${hooks_dir}/session-memory-inject.sh|")
    hooks+=("PostToolUse||${hooks_dir}/auto-compact.sh|async")
    hooks+=("PostToolUse|mcp__|${hooks_dir}/mcp-tracker.sh|async")
    hooks+=("PostToolUse|Bash|${hooks_dir}/failure-tracker.sh|async")
    hooks+=("PostToolUse|Bash|${hooks_dir}/dep-vuln-scanner.sh|async")
    hooks+=("PostToolUse|Bash,Read|${hooks_dir}/repetition-detector.sh|")
    hooks+=("PreToolUse|Agent|${hooks_dir}/agent-gate.sh|")
    hooks+=("PreToolUse|Skill|${hooks_dir}/skill-poisoning-scanner.sh|")
    hooks+=("PreToolUse|CronCreate,CronDelete,CronList|${hooks_dir}/cron-discovery.sh|async")
    # v2.7.27: do NOT register any hook on WorktreeCreate/WorktreeRemove. Despite
    # being in CC's valid-events list, WorktreeCreate is a PROVIDER hook, not an
    # observational one: CC delegates worktree creation to the registered hook and
    # requires it to return the new worktree path (stdout or
    # hookSpecificOutput.worktreePath). A passive/discovery hook returns nothing,
    # so CC fails the creation — registering here BREAKS `isolation: worktree` for
    # every agent (regression introduced and caught in v2.7.26). We can't observe
    # these events without taking over worktree creation, which is out of scope.
    # v2.7.2: runaway fan-out / recursion breaker (OWASP ASI08). Blocking gate,
    # so NOT async — must run before the spawn proceeds.
    hooks+=("SubagentStart||${hooks_dir}/subagent-circuit-breaker.sh|")
    hooks+=("SubagentStart|*|${hooks_dir}/subagent-discovery.sh|async")
    hooks+=("SubagentStop|*|${hooks_dir}/subagent-discovery.sh|async")
    # v2.7.25: MessageDisplay + UserPromptExpansion removed — current Claude Code
    # no longer lists them as valid hook events, so registering them triggered a
    # settings.json warning on every startup. The events existed in mid-2026 CC
    # builds but were dropped; their hooks are non-functional now. If CC
    # re-introduces an expansion/display event, restore from git history.
    hooks+=("Elicitation|*|${hooks_dir}/elicitation-discovery.sh|async")
    hooks+=("ElicitationResult|*|${hooks_dir}/elicitation-discovery.sh|async")
    hooks+=("CwdChanged|*|${hooks_dir}/cwd-changed.sh|")
    hooks+=("PermissionDenied||${hooks_dir}/permission-denied-advisor.sh|")
    hooks+=("PreCompact||${hooks_dir}/precompact-priorities.sh|")
    hooks+=("PostToolUse||${hooks_dir}/slow-tool-detector.sh|async")
    hooks+=("Stop|*|${hooks_dir}/stop-keep-going.sh|")
    hooks+=("SubagentStop|*|${hooks_dir}/subagent-stop-check.sh|")
    # v2.7.1: auto-recover subagent reports when the agent ignores the
    # report-pin instruction from subagent-safety.sh. async — pure scrape.
    hooks+=("SubagentStop|*|${hooks_dir}/subagent-report-fallback.sh|async")
    # v2.7.4: when the final message is a degraded stub (CC #54323), tell the
    # parent the report was recovered + how to read it. BLOCKING — async cannot
    # inject hookSpecificOutput into the parent's context.
    hooks+=("SubagentStop|*|${hooks_dir}/subagent-report-notify.sh|")
    hooks+=("PostToolUseFailure||${hooks_dir}/tool-failure-advisor.sh|")
    hooks+=("UserPromptSubmit||${hooks_dir}/agent-router.sh|")
    hooks+=("UserPromptSubmit||${hooks_dir}/context-advisor.sh|async")
    hooks+=("UserPromptSubmit||${hooks_dir}/adaptive-economy.sh|")
    hooks+=("UserPromptSubmit||${hooks_dir}/economy-reinforce.sh|")
    hooks+=("UserPromptSubmit||${hooks_dir}/scope-guard.sh contract|")
    hooks+=("UserPromptSubmit||${hooks_dir}/prompt-validator.sh|")
    hooks+=("UserPromptSubmit||${hooks_dir}/shell-escape-advisor.sh|")
    hooks+=("UserPromptSubmit||${hooks_dir}/destructive-prompt-scanner.sh|")
    # v2.10.9: block a pasted LIVE credential in the prompt before it reaches the
    # model + transcript. Shares lib-secret-patterns.sh. Override with
    # SUPERCHARGER_ALLOW_PROMPT_SECRETS=1. From dwarvesf/claude-guardrails.
    hooks+=("UserPromptSubmit||${hooks_dir}/prompt-secret-guard.sh|")
    hooks+=("Setup||${hooks_dir}/setup-check.sh|")
    hooks+=("UserPromptSubmit||${hooks_dir}/reentry-detector.sh|")
    hooks+=("UserPromptSubmit||${hooks_dir}/learn-from-prompts.sh|async")
    hooks+=("UserPromptSubmit||${hooks_dir}/rate-limit-advisor.sh|async")
    hooks+=("PreCompact||${hooks_dir}/compaction-backup.sh|")
    hooks+=("PostCompact||${hooks_dir}/post-compact-inject.sh|")
    hooks+=("SessionEnd||${hooks_dir}/session-end.sh|async")
    hooks+=("Stop|*|${hooks_dir}/stop-verify.sh|")
    hooks+=("Stop|*|${hooks_dir}/scope-guard.sh clear|async")
    hooks+=("Stop|*|${hooks_dir}/session-complete.sh|async")
    hooks+=("Stop|*|${hooks_dir}/session-memory-write.sh|async")
    hooks+=("StopFailure||${hooks_dir}/stop-failure.sh|async")
    hooks+=("PermissionDenied||${hooks_dir}/event-logger.sh permission_denied|async")
    hooks+=("PostToolUseFailure||${hooks_dir}/event-logger.sh tool_failure|async")
    hooks+=("SubagentStop||${hooks_dir}/event-logger.sh subagent_stop|async")
    hooks+=("ConfigChange||${hooks_dir}/event-logger.sh config_change|async")
    hooks+=("InstructionsLoaded||${hooks_dir}/event-logger.sh instructions_loaded|async")
    hooks+=("TaskCreated||${hooks_dir}/event-logger.sh task_created|async")
    hooks+=("TaskCompleted||${hooks_dir}/event-logger.sh task_completed|async")
    hooks+=("TeammateIdle||${hooks_dir}/event-logger.sh teammate_idle|async")
    hooks+=("FileChanged|.env,.envrc,package.json,.claude/settings.json|${hooks_dir}/file-watcher.sh|async")
    hooks+=("SubagentStart||${hooks_dir}/subagent-safety.sh|")
    hooks+=("SubagentStop||${hooks_dir}/agent-handoff-gate.sh|")
    hooks+=("PostToolUse||${hooks_dir}/budget-cap.sh|async")
    hooks+=("PostToolUse|Write,Edit,Bash|${hooks_dir}/session-checkpoint.sh|async")
    hooks+=("PreToolUse||${hooks_dir}/budget-cap.sh check|")
    hooks+=("PreToolUse||${hooks_dir}/tool-call-limiter.sh|")
    hooks+=("PreToolUse|Bash,PowerShell|${hooks_dir}/human-approval-gate.sh|")
    hooks+=("PreToolUse|Agent|${hooks_dir}/cost-forecast.sh|")
    hooks+=("SubagentStart||${hooks_dir}/subagent-cost.sh start|async")
    hooks+=("SubagentStop||${hooks_dir}/subagent-cost.sh stop|")
    if [[ "$has_developer" == "true" ]]; then
      hooks+=("PostToolUse|Write,Edit|${hooks_dir}/quality-gate.sh|")
      hooks+=("PostToolUse|Write,Edit|${hooks_dir}/typecheck.sh|")
      hooks+=("PreToolUse|Write,Edit|${hooks_dir}/design-context.sh|async")
    fi
  fi

  printf '%s\n' "${hooks[@]}"
}

deploy_hook_scripts() {
  local source_dir="$1"
  local target_dir="$HOME/.claude/supercharger/hooks"
  mkdir -p "$target_dir"
  chmod 700 "$HOME/.claude/supercharger"

  # Remove hook .sh files that no longer exist in source. Without this, hooks
  # deleted in newer versions linger on disk forever (they're harmless because
  # settings.json doesn't register them, but they pollute /why explanations,
  # diagnostics, and confuse audits).
  for installed in "$target_dir/"*.sh; do
    [ ! -f "$installed" ] && continue
    local base
    base=$(basename "$installed")
    # Keep webhook-lib.sh (renamed copy of lib/webhook.sh, handled below)
    [ "$base" = "webhook-lib.sh" ] && continue
    if [ ! -f "$source_dir/hooks/$base" ]; then
      rm -f "$installed"
    fi
  done

  cp "$source_dir/hooks/"*.sh "$target_dir/"
  cp "$source_dir/lib/webhook.sh" "$target_dir/webhook-lib.sh"
  chmod 700 "$target_dir/"*.sh
  # Python deep-scanners invoked by hooks (safety-detect.py, env-file-detect.py).
  # These live in hooks/ but were previously never deployed (only *.sh was copied),
  # so safety.sh/env-file-guard.sh ran `python3 <missing-file>` → python exits 2 →
  # under `set -e` the hook died with empty stderr → CC rendered a phantom
  # "hook error: No stderr output" deny on every command that tripped the deep-scan
  # gate (python -c, curl, find, .env, secret, aws, …). Deploy them here.
  cp "$source_dir/hooks/"*.py "$target_dir/" 2>/dev/null || true
  chmod 700 "$target_dir/"*.py 2>/dev/null || true

  # Deploy tools so they're available after one-liner installs (no local repo)
  local tools_dir="$HOME/.claude/supercharger/tools"
  mkdir -p "$tools_dir"
  cp "$source_dir/tools/"*.sh "$tools_dir/"
  chmod 700 "$tools_dir/"*.sh

  # Deploy lib dependencies that hooks/tools source at runtime
  local lib_dir="$HOME/.claude/supercharger/lib"
  mkdir -p "$lib_dir"
  cp "$source_dir/lib/utils.sh" "$lib_dir/"
  cp "$source_dir/lib/economy.sh" "$lib_dir/"
  # Python modules imported by hooks (e.g., cwd-changed, project-config, statusline)
  cp "$source_dir/lib/"*.py "$lib_dir/" 2>/dev/null || true
  chmod 700 "$lib_dir/"*.sh
  chmod 600 "$lib_dir/"*.py 2>/dev/null || true

  # Deploy stack standards (rules/stacks/*.md) that standards-inject.sh reads.
  # Without this, standards-inject crashes at SessionStart on every install
  # because it expects rules/ as a sibling of hooks/ in the deploy layout.
  if [ -d "$source_dir/rules/stacks" ]; then
    local rules_dir="$HOME/.claude/supercharger/rules/stacks"
    mkdir -p "$rules_dir"
    cp "$source_dir/rules/stacks/"*.md "$rules_dir/" 2>/dev/null || true
    chmod 600 "$rules_dir/"*.md 2>/dev/null || true
  fi
}

merge_hooks_into_settings() {
  local mode="$1"
  local has_developer="$2"
  local hooks_dir="$HOME/.claude/supercharger/hooks"
  local settings_file="$HOME/.claude/settings.json"

  local hooks_list
  hooks_list=$(get_hooks_for_mode "$mode" "$has_developer" "$hooks_dir")

  SETTINGS_FILE="$settings_file" SUPERCHARGER_TAG="$SUPERCHARGER_TAG" HOOKS_INPUT="$hooks_list" python3 -c "
import json, os, sys

settings_file = os.environ['SETTINGS_FILE']
tag = os.environ['SUPERCHARGER_TAG']
hooks_input = os.environ['HOOKS_INPUT']

if os.path.exists(settings_file):
    with open(settings_file, 'r') as f:
        try:
            settings = json.load(f)
        except json.JSONDecodeError:
            print('ERROR: settings.json is malformed. Use Replace or Skip.', file=sys.stderr)
            sys.exit(1)
else:
    settings = {}

if 'hooks' not in settings:
    settings['hooks'] = {}

# Remove existing supercharger hook entries
for event in list(settings['hooks'].keys()):
    settings['hooks'][event] = [
        entry for entry in settings['hooks'][event]
        if not any(tag in h.get('command', '') or tag in h.get('prompt', '') for h in entry.get('hooks', []))
    ]
    if not settings['hooks'][event]:
        del settings['hooks'][event]

# Add new entries in the new format
for line in hooks_input.strip().split('\n'):
    if not line.strip():
        continue
    parts = line.split('|', 4)
    event = parts[0]
    matcher = parts[1] if len(parts) > 1 else ''
    command = parts[2] if len(parts) > 2 else ''
    flags = parts[3] if len(parts) > 3 else ''
    if_pattern = parts[4] if len(parts) > 4 else ''

    if event not in settings['hooks']:
        settings['hooks'][event] = []

    if command.startswith('prompt:'):
        inner = {'type': 'prompt', 'prompt': command[7:] + ' ' + tag}
    else:
        inner = {'type': 'command', 'command': command + ' ' + tag}

    flag_list = [f.strip() for f in flags.split(',') if f.strip()]
    if 'async' in flag_list:
        inner['async'] = True
    if 'asyncRewake' in flag_list:
        inner['asyncRewake'] = True
    if if_pattern:
        inner['if'] = if_pattern

    hook_entry = {'hooks': [inner]}
    if matcher:
        hook_entry['matcher'] = matcher

    settings['hooks'][event].append(hook_entry)

statusline_path = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'hooks', 'statusline.sh')
if os.path.isfile(statusline_path):
    settings['statusLine'] = {
        'type': 'command',
        'command': statusline_path + ' ' + tag
    }

# Enable 1-hour prompt cache TTL (regressed to 5min in March 2026; restores 20-32% cost savings)
if 'env' not in settings:
    settings['env'] = {}
settings['env']['ENABLE_PROMPT_CACHING_1H'] = '1'

# Disable Co-Authored-By trailers in commits and PRs
if 'attribution' not in settings:
    settings['attribution'] = {'commit': '', 'pr': ''}

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>&1

  return $?
}

remove_supercharger_hooks() {
  local settings_file="$HOME/.claude/settings.json"

  if [ ! -f "$settings_file" ]; then
    return 0
  fi

  SETTINGS_FILE="$settings_file" SUPERCHARGER_TAG="$SUPERCHARGER_TAG" python3 -c "
import json, os

settings_file = os.environ['SETTINGS_FILE']
tag = os.environ['SUPERCHARGER_TAG']

with open(settings_file, 'r') as f:
    settings = json.load(f)

if 'hooks' in settings:
    for event in list(settings['hooks'].keys()):
        settings['hooks'][event] = [
            entry for entry in settings['hooks'][event]
            if not any(tag in h.get('command', '') or tag in h.get('prompt', '') for h in entry.get('hooks', []))
        ]
        if not settings['hooks'][event]:
            del settings['hooks'][event]
    if not settings['hooks']:
        del settings['hooks']

if 'statusLine' in settings:
    cmd = settings['statusLine'].get('command', '')
    if tag in cmd:
        del settings['statusLine']

# Remove attribution override (restore Claude default)
if 'attribution' in settings:
    attr = settings['attribution']
    if attr.get('commit') == '' and attr.get('pr') == '':
        del settings['attribution']

# Remove prompt cache TTL override
if settings.get('env', {}).get('ENABLE_PROMPT_CACHING_1H') == '1':
    del settings['env']['ENABLE_PROMPT_CACHING_1H']
    if not settings['env']:
        del settings['env']

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>&1
}

count_installed_hooks() {
  local mode="$1"
  local has_developer="$2"
  # Count by generating the list — single source of truth
  local hooks_dir="$HOME/.claude/supercharger/hooks"
  local count
  # v2.6.42: awk emits exactly one number; `grep -c | || echo 0` doubled
  # output on zero matches and showed "0\n0 hooks installed" in install.sh.
  # v2.9.4: dedup by hook SCRIPT basename (tuple field 3), not registration
  # count — one hook registered on N events is still ONE installed hook. The
  # banner now matches the distinct-script count in docs/HOOKS.md instead of
  # overstating (a hook on 3 events used to count 3×). Portable awk: no
  # length(array) (BWK/macOS awk lacks it), count keys via a for-in loop.
  count=$(get_hooks_for_mode "$mode" "$has_developer" "$hooks_dir" \
    | awk -F'|' 'NF{ n=split($3,a,"/"); b=a[n]; if(b!="") seen[b]=1 } END{ c=0; for(k in seen) c++; print c+0 }')
  echo "$count"
}
