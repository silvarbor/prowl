# 023 — Shelf Mode: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-04-21 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #230, #232, #244, #246, #272, #273, #356, #432, #434 |
| **Sources** | `doc-onevcat/shelf-view.md` (absorbed here; original removed in the docs-ai migration), PR descriptions, [jank-investigation.md](jank-investigation.md) (kept verbatim in this folder) |
| **Related** | [005-canvas-live-sessions](../005-canvas-live-sessions/000-plan.md), [012-keybinding-system](../012-keybinding-system/000-plan.md), [025-repo-identity-appearance](../025-repo-identity-appearance/000-plan.md), [030-agent-status-detection](../030-agent-status-detection/000-plan.md), `docs/components/shelf.md`, `docs/components/view-modes.md` |

## Background

Canvas (entry 005) spreads worktrees out as flat per-tab cards and deliberately weakens
the worktree concept. Shelf is the opposite bet: a terminal presentation mode that
preserves and strengthens it. Each worktree (or plain folder) becomes a "book" with a
one-line-wide vertical spine that doubles as its tab bar. Exactly one book is open at a
time, occupying the space between a left stack of already-passed spines and a right stack
of upcoming ones:

```
[ left spine stack ] [ open book terminal area ] [ right spine stack ]
```

The design was written up front as a full spec (spine geometry, animation, keyboard
shortcuts, notification badges) with an "Implementation Decisions Journal" appended
during the build; both are condensed into this entry.

## Goals

- A terminal-region presentation mode next to Canvas, **mutually exclusive** with Canvas
  and Archived Worktrees; the left navigation stays visible.
- **Book = worktree or plain folder**, 1:1. Book order mirrors sidebar order; reordering
  happens through the sidebar, not on the shelf.
- **Spine = vertical tab bar + identity**: rotated worktree/branch header (branch line
  omitted for plain folders), icon-only tab slots, and — on the open book's spine only —
  pinned bottom controls (`+` / vertical split / horizontal split). Holding ⌘ swaps each
  slot's icon for its `Cmd+1..9` digit with zero layout shift.
- **`selectedWorktreeID` is the single source of truth** for the open book, giving
  bidirectional sync with the sidebar for free. Unlike Canvas, clicking a sidebar
  worktree does **not** exit Shelf — it just turns to that book.
- **Book set = opened worktrees only**: only worktrees with terminal state (interacted
  with this session) get spines; clicking an unopened worktree materializes its spine.
- Snappy spine-flow animation (~200 ms ease-in-out); forward clicks pull spines into the
  left stack, backward clicks push them back to the right stack, with the outgoing
  terminal crossfading so no half-clipped surface is ever visible.
- Notification surfacing at two levels: per-tab slot tint (same token as Canvas title-bar
  highlights) plus an aggregated dot on the spine header for tabs scrolled out of view.
