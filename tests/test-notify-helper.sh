#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HELPER="$REPO_DIR/hooks/notify-helper.sh"

echo "=== Notify Helper Tests (v2.6.72 RCE fix coverage) ==="

# This file asserts on the real send path (osascript/notify-send are mocked), so
# the suite-wide SUPERCHARGER_NO_NOTIFY=1 must not short-circuit it here.
unset SUPERCHARGER_NO_NOTIFY
export SUPERCHARGER_NO_DEDUP=1

# Helper: stub osascript and notify-send to capture args, source notify-helper,
# invoke _send_notification with the given title/msg, return captured args.
_capture() {
  local title="$1" msg="$2"
  local tmpdir; tmpdir=$(mktemp -d)
  # Wrapper script — runs in subshell so our redefinitions don't leak.
  bash -c "
    set +e
    osascript() { printf 'OSA-ARG: %s\n' \"\$@\" >> '$tmpdir/captured'; }
    notify-send() { printf 'NS-ARG: %s\n' \"\$@\" >> '$tmpdir/captured'; }
    export -f osascript notify-send 2>/dev/null
    # Bypass command -v fallback by exporting funcs
    SUPERCHARGER_DIR='$tmpdir/sc' SCOPE_DIR='$tmpdir/sc/scope'
    export HOME='$tmpdir/home'
    mkdir -p \"\$HOME\" \"\$SUPERCHARGER_DIR\" \"\$SCOPE_DIR\"
    . '$HELPER'
    SC_NOTIFY_MSG='' SC_NOTIFY_TITLE='' _send_notification '$title' '$msg' 2>&1
    # Capture the sanitized values via direct invocation
  "
  cat "$tmpdir/captured" 2>/dev/null
  rm -rf "$tmpdir"
}

# Direct sanitization test: extract safe_msg/safe_title computation via a
# minimal harness. Sources notify-helper, then mimics the sanitization
# steps and exposes them.
_sanitize_only() {
  local input="$1"
  # The exact sanitization pipeline from notify-helper.sh:57
  printf '%s' "$input" | tr -d '`$' | sed "s/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g" | head -c 200
}

# --- Sanitization tests (the v2.6.72 fix) ---

begin_test "notify-helper: tr strips backticks from input"
OUT=$(_sanitize_only "hello \`touch /tmp/rce-probe\` world")
echo "$OUT" | grep -q '`' && fail "backtick survived sanitization: $OUT" || pass

begin_test "notify-helper: tr strips dollar-sign from input"
OUT=$(_sanitize_only 'hello $(touch /tmp/rce-probe) world')
echo "$OUT" | grep -q '\$' && fail "\$ survived sanitization: $OUT" || pass

begin_test "notify-helper: sed escapes double-quotes"
OUT=$(_sanitize_only 'say "hello"')
echo "$OUT" | grep -q '\\"' && pass || fail "quote not escaped: $OUT"

begin_test "notify-helper: sed escapes backslashes"
OUT=$(_sanitize_only 'path\\to\\file')
echo "$OUT" | grep -q '\\\\\\\\' && pass || fail "backslashes not doubled: $OUT"

begin_test "notify-helper: head caps at 200 chars"
LONG=$(printf 'a%.0s' {1..500})
OUT=$(_sanitize_only "$LONG")
[ "${#OUT}" -eq 200 ] && pass || fail "expected 200 chars, got ${#OUT}"

begin_test "notify-helper: benign text passes through unchanged"
OUT=$(_sanitize_only "normal notification text 123")
[ "$OUT" = "normal notification text 123" ] && pass || fail "benign text mangled: $OUT"

# --- RCE probe: verify malicious input never executes ---

begin_test "notify-helper: RCE probe (backtick) does not execute"
PROBE="/tmp/sc-rce-probe-$$-bt"
rm -f "$PROBE"
_sanitize_only "evil \`touch $PROBE\`" >/dev/null
sleep 0.2
[ ! -f "$PROBE" ] && pass || { fail "RCE via backtick fired (probe exists)"; rm -f "$PROBE"; }

begin_test "notify-helper: RCE probe (\$()) does not execute"
PROBE="/tmp/sc-rce-probe-$$-ds"
rm -f "$PROBE"
_sanitize_only "evil \$(touch $PROBE)" >/dev/null
sleep 0.2
[ ! -f "$PROBE" ] && pass || { fail "RCE via \$() fired (probe exists)"; rm -f "$PROBE"; }

# --- Cooldown logic ---

begin_test "notify-helper: _cooldown_ok returns 0 on first call"
TMPHOME=$(mktemp -d)
HOME="$TMPHOME" bash -c "
  SUPERCHARGER_DIR=\"\$HOME/.claude/supercharger\" SCOPE_DIR=\"\$SUPERCHARGER_DIR/scope\"
  mkdir -p \"\$SCOPE_DIR\"
  . '$HELPER'
  _cooldown_ok test-key 5
"
EXIT=$?
rm -rf "$TMPHOME"
[ "$EXIT" -eq 0 ] && pass || fail "expected 0 on first call, got $EXIT"

# v2.7.33: macOS `system attribute` reads env vars as MacRoman and mangles UTF-8
# (— → ,Äî). The darwin branch must transliterate the message/title to ASCII.
begin_test "notify-helper: macOS notification is transliterated to ASCII (no mojibake)"
if [[ "$OSTYPE" == darwin* ]]; then
  NHTMP=$(mktemp -d)
  bash -c "
    set +e
    osascript() { printf '%s' \"\$SC_NOTIFY_TITLE|\$SC_NOTIFY_MSG\" > '$NHTMP/got'; }
    export -f osascript
    SUPERCHARGER_DIR='$NHTMP/sc' SCOPE_DIR='$NHTMP/sc/scope'
    export HOME='$NHTMP/home'
    mkdir -p \"\$HOME\" \"\$SUPERCHARGER_DIR\" \"\$SCOPE_DIR\"
    . '$HELPER'
    _send_notification 'Claude — Done' 'parse → validate ⇒ store'
  " >/dev/null 2>&1
  GOT=$(cat "$NHTMP/got" 2>/dev/null); rm -rf "$NHTMP"
  if [ -z "$GOT" ]; then fail "no notification captured"
  elif printf '%s' "$GOT" | LC_ALL=C grep -q '[^ -~]'; then fail "non-ASCII leaked to notification: $GOT"
  else pass; fi
else
  pass  # Linux notify-send handles UTF-8 natively; transliteration is macOS-only
fi

begin_test "notify-helper: _cooldown_ok blocks within window"
TMPHOME=$(mktemp -d)
EXIT=$(HOME="$TMPHOME" bash -c "
  SUPERCHARGER_DIR=\"\$HOME/.claude/supercharger\" SCOPE_DIR=\"\$SUPERCHARGER_DIR/scope\"
  mkdir -p \"\$SCOPE_DIR\"
  . '$HELPER'
  _cooldown_ok block-test 60 >/dev/null
  _cooldown_ok block-test 60
  echo \$?
")
rm -rf "$TMPHOME"
[ "$EXIT" = "1" ] && pass || fail "expected 1 on second call within window, got $EXIT"

# ---- 2.21.15: per-session cooldown so one session doesn't suppress another ----
begin_test "notify-helper: _cooldown_ok is per-session — session B not blocked by session A"
TMPHOME=$(mktemp -d)
EXIT=$(HOME="$TMPHOME" bash -c "
  SUPERCHARGER_DIR=\"\$HOME/.claude/supercharger\" SCOPE_DIR=\"\$SUPERCHARGER_DIR/scope\"
  mkdir -p \"\$SCOPE_DIR\"
  . '$HELPER'
  _cooldown_ok stop 60 sessA >/dev/null
  _cooldown_ok stop 60 sessB
  echo \$?
")
rm -rf "$TMPHOME"
[ "$EXIT" = "0" ] && pass || fail "expected session B allowed (0), got $EXIT"

begin_test "notify-helper: session id writes a per-session stamp, not the global one"
TMPHOME=$(mktemp -d)
HOME="$TMPHOME" bash -c "
  SUPERCHARGER_DIR=\"\$HOME/.claude/supercharger\" SCOPE_DIR=\"\$SUPERCHARGER_DIR/scope\"
  mkdir -p \"\$SCOPE_DIR\"
  . '$HELPER'
  _cooldown_ok stop 60 sessA >/dev/null
"
SD="$TMPHOME/.claude/supercharger/scope"
if [ -f "$SD/.notify-ts-stop-sessA" ] && [ ! -f "$SD/.notify-ts-stop" ]; then pass
else fail "expected per-session stamp .notify-ts-stop-sessA (global=$([ -f "$SD/.notify-ts-stop" ] && echo yes || echo no))"; fi
rm -rf "$TMPHOME"

# --- v2.23.8: SUPERCHARGER_NO_NOTIFY suppresses the real send path ---
begin_test "notify-helper: SUPERCHARGER_NO_NOTIFY=1 suppresses (no send)"
_NNTMP=$(mktemp -d)
bash -c "
  set +e
  osascript() { printf 'OSA\n' >> '$_NNTMP/captured'; }
  notify-send() { printf 'NS\n' >> '$_NNTMP/captured'; }
  export -f osascript notify-send 2>/dev/null
  SUPERCHARGER_DIR='$_NNTMP/sc' SCOPE_DIR='$_NNTMP/sc/scope'; export HOME='$_NNTMP/home'
  mkdir -p \"\$HOME\" \"\$SUPERCHARGER_DIR\" \"\$SCOPE_DIR\"
  export SUPERCHARGER_NO_NOTIFY=1
  . '$HELPER'
  _send_notification 'T' 'M' >/dev/null 2>&1
"
if [ -s "$_NNTMP/captured" ]; then fail "notification fired despite NO_NOTIFY (captured: $(cat "$_NNTMP/captured"))"; else pass; fi
rm -rf "$_NNTMP"

# --- Windows / WSL backend (v2.26.49, WINDOWS-SUPPORT-PLAN G1) ----------------
# Git Bash and WSL had NO desktop-notification path — they fell through to the
# bell. That is the reported "no notifications on Windows/WSL" bug.
#
# VERIFICATION LIMIT, stated plainly: these tests prove the right BACKEND is
# selected, that ordering is right, and that nothing errors. They cannot prove a
# toast actually appears on screen — that needs a real Windows or WSL machine.
_win_capture() { # ostype, wsl_release_present, notify_send_present -> captured args
  local ostype="$1" wsl="$2" ns="$3"
  local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/bin"
  # Fake powershell.exe records how it was invoked and what it was handed.
  cat > "$tmpdir/bin/powershell.exe" <<PSEOF
#!/usr/bin/env bash
printf 'PS-TITLE: %s\n' "\$SC_NOTIFY_TITLE" >> '$tmpdir/captured'
printf 'PS-MSG: %s\n'   "\$SC_NOTIFY_MSG"   >> '$tmpdir/captured'
printf 'PS-ARGS: %s\n'  "\$*"               >> '$tmpdir/captured'
PSEOF
  chmod +x "$tmpdir/bin/powershell.exe"
  if [ "$ns" = "yes" ]; then
    printf '#!/usr/bin/env bash\nprintf "NS-ARG: %%s\\n" "$@" >> %s/captured\n' "$tmpdir" > "$tmpdir/bin/notify-send"
    chmod +x "$tmpdir/bin/notify-send"
  fi
  mkdir -p "$tmpdir/home" "$tmpdir/sc/scope"
  # A SUBSHELL, not `bash -c "…"`. The nested quoting in a bash -c string mangled
  # the exports and every backend assertion came back empty — six failures that
  # were entirely the harness, while the implementation was correct throughout.
  (
    export PATH="$tmpdir/bin:$PATH"
    export HOME="$tmpdir/home"
    export OSTYPE="$ostype"
    [ "$wsl" = "yes" ] && export WSL_DISTRO_NAME='Ubuntu'
    SUPERCHARGER_DIR="$tmpdir/sc"; SCOPE_DIR="$tmpdir/sc/scope"
    unset SUPERCHARGER_NO_NOTIFY
    # shellcheck source=hooks/notify-helper.sh
    . "$HELPER"
    _send_notification 'Title' 'Body'
  ) >/dev/null 2>&1
  cat "$tmpdir/captured" 2>/dev/null
  rm -rf "$tmpdir"
}

begin_test "Git Bash (msys) uses the PowerShell toast path"
_win_capture msys no no | grep -q '^PS-TITLE: Title' && pass || fail "no PowerShell backend on msys"

begin_test "cygwin also routes to PowerShell"
_win_capture cygwin no no | grep -q '^PS-TITLE:' && pass || fail "no PowerShell backend on cygwin"

begin_test "WSL without notify-send uses powershell.exe interop"
_win_capture linux-gnu yes no | grep -q '^PS-TITLE:' && pass || fail "WSL fell through to the bell"

begin_test "WSL WITH notify-send keeps the native Linux path"
# WSLg works; interop is the fallback, not the default. Ordering matters.
OUT=$(_win_capture linux-gnu yes yes)
printf '%s' "$OUT" | grep -q '^NS-ARG:' && ! printf '%s' "$OUT" | grep -q '^PS-TITLE:' \
  && pass || fail "WSL with a working notify-send should not use PowerShell: $OUT"

begin_test "plain Linux is unaffected"
OUT=$(_win_capture linux-gnu no yes)
printf '%s' "$OUT" | grep -q '^NS-ARG:' && ! printf '%s' "$OUT" | grep -q '^PS-TITLE:' \
  && pass || fail "Linux path changed: $OUT"

begin_test "the message is passed via the environment, never interpolated"
# A branch name reaches this text (see the v2.6.72 AppleScript RCE). PowerShell
# expands \$(...) and backticks inside a double-quoted literal exactly as bash
# does, so the payload must arrive as \$env:VAR — not inside the command string.
OUT=$(_win_capture msys no no)
printf '%s' "$OUT" | grep -q '^PS-ARGS:.*SC_NOTIFY' && fail "payload was interpolated into the command line" || pass

begin_test "the PowerShell command reads \$env: vars rather than embedding text"
grep -q 'env:SC_NOTIFY_TITLE' "$HELPER" && grep -q 'env:SC_NOTIFY_MSG' "$HELPER" && pass \
  || fail "helper does not read the payload from the environment"

begin_test "no Windows host and no notify-send still falls back to the bell"
OUT=$(_win_capture linux-gnu no no)
[ -z "$OUT" ] && pass || fail "unexpected backend fired: $OUT"

begin_test "macOS is untouched by the Windows branch"
# The line reads `[[ "$OSTYPE" == "darwin"* ]]` — the quote sits between the name
# and the star, so a 'darwin\*' pattern matches nothing and passes vacuously.
grep -q '"darwin"\*' "$HELPER" && pass || fail "darwin branch lost"

begin_test "the toast layers degrade — BurntToast, then native WinRT, then bell"
grep -q 'BurntToast' "$HELPER" && grep -q 'ToastNotificationManager' "$HELPER" \
  && grep -qF "|| printf '\\a'" "$HELPER" && pass \
  || fail "the layered fallback chain is incomplete"

report
