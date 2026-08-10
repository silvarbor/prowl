struct AgentScreenSnapshot: Equatable, Sendable {
  let text: String
  let lines: [String]

  nonisolated init(canonicalText: String) {
    assert(
      canonicalText == agentDetectionRecentText(canonicalText),
      "AgentScreenSnapshot requires canonical detector-tail text."
    )
    self.text = canonicalText
    self.lines = canonicalText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  }
}
