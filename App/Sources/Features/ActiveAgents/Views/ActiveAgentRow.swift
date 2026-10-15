import AppKit
import ComposableArchitecture
import SwiftUI

struct ActiveAgentRow: View {
  let entry: ActiveAgentEntry
  let repositoryName: String
  let subtitle: String
  let repositoryColor: RepositoryColorChoice?
  let isDimmed: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 8) {
      agentIcon
      VStack(alignment: .leading, spacing: 2) {
        title
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      Spacer(minLength: 8)
      statusPill
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .contentShape(.rect)
    .opacity(isDimmed ? 0.7 : 1)
  }

  private var title: some View {
    HStack(alignment: .firstTextBaseline, spacing: 3) {
      Text(entry.displayName)
        .font(.body.weight(.medium))
        .foregroundStyle(.primary)
      Text("·")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
      Text(repositoryName)
        .font(.callout.weight(.medium))
        .foregroundStyle(repositoryColor?.color ?? .secondary)
    }
    .lineLimit(1)
  }

  private var agentIcon: some View {
    Group {
      if let icon = entry.iconSource {
        TabIconImage(rawName: icon.storageString, pointSize: 16)
      } else {
        Image(systemName: "sparkle")
      }
    }
    .frame(width: 20, height: 20)
    .accessibilityHidden(true)
  }

  private var statusPill: some View {
    HStack(spacing: 4) {
      if entry.displayState == .working {
        if reduceMotion {
          statusText
        } else {
          // The layer-backed indicator draws itself, so it takes the status
          // color directly instead of inheriting the pill's foreground style.
          BaguaWorkingIndicator(color: entry.displayState.foregroundStyle)
        }
      } else {
        statusText
      }
    }
    .foregroundStyle(entry.displayState.foregroundStyle)
  }

  private var statusText: some View {
    Text(entry.displayState.label)
      .font(.caption2.weight(.semibold))
      .lineLimit(1)
  }
}

/// Bagua trigram spinner: ping-pongs through the eight trigram glyphs.
///
/// The frames are handed to Core Animation once as a discrete keyframe
/// animation instead of being swapped by a SwiftUI `TimelineView`. Drawing a
/// glyph was never the cost — it profiled at 0.09% of a core — but every
/// timeline tick invalidated the window's view graph, and each render pass
/// pays a full `NSHostingView.layout` plus an accessibility graph
/// revalidation whatever actually changed. At ~8 fps per working agent that
/// overhead measured 15 points of a core with seven agents working, a third of
/// all main-thread work. A layer animation runs on the render server and never
/// touches the graph again.
///
/// Frame selection is a pure function of Core Animation's media time
/// (`CACurrentMediaTime`), and every animation begins at a cycle boundary on
/// that clock, so every spinner on screen shows the same glyph at the same
/// moment however far apart they were mounted. Media time is monotonic, so a
/// change to the system clock cannot split the phase.
struct BaguaWorkingIndicator: View {
  static let frames = ["☰", "☱", "☲", "☳", "☴", "☵", "☶", "☷"]
  static let frameDuration = 0.12
  /// The glyph's point size and frame at the default text size, the same as
  /// the `Text`-based spinner this replaced. Both scale with Dynamic Type,
  /// relative to the caption style of the status label the glyph stands in for.
  static let defaultPointSize: CGFloat = 17
  static let defaultSize = CGSize(width: 20, height: 18)

  var color: Color
  @ScaledMetric(relativeTo: .caption2) private var pointSize = BaguaWorkingIndicator.defaultPointSize
  @ScaledMetric(relativeTo: .caption2) private var width = BaguaWorkingIndicator.defaultSize.width
  @ScaledMetric(relativeTo: .caption2) private var height = BaguaWorkingIndicator.defaultSize.height

  init(color: Color = .orange) {
    self.color = color
  }

  var body: some View {
    BaguaIndicatorLayerView(
      style: BaguaIndicatorNSView.Style(
        color: NSColor(color),
        pointSize: pointSize,
        size: CGSize(width: width, height: height)
      )
    )
    .frame(width: width, height: height)
    .accessibilityHidden(true)
  }

  /// Ticks in one full ping-pong cycle: up through the eight glyphs, then back
  /// down without repeating either end.
  static var cycleLength: Int {
    (frames.count * 2) - 2
  }

  static var cycleDuration: TimeInterval {
    Double(cycleLength) * frameDuration
  }

  /// The glyphs of one cycle in order — the keyframe values of the layer
  /// animation, derived from the same tick math `frame(at:)` uses.
  static var cycleFrames: [String] {
    (0..<cycleLength).map { frames[frameIndex(atTick: $0)] }
  }

  /// The glyph shown at `mediaTime`, in seconds on Core Animation's clock.
  static func frame(at mediaTime: CFTimeInterval) -> String {
    frames[frameIndex(at: mediaTime)]
  }

  static func frameIndex(at mediaTime: CFTimeInterval) -> Int {
    frameIndex(atTick: Int((mediaTime / frameDuration).rounded(.down)))
  }

  static func frameIndex(atTick tick: Int) -> Int {
    let cycleIndex = ((tick % cycleLength) + cycleLength) % cycleLength
    return cycleIndex < frames.count ? cycleIndex : cycleLength - cycleIndex
  }

