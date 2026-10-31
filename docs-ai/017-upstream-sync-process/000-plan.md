# 017 — Upstream Sync Process: Plan

| | |
| --- | --- |
| **Status** | Retired (2026-10-18) |
| **Anchor date** | 2026-04-08 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #193 (process establishment); review rounds landed as #268, #547, #549 and direct docs commits `013be91e`, `2948302e` |
| **Sources** | [upstream-ledger.md](upstream-ledger.md) (living ledger, migrated from the fork change log), [batch-2026-07-06-post-v0.10.5.md](batch-2026-07-06-post-v0.10.5.md) (kept verbatim), PR #193/#547 descriptions, `.claude/skills/check-upstream-changes/SKILL.md` |
| **Related** | [001-fork-bootstrap-and-release-pipeline](../001-fork-bootstrap-and-release-pipeline/000-plan.md) (sync/release mechanics), [013-prowl-cli](../013-prowl-cli/000-plan.md), [014-terminal-layout-persistence](../014-terminal-layout-persistence/000-plan.md), [030-agent-status-detection](../030-agent-status-detection/000-plan.md) |

## Background

`onevcat/Prowl` tracks `supabitapp/supacode` as the `upstream` remote. In the fork's
first month upstream was integrated wholesale: repeated
`git merge upstream/main` commits (last one on 2026-03-24 via PR #46; the merge-base
with upstream is still `db6d189b`, 2026-03-23). As fork-only surface grew — the Prowl
rebrand, Canvas, the diff window, the fork's own CLI and release pipeline — wholesale
merges stopped being viable, and a transitional cherry-pick round (PR #119, 2026-04-01)
showed that selective adoption works but needs bookkeeping.

The bookkeeping that existed was a per-commit tracking table in the fork change log
(preserved as the "Old Log" section of [upstream-ledger.md](upstream-ledger.md)): one
row per fork commit with a `Fork only` / `Merged upstream` status. That format answers
"what did the fork change" but not "which upstream commits have we reviewed, what did we
decide about them, and where do we resume next time" — every upstream check had to
re-derive its starting point.

## Goals

- **Bounded review scope**: a recorded *upstream baseline* commit; each review round
  only inspects `baseline..upstream/main`, then advances the baseline.
- **Durable decisions**: skip/defer verdicts are written down with rationale so future
  rounds do not re-litigate them (e.g. "no zmx in this fork" holds across rounds).
- **Provenance**: ported changes map upstream commit/PR → fork PR in a table, so later
  archaeology (like this backfill) can trace any fork behavior to its upstream origin.
- **Cheap reconnaissance**: a read-only skill an agent can run any time to get a
  categorized briefing of what is new upstream, without touching the tree.
- **Normal review flow for ports**: upstream changes enter the fork as dedicated fork
  PRs (re-implementations adapted to Prowl's architecture where needed), not as opaque
  merge commits.

**Non-goals**

- Resuming wholesale `upstream/main` merges (the mechanical sync script from
  [001](../001-fork-bootstrap-and-release-pipeline/000-plan.md) remains for that model,
  but the fork moved off it).
- Maintaining the old per-commit status table; it is frozen as the ledger's "Old Log".

## Design / Approach

Three pieces, established together in PR #193 (2026-04-08):

1. **The ledger** — the fork change log converted from a per-commit table to a dated
   review log, newest first. It opens with an **Upstream Baseline** table (commit, tag,
   date) meaning "everything up to and including this commit has been reviewed". Each
   dated entry records one review round with a consistent decision taxonomy that
   stabilized over the rounds: *Ported into the fork* (upstream ref → fork PR mapping),
   *Already present in the fork*, *Reviewed and skipped (decision recorded)*, and
   *Deferred with tracking*. The ledger lives on as
   [upstream-ledger.md](upstream-ledger.md) in this folder.
2. **The `/check-upstream-changes` skill**
   (`.claude/skills/check-upstream-changes/SKILL.md`) — read-only reconnaissance: read
   the baseline from the ledger, `git fetch upstream main`, list
   `baseline..upstream/main`, summarize each commit with its PR number, and categorize
   into **Needs Attention** (possible conflict with fork customizations) vs **Safe to
   Merge**. It explicitly must not modify files or run a sync.
3. **The review-round workflow** — run the skill, investigate the new commits, decide
   port/already-present/skip/defer per commit or per track, land ports as fork PRs,
   then append a dated ledger entry and advance the baseline.

## Alternatives & decisions

- **Per-commit table vs dated log** (#193): the table was retired because it tracked
  fork commits, not upstream review state; the dated log tracks decisions and a resume
  point. The old table is preserved read-only ("Old Log") because the skill still uses
  it as context for spotting overlap with fork customizations.
- **Wholesale merge vs selective port**: after 2026-03-24 no upstream merge commits
  exist; ledger entries state ports are "dedicated fork PRs (fork implementations may
  differ to fit Prowl's architecture)". Track-level skips (Tuist, zmx, upstream hooks,
  upstream CLI) would be impossible under wholesale merging.
- **Skips are decisions, not omissions**: starting with the 2026-04-20 round, each skip
  records why (e.g. Tuist migration skipped because the fork's SwiftPM `ProwlCLI` layout
  sidesteps the archive bug that motivated it upstream).
- **Plan-doc-first for large batches** (2026-07 round): per-commit verdicts are written
  into a standalone batch plan before any port PR is opened, and long-tail items are
  deferred into Linear issues — see [002-plan-doc-batch-workflow.md](002-plan-doc-batch-workflow.md).

## Amendments

- Updated 2026-07-09: the post-v0.10.5 round introduced the plan-doc-first batch
  workflow with Linear-tracked deferrals — see
  [002-plan-doc-batch-workflow.md](002-plan-doc-batch-workflow.md)
