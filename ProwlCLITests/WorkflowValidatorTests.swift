import Foundation
import ProwlCLIShared
import XCTest

final class WorkflowValidatorTests: XCTestCase {
  private func minimal(id: String = "demo", steps: String = "", roles: String = "") -> String {
    WorkflowFixtures.minimal(id: id, extraSteps: steps, extraRoles: roles)
  }

  private func errors(_ diagnostics: [WorkflowDiagnostic]) -> [String] {
    diagnostics.filter { $0.severity == .error }.map(\.code)
  }

  private func warnings(_ diagnostics: [WorkflowDiagnostic]) -> [String] {
    diagnostics.filter { $0.severity == .warning }.map(\.code)
  }

  // MARK: - The spec example

  func testSpecExampleIsValidInBundleScope() {
    let diagnostics = WorkflowFixtures.diagnostics(WorkflowFixtures.adversarialReview, scope: .bundle)
    XCTAssertEqual(diagnostics, [])
  }

  func testReservedIDIsRejectedOutsideTheBundle() {
    for scope in [WorkflowScope.user, .repo] {
      let diagnostics = WorkflowFixtures.diagnostics(WorkflowFixtures.adversarialReview, scope: scope)
      XCTAssertEqual(errors(diagnostics), ["reserved_id"], "\(scope)")
    }
  }

  func testUnknownBundleReportsSkillsAsUncheckedAndAKnownBundleChecksThem() {
    let unchecked = WorkflowFixtures.diagnostics(
      WorkflowFixtures.adversarialReview, scope: .bundle, bundledSkillIDs: nil)
    XCTAssertEqual(warnings(unchecked), ["skill_unchecked"])
    XCTAssertEqual(errors(unchecked), [])
    let missing = WorkflowFixtures.diagnostics(
      WorkflowFixtures.adversarialReview, scope: .bundle, bundledSkillIDs: ["prowl-cli"])
    XCTAssertEqual(errors(missing), ["skill_not_found"])
  }

  // MARK: - Ids and roles

  func testSlugsAreEnforcedForIdsRolesStepsOutputsAndInputs() {
    XCTAssertEqual(WorkflowFixtures.codes(minimal(id: "Demo Flow")), ["workflow_id"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal(roles: "  Reviewer:\n    source: pick")), ["role_name_slug"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal(steps: "  - id: Fix It\n    notify: hi")), ["step_id_slug"])
    XCTAssertEqual(
      WorkflowFixtures.codes(
        minimal(steps: "  - id: b\n    message: author\n    text: hi\n    expect: { output: Bad.Name }")),
      ["output_name_slug"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal() + "inputs:\n  Max: { type: integer }\n"), ["input_name_slug"])
  }

