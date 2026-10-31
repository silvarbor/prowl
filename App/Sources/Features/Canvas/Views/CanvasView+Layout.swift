import SwiftUI

/// Card placement, automatic layouts, and the layout mode.
extension CanvasView {
  // MARK: - Cards

  /// Every card on the canvas, in canvas order: worktree order, then tab order.
  /// A tab is a card only once its surface exists.
  func canvasCards(in states: [WorktreeTerminalState]) -> [CanvasCardRef] {
    states.flatMap { state in
      state.tabManager.tabs.compactMap { tab in
        state.hasCanvasCard(tab.id) ? CanvasCardRef(worktreeID: state.worktreeID, tabID: tab.id) : nil
      }
    }
  }

  func currentCardKeys() -> [String] {
    canvasCards(in: terminalManager.activeWorktreeStates).map(\.key)
  }

  // MARK: - Layout Mode

  /// Lay out the cards the first time Canvas has both cards and a measured
  /// viewport: in the remembered automatic layout, or — on a fresh canvas — in
  /// the default layout from Settings. Freeform keeps the stored positions.
  func performEntryLayoutIfNeeded() {
    guard !hasPerformedInitialFit, hasMeasuredViewport else { return }
    let keys = currentCardKeys()
    guard !keys.isEmpty else { return }
    hasPerformedInitialFit = true
    let defaultKind = settingsFile.global.canvasDefaultLayout.layoutKind
    if let kind = layoutStore.layoutForEntry(cardKeys: keys, defaultKind: defaultKind) {
      layoutCards(kind)
    }
    fitToView()
  }

  /// React to cards appearing or closing. In an automatic layout every card is
  /// laid out again (refitting if the view showed the whole board); in
  /// freeform new cards get free spots and nothing else moves. Either way a new
  /// foreground card takes focus.
  ///
  /// `appeared` are the cards new to the canvas since the last change: newly
  /// created ones, and ones coming back (undo-close) with a stored frame.
  func handleCardSetChange(to cardKeys: [String], appeared: Set<String> = []) {
    guard !cardKeys.isEmpty else { return }
    // A returning card's old frame may now be covered by cards that moved in
    // since it closed; place it again instead of on top of them.
    dropCoveredLayouts(of: appeared, among: cardKeys)
    guard hasPerformedInitialFit else {
      // The first cards of an empty Canvas, or cards that arrived before the
      // viewport was measured.
      let placed = placeUnpositionedCards(cardKeys)
      performEntryLayoutIfNeeded()
      followNewCard(among: placed, states: terminalManager.activeWorktreeStates)
      return
    }

    let action =
      layoutStore.mode?.cardSetChangeAction(canRelayoutNow: canRelayoutNow(cardKeys: cardKeys)) ?? .placeNewCards
    switch action {
    case .relayout(let kind):
      let newKeys = cardKeys.filter { layoutStore.cardLayouts[$0] == nil }
      let refitted = relayoutAutomatically(kind, revealsFocusedCard: false)
      let followed = followNewCard(among: newKeys, states: terminalManager.activeWorktreeStates)
      // A zoomed-in view keeps showing the focused card as the others move.
      if !refitted, !followed, let focused = selectionState.primaryTabID {
        revealCard(focused, allowsZoomOut: true)
      }
    case .placeNewCards:
      followNewCard(among: placeUnpositionedCards(cardKeys), states: terminalManager.activeWorktreeStates)
    case .placeNewCardsAndRelayoutLater:
      // Set before following: restoring an expanded card for the new one runs
      // the deferred relayout right away.
      needsAutomaticRelayout = true
      followNewCard(among: placeUnpositionedCards(cardKeys), states: terminalManager.activeWorktreeStates)
    }
  }

  /// A relayout would cancel an expanded card, or move a card the user is
  /// resizing, and Arrange and Tile need a measured viewport.
  func canRelayoutNow(cardKeys: [String]) -> Bool {
    let isExpandedCardShown = expandedTabID.map { cardKeys.contains($0.canvasCardKey) } ?? false
    return !isExpandedCardShown && activeResize.isEmpty && hasMeasuredViewport
  }

