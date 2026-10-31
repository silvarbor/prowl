# 071 — Git Environment Recovery: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-09-20 |
| **Related** | #823, [010 plain folders](../010-plain-folder-support/000-plan.md), [023 Shelf](../023-shelf-mode/000-plan.md) |

## Background

A GUI reproduction on macOS 27 confirmed that an unavailable Apple Git toolchain
causes `wt root` to append `not a git repository`. Prowl saves the repository as a
plain folder. Its worktree rows disappear and Shelf cannot open when no Git rows
remain. Restoring the toolchain and manually refreshing recovers both symptoms.
This establishes the failure mechanism, not the reporter's original environment.

## Goals

- Resolve a working Git executable across app-owned Git operations.
- Do not persist a repository type change when Git or repository access fails.
- Explain unavailable Git and repository read errors; offer retry and error details.
- Allow Shelf to open plain folders without requiring a Git worktree.

## Non-goals

No bundled Git, new Git path preference, system toolchain changes, or retention of
stale worktree lists after failed loads. Keep the existing failed-repository row.
Do not change Git chosen by user commands in terminal panes or workflow scripts.

## Approach

1. Use one executable resolver. Try the process PATH, login shell PATH, and common
   installation locations. Validate candidates with `git --version`, reuse successful
   resolution, merge concurrent discovery, and revalidate on repository discovery.
   Preserve the selected executable and its PATH for `wt` and other child processes.
   Do not replay failed mutation commands against another executable.
2. Give repository discovery a typed non-repository result. Classify only direct Git
   discovery output, with checks for inaccessible or existing Git metadata. Never
   classify `wt`'s error wrapper by substring. Keep genuine plain-folder support.
3. Preserve persisted kind on unknown failures. Reuse the existing failure row,
   add a clear status and Retry, and show recovery guidance plus copyable details.
   Terminal cleanup preserves sessions owned by failed roots; this uses existing
   terminal ownership rather than retaining stale repository models.
4. Use one Shelf availability predicate for Git rows and plain folders. Include an
   unopened folder in the initial selection fallback.
5. Migrate app-owned hardcoded Git callers: clone, external diff snapshots, native
   workflow actions, and branch observation. Keep binary output and workflow process
   cancellation semantics intact.

## Validation

Test error classification, executable fallback and recovery, failed load persistence,
plain-only Shelf entry, error presentation and retry. Run the affected suites,
`make check`, and `make build-app`. Repeat isolated GUI acceptance with a disposable
repository and worktree, controlled PATH and developer directory. Verify both the
no-working-Git error state and independent-Git fallback; restore and retry in the
same process. Record automatic recovery separately from explicit Retry.

## Alternatives and decisions

Retaining stale repository models requires separate navigation and terminal lifetime
policy. It is excluded. Clearing DEVELOPER_DIR hides user configuration and does not
repair an invalid system default, so it is excluded. Bundling Git is a separate
packaging and maintenance decision.

## Amendments

PR #824 review follow-up:

- Accept Git's filesystem-boundary non-repository diagnostic in addition to its
  root-directory diagnostic. Keep the exit-code and metadata checks. Do not accept
  extra error output or a `wt` wrapper as proof.
- Bound each executable and login-shell probe with the existing process-group
  executor. Stop probe descendants on timeout or cancellation; do not add a second
  process runner or change mutation execution.
- Track shared-discovery waiters separately. Cancellation releases that waiter
  immediately. Other waiters keep the probe alive; the last cancellation stops it.
  Ignore late completion from a cancelled discovery so Retry can start a new one.
- Cover boundary diagnostics, timeout fallback, cancellation isolation, and retry.
  Use controlled clocks or explicit gates for concurrency tests and real process
  fixtures for process-group termination.
- Removing a failed root must reconcile terminal ownership even when the loaded
  repository list is unchanged. Reuse the existing repositories-changed delegate
  immediately after removal instead of waiting for another Git reload. Exercise
  the full failure/removal reducer flow with a real terminal manager, including
  the last root and removal alongside healthy and still-failed roots.

Issue #920 follow-up (2026-10-21):

- The first version gave every Git child process the PATH where Git was found. For an
  app started from the Dock, that is the launchd PATH (`/usr/bin:/bin:/usr/sbin:/sbin`).
  Hooks, `git-lfs`, credential helpers, and `ssh` lost the login shell PATH that
  worktree creation had before this entry (see a79045d00, #21). A `post-checkout`
  hook that calls a Homebrew tool failed with exit 127.
- Select Git from the login shell PATH first, then the process PATH, then common
  locations. All app-owned Git and `wt` processes get the login PATH. Put the selected
  Git's folder first only when an earlier Git on that PATH does not work, or an empty
  or relative entry comes before it (`wt` runs bare `git`, which such an entry can
  resolve to a `git` in the repository). A prepended folder such as `/usr/bin` also
  shadows the user's `python3`, `ruby`, and other tools.
  Without a login PATH, use the process PATH. Read only the last stdout line of the
  login probe, because startup files can print (see 24027a919).
- Callers that start `Process` directly use one shared environment
  (`GitExecutable.processEnvironment`). The workflow context action now also inherits
  the app environment, so Git can read `HOME` and the user's configuration.
- Git error messages keep only the final state of carriage-return progress lines and
  the last 20 lines of each stream, so that the hook's error is visible.
- `reloadRepositories` no longer clears the repositories alert. App activation, the
  worktree registry monitor, the 30-second timer, and the failure cleanup itself all
  reload, so a failure alert closed within a second, before the user could read it.
  Alert actions that start a reload clear the alert themselves.
- Failed creation cleanup keeps its policy (remove the folder, keep the branch). It
  now targets the actual destination, including a custom name or parent folder. It
  removes the worktree only if that folder did not exist before the attempt and Git
  registers it on the attempted branch: another creation can claim the same folder
  between the check and `wt sw`.
