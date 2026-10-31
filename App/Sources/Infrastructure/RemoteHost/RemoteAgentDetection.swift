import Foundation

/// The user's answer about SSH-transparent detection (docs-ai 082, L0 item 12). The side
/// channel reaches hosts the user named and the host can log it, so it starts only after
/// the user agrees.
nonisolated enum RemoteAgentDetectionConsent: String, Codable, Equatable, Sendable {
  /// No answer yet: no side channel; the first `ssh` asks.
  case undecided
  case enabled
  case disabled

  /// What the Settings switch shows: on unless the user turned it off.
  var showsEnabled: Bool { self != .disabled }
}

/// The switch for SSH-transparent detection (docs-ai 082, L0). The stored consent decides,
/// unless `PROWL_REMOTE_AGENT_DETECTION` is set: `0` turns it off, any other value on, and
/// neither asks.
nonisolated enum RemoteAgentDetection {
  static let environmentKey = "PROWL_REMOTE_AGENT_DETECTION"

  enum Mode: Equatable, Sendable {
    case enabled
    case disabled
    /// Detection waits for the user's answer: Prowl opens no connection and asks.
    case awaitingConsent
  }

  static func mode(environment: [String: String], consent: RemoteAgentDetectionConsent) -> Mode {
    if let value = environment[environmentKey] { return value == "0" ? .disabled : .enabled }
    switch consent {
    case .undecided: return .awaitingConsent
    case .enabled: return .enabled
    case .disabled: return .disabled
    }
  }
}
