import CoreGraphics
import Foundation

struct CanvasCardLayout: Codable, Equatable, Hashable, Sendable {
  var positionX: CGFloat
  var positionY: CGFloat
  var width: CGFloat
  var height: CGFloat

  var position: CGPoint {
    get { CGPoint(x: positionX, y: positionY) }
    set {
      positionX = newValue.x
      positionY = newValue.y
    }
  }

  var size: CGSize {
    get { CGSize(width: width, height: height) }
    set {
      width = newValue.width
      height = newValue.height
    }
  }

  /// Card size used on small screens (≈14" MacBook Pro). On a small viewport
  /// the canvas must zoom out to fit a multi-card grid, which shrinks rendered
  /// text; smaller cards keep the fit-to-view scale — and thus text — larger.
  static let minDefaultSize = CGSize(width: 800, height: 550)
  /// Card size used on large screens (≈27" display and up), where fit-to-view
  /// caps at 1.0 so a larger card simply shows more content at native size.
  static let maxDefaultSize = CGSize(width: 1000, height: 680)
  /// Reference screen widths (logical points, default scaling) mapped to the
  /// interpolation endpoints above.
  static let minDefaultScreenWidth: CGFloat = 1512  // 14" MacBook Pro
  static let maxDefaultScreenWidth: CGFloat = 2560  // 27" / Studio Display

  /// Size new cards adopt when no explicit size is given. Equal to
  /// `maxDefaultSize`, used only for transient fallbacks; creation paths pass
  /// an explicit `adaptiveDefaultSize(forScreenWidth:)` instead.
  static let defaultSize = maxDefaultSize

  /// Linearly interpolate the default card size between `minDefaultSize`
  /// (14"-class screens) and `maxDefaultSize` (27"-class and larger) by screen
  /// width, clamped at both ends.
  static func adaptiveDefaultSize(forScreenWidth screenWidth: CGFloat) -> CGSize {
    let span = maxDefaultScreenWidth - minDefaultScreenWidth
    let fraction = span > 0 ? min(max((screenWidth - minDefaultScreenWidth) / span, 0), 1) : 1
    return CGSize(
      width: minDefaultSize.width + (maxDefaultSize.width - minDefaultSize.width) * fraction,
      height: minDefaultSize.height + (maxDefaultSize.height - minDefaultSize.height) * fraction
    )
  }

  init(position: CGPoint, size: CGSize = Self.defaultSize) {
    self.positionX = position.x
    self.positionY = position.y
    self.width = size.width
    self.height = size.height
  }
}

// MARK: - Layout Store

@MainActor
@Observable
final class CanvasLayoutStore {
  private static let storageKey = "canvasCardLayouts"

  private let defaults: UserDefaults
  private let initiallyLoadedCardKeys: Set<String>

  var cardLayouts: [String: CanvasCardLayout] {
    didSet { save() }
  }

  var zOrder: [String] {
    didSet { save() }
  }

  /// The remembered layout mode; nil until the canvas first lays out cards.
  /// Layouts stored before modes existed load as `freeform`, so upgrading never
  /// rearranges a canvas the user arranged.
  var mode: CanvasLayoutMode? {
    didSet {
      if mode != oldValue { save() }
    }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let stored = Self.load(from: defaults)
    cardLayouts = stored.cardLayouts
    zOrder = stored.zOrder
    mode = stored.mode ?? (stored.cardLayouts.isEmpty ? nil : .freeform)
    initiallyLoadedCardKeys = Set(stored.cardLayouts.keys)
  }

  // No actor-bound cleanup is needed. Avoid inferred isolated deinit, which can
  // hit the TaskLocal invalid-free bug in older system Swift runtimes (swiftlang/swift#85204).
  nonisolated deinit {}

  /// Resolve the layout for entering Canvas with `cardKeys` on screen. A canvas
  /// that never chose a mode starts in `defaultKind`, and so does a freeform
  /// canvas whose cards were all unknown when it loaded (there is nothing left
  /// of the arrangement). A remembered automatic layout always applies: it
  /// does not depend on card positions. Returns the automatic layout to apply,
  /// or nil in freeform.
  func layoutForEntry(cardKeys: [String], defaultKind: CanvasLayoutKind) -> CanvasLayoutKind? {
    guard !cardKeys.isEmpty else { return nil }
    let isFreshCanvas = !cardKeys.contains { initiallyLoadedCardKeys.contains($0) }
    if mode == nil || (mode == .freeform && isFreshCanvas) {
      mode = .automatic(defaultKind)
    }
    return mode?.automaticKind
  }

