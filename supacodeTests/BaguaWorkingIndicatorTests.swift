import Foundation
import Testing

@testable import supacode

struct BaguaWorkingIndicatorTests {
  @Test func framesUseFullTrigramSequence() {
    #expect(BaguaWorkingIndicator.frames == ["☰", "☱", "☲", "☳", "☴", "☵", "☶", "☷"])
  }

  @Test func frameSelectionLoopsByDuration() {
    let duration = BaguaWorkingIndicator.frameDuration

    #expect(BaguaWorkingIndicator.frame(at: Date(timeIntervalSinceReferenceDate: 0)) == "☰")
    #expect(BaguaWorkingIndicator.frame(at: Date(timeIntervalSinceReferenceDate: duration)) == "☱")
    #expect(BaguaWorkingIndicator.frame(at: Date(timeIntervalSinceReferenceDate: duration * 7)) == "☷")
    #expect(BaguaWorkingIndicator.frame(at: Date(timeIntervalSinceReferenceDate: duration * 8)) == "☶")
    #expect(BaguaWorkingIndicator.frame(at: Date(timeIntervalSinceReferenceDate: duration * 13)) == "☱")
    #expect(BaguaWorkingIndicator.frame(at: Date(timeIntervalSinceReferenceDate: duration * 14)) == "☰")
  }

  @Test func cycleFramesMatchTheClockDrivenSequence() {
    let duration = BaguaWorkingIndicator.frameDuration
    // Sampled mid-frame: `duration * 11` lands on 1.3199999999999998, which
    // truncates into the previous tick, so a boundary sample would compare the
    // keyframe order against a float artifact rather than against the sequence.
    let expected = (0..<BaguaWorkingIndicator.cycleLength).map { tick in
      BaguaWorkingIndicator.frame(at: Date(timeIntervalSinceReferenceDate: duration * (Double(tick) + 0.5)))
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

  @Test func cycleOffsetTracksPositionWithinTheCycle() {
    let duration = BaguaWorkingIndicator.frameDuration
    let cycle = BaguaWorkingIndicator.cycleDuration

    #expect(BaguaWorkingIndicator.cycleOffset(at: Date(timeIntervalSinceReferenceDate: 0)) == 0)
    #expect(
      BaguaWorkingIndicator.cycleOffset(at: Date(timeIntervalSinceReferenceDate: duration * 3))
        .isApproximatelyEqual(to: duration * 3)
    )
    // A whole cycle later the animation must be back at the same phase, which is
    // what keeps every spinner on screen showing the same glyph.
    #expect(
      BaguaWorkingIndicator.cycleOffset(at: Date(timeIntervalSinceReferenceDate: cycle + duration * 3))
        .isApproximatelyEqual(to: duration * 3)
    )
  }
}

extension Double {
  fileprivate func isApproximatelyEqual(to other: Double, tolerance: Double = 1e-9) -> Bool {
    abs(self - other) <= tolerance
  }
}
