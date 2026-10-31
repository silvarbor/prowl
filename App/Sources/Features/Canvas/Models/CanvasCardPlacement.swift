import CoreGraphics
import Foundation

/// Finds a free spot for each new card among the cards already on the canvas,
/// without moving any of them.
///
/// A new card goes next to an anchor card — normally the focused one — trying
/// its right side, then below it. When both are taken, the card goes to the
/// free slot (right of or below any card) nearest the anchor. Candidates are
/// checked against the real frames of every card, so the result never
/// overlaps, whatever layout produced the existing cards.
///
/// Cards in one call are placed one after another, each new card becoming the
/// anchor of the next. Placing three cards at once therefore gives the same
/// result as placing them one at a time while focus follows each new card,
/// which keeps placement independent of how creations were batched.
struct CanvasCardPlacement {
  var spacing: CGFloat
  var titleBarHeight: CGFloat

  struct NewCard: Equatable {
    var key: String
    /// Terminal size, excluding the title bar (as in `CanvasCardLayout`).
    var size: CGSize
  }

  /// Layouts for `newCards`, keyed by card key. `existing` holds the cards
  /// already placed; `anchorKey` names the card to place next to. Without a
  /// usable anchor, cards continue after the last card in reading order.
  func place(
    _ newCards: [NewCard],
    existing: [String: CanvasCardLayout],
    anchorKey: String?
  ) -> [String: CanvasCardLayout] {
    // Sort for a deterministic candidate order; dictionary order is not stable.
    var occupied = existing.sorted { $0.key < $1.key }.map { $0.value.frame(titleBarHeight: titleBarHeight) }
    var anchor = anchorKey.flatMap { existing[$0] }?.frame(titleBarHeight: titleBarHeight)
    var placed: [String: CanvasCardLayout] = [:]

    for card in newCards {
      let visualSize = CGSize(width: card.size.width, height: card.size.height + titleBarHeight)
      let frame = freeFrame(of: visualSize, occupied: occupied, anchor: anchor ?? lastInReadingOrder(occupied))
      placed[card.key] = CanvasCardLayout(position: CGPoint(x: frame.midX, y: frame.midY), size: card.size)
      occupied.append(frame)
      anchor = frame
    }
    return placed
  }

  private func freeFrame(of size: CGSize, occupied: [CGRect], anchor: CGRect?) -> CGRect {
    guard let anchor else {
      return CGRect(origin: CGPoint(x: spacing, y: spacing), size: size)
    }

    for origin in [rightOf(anchor), below(anchor)] {
      let candidate = CGRect(origin: origin, size: size)
      if isFree(candidate, among: occupied) { return candidate }
    }

    let anchorCenter = CGPoint(x: anchor.midX, y: anchor.midY)
    let best =
      occupied
      .flatMap { [rightOf($0), below($0)] }
      .map { CGRect(origin: $0, size: size) }
      .filter { isFree($0, among: occupied) }
      .min { lhs, rhs in
        let lhsDistance = distanceSquared(from: anchorCenter, to: lhs)
        let rhsDistance = distanceSquared(from: anchorCenter, to: rhs)
        if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
        if lhs.minY != rhs.minY { return lhs.minY < rhs.minY }
        return lhs.minX < rhs.minX
      }
    if let best { return best }

    // Unreachable in practice: the slot right of the rightmost card is always
    // free. Kept so placement can never fail.
    let bounds = occupied.reduce(CGRect.null) { $0.union($1) }
    return CGRect(origin: CGPoint(x: bounds.maxX + spacing, y: bounds.minY), size: size)
  }

  private func rightOf(_ rect: CGRect) -> CGPoint {
    CGPoint(x: rect.maxX + spacing, y: rect.minY)
  }

  private func below(_ rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX, y: rect.maxY + spacing)
  }

  /// Free when the candidate keeps at least (almost) `spacing` from every card.
  /// The half-point tolerance lets a candidate sit exactly `spacing` away from
  /// the card it was derived from despite floating-point rounding.
  private func isFree(_ candidate: CGRect, among occupied: [CGRect]) -> Bool {
    let padded = candidate.insetBy(dx: -(spacing - 0.5), dy: -(spacing - 0.5))
    return !occupied.contains { $0.intersection(padded).width > 0 && $0.intersection(padded).height > 0 }
  }

  /// The card that ends the reading order: the lowest row, then the rightmost
  /// card in it.
  private func lastInReadingOrder(_ frames: [CGRect]) -> CGRect? {
    frames.max { lhs, rhs in
      if lhs.minY != rhs.minY { return lhs.minY < rhs.minY }
      return lhs.minX < rhs.minX
    }
  }

  private func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
    let deltaX = rect.midX - point.x
    let deltaY = rect.midY - point.y
    return deltaX * deltaX + deltaY * deltaY
  }
}
