# 081 — Canvas Layout Modes: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-10-12 |
| **Primary PRs** | #901 (S0), #902 (S1), #903 (S2), #904 (S3) |
| **Related** | [005-canvas-live-sessions](../005-canvas-live-sessions/000-plan.md), [024-canvas-interaction-evolution](../024-canvas-interaction-evolution/000-plan.md), [043-canvas-tile-layout](../043-canvas-tile-layout/000-plan.md), [060-prowl-cli-targeting-and-contract-governance](../060-prowl-cli-targeting-and-contract-governance/000-plan.md), [#760](https://github.com/onevcat/Prowl/issues/760), `docs/components/canvas.md`, `docs/components/cli.md` |

## Background

Canvas has three one-shot automatic layouts — Arrange (⌘⌥R, size-preserving
pack), Organize (⌘⌥G, uniform √N grid), and Tile (⌘⌥T, resize to fill the
viewport, the default initial layout since [043](../043-canvas-tile-layout/000-plan.md)).
Once a layout ran, Canvas forgot it. Three problems followed:

1. **New cards overlap existing ones.** `CanvasView.ensureLayouts` placed every
   new card in "virtual grid slot N" of a default-size grid whose column count
   was `ceil(√positionedCount)`. It never looked at where cards actually were:
   - the column count changes as cards are added, so slots get reused (starting
     from one card and adding one at a time, card 3 lands on card 2 and card 7
     on card 5);
   - after Arrange, Tile, a drag, or a resize, the virtual grid has nothing to do
     with the real layout — with Tile as the default, a new card almost always
     lands on top of a tiled one.

   Pressing ⌘T quickly made it look worse because SwiftUI coalesces several new
   tabs into one `onChange(of: allCardKeys)`, so the batch size — and therefore
   which slots collide — depends on typing speed. The store itself was never
   stale.
2. **The viewport ignores new cards.** ⌘T in a card runs Ghostty's `new_tab`
   action, which creates the tab directly in `WorktreeTerminalState` and never
   issues a Canvas focus request. A card created outside the viewport is
   invisible, and the user cannot tell that a tab was created at all. The
   sidebar "new tab" button and undo-close do request focus, so behavior
   differed by entry point.
3. **Layouts are not scriptable.** Agents create many tabs with
   `prowl create tab` but cannot ask Canvas to tile them afterwards (#760).

## Goals

- A new card never overlaps an existing card, regardless of how fast or from
  where it was created.
- Creating a focused tab in Canvas always shows the new card.
- Canvas remembers the layout the user chose. In an automatic layout the card
  set determines the layout: adding or closing a card re-applies it and fits
  the viewport. After a manual drag or resize the canvas is freeform and keeps
  every card where the user put it.
- `prowl canvas …` commands show/hide Canvas and apply a layout (#760).
- One code path per concept: a single layout entry point, a single card
  enumeration, a single "card was created" path.

### Non-goals

- Off-screen indicators for cards outside the viewport (deferred).
- Changing the three layout algorithms themselves (packer, grid, tile).
- Renaming persisted identifiers: keybinding IDs (`arrange_canvas_cards`, …),
  command palette item IDs, the `canvasDefaultLayout` setting key, and its raw
  values stay as they are.

## Design / Approach

### Slices

| Slice | Scope | Behavior change |
| --- | --- | --- |
| **S0** | Naming and path consolidation | None (refactor) |
| **S1** | Collision-free placement, unified creation path, viewport follows new cards | Yes |
| **S2** | Persistent layout mode; automatic relayout on card-set change; toolbar state | Yes |
| **S3** | `prowl canvas` CLI (#760) | Yes (new commands) |

### S0 — Consolidation

- `CanvasLayoutKind` (`arrange` / `organize` / `tile`) is the single description
  of an automatic layout: keybinding ID, default shortcut, SF Symbol, title, and
  tooltip. The toolbar, key handlers, palette requests
  (`CanvasCommandRequest.Command.layout(kind)`), and the default-layout setting
  (`CanvasDefaultLayout.layoutKind`) all resolve through it.
- `CanvasLayoutEngine.layouts(for:input:metrics:)` is the pure entry point for
  all three algorithms. `CanvasGridLayout` extracts Organize's grid math from the
  view; `CanvasCardPacker` and `CanvasTileLayout` move to their own files.
  `CanvasLayoutMetrics` owns the shared constants (title bar height, spacings).
- `CanvasView.applyLayout(_:)` replaces the three `*CardsWithFit` functions;
  `layoutCards(_:)` is the viewport-free core used by the initial auto-layout.
- `CanvasCardRef` (formerly `CanvasFocusCandidate`) plus
  `canvasCards(in:)` replace four parallel enumerations of the same tabs;
  `TerminalTabID.canvasCardKey` names the persisted card key.
- `CanvasCardLayout.frame(titleBarHeight:)` replaces duplicated rect math, and
  `animateViewport(to:)` replaces three copies of the animator callback.

### S1 — Placement and creation

- `CanvasCardPlacement` (pure) finds a free slot for each new card against the
  real frames of the existing cards, preferring positions next to an anchor card
  (the focused card): right, then below, then the nearest free corner slot.
  A batch of new cards is placed one at a time with the previous new card as
  the next anchor, so the result does not depend on how creations were batched.
- A card created in the foreground (marked on the terminal state) — every foreground
  creation path (⌘T, palette, sidebar, CLI without `--background`) — takes
  Canvas focus in the same pass that places it, and is revealed with the
  smallest pan, zooming out only when it does not fit. Background creations
  leave focus alone. (Corrected during S1: the plan first routed this through
  the `tabCreated` event; see [003](003-s1-placement.md).)
- Foreground `prowl create tab` no longer leaves Canvas.

### S2 — Layout modes

- `CanvasLayoutMode` is `automatic(CanvasLayoutKind)` or `freeform`, persisted
  with the card layouts in `CanvasLayoutStore`.
- Applying a layout (toolbar, shortcut, palette, CLI) sets `automatic(kind)`.
  Committing a drag or resize sets `freeform`.
- In `automatic` mode, a change to the card set re-applies the layout and fits
  the viewport, animated; in `freeform` mode, S1 placement applies.
- The toolbar marks the active automatic layout.
- First entry uses `canvasDefaultLayout`. Stored layouts written by a version
  without a mode load as `freeform`, so upgrading never rearranges cards.

### S3 — CLI

- `prowl canvas show|hide`, `prowl canvas layout <arrange|organize|tile>`,
  `prowl canvas fit`, and `prowl canvas status` following the 060 contract
  governance (contracts, docs, bundled skill).
- A layout chosen before Canvas has measured its viewport sets the mode; the
  entry layout applies it once the viewport is known.

## Alternatives & decisions

- **Remembered mode vs. per-creation placement only.** Placement alone fixes
  the overlap but leaves Tile users with a "tiled grid plus one stray card".
  Remembering the mode keeps each layout's promise (Tile fills the screen) and
  gives the CLI a durable effect.
- **Re-applying a layout resizes terminals.** In Tile and Organize every card
  changes size when the set changes, so TUIs reflow. Accepted: filling the
  screen is the point of Tile; users who want stability drag a card and get
  freeform.
- **Reveal vs. center for new cards.** Centering and zooming to every new card
  makes rapid ⌘T presses jump around; revealing keeps the surrounding context.
- **Unknown mode on upgrade = freeform.** Rearranging a user's saved canvas on
  first launch of a new version would be surprising.

## Amendments

- Updated 2026-10-12: S0 consolidation shipped — see [002-s0-consolidation.md](002-s0-consolidation.md)
- Updated 2026-10-12: S1 placement and following new cards — see [003-s1-placement.md](003-s1-placement.md)
- Updated 2026-10-12: S2 remembered layout modes — see [004-s2-layout-modes.md](004-s2-layout-modes.md)
- Updated 2026-10-12: S3 `prowl canvas` CLI — see [005-s3-cli.md](005-s3-cli.md); action log in [001-action.md](001-action.md)
