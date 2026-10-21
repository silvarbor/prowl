import SwiftUI

/// The side channel of the focused pane's `ssh`, for the toolbar status (docs-ai 082, L0
/// item 12): Prowl has a connection to the host, or tried to open one.
struct RemoteChannelToolbarStatus: Equatable {
  let host: String
  /// Why Prowl does not read the pane's agents; nil while it does.
  let issue: RemotePaneCorrelation?

  /// nil when the pane's `ssh` has no side channel: no `ssh`, an ended one, or one outside the
  /// grammar (Prowl never connects for it; the pane badge says why).
  init?(_ indicator: RemotePaneIndicator?) {
    guard case .connected(let host, _, let issue) = indicator else { return nil }
    if case .unsupported = issue { return nil }
    self.host = host
    self.issue = issue
  }
}

/// Asks whether Prowl may open its own connection. Its panel opens at once and stays until the
/// user answers or clicks elsewhere; the capsule stays until the user answers. Neither takes
/// keyboard focus: the user can be typing a password or a code in the pane.
struct RemoteAgentConsentStatusButton: View {
  let prompt: RemoteAgentConsentPrompt
  let onChoice: (RemoteAgentConsentChoice) -> Void
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "network.badge.shield.half.filled")
          .symbolRenderingMode(.multicolor)
          .foregroundStyle(.orange)
          .accessibilityHidden(true)
        Text("Detect agents on \(prompt.destination)?")
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .buttonStyle(.plain)
    .font(.caption)
    .contentShape(.rect)
    .help("Choose whether Prowl may connect to the host of this SSH session to detect agents.")
    .accessibilityLabel(Text("Detect agents on \(prompt.destination)? Prowl waits for your answer."))
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      RemoteAgentConsentPanel(destination: prompt.destination) { choice in
        isPresented = false
        onChoice(choice)
      }
    }
    .task(id: prompt) {
      // Opened after the toolbar item is in the window, so the panel has an anchor.
      await Task.yield()
      isPresented = true
    }
  }
}

private struct RemoteAgentConsentPanel: View {
  let destination: String
  let onChoice: (RemoteAgentConsentChoice) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label {
        Text("Detect agents in SSH sessions?")
          .font(.headline)
      } icon: {
        Image(systemName: "network.badge.shield.half.filled")
          .symbolRenderingMode(.multicolor)
          .accessibilityHidden(true)
      }
      Text(
        """
        Prowl can show the agents that run on \(destination), with their state. To find them, \
        Prowl opens its own SSH connection to the host, next to your session, and runs a \
        read-only check every few seconds. It installs nothing on the host, and your session \
        does not change.
        """
      )
      .fixedSize(horizontal: false, vertical: true)
      Text("The host can log this connection. Prowl does not connect until you choose.")
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      // No default button and no keyboard focus: a Return typed for the pane's password
      // prompt must never answer here.
      HStack {
        Button("Turn Off") { onChoice(.turnOff) }
          .focusable(false)
          .help("Never detect agents in SSH sessions. You can turn it on in Settings › Agents › Display.")
        Button("Not Now") { onChoice(.notNow) }
          .focusable(false)
          .help("Ask again after Prowl restarts.")
        Spacer(minLength: 12)
        Button("Turn On") { onChoice(.turnOn) }
          .focusable(false)
          .buttonStyle(.borderedProminent)
          .help("Detect agents in SSH sessions. You can turn it off in Settings › Agents › Display.")
      }
    }
    .font(.callout)
    .padding(16)
    .frame(width: 380)
  }
}

/// The focused pane's side channel: the host and its health, with a panel on hover that tells
/// what the extra connection does.
struct RemoteChannelStatusButton: View {
  let status: RemoteChannelToolbarStatus
  let onOpenSettings: () -> Void
  @State private var isPresented = false
  @State private var isPinnedOpen = false
  @State private var isHoveringButton = false
  @State private var isHoveringPopover = false
  @State private var closeTask: Task<Void, Never>?

  var body: some View {
    Button {
      isPinnedOpen.toggle()
      updatePresentation()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: status.issue == nil ? "network" : "exclamationmark.triangle.fill")
          .symbolRenderingMode(status.issue == nil ? .monochrome : .multicolor)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        Text(verbatim: status.host)
          .lineLimit(1)
          .truncationMode(.middle)
        Text(status.issue == nil ? "Agent detection on" : "Agents not detected")
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .buttonStyle(.plain)
    .font(.caption)
    .contentShape(.rect)
    .help("Prowl's own SSH connection for agent detection. Hover to see what it does.")
    .accessibilityLabel(accessibilityLabel)
    .onHover { hovering in
      isHoveringButton = hovering
      updatePresentation()
    }
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      RemoteChannelPanel(status: status) {
        isPinnedOpen = false
        isPresented = false
        onOpenSettings()
      }
      .onHover { hovering in
        isHoveringPopover = hovering
        updatePresentation()
      }
      .onDisappear {
        isHoveringPopover = false
        isPinnedOpen = false
      }
    }
    .onDisappear {
      closeTask?.cancel()
    }
  }

  private var accessibilityLabel: Text {
    status.issue == nil
      ? Text("Agent detection connected to \(status.host)")
      : Text("Agent detection for \(status.host): agents are not detected")
  }

  private func updatePresentation() {
    if isPinnedOpen || isHoveringButton || isHoveringPopover {
      closeTask?.cancel()
      isPresented = true
      return
    }
    closeTask?.cancel()
    closeTask = Task { @MainActor in
      try? await ContinuousClock().sleep(for: .milliseconds(150))
      if !Task.isCancelled {
        isPresented = false
      }
    }
  }
}

private struct RemoteChannelPanel: View {
  let status: RemoteChannelToolbarStatus
  let onOpenSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label {
        Text("Agent detection over SSH")
          .font(.headline)
      } icon: {
        Image(systemName: "network")
          .accessibilityHidden(true)
      }
      Text(
        """
        Prowl keeps its own SSH connection to \(status.host), next to your session in this \
        pane. Over it, Prowl runs a read-only check every few seconds to find the agents in \
        this pane and their state. It installs nothing on the host, and your session does not \
        change.
        """
      )
      .fixedSize(horizontal: false, vertical: true)
      Label {
        Text(verbatim: detail)
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: status.issue == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
          .symbolRenderingMode(.multicolor)
          .accessibilityHidden(true)
      }
      .foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button("Agent Settings…", action: onOpenSettings)
          .focusable(false)
          .help("Open Settings › Agents › Display, where you can turn off agent detection in SSH sessions.")
      }
    }
    .font(.callout)
    .padding(16)
    .frame(width: 380)
  }

  private var detail: String {
    guard let issue = status.issue else {
      return String(localized: "Connected. Agents in this pane are detected.")
    }
    return RemoteAgentPresentation.paneIssueExplanation(issue, host: status.host)
  }
}
