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
  hooks+=("PreToolUse|Bash|${hooks_dir}/safety.sh|")
  hooks+=("PreToolUse|Write,Edit|${hooks_dir}/code-security-scanner.sh|")
  hooks+=("PermissionRequest||${hooks_dir}/smart-approve.sh|")
  hooks+=("PostToolUse|Bash,Write,Edit|${hooks_dir}/audit-trail.sh|async")
  hooks+=("PostToolUse|Bash|${hooks_dir}/trace-compactor.sh|async")
  hooks+=("PostToolUse|mcp__|${hooks_dir}/mcp-output-truncator.sh|")
  hooks+=("PostToolUse|mcp__,WebFetch,WebSearch|${hooks_dir}/prompt-injection-scanner.sh|")
  hooks+=("PostToolUse|Bash,Read|${hooks_dir}/output-secrets-scanner.sh|")
  hooks+=("SessionStart||${hooks_dir}/config-scan.sh|")

  # ── Full mode: everything ──
  if [[ "$mode" == "full" ]]; then
    hooks+=("Notification|idle_prompt|${hooks_dir}/notify.sh|async")
    hooks+=("Stop|*|${hooks_dir}/notify-stop.sh|async")
    hooks+=("PermissionRequest||${hooks_dir}/notify-permission.sh|async")
    hooks+=("PreToolUse|Bash|${hooks_dir}/git-safety.sh|")
    if [[ -f "$HOME/.claude/supercharger/.conventional-commits" ]]; then
      hooks+=("PreToolUse|Bash|${hooks_dir}/commit-check.sh|")
    fi
    hooks+=("PreToolUse|Bash|${hooks_dir}/enforce-pkg-manager.sh|")
    hooks+=("PostToolUse|Write,Edit|${hooks_dir}/scope-guard.sh check|")
    hooks+=("SessionStart||${hooks_dir}/project-config.sh|")
    hooks+=("SessionStart||${hooks_dir}/scope-guard.sh snapshot|")
    hooks+=("SessionStart||${hooks_dir}/update-check.sh|")
    hooks+=("SessionStart||${hooks_dir}/learn-from-blocks.sh|")
    hooks+=("SessionStart||${hooks_dir}/session-memory-inject.sh|")
    hooks+=("PostToolUse|mcp__|${hooks_dir}/mcp-tracker.sh|async")
    hooks+=("PostToolUse|Bash|${hooks_dir}/failure-tracker.sh|async")
    hooks+=("PostToolUse|Bash,Read|${hooks_dir}/loop-detector.sh|")
    hooks+=("PostToolUse|Read|${hooks_dir}/reread-detector.sh|")
    hooks+=("PreToolUse|Agent|${hooks_dir}/agent-gate.sh|")
    hooks+=("UserPromptSubmit||${hooks_dir}/agent-router.sh|")
    hooks+=("UserPromptSubmit||${hooks_dir}/context-advisor.sh|")
    hooks+=("UserPromptSubmit||${hooks_dir}/adaptive-economy.sh|")
    hooks+=("UserPromptSubmit||${hooks_dir}/scope-guard.sh contract|")
    hooks+=("UserPromptSubmit||${hooks_dir}/learn-from-prompts.sh|")
    hooks+=("PreCompact||${hooks_dir}/compaction-backup.sh|async")
    hooks+=("SessionEnd||${hooks_dir}/session-end.sh|async")
    hooks+=("Stop|*|${hooks_dir}/verify-on-stop.sh|")
    hooks+=("Stop|*|${hooks_dir}/project-verify.sh|")
    hooks+=("Stop|*|${hooks_dir}/scope-guard.sh clear|async")
    hooks+=("Stop|*|${hooks_dir}/session-complete.sh|async")
    hooks+=("Stop|*|${hooks_dir}/session-memory-write.sh|async")
    hooks+=("SubagentStart||${hooks_dir}/subagent-safety.sh|")
    if [[ "$has_developer" == "true" ]]; then
      hooks+=("PostToolUse|Write,Edit|${hooks_dir}/quality-gate.sh|")
    fi
  fi

  printf '%s\n' "${hooks[@]}"
}

deploy_hook_scripts() {
  local source_dir="$1"
  local target_dir="$HOME/.claude/supercharger/hooks"
  mkdir -p "$target_dir"
  chmod 700 "$HOME/.claude/supercharger"

  cp "$source_dir/hooks/"*.sh "$target_dir/"
  cp "$source_dir/lib/webhook.sh" "$target_dir/webhook-lib.sh"
  chmod 700 "$target_dir/"*.sh

  # Deploy tools so they're available after one-liner installs (no local repo)
  local tools_dir="$HOME/.claude/supercharger/tools"
  mkdir -p "$tools_dir"
  cp "$source_dir/tools/"*.sh "$tools_dir/"
  chmod 700 "$tools_dir/"*.sh

  # Deploy lib dependencies that tools/ scripts source at runtime
  local lib_dir="$HOME/.claude/supercharger/lib"
  mkdir -p "$lib_dir"
  cp "$source_dir/lib/utils.sh" "$lib_dir/"
  cp "$source_dir/lib/economy.sh" "$lib_dir/"
  chmod 700 "$lib_dir/"*.sh
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
    parts = line.split('|', 3)
    event = parts[0]
    matcher = parts[1] if len(parts) > 1 else ''
    command = parts[2] if len(parts) > 2 else ''
    flags = parts[3] if len(parts) > 3 else ''

    if event not in settings['hooks']:
        settings['hooks'][event] = []

    if command.startswith('prompt:'):
        inner = {'type': 'prompt', 'prompt': command[7:] + ' ' + tag}
    else:
        inner = {'type': 'command', 'command': command + ' ' + tag}

    if 'async' in flags.split(','):
        inner['async'] = True

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

# Disable Co-Authored-By trailers in commits and PRs
if 'attribution' not in settings:
    settings['attribution'] = {'commit': '', 'pr': ''}

# Set autocompact threshold to 70% (quality degrades at ~70%, not 50%)
if 'env' not in settings:
    settings['env'] = {}
settings['env']['CLAUDE_AUTOCOMPACT_PCT_OVERRIDE'] = '70'

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

# Remove autocompact override
if settings.get('env', {}).get('CLAUDE_AUTOCOMPACT_PCT_OVERRIDE') == '70':
    del settings['env']['CLAUDE_AUTOCOMPACT_PCT_OVERRIDE']
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
  count=$(get_hooks_for_mode "$mode" "$has_developer" "$hooks_dir" | grep -c '.' 2>/dev/null || echo "0")
  echo "$count"
}
