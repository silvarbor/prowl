# 084 — Active Agents in Sidebar Order: Plan

|                 |                                                                                                                                                                                                                                       |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Status**      | Implemented                                                                                                                                                                                                                               |
| **Anchor date** | 2026-10-18                                                                                                                                                                                                                            |
| **Primary PRs** | (fill in as they merge)                                                                                                                                                                                                               |
| **Related**     | [029-active-agents-panel](../029-active-agents-panel/000-plan.md), [066-agent-island](../066-agent-island/000-plan.md), [083-fold-inactive-worktrees](../083-fold-inactive-worktrees/000-plan.md), `docs/components/active-agents.md` |

## Background

The Active Agents panel lists agents in the order Prowl first published them.
`ActiveAgentsFeature` upserts each entry into `entries`, an `IdentifiedArray`, so a new
agent lands at the end. When an agent's state reads `unknown` or the agent exits and
starts again, `WorktreeTerminalState` removes its entry and the next publish appends it
at the end again. The order therefore reflects arrival history and drifts during a
session; users cannot predict where an agent will be.

Users already arrange worktrees in the sidebar: repository order, worktree order, and
pins, all persisted.

## Goals

- The panel shows agents in an order derived from the sidebar, with no controls and no
  state of its own.
- Agents in pinned worktrees come first, across all repositories, in sidebar order.
- All other agents follow in sidebar order: repositories in `repositoryOrderIDs` order,
  and within each repository the main worktree, then the unpinned worktrees in
  `worktreeOrderByRepository` order.
- Agents in one worktree sort by tab position, then pane index.
- ⌥⌃↑/↓ and the Agent Island roster follow the same order.

### Non-goals

- No pinning, dragging, or reordering in the panel. Rearranging the sidebar rearranges
  the panel.
- The island's attention view keeps its own priority (blocked, then done).

## Design / Approach

**Pin scope.** A pin is one stored fact per worktree (`pinnedWorktreeIDs` in
`settings.json`). The sidebar groups by repository, so a pin lifts a row within its
repository. The panel has no repository groups, so a pin lifts the agent to the top of
the whole panel.

**Rank.** `RepositoriesFeature` computes `[Worktree.ID: Int]`: pinned worktrees across
repositories first, in repository order and then pin order, followed by every other
worktree in `orderedWorktreeRows()` order. It sends the map to `ActiveAgentsFeature`
through a new `worktreeRanksChanged` action whenever the map changes, using the reducer
`onChange(of:)` on the inputs (`orderedRepositoryIDs()`, `pinnedWorktreeIDs`,
`worktreeOrderByRepository`, and the repositories' worktree IDs). Agent state changes do
not touch these inputs, so they never re-rank.

**Sorted entries.** `ActiveAgentsFeature.State` stores the rank map and keeps `entries`
sorted by `(rank, tabIndex, paneIndex)`. `agentEntryChanged` re-sorts after an upsert,
and `worktreeRanksChanged` re-sorts the whole list. An entry whose worktree has no rank
sorts last. Because `entries` itself is ordered, every reader — `ActiveAgentsPanel`, the
overlay row displays in `SidebarListView`, `navigate` for ⌥⌃↑/↓, and
`AgentIslandNavigation` — gets the order without change.

**Tab index.** `ActiveAgentEntry` gains `tabIndex`, the tab's position in
`tabManager.tabs`, filled in `activeAgentEntry(surfaceID:tabId:state:)` in
`App/Sources/Features/Terminal/Models/WorktreeTerminalState+AgentDetection.swift`
next to `paneIndex`.

**Cost.** Sorting a few dozen entries per upsert is negligible. Upserts already write
`entries`, so observation fires no more often than today.

**Interaction with notifications.** `moveNotifiedWorktreeToTop` (default on) moves a
notified worktree to the top of its repository's unpinned rows, so its agent moves up in
the panel too. Pinned worktrees do not move.

**Docs.** `docs/components/active-agents.md` and `docs/components/agent-island.md`
describe the order; `docs/reference/keyboard-shortcuts.md` says ⌥⌃↑/↓ walks it.

**Tests.** Rank computation across repositories (pins first in repository then pin
order, main before unpinned, repository order respected); entries sorted on upsert and on
a rank change; an entry removed and re-added returning to its rank position, not the end;
two agents in one worktree ordered by tab then pane; ⌥⌃↑/↓ following the sorted order;
an unranked entry sorting last.

## Alternatives & decisions

- **Panel-owned pins and order** (`activeAgentsOrder` in app storage, drag and pin in
  the panel). It would allow an order independent of the sidebar, at the cost of a
  second ordering system, its persistence, pruning, and UI. Rejected: the sidebar
  already holds the user's arrangement.
- **Follow the sidebar block by block**, pins lifting only within each repository.
  Rejected: users expect pinned agents at the top of the panel.
- **Sort in the view.** Each reader (panel, navigation, island) would need the same sort.
  Keeping `entries` sorted gives them one order by construction.
- **Order by surface identity.** Surface UUIDs are new at every launch, so nothing keyed
  on them survives a restart. Worktree IDs (paths) do.

**Readers by index.** `navigate` in `ActiveAgentsFeature`, `AgentIslandNavigation`, and
`AgentIslandRosterContent` index into `entries`, and each tracks its selection by entry
ID, so a re-sort keeps the selected agent selected. `worktreeRanksChanged` calls
`islandNavigation.reconcile(entries:)` when the roster is expanded, as
`agentEntryChanged` already does.

## Open questions

- Whether reordering tabs republishes the agent entries of the moved tabs. If it does
  not, `tabIndex` goes stale until the next state change; the tab-move path then needs
  to republish.

## Amendments
