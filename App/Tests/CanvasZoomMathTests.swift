import CoreGraphics
import Foundation
import Testing

@testable import Prowl

struct CanvasZoomMathTests {
  @Test func positiveDeltaIncreasesScale() {
    let result = CanvasZoomMath.zoom(
      currentScale: 1.0,
      currentOffset: .zero,
      deltaY: 10,
      anchor: .zero,
      isPrecise: false
    )

    #expect(result.scale > 1.0)
  }

  @Test func negativeDeltaDecreasesScale() {
    let result = CanvasZoomMath.zoom(
      currentScale: 1.0,
      currentOffset: .zero,
      deltaY: -10,
      anchor: .zero,
      isPrecise: false
    )

    #expect(result.scale < 1.0)
  }

  @Test func scaleIsClampedToMaximum() {
    let result = CanvasZoomMath.zoom(
      currentScale: CanvasZoomMath.maxScale,
      currentOffset: .zero,
      deltaY: 1000,
      anchor: .zero,
      isPrecise: false
    )

    #expect(result.scale == CanvasZoomMath.maxScale)
  }

  @Test func scaleIsClampedToMinimum() {
    let result = CanvasZoomMath.zoom(
      currentScale: CanvasZoomMath.minScale,
      currentOffset: .zero,
      deltaY: -1000,
      anchor: .zero,
      isPrecise: false
    )

    #expect(result.scale == CanvasZoomMath.minScale)
  }

  @Test func anchorPointStaysPutAfterZoom() {
    // The canvas point under the anchor must map to the same screen position
    // before and after zooming. Using `screen = canvas * scale + offset`,
    // the canvas point under `anchor` is `(anchor - offset) / scale`. After
    // applying the new scale and offset, it must still land on `anchor`.
    let currentScale: CGFloat = 1.0
    let currentOffset = CGSize(width: 50, height: 30)
    let anchor = CGPoint(x: 200, y: 150)

    let result = CanvasZoomMath.zoom(
      currentScale: currentScale,
      currentOffset: currentOffset,
      deltaY: 25,
      anchor: anchor,
      isPrecise: false
    )

    let canvasX = (anchor.x - currentOffset.width) / currentScale
    let canvasY = (anchor.y - currentOffset.height) / currentScale
    let projectedX = canvasX * result.scale + result.offset.width
    let projectedY = canvasY * result.scale + result.offset.height

    #expect(abs(projectedX - anchor.x) < 0.0001)
    #expect(abs(projectedY - anchor.y) < 0.0001)
  }

  @Test func clampedScaleLeavesOffsetUnchanged() {
    // When the new scale is clamped to the same as the current scale, the
    // offset should not drift — otherwise the canvas would jump even though
    // the zoom did nothing.
    let currentOffset = CGSize(width: 100, height: 80)
    let result = CanvasZoomMath.zoom(
      currentScale: CanvasZoomMath.maxScale,
      currentOffset: currentOffset,
      deltaY: 50,
      anchor: CGPoint(x: 300, y: 200),
      isPrecise: false
    )

    #expect(result.offset == currentOffset)
    #expect(result.scale == CanvasZoomMath.maxScale)
  }

  @Test func preciseScrollUsesGentlerSensitivity() {
    let imprecise = CanvasZoomMath.zoom(
      currentScale: 1.0,
      currentOffset: .zero,
      deltaY: 10,
      anchor: .zero,
      isPrecise: false
    )
    let precise = CanvasZoomMath.zoom(
      currentScale: 1.0,
      currentOffset: .zero,
      deltaY: 10,
      anchor: .zero,
      isPrecise: true
    )

    #expect(precise.scale < imprecise.scale)
    #expect(precise.scale > 1.0)
  }
}

struct CanvasViewportMathTests {
  @Test func fitKeepsFullHeightTileCardsInsideRevealViewport() throws {
    let viewport = CGSize(width: 1600, height: 900)
    let bottomReserve: CGFloat = 50
    let leftCard = CGRect(x: 20, y: 20, width: 773, height: 860)
    let rightCard = CGRect(x: 807, y: 20, width: 773, height: 860)
    let bounds = leftCard.union(rightCard)

    let fit = try #require(
      CanvasViewportMath.fit(
        bounds: bounds,
        viewport: viewport,
        bottomReserve: bottomReserve,
        padding: 30
      )
    )

