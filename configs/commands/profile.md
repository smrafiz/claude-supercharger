Show or switch the active performance profile. Arguments: $ARGUMENTS

## Show current profile (no arguments)

Run this inline shell to report current state:

```bash
python3 << 'EOF'
import os

scope = os.path.expanduser("~/.claude/supercharger/scope")
profile_file = os.path.join(scope, ".profile")
env_profile = os.environ.get("SUPERCHARGER_PROFILE", "")

# The hooks resolve the profile per project first (lib-paths.sh sc_scope_resolve):
# .profile-<project key>, written from this project's .supercharger.json "profile".
k = os.getcwd().replace("/", "-").replace("\\", "-").replace(":", "-").lstrip("-")
k = (k[-100:] if len(k) > 100 else k) or "root"
project_file = os.path.join(scope, ".profile-" + k)

if env_profile:
    source = "env var (SUPERCHARGER_PROFILE)"
    active = env_profile
elif os.path.isfile(project_file):
    with open(project_file) as f:
        active = f.read().strip()
    source = "this project's .supercharger.json"
elif os.path.isfile(profile_file):
    with open(profile_file) as f:
        active = f.read().strip()
    source = f"scope file ({profile_file})"
else:
    active = "standard"
    source = "default"

profiles = {
    "standard": ("all hooks active", []),
    "fast":     ("skips 7 analytics hooks, keeps code-quality checks",
                 ["adaptive-economy", "rate-limit-advisor",
                  "mcp-tracker", "failure-tracker", "session-checkpoint",
                  "repetition-detector", "context-advisor"]),
    "minimal":  ("skips 10 hooks — all non-security",
                 ["quality-gate", "typecheck", "dep-vuln-scanner",
                  "adaptive-economy", "rate-limit-advisor",
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
# A per-project profile (from this project's .supercharger.json) takes precedence
# over the global one written above — say so rather than report a switch that
# will not apply here.
KEY=$(pwd | tr '/\\:' '---' | sed 's/^-//' | tail -c 101); [ -z "$KEY" ] && KEY=root
if [ -f "$SCOPE_DIR/.profile-$KEY" ] && [ -n "$PROFILE" ]; then
  echo "Note: this project's .supercharger.json sets \"profile\": \"$(cat "$SCOPE_DIR/.profile-$KEY")\", which overrides the global setting here. Change it in .supercharger.json for this project."
fi
```

After switching, briefly note what changed:
- **standard → fast**: analytics/tracking hooks skip, code-quality hooks still run
- **standard → minimal**: all non-security hooks skip — maximum speed
- **fast/minimal → standard**: all hooks re-enabled
- **Note:** env var `SUPERCHARGER_PROFILE` overrides the scope file — unset it if switching via this command has no effect
