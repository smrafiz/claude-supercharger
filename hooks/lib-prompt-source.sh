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
