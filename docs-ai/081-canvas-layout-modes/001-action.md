# 081 — Canvas Layout Modes: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-12 | S0: `CanvasLayoutKind`, `CanvasLayoutEngine`, `CanvasGridLayout`, `CanvasCardRef`, `applyLayout(_:)`; layout merging moved into `CanvasLayoutStore.applyLayouts` after review | #901, [002](002-s0-consolidation.md) |
| 2026-10-12 | S1: `CanvasCardPlacement`, following foreground-created cards (`lastForegroundCreatedTabID`), `CanvasViewportMath.reveal`, CLI tab creation stays in Canvas; review fixes for background tabs, empty Canvas, split panes, and reveal edge cases | #902, [003](003-s1-placement.md) |
| 2026-10-12 | S2: `CanvasLayoutMode`, relayout on card-set and viewport changes, toolbar state, persisted mode; review fixes for deferred relayouts, mode retention across launches, animation, and refit-vs-reveal | #903, [004](004-s2-layout-modes.md) |
| 2026-10-12 | S3: `prowl canvas show\|hide\|layout\|fit\|status` with contracts, schema, docs, and skill | #904, [005](005-s3-cli.md) |

## Outcome & current state

- Models: `App/Sources/Features/Canvas/Models/` — `CanvasLayoutKind`, `CanvasLayoutMode`,
  `CanvasLayoutEngine` (+ `CanvasLayoutMetrics`, `CanvasGridLayout`), `CanvasCardPacker`,
  `CanvasTileLayout`, `CanvasCardPlacement`, `CanvasCardLayout` (+ `CanvasLayoutStore`
  with the persisted mode), `CanvasFocusRequest` (+ `CanvasCardRef`,
  `CanvasNewCardFocus`, `CanvasCommandRequest.Command.layout/.fit`).
- View: `CanvasView+Layout.swift` owns entry layout, card-set changes, automatic
  relayouts, placement, following new cards, and fitting; `CanvasView+Focus.swift` owns
  focus requests, reveal, and expand; `CanvasViewportMath.reveal` and
  `CanvasViewportAnimator.activeTarget` in `CanvasSupportViews.swift`.
- CLI: `CLI/Sources/prowl/Commands/CanvasCommand.swift`,
  `Shared/Sources/ProwlCLIShared/CanvasCommandPayload.swift`, `CanvasInput` in
  `InputModels.swift`, `App/Sources/CLIService/CanvasCommandHandler.swift`.

## Deviations from plan

- S1 first routed "follow the new card" through the `tabCreated` terminal event. Rapid
  ⌘T presses raced the focus request, so the decision moved into the view, in the pass
  that places the card, with an explicit foreground mark on the terminal state.
- Freeform after a drag could not be exercised in the Debug app (the Mac was locked, so
  synthesized mouse input never reached SwiftUI controls); it is covered by code review
  and by entering freeform through the stored mode.

## Open questions

- `prowl focus` and `prowl create pane` still leave Canvas (they add no card to follow).
- Off-screen indicators for cards outside the viewport were deferred.