  /// The mode saved by the last Canvas, without loading a store — for status
  /// reports while Canvas is hidden.
  static func storedMode(defaults: UserDefaults = .standard) -> CanvasLayoutMode? {
    let stored = load(from: defaults)
    return stored.mode ?? (stored.cardLayouts.isEmpty ? nil : .freeform)
  }

  func setCardLayouts(_ layouts: [String: CanvasCardLayout], zOrder newZOrder: [String]? = nil) {
    cardLayouts = layouts
    zOrder = normalizedZOrder(newZOrder ?? zOrder, visibleKeys: Array(layouts.keys))
  }

  /// Store the result of an automatic layout. `layouts` replaces the entries of
  /// the cards it covers; entries for other cards (not on the canvas right now)
  /// are kept. `order` becomes the stacking order of the laid-out cards, above
  /// any card the layout did not cover.
  func applyLayouts(_ layouts: [String: CanvasCardLayout], order: [String]) {
    let merged = cardLayouts.merging(layouts) { _, new in new }
    let laidOut = Set(order)
    let untouched = zOrder.filter { !laidOut.contains($0) && merged[$0] != nil }
    setCardLayouts(merged, zOrder: untouched + order)
  }

  func ensureZOrder(for visibleKeys: [String]) {
    zOrder = normalizedZOrder(zOrder, visibleKeys: visibleKeys)
  }

  func prune(to visibleKeys: Set<String>) {
    cardLayouts = cardLayouts.filter { visibleKeys.contains($0.key) }
    zOrder = zOrder.filter { visibleKeys.contains($0) }
  }

  func moveToFront(_ cardKey: String) {
    guard cardLayouts[cardKey] != nil else { return }
    zOrder.removeAll { $0 == cardKey }
    zOrder.append(cardKey)
  }

  func zIndex(for cardKey: String) -> Double {
    guard let index = zOrder.firstIndex(of: cardKey) else { return 0 }
    return Double(index)
  }

  private static func load(from defaults: UserDefaults) -> CanvasLayoutStoragePayload {
    guard let data = defaults.data(forKey: storageKey) else {
      return CanvasLayoutStoragePayload(cardLayouts: [:], zOrder: [])
    }

    if let payload = try? JSONDecoder().decode(CanvasLayoutStoragePayload.self, from: data) {
      return CanvasLayoutStoragePayload(
        cardLayouts: payload.cardLayouts,
        zOrder: normalizedZOrder(payload.zOrder, visibleKeys: Array(payload.cardLayouts.keys)),
        mode: payload.mode
      )
    }

    if let layouts = try? JSONDecoder().decode([String: CanvasCardLayout].self, from: data) {
      return CanvasLayoutStoragePayload(cardLayouts: layouts, zOrder: Array(layouts.keys).sorted())
    }

    return CanvasLayoutStoragePayload(cardLayouts: [:], zOrder: [])
  }

  private func save() {
    let payload = CanvasLayoutStoragePayload(
      cardLayouts: cardLayouts,
      zOrder: Self.normalizedZOrder(zOrder, visibleKeys: Array(cardLayouts.keys)),
      mode: mode
    )
    if let data = try? JSONEncoder().encode(payload) {
      defaults.set(data, forKey: Self.storageKey)
    }
  }

  private func normalizedZOrder(_ order: [String], visibleKeys: [String]) -> [String] {
    Self.normalizedZOrder(order, visibleKeys: visibleKeys)
  }

  private static func normalizedZOrder(_ order: [String], visibleKeys: [String]) -> [String] {
    let visibleKeySet = Set(visibleKeys)
    var seen: Set<String> = []
    var normalized: [String] = []
    for key in order where visibleKeySet.contains(key) && seen.insert(key).inserted {
      normalized.append(key)
    }
    for key in visibleKeys.sorted() where seen.insert(key).inserted {
      normalized.append(key)
    }
    return normalized
  }
}

private struct CanvasLayoutStoragePayload: Codable, Equatable {
  var cardLayouts: [String: CanvasCardLayout]
  var zOrder: [String]
  var mode: CanvasLayoutMode?

  init(cardLayouts: [String: CanvasCardLayout], zOrder: [String], mode: CanvasLayoutMode? = nil) {
    self.cardLayouts = cardLayouts
    self.zOrder = zOrder
    self.mode = mode
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    cardLayouts = try container.decode([String: CanvasCardLayout].self, forKey: .cardLayouts)
    zOrder = try container.decode([String].self, forKey: .zOrder)
    // A mode written by a newer version must not discard the card layouts.
    mode = try? container.decodeIfPresent(CanvasLayoutMode.self, forKey: .mode)
  }
}