  /// Re-apply the automatic layout once a deferred change can run (the
  /// expanded card was restored).
  func relayoutIfDeferred() {
    guard needsAutomaticRelayout else { return }
    guard let kind = layoutStore.mode?.automaticKind else {
      needsAutomaticRelayout = false
      return
    }
    guard canRelayoutNow(cardKeys: currentCardKeys()) else { return }
    relayoutAutomatically(kind)
  }

  /// An automatic layout depends on the viewport, so a resized window lays the
  /// cards out again — once the size settles, to avoid reflowing every
  /// terminal on each frame of a live resize.
  func relayoutAfterViewportChange() async {
    guard hasPerformedInitialFit, hasMeasuredViewport, layoutStore.mode?.automaticKind != nil else { return }
    guard viewportSize != automaticLayoutViewportSize || needsAutomaticRelayout else { return }
    try? await Task.sleep(for: .milliseconds(300))
    guard !Task.isCancelled else { return }
    // Re-read after the wait: the user may have picked another layout, moved a
    // card, or a card-set change may already have laid the cards out.
    guard let kind = layoutStore.mode?.automaticKind,
      viewportSize != automaticLayoutViewportSize || needsAutomaticRelayout
    else { return }
    if canRelayoutNow(cardKeys: currentCardKeys()) {
      relayoutAutomatically(kind)
    } else {
      needsAutomaticRelayout = true
    }
  }

  // MARK: - Automatic Layouts

  var hasMeasuredViewport: Bool {
    viewportSize.width > 0 && viewportSize.height > 0
  }

  func layoutShortcut(_ kind: CanvasLayoutKind) -> AppShortcut? {
    AppShortcuts.resolvedShortcut(for: kind.commandID, in: resolvedKeybindings)
  }

  /// Choose `kind` as the canvas's automatic layout and apply it. Shared by the
  /// toolbar buttons, the keyboard shortcuts, the command palette, and the CLI.
  func applyLayout(_ kind: CanvasLayoutKind) {
    layoutStore.mode = .automatic(kind)
    cancelExpandForRelayout()
    // Choosing a layout shows the whole board again.
    relayoutAutomatically(kind, refitting: true)
  }

  /// Lay out every card with `kind`, animated. Existing cards glide to their
  /// new frames; a card without a frame yet appears at its own (see
  /// `cardView`). The viewport refits when it showed the whole board before
  /// (or `refitting` asks for it); a viewport the user zoomed or panned keeps
  /// its zoom and follows the focused card instead.
  /// Returns whether the viewport refits.
  @discardableResult
  func relayoutAutomatically(
    _ kind: CanvasLayoutKind,
    refitting: Bool = false,
    revealsFocusedCard: Bool = true
  ) -> Bool {
    needsAutomaticRelayout = false
    guard let result = computeLayouts(kind) else { return false }
    let refits = refitting || isViewportFitted
    withAnimation(expandAnimation) {
      layoutStore.applyLayouts(result.layouts, order: result.keys)
    }
    automaticLayoutViewportSize = viewportSize
    if refits {
      animateFitToView()
    } else if revealsFocusedCard, let focused = selectionState.primaryTabID {
      revealCard(focused, allowsZoomOut: true)
    }
    return refits
  }

  /// Lay out every card with `kind`, without animation or touching the
  /// viewport. A no-op when there are no cards, or when Arrange or Tile have
  /// no measured viewport yet.
  func layoutCards(_ kind: CanvasLayoutKind) {
    guard let result = computeLayouts(kind) else { return }
    layoutStore.applyLayouts(result.layouts, order: result.keys)
    automaticLayoutViewportSize = viewportSize
  }

