#!/usr/bin/env bash
# 4.3.0 macOS notifier app: notify-helper prefers it, falls back to osascript when
# it is missing or refuses (notifications off for it), and the app really builds.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

if [[ "$OSTYPE" != darwin* ]]; then
  begin_test "notifier: macOS only"; pass; report; exit 0
fi

# send <notifier-exit-code|none> -> "notifier:<args>" and/or "osascript" lines
send() {
  local d; d=$(mktemp -d); mkdir -p "$d/bin" "$d/home/.claude/supercharger/scope"
  printf '#!/bin/sh\necho osascript >> "%s/log"\n' "$d" > "$d/bin/osascript"; chmod +x "$d/bin/osascript"
  local nb="$d/notifier"
  if [ "$1" != none ]; then
    printf '#!/bin/sh\necho "notifier:$1|$2|$3|$4" >> "%s/log"\nexit %s\n' "$d" "$1" > "$nb"; chmod +x "$nb"
  fi
  mkdir -p "$d/myproj"; ( cd "$d/myproj" && env -u SUPERCHARGER_NO_NOTIFY HOME="$d/home" PATH="$d/bin:$PATH" SUPERCHARGER_NOTIFIER="$nb" \
    __CFBundleIdentifier=dev.warp.Warp-Stable bash -c '
      source "$1/hooks/notify-helper.sh"; _send_notification "Claude — Done" "body text" "main"' _ "$REPO_DIR" 2>/dev/null )
  cat "$d/log" 2>/dev/null; rm -rf "$d"
}

begin_test "notifier: used when present — project in the title, calling app's bundle id for click-to-focus"
OUT=$(send 0)
{ printf '%s' "$OUT" | grep -q '^notifier:Claude — Done · myproj|body text|main|dev.warp.Warp-Stable$' \
  && ! printf '%s' "$OUT" | grep -q osascript; } && pass || fail "got: $OUT"

begin_test "notifier: notifications off for the app (exit 2) falls back to osascript"
OUT=$(send 2)
printf '%s' "$OUT" | grep -q '^osascript$' && pass || fail "got: $OUT"

begin_test "notifier: no app installed falls back to osascript"
OUT=$(send none)
[ "$OUT" = osascript ] && pass || fail "got: $OUT"

# Consent: the app installs a program outside ~/.claude, so an install or update
# that was never told yes must not build it — only mention it.
begin_test "notifier: stays quiet while the app Claude runs in is frontmost (exit 0, no osascript fallback)"
_F=$(osascript -e 'id of application (path to frontmost application as text)' 2>/dev/null)
_ND=$(mktemp -d)
if [ -z "$_F" ] || ! command -v swiftc >/dev/null 2>&1 || ! swiftc -O "$REPO_DIR/tools/notifier/main.swift" -o "$_ND/n" 2>/dev/null; then
  echo "    (skipped: no frontmost app or no Swift)"; pass
else
  _E=$("$_ND/n" t b "" "$_F" 2>&1); _RC=$?
  { [ "$_RC" = 0 ] && [[ "$_E" == "skipped: $_F is frontmost"* ]] \
    && grep -q 'SUPERCHARGER_NOTIFY_WHEN_FOCUSED' "$REPO_DIR/tools/notifier/main.swift"; } && pass || fail "rc=$_RC out=$_E"
fi
rm -rf "$_ND"

begin_test "notifier: a non-interactive install (what updates run) does not install the app, only tells the user"
H=$(mktemp -d)
OUT=$(env -u SUPERCHARGER_NO_NOTIFIER HOME="$H" bash "$REPO_DIR/install.sh" --mode full --roles developer \
  --config deploy --settings deploy --economy lean 2>&1)
{ [ ! -e "$H/Applications/Claude Supercharger.app" ] && printf '%s' "$OUT" | grep -q '/sc-notifier'; } \
  && pass || fail "app built without consent, or no tip: $(printf '%s' "$OUT" | grep -i notifier)"
rm -rf "$H"

begin_test "notifier: interactive install — no answer installs nothing, 'y' installs the app"
H1=$(mktemp -d); H2=$(mktemp -d)
printf '\n1\n' | env -u SUPERCHARGER_NO_NOTIFIER HOME="$H1" bash "$REPO_DIR/install.sh" >/dev/null 2>&1
if xcrun --find swiftc >/dev/null 2>&1; then
  printf '\n1\ny\n' | env -u SUPERCHARGER_NO_NOTIFIER HOME="$H2" SC_NOTIFIER_NO_REGISTER=1 bash "$REPO_DIR/install.sh" >/dev/null 2>&1
  Y_OK=$([ -x "$H2/Applications/Claude Supercharger.app/Contents/MacOS/notifier" ] && echo yes)
else Y_OK=yes; fi
{ [ ! -e "$H1/Applications/Claude Supercharger.app" ] && [ "$Y_OK" = yes ]; } && pass \
  || fail "default-no built=$([ -e "$H1/Applications/Claude Supercharger.app" ] && echo yes || echo no) y-installed=${Y_OK:-no}"
rm -rf "$H1" "$H2"

begin_test "notifier: the app builds, is signed, and a rebuild of unchanged source is skipped"
if xcrun --find swiftc >/dev/null 2>&1; then
  T=$(mktemp -d)
  B1=$(SC_NOTIFIER_NO_REGISTER=1 bash "$REPO_DIR/tools/notifier/build.sh" "$T")
  B2=$(SC_NOTIFIER_NO_REGISTER=1 bash "$REPO_DIR/tools/notifier/build.sh" "$T")
  { [ -x "$T/Claude Supercharger.app/Contents/MacOS/notifier" ] \
    && codesign -v "$T/Claude Supercharger.app" 2>/dev/null \
    && printf '%s' "$B1" | grep -q built && [ -z "$B2" ]; } && pass || fail "build=[$B1] rebuild=[$B2]"
  rm -rf "$T"
else
  pass  # no Swift: install skips the app and osascript is used (covered above)
fi

report
