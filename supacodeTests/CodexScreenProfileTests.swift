import Testing

@testable import supacode

struct CodexScreenProfileTests {
  @Test func ruleIDsAreUniqueAndRuntimePrefixed() {
    let ruleIDs = CodexScreenProfile.RuleID.all

    #expect(Set(ruleIDs).count == ruleIDs.count)
    #expect(ruleIDs.allSatisfy { $0.rawValue.hasPrefix("codex.") })
  }

  @Test func capturedFixturesHaveStableReasons() throws {
    let expectedReasons: [String: AgentScreenDetectionReason] = [
      "codex/0.146.1/blocked/command-permission.txt": .matched(
        CodexScreenProfile.RuleID.confirmationFooter
      ),
      "codex/0.146.1/blocked/directory-trust.txt": .matched(
        CodexScreenProfile.RuleID.directoryTrust
      ),
      "codex/0.146.1/blocked/hook-review.txt": .matched(CodexScreenProfile.RuleID.hookReview),
      "codex/0.146.1/blocked/sign-in-selection.txt": .matched(CodexScreenProfile.RuleID.signIn),
      "codex/0.146.1/idle/composer.txt": .noRuleMatched,
      "codex/0.146.1/idle/quoted-directory-trust.txt": .noRuleMatched,
      "codex/0.146.1/working/foreground-footer.txt": .matched(
        CodexScreenProfile.RuleID.workingFooter
      ),
    ]
    let fixtures = try AgentScreenFixtureCorpus.load().filter { $0.agent == .codex }

    #expect(fixtures.count == expectedReasons.count)
    for fixture in fixtures {
      let detection = DetectedAgent.codex.detectScreen(in: fixture.text)
      #expect(detection.state == fixture.currentState)
      #expect(detection.reason == expectedReasons[fixture.relativePath])
    }
  }

  @Test func structuredChoicesExplainBlockedWithoutAFooter() {
    let detection = CodexScreenProfile.detect(
      in: AgentScreenSnapshot(
        canonicalText: """
            Would you like to run the following command?
          › 1. Yes, proceed
            2. No, cancel
          """
      )
    )

    #expect(detection.state == .blocked)
    #expect(detection.reason == .matched(CodexScreenProfile.RuleID.confirmationChoices))
  }
}
