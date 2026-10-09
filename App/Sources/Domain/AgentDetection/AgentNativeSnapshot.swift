import Foundation

/// Current process-scoped state, not a trusted completion receipt or a log turn edge.
nonisolated struct AgentNativeSnapshot: Equatable, Sendable {
  let sessionID: String
  let state: AgentRawState
  let statusUpdatedAt: TimeInterval
  /// Work the runtime still runs after its turn, such as a background shell. It keeps
  /// readiness waits closed without making the agent look busy.
  var hasBackgroundWork = false
}
