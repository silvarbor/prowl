import Foundation
import Testing

@testable import supacode

/// Composition tests for the detection pipeline.
///
/// `ScreenHeuristicsTests` proves `screen -> AgentRawState`, and
/// `PaneAgentStateTests` proves `AgentRawState -> AgentDisplayState`, but each
/// stage is driven by a hand-built input of its own type, so nothing verifies
/// that a real screen reaches a reported status. These tests close that seam:
/// they start from a captured screen, run the real classifier and the real
/// stabilizer, and assert what the sidebar and `prowl agents` would report.
@MainActor
struct AgentDetectionPipelineTests {
  private let start = Date(timeIntervalSince1970: 100)

  private struct Reported {
    let raw: AgentRawState
    let display: AgentDisplayState
    let isBusy: Bool
  }

  /// Runs a captured screen through classification and stabilization exactly as
  /// the detection loop does, starting from an idle pane.
  private func reportedState(
    screen: String,
    agent: DetectedAgent = .claude
  ) -> Reported {
    var lastWorkingAt: Date?
    let raw = agent.detectState(in: screen)
    let stabilized = stabilizeAgentState(
      agent: agent,
      previous: .idle,
      raw: raw,
      now: start,
      lastWorkingAt: &lastWorkingAt
    )
    let pane = PaneAgentState(detectedAgent: agent, state: stabilized)
    return Reported(raw: raw, display: pane.displayState, isBusy: pane.isBusy)
  }

  @Test func longRunningTurnIsReportedBusyEndToEnd() {
    // Claude Code 2.1.220. Before the elapsed-segment fix this screen classified
    // as .idle, so the pane reported finished while the turn was still running.
    let screen = """
      ⏺ Update(docs/production-prune.md)
        ⎿  Updated docs/production-prune.md with 12 additions

      ● Actioning… (28m 34s · ↓ 47.7k tokens)
      ─────────
      ❯
      ─────────
        ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents
      """

    let result = reportedState(screen: screen)
    #expect(result.raw == .working)
    #expect(result.display == .working)
    #expect(result.isBusy)
  }

  @Test func liveBackgroundAgentsAreReportedBusyEndToEnd() {
    // Claude Code 2.1.220, main turn finished while background agents run. Before
    // the switcher-row fix this classified as .idle and the pane reported done.
    let screen = """
      ⏺ Holding the push until the evidence auditor returns.

      ✻ Waiting for 2 background agents to finish
      ─────────
      ❯
      ─────────
        [Opus 5 (1M context)] | ############--------  60% | $86.94
        🟢
        ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents

        ⏺ main
        ◯ Explore  Probe C long                     1m 6s · ↓ 28.6k tokens
        ◯ spec-tree:test-evidence-aud…  Re-audit    4m 29s · ↓ 178.9k tokens
      """

    let result = reportedState(screen: screen)
    #expect(result.raw == .working)
    #expect(result.display == .working)
    #expect(result.isBusy)
  }

  @Test func finishedPaneIsReportedIdleEndToEnd() {
    // Negative control: every background agent finished, so the switcher block is
    // gone. The pipeline must not hold the pane busy.
    let screen = """
      ⏺ All three agents returned.

      ─────────
      ❯
      ─────────
        [Opus 5 (1M context)] | --------------------  0% | $98.35
        🟢
        ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents
      """

    let result = reportedState(screen: screen)
    #expect(result.raw == .idle)
    #expect(result.display == .idle)
    #expect(!result.isBusy)
  }

  @Test func blockedPromptSurvivesTheWorkingHold() {
    // A pane that was working and then blocks must report blocked immediately —
    // the 3s working-hold applies to idle, not to a live permission prompt.
    let screen = """
      Do you want to proceed?
      ❯ 1. Yes
        2. No
      Esc to cancel · Tab to amend
      """

    var lastWorkingAt: Date? = start
    let raw = DetectedAgent.claude.detectState(in: screen)
    let stabilized = stabilizeAgentState(
      agent: .claude,
      previous: .working,
      raw: raw,
      now: start.addingTimeInterval(0.5),
      lastWorkingAt: &lastWorkingAt
    )
    let pane = PaneAgentState(detectedAgent: .claude, state: stabilized)

    #expect(raw == .blocked)
    #expect(pane.displayState == .blocked)
    #expect(pane.isBusy)
  }

  @Test func workingHoldKeepsALongTurnBusyAcrossARefreshGap() {
    // Between screen polls Claude can repaint with no status row at all. The
    // pipeline must keep reporting busy through that gap rather than flickering
    // to done — this is the composition of the classifier's .idle with the
    // stabilizer's hold, which neither suite exercises on its own.
    var lastWorkingAt: Date?

    let live = """
      ● Running gates and merge lifecycle… (2m 28s · ↓ 13.2k tokens)
      ─────────
      ❯
      ─────────
      """
    let working = stabilizeAgentState(
      agent: .claude,
      previous: .idle,
      raw: DetectedAgent.claude.detectState(in: live),
      now: start,
      lastWorkingAt: &lastWorkingAt
    )
    #expect(working == .working)

    let repaintGap = """
      ─────────
      ❯
      ─────────
      """
    let held = stabilizeAgentState(
      agent: .claude,
      previous: working,
      raw: DetectedAgent.claude.detectState(in: repaintGap),
      now: start.addingTimeInterval(2.0),
      lastWorkingAt: &lastWorkingAt
    )
    #expect(held == .working)
  }
}