  func testAtMostOneCurrentRole() {
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal(roles: "  other:\n    source: current")), ["multiple_current_roles"])
  }

  func testUndefinedRolesAndRoleSources() {
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: "  - id: b\n    message: ghost\n    text: hi")), ["undefined_role"])
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: "  - id: b\n    close: ghost")), ["undefined_role"])
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: "  - id: b\n    close: author")), ["close_role_source"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal(steps: "  - id: b\n    launch: author\n    prompt: go")), ["launch_role_source"])
  }

  func testLaunchOrderingRules() {
    let role = "  r:\n    source: launch"
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal(steps: "  - id: b\n    message: r\n    text: hi", roles: role)),
      ["message_before_launch"])
    let twice = "  - id: l1\n    launch: r\n    prompt: go\n  - id: l2\n    launch: r\n    prompt: again"
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: twice, roles: role)), ["launch_twice"])
    let ordered = "  - id: l1\n    launch: r\n    prompt: go\n  - id: m\n    message: r\n    text: \"pane {{ roles.r.pane }}\""
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: ordered, roles: role)), [])
  }

  func testDuplicateStepIdsAcrossNesting() {
    let steps = """
        - id: loop
          repeat: { max: 2 }
          steps:
            - id: ask
              notify: hi
      """
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: steps)), ["duplicate_step_id"])
  }

  // MARK: - Inputs

  func testInputConstraints() {
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal() + "inputs:\n  n: { type: integer, default: 11, min: 1, max: 10 }\n"),
      ["input_range"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal() + "inputs:\n  n: { type: integer, min: 5, max: 1 }\n"), ["input_range"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal() + "inputs:\n  m: { type: enum, values: [a, b], default: c }\n"), ["enum_default"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal() + "inputs:\n  m: { type: enum, values: [a, a] }\n"), ["enum_values_duplicate"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal() + "inputs:\n  s: { type: string, default: \"two\\nlines\" }\n"),
      ["input_default_multiline"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal() + "inputs:\n  m: { type: enum, values: [a, \"two\\nlines\"] }\n"),
      ["enum_value_multiline"])
  }

  // MARK: - Templates

  func testTemplateReferencesAreWhitelistedAndOrdered() {
    let role = "  r:\n    source: launch"
    func codes(_ text: String, roles: String = "") -> [String] {
      WorkflowFixtures.codes(minimal(steps: "  - id: b\n    notify: \"\(text)\"", roles: roles))
    }
    XCTAssertEqual(codes("{{ run.id }} {{ run.dir }} {{ worktree.path }} {{ worktree.branch }}"), [])
    XCTAssertEqual(codes("{{ roles.author.name }} {{ roles.author.agent }} {{ roles.author.pane }}"), [])
    XCTAssertEqual(codes("{{ nope.x }}"), ["unknown_variable"])
    XCTAssertEqual(codes("{{ worktree.owner }}"), ["unknown_variable"])
    XCTAssertEqual(codes("{{ inputs.missing }}"), ["unknown_variable"])
    XCTAssertEqual(codes("{{ outputs.brief.path }}"), ["unknown_variable"], "no producer yet")
    XCTAssertEqual(codes("{{ roles.r.pane }}", roles: role), ["unknown_variable"], "launch role not launched")
    XCTAssertEqual(codes("{{ loop.index }}"), ["unknown_variable"], "outside repeat")
    XCTAssertEqual(codes("{{ loop.count }}"), ["unknown_variable"], "before any loop")
    XCTAssertEqual(codes("{{ open"), ["template_syntax"])
    XCTAssertEqual(codes("{{ }}"), ["template_syntax"])
  }

  func testOutputAndActionReferencesFollowProducers() {
    let steps = """
        - id: b
          message: author
          text: hi
          expect: { output: brief }
        - id: ctx
          action: git.context
        - id: n
          notify: "{{ outputs.brief.path }} {{ actions.ctx.path }} {{ actions.ctx.branch }}"
        - id: v
          notify: "{{ outputs.brief.verdict }}"
        - id: k
          notify: "{{ actions.ctx.nope }}"
      """
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: steps)), ["unknown_variable", "unknown_variable"])
  }

  func testActionsInsideALoopAreNotVisibleAfterIt() {
    let steps = """
        - id: loop
          repeat: { max: 2 }
          steps:
            - id: ctx
              action: git.context
            - id: inside
              notify: "{{ actions.ctx.path }} round {{ loop.index }}"
        - id: after
          notify: "{{ loop.count }} {{ actions.ctx.path }}"
      """
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: steps)), ["unknown_variable"])
  }

  // MARK: - Actions

  func testActionInputsFollowTheRegistry() {
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: "  - id: b\n    action: fs.delete")), ["unknown_action"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal(steps: "  - id: b\n    action: git.context\n    with: { depth: 3 }")),
      ["unknown_action_input"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal(steps: "  - id: b\n    action: handoff.transition\n    with: { from: author }")),
      ["missing_action_input"])
  }

  // MARK: - Repeat and until

  func testRepeatMaxBounds() {
    func loop(_ max: String) -> String {
      minimal(steps: "  - id: loop\n    repeat: { max: \(max) }\n    steps:\n      - id: x\n        notify: hi")
    }
    XCTAssertEqual(WorkflowFixtures.codes(loop("0")), ["repeat_max_range"])
    XCTAssertEqual(WorkflowFixtures.codes(loop("21")), ["repeat_max_range"])
    XCTAssertEqual(WorkflowFixtures.codes(loop("20")), [])
    XCTAssertEqual(
      WorkflowFixtures.codes(loop("\"{{ inputs.n }}\"") + "inputs:\n  n: { type: integer }\n"), [])
    XCTAssertEqual(
      WorkflowFixtures.codes(loop("\"{{ inputs.n }}\"") + "inputs:\n  n: { type: string }\n"), ["repeat_max_template"])
    XCTAssertEqual(
      WorkflowFixtures.codes(loop("\"{{ inputs.n }} rounds\"") + "inputs:\n  n: { type: integer }\n"),
      ["repeat_max_template"])
  }

  func testUntilNeedsADeclaredVerdict() {
    func loop(until: String, producer: String) -> String {
      minimal(
        steps: """
          \(producer)
            - id: loop
              repeat: { max: 2, until: "\(until)" }
              steps:
                - id: x
                  notify: hi
          """)
    }
    let verdictProducer = "  - id: p\n    message: author\n    text: hi\n    expect: { output: f, verdict: [clean, issues] }"
    let plainProducer = "  - id: p\n    message: author\n    text: hi\n    expect: { output: f }"
    XCTAssertEqual(WorkflowFixtures.codes(loop(until: "outputs.f.verdict == clean", producer: verdictProducer)), [])
    XCTAssertEqual(
      WorkflowFixtures.codes(loop(until: "outputs.f.verdict == done", producer: verdictProducer)),
      ["until_verdict_literal"])
    XCTAssertEqual(
      WorkflowFixtures.codes(loop(until: "outputs.f.verdict == clean", producer: plainProducer)),
      ["until_verdict_undeclared"])
    XCTAssertEqual(
      WorkflowFixtures.codes(loop(until: "outputs.g.verdict == clean", producer: verdictProducer)), ["until_output"])
  }

  func testUntilMayReferenceAnOutputProducedInsideTheLoop() {
    let steps = """
        - id: loop
          repeat: { max: 2, until: "outputs.f.verdict == clean" }
          steps:
            - id: x
              message: author
              text: hi
              expect: { output: f, verdict: [clean, issues] }
      """
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: steps)), [])
  }

  // MARK: - Expect

  func testVerdictRules() {
    func expect(_ verdict: String) -> String {
      minimal(steps: "  - id: b\n    message: author\n    text: hi\n    expect: { verdict: \(verdict) }")
    }
    XCTAssertEqual(WorkflowFixtures.codes(expect("[clean]")), ["verdict_count"])
    XCTAssertEqual(WorkflowFixtures.codes(expect("[a, b, c, d, e]")), ["verdict_count"])
    XCTAssertEqual(WorkflowFixtures.codes(expect("[clean, clean]")), ["verdict_duplicate"])
    XCTAssertEqual(WorkflowFixtures.codes(expect("[clean, \"Needs Work\"]")), ["verdict_slug"])
    XCTAssertEqual(WorkflowFixtures.codes(expect("[clean, issues]")), [])
  }

  func testTextMustBeOneLineButInstructionsMayNot() {
    let text = minimal(steps: "  - id: b\n    message: author\n    text: \"two\\nlines\"")
    XCTAssertEqual(WorkflowFixtures.codes(text), ["text_multiline"])
    let instruction = minimal(steps: "  - id: b\n    message: author\n    instruction: |\n      two\n      lines")
    XCTAssertEqual(WorkflowFixtures.codes(instruction), [])
  }

  // MARK: - Warnings

  func testWarnings() {
    let long = minimal(steps: "  - id: b\n    message: author\n    text: hi\n    expect: { timeout: 3h }")
    XCTAssertEqual(WorkflowFixtures.codes(long), ["timeout_long"])
    let spelled = minimal(steps: "  - id: b\n    message: author\n    text: \"finish with prowl workflow done -\"")
    XCTAssertEqual(WorkflowFixtures.codes(spelled), ["spells_completion_command"])
    XCTAssertEqual(WorkflowFixtures.diagnostics(spelled).first?.severity, .warning)
  }

  func testSkipWarnsOnlyWhenALaterNonOptionalConsumerExists() {
    let blocking = """
        - id: b
          message: author
          text: hi
          expect: { output: brief, timeout: 5m, on_timeout: skip }
        - id: n
          notify: "{{ outputs.brief.path }}"
      """
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: blocking)), ["skip_ends_run"])
    let optional = """
        - id: b
          message: author
          text: hi
          expect: { output: brief, timeout: 5m, on_timeout: skip }
        - id: t
          action: handoff.checkpoint
          with: { briefing: "{{ outputs.brief.path }}" }
      """
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: optional)), [])
  }

  func testAgentTokenWarnings() {
    let role = "  r:\n    source: launch\n    agents: [codex, robo]"
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal(roles: role), knownAgents: ["codex", "claude"]), ["unknown_agent"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal(roles: role), installedAgents: ["claude"]), ["agents_not_installed"])
    XCTAssertEqual(WorkflowFixtures.codes(minimal(roles: role), installedAgents: ["codex"]), [])
    XCTAssertEqual(WorkflowFixtures.codes(minimal(roles: role)), [], "unknown catalogs skip the warnings")
  }

  // MARK: - Round 1 review findings

  func testControlCharactersIncludingTabsAreRejectedInTypedText() {
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal() + "inputs:\n  s: { type: string, default: \"has\\ttab\" }\n"),
      ["input_default_multiline"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal(steps: "  - id: b\n    message: author\n    text: \"a\\tb\"")), ["text_multiline"])
  }

  func testRoleInputsOfNativeActionsMustNameDeclaredRoles() {
    let missing = "  - id: t\n    action: handoff.transition\n    with: { from: missing, to: also-missing }"
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: missing)), ["unknown_role", "unknown_role"])
    let templated = "  - id: t\n    action: handoff.transition\n    with: { from: \"{{ roles.author.name }}\", to: author }"
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: templated)), ["role_input_literal"])
    let valid = "  - id: t\n    action: handoff.transition\n    with: { from: author, to: author }"
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: valid)), [])
  }

  func testVerdictReferencesFollowTheLatestProducer() {
    let stale = """
        - id: first
          message: author
          text: First
          expect: { output: result, verdict: [clean, issues] }
        - id: second
          message: author
          text: Second
          expect: { output: result }
        - id: report
          notify: "{{ outputs.result.verdict }}"
      """
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: stale)), ["unknown_variable"])
    let refreshed = """
        - id: first
          message: author
          text: First
          expect: { output: result }
        - id: second
          message: author
          text: Second
          expect: { output: result, verdict: [clean, issues] }
        - id: report
          notify: "{{ outputs.result.verdict }}"
      """
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: refreshed)), [])
  }

  func testOutputsProducedOnlyInsideASkippableLoopAreNotVisibleAfterIt() {
    let skippable = """
        - id: initial
          message: author
          text: Initial
          expect: { output: verdict, verdict: [clean, issues] }
        - id: retry
          repeat: { max: 2, until: "outputs.verdict.verdict == clean" }
          steps:
            - id: produce
              message: author
              text: Retry
              expect: { output: retry_result }
        - id: report
          notify: "{{ outputs.retry_result.path }}"
      """
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: skippable)), ["unknown_variable"])
    let unconditional = """
        - id: retry
          repeat: { max: 2 }
          steps:
            - id: produce
              message: author
              text: Retry
              expect: { output: retry_result }
        - id: report
          notify: "{{ outputs.retry_result.path }}"
      """
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: unconditional)), [])
    let produced_before_and_inside = """
        - id: initial
          message: author
          text: Initial
          expect: { output: findings, verdict: [clean, issues] }
        - id: loop
          repeat: { max: 2, until: "outputs.findings.verdict == clean" }
          steps:
            - id: again
              message: author
              text: Again
              expect: { output: findings }
        - id: path
          notify: "{{ outputs.findings.path }}"
        - id: verdict
          notify: "{{ outputs.findings.verdict }}"
      """
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal(steps: produced_before_and_inside)), ["until_verdict_undeclared", "unknown_variable"],
      "the in-loop producer declares no verdict: until cannot read it and neither can a later reference")
  }

  func testSuggestWarnsWhenNoEnabledProfileMatches() {
    let role = "  r:\n    source: launch\n    suggest: { agent: codex, reasoning_effort: xhigh }"
    let codexHigh = WorkflowProfileSuggestion(agent: "codex", model: "gpt-5", reasoningEffort: "xhigh", executionMode: "standard")
    let claude = WorkflowProfileSuggestion(agent: "claude", model: nil, reasoningEffort: nil, executionMode: "standard")
    XCTAssertEqual(WorkflowFixtures.codes(minimal(roles: role), enabledProfiles: [claude]), ["suggest_unmatched"])
    XCTAssertEqual(WorkflowFixtures.codes(minimal(roles: role), enabledProfiles: [claude, codexHigh]), [])
    XCTAssertEqual(WorkflowFixtures.codes(minimal(roles: role)), [], "no profile catalog: no warning")
  }

  // MARK: - Round 2 review findings

  func testUntilReadsOnlyTheFinalProducerOfTheLoopBody() {
    let steps = """
        - id: initial
          message: author
          text: Initial
          expect: { output: result, verdict: [retry, stop] }
        - id: loop
          repeat: { max: 3, until: "outputs.result.verdict == stop" }
          steps:
            - id: intermediate
              message: author
              text: Working
              expect: { output: result, verdict: [working, failed] }
            - id: final
              message: author
              text: Final
              expect: { output: result, verdict: [retry, stop] }
      """
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: steps)), [])
  }

  func testALaterSkippableLoopSeesTheFoldedStateOfAnEarlierOne() {
    let steps = """
        - id: initial
          message: author
          text: Initial
          expect: { output: findings, verdict: [clean, issues] }
        - id: first
          repeat: { max: 2, until: "outputs.findings.verdict == clean" }
          steps:
            - id: again
              message: author
              text: Again
              expect: { output: findings, verdict: [needs-work, clean] }
        - id: second
          repeat: { max: 2, until: "outputs.findings.verdict == needs-work" }
          steps:
            - id: poke
              notify: "round {{ loop.index }}"
      """
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal(steps: steps)), ["until_verdict_literal"],
      "if the first loop is skipped the latest findings verdict set is {clean, issues}; needs-work is not in it")
  }

  func testSkipWarningsSurviveFoldingASkippableLoop() {
    let steps = """
        - id: initial
          message: author
          text: Initial
          expect: { output: gate, verdict: [go, stop] }
        - id: loop
          repeat: { max: 2, until: "outputs.gate.verdict == stop" }
          steps:
            - id: produce
              message: author
              text: Produce
              expect: { output: draft, timeout: 5m, on_timeout: skip }
            - id: consume
              notify: "{{ outputs.draft.path }}"
      """
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: steps)), ["skip_ends_run"])
  }

  func testBlankNamesAndTokensAreRejectedLikeTheSchemaDoes() {
    XCTAssertEqual(
      WorkflowFixtures.codes("schema: prowl.workflow/v1\nid: demo\nname: \"\"\nroles:\n  author:\n    source: current\nsteps:\n  - id: a\n    notify: hi\n"),
      ["name_empty"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal(roles: "  r:\n    source: launch\n    agents: [\"\", codex]")), ["agent_token_empty"])
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal() + "inputs:\n  m: { type: enum, values: [\"\", b] }\n"), ["enum_value_empty"])
  }

  // MARK: - Round 3 review findings

  func testSkipWarningsRespectProducerAndConsumerOrder() {
    let consumedBefore = """
        - id: first
          message: author
          text: First
          expect: { output: brief }
        - id: use
          notify: "{{ outputs.brief.path }}"
        - id: second
          message: author
          text: Second
          expect: { output: brief, timeout: 5m, on_timeout: skip }
      """
    XCTAssertEqual(WorkflowFixtures.codes(minimal(steps: consumedBefore)), [], "nothing after the skip depends on it")
    let loopCarried = """
        - id: seed
          message: author
          text: Seed
          expect: { output: draft, verdict: [go, stop] }
        - id: loop
          repeat: { max: 3, until: "outputs.draft.verdict == stop" }
          steps:
            - id: use
              notify: "{{ outputs.draft.path }}"
            - id: redo
              message: author
              text: Redo
              expect: { output: draft, verdict: [go, stop], timeout: 5m, on_timeout: skip }
      """
    XCTAssertEqual(
      WorkflowFixtures.codes(minimal(steps: loopCarried)), ["skip_ends_run"],
      "the next iteration and the until check read the skipped output")
  }
}

