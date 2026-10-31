import Foundation

enum DetectedAgent: String, CaseIterable, Equatable, Identifiable, Sendable {
  // swiftlint:disable:next identifier_name
  case pi
  case omp
  case claude
  case codex
  case gemini
  case cursor = "cursor-agent"
  case cline
  case opencode
  case copilot
  case kimi
  case droid
  case devin
  case amp
  case qoder = "qodercli"
  case qwen
  case grok
  case antigravity
  case trae

  var id: String { rawValue }

  nonisolated var displayName: String {
    switch self {
    case .cursor:
      return "cursor"
    default:
      return rawValue
    }
  }

  nonisolated var iconLookupToken: String {
    switch self {
    case .claude:
      return "claude"
    case .copilot:
      return "copilot"
    case .cursor:
      return "cursor"
    default:
      return rawValue
    }
  }

  /// Whether an Idle screen verdict must keep arriving for a confirmed window before it
  /// may replace a Working one (`AgentStateMachine.confirmedIdleWindow`). A screen-only
  /// agent's live region is repainted on the terminal's own clock, so a single frame can
  /// land mid-repaint — traecli 0.209.1 redraws as slowly as once a second while a turn
  /// streams, and its running footer is the only mark that separates Working from Idle
  /// (the composer's status row reads the same in both). Publishing that frame flips the
  /// pane Working → Idle → Working within one poll, and, on an unviewed pane, earns a
  /// spurious Done badge. The confirmation is time-based, not a count of observations:
  /// a repaint gap yields several Idle frames, and repeated reads of one frame — an
  /// `agents read` polls outside the detection cadence — arrive back to back. Scoped per
  /// agent: agents whose Working evidence is corroborated by a log provider or a
  /// program-status report do not need the confirmation.
  nonisolated var requiresConfirmedIdleScreen: Bool {
    switch self {
    case .trae:
      return true
    default:
      return false
    }
  }
}
