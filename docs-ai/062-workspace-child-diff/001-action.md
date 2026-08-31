# 062 — Workspace Child Per-Repository Diff: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-19 | Plan aligned with onevcat (⌘⇧Y follows selected child; Outgoing Changes included; Hunk runs in workspace terminal with child cwd; natural degradation, no pre-checks) | tracker relay-tracker#154, issue #616 |
| 2026-08-19 | Implemented `DiffTarget` routing end to end, with tests and `docs/` updates | #704 |
| 2026-08-20 | Review round 1 (pi agent): scoped child targets by workspace, child `repositoryRootURL` follows recorded source root, added child outgoing coverage | #704 |
| 2026-08-20 | Review round 2 (pi agent): child roots live-resolved via `gitClient.repoRoot` (cached per reload) since a recorded source location may be a subdirectory or nested worktree; selection pruning validates against the selected workspace's own children | #704 |
| 2026-08-20 | Review round 3 (pi agent): dropped the root cache — canonicalization moved to the diff effects (`AppFeature.canonicalizedDiffTarget`) at invocation time, eliminating the startup window and cache-staleness class; empty-child reloads cancel the in-flight refresh and stale child updates are filtered | #704 |

## Outcome & current state (as of 2026-08-19)

- `supacode/Domain/DiffTarget.swift` — `DiffTargetID` (`worktree` /
  `workspaceChild(workspaceID:path:)` — children are scoped by workspace because metadata
  does not enforce path uniqueness across workspaces) and `DiffTarget` (git
  `workingDirectory`, `branchName`, `repositoryRootURL`, `terminalHost`,
  `terminalWorkingDirectory`), plus `DiffTarget(worktree:)`.
- `supacode/Features/Repositories/Reducer/RepositoriesFeature+StateQueries.swift` —
  `diffTarget(for:)` (resolves within the named workspace; child branch falls back live →
  metadata → repository name; terminal host is the synthesized workspace worktree via
  `plainFolderWorktree(for:)`), `selectedDiffTargetID` (selected worktree, else selected
  workspace child), and `pullRequest(for:)` (per-target PR cache dispatch, wired from
  `supacodeApp`). A child's sync-resolved `repositoryRootURL` is the metadata source root
  (`ProjectWorkspaceRepositoryEntry.localSourceURL`) falling back to the checkout
  directory; because a recorded source location may be a subdirectory or a nested
  worktree, the diff effects canonicalize it at invocation time —
  `AppFeature.canonicalizedDiffTarget` runs `gitClient.repoRoot(childDirectory)` inside
  `openDiffEffect` / `openOutgoingChangesEffect`, the same normalization that keys
  registered repositories (`RepositoriesFeature+RepositoryLoading`), so
  `repositorySettings` and `{repoPath}` match the source repository by construction with
  no cache to go stale and no startup window. A failed lookup keeps the metadata fallback.
- `pruneWorkspaceChildInfo` validates `selectedWorkspaceChildID` against the selected
  workspace's own children (not the global path set), so a child removed from the selected
  workspace cannot survive as a ghost selection through another workspace sharing the path.
- Reloads that leave no workspace children cancel the in-flight children refresh, and
  `workspaceChildrenInfoLoaded` filters updates to current children, so a late batch
  cannot repopulate just-pruned maps.
- `RepositoriesFeature.Delegate.showDiff` / `.showOutgoingChanges` carry `DiffTargetID`;
  `WorkspaceChildRowsView` + `RepositorySectionView` wire the child badge and new
  **Show Diff** / **Show Outgoing Changes** context-menu items.
- `AppFeature` / `AppFeature+CommandPalette` resolve targets through `diffTarget(for:)`;
  `SidebarCommands` and the palette item builder gate the two diff view items on
  `selectedDiffTargetID` (navigation/action items keep the worktree gate).
- `ExternalDiffToolClient` and `OutgoingChangesClient` take `DiffTarget`;
  `ExternalDiffSnapshotClient` takes the working-directory `URL`. Hunk sends
  `.createTabWithInput(terminalHost, workingDirectory: terminalWorkingDirectory, …)` and
  names the tab `Hunk Diff · <folder>` when a cwd override is present. The
  `pullRequestInfo` lookup in `supacodeApp.swift` dispatches on `DiffTargetID`
  (`worktreeInfoByID` / `workspaceChildInfoByID`).
- `WorktreeRow` renders the `+N/-M` badge as plain text (no button, no "Show Diff" help)
  when `onDiffTap` is nil.
- Docs: `docs/components/workspaces.md` and `docs/components/diff-view.md` describe the
  child entry points and the workspace-root availability rule.

## Deviations from plan

None known.

## Open questions

None.