    for card in [leftCard, rightCard] {
      let screenRect = CGRect(
        x: card.minX * fit.scale + fit.offset.width,
        y: card.minY * fit.scale + fit.offset.height,
        width: card.width * fit.scale,
        height: card.height * fit.scale
      )
      let delta = CanvasViewportMath.revealDelta(
        for: screenRect,
        viewport: viewport,
        bottomReserve: bottomReserve,
        margin: 20
      )
      #expect(delta == .zero)
    }
  }

  @Test func fullyVisibleCardInsideMarginDoesNotReveal() {
    let delta = CanvasViewportMath.revealDelta(
      for: CGRect(x: 10, y: 10, width: 100, height: 100),
      viewport: CGSize(width: 200, height: 200),
      bottomReserve: 0,
      margin: 20
    )

    #expect(delta == .zero)
  }

  @Test func partiallyOffscreenCardRevealsWithMargin() {
    let delta = CanvasViewportMath.revealDelta(
      for: CGRect(x: -5, y: 50, width: 100, height: 100),
      viewport: CGSize(width: 200, height: 200),
      bottomReserve: 0,
      margin: 20
    )

    #expect(delta == CGSize(width: 25, height: 0))
  }

  // MARK: - reveal

  private let revealViewport = CGSize(width: 1000, height: 640)

  @Test func revealIsANoOpForAVisibleCard() {
    let result = CanvasViewportMath.reveal(
      cardFrame: CGRect(x: 100, y: 100, width: 300, height: 200),
      in: CanvasViewportMath.Viewport(size: revealViewport, scale: 1, offset: .zero, bottomReserve: 40),
      margin: 20,
      allowsZoomOut: true
    )

    #expect(result == nil)
  }

  @Test func revealPansToTheCardsFarEdge() throws {
    let card = CGRect(x: 1200, y: 100, width: 300, height: 200)
    let result = try #require(
      CanvasViewportMath.reveal(
        cardFrame: card,
        in: CanvasViewportMath.Viewport(size: revealViewport, scale: 1, offset: .zero, bottomReserve: 40),
        margin: 20,
        allowsZoomOut: true
      ))

    #expect(result.scale == 1)
    #expect(card.maxX + result.offset.width == revealViewport.width - 20)
    #expect(result.offset.height == 0)
  }

  @Test func revealZoomsOutToFitAnOversizedCard() throws {
    let card = CGRect(x: 2000, y: 2000, width: 1920, height: 1160)
    let result = try #require(
      CanvasViewportMath.reveal(
        cardFrame: card,
        in: CanvasViewportMath.Viewport(size: revealViewport, scale: 1, offset: .zero, bottomReserve: 40),
        margin: 20,
        allowsZoomOut: true
      ))

    // Visible area is 960 × 560 after margins and the bottom reserve; height binds.
    #expect(abs(result.scale - 560.0 / 1160.0) < 0.0001)
    #expect(abs(card.midX * result.scale + result.offset.width - revealViewport.width / 2) < 0.001)
    #expect(abs(card.midY * result.scale + result.offset.height - (revealViewport.height - 40) / 2) < 0.001)
  }

  @Test func revealKeepsTheZoomWhenZoomingOutIsNotAllowed() throws {
    let card = CGRect(x: 2000, y: 2000, width: 1920, height: 1160)
    let result = try #require(
      CanvasViewportMath.reveal(
        cardFrame: card,
        in: CanvasViewportMath.Viewport(size: revealViewport, scale: 1, offset: .zero, bottomReserve: 40),
        margin: 20,
        allowsZoomOut: false
      ))

    #expect(result.scale == 1)
  }

  @Test func revealIsANoOpForAVisibleCardInsideTheMargin() {
    // Fully on screen but closer than the margin to the left edge.
    let result = CanvasViewportMath.reveal(
      cardFrame: CGRect(x: 5, y: 100, width: 300, height: 200),
      in: CanvasViewportMath.Viewport(size: revealViewport, scale: 1, offset: .zero, bottomReserve: 40),
      margin: 20,
      allowsZoomOut: true
    )

    #expect(result == nil)
  }

  @Test func revealWithoutZoomShowsTheTopLeftOfAnOversizedCard() throws {
    let card = CGRect(x: 2000, y: 2000, width: 1920, height: 1160)
    let result = try #require(
      CanvasViewportMath.reveal(
        cardFrame: card,
        in: CanvasViewportMath.Viewport(size: revealViewport, scale: 1, offset: .zero, bottomReserve: 40),
        margin: 20,
        allowsZoomOut: false
      ))

    #expect(card.minX + result.offset.width == 20)
    #expect(card.minY + result.offset.height == 20)
  }

  @Test func revealKeepsTheTitleBarVisibleWhenEvenTheMinimumScaleIsTooLarge() throws {
    let card = CGRect(x: 0, y: 0, width: 400, height: 9000)
    let result = try #require(
      CanvasViewportMath.reveal(
        cardFrame: card,
        in: CanvasViewportMath.Viewport(
          size: revealViewport, scale: 1, offset: CGSize(width: 0, height: -5000), bottomReserve: 40),
        margin: 20,
        allowsZoomOut: true
      ))

    #expect(result.scale == CanvasZoomMath.minScale)
    #expect(card.minY * result.scale + result.offset.height == 20)
  }
}
