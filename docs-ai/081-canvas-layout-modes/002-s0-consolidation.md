# 081 / 002 — S0: Naming and Path Consolidation

## Context

Before changing behavior, S0 gives every Canvas layout concept one name and one
code path, so S1–S3 change a single place each. No user-visible behavior
changes.

## Change

- `CanvasLayoutKind` (`App/Sources/Features/Canvas/Models/CanvasLayoutKind.swift`)
  describes the three automatic layouts: keybinding ID, default shortcut, SF
  Symbol, title, and tooltip. The toolbar renders its buttons from
  `CanvasLayoutKind.allCases`; the key handlers use one `onCanvasShortcut`
  helper; `CanvasCommandRequest.Command.layout(kind)` replaces
  `.arrange` / `.organize` / `.tile`; `CanvasDefaultLayout.layoutKind` maps the
  setting (`uniform` keeps its historical meaning, the size-preserving pack).
- `CanvasLayoutEngine` (`CanvasLayoutEngine.swift`) is the pure entry point for
  all layouts, with `CanvasLayoutMetrics` for shared constants and
  `CanvasGridLayout` for Organize's grid (previously inline in the view).
  `CanvasCardPacker` and `CanvasTileLayout` moved unchanged into their own files.
- `CanvasView.applyLayout(_:)` replaces `arrangeCardsWithFit` /
  `organizeCardsWithFit` / `tileCardsWithFit`; `layoutCards(_:)` replaces
  `arrangeCards` / `organizeCards` / `tileCards` and also runs the initial
  auto-layout.
- `CanvasCardRef` (renamed from `CanvasFocusCandidate`) and `canvasCards(in:)`
  replace `collectCardKeys`, `collectVisibleTabIDs`, `collectFocusCandidates`,
  and `cardEntries`. `TerminalTabID.canvasCardKey` names the persisted key.
- `CanvasCardLayout.frame(titleBarHeight:)` and `CanvasView.animateViewport(to:)`
  replace duplicated rect and animator code. The title bar height now has one
  definition, shared with `CanvasCardView`.
- `CanvasLayoutStore.hasAutoArrangedInSession` / `shouldAutoArrangeOnInitialEntry`
  are renamed `hasAppliedInitialLayoutInSession` / `shouldApplyInitialLayout`.

One deliberate normalization: every layout now stores its result through
`CanvasLayoutStore.applyLayouts(_:order:)`, which merges into the stored
layouts. Organize already merged; Arrange and Tile used to replace the whole
dictionary, dropping entries for cards not currently on the canvas (for
example, tabs of a worktree whose terminal state is not loaded). Kept entries
stay below the laid-out cards in the stacking order.

The command palette keeps one item kind per command, following its own
architecture ([031](../031-command-palette-architecture/000-plan.md)); only the
request it sends to Canvas (`CanvasCommandRequest.Command.layout(kind)`) is
unified.

## Verification

- `CanvasLayoutEngineTests`: empty input and unmeasured viewport are no-ops,
  every kind lays out every card without overlap, Organize equals the grid,
  Arrange preserves sizes, Tile fills the viewport, grid math, card frame, and
  the persisted keybinding IDs.
- `CanvasLayoutStoreTests.applyLayoutsKeepsUncoveredCardsBelowTheLaidOutOnes`
  covers the merge and stacking order.
- Full `make test` and `make check` pass.
- Prowl Debug (isolated data directory): entering Canvas with four cards
  applies the default Tile layout; ⌘⌥G, ⌘⌥R, and ⌘⌥T produce the expected
  layouts.