- All shortcuts configurable through the keybinding system (entry 012): `Toggle Shelf`
  (⌘⇧↩, symmetric with Canvas's ⌥⌘↩), next/previous book (⌘⌃→/←), and direct book jump
  (⌃⌥1..9, deliberately distinct from ⌃1..9 worktree selection because plain folders
  interleave in book numbering).

**Non-goals**: no Shelf-only tab memory (the open book's active tab is the worktree's
active tab); no book reordering on the shelf; no spines for never-opened worktrees.

## Design / Approach

- **State**: `RepositoriesFeature.State.isShelfActive: Bool` as an independent flag, not
  a `SidebarSelection` case — Shelf still needs `selection` to track the open book, and a
  separate flag makes the sidebar sync fall out for free. Entering Canvas or Archived
  clears the flag.
- **Model**: `ShelfBook` unifies worktrees and plain folders behind `Worktree.ID`; plain
  folders use the repository ID, matching the synthetic worktree from
  `selectedTerminalWorktree`, so `openShelfBookID == selectedTerminalWorktree?.id` holds
  for both kinds without special-casing.
- **Book membership**: `RepositoriesFeature.State.openedWorktreeIDs: Set<Worktree.ID>`,
  inserted from `selectWorktree` / `selectRepository` / the `toggleShelf` entry path, plus
  a `markWorktreeOpened` catch-all that AppFeature dispatches on
  `.terminalEvent(.tabCreated)` — covering cold-launch auto-selection, layout restore, and
  any other path that sets `selection` directly. `orderedShelfBooks()` filters the live
  repository list against this set (so archived/removed worktrees drop off even if their
  ID lingers in the set).
- **Views** (`supacode/Features/Shelf/`): `ShelfView` lays out spines and the open area;
  `ShelfSpineView` + `ShelfSpineTabSlot` render one spine; `ShelfOpenBookView` is a
  leaner alternative to `WorktreeTerminalTabsView` that renders the terminal content
  stack without the horizontal tab bar (in Shelf the tab bar *is* the spine).
- **Animation**: as shipped in #230, spines lived in left/right stacks bridged with
  `matchedGeometryEffect`; the root `HStack` carries
  `.animation(.easeInOut(duration: 0.2), value: openBookID)` so sidebar-originated
  switches animate identically to spine clicks. (The stack model was later replaced — see
  [002-book-switch-jank.md](002-book-switch-jank.md).)
- **Close last tab retires the book**: `TerminalClient.Event.tabClosed` gained a
  `remainingTabs: Int` payload; on `remainingTabs == 0` AppFeature dispatches
  `.repositories(.markWorktreeClosed(id))`, which removes the ID from
  `openedWorktreeIDs` and — only while Shelf is active and the closed book was open —
  auto-advances selection to a neighboring book.
- **Commands plumbing**: Shelf menu commands merged into `SidebarCommands` rather than a
  new `Commands` struct, because SwiftUI's `@CommandsBuilder` caps direct children in a
  `.commands { }` block and a new top-level struct broke the build.

## Alternatives & decisions

- **Wrapper commands over multi-binding**: the spec wanted ⌘⌃→/← as a *second* binding on
  `selectNext/PreviousWorktree`, requiring the keybinding schema to grow from a single
  `shortcut` to a collection. Implemented instead as distinct `selectNextShelfBook` /
  `selectPreviousShelfBook` commands: book order includes interleaved plain folders, so
  "next book" is not semantically "next worktree", and the wrapper approach keeps
  `AppShortcut.Binding.shortcut` singular.
- **Close-last-tab behavior reversed mid-branch**: earlier drafts kept an empty book on
  the shelf with a placeholder terminal area. Reversed before merge (commit `795776e9`):
  a lingering empty book felt unnatural and was dead weight. (PR #230's test plan text
  still describes the pre-reversal behavior; the spec journal records the reversal.)
- **"Remove Book" replaced by "Close Worktree/Folder"** (#232, one day after launch): the
  original spine context-menu entry conflated "take this book off the Shelf" with
  destructive resource lifecycle (it archived worktrees, silently no-op'd on the main
  worktree, and removed plain folders from the app). The kind-aware Close action reuses
  the close-last-tab pipeline and drops the `.destructive` role — it is view-state, not
  data deletion.
- **`openedWorktreeIDs` is additive by design** (v1): stale IDs are tolerated because
  book iteration anchors on the live `repositories` array; pruning can be layered in
  later if the set grows unbounded.

## Amendments

- Updated 2026-10-11: repeatable book-switch measurements and a spine animation
  boundary — see [004-book-switch-performance.md](004-book-switch-performance.md).

- Updated 2026-04-29: book-switch jank investigation and retained performance fixes
  (#246) — see [002-book-switch-jank.md](002-book-switch-jank.md) and the verbatim trace
  record [jank-investigation.md](jank-investigation.md)
- Updated 2026-06-10: agent status badges on spines + trackpad book navigation
  (#432/#434), and the 2026-06-12 herdr-review decision to keep the 3-second status hold —
  see [003-agent-status-and-trackpad.md](003-agent-status-and-trackpad.md)
