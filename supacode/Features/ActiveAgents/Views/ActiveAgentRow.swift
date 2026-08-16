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
/// Frame selection stays a pure function of wall-clock time, and the animation
/// is started with a matching `timeOffset`, so every spinner on screen shows
/// the same glyph as before.
struct BaguaWorkingIndicator: View {
  static let frames = ["☰", "☱", "☲", "☳", "☴", "☵", "☶", "☷"]
  static let frameDuration = 0.12
  static let size = CGSize(width: 20, height: 18)
  static let pointSize: CGFloat = 17

  var color: Color = .orange

  var body: some View {
    BaguaIndicatorLayerView(color: color)
      .frame(width: Self.size.width, height: Self.size.height)
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

  static func frame(at date: Date) -> String {
    frames[frameIndex(at: date)]
  }

  static func frameIndex(at date: Date) -> Int {
    frameIndex(atTick: Int(date.timeIntervalSinceReferenceDate / frameDuration))
  }

  static func frameIndex(atTick tick: Int) -> Int {
    let cycleIndex = ((tick % cycleLength) + cycleLength) % cycleLength
    return cycleIndex < frames.count ? cycleIndex : cycleLength - cycleIndex
  }

  /// How far into the current cycle wall-clock time sits, used to start the
  /// layer animation in phase with every other spinner.
  static func cycleOffset(at date: Date) -> TimeInterval {
    let elapsed = date.timeIntervalSinceReferenceDate
    return elapsed.truncatingRemainder(dividingBy: cycleDuration)
  }
}

private struct BaguaIndicatorLayerView: NSViewRepresentable {
  let color: Color

  func makeNSView(context _: Context) -> BaguaIndicatorNSView {
    BaguaIndicatorNSView(color: NSColor(color))
  }

  func updateNSView(_ nsView: BaguaIndicatorNSView, context _: Context) {
    nsView.color = NSColor(color)
  }
}

private final class BaguaIndicatorNSView: NSView {
  private static let animationKey = "bagua.frames"

  var color: NSColor {
    didSet {
      guard color != oldValue else {
        return
      }
      restartAnimation()
    }
  }

  private let glyphLayer = CALayer()

  init(color: NSColor) {
    self.color = color
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
    animation.calculationMode = .discrete
    animation.duration = BaguaWorkingIndicator.cycleDuration
    animation.repeatCount = .infinity
    animation.isRemovedOnCompletion = false
    animation.timeOffset = BaguaWorkingIndicator.cycleOffset(at: Date())
    glyphLayer.contents = images[0]
    glyphLayer.removeAnimation(forKey: Self.animationKey)
    glyphLayer.add(animation, forKey: Self.animationKey)
  }

  private func glyphImage(_ glyph: String, scale: CGFloat) -> CGImage? {
    let size = BaguaWorkingIndicator.size
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
      .font: NSFont.monospacedSystemFont(ofSize: BaguaWorkingIndicator.pointSize, weight: .bold),
      .foregroundColor: color,
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
