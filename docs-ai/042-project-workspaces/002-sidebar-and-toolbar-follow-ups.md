# 042 — Amendment: Sidebar and Toolbar Follow-up Fixes (2026-06-20)

## Context

Two days of dogfooding after the workspace merge surfaced small UI defects in how
workspaces (and plain folders) integrate with existing chrome.

## Change

- **Toolbar title width (#481).** Folder and workspace names in the toolbar navigation
  area rendered narrower than branch names: branch titles were wrapped in a `Button`
  (for rename) and got toolbar button padding, while folder/workspace titles were bare
  labels. Fix: wrap folder/workspace titles in a no-op `Button` so all title kinds get
  the same toolbar styling (`supacode/Features/Repositories/Views/WorktreeDetailTitleView.swift`).
- **Workspace child row click area (#485).** Only the label text of a workspace child row
  was clickable. The row's `Button(.plain)` was replaced with `onTapGesture` +
  `contentShape(.interaction, .rect)` to match the worktree-row pattern
  (`supacode/Features/Repositories/Views/WorkspaceChildRowsView.swift`).
- **Collapse/expand all (#485).** The sidebar header's Collapse all / Expand all toggle
  ignored workspaces because `expandableRepositoryIDs` filtered on `supportsWorktrees`
  only; the filter now also accepts `isWorkspace`
  (`supacode/Features/Repositories/Views/SidebarListView.swift`).

## Refs

- PR #481 (merged 2026-06-20, `d10572e3`)
- PR #485 (merged 2026-06-20, `0a49b5e5`)

## Current state

The workspace child-row and collapse/expand fixes remain in the working tree:
`WorkspaceChildRowsView.swift` uses `contentShape(.interaction, .rect)` +
`onTapGesture`, and `SidebarListView.expandableRepositoryIDs` filters on
`$0.capabilities.supportsWorktrees || $0.isWorkspace`. The toolbar title and its no-op
`Button` wrapper were removed on 2026-08-07 by
[058](../058-unified-toolbar-layout/000-plan.md), superseding that presentation-only fix.

Note: #485 trades the project guideline "prefer `Button` over `onTapGesture`" for
consistency with the existing worktree-row implementation; if worktree rows ever move
back to `Button`, workspace child rows should follow.
