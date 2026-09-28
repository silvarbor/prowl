import AppKit
import SwiftUI
import Testing

@testable import supacode

struct BaguaWorkingIndicatorTests {
  @Test func framesUseFullTrigramSequence() {
    #expect(BaguaWorkingIndicator.frames == ["☰", "☱", "☲", "☳", "☴", "☵", "☶", "☷"])
  }

  @Test func frameSelectionLoopsByDuration() {
    let duration = BaguaWorkingIndicator.frameDuration

    #expect(BaguaWorkingIndicator.frame(at: 0) == "☰")
    #expect(BaguaWorkingIndicator.frame(at: duration) == "☱")
    #expect(BaguaWorkingIndicator.frame(at: duration * 7) == "☷")
    #expect(BaguaWorkingIndicator.frame(at: duration * 8) == "☶")
    #expect(BaguaWorkingIndicator.frame(at: duration * 13) == "☱")
    #expect(BaguaWorkingIndicator.frame(at: duration * 14) == "☰")
  }

  @Test func cycleFramesMatchTheClockDrivenSequence() {
    let duration = BaguaWorkingIndicator.frameDuration
    // Sampled mid-frame: `duration * 11` lands on 1.3199999999999998, which
    // truncates into the previous tick, so a boundary sample would compare the
    // keyframe order against a float artifact rather than against the sequence.
    let expected = (0..<BaguaWorkingIndicator.cycleLength).map { tick in
      BaguaWorkingIndicator.frame(at: duration * (Double(tick) + 0.5))
    }

    #expect(BaguaWorkingIndicator.cycleFrames == expected)
    #expect(BaguaWorkingIndicator.cycleFrames.count == 14)
    #expect(BaguaWorkingIndicator.cycleFrames.first == "☰")
    #expect(BaguaWorkingIndicator.cycleFrames.last == "☱")
  }

  @Test func cycleKeyTimesGiveEveryFrameOneFrameDuration() {
    // Discrete keyframes want N + 1 key times from 0 to 1. With N, Core
    // Animation spreads the values over N - 1 intervals and drops the last one.
    let keyTimes = BaguaWorkingIndicator.cycleKeyTimes.map(\.doubleValue)
    let length = BaguaWorkingIndicator.cycleLength
    #expect(keyTimes.count == length + 1)
    #expect(keyTimes.first == 0)
    #expect(keyTimes.last == 1)
    for index in 0..<length {
      let interval = keyTimes[index + 1] - keyTimes[index]
      #expect(abs(interval - 1.0 / Double(length)) < 1e-9)
    }
  }

  @Test func cycleStartAnchorsEveryMountToTheSameCycleBoundary() {
    let duration = BaguaWorkingIndicator.frameDuration
    let cycle = BaguaWorkingIndicator.cycleDuration

    #expect(BaguaWorkingIndicator.cycleStart(containing: 0) == 0)
    #expect(BaguaWorkingIndicator.cycleStart(containing: duration * 3) == 0)
    #expect(
      BaguaWorkingIndicator.cycleStart(containing: cycle * 5 + duration * 3)
        .isApproximatelyEqual(to: cycle * 5)
    )
    // Two mounts inside the same cycle anchor to the same boundary, and a mount a
    // cycle later anchors exactly one cycle later, which is what keeps every
    // spinner on screen showing the same glyph.
    let early = BaguaWorkingIndicator.cycleStart(containing: cycle * 5 + duration * 0.5)
    let late = BaguaWorkingIndicator.cycleStart(containing: cycle * 5 + duration * 13.5)
    let nextCycle = BaguaWorkingIndicator.cycleStart(containing: cycle * 6 + duration * 3)
    #expect(early == late)
    #expect((nextCycle - early).isApproximatelyEqual(to: cycle))
  }
}

/// Mounts real indicator views in a window, the path that installs the layer
/// animation, with media time injected so two mounts land at chosen moments.
@MainActor
struct BaguaIndicatorLayerTests {
  @Test func indicatorsMountedAtDifferentMomentsShowTheSameGlyph() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
      styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    defer { window.close() }

    // The second mount lands 3.37 s later: mid-frame, and not a whole number
    // of cycles, so an animation phased from its own mount time would drift.
    var now: CFTimeInterval = 5_000.05
    let first = BaguaIndicatorNSView(style: .init(color: .orange), mediaTime: { now })
    window.contentView?.addSubview(first)
    now += 3.37
    let second = BaguaIndicatorNSView(style: .init(color: .orange), mediaTime: { now })
    window.contentView?.addSubview(second)

