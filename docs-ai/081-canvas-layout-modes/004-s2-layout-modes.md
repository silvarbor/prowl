# 081 / 004 — S2: Remembered Layout Modes

## Context

With S1, new cards no longer overlap, but a tiled board stops being tiled as
soon as a card is added: Arrange, Organize, and Tile were one-shot commands.
S2 makes the chosen layout a mode that Canvas keeps applying.

## Change

- **`CanvasLayoutMode`** (`App/Sources/Features/Canvas/Models/CanvasLayoutMode.swift`):
  `automatic(CanvasLayoutKind)` or `freeform`, encoded as one string
  (`arrange` / `organize` / `tile` / `freeform`). `cardSetChangeAction` is the
  pure decision for a card-set change: relayout, place new cards, or place now
  and relayout later.
- **Persistence**: `CanvasLayoutStore.mode` is saved in the existing
  `canvasCardLayouts` payload. Payloads written before modes existed load as
  `freeform` when they hold layouts, so an upgrade never rearranges a board.
  An unknown mode (from a newer version) is ignored without discarding the
  layouts.
- **Entry**: `CanvasLayoutStore.layoutForEntry(cardKeys:defaultKind:)` replaces
  the session-wide `hasAppliedInitialLayoutInSession` flag and
  `shouldApplyInitialLayout`. A canvas that never chose a mode, or whose cards
  were all unknown when it loaded, starts in `canvasDefaultLayout`; an automatic
  mode is re-applied on every entry (it is a function of the cards and the
  viewport); freeform keeps the stored positions.
  `CanvasView.performEntryLayoutIfNeeded()` runs this once both cards and a
  measured viewport exist, which also fixes a Canvas opened empty never fitting
  its first cards.
- **Transitions**: `applyLayout(_:)` (toolbar, shortcut, palette, CLI) sets
  `automatic(kind)`; committing a drag or resize sets `freeform`
  (`enterFreeformLayout()`).
- **Card-set changes** (`CanvasView.handleCardSetChange(to:)` in the new
  `CanvasView+Layout.swift`): in an automatic mode every card is laid out again
  and the viewport refits (`relayoutAutomatically`). Cards without a frame get
  theirs outside the animation, so they appear in place instead of flying in
  from the canvas origin; the others glide. In freeform, S1 placement applies.
  A new foreground card is focused either way. While a card is expanded the
  relayout is deferred (`needsAutomaticRelayout`) and runs when it is
  restored; if the expanded card itself closed, the relayout runs at once.
- **Viewport changes**: in an automatic mode a resized viewport (window resize,
  sidebar toggle) re-applies the layout 300 ms after the size settles
  (`.task(id: viewportSize)`), skipping sizes the layout was already computed
  for (`automaticLayoutViewportSize`).
- **Toolbar**: the active layout's symbol uses the accent color and its button
  is tinted, carries the selected accessibility trait, and switches its tooltip
  to "Tiling: cards re-tile as they are added or closed" (and equivalents). The
  Canvas help popover explains keeping a layout and how to leave it.
- `canvasDefaultLayout` keeps its stored values; it now names the layout a fresh
  canvas starts in.

## Review fixes

A review of the first cut found, and this slice fixes:

- ⌘T in an expanded card lost the deferred relayout (following the new card
  restored the expansion before the flag was set) and left the flag set; the
  flag is now set first and consumed by every relayout.
- A remembered automatic mode was replaced by the default whenever every card
  was new — on every launch without terminal layout restore. Only a freeform
  canvas of unknown cards falls back to the default now.
- The viewport-change relayout used the mode read before its 300 ms wait; it
  now re-reads the mode and size after the wait.
- Writing new cards' frames in a separate non-animated transaction cannot work
  (one body update, one transaction). New cards now opt out with
  `.animation(nil, value: hasLayout)` on the card.
- `fitToView` inside `withAnimation` does not animate the scroll container's
  transform; relayouts use `animateFitToView()` (the viewport animator), and
  `revealCard` computes from the animator's target so a reveal does not cancel
  a refit that already shows the card (seen in the Debug app: the new card was
  revealed at the old zoom instead of the board refitting).
- A relayout refits only if the viewport showed the fitted board
  (`fittedViewport`); otherwise it keeps the user's zoom and reveals the
  focused card. Choosing a layout always refits.
- A relayout waits while a card is being resized; a resize that changes
  nothing no longer enters freeform; the mode is saved only when it changes.

### Second review round (whole stack)

- A resize released with no change kept the deferred relayout pending until some
  other event; `commitResize` now runs `relayoutIfDeferred()`.
- Undo-close could return a card onto cards that moved into its old spot
  (automatic relayout, then a drag into freeform). Cards that reappear with a
  frame covered by a card that stayed are placed again (`dropCoveredLayouts`).
- User scroll, pan, middle-drag, and pinch now cancel a running viewport
  animation (`CanvasScrollContainer.onUserViewportChange`, gesture handlers).
- In a zoomed-in automatic board, a relayout no longer reveals the old focused card
  before following the new one; it reveals only the card that ends up focused.
- On entry, freeform placement anchors to the selected tab of the selected worktree
  (the card entry is about to focus) instead of the reading-order fallback.

## Decisions

- **Re-applying Tile and Organize resizes every terminal.** Accepted: filling
  the screen is the promise of Tile; a user who wants stable cards moves one
  and gets freeform.
- **No new `canvasDefaultLayout` values** (e.g. `organize`): older builds would
  fail to decode them and fall back to defaults for the whole settings file.
- **The mode lives with the card layouts** in `UserDefaults`, not in
  `settings.json`: it is board state, like positions, not a preference.

## Verification

- `CanvasLayoutModeTests`: JSON round trip, plain-string encoding, unknown
  values rejected, and the card-set change policy for each mode.
- `CanvasLayoutStoreTests`: legacy payloads load as freeform; a fresh canvas and
  a canvas of unknown cards start in the default; a remembered automatic layout
  applies on entry; an unknown stored mode keeps the layouts.
- Prowl Debug (isolated data directory): a fresh board of four cards starts in
  Tile with the Tile button highlighted; three quick ⌘T presses re-tile seven
  cards (three over four) with the last one focused; Organize then ⌘T keeps a
  grid; closing a card re-lays out the rest; resizing the window re-tiles;
  closing a card while another is expanded leaves the expansion alone and
  re-tiles on restore; in freeform, new cards go next to the focused card and
  nothing moves.
