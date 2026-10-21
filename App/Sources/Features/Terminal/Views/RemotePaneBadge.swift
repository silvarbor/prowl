import SwiftUI

/// The host a pane's foreground `ssh` reaches, in the pane's corner (docs-ai 082, L0
/// item 10). It names the host for `RemotePaneIndicator.hostLabelDuration` after it appears
/// or changes, then shrinks to its glyph so that it does not keep the terminal's bottom line
/// (often a tmux status line) covered; the pointer on the glyph shows the host again. When
/// that `ssh` exits, it says so for `RemotePaneIndicator.endedMarkerDuration` after the
/// exit, then goes away; a later mount of the view does not show it again.
struct RemotePaneBadge: View {
  let indicator: RemotePaneIndicator?
  @State private var isEndedMarkerExpired = false
  @State private var isHostLabelExpired = false
  @State private var isHovering = false

  var body: some View {
    Group {
      switch indicator {
      case .connected(let host, _, nil):
        label(Text(verbatim: host), systemImage: "network", isExpanded: isHostShown)
          .onHover { isHovering = $0 }
          .onDisappear { isHovering = false }
          .accessibilityLabel(Text("Connected to \(host)"))
      case .connected(let host, _, let issue?):
        // The reason is the tooltip.
        let explanation = RemoteAgentPresentation.paneIssueExplanation(issue, host: host)
        label(
          Text(verbatim: host), systemImage: "exclamationmark.triangle.fill", multicolor: true,
          isExpanded: isHostShown
        )
        .onHover { isHovering = $0 }
        .onDisappear { isHovering = false }
        .help(explanation)
        .accessibilityLabel(Text("Connected to \(host). Agents are not detected."))
        .accessibilityHint(Text(verbatim: explanation))
      case .ended(let host, _):
        if !isEndedMarkerExpired, indicator?.showsEndedMarker(now: Date()) == true {
          label(Text("Disconnected from \(host)"), systemImage: "network.slash", isExpanded: true)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
      case nil:
        EmptyView()
      }
    }
    .animation(.easeOut(duration: 0.3), value: isEndedMarkerExpired)
    .animation(.easeOut(duration: 0.2), value: isHostShown)
    .task(id: indicator) {
      isEndedMarkerExpired = false
      isHostLabelExpired = false
      let remaining: TimeInterval
      switch indicator {
      case .connected:
        remaining = RemotePaneIndicator.hostLabelDuration
      case .ended(_, let endedAt):
        remaining = endedAt.addingTimeInterval(RemotePaneIndicator.endedMarkerDuration).timeIntervalSinceNow
      case nil:
        return
      }
      // A cancelled sleep means a new indicator, whose own task resets the flags.
      if remaining > 0 {
        do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
      }
      if case .ended = indicator { isEndedMarkerExpired = true } else { isHostLabelExpired = true }
    }
  }

  private var isHostShown: Bool { !isHostLabelExpired || isHovering }

  @ViewBuilder
  private func label(_ text: Text, systemImage: String, multicolor: Bool = false, isExpanded: Bool) -> some View {
    let label = Label {
      text.lineLimit(1).truncationMode(.middle)
    } icon: {
      Image(systemName: systemImage)
        .imageScale(.small)
        .symbolRenderingMode(multicolor ? .multicolor : .monochrome)
        .accessibilityHidden(true)
    }
    Group {
      if isExpanded {
        label.labelStyle(.titleAndIcon)
      } else {
        label.labelStyle(.iconOnly)
      }
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(.regularMaterial, in: .capsule)
    .contentShape(.capsule)
    .padding(6)
  }
}
