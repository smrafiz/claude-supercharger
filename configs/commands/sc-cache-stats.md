Show hook cache statistics for typecheck and quality-gate. Arguments: $ARGUMENTS

Run this inline Python to report cache state:

```bash
python3 << 'EOF'
import os, json, glob, time

scope = os.path.expanduser("~/.claude/supercharger/scope")

def report_cache(label, pattern):
    files = glob.glob(os.path.join(scope, pattern))
    if not files:
        print(f"{label}: no cache files found")
        return
    total_entries = 0
    stale = 0
    for path in files:
        try:
            with open(path) as f:
                d = json.load(f)
            entries = len(d)
            dead = sum(1 for k in d if not os.path.exists(k))
            age_days = (time.time() - os.path.getmtime(path)) / 86400
            print(f"{label} [{os.path.basename(path)}]: {entries} entries, {dead} stale, last written {age_days:.1f}d ago")
            total_entries += entries
            stale += dead
        except Exception as e:
            print(f"{label} [{os.path.basename(path)}]: unreadable ({e})")
    print(f"  Total: {total_entries} entries, {stale} stale across {len(files)} project(s)")

report_cache("typecheck   ", ".typecheck-cache-*")
report_cache("quality-gate", ".quality-gate-cache-*")
EOF
```

After showing output, interpret it:
- **stale > 0**: stale entries exist but will self-prune on next cache write — no action needed
- **no cache files**: caches haven't been written yet (hooks haven't run a clean pass on any file)
- **age > 7d**: cache may be for a project no longer active — mention it but don't delete
- **large entry count (>500)**: note it, suggest it's normal for large codebases
