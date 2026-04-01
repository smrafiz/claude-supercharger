#!/usr/bin/env bash
# Claude Supercharger — Hook Assembly & settings.json Merge

SUPERCHARGER_TAG="#supercharger"

get_hooks_for_mode() {
  local mode="$1"
  local has_developer="$2"
  local hooks_dir="$3"
  local hooks=()

  hooks+=("PreToolUse|Bash|${hooks_dir}/safety.sh")

  if [[ "$mode" == "standard" || "$mode" == "full" ]]; then
    hooks+=("Notification||${hooks_dir}/notify.sh")
    hooks+=("PreToolUse|Bash|${hooks_dir}/git-safety.sh")
    if [[ "$has_developer" == "true" ]]; then
      hooks+=("PostToolUse|Write,Edit|${hooks_dir}/auto-format.sh")
    fi
  fi

  if [[ "$mode" == "full" ]]; then
    hooks+=("UserPromptSubmit||${hooks_dir}/prompt-validator.sh")
    hooks+=("PreCompact||${hooks_dir}/compaction-backup.sh")
  fi

  printf '%s\n' "${hooks[@]}"
}

deploy_hook_scripts() {
  local source_dir="$1"
  local target_dir="$HOME/.claude/supercharger/hooks"
  mkdir -p "$target_dir"
  chmod 700 "$HOME/.claude/supercharger"

  cp "$source_dir/hooks/"*.sh "$target_dir/"
  chmod +x "$target_dir/"*.sh
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

for event in list(settings['hooks'].keys()):
    settings['hooks'][event] = [
        h for h in settings['hooks'][event]
        if tag not in h.get('command', '')
    ]
    if not settings['hooks'][event]:
        del settings['hooks'][event]

for line in hooks_input.strip().split('\n'):
    if not line.strip():
        continue
    parts = line.split('|', 2)
    event = parts[0]
    matcher = parts[1] if len(parts) > 1 else ''
    command = parts[2] if len(parts) > 2 else ''

    if event not in settings['hooks']:
        settings['hooks'][event] = []

    hook_entry = {'command': command + ' ' + tag}
    if matcher:
        hook_entry['matcher'] = matcher

    settings['hooks'][event].append(hook_entry)

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
            h for h in settings['hooks'][event]
            if tag not in h.get('command', '')
        ]
        if not settings['hooks'][event]:
            del settings['hooks'][event]
    if not settings['hooks']:
        del settings['hooks']

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>&1
}

count_installed_hooks() {
  local mode="$1"
  local has_developer="$2"
  local count=1

  if [[ "$mode" == "standard" || "$mode" == "full" ]]; then
    count=$((count + 2))
    if [[ "$has_developer" == "true" ]]; then
      count=$((count + 1))
    fi
  fi

  if [[ "$mode" == "full" ]]; then
    count=$((count + 2))
  fi

  echo "$count"
}
