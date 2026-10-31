import CoreGraphics
import Foundation

/// Geometry constants shared by every Canvas layout and by the card chrome.
struct CanvasLayoutMetrics: Equatable, Sendable {
  /// Height of a card's title bar. A card's `CanvasCardLayout.size` excludes it.
  var titleBarHeight: CGFloat = 28
  /// Gap between cards for Arrange, Organize, and new-card placement.
  var cardSpacing: CGFloat = 20
  /// Tighter gap for the Tile layout. It lives in the scaled-up tile frame, so
  /// the on-screen gap shrinks further as more cards are tiled (gap × scale).
  var tileCardSpacing: CGFloat = 12
  /// Tile scales its frame up once cards would shrink below this fraction of
  /// the default card size, so each card keeps a readable terminal surface.
  var tileComfortableFraction: CGFloat = 0.6

  static let standard = CanvasLayoutMetrics()
}

extension CanvasCardLayout {
  /// The card's visual frame in canvas space: its terminal area plus the title
  /// bar above it, centered on `position`.
  func frame(titleBarHeight: CGFloat) -> CGRect {
    let visualHeight = height + titleBarHeight
    return CGRect(
      x: positionX - width / 2,
      y: positionY - visualHeight / 2,
      width: width,
      height: visualHeight
    )
  }
}

/// Computes card layouts for a `CanvasLayoutKind`. Pure (it reads no view
/// state), so every layout is testable without a view.
enum CanvasLayoutEngine {
  struct Input: Equatable {
    /// Cards to lay out, in canvas order (worktree order, then tab order).
    var keys: [String]
    /// Each card's current terminal size. Cards without an entry use
    /// `defaultCardSize`.
    var cardSizes: [String: CGSize]
    var viewport: CGSize
    var defaultCardSize: CGSize
  }

  /// Layouts for every key in `input`, or an empty dictionary when there is
  /// nothing to lay out: no keys, or — for the viewport-shaped Arrange and
  /// Tile — a viewport that has not been measured yet. Organize ignores the
  /// viewport. Callers treat an empty result as a no-op.
  static func layouts(
    for kind: CanvasLayoutKind,
    input: Input,
    metrics: CanvasLayoutMetrics = .standard
  ) -> [String: CanvasCardLayout] {
    guard !input.keys.isEmpty else { return [:] }
    let hasViewport = input.viewport.width > 0 && input.viewport.height > 0

    switch kind {
    case .arrange:
      guard hasViewport else { return [:] }
      let cards = input.keys.map { key in
        CanvasCardPacker.CardInfo(key: key, size: input.cardSizes[key] ?? input.defaultCardSize)
      }
      let packer = CanvasCardPacker(spacing: metrics.cardSpacing, titleBarHeight: metrics.titleBarHeight)
      return packer.pack(cards: cards, targetRatio: input.viewport.width / input.viewport.height).layouts

    case .organize:
      let grid = CanvasGridLayout(spacing: metrics.cardSpacing, titleBarHeight: metrics.titleBarHeight)
      return grid.layout(keys: input.keys, cardSize: input.defaultCardSize)

    case .tile:
      guard hasViewport else { return [:] }
      let comfortableSize = CGSize(
        width: input.defaultCardSize.width * metrics.tileComfortableFraction,
        height: input.defaultCardSize.height * metrics.tileComfortableFraction
      )
      let tiler = CanvasTileLayout(spacing: metrics.tileCardSpacing, titleBarHeight: metrics.titleBarHeight)
      return tiler.layout(keys: input.keys, viewport: input.viewport, comfortableSize: comfortableSize)
    }
  }
}

// MARK: - Grid Layout

/// Uniform-size cards in a balanced grid of `ceil(√N)` columns, filled row by
/// row. The canvas is infinite, so the grid ignores the viewport; fit-to-view
/// scales it afterwards.
struct CanvasGridLayout {
  var spacing: CGFloat
  var titleBarHeight: CGFloat

  static func columns(for count: Int) -> Int {
    max(1, Int(ceil(sqrt(Double(count)))))
  }

  /// Center of the cell at `index` in a grid of `columns` columns.
  func position(index: Int, columns: Int, cardSize: CGSize) -> CGPoint {
    let cardWidth = cardSize.width
    let cardHeight = cardSize.height + titleBarHeight
    let row = index / columns
    let col = index % columns
    return CGPoint(
      x: spacing + (cardWidth + spacing) * CGFloat(col) + cardWidth / 2,
      y: spacing + (cardHeight + spacing) * CGFloat(row) + cardHeight / 2
    )
  }

  func layout(keys: [String], cardSize: CGSize) -> [String: CanvasCardLayout] {
    let columns = Self.columns(for: keys.count)
    var layouts: [String: CanvasCardLayout] = [:]
    for (index, key) in keys.enumerated() {
      layouts[key] = CanvasCardLayout(
        position: position(index: index, columns: columns, cardSize: cardSize),
        size: cardSize
      )
    }
    return layouts
  }
}
