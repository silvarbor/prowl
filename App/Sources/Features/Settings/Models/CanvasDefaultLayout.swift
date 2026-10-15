import Foundation

/// The automatic layout a fresh Canvas starts in (see `CanvasLayoutMode`).
/// `uniform` opens every card at one comfortable size, packed to fit (Arrange,
/// the historical behavior); `tile` resizes cards to tile and fill the viewport,
/// which adapts better as the card count grows. Once the user picks a layout or
/// moves a card, Canvas remembers that instead.
enum CanvasDefaultLayout: String, CaseIterable, Identifiable, Codable, Sendable {
  case uniform
  case tile

  var id: String { rawValue }

  /// The automatic layout this setting applies on first entry. `uniform` keeps
  /// its historical meaning: the size-preserving pack, which on a fresh set of
  /// default-size cards gives same-size cards packed to fit.
  var layoutKind: CanvasLayoutKind {
    switch self {
    case .uniform: .arrange
    case .tile: .tile
    }
  }

  var title: String {
    switch self {
    case .uniform:
      return String(localized: "Uniform")
    case .tile:
      return String(localized: "Tile")
    }
  }

  /// One-line description shown under the Settings picker, following the
  /// current selection.
  var settingsDescription: String {
    switch self {
    case .uniform:
      return String(localized: "Cards open at the same size.")
    case .tile:
      return String(localized: "Cards resize to fill the screen, smaller as you add more.")
    }
  }
}
