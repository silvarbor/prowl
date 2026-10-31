import CoreGraphics
import Foundation
import Testing

@testable import Prowl

@MainActor
struct CanvasViewportAnimatorTests {
  @Test func releasesSynchronouslyWithTaskLocalStorageOutsideATask() async {
    // Swift Testing runs in a Task. A main-queue callback reproduces the synchronous
    // `CanvasView` teardown inside TCA's `withDependencies` TaskLocal scope.
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          withUnsafeCurrentTask { #expect($0 == nil) }

          CanvasViewportAnimatorTestLocal.$marker.withValue(1) {
            var idleAnimator: CanvasViewportAnimator? = CanvasViewportAnimator()
            weak let releasedIdleAnimator = idleAnimator
            idleAnimator = nil
            #expect(releasedIdleAnimator == nil)

            var runningAnimator: CanvasViewportAnimator? = CanvasViewportAnimator()
            weak let releasedRunningAnimator = runningAnimator
            let target = CanvasViewportAnimator.Snapshot(offset: CGSize(width: 100, height: 50), scale: 2)
            runningAnimator?.animate(
              from: CanvasViewportAnimator.Snapshot(offset: .zero, scale: 1),
              to: target
            ) { _ in }
            #expect(runningAnimator?.activeTarget == target)
            runningAnimator = nil
            #expect(releasedRunningAnimator == nil)

            #expect(CanvasViewportAnimatorTestLocal.marker == 1)
          }
          #expect(CanvasViewportAnimatorTestLocal.marker == 0)
          continuation.resume()
        }
      }
    }
  }
}

private enum CanvasViewportAnimatorTestLocal {
  @TaskLocal static var marker = 0
}
