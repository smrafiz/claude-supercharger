Show or switch the active performance profile. Arguments: $ARGUMENTS

## Show current profile (no arguments)

Run this inline shell to report current state:

```bash
python3 << 'EOF'
import os

scope = os.path.expanduser("~/.claude/supercharger/scope")
profile_file = os.path.join(scope, ".profile")
env_profile = os.environ.get("SUPERCHARGER_PROFILE", "")

if env_profile:
    source = "env var (SUPERCHARGER_PROFILE)"
    active = env_profile
elif os.path.isfile(profile_file):
    with open(profile_file) as f:
        active = f.read().strip()
    source = f"scope file ({profile_file})"
else:
    active = "standard"
    source = "default"

profiles = {
    "standard": ("all hooks active", []),
    "fast":     ("skips 8 analytics hooks, keeps code-quality checks",
                 ["adaptive-economy", "thinking-budget", "rate-limit-advisor",
                  "mcp-tracker", "failure-tracker", "session-checkpoint",
                  "repetition-detector", "context-advisor"]),
    "minimal":  ("skips 11 hooks — all non-security",
                 ["quality-gate", "typecheck", "dep-vuln-scanner",
                  "adaptive-economy", "thinking-budget", "rate-limit-advisor",
                  "mcp-tracker", "failure-tracker", "session-checkpoint",
                  "repetition-detector", "context-advisor"]),
}

print(f"Active profile : {active}  (from {source})")
desc, skipped = profiles.get(active, ("unknown profile", []))
print(f"Description    : {desc}")
if skipped:
    print(f"Skipped hooks  : {', '.join(skipped)}")
print()
print("Available profiles:")
for name, (d, _) in profiles.items():
    marker = "●" if name == active else "○"
    print(f"  {marker} {name:10s} — {d}")
print()
print("Switch: /profile fast  |  /profile minimal  |  /profile standard")
print("Or set per-project: add {\"profile\": \"fast\"} to .supercharger.json")
EOF
```

## Switch profile (e.g. /profile fast)

Parse the argument from `$ARGUMENTS`. If a profile name is given (`standard`, `fast`, or `minimal`), write it to the scope file:

```bash
PROFILE=$(echo "$ARGUMENTS" | tr -d '[:space:]')
SCOPE_DIR="$HOME/.claude/supercharger/scope"
PROFILE_FILE="$SCOPE_DIR/.profile"

case "$PROFILE" in
  standard)
    [ -f "$PROFILE_FILE" ] && rm -f "$PROFILE_FILE"
    echo "Profile set to: standard (all hooks active). Takes effect next hook run."
    ;;
  fast|minimal)
    mkdir -p "$SCOPE_DIR"
    printf '%s' "$PROFILE" > "$PROFILE_FILE"
    echo "Profile set to: $PROFILE. Takes effect next hook run."
    ;;
  "")
    # No argument — show current (already handled by the Python block above)
    ;;
  *)
    echo "Unknown profile: $PROFILE"
    echo "Valid options: standard, fast, minimal"
    ;;
esac
```

After switching, briefly note what changed:
- **standard → fast**: analytics/tracking hooks skip, code-quality hooks still run
- **standard → minimal**: all non-security hooks skip — maximum speed
- **fast/minimal → standard**: all hooks re-enabled
- **Note:** env var `SUPERCHARGER_PROFILE` overrides the scope file — unset it if switching via this command has no effect
