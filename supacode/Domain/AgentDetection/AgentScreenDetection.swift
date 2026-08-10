struct AgentScreenRuleID: Equatable, Hashable, Sendable {
  let rawValue: String

  nonisolated init(_ rawValue: String) {
    precondition(!rawValue.isEmpty, "Agent screen rule IDs must not be empty.")
    self.rawValue = rawValue
  }
}

enum AgentScreenDetectionReason: Equatable, Sendable {
  case matched(AgentScreenRuleID)
  case noRuleMatched
  case legacyDetector

  nonisolated var identifier: String {
    switch self {
    case .matched(let ruleID):
      return ruleID.rawValue
    case .noRuleMatched:
      return "fallback.noRuleMatched"
    case .legacyDetector:
      return "legacy.detector"
    }
  }
}

struct AgentScreenDetection: Equatable, Sendable {
  let state: AgentRawState
  let reason: AgentScreenDetectionReason
}
