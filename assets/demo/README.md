# Demo assets

Terminal recording showing Supercharger's shell hooks denying destructive
commands (exit code 2) before they run — no install required, nothing executes.

## Regenerate the GIF

```bash
brew install vhs            # https://github.com/charmbracelet/vhs
vhs assets/demo/demo.tape   # run from the repo root → writes assets/demo/demo.gif
```

## Files

- `demo.tape` — VHS script driving the recording
- `try.sh` — helper: pipes a command string through `safety.sh` / `git-safety.sh`
  and prints `BLOCKED` / `allowed`. Reusable on its own:
  `./assets/demo/try.sh 'rm -rf /'`
- `demo.gif` — generated output (commit after regenerating)
