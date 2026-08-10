import Foundation

enum ClaudeScreenProfile {
  enum RuleID {
    nonisolated static let viewer = AgentScreenRuleID("claude.viewer")
    nonisolated static let blockedPrompt = AgentScreenRuleID("claude.blockedPrompt")
    nonisolated static let spinner = AgentScreenRuleID("claude.spinner")
    nonisolated static let elapsedStatus = AgentScreenRuleID("claude.elapsedStatus")
    nonisolated static let backgroundWork = AgentScreenRuleID("claude.backgroundWork")
    nonisolated static let idleComposer = AgentScreenRuleID("claude.idleComposer")

    // Keep exhaustive so prefix and uniqueness tests cover every emitted ID.
    nonisolated static let all = [
      viewer,
      blockedPrompt,
      spinner,
      elapsedStatus,
      backgroundWork,
      idleComposer,
    ]
  }

  nonisolated static func detect(in snapshot: AgentScreenSnapshot) -> AgentScreenDetection {
    let regions = ClaudeScreenRegions(snapshot: snapshot)

    if hasViewerChrome(regions) {
      return AgentScreenDetection(state: .unknown, reason: .matched(RuleID.viewer))
    }
    if hasBlockedPrompt(regions) {
      return AgentScreenDetection(state: .blocked, reason: .matched(RuleID.blockedPrompt))
    }
    if hasSpinnerActivity(regions.liveStatus) {
      return AgentScreenDetection(state: .working, reason: .matched(RuleID.spinner))
    }
    if hasElapsedStatusLine(regions.liveStatus) {
      return AgentScreenDetection(state: .working, reason: .matched(RuleID.elapsedStatus))
    }
    if regions.belowPromptLower.contains("agents done") {
      return AgentScreenDetection(state: .working, reason: .matched(RuleID.backgroundWork))
    }
    if regions.hasIdleComposer {
      return AgentScreenDetection(state: .idle, reason: .matched(RuleID.idleComposer))
    }
    return AgentScreenDetection(state: .idle, reason: .noRuleMatched)
  }

  nonisolated private static func hasViewerChrome(_ regions: ClaudeScreenRegions) -> Bool {
    if regions.bottomChromeLines.contains(where: { line in
      line.contains("⌕ Search…") || line.lowercased().contains("ctrl+r to toggle")
    }) {
      return true
    }

    let lower = regions.bottomViewerLines.joined(separator: "\n").lowercased()
    return lower.contains("⌕ filter history")
      && lower.contains("↑/↓ to nav")
      && lower.contains("enter to use")
      && lower.contains("esc to cancel")
      && lower.contains("ctrl+s to scope")
  }

  nonisolated private static func hasBlockedPrompt(_ regions: ClaudeScreenRegions) -> Bool {
    let lower = regions.currentInteractionLower
    if lower.contains("do you want to proceed?")
      || lower.contains("would you like to proceed?")
      || lower.contains("waiting for permission")
      || lower.contains("do you want to allow this connection?")
      || lower.contains("tab to amend")
      || lower.contains("ctrl+e to explain")
      || lower.contains("chat about this")
      || lower.contains("review your answers")
      || lower.contains("skip interview and plan immediately")
    {
      return true
    }
    return hasConfirmationPrompt(lower)
      || (hasSelectionPrompt(regions.currentInteractionLines)
        && hasYesNoChoice(regions.currentInteractionLines))
  }

  nonisolated private static func hasSelectionPrompt(_ lines: [String]) -> Bool {
    lines.contains(where: isClaudeNumberedSelectionLine)
  }

  nonisolated private static func hasYesNoChoice(_ lines: [String]) -> Bool {
    lines.contains { line in
      let line = line.trimmingCharacters(in: .whitespaces)
      let option =
        line.hasPrefix("❯")
        ? String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        : line
      let trimmed = option.lowercased()
      return trimmed == "yes"
        || trimmed == "no"
        || trimmed.hasPrefix("1. yes")
        || trimmed.hasPrefix("2. no")
        || trimmed.hasPrefix("yes, and ")
        || trimmed.hasPrefix("no, and tell claude")
    }
  }

