import AppKit
import SwiftUI
import Testing

@testable import Prowl

@MainActor
struct ShelfSpineMotionTests {
  @Test func bookMotionInterpolatesWhileSelectionChromeChangesImmediately() {
    let fixture = SpineMotionFixture()
    defer { fixture.close() }

    for moved in [true, false] {
      fixture.move(moved)
      #expect(fixture.positions.contains { $0 > 1 && $0 < 159 })
      #expect(abs((fixture.positions.last ?? -1) - (moved ? 160 : 0)) < 0.5)
      #expect(!fixture.chromeSamples.isEmpty)
      #expect(fixture.chromeSamples.allSatisfy { $0 == 0 || $0 == 1 })
      #expect(fixture.chromeSamples.last == (moved ? 1 : 0))
      #expect(fixture.mounts == 1)
    }
  }

  @Test func descendantHoverCanStartItsOwnAnimation() {
    let fixture = SpineMotionFixture()
    defer { fixture.close() }

    fixture.hover()
    #expect(fixture.hoverSamples.contains { $0 > 0 && $0 < 1 })
    #expect(fixture.hoverSamples.last == 1)
  }
}

@MainActor
private final class SpineMotionFixture {
  @MainActor @Observable final class Model {
    var moved = false
    var hovered = false
  }

  final class Recorder {
    var samples: [CGFloat] = []
    var view: NSView?
    var mounts = 0
  }

  private struct ProgressProbe: AnimatableModifier {
    var progress: CGFloat
    let recorder: Recorder

    var animatableData: CGFloat {
      get { progress }
      set { progress = newValue }
    }

    func body(content: Content) -> some View {
      recorder.samples.append(progress)
      return content.opacity(0.5 + 0.5 * progress)
    }
  }

  private struct FrameProbe: NSViewRepresentable {
    let recorder: Recorder

    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      recorder.view = view
      recorder.mounts += 1
      return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
  }

  private struct Host: View {
    let model: Model
    let chrome: Recorder
    let hover: Recorder
    let frame: Recorder

    var body: some View {
      HStack(spacing: 0) {
        Color.clear.frame(width: model.moved ? 160 : 0)
        Color.primary
          .modifier(ProgressProbe(progress: model.moved ? 1 : 0, recorder: chrome))
          .overlay {
            Color.secondary
              .modifier(ProgressProbe(progress: model.hovered ? 1 : 0, recorder: hover))
              .animation(.linear(duration: 0.12), value: model.hovered)
          }
          .background { FrameProbe(recorder: frame) }
          .frame(width: 34, height: 120)
          .modifier(ShelfSpineMotion())
        Spacer(minLength: 0)
      }
      .frame(width: 320, height: 120)
      .animation(.linear(duration: 0.2), value: model.moved)
    }
  }

  private let model = Model()
  private let chrome = Recorder()
  private let hoverRecorder = Recorder()
  private let frame = Recorder()
  private let window: NSWindow
  private let host: NSHostingView<Host>
  private(set) var positions: [CGFloat] = []
  var chromeSamples: [CGFloat] { chrome.samples }
  var hoverSamples: [CGFloat] { hoverRecorder.samples }
  var mounts: Int { frame.mounts }

  init() {
    window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 320, height: 120),
      styleMask: [.borderless], backing: .buffered, defer: false
    )
    host = NSHostingView(
      rootView: Host(model: model, chrome: chrome, hover: hoverRecorder, frame: frame))
    window.contentView = host
    window.orderBack(nil)
    render()
  }

  func close() {
    window.orderOut(nil)
  }

  func move(_ moved: Bool) {
    positions = []
    chrome.samples = []
    model.moved = moved
    render()
  }

  func hover() {
    hoverRecorder.samples = []
    model.hovered = true
    render()
  }

  private func render() {
    // AppKit presentation frames use the real run loop, not an injected TestClock.
    let deadline = Date().addingTimeInterval(0.35)
    while Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()
      if let view = frame.view {
        positions.append(view.convert(view.bounds, to: nil).minX)
      }
    }
  }
}