  /// Key times for a discrete keyframe animation over `cycleFrames`. Core
  /// Animation wants one more entry than there are values, running 0 to 1, so
  /// that each glyph holds for exactly `frameDuration`; without them it spreads
  /// N values over N - 1 intervals and the last glyph never shows.
  static var cycleKeyTimes: [NSNumber] {
    (0...cycleLength).map { NSNumber(value: Double($0) / Double(cycleLength)) }
  }

  /// The start of the cycle containing `mediaTime`. Used as the animation's
  /// `beginTime`, it puts the animation's local time a whole number of cycles
  /// behind media time, so the glyph it shows is `frame(at:)` of the current
  /// media time whenever the animation was added.
  static func cycleStart(containing mediaTime: CFTimeInterval) -> CFTimeInterval {
    (mediaTime / cycleDuration).rounded(.down) * cycleDuration
  }
}

private struct BaguaIndicatorLayerView: NSViewRepresentable {
  let style: BaguaIndicatorNSView.Style

  func makeNSView(context _: Context) -> BaguaIndicatorNSView {
    BaguaIndicatorNSView(style: style)
  }

  func updateNSView(_ nsView: BaguaIndicatorNSView, context _: Context) {
    nsView.style = style
  }
}

final class BaguaIndicatorNSView: NSView {
  static let animationKey = "bagua.frames"

  /// Everything the pre-rendered glyphs depend on. A change re-renders them,
  /// as a backing-scale or appearance change does.
  struct Style: Equatable {
    var color: NSColor
    var pointSize: CGFloat = BaguaWorkingIndicator.defaultPointSize
    var size: CGSize = BaguaWorkingIndicator.defaultSize
  }

  var style: Style {
    didSet {
      guard style != oldValue else {
        return
      }
      restartAnimation()
    }
  }

  let glyphLayer = CALayer()
  /// Core Animation's media time. Injected so tests can mount indicators at
  /// chosen moments.
  private let mediaTime: () -> CFTimeInterval

  init(style: Style, mediaTime: @escaping () -> CFTimeInterval = CACurrentMediaTime) {
    self.style = style
    self.mediaTime = mediaTime
    super.init(frame: .zero)
    wantsLayer = true
    layer?.addSublayer(glyphLayer)
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("BaguaIndicatorNSView is not loaded from a nib")
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    glyphLayer.frame = bounds
    CATransaction.commit()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    restartAnimation()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restartAnimation()
  }

  // Leaving the window strips the animation, so it is rebuilt on the way back
  // in rather than left silently stopped.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil {
      glyphLayer.removeAnimation(forKey: Self.animationKey)
    } else {
      restartAnimation()
    }
  }

  private func restartAnimation() {
    guard let window else {
      return
    }
    let scale = window.backingScaleFactor
    glyphLayer.contentsScale = scale
    let images = BaguaWorkingIndicator.cycleFrames.compactMap { glyphImage($0, scale: scale) }
    guard images.count == BaguaWorkingIndicator.cycleLength else {
      return
    }
    let animation = CAKeyframeAnimation(keyPath: "contents")
    animation.values = images
    animation.keyTimes = BaguaWorkingIndicator.cycleKeyTimes
    animation.calculationMode = .discrete
    animation.duration = BaguaWorkingIndicator.cycleDuration
    animation.repeatCount = .infinity
    animation.isRemovedOnCompletion = false
    // The indicator's ancestors are plain view layers, so its local time is
    // media time, the clock `beginTime` is measured on.
    animation.beginTime = BaguaWorkingIndicator.cycleStart(containing: mediaTime())
    glyphLayer.contents = images[0]
    glyphLayer.removeAnimation(forKey: Self.animationKey)
    glyphLayer.add(animation, forKey: Self.animationKey)
  }

  private func glyphImage(_ glyph: String, scale: CGFloat) -> CGImage? {
    let size = style.size
    let pixelWidth = Int((size.width * scale).rounded())
    let pixelHeight = Int((size.height * scale).rounded())
    guard
      pixelWidth > 0,
      pixelHeight > 0,
      let context = CGContext(
        data: nil,
        width: pixelWidth,
        height: pixelHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }
    context.scaleBy(x: scale, y: scale)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: style.pointSize, weight: .bold),
      .foregroundColor: style.color,
    ]
    let string = NSAttributedString(string: glyph, attributes: attributes)
    let textSize = string.size()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    string.draw(
      at: CGPoint(
        x: ((size.width - textSize.width) / 2).rounded(),
        y: ((size.height - textSize.height) / 2).rounded()
      )
    )
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()
  }
}

extension AgentDisplayState {
  // "Done" and "Blocked" have other meanings elsewhere in the app, so the states use their own keys.
  var label: String {
    switch self {
    case .working:
      return String(localized: "agentState.working", defaultValue: "Working")
    case .blocked:
      return String(localized: "agentState.blocked", defaultValue: "Blocked")
    case .done:
      return String(localized: "agentState.done", defaultValue: "Done")
    case .idle:
      return String(localized: "agentState.idle", defaultValue: "Idle")
    }
  }

  var foregroundStyle: Color {
    switch self {
    case .working:
      return .orange
    case .blocked:
      return .red
    case .done:
      return .blue
    case .idle:
      return .secondary
    }
  }
}

#Preview {
  BaguaWorkingIndicator(color: .orange)
    .frame(width: 100, height: 100)
}