    let animations = try [first, second].map { view in
      try #require(
        view.glyphLayer.animation(forKey: BaguaIndicatorNSView.animationKey) as? CAKeyframeAnimation
      )
    }
    for animation in animations {
      #expect(animation.keyPath == "contents")
      #expect(animation.calculationMode == .discrete)
      #expect(animation.values?.count == BaguaWorkingIndicator.cycleLength)
      #expect(animation.keyTimes == BaguaWorkingIndicator.cycleKeyTimes)
      #expect(animation.duration == BaguaWorkingIndicator.cycleDuration)
      #expect(animation.repeatCount == .infinity)
      #expect(animation.speed == 1)
      #expect(animation.timeOffset == 0)
    }

    // Sample one full cycle after both mounts, mid-frame so no sample sits on
    // a float boundary. Each layer's local time is media time minus its
    // beginTime; the glyph it shows must be the one `frame(at:)` gives for
    // that media time, for both layers alike.
    let duration = BaguaWorkingIndicator.frameDuration
    let firstTick = Int((now / duration).rounded(.up))
    for tick in firstTick..<(firstTick + BaguaWorkingIndicator.cycleLength) {
      let sample = duration * (Double(tick) + 0.5)
      let expected = BaguaWorkingIndicator.frame(at: sample)
      for animation in animations {
        #expect(shownGlyph(of: animation, at: sample) == expected)
      }
    }
  }

  @Test func glyphFollowsDynamicTypeAndMatchesTheTextSpinnerByDefault() throws {
    let standard = try renderedIndicator(dynamicTypeSize: .large)
    #expect(standard.style.pointSize == 17)
    #expect(standard.style.size == CGSize(width: 20, height: 18))

    let larger = try renderedIndicator(dynamicTypeSize: .accessibility3)
    #expect(larger.style.pointSize > standard.style.pointSize)
    #expect(larger.style.size.width > standard.style.size.width)
    #expect(larger.style.size.height > standard.style.size.height)

    // The keyframe images are rendered at the scaled size, not just laid out
    // in a larger frame.
    let standardFrame = try firstKeyframeImage(of: standard)
    let largerFrame = try firstKeyframeImage(of: larger)
    #expect(largerFrame.width > standardFrame.width)
    #expect(largerFrame.height > standardFrame.height)
  }

  /// Hosts the SwiftUI indicator at `dynamicTypeSize` and returns the layer
  /// view SwiftUI created for it.
  private func renderedIndicator(dynamicTypeSize: DynamicTypeSize) throws -> BaguaIndicatorNSView {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
      styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let host = NSHostingView(
      rootView: BaguaWorkingIndicator(color: .orange).environment(\.dynamicTypeSize, dynamicTypeSize)
    )
    host.frame = window.contentLayoutRect
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    return try #require(indicatorView(in: host))
  }

  private func indicatorView(in view: NSView) -> BaguaIndicatorNSView? {
    if let indicator = view as? BaguaIndicatorNSView {
      return indicator
    }
    return view.subviews.lazy.compactMap { indicatorView(in: $0) }.first
  }

  private func firstKeyframeImage(of view: BaguaIndicatorNSView) throws -> CGImage {
    let animation = try #require(
      view.glyphLayer.animation(forKey: BaguaIndicatorNSView.animationKey) as? CAKeyframeAnimation
    )
    // Core Animation hands `contents` values back as untyped objects, so
    // check the Core Foundation type before treating one as an image.
    let first = try #require(animation.values?.first) as AnyObject
    try #require(CFGetTypeID(first) == CGImage.typeID)
    return unsafeDowncast(first, to: CGImage.self)
  }

  /// The glyph a discrete keyframe animation shows at `mediaTime`, read from
  /// the animation's own timing and key times.
  private func shownGlyph(of animation: CAKeyframeAnimation, at mediaTime: CFTimeInterval) -> String? {
    let local = (mediaTime - animation.beginTime) * Double(animation.speed) + animation.timeOffset
    let fraction = local.truncatingRemainder(dividingBy: animation.duration) / animation.duration
    guard let keyTimes = animation.keyTimes?.map(\.doubleValue) else {
      return nil
    }
    guard let index = keyTimes.lastIndex(where: { $0 <= fraction }), index < BaguaWorkingIndicator.cycleLength
    else {
      return nil
    }
    return BaguaWorkingIndicator.cycleFrames[index]
  }
}

extension Double {
  fileprivate func isApproximatelyEqual(to other: Double, tolerance: Double = 1e-9) -> Bool {
    abs(self - other) <= tolerance
  }
}
