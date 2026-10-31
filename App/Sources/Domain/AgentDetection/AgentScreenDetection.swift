nonisolated struct AgentScreenRuleID: Equatable, Hashable, Sendable {
  let rawValue: String

  nonisolated init(_ rawValue: String) {
    precondition(!rawValue.isEmpty, "Agent screen rule IDs must not be empty.")
    self.rawValue = rawValue
  }
}

nonisolated enum AgentScreenDetectionReason: Equatable, Sendable {
  case matched(AgentScreenRuleID)
  case noRuleMatched
  case legacyDetector
  /// The screen read as settled, but the pane's own out-of-band mark said a turn
  /// is still running (traecli's braille title spinner); the corroboration wins.
  /// Only a screen for `.trae` produces it today.
  case titleSpinner
  /// Not a classification: the screen was not consulted because an eligible OSC 7501
  /// root record holds authority (docs-ai 079). Only a decision carries it; a scan
  /// never produces it.
  case delegated

  nonisolated var identifier: String {
    switch self {
    case .matched(let ruleID):
      return ruleID.rawValue
    case .noRuleMatched:
      return "fallback.noRuleMatched"
    case .legacyDetector:
      return "legacy.detector"
    case .titleSpinner:
      return "screen.titleSpinner"
    case .delegated:
      return "screen.delegated"
    }
  }
}

nonisolated struct AgentScreenDetection: Equatable, Sendable {
  let state: AgentRawState
  let reason: AgentScreenDetectionReason
}
