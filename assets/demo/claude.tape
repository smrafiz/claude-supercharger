# Claude Supercharger — a real Claude Code session (not a script)
# Record:  vhs assets/demo/claude.tape   (repo root; needs Supercharger installed,
#          the `claude` CLI logged in, and costs two short Haiku turns)
# Produces: assets/demo/claude.gif
# Claude Code, the model and the installed hooks are all live: the prompts below
# are the only scripted part.

Output assets/demo/claude.gif

Require bash
Require claude
Set Shell bash
Set FontSize 15
Set Width 1400
Set Height 860
Set Padding 20
Set Theme "Dracula"
Set TypingSpeed 40ms

Hide
Type "rm -rf /tmp/my-app && DEMO_DIR=/tmp/my-app ./assets/demo/fixture.sh >/dev/null && cd /tmp/my-app && clear" Enter
Sleep 1500ms
# Recorded from inside another Claude session? Drop its markers, or Claude Code
# shows "Transcript saving is off - inherited CLAUDE_CODE_CHILD_SESSION marker".
Type "clear; unset CLAUDECODE CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ID CLAUDE_CODE_ENTRYPOINT; claude --model haiku --permission-mode default" Enter
# /tmp/my-app must already be trusted: run `claude` there once and pick "Yes, I
# trust this folder" (Claude Code remembers it per path; a tape cannot branch).
Wait+Screen@60s /manual mode/
Sleep 1500ms
Show

# The model's thinking time is cut (Hide until the answer is on screen), and each
# result is held long enough to read: the waits were long and the results flashed.
Type "Delete the src folder. Run exactly: rm -rf src" Sleep 500ms Enter
Sleep 1500ms
Hide
Wait+Screen@120s /no undo/
Sleep 300ms
Show
Sleep 9000ms
Escape
Sleep 2500ms

# Without the confirmation Claude itself declines and asks, and the hook never runs.
Type "I confirm, it is my repo: run exactly git push --force origin main" Sleep 500ms Enter
Sleep 1500ms
Hide
Wait+Screen@120s /protected branch/
Sleep 1500ms
Show
Sleep 10000ms

Hide
Ctrl+C
Sleep 300ms
Ctrl+C
Sleep 500ms
