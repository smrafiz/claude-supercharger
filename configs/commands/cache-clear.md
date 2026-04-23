Clear typecheck and quality-gate hash caches. Arguments: $ARGUMENTS

Runs `tools/cache-clear.sh` to remove all cached hash files so hooks re-check all files on next run.

```bash
if [ -f "$(dirname "$0")/../../tools/cache-clear.sh" ]; then
  bash "$(dirname "$0")/../../tools/cache-clear.sh" $ARGUMENTS
elif [ -f "$HOME/.claude/supercharger/tools/cache-clear.sh" ]; then
  bash "$HOME/.claude/supercharger/tools/cache-clear.sh" $ARGUMENTS
else
  echo "cache-clear.sh not found. Re-run install.sh to restore tools."
fi
```

**Options:**
- No args — clears all cache files immediately
- `--dry-run` — shows what would be removed without deleting

**When to use:**
- After moving or renaming files (stale keys from old paths won't prune themselves until next write)
- After a hook misconfiguration produced incorrect cache entries
- When forcing a full re-check for a security audit

After running, the next hook execution will re-hash all files from scratch.
