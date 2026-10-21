# 017 — Upstream Sync Process: Action Log

Per-commit verdicts for every round live in [upstream-ledger.md](upstream-ledger.md);
this log records the rounds themselves and their headline decisions.

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-03-06 – 03-24 | (pre-process) wholesale `upstream/main` merges; last one lands via PR #46; merge-base frozen at upstream `db6d189b` | PR #46 |
| 2026-04-01 | (transitional) selective upstream cherry-picks + dependency bumps | PR #119 |
| 2026-04-08 | **Process established**: change log converted to dated review log with Upstream Baseline table; `/check-upstream-changes` added as a skill; baseline set to `0150ceaf` (v0.8.0). Review noted upstream `ce214902` overlaps fork issue #178 (global worktree defaults) | PR #193 |
| 2026-04-20 | **Round 2** — 47 commits through `c4e9be3b` (v0.8.1). Headline skips: upstream **Tuist migration** (fork's SwiftPM `ProwlCLI` sidesteps the archive bug that motivated it; migrating would rewrite the release/notarization flow for no gain) and upstream **`supacode` CLI** (orchestration-focused, orthogonal to the fork's agent-scripting `prowl` CLI). Upstream #225 (`toggle-background-opacity` cleanup) deferred "to next sync of the affected files" | commit `013be91e` |
| 2026-05-08 | **Round 3** — 25 commits through `5e88ec5d` (post-v0.8.5). First round with a port batch: fork PRs #255, #256, #260–#264, #266 (Ghostty key routing, fork-aware PR repo resolution, worktree history, window title/quit behavior, Android Studio, CI concurrency, …). Two further listed ports were closed unmerged: #265 (sidebar right-arrow focus) and #267 (`CFBundleIconName`). Headline skip: upstream per-repo title/color (#276 upstream) — fork keeps its richer repo-appearance model (see [025](../025-repo-identity-appearance/000-plan.md)) | PR #268 (`5dd20d81`) |
| 2026-05-09 | Ledger records the fork-only Ghostty C API patch (`ghostty_surface_pid`, patched `onevcat/ghostty` branch) — detail in [030](../030-agent-status-detection/000-plan.md) | commit `963480cd` |
| 2026-06-09 | **Round 4** — 55 commits through `1d888dbc` (post-v0.10.2, upstream v0.9.0→v0.10.2). Ports as fork PRs #414–#425 (perf wave #414–#417, gh JSON noise #418, merge-queue state #425, worktree name/parent override #424, …). Headline skips: the whole **zmx terminal-persistence track** (fork keeps its own layout persistence, see [014](../014-terminal-layout-persistence/000-plan.md)) and **hook-driven agent integrations** (upstream settings/hook modules absent in fork). Entry adds two new ledger sections: "Not yet ported — re-evaluate next round" and a full upstream commit inventory | commit `2948302e` |
| 2026-07-06 – 07-09 | **Round 5** — 70 commits through `bcbc4059` (post-v0.10.5, upstream v0.10.3→v0.10.5). First plan-doc-first round: per-commit verdicts written up before porting (PR #547, kept verbatim as [batch-2026-07-06-post-v0.10.5.md](batch-2026-07-06-post-v0.10.5.md)); ports #541–#546; **remote SSH track deferred → Linear CLAW-98**, **searchable base-ref filter deferred → Linear CLAW-99**; baseline advanced after the port PRs merged | PRs #547, #541–#546, #549 (`2197d13e`) — see [002](002-plan-doc-batch-workflow.md) |
| 2026-07-12 | `/check-upstream-changes` retargeted to read the ledger at `docs-ai/017-upstream-sync-process/upstream-ledger.md` as part of the docs-ai migration | branch `docs/ai-docs-backfill` |
| 2026-10-18 | **Process retired**: the fork no longer tracks upstream. Removed the `upstream` remote, `/check-upstream-changes`, `scripts/sync-upstream-main.sh`, the upstream-PR hook, and the upstream steps in the release runbook and `AGENTS.md`. The ledger stays as history | this PR |

## Outcome & current state (as of 2026-10-18)

- The process is retired. The fork no longer tracks `supabitapp/supacode` and has no
  `upstream` remote. Do not run new review rounds or update the ledger.
- Last baseline: `bcbc4059` (post-v0.10.5, 2026-07-06), recorded in the ledger's
  Upstream Baseline table.
- The ledger is [upstream-ledger.md](upstream-ledger.md) in this folder (history only,
  non-numbered; migrating from the fork's old change-log location in the docs-ai
  migration). Its "Old Log" tail preserves the retired per-commit table.
- `.claude/skills/check-upstream-changes/` and `scripts/sync-upstream-main.sh` are removed.
- No upstream merge commit exists after `db6d189b` (2026-03-23) — all later upstream
  adoption is via fork PRs listed in the ledger's port tables.
- Five review rounds are on record: 2026-04-08 (v0.8.0), 2026-04-20 (v0.8.1),
  2026-05-08 (post-v0.8.5), 2026-06-09 (post-v0.10.2), 2026-07-09 (post-v0.10.5).

## Deviations from plan

- Baseline-advance timing was only formalized in round 5 ("advance the baseline only
  after the batch's port PRs merge"); earlier rounds advanced the baseline in the same
  commit as the review log, before or alongside the ports.
- The ledger's 2026-05-08 "Ported to Prowl PRs" list includes #265 and #267, but both
  were closed without merging (#267 deliberately: "not useful since we are not using
  Icon Composer yet"); the ledger entry was never corrected.

## Open questions

- The 2026-04-20 deferred item — replace the fork's `toggle-background-opacity`
  implementation with upstream #225's runtime-level version "when next editing the
  affected files" — appears never executed: the toggle state is still per-view
  (`isBackgroundOpaqueOverride` in
  `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift`), although those files
  have been edited since.
- PR #265 (sidebar right-arrow focus port) was closed unmerged after an LGTM review,
  with no recorded reason; unclear whether the behavior was superseded or dropped.
