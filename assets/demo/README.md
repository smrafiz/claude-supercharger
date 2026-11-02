# Demo assets

Terminal recording of Supercharger deciding on commands before they run: allowed,
blocked (exit code 2), or asked about first (with how many files have no undo),
then the statusline. Nothing executes, and every message is produced live by the
hooks in this checkout.

## Regenerate the GIF

```bash
brew install vhs            # https://github.com/charmbracelet/vhs
vhs assets/demo/demo.tape   # run from the repo root → writes assets/demo/demo.gif
```

Re-render after changing a hook message, so the GIF never shows old wording.

## Files

- `demo.tape` — VHS script driving the recording
- `try.sh` — pipes a command string through `safety.sh`, `git-safety.sh` and
  `blast-radius-guard.sh` and prints `BLOCKED` / `ASKS` / `allowed` with the reason.
  Reusable on its own: `./assets/demo/try.sh 'rm -rf /'` (`TRY_CWD=<dir>` sets the project)
- `fixture.sh` — creates a throwaway git project with committed, edited and
  never-committed files, so the `rm -rf src` prompt has real files to count
- `statusline.sh` — renders the real statusline from a fixed sample payload in a
  throwaway HOME (5-hour and weekly usage included)
- `demo.gif` — generated output (commit after regenerating)
