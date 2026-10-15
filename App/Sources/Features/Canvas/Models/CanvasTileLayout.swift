import CoreGraphics
import Foundation

/// Resizes cards to tile and fill the entire viewport, like an automatic window
/// manager. Cards are laid into a balanced grid whose orientation follows the
/// viewport: wide viewports spread cards into rows (left-to-right), tall
/// viewports stack them into columns (top-to-bottom). Each line independently
/// fills its full extent, so a 2-card row gets ½-width cards while a 3-card row
/// gets ⅓-width cards — maximizing the area every card uses.
struct CanvasTileLayout {
  var spacing: CGFloat
  var titleBarHeight: CGFloat

  /// Distribute `count` cards across `floor(√count)` lines, packing the extra
  /// cards into the later lines. e.g. 5 → `[2, 3]`, 7 → `[3, 4]`, 9 → `[3, 3, 3]`.
  static func lineCounts(for count: Int) -> [Int] {
    guard count > 0 else { return [] }
    let lines = max(1, Int(Double(count).squareRoot().rounded(.down)))
    let base = count / lines
    let remainder = count % lines
    // Earlier lines get `base`; the last `remainder` lines get one extra.
    return (0..<lines).map { index in index < lines - remainder ? base : base + 1 }
  }

  /// Resize and position `keys` to tile and fill `viewport`. Returns an empty
  /// dictionary when there is nothing to lay out (the caller treats this as a
  /// no-op, matching `CanvasCardPacker.pack`).
  ///
  /// The layout is built in a `viewport × zoom` frame and laid out edge-to-edge,
  /// so `fitToView` reproduces a scale of `1 / zoom`. `zoom` stays `1` (native
  /// scale, identical to single-card framing) while the tiled cards are already
  /// at least `comfortableSize`; once the grid shrinks cards below that, `zoom`
  /// grows so each card keeps a comfortable terminal surface (more rows/columns
  /// at smaller on-screen text) instead of a few oversized glyphs. The constant
  /// `spacing` lives in this scaled frame, so the on-screen gap (`spacing × scale`)
  /// tightens automatically as more cards are tiled.
  func layout(keys: [String], viewport: CGSize, comfortableSize: CGSize) -> [String: CanvasCardLayout] {
    guard !keys.isEmpty, viewport.width > 0, viewport.height > 0 else { return [:] }

    let counts = Self.lineCounts(for: keys.count)
    let landscape = viewport.width >= viewport.height
    let lineCount = CGFloat(counts.count)
    let maxPerLine = CGFloat(counts.max() ?? 1)

    // Enlarge the frame so the smallest card surface reaches `comfortableSize`;
    // `fitToView` later scales the whole frame back down to the viewport.
    let zoom: CGFloat
    if landscape {
      // Lines are rows: a card's width ≈ frameWidth / maxPerLine, height ≈ frameHeight / lineCount.
      zoom = max(
        1,
        max(comfortableSize.width * maxPerLine / viewport.width, comfortableSize.height * lineCount / viewport.height)
      )
    } else {
      // Lines are columns: width ≈ frameWidth / lineCount, height ≈ frameHeight / maxPerLine.
      zoom = max(
        1,
        max(comfortableSize.width * lineCount / viewport.width, comfortableSize.height * maxPerLine / viewport.height)
      )
    }
    let frame = CGSize(width: viewport.width * zoom, height: viewport.height * zoom)

    var layouts: [String: CanvasCardLayout] = [:]
    var cursor = 0

    if landscape {
      // Lines are rows: split the height evenly, fill each row's width.
      let rows = counts.count
      let rowVisualHeight = (frame.height - CGFloat(rows + 1) * spacing) / CGFloat(rows)
      var originY = spacing
      for cardsInRow in counts {
        let cardWidth = (frame.width - CGFloat(cardsInRow + 1) * spacing) / CGFloat(cardsInRow)
        var originX = spacing
        for _ in 0..<cardsInRow {
          layouts[keys[cursor]] = CanvasCardLayout(
            position: CGPoint(x: originX + cardWidth / 2, y: originY + rowVisualHeight / 2),
            size: CGSize(width: cardWidth, height: rowVisualHeight - titleBarHeight)
          )
          originX += cardWidth + spacing
          cursor += 1
        }
        originY += rowVisualHeight + spacing
      }
    } else {
      // Lines are columns: split the width evenly, fill each column's height.
      let cols = counts.count
      let colVisualWidth = (frame.width - CGFloat(cols + 1) * spacing) / CGFloat(cols)
      var originX = spacing
      for cardsInColumn in counts {
        let cardVisualHeight = (frame.height - CGFloat(cardsInColumn + 1) * spacing) / CGFloat(cardsInColumn)
        var originY = spacing
        for _ in 0..<cardsInColumn {
          layouts[keys[cursor]] = CanvasCardLayout(
            position: CGPoint(x: originX + colVisualWidth / 2, y: originY + cardVisualHeight / 2),
            size: CGSize(width: colVisualWidth, height: cardVisualHeight - titleBarHeight)
          )
          originY += cardVisualHeight + spacing
          cursor += 1
        }
        originX += colVisualWidth + spacing
      }
    }

    return layouts
  }
}
