# 083 — Fold Inactive Worktrees: Plan

|                 |                                                                                                                                                                                                                                                                                                                            |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Status**      | Implemented                                                                                                                                                                                                                                                                                                                |
| **Anchor date** | 2026-10-18                                                                                                                                                                                                                                                                                                                 |
| **Primary PRs** | (fill in as they merge)                                                                                                                                                                                                                                                                                                    |
| **Related**     | [018-archived-worktrees](../018-archived-worktrees/000-plan.md), [050-sidebar-expand-active-and-worktree-tab-badges](../050-sidebar-expand-active-and-worktree-tab-badges/000-plan.md), [084-active-agents-sidebar-order](../084-active-agents-sidebar-order/000-plan.md), `docs/components/repositories-and-worktrees.md` |

## Background

Prowl lists every git worktree of every repository it knows. A repository that other
tools also drive accumulates worktrees nobody works on in Prowl: an orchestrator running
agents in another terminal creates a dozen `executor-NNN` worktrees, and each one gets a
sidebar row, a place in ⌘⌃↑/↓, and possibly a ⌃1–9 number. The worktrees the user works
on in Prowl end up scattered among them.

The only per-worktree hide today is archiving, which closes the worktree's terminals,
stops watching it, and makes it unselectable. That is right for finished work and wrong
for a worktree that is merely idle in Prowl.

## Goals

- A worktree with no open terminal tab in Prowl is **inactive**. With the setting on, each
  repository folds its inactive worktrees into one collapsed row, "Inactive (N)", at the
  bottom of its section. One click expands it.
- Folded rows drop out of ⌘⌃↑/↓ and ⌃1–9, the same way rows of a collapsed repository do.
- Opening a folded worktree works as it does today and makes it active.

### Non-goals

- Agent detection plays no part. A worktree with an open tab stays active whether or not
  an agent runs in it, so rows do not move when an agent starts, exits, or reads `unknown`.
- No path or branch patterns, and no manual hide. Both remain possible later on top of
  the same section.
- No change to `prowl list`, notifications, the command palette, Canvas, or the Shelf.

## Design / Approach

**Active set.** `RepositoriesFeature.State.openedWorktreeIDs`, the Shelf's book set, is
the source. A tab creation adds its worktree (`tabCreatedEffect` in
`App/Sources/Features/App/Reducer/AppFeature+TerminalEvents.swift`, layout restore
included), closing the last tab removes it, and selection adds it. The sidebar and the
Shelf therefore agree on which worktrees are open.

**Always active.** The main worktree, pinned worktrees, pending (being created) worktrees,
and the selected worktree never fold.

**Sections.** `WorktreeRowSections` in
`App/Sources/Features/Repositories/Reducer/RepositoriesFeature+StateQueries.swift` gains
`inactive: [WorktreeRowModel]`. `worktreeRowSections(in:)` splits the unpinned worktrees
into `unpinned` and `inactive`, each keeping the existing unpinned order, only when the
setting is on. `allRows` keeps returning every row, because the command palette, the
Worktree menu, and CLI-facing callers use it. A new `navigableRows` returns `allRows`
minus `inactive` unless that repository's inactive group is expanded.

**Navigation.** `worktreeID(byOffset:)` and the hotkey rows that `SidebarView` publishes as
`visibleHotkeyWorktreeRows` read `navigableRows`. `WorktreeCommands` assigns ⌃1–9 from
that list. The command palette keeps reading `orderedWorktreeRows()` over `allRows`, so
it still finds every worktree.

**Fold state.** `@Shared(.appStorage("sidebarExpandedInactiveRepositoryIDs"))` holds the
repositories whose inactive group is expanded, next to `collapsedRepositoryIDs`. Default:
folded. Reload pruning drops IDs of repositories that no longer exist.

**View.** `WorktreeRowsView` renders the inactive group after `unpinned` as a disclosure
row with the count, then the rows when expanded. Folded rows keep their context menus,
archive and delete actions, and badges.

**Drag.** Dragging stays within a group. A move inside `unpinned` or `inactive` maps its
offsets back to positions in the repository's full unpinned order before
`unpinnedWorktreesMoved` writes `worktreeOrderByRepository`, so the stored order stays
one list.

**Setting.** `GlobalSettings` gains `foldInactiveWorktrees: Bool`, default `false`, so
upstream behaviour is unchanged until a user turns it on. `AppFeature` pushes it into
`RepositoriesFeature` on `settingsChanged`, as it does `moveNotifiedWorktreeToTop`. The
Settings UI gets a toggle beside that one.

**Docs.** `docs/components/repositories-and-worktrees.md` (the folded group),
`docs/reference/keyboard-shortcuts.md` (folded rows are skipped),
`docs/reference/settings-fields.md` and `docs/components/settings.md` (the setting).

**Tests.** Reducer and state-query tests for: the section split with the setting off and
on; each always-active exception; a worktree moving between groups on its first tab and
its last tab closing; ⌘⌃↑/↓ and ⌃1–9 skipping folded rows and including them when
expanded; palette rows unchanged; a drag inside each group producing the expected
`worktreeOrderByRepository`; fold-state pruning.

## Alternatives & decisions

- **Hide instead of fold.** Hiding would make the palette the only way to reach an
  inactive worktree. Clicking a sidebar row is how work starts today, so folding keeps it
  one click away. Chosen: fold.
- **Agent detection as the criterion.** Detection drops an entry whenever the state reads
  `unknown` or the agent exits, so rows would jump and ⌃1–9 would renumber. Open tabs
  change only on user or CLI action. Chosen: open tabs.
- **A separate sidebar group for worktrees running an agent.** Rejected for the same
  reason; the Active Agents panel already shows which worktrees run agents.
- **Reuse archiving.** Archiving closes terminals and blocks selection. Rejected.
- **Default on.** Off keeps upstream's sidebar unchanged for existing users.

## Open questions

- `WorktreeTerminalTabsView` calls `ensureInitialTab` when it mounts. Whether closing the
  last tab of the selected worktree leaves it tabless or opens a new tab decides whether
  the selected-worktree exception is ever needed; confirm while implementing.

## Amendments
