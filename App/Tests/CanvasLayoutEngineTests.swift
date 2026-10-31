import CoreGraphics
import Foundation
import Testing

@testable import Prowl

struct CanvasLayoutEngineTests {
  private let metrics = CanvasLayoutMetrics.standard
  private let defaultSize = CGSize(width: 800, height: 550)
  private let viewport = CGSize(width: 1600, height: 1000)

  private func input(keys: [String], sizes: [String: CGSize] = [:]) -> CanvasLayoutEngine.Input {
    CanvasLayoutEngine.Input(keys: keys, cardSizes: sizes, viewport: viewport, defaultCardSize: defaultSize)
  }

  @Test(arguments: CanvasLayoutKind.allCases)
  func emptyKeysProduceNoLayouts(kind: CanvasLayoutKind) {
    #expect(CanvasLayoutEngine.layouts(for: kind, input: input(keys: [])).isEmpty)
  }

  @Test(arguments: [CanvasLayoutKind.arrange, .tile])
  func viewportShapedLayoutsWaitForAMeasuredViewport(kind: CanvasLayoutKind) {
    var input = input(keys: ["a", "b"])
    input.viewport = .zero
    #expect(CanvasLayoutEngine.layouts(for: kind, input: input).isEmpty)
  }

  @Test func organizeIgnoresTheViewport() {
    var input = input(keys: ["a", "b"])
    input.viewport = .zero
    #expect(CanvasLayoutEngine.layouts(for: .organize, input: input).count == 2)
  }

  @Test(arguments: CanvasLayoutKind.allCases)
  func everyKindLaysOutEveryCardWithoutOverlap(kind: CanvasLayoutKind) {
    let keys = (0..<7).map { "card-\($0)" }
    let layouts = CanvasLayoutEngine.layouts(for: kind, input: input(keys: keys))

    #expect(Set(layouts.keys) == Set(keys))
    let frames = keys.compactMap { layouts[$0]?.frame(titleBarHeight: metrics.titleBarHeight) }
    for (index, frame) in frames.enumerated() {
      for other in frames[(index + 1)...] {
        #expect(!frame.intersects(other))
      }
    }
  }

  @Test func organizeUsesTheDefaultSizeInABalancedGrid() {
    let keys = ["a", "b", "c", "d", "e"]
    let sizes = ["a": CGSize(width: 1200, height: 900)]
    let layouts = CanvasLayoutEngine.layouts(for: .organize, input: input(keys: keys, sizes: sizes))

    let grid = CanvasGridLayout(spacing: metrics.cardSpacing, titleBarHeight: metrics.titleBarHeight)
    #expect(layouts == grid.layout(keys: keys, cardSize: defaultSize))
    #expect(layouts.values.allSatisfy { $0.size == defaultSize })
  }

  @Test func arrangePreservesCurrentSizesAndDefaultsTheRest() {
    let custom = CGSize(width: 1200, height: 900)
    let layouts = CanvasLayoutEngine.layouts(
      for: .arrange,
      input: input(keys: ["a", "b"], sizes: ["a": custom])
    )

    #expect(layouts["a"]?.size == custom)
    #expect(layouts["b"]?.size == defaultSize)
  }

  @Test func arrangeKeepsMixedSizesApart() {
    let keys = (0..<6).map { "card-\($0)" }
    let sizes: [String: CGSize] = [
      "card-0": CGSize(width: 1800, height: 300),
      "card-1": CGSize(width: 400, height: 1200),
      "card-2": CGSize(width: 900, height: 900),
      "card-3": CGSize(width: 300, height: 200),
      "card-4": CGSize(width: 1400, height: 700),
    ]
    let layouts = CanvasLayoutEngine.layouts(for: .arrange, input: input(keys: keys, sizes: sizes))

    let frames = keys.compactMap { layouts[$0]?.frame(titleBarHeight: metrics.titleBarHeight) }
    #expect(frames.count == keys.count)
    for (index, frame) in frames.enumerated() {
      for other in frames[(index + 1)...] {
        #expect(!frame.intersects(other))
      }
    }
    for (key, size) in sizes {
      #expect(layouts[key]?.size == size)
    }
  }

  @Test func tileScalesItsFrameUpForManyCards() {
    let keys = (0..<16).map { "card-\($0)" }
    let layouts = CanvasLayoutEngine.layouts(for: .tile, input: input(keys: keys))

    // 16 cards in a 1600×1000 viewport would be far below the comfortable
    // size (60% of the default card), so the tile frame grows past the viewport.
    let bounds = layouts.values.reduce(CGRect.null) { $0.union($1.frame(titleBarHeight: metrics.titleBarHeight)) }
    #expect(bounds.width > viewport.width)
    #expect(
      layouts.values.allSatisfy {
        $0.size.width >= defaultSize.width * metrics.tileComfortableFraction - metrics.tileCardSpacing * 2
      })
  }

  @Test func tileFillsTheViewportFrame() {
    let layouts = CanvasLayoutEngine.layouts(for: .tile, input: input(keys: ["a", "b"]))

    let bounds = layouts.values.reduce(CGRect.null) { $0.union($1.frame(titleBarHeight: metrics.titleBarHeight)) }
    let spacing = metrics.tileCardSpacing
    #expect(abs(bounds.minX - spacing) < 0.001)
    #expect(abs(bounds.minY - spacing) < 0.001)
    #expect(abs(bounds.maxX - (viewport.width - spacing)) < 0.001)
    #expect(abs(bounds.maxY - (viewport.height - spacing)) < 0.001)
  }

  @Test func gridColumnsAreTheCeilingOfTheSquareRoot() {
    let columns = [1, 2, 3, 4, 5, 9, 10].map(CanvasGridLayout.columns(for:))
    #expect(columns == [1, 2, 2, 2, 3, 3, 4])
    #expect(CanvasGridLayout.columns(for: 0) == 1)
  }

  @Test func gridFillsRowByRow() {
    let grid = CanvasGridLayout(spacing: 20, titleBarHeight: 28)
    let size = CGSize(width: 100, height: 72)

    #expect(grid.position(index: 0, columns: 2, cardSize: size) == CGPoint(x: 70, y: 70))
    #expect(grid.position(index: 1, columns: 2, cardSize: size) == CGPoint(x: 190, y: 70))
    #expect(grid.position(index: 2, columns: 2, cardSize: size) == CGPoint(x: 70, y: 190))
  }

  @Test func frameIncludesTheTitleBarAboveTheTerminal() {
    let layout = CanvasCardLayout(position: CGPoint(x: 100, y: 100), size: CGSize(width: 200, height: 72))
    #expect(layout.frame(titleBarHeight: 28) == CGRect(x: 0, y: 50, width: 200, height: 100))
  }

  @Test func layoutKindsMapToDistinctPersistedShortcutIDs() {
    #expect(CanvasLayoutKind.arrange.commandID == "arrange_canvas_cards")
    #expect(CanvasLayoutKind.organize.commandID == "organize_canvas_cards")
    #expect(CanvasLayoutKind.tile.commandID == "tile_canvas_cards")
    for kind in CanvasLayoutKind.allCases {
      #expect(AppShortcuts.defaultShortcut(for: kind.commandID) == kind.defaultShortcut)
    }
  }

  @Test func defaultLayoutSettingMapsToItsLayoutKind() {
    #expect(CanvasDefaultLayout.uniform.layoutKind == .arrange)
    #expect(CanvasDefaultLayout.tile.layoutKind == .tile)
  }
}
