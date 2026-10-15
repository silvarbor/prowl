import Foundation

/// Canvas state reported by every `prowl canvas` action, after the action ran.
public struct CanvasCommandPayload: Codable, Sendable, Equatable {
  public let action: CanvasAction
  /// Whether Canvas is the current view.
  public let showing: Bool
  /// The remembered layout mode: `arrange`, `organize`, `tile`, or `freeform`.
  /// Absent until Canvas has laid out cards once.
  public let layout: String?
  /// Cards on the board: open tabs whose terminal exists.
  public let cardCount: Int

  enum CodingKeys: String, CodingKey {
    case action
    case showing
    case layout
    case cardCount = "card_count"
  }

  public init(action: CanvasAction, showing: Bool, layout: String?, cardCount: Int) {
    self.action = action
    self.showing = showing
    self.layout = layout
    self.cardCount = cardCount
  }
}
