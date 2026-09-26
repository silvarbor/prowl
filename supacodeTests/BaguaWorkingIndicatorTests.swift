import Foundation
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

extension Double {
  fileprivate func isApproximatelyEqual(to other: Double, tolerance: Double = 1e-9) -> Bool {
    abs(self - other) <= tolerance
  }
}
