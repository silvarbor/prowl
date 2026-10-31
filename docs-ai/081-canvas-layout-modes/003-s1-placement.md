# 081 / 003 — S1: Collision-Free Placement and Following New Cards

## Context

New cards overlapped existing ones and appeared outside the viewport (see the
plan's Background). S1 fixes both without introducing layout modes.

## Change

- **`CanvasCardPlacement`** (`App/Sources/Features/Canvas/Models/CanvasCardPlacement.swift`)
  places new cards against the real frames of every stored card: right of the
  anchor, else below it, else the free slot (right of or below any card)
  nearest the anchor. Candidates keep `cardSpacing` from every card. Cards
  placed in one call chain off each other, so a batch gives the same result as
  one-at-a-time creation. `CanvasView.placeUnpositionedCards` uses it whenever
  some cards are already placed; a fresh canvas still gets the balanced grid.
  Stored layouts of cards that are not on the canvas right now (tabs closed in
  this session, which undo can bring back) are obstacles too, so they never
  come back underneath a new card. Entering Canvas prunes layouts of tabs that
  no longer exist before placing anything.
- **Following new cards happens in the view, in the same pass as placement.**
  `WorktreeTerminalState.lastForegroundCreatedTabID` marks the latest tab
  created with `focusing: true` (⌘T through Ghostty's `new_tab` or the New
  Terminal menu, the palette, the sidebar's new-tab action, foreground
  `prowl create tab`, run script). `CanvasView.followNewCard(among:states:)`
  focuses the last newly placed card carrying that mark
  (`CanvasNewCardFocus.cardToFollow`), reveals it, and clears the marks. An
  expanded card is restored first so the new card is not hidden behind it.
  Background creations, layout restore, and undo never set the mark. (The
  selected tab is not a usable proxy: a background tab created in a worktree
  without tabs still becomes its selected tab.)
- **Reveal** (`CanvasViewportMath.reveal`) does nothing for a fully visible
  card and otherwise pans the least amount that shows the whole card. When the
  card does not fit at the current zoom, new cards zoom out just enough and
  center; spatial navigation keeps the user's zoom (its previous behavior, now
  through the same function) and shows the card's top-left, title bar first.
- **The CLI stays in Canvas.** Foreground `prowl create tab` (shell or Profile)
  and workflow tab launches used to select the worktree, which left Canvas. In
  Canvas they now leave the view alone and the new card follows the rule above
  (`ProwlApp.selectCLIWorktreeContextForNewTab`). Split panes (`create pane`)
  and `prowl focus` keep their previous behavior: they add no card, so they
  still select the worktree.
- The sidebar new-tab action in Canvas no longer needs the synchronous
  `TerminalClient.createTabInDirectory` endpoint (removed); it sends the regular
  `.createTabInDirectory` command. Undo-restored tabs still request focus through
  the reducer, now with `CanvasFocusRequest.Viewport.reveal`.
- A card renders once before it has a layout; it stays transparent for that
  frame instead of flashing at the canvas origin.

## Decision: why not drive this from the reducer

The first cut added the new tab ID to `TerminalClient.Event.tabCreated` and let
`AppFeature` issue a Canvas focus request for every focused creation. In the
Debug app, three fast ⌘T presses then placed the third card below the first:
the focus request for the second card had not reached the view yet, so the
anchor was stale and the result depended on typing speed again. Deciding focus
in the view, in the pass that places the card, removes that race.

## Review fixes

A review of the first cut found: background tabs in a worktree without tabs
were followed (fixed by the foreground mark above); the first card created in
an empty Canvas was not followed (the fresh-canvas grid now returns its keys
too); a foreground `create pane --profile` stayed in Canvas without a card to
focus (split panes keep selecting the worktree); a fully visible card near the
edge was zoomed out (reveal now returns early); and an oversized card revealed
without zoom showed its bottom edge (it now shows the top-left).

## Verification

- `CanvasCardPlacementTests`: origin on an empty canvas; right of / below the
  anchor; no overlap and full spacing after a Tile layout for every anchor;
  batch equals sequential; reading-order fallback; determinism.
- `CanvasViewportMathTests`: reveal is a no-op when visible (also inside the
  margin), pans to the far edge, zooms out to fit an oversized card, keeps the
  zoom when not allowed and then shows the top-left, and keeps the title bar on
  screen when even the minimum scale is too large.
- `CanvasNewCardFocusTests`: the last foreground new card is followed;
  background creations and foreground tabs that are not new cards are not.
- `RepositoriesFeatureTests`: the sidebar new-tab action stays in Canvas and
  sends one create command; undo restore requests a reveal.
- Prowl Debug (isolated data directory, in-process window capture): four tiled
  cards plus three ⌘T presses in quick succession — before: two new cards on the
  same slot and all three off-screen; after: three cards in a row to the right
  of the focused card, no overlap, the last one focused and in view.
  `prowl create tab` after Organize stays in Canvas, lands right of the focused
  card, and is revealed.
