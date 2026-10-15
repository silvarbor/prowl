import CoreGraphics
import Foundation
import Testing

@testable import Prowl

struct CanvasCardPlacementTests {
  private let spacing: CGFloat = 20
  private let titleBarHeight: CGFloat = 28
  private let newSize = CGSize(width: 800, height: 550)

  private var placement: CanvasCardPlacement {
    CanvasCardPlacement(spacing: spacing, titleBarHeight: titleBarHeight)
  }

  private func newCards(_ keys: [String]) -> [CanvasCardPlacement.NewCard] {
    keys.map { CanvasCardPlacement.NewCard(key: $0, size: newSize) }
  }

  private func frame(_ layout: CanvasCardLayout?) -> CGRect {
    layout?.frame(titleBarHeight: titleBarHeight) ?? .null
  }

  private func expectNoOverlap(_ layouts: [String: CanvasCardLayout]) {
    let frames = layouts.sorted { $0.key < $1.key }.map { frame($0.value) }
    for (index, lhs) in frames.enumerated() {
      for rhs in frames[(index + 1)...] {
        let overlap = lhs.intersection(rhs)
        #expect(overlap.isNull || overlap.width <= 0 || overlap.height <= 0)
      }
    }
  }

  /// Four cards tiled into a 1600×1000 viewport, as Canvas's default layout does.
  private var tiledLayouts: [String: CanvasCardLayout] {
    CanvasTileLayout(spacing: 12, titleBarHeight: titleBarHeight).layout(
      keys: ["a", "b", "c", "d"],
      viewport: CGSize(width: 1344, height: 948),
      comfortableSize: CGSize(width: 480, height: 330)
    )
  }

  @Test func firstCardOnAnEmptyCanvasGoesToTheOrigin() {
    let placed = placement.place(newCards(["new"]), existing: [:], anchorKey: nil)

    #expect(frame(placed["new"]).origin == CGPoint(x: spacing, y: spacing))
    #expect(placed["new"]?.size == newSize)
  }

  @Test func newCardGoesRightOfTheAnchor() {
    let anchor = CanvasCardLayout(position: CGPoint(x: 500, y: 400), size: CGSize(width: 600, height: 400))
    let placed = placement.place(newCards(["new"]), existing: ["anchor": anchor], anchorKey: "anchor")

    let anchorFrame = frame(anchor)
    #expect(frame(placed["new"]).minX == anchorFrame.maxX + spacing)
    #expect(frame(placed["new"]).minY == anchorFrame.minY)
  }

  @Test func newCardGoesBelowTheAnchorWhenItsRightSideIsTaken() {
    let size = CGSize(width: 600, height: 400)
    let anchor = CanvasCardLayout(position: CGPoint(x: 320, y: 234), size: size)
    let neighbor = CanvasCardLayout(position: CGPoint(x: 940, y: 234), size: size)
    let placed = placement.place(
      newCards(["new"]),
      existing: ["anchor": anchor, "neighbor": neighbor],
      anchorKey: "anchor"
    )

    let anchorFrame = frame(anchor)
    #expect(frame(placed["new"]).minX == anchorFrame.minX)
    #expect(frame(placed["new"]).minY == anchorFrame.maxY + spacing)
  }

  @Test func newCardsNeverOverlapATiledCanvas() {
    // The original bug: after Tile, new default-size cards landed on top of
    // tiled cards or of each other.
    let existing = tiledLayouts
    for anchorKey in ["a", "b", "c", "d", nil] as [String?] {
      let placed = placement.place(newCards(["n1", "n2", "n3", "n4", "n5"]), existing: existing, anchorKey: anchorKey)
      #expect(placed.count == 5)
      expectNoOverlap(existing.merging(placed) { $1 })
    }
  }

  @Test func newCardsKeepSpacingFromEveryCard() {
    let existing = tiledLayouts
    let placed = placement.place(newCards(["n1", "n2", "n3"]), existing: existing, anchorKey: "d")
    let all = existing.merging(placed) { $1 }

    for (key, layout) in placed {
      let padded = frame(layout).insetBy(dx: -(spacing - 1), dy: -(spacing - 1))
      for (otherKey, other) in all where otherKey != key {
        let overlap = padded.intersection(frame(other))
        #expect(overlap.isNull || overlap.width <= 0 || overlap.height <= 0)
      }
    }
  }

  @Test func placingABatchMatchesPlacingOneAtATime() {
    let existing = tiledLayouts
    let batch = placement.place(newCards(["n1", "n2", "n3"]), existing: existing, anchorKey: "b")

    var sequential = existing
    var anchor = "b"
    for key in ["n1", "n2", "n3"] {
      let placed = placement.place(newCards([key]), existing: sequential, anchorKey: anchor)
      sequential.merge(placed) { $1 }
      anchor = key
    }

    for key in ["n1", "n2", "n3"] {
      #expect(batch[key] == sequential[key])
    }
  }

  @Test func withoutAnAnchorCardsContinueAfterTheLastCardInReadingOrder() {
    let existing = tiledLayouts
    // Tile's bottom-right card ends the reading order.
    let lastFrame = frame(existing["d"])
    let placed = placement.place(newCards(["new"]), existing: existing, anchorKey: nil)

    #expect(frame(placed["new"]).minX == lastFrame.maxX + spacing)
    #expect(frame(placed["new"]).minY == lastFrame.minY)
  }

  @Test func unknownAnchorFallsBackToReadingOrder() {
    let existing = tiledLayouts
    let withUnknown = placement.place(newCards(["new"]), existing: existing, anchorKey: "missing")
    let withoutAnchor = placement.place(newCards(["new"]), existing: existing, anchorKey: nil)

    #expect(withUnknown == withoutAnchor)
  }

  @Test func placementIsDeterministic() {
    let existing = tiledLayouts
    let first = placement.place(newCards(["n1", "n2", "n3", "n4"]), existing: existing, anchorKey: "a")
    let second = placement.place(newCards(["n1", "n2", "n3", "n4"]), existing: existing, anchorKey: "a")

    #expect(first == second)
  }
}