  nonisolated private static func hasElapsedStatusLine(_ content: String) -> Bool {
    content.split(separator: "\n").contains { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.first == "●" else { return false }
      let body = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
      guard let open = body.firstIndex(of: "(") else { return false }

      let label = body[..<open].trimmingCharacters(in: .whitespaces)
      guard label.hasSuffix("…"), label.split(whereSeparator: { $0.isWhitespace }).count == 1 else {
        return false
      }

      let elapsed = body[body.index(after: open)...]
      let digits = elapsed.prefix(while: \.isNumber)
      guard !digits.isEmpty else { return false }
      let afterDigits = elapsed.dropFirst(digits.count)
      guard let unit = afterDigits.first, unit == "s" || unit == "m" || unit == "h" else {
        return false
      }
      let trailing = afterDigits.dropFirst()
      return trailing.hasPrefix(")") || trailing.hasPrefix(" · ")
    }
  }
}

private struct ClaudeScreenRegions: Sendable {
  let currentInteractionLines: [String]
  let currentInteractionLower: String
  let liveStatus: String
  let belowPromptLower: String
  let bottomChromeLines: [String]
  let bottomViewerLines: [String]
  let hasIdleComposer: Bool

  nonisolated init(snapshot: AgentScreenSnapshot) {
    let lines = snapshot.lines
    let promptIndex = lines.lastIndex(where: { $0.contains("❯") })
    let currentInteractionLines = Self.currentInteractionLines(
      screenLines: lines,
      promptIndex: promptIndex
    )
    self.currentInteractionLines = currentInteractionLines
    self.currentInteractionLower = currentInteractionLines.joined(separator: "\n").lowercased()
    self.liveStatus = agentDetectionRecentLines(
      Self.contentAbovePrompt(screenLines: lines, promptIndex: promptIndex),
      limit: 3
    )
    self.belowPromptLower = Self.contentBelowPrompt(screenLines: lines, promptIndex: promptIndex)
      .lowercased()

    let nonEmptyLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    self.bottomChromeLines = Array(nonEmptyLines.suffix(3))
    self.bottomViewerLines = Array(nonEmptyLines.suffix(5))
    self.hasIdleComposer = Self.hasIdleComposer(screenLines: lines, promptIndex: promptIndex)
  }

  nonisolated private static func currentInteractionLines(
    screenLines: [String],
    promptIndex: Int?
  ) -> [String] {
    guard let promptIndex else {
      return Array(screenLines.suffix(18))
    }
    guard isClaudeNumberedSelectionLine(screenLines[promptIndex]) else {
      return []
    }
    let lowerBound = max(screenLines.startIndex, promptIndex - 10)
    return Array(screenLines[lowerBound..<screenLines.endIndex])
  }

  nonisolated private static func contentAbovePrompt(
    screenLines: [String],
    promptIndex: Int?
  ) -> String {
    guard let promptIndex else {
      return screenLines.joined(separator: "\n")
    }
    let borderIndex = screenLines[..<promptIndex].lastIndex(where: isBoxBorderLine)
    return screenLines[..<(borderIndex ?? promptIndex)].joined(separator: "\n")
  }

  nonisolated private static func contentBelowPrompt(
    screenLines: [String],
    promptIndex: Int?
  ) -> String {
    guard let promptIndex else { return "" }
    let startIndex = screenLines.index(after: promptIndex)
    guard startIndex < screenLines.endIndex else { return "" }
    return screenLines[startIndex...].joined(separator: "\n")
  }

  nonisolated private static func hasIdleComposer(
    screenLines: [String],
    promptIndex: Int?
  ) -> Bool {
    guard let promptIndex, promptIndex > screenLines.startIndex else { return false }
    let nextIndex = screenLines.index(after: promptIndex)
    guard nextIndex < screenLines.endIndex else { return false }
    return isBoxBorderLine(screenLines[screenLines.index(before: promptIndex)])
      && isBoxBorderLine(screenLines[nextIndex])
  }
}

nonisolated private func isClaudeNumberedSelectionLine(_ line: String) -> Bool {
  let trimmed = line.trimmingCharacters(in: .whitespaces)
  guard trimmed.first == "❯" else { return false }
  let option = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
  return isNumberedChoice(option)
}

nonisolated private func isBoxBorderLine(_ line: String) -> Bool {
  let trimmed = line.trimmingCharacters(in: .whitespaces)
  guard trimmed.count >= 3 else { return false }
  return trimmed.allSatisfy { $0 == "─" || $0 == "-" }
}
