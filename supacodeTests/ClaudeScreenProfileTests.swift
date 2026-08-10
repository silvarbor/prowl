import Testing

@testable import supacode

struct ClaudeScreenProfileTests {
  @Test func ruleIDsAreUniqueAndRuntimePrefixed() {
    let ruleIDs = ClaudeScreenProfile.RuleID.all

    #expect(Set(ruleIDs).count == ruleIDs.count)
    #expect(ruleIDs.allSatisfy { $0.rawValue.hasPrefix("claude.") })
  }

  @Test func capturedFixturesHaveStableReasonsIncludingViewerFix() throws {
    let expectedReasons: [String: AgentScreenDetectionReason] = [
      "claude/2.1.223/blocked/command-permission.txt": .matched(
        ClaudeScreenProfile.RuleID.blockedPrompt
      ),
      "claude/2.1.223/blocked/workspace-trust.txt": .matched(
        ClaudeScreenProfile.RuleID.blockedPrompt
      ),
      "claude/2.1.223/idle/composer.txt": .matched(ClaudeScreenProfile.RuleID.idleComposer),
      "claude/2.1.223/idle/quoted-permission.txt": .matched(
        ClaudeScreenProfile.RuleID.idleComposer
      ),
      "claude/2.1.223/unknown/676-history-search-viewer.txt": .matched(
        ClaudeScreenProfile.RuleID.viewer
      ),
      "claude/2.1.223/working/backgrounded-subagent.txt": .matched(
        ClaudeScreenProfile.RuleID.spinner
      ),
      "claude/2.1.223/working/foreground-spinner.txt": .matched(
        ClaudeScreenProfile.RuleID.spinner
      ),
      "claude/2.1.223/working/subagent-active.txt": .matched(
        ClaudeScreenProfile.RuleID.spinner
      ),
    ]
    let fixtures = try AgentScreenFixtureCorpus.load().filter { $0.agent == .claude }

    #expect(fixtures.count == expectedReasons.count)
    for fixture in fixtures {
      let detection = DetectedAgent.claude.detectScreen(in: fixture.text)
      #expect(detection.state == fixture.expectedState)
      #expect(detection.reason == expectedReasons[fixture.relativePath])
    }
  }

  @Test func elapsedAndBackgroundWorkHaveDistinctReasons() {
    let elapsed = ClaudeScreenProfile.detect(
      in: AgentScreenSnapshot(
        canonicalText: """
            ● Forging… (10s · thinking with high effort)
            ─────────
            ❯
            ─────────
          """
      )
    )
    #expect(elapsed.state == .working)
    #expect(elapsed.reason == .matched(ClaudeScreenProfile.RuleID.elapsedStatus))

    let background = ClaudeScreenProfile.detect(
      in: AgentScreenSnapshot(
        canonicalText: """
            Task complete.
            ─────────
            ❯
            ─────────
            ◯ scout  Map idle detection  3/5 agents done · 7m 29s
          """
      )
    )
    #expect(background.state == .working)
    #expect(background.reason == .matched(ClaudeScreenProfile.RuleID.backgroundWork))
  }

  @Test func blockerOutranksRetainedSpinner() {
    let detection = ClaudeScreenProfile.detect(
      in: AgentScreenSnapshot(
        canonicalText: """
            ✻ Tempering… (12s · esc to interrupt)
            Do you want to proceed?
            ❯ 1. Yes
              2. No
            Esc to cancel · Tab to amend
          """
      )
    )

    #expect(detection.state == .blocked)
    #expect(detection.reason == .matched(ClaudeScreenProfile.RuleID.blockedPrompt))
  }

  @Test func unstructuredScreenUsesExplicitFallback() {
    let detection = ClaudeScreenProfile.detect(
      in: AgentScreenSnapshot(canonicalText: "screen without live Claude chrome")
    )

    #expect(detection.state == .idle)
    #expect(detection.reason == .noRuleMatched)
  }
}
