# 042 — Project Workspaces: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-06-11 → 06-18 | Feature built on `codex/workspace-mode` by MikotoZero (22 commits): `ProjectWorkspace` domain model + `.prowl/workspace.json`, creation flow with checkout modes and rollback, sidebar/detail UI with read-only child rows, removal flow with cleanup guards, `prowl list` workspace kind, `docs/components/workspaces.md`, ~2k lines of tests | PR #455 |
| 2026-06-18 | Review pass on `fix/workspace-mode-review` (onevcat, 5 fix commits + child-row icon tweaks): removal auto-selection, `*/HEAD` local-branch filter fix, `hasMetadata` instead of full JSON decode in the persistence normalizer, `async let` parallel git lookups in base-ref fetch, root-path logic deduplicated into `ProjectWorkspace`. Merged to `main` carrying #455's commits (`161237fb`); GitHub marked both PRs merged at the same instant | PR #472 |
| 2026-06-20 | Toolbar title too narrow for folder/workspace names | PR #481 → [002](002-sidebar-and-toolbar-follow-ups.md) |
| 2026-06-20 | Workspace sidebar full-row click area + collapse/expand all | PR #485 → [002](002-sidebar-and-toolbar-follow-ups.md) |

## Outcome & current state (as of 2026-07-12)

- `supacode/Domain/ProjectWorkspace.swift` (~1,000 lines) — schema
  `prowl.workspace.v1`, `metadataURL`/`hasMetadata`/`load`/`normalized(relativeTo:)`,
  `create(...)` with `MaterializationLedger` rollback, `removeWorktrees` /
  `removeWorkspaceFolder`, `workspaceRootPath` / `uniqueWorkspaceRootPath` (defaults
  under `~/.prowl/workspaces`, `SupacodePaths.workspacesDirectory` in
  `supacode/Support/SupacodePaths.swift`).
- `supacode/Domain/Repository.swift` — `workspace: ProjectWorkspace?`, `isWorkspace`;
  the initializer forces `kind = .plain` when a workspace payload is present.
- Reducers — `supacode/Features/Repositories/Reducer/WorkspaceCreationPromptFeature.swift`
  (creation prompt state machine), `RepositoriesFeature+WorkspaceCreation.swift`
  (execution + rollback), `RepositoriesFeature+WorkspaceChildren.swift`
  (`ResolvedWorkspaceChild`, branch/diff/PR refresh on the `repositoriesLoaded` cadence,
  explicitly kept out of the worktree info watcher), removal handling in
  `RepositoriesFeature+RepositoryManagement.swift`.
- Views — `supacode/Features/Repositories/Views/WorkspaceCreationPromptView.swift`
  (Add Opened / Add Remote / Add Local menu; bare-repository rows render but are not
  offered as a source), `WorkspaceDetailView.swift`, `WorkspaceChildRowsView.swift`,
  `WorkspaceRepositoriesGridView.swift`, `RemoveWorkspaceConfirmationView.swift`;
  `SidebarListView.swift` carries the surviving 002 fix; the toolbar-title portion was
  superseded by [058](../058-unified-toolbar-layout/000-plan.md).
- Entry points — "New Workspace" lives in the Worktrees menu
  (`supacode/Commands/WorktreeCommands.swift`) and the command palette
  (`CommandPaletteFeature` / `CommandPaletteItem.newWorkspace`). The standalone sidebar
  toolbar button that #455 deliberately kept **no longer exists**: since #520 (entry 019)
  the sidebar toolbar has a single "Add..." button opening the `AddToProwlView` popover,
  which contains "Add Workspace".
- Settings — `supacode/Features/Settings/Views/RepositorySettingsView.swift` shows the
  workspace metadata read-only (description, task links, repository grid).
- Persistence — `supacode/Features/Settings/BusinessLogic/RepositoryPersistenceKeys.swift`
  uses `ProjectWorkspace.hasMetadata` (file-exists check) when normalizing entries.
- CLI — `supacode/CLIService/Shared/ListCommandPayload.swift` (`case workspace`) and
  `supacode/CLIService/ListRuntimeSnapshotBuilder.swift`; documented in
  `docs/components/cli.md` (`kind` is `git`|`plain`|`workspace`).
- Tests — `supacodeTests/ProjectWorkspaceTests.swift` (~950 lines of domain tests),
  `RepositoriesFeatureTests.swift` (incl. `removeSelectedWorkspaceSelectsNextRepository`),
  `GitClientBranchRefsTests.swift` (incl. `branchRefOptionsPreservesLocalBranchNamedHEAD`),
  toolbar-title tests (later removed with the title UI in
  [058](../058-unified-toolbar-layout/000-plan.md)).
- User-facing behavior is documented in `docs/components/workspaces.md` (added in the
  same merge).

## Deviations from plan

- The standalone "New Workspace" toolbar button — argued for explicitly in #455's
  description — was superseded on 2026-06-30 by the consolidated Add-to-Prowl popover
  (#520, entry 019). The direction matches #455's own analysis (reduce reliance on
  `NavigationSplitView` sidebar toolbar items), so this is evolution rather than
  reversal; the menu and palette entry points survive as planned.

## Open questions

- None beyond the note recorded in
  [002-sidebar-and-toolbar-follow-ups.md](002-sidebar-and-toolbar-follow-ups.md) about
  `onTapGesture` vs the project's Button-preference guideline.
