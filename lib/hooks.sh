#!/usr/bin/env bash
# Claude Supercharger — Hook Assembly & settings.json Merge

SUPERCHARGER_TAG="#supercharger"

get_hooks_for_mode() {
  local mode="$1"
  local has_developer="$2"
  local hooks_dir="$3"
  local hooks=()

  # Format: event|matcher|command
  # matcher is empty for events that don't support it
  hooks+=("PreToolUse|Bash|${hooks_dir}/safety.sh")

  if [[ "$mode" == "standard" || "$mode" == "full" ]]; then
    hooks+=("Notification||${hooks_dir}/notify.sh")
    hooks+=("PreToolUse|Bash|${hooks_dir}/git-safety.sh")
    hooks+=("PreToolUse|Bash|${hooks_dir}/commit-check.sh")
    hooks+=("PreToolUse|Bash|${hooks_dir}/enforce-pkg-manager.sh")
    hooks+=("PostToolUse|Bash,Write,Edit|${hooks_dir}/audit-trail.sh")
    hooks+=("PostToolUse|Write,Edit|${hooks_dir}/scope-guard.sh check")
    hooks+=("SessionStart||${hooks_dir}/project-config.sh")
    hooks+=("SessionStart||${hooks_dir}/scope-guard.sh snapshot")
    hooks+=("UserPromptSubmit||${hooks_dir}/scope-guard.sh contract")
    hooks+=("UserPromptSubmit||${hooks_dir}/agent-router.sh")
    hooks+=("PreToolUse|Agent|${hooks_dir}/agent-gate.sh")
    hooks+=("SessionStart||${hooks_dir}/update-check.sh")
    if [[ "$has_developer" == "true" ]]; then
      hooks+=("PostToolUse|Write,Edit|${hooks_dir}/quality-gate.sh")
    fi
  fi

  if [[ "$mode" == "full" ]]; then
    hooks+=("UserPromptSubmit||${hooks_dir}/prompt-validator.sh")
    hooks+=("PreCompact||${hooks_dir}/compaction-backup.sh")
    hooks+=("Stop||${hooks_dir}/session-complete.sh")
    hooks+=("Stop||${hooks_dir}/scope-guard.sh clear")
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
        if not any(tag in h.get('command', '') for h in entry.get('hooks', []))
    ]
    if not settings['hooks'][event]:
        del settings['hooks'][event]

# Add new entries in the new format
for line in hooks_input.strip().split('\n'):
    if not line.strip():
        continue
    parts = line.split('|', 2)
    event = parts[0]
    matcher = parts[1] if len(parts) > 1 else ''
    command = parts[2] if len(parts) > 2 else ''

    if event not in settings['hooks']:
        settings['hooks'][event] = []

    hook_entry = {
        'hooks': [
            {
                'type': 'command',
                'command': command + ' ' + tag
            }
        ]
    }
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
            if not any(tag in h.get('command', '') for h in entry.get('hooks', []))
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

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>&1
}

count_installed_hooks() {
  local mode="$1"
  local has_developer="$2"
  local count=1  # safety always

  if [[ "$mode" == "standard" || "$mode" == "full" ]]; then
    # notify, git-safety, commit-check, enforce-pkg-manager, audit-trail,
    # scope-guard(check+snapshot+contract), project-config, update-check,
    # agent-router, agent-gate
    count=$((count + 12))
    if [[ "$has_developer" == "true" ]]; then
      count=$((count + 1))  # quality-gate
    fi
  fi

  if [[ "$mode" == "full" ]]; then
    # prompt-validator, compaction-backup, session-complete, scope-guard clear
    count=$((count + 4))
  fi

  echo "$count"
}
