import Foundation

/// How Canvas keeps its cards laid out, remembered across launches.
///
/// - `automatic(kind)`: the card set and the viewport determine the layout.
///   Adding or closing a card, or resizing the window, re-applies `kind`; the
///   viewport refits if it showed the whole board. Choosing a layout (toolbar,
///   shortcut, palette, CLI) enters this mode and refits.
/// - `freeform`: the user arranged cards by hand. Cards stay where they are;
///   a new card goes to a free spot next to the focused card. Dragging or
///   resizing a card enters this mode.
enum CanvasLayoutMode: Equatable, Sendable {
  case automatic(CanvasLayoutKind)
  case freeform

  var automaticKind: CanvasLayoutKind? {
    if case .automatic(let kind) = self { kind } else { nil }
  }

  /// What a change in the set of cards should do in this mode. A relayout
  /// cannot run while a card is expanded or being resized, or before the
  /// viewport is measured; it then waits.
  func cardSetChangeAction(canRelayoutNow: Bool) -> CanvasCardSetChangeAction {
    guard let kind = automaticKind else { return .placeNewCards }
    return canRelayoutNow ? .relayout(kind) : .placeNewCardsAndRelayoutLater
  }
}

enum CanvasCardSetChangeAction: Equatable {
  /// Re-apply the automatic layout to every card and fit the viewport.
  case relayout(CanvasLayoutKind)
  /// Keep existing cards in place and give new cards free spots.
  case placeNewCards
  /// Place new cards now; re-apply the automatic layout once possible.
  case placeNewCardsAndRelayoutLater
}

extension CanvasLayoutMode: Codable {
  private static let freeformValue = "freeform"

  init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    if value == Self.freeformValue {
      self = .freeform
    } else if let kind = CanvasLayoutKind(rawValue: value) {
      self = .automatic(kind)
    } else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown Canvas layout mode \(value)")
      )
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(automaticKind?.rawValue ?? Self.freeformValue)
  }
}
