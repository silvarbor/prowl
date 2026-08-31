# 062 — Workspace Child Per-Repository Diff: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-19 |
| **Primary PRs** | #704 |
| **Related** | [042-project-workspaces](../042-project-workspaces/000-plan.md), `docs/` diff & workspace pages, issue #616 |

## Background

Workspace child repositories show live per-repository status — branch, `+N/-M` line
changes, and PR info — but none of the diff entry points work for them (issue #616).
The child rows pass `onDiffTap: nil` (`supacode/Features/Repositories/Views/WorkspaceChildRowsView.swift`),
and the whole diff pipeline is keyed on `Worktree.ID`: the sidebar badge delegate
(`RepositoriesFeature.Delegate.showDiff(Worktree.ID)`), the ⌘⇧Y menu command and the
Command Palette items are all gated on `selectedWorktreeID`, which is `nil` while a
workspace child is selected (selection stays `.repository(workspaceID)` +
`selectedWorkspaceChildID`). This was a deliberate v1 scope cut — children are metadata
entries, not tracked worktrees (see entry 042) — not a regression, but it blocks the
core review flow for multi-repo tasks.

## Goals

- Clicking a workspace child's `+N/-M` badge opens the diff for that child repository.
- With a child selected, ⌘⇧Y / "Show Diff" and ⌘⇧U / "Show Outgoing Changes" (menu and
  Command Palette) target that child, matching single-repo behavior.
- All configured diff tools behave consistently for children: built-in window, FileMerge,
  Kaleidoscope, custom command, and Hunk.
- Hunk runs in the workspace's own terminal (a new tab with the child directory as cwd),
  so no terminal state exists outside the workspace's lifecycle.
- Built-in diff supports Outgoing Changes for children, using the child's already-fetched
  PR info (`workspaceChildInfoByID`) with the existing base-resolution ladder.

### Non-goals

- Promoting workspace children to first-class `Worktree`s (conflicts with the single-host
  terminal design from entry 042; not needed for diff).
- Path-validity pre-checks: when a child path is gone or not a git repo, git commands fail
  naturally and surface the existing "Unable to open diff" error alert.

## Design / Approach

Introduce a resolved diff request type and a stable reference for routing:

- `DiffTargetID`: `case worktree(Worktree.ID)` | `case workspaceChild(String)` (child id =
  working-directory path, same key as `workspaceChildInfoByID`).
- `DiffTarget`: `id`, `workingDirectory` (git dir to diff), `branchName` (window title +
  `{branch}` template; fallback live branch → metadata branch → repository name),
  `repositoryRootURL` (`{repoPath}` template + `repositorySettings` key), `terminalHost:
  Worktree` (Hunk tab host — the synthesized workspace worktree for children), and
  `terminalWorkingDirectory: URL?` (Hunk cwd override).

Wiring:

- `RepositoriesFeature+StateQueries`: `diffTarget(for: DiffTargetID) -> DiffTarget?` and
  `selectedDiffTargetID` (selected worktree, else selected workspace child).
- `RepositoriesFeature.Delegate.showDiff` / `.showOutgoingChanges` carry `DiffTargetID`.
- `WorkspaceChildRowsView` gains an `onDiffTap` per row, wired in `RepositorySectionView`.
- `SidebarCommands` and the Command Palette item builder gate the two view items on
  `selectedDiffTargetID` instead of `selectedWorktreeID` (navigation/action items keep the
  worktree gate).
- `ExternalDiffToolClient.open` takes a `DiffTarget`; the Hunk case sends
  `.createTabWithInput(target.terminalHost, workingDirectory: target.terminalWorkingDirectory, …)`
  (parameter already exists on `TerminalClient.Command`).
- `ExternalDiffSnapshotClient` takes the working-directory `URL` (its only input today).
- `OutgoingChangesClient` resolves per `DiffTarget`; its `pullRequestInfo` lookup is keyed
  by `DiffTargetID` and wired in `supacodeApp` to `worktreeInfoByID` /
  `workspaceChildInfoByID` respectively. Child `repositorySettings` are keyed by the child
  root, so a child that is also registered standalone honors its configured base ref.
- `WorktreeRow` renders the `+N/-M` badge as non-interactive (no "Show Diff" help) when
  `onDiffTap == nil`, removing the current dead-button affordance.

## Alternatives & decisions

- **Synthesize a fake child `Worktree`** instead of `DiffTarget`: less churn, but the two
  ID-keyed lookups (PR cache, terminal state) would silently miss or orphan; rejected.
- **Badge-only support** (no ⌘⇧Y/palette): smaller, but leaves inconsistent entry points
  that would need a follow-up anyway; rejected with onevcat.
- **Skip Hunk for children**: avoids terminal questions, but silently bypasses the user's
  configured tool; rejected — `createTabWithInput`'s `workingDirectory` parameter makes the
  consistent behavior cheap.
- **Path pre-checks / disabled states for broken children**: rejected in favor of natural
  degradation (no line changes → no badge; explicit invocation → existing error alert).

## Amendments

