# 085 — Fold Inactive Worktrees: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-18 | First version: fold worktrees with no open tab into a per-repository "Inactive (N)" group behind a `foldInactiveWorktrees` setting | fork review PR |
| 2026-10-27 | Reworked per the maintainer's request on #939: always on, no setting, no Sidebar settings section; renumbered to 085 after 083 and 084 were taken | PR (see Primary PRs) |

## Outcome & current state (as of 2026-10-27)

- `worktreeRowSections(in:)` splits the unpinned worktrees into `unpinned` and
  `inactive`. A worktree is inactive when it is not in `openedWorktreeIDs`, is not the
  selected worktree, and is not in the sidebar multi-selection (`isWorktreeFolded`).
  Main, pinned, and pending worktrees are never in the unpinned list, so they never
  fold. There is no setting: `GlobalSettings`, `SettingsFeature`, and `AppFeature` carry
  nothing for it.
- Plain folders, workspaces, and remote folders have an empty `repository.worktrees`
  and produce no rows, so they cannot fold and shift no other repository's rows. A
  remote git repository lists its root worktree, which is main.
- `WorktreeRowSections.allRows` still returns every row (inactive last), so the
  command palette, the Worktree menu, and CLI-facing callers see every worktree.
  `navigableRows(isInactiveExpanded:)` and `navigableWorktreeRows(includingRepositoryIDs:)`
  drop a folded group. `worktreeID(byOffset:)`, `SidebarView`'s and
  `SidebarListView`'s hotkey rows, and `WorktreeCommands`' fallback read them, so
  ⌘⌃↑/↓ and ⌃1–9 skip folded rows.
- `sidebarExpandedInactiveRepositoryIDs` (app storage) holds the repositories whose
  group is expanded. `toggleInactiveWorktreesExpanded` flips it, and
  `repositoriesLoaded` prunes IDs of repositories that no longer exist, keeping those
  of a repository whose load failed.
- `WorktreeRowsView` renders the group after the unpinned rows as a disclosure
  button, "Inactive (N)", in `.body` like the worktree names, followed by the rows when
  expanded. A move inside either group goes through `fullUnpinnedOrderMove`, which maps
  the group offsets back to the repository's full unpinned order before
  `unpinnedWorktreesMoved` writes `worktreeOrderByRepository`. The stored order stays
  one list.
- Docs: `docs/components/repositories-and-worktrees.md` and
  `docs/reference/keyboard-shortcuts.md`.

## Verification

- `FoldInactiveWorktreesTests`: the section split with no setting involved, each
  always-active exception, plain and remote folders producing no rows, a worktree
  moving between groups on its first tab and its last tab closing, ⌘⌃↑/↓ and offset
  navigation skipping folded rows and including them when expanded, palette rows
  unchanged, drag mapping in each group, and the fold-state toggle and its pruning
  (including a failed load).
- `make check`, `make lint`, `make check-localization`, `make test-scripts`, and
  `make test` passed before the push; the PR records the counts.

## Deviations from plan

- The sidebar multi-selection also keeps rows out of the group, not only the
  selected worktree. Command-clicking a row in the expanded group would otherwise
  fold the row away under the cursor.
- The expand/fold action is a top-level `RepositoriesFeature` action next to
  `revealSelectedWorktreeInSidebar`, because it is sidebar state rather than ordering.
- The first version put the feature behind a setting. The maintainer asked for it to
  replace the current behavior instead (see the plan's alternatives), so the setting,
  its settings section, and its decode default are gone.

## Open questions

Resolved: the selected-worktree exception is needed. `ensureInitialTab` runs when
`WorktreeTerminalTabsView` appears and from a few explicit commands, and
`WorktreeTerminalState.closeTab` creates no replacement tab. Closing the last tab of
the selected worktree leaves it tabless while `tabClosedEffect` removes it from
`openedWorktreeIDs`, so without the exception the selected row would fold away.

Open: a bare repository has no main worktree by the current rule (see the plan).
