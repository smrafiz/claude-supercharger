#!/usr/bin/env bash
# Build "Claude Supercharger.app" (the macOS notifier) into a directory, sign it
# locally (ad-hoc) and register it with LaunchServices. macOS only; needs Swift
# (Xcode Command Line Tools). Skips the build when the installed app was built
# from the same source. Never fatal: no app just means osascript notifications.
#
#   bash tools/notifier/build.sh [dest-dir]     (default: ~/Applications)
set -uo pipefail
case "${OSTYPE:-}" in darwin*) ;; *) exit 0 ;; esac
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$HOME/Applications}"
APP="$DEST/Claude Supercharger.app"
command -v xcrun >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1 || {
  echo "notifier: Swift not found (xcode-select --install) — using osascript notifications"; exit 0; }

STAMP=$(cat "$SRC/main.swift" "$SRC/Info.plist" "$SRC/icon.swift" | shasum -a 256 | cut -c1-16)
if [ "$(cat "$APP/Contents/Resources/source-hash" 2>/dev/null)" = "$STAMP" ]; then
  exit 0
fi

TMP=$(mktemp -d) || exit 0
trap 'rm -rf "$TMP"' EXIT

# Progress: the Swift steps take ~20-30s with no output of their own, which read
# as a hang. A spinner on a terminal; one line per step otherwise (piped, CI).
_step() { # label, command... -> runs the command, shows progress, keeps its status
  local label="$1"; shift
  if [ -t 1 ]; then
    "$@" & local pid=$! i=0 f='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r%s %s ' "$label" "${f:i++%4:1}"; sleep 0.2
    done
    wait "$pid"; local rc=$?
    printf '\r%s %s\n' "$label" "$([ $rc -eq 0 ] && echo done || echo failed)"
    return $rc
  fi
  echo "$label"; "$@"
}
echo "notifier: building the notification app (about 30 seconds)"
B="$TMP/Claude Supercharger.app/Contents"
mkdir -p "$B/MacOS" "$B/Resources"
cp "$SRC/Info.plist" "$B/Info.plist"
echo "$STAMP" > "$B/Resources/source-hash"
_step "  compiling..." xcrun swiftc -O "$SRC/main.swift" -o "$B/MacOS/notifier" 2>"$TMP/err" || {
  echo "notifier: build failed — using osascript notifications"; sed 's/^/  /' "$TMP/err" | head -5; exit 0; }
# Icon, drawn by icon.swift (no binary in the repo). Optional: no icon on failure.
if _step "  drawing the icon..." xcrun swift "$SRC/icon.swift" "$TMP/icon.png" 2>/dev/null; then
  mkdir -p "$TMP/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null 2>&1
    sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null 2>&1
  done
  iconutil -c icns "$TMP/AppIcon.iconset" -o "$B/Resources/AppIcon.icns" 2>/dev/null || true
fi
codesign --force -s - "$TMP/Claude Supercharger.app" 2>/dev/null || {
  echo "notifier: signing failed — using osascript notifications"; exit 0; }

LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Notification Center caches an app's icon the first time it sees it, and an
# in-place rebuild does not refresh it (measured: blank until unregister + reinstall
# + restart). So when replacing a copy that had no icon, do exactly that, once.
_sc_refresh_icon=""
[ -d "$APP" ] && [ ! -f "$APP/Contents/Resources/AppIcon.icns" ] && _sc_refresh_icon=1
[ -n "$_sc_refresh_icon" ] && [ -z "${SC_NOTIFIER_NO_REGISTER:-}" ] && "$LSREG" -u "$APP" 2>/dev/null
mkdir -p "$DEST" && rm -rf "$APP" && mv "$TMP/Claude Supercharger.app" "$APP" || exit 0
[ -n "${SC_NOTIFIER_NO_REGISTER:-}" ] || "$LSREG" -f "$APP" 2>/dev/null || true
[ -n "$_sc_refresh_icon" ] && [ -z "${SC_NOTIFIER_NO_REGISTER:-}" ] && killall NotificationCenter usernoted 2>/dev/null
echo "notifier: built $APP"
if [ -n "$_sc_refresh_icon" ]; then
  echo "  macOS may have switched its notifications off while refreshing the icon:"
  echo "  System Settings → Notifications → Claude Supercharger → Allow notifications"
else
  echo "  Turn it on once: System Settings → Notifications → Claude Supercharger → Allow notifications"
fi
