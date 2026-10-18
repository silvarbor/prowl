# 083 — Fold Inactive Worktrees: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-18 | Fold worktrees with no open tab into a per-repository "Inactive (N)" group behind `foldInactiveWorktrees` | fork review PR (see below) |

## Outcome & current state (as of 2026-10-18)

- `GlobalSettings.foldInactiveWorktrees` (default `false`) reaches
  `RepositoriesFeature.State.foldInactiveWorktrees` through
  `worktreeOrdering(.setFoldInactiveWorktrees)`, sent from `AppFeature` on
  `settingsChanged` next to `setMoveNotifiedWorktreeToTop`. The toggle sits beside
  "Move notified worktree to top" in the Notifications settings.
- `worktreeRowSections(in:)` splits the unpinned worktrees into `unpinned` and
  `inactive` when the setting is on. A worktree is inactive when it is not in
  `openedWorktreeIDs`, is not the selected worktree, and is not in the sidebar
  multi-selection (`isWorktreeFolded`). Main, pinned, and pending worktrees are
  never in the unpinned list, so they never fold.
- `WorktreeRowSections.allRows` still returns every row (inactive last), so the
  command palette, the Worktree menu, and CLI-facing callers see every worktree.
  `navigableRows(isInactiveExpanded:)` and `navigableWorktreeRows(includingRepositoryIDs:)`
  drop a folded group. `worktreeID(byOffset:)`, `SidebarView`'s and
  `SidebarListView`'s hotkey rows, and `WorktreeCommands`' fallback read them, so
  ⌘⌃↑/↓ and ⌃1–9 skip folded rows.
- `sidebarExpandedInactiveRepositoryIDs` (app storage) holds the repositories whose
  group is expanded. `toggleInactiveWorktreesExpanded` flips it, and
  `repositoriesLoaded` prunes IDs of repositories that no longer exist.
- `WorktreeRowsView` renders the group after the unpinned rows as a disclosure
  button, "Inactive (N)", followed by the rows when expanded. A move inside either
  group goes through `fullUnpinnedOrderMove`, which maps the group offsets back to
  the repository's full unpinned order before `unpinnedWorktreesMoved` writes
  `worktreeOrderByRepository`. The stored order stays one list.
- Docs: `docs/components/repositories-and-worktrees.md`,
  `docs/reference/keyboard-shortcuts.md`, `docs/reference/settings-fields.md`,
  `docs/components/settings.md`, `docs/components/notifications.md`.

## Verification

- `FoldInactiveWorktreesTests` (21 tests): the section split with the setting off
  and on, each always-active exception, a worktree moving between groups on its
  first tab and its last tab closing, ⌘⌃↑/↓ and offset navigation skipping folded
  rows and including them when expanded, palette rows unchanged, drag mapping in
  each group, the fold-state toggle and its pruning, and the setting's
  decode default and round trip. `AppFeatureSettingsChangedTests` receives the
  new action.
- `make check`, `make lint`, `make check-localization`, and `make test` passed
  before the push; the PR records the counts.

## Deviations from plan

- The sidebar multi-selection also keeps rows out of the group, not only the
  selected worktree. Command-clicking a row in the expanded group would otherwise
  fold the row away under the cursor.
- The plan placed the toggle's action beside `setMoveNotifiedWorktreeToTop`; the
  expand/fold action is a top-level `RepositoriesFeature` action next to
  `revealSelectedWorktreeInSidebar`, because it is sidebar state rather than
  ordering.

## Open questions

Resolved: the selected-worktree exception is needed. `ensureInitialTab` runs when
`WorktreeTerminalTabsView` appears and from a few explicit commands, and
`WorktreeTerminalState.closeTab` creates no replacement tab. Closing the last tab of
the selected worktree leaves it tabless while `tabClosedEffect` removes it from
`openedWorktreeIDs`, so without the exception the selected row would fold away.