  private func computeLayouts(_ kind: CanvasLayoutKind) -> (keys: [String], layouts: [String: CanvasCardLayout])? {
    let keys = currentCardKeys()
    let input = CanvasLayoutEngine.Input(
      keys: keys,
      cardSizes: layoutStore.cardLayouts.mapValues(\.size),
      viewport: viewportSize,
      defaultCardSize: adaptiveDefaultCardSize
    )
    let layouts = CanvasLayoutEngine.layouts(for: kind, input: input, metrics: layoutMetrics)
    return layouts.isEmpty ? nil : (keys, layouts)
  }

  /// A drag or resize by the user ends any automatic layout.
  func enterFreeformLayout() {
    guard layoutStore.mode != .freeform else { return }
    layoutStore.mode = .freeform
    needsAutomaticRelayout = false
  }

  // MARK: - Placement

  /// Give every card that has no stored layout a position. On a fresh canvas
  /// the cards form a balanced grid; after that, each new card goes to a free
  /// spot next to the focused card without moving any other card.
  ///
  /// Returns the keys that were placed, in canvas order.
  @discardableResult
  func placeUnpositionedCards(_ cardKeys: [String]) -> [String] {
    let unpositioned = cardKeys.filter { layoutStore.cardLayouts[$0] == nil }
    guard !unpositioned.isEmpty else { return [] }
    let cardSize = adaptiveDefaultCardSize

    guard unpositioned.count < cardKeys.count else {
      let grid = CanvasGridLayout(spacing: layoutMetrics.cardSpacing, titleBarHeight: titleBarHeight)
      layoutStore.setCardLayouts(
        layoutStore.cardLayouts.merging(grid.layout(keys: unpositioned, cardSize: cardSize)) { _, new in new })
      return unpositioned
    }

    // Every stored card is an obstacle, including ones not on the canvas right
    // now: they come back where they were.
    let placement = CanvasCardPlacement(spacing: layoutMetrics.cardSpacing, titleBarHeight: titleBarHeight)
    let placed = placement.place(
      unpositioned.map { CanvasCardPlacement.NewCard(key: $0, size: cardSize) },
      existing: layoutStore.cardLayouts,
      anchorKey: placementAnchorKey
    )
    // Assign once to trigger a single save.
    layoutStore.setCardLayouts(layoutStore.cardLayouts.merging(placed) { _, new in new })
    return unpositioned
  }

  /// The card new cards go next to: the focused card, or — before Canvas has
  /// focused one on entry — the selected tab of the selected worktree, which
  /// entry is about to focus.
  var placementAnchorKey: String? {
    if let primary = selectionState.primaryTabID { return primary.canvasCardKey }
    guard let worktreeID = terminalManager.selectedWorktreeID,
      let state = terminalManager.activeWorktreeStates.first(where: { $0.worktreeID == worktreeID })
    else { return nil }
    return state.tabManager.selectedTabId?.canvasCardKey
  }

  /// Forget the stored frames of `appeared` cards that overlap a card that
  /// stayed on the canvas, so they are placed again.
  func dropCoveredLayouts(of appeared: Set<String>, among cardKeys: [String]) {
    guard !appeared.isEmpty else { return }
    let stayed = cardKeys.filter { !appeared.contains($0) }.compactMap {
      layoutStore.cardLayouts[$0]?.frame(titleBarHeight: titleBarHeight)
    }
    var layouts = layoutStore.cardLayouts
    for key in appeared {
      guard let frame = layouts[key]?.frame(titleBarHeight: titleBarHeight) else { continue }
      if stayed.contains(where: { $0.intersection(frame).width > 1 && $0.intersection(frame).height > 1 }) {
        layouts[key] = nil
      }
    }
    if layouts.count != layoutStore.cardLayouts.count {
      layoutStore.setCardLayouts(layouts)
    }
  }

