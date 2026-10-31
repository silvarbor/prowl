import ComposableArchitecture
import Foundation

/// The question a pane's first `ssh` raises (docs-ai 082, L0 item 12): may Prowl open its own
/// connection to that host to detect agents.
struct RemoteAgentConsentPrompt: Equatable {
  let worktreeID: Worktree.ID
  let surfaceID: UUID
  /// The destination as the user typed it (`mini`, `dev@box`); Prowl has not resolved it.
  let destination: String
}

enum RemoteAgentConsentChoice: Equatable {
  case turnOn
  /// Asks again after a relaunch.
  case notNow
  case turnOff
}

extension AppFeature {
  func reduceRemoteAgentConsentNeeded(
    worktreeID: Worktree.ID, surfaceID: UUID, destination: String, state: inout State
  ) -> Effect<Action> {
    // The terminal layer asks before the settings reach it at launch; a stored answer wins.
    guard state.settings.remoteAgentDetection == .undecided, !state.isRemoteAgentConsentDeferred else {
      return .none
    }
    state.remoteAgentConsentPrompt = RemoteAgentConsentPrompt(
      worktreeID: worktreeID, surfaceID: surfaceID, destination: destination)
    return .none
  }

  func reduceRemoteAgentConsent(_ choice: RemoteAgentConsentChoice, state: inout State) -> Effect<Action> {
    state.remoteAgentConsentPrompt = nil
    switch choice {
    case .turnOn:
      return .send(.settings(.setRemoteAgentDetection(.enabled)))
    case .notNow:
      state.isRemoteAgentConsentDeferred = true
      return .none
    case .turnOff:
      return .send(.settings(.setRemoteAgentDetection(.disabled)))
    }
  }
}
