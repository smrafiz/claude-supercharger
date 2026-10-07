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

STAMP=$(cat "$SRC/main.swift" "$SRC/Info.plist" | shasum -a 256 | cut -c1-16)
if [ "$(cat "$APP/Contents/Resources/source-hash" 2>/dev/null)" = "$STAMP" ]; then
  exit 0
fi

TMP=$(mktemp -d) || exit 0
trap 'rm -rf "$TMP"' EXIT
B="$TMP/Claude Supercharger.app/Contents"
mkdir -p "$B/MacOS" "$B/Resources"
cp "$SRC/Info.plist" "$B/Info.plist"
echo "$STAMP" > "$B/Resources/source-hash"
xcrun swiftc -O "$SRC/main.swift" -o "$B/MacOS/notifier" 2>"$TMP/err" || {
  echo "notifier: build failed — using osascript notifications"; sed 's/^/  /' "$TMP/err" | head -5; exit 0; }
codesign --force -s - "$TMP/Claude Supercharger.app" 2>/dev/null || {
  echo "notifier: signing failed — using osascript notifications"; exit 0; }

mkdir -p "$DEST" && rm -rf "$APP" && mv "$TMP/Claude Supercharger.app" "$APP" || exit 0
[ -n "${SC_NOTIFIER_NO_REGISTER:-}" ] || /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
echo "notifier: built $APP"
echo "  Turn it on once: System Settings → Notifications → Claude Supercharger → Allow notifications"
