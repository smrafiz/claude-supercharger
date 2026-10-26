#!/usr/bin/env bash
# Claude Supercharger — prompt source check (sourced by UserPromptSubmit hooks)
#
# The harness writes its own messages into the prompt slot: background-task
# notices, slash-command echoes, `!` shell output, subagent hand-backs, Stop
# hook feedback, the post-compaction summary. They are not what the user typed,
# so a hook that reads intent from the prompt must not read these. Measured
# 2026-09-29 on real transcripts: 3,000+ such prompts; they were routed as
# tasks, raised "destructive intent" on quoted commands, and logged Stop hook
# feedback as a user correction.
#
# Advisory hooks only. A SECURITY guard (prompt-secret-guard) must not skip
# these: the text still reaches the model.

# prompt_is_harness <prompt> — 0 when the prompt is a harness message.
prompt_is_harness() {
  # Leading whitespace first: a report delivered as "\nAnother Claude session..."
  # slipped past every prefix below and fired destructive-prompt-scanner on the
  # commands it quoted (3x on 2026-10-05). Fork-free ltrim.
  local _p="${1#"${1%%[![:space:]]*}"}"
  case "$_p" in
    "<task-notification"*|"<command-"*|"<local-command-"*|"<bash-"*|"<system-reminder"*|\
    "Another Claude session sent a message"*|"This session is being continued"*|"Stop hook feedback:"*)
      return 0 ;;
  esac
  return 1
}

# sc_strip_private VAR — remove every <private>…</private> span from the variable
# named VAR, in place, before anything is written to memory or lessons. An unclosed
# <private> drops the rest: when the end is missing, keeping less is the safe side.
# Idea from thedotmack/claude-mem (audited 2026-10-26). Fork-free.
sc_strip_private() {
  local _v="${!1}"
  while [[ "$_v" == *"<private>"* ]]; do
    if [[ "${_v#*<private>}" == *"</private>"* ]]; then
      _v="${_v%%<private>*}${_v#*</private>}"
    else
      _v="${_v%%<private>*}"
    fi
  done
  printf -v "$1" '%s' "$_v"
}
