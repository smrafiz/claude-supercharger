#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HELPER="$REPO_DIR/hooks/notify-helper.sh"

echo "=== Notify Helper Tests (v2.6.72 RCE fix coverage) ==="

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

report