  /// A tab created in the foreground — ⌘T, the palette, the sidebar, the CLI
  /// without `--background` — takes canvas focus as soon as its card is placed
  /// and is revealed, so the user always sees what they created. Focusing it in
  /// the same pass that placed it also makes it the anchor for the next new
  /// card, however quickly that one follows. Background creations leave focus
  /// and the view alone.
  /// Returns whether a card was followed.
  @discardableResult
  func followNewCard(among placedKeys: [String], states: [WorktreeTerminalState]) -> Bool {
    guard !placedKeys.isEmpty else { return false }
    let newKeys = Set(placedKeys)
    let foregroundTabIDs = Set(states.compactMap(\.lastForegroundCreatedTabID))
    let card = CanvasNewCardFocus.cardToFollow(
      newKeys: newKeys,
      cards: canvasCards(in: states),
      foregroundTabIDs: foregroundTabIDs
    )
    // Claim the foreground marks of the cards placed now.
    for state in states {
      if let tabID = state.lastForegroundCreatedTabID, newKeys.contains(tabID.canvasCardKey) {
        state.lastForegroundCreatedTabID = nil
      }
    }
    guard let card else { return false }
    // ⌘T inside an expanded card: show the new card instead of hiding it behind
    // the expansion.
    collapseExpand()
    focusSingleCard(card.tabID, states: states)
    revealCard(card.tabID, allowsZoomOut: true)
    return true
  }

  // MARK: - Viewport

  /// The viewport that shows every card, or nil without cards or a measured
  /// viewport.
  func fitTarget() -> CanvasViewportAnimator.Snapshot? {
    let bounds = currentCardKeys().reduce(CGRect.null) { bounds, key in
      guard let layout = layoutStore.cardLayouts[key] else { return bounds }
      return bounds.union(layout.frame(titleBarHeight: titleBarHeight))
    }
    guard
      let fit = CanvasViewportMath.fit(
        bounds: bounds,
        viewport: viewportSize,
        bottomReserve: bottomToolbarReserve,
        padding: viewportFitPadding
      )
    else { return nil }
    return CanvasViewportAnimator.Snapshot(offset: fit.offset, scale: fit.scale)
  }

  /// Show every card at once, immediately.
  func fitToView() {
    guard let target = fitTarget() else { return }
    viewportAnimator.cancel()
    canvasOffset = target.offset
    canvasScale = target.scale
    lastCanvasScale = target.scale
    lastCanvasOffset = target.offset
    fittedViewport = target
  }

  /// Show every card at once, animated.
  func animateFitToView() {
    guard let target = fitTarget() else { return }
    animateViewport(to: target)
    fittedViewport = target
  }

  /// Whether the viewport shows the fitted board — or is animating there — so
  /// a relayout should refit it rather than keep a zoom the user chose.
  var isViewportFitted: Bool {
    guard let fittedViewport else { return false }
    let current =
      viewportAnimator.activeTarget ?? CanvasViewportAnimator.Snapshot(offset: canvasOffset, scale: canvasScale)
    return current.isClose(to: fittedViewport)
  }

  /// Animate the viewport to `target` with `viewportAnimator`, which drives
  /// the transform frame by frame (a SwiftUI animation would not reach the
  /// scroll container's bindings). A pan-only animation never writes the
  /// scale, and any user scroll, pan, or zoom cancels the animation.
  func animateViewport(to target: CanvasViewportAnimator.Snapshot) {
    let start = CanvasViewportAnimator.Snapshot(offset: canvasOffset, scale: canvasScale)
    let animatesScale = start.scale != target.scale
    viewportAnimator.animate(from: start, to: target) { [self] snapshot in
      canvasOffset = snapshot.offset
      lastCanvasOffset = snapshot.offset
      if animatesScale {
        canvasScale = snapshot.scale
        lastCanvasScale = snapshot.scale
      }
    }
  }

  /// Remove stored layouts for tabs that no longer exist.
  func cleanStaleLayouts() {
    let visibleKeys = Set(currentCardKeys())
    guard !visibleKeys.isEmpty || hasSeenCanvasCards else { return }
    layoutStore.prune(to: visibleKeys)
  }
}

extension WorktreeTerminalState {
  /// A tab is a Canvas card once its surface exists.
  func hasCanvasCard(_ tabID: TerminalTabID) -> Bool {
    surfaceView(for: tabID) != nil
  }
}
