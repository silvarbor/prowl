# 084 — Active Agents in Sidebar Order: Action Log

## Timeline

| Date       | Change                                                                                                                            | Ref                                            |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| 2026-10-18 | Plan committed; `ActiveAgentEntry.tabIndex`, ranks pushed from `RepositoriesFeature`, sorted `entries`, tab-order republish, docs | fork review PR (see `Primary PRs` in the plan) |

## Outcome & current state (as of 2026-10-18)

- `ActiveAgentsFeature.State.entries` stays sorted by `(rank of the entry's worktree, tabIndex, paneIndex)`.
  `sortsBefore` is the comparator; `sortEntries()` sorts only when the array is out of order, and
  entries that tie keep their arrival order. A worktree without a rank sorts after every ranked one.
  File: `App/Sources/Features/ActiveAgents/Reducer/ActiveAgentsFeature.swift`.
- `State.worktreeRanks` holds the rank map. The new action `worktreeRanksChanged` replaces it, re-sorts, and
  reconciles the island roster when it is expanded.
- `RepositoriesFeature.State.worktreeRanks()` (in `RepositoriesFeature+StateQueries.swift`) computes the
  map: pinned worktrees of every repository first (repository order, then pin order), then the main worktree
  and the unpinned worktrees of each repository in sidebar order. Pending and archived worktrees get no rank.
- `RepositoriesFeature` sends `worktreeRanksChanged` in two cases, both only when the map differs from the one
  the panel holds:
  - `onChange(of: \.worktreeRankInputs)`, while the panel lists at least one agent. The inputs are the stored
    repositories, repository roots and order, pins, worktree order, and archived worktrees; agent state
    changes touch none of them.
  - After `activeAgents(.agentEntryChanged)`, so the first entry that arrives into an empty panel gets ranks
    that were not tracked while the panel was empty. Tests that change the sidebar with no agents listed see no
    extra action.
- `ActiveAgentEntry.tabIndex` is the tab's position in `tabManager.tabs`, filled in `activeAgentEntry(...)`
  in `WorktreeTerminalState+AgentDetection.swift`. It takes part in `==`, so a changed position is a visible
  change for `emitAgentEntry`.
- Docs: `docs/components/active-agents.md`, `docs/components/agent-island.md`,
  `docs/reference/keyboard-shortcuts.md`.
- Tests: `App/Tests/ActiveAgentsSidebarOrderTests.swift` (rank computation, sorted upsert, rank change,
  remove and re-add, tab then pane, unranked last, navigation, island selection, wiring in
  `RepositoriesFeature`), `AgentEntryEmissionDedupTests` (tab position and republish), and
  `TerminalTabManagerTests` (order callback).

## Deviations from plan

- The plan sent ranks through `onChange(of:)` alone. A rank sync on every sidebar change would add one
  received action to every existing `RepositoriesFeature` test that touches pins or order, and the rank map is
  only needed while agents are listed. The sync therefore runs only with a non-empty panel, and
  `agentEntryChanged` fetches the ranks for the first entry.
- `tabIndex` is declared `var tabIndex = 0`, so entry builders in tests need no new argument.

## Open questions

The plan asked whether reordering tabs republishes the agent entries of the moved tabs. It does not. Nothing
called `emitAgentEntry` when `tabManager.tabs` changed order, length, or content of positions, so `tabIndex`
would have gone stale until the agent's next state change. `TerminalTabManager` now calls `onTabOrderChanged`
from `tabs.didSet` when the sequence of tab IDs changes (reorder, close, insert, undo close), never for a write
to one tab's fields, and `WorktreeTerminalState.refreshAgentEntriesForTabOrderChange()` re-emits the agent
entries of every remaining tab. The emission dedup drops entries whose position did not change.

Not verified in the running app: the panel and island reorder live while a tab is dragged. The unit tests cover
the republish and the sort.
