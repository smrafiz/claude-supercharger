---
description: "Install, check or remove the macOS notifier app (notifications as Claude Supercharger instead of Script Editor)."
argument-hint: "[install|status|remove]"
disable-model-invocation: true
---
Manage the optional macOS notifier app. Arguments: $ARGUMENTS

The app is `~/Applications/Claude Supercharger.app`, about 40 lines of Swift built on this Mac from Supercharger's own source (`tools/notifier/`). With it, notifications show as "Claude Supercharger" and a click returns to the terminal or editor you were in. Without it they show as "Script Editor". It is never installed without the user asking; this command is that ask.

macOS only. If this is not macOS, say so and stop.

**`install`** (or no argument) — tell the user in one line what will be installed and where, then build it:

```bash
bash ~/.claude/supercharger/tools/notifier/build.sh
```

Report the output. If it says Swift was not found, tell the user to run `xcode-select --install` and try again. After a successful build, open the settings page and tell the user to switch on "Allow notifications" for Claude Supercharger — macOS keeps it off until they do:

```bash
open "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
```

**`status`** — report whether the app is installed and whether it can post:

```bash
A="$HOME/Applications/Claude Supercharger.app"
if [ -x "$A/Contents/MacOS/notifier" ]; then
  "$A/Contents/MacOS/notifier" "Claude Supercharger" "Notifier test" >/dev/null 2>&1
  case $? in 0) echo "installed, notifications allowed (a test banner was sent)";;
             2) echo "installed, but notifications are OFF — System Settings → Notifications → Claude Supercharger";;
             *) echo "installed, but posting failed";; esac
else echo "not installed — notifications use Script Editor"; fi
```

**`remove`** — confirm with the user first, then remove only our app (checked by bundle id) and unregister it:

```bash
A="$HOME/Applications/Claude Supercharger.app"
grep -q dev.supercharger.notifier "$A/Contents/Info.plist" 2>/dev/null \
  && /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$A" 2>/dev/null; \
  grep -q dev.supercharger.notifier "$A/Contents/Info.plist" 2>/dev/null && rm -r "$A" && echo removed || echo "not installed"
```

Notifications fall back to Script Editor after removal. Updates never reinstall it once removed.
