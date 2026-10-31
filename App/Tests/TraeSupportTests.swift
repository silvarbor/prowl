import Foundation
import Testing

@testable import Prowl

struct TraeSupportTests {
  private func agent() throws -> DetectedAgent {
    try #require(DetectedAgent(rawValue: "trae"))
  }

  private let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
  private let now = Date(timeIntervalSince1970: 1_783_800_000)

  // MARK: - Process detection

  @Test func recognizesTheCLIEntrypointsAndLeavesTheDesktopLauncherUnmapped() throws {
    let expected = try agent()
    #expect(identifyAgent(processName: "traecli") == expected)
    #expect(identifyAgent(processName: "traex") == expected)
    #expect(identifyAgent(processName: "trae-cli") == expected)
    #expect(identifyAgent(processName: "trae-agent") == expected)
    // The Trae desktop IDE ships a `trae` launcher; only the CLI entrypoints map.
    #expect(identifyAgent(processName: "trae") == nil)

    // A native executable's name in a wrapper's argv is a prompt token or an
    // install path, never the TUI (score-40 guard, shared with grok/devin/agy).
    let wrapped = ForegroundProcess(
      pid: 400, name: "node", argv0: "node", cmdline: "node /tmp/app.js --model traecli")
    #expect(identifyAgentInJob(ForegroundJob(processGroupID: 400, processes: [wrapped])) == nil)
  }

  // MARK: - Runtime adapter

  /// traecli's TUI notification defaults to off, so a turn completion only
  /// reaches Prowl through Ghostty's OSC 9 callback if the adapter asks for it.
  private static let notificationOptions = [
    "-c", "tui.notifications=true",
    "-c", "tui.notification_method=osc9",
    "-c", "tui.notification_condition=always",
  ]

  @Test func launchBuildsCodexShapedInvocations() throws {
    let runtime = try #require(AgentProfileRuntime(rawValue: "trae"))
    #expect(AgentRuntimeAdapterRegistry.displayName(for: runtime) == "TraeCode CLI")
    #expect(runtime.defaultHomeDirectoryName == ".trae")

    let options =
      ["--model", "gpt-5.6-sol", "-c", "model_reasoning_effort=high"] + Self.notificationOptions
    for (intent, expected) in [
      (AgentStartIntent.interactive, options),
      (.prompt("Review this."), options + ["Review this."]),
      // Headless runs the `exec` subcommand, so it leads the arguments.
      (.headless("Review this."), ["exec"] + options + ["Review this."]),
    ] {
      let invocation = try AgentRuntimeAdapterRegistry.makeStartInvocation(
        AgentStartRequest(
          runtime: runtime, intent: intent,
          configuration: .init(model: "gpt-5.6-sol", reasoningEffort: "high")))
      #expect(invocation.executable == "traecli")
      #expect(invocation.arguments == expected)
    }

    let unrestricted = try AgentRuntimeAdapterRegistry.makeStartInvocation(
      AgentStartRequest(
        runtime: runtime, intent: .interactive, configuration: .init(executionMode: .unrestricted)))
    #expect(
      unrestricted.arguments
        == ["--dangerously-bypass-approvals-and-sandbox"] + Self.notificationOptions)
  }

  @Test func launchEnablesOsc9CompletionNotifications() throws {
    let runtime = try #require(AgentProfileRuntime(rawValue: "trae"))
    let invocation = try AgentRuntimeAdapterRegistry.makeStartInvocation(
      AgentStartRequest(runtime: runtime, intent: .interactive, configuration: .init()))
    // OSC 9 (not `bel`): Prowl's inbox is fed by Ghostty's desktop-notification
    // callback, and its bell counter drives no inbox entry.
    #expect(
      invocation.arguments == [
        "-c", "tui.notifications=true",
        "-c", "tui.notification_method=osc9",
        "-c", "tui.notification_condition=always",
      ])
  }

  @Test func observesModelAndBothUnrestrictedSpellings() throws {
    let runtime = try #require(AgentProfileRuntime(rawValue: "trae"))
    #expect(
      AgentRuntimeAdapterRegistry.observe(
        runtime: runtime,
        arguments: ["traecli", "--model", "gpt-5.6-sol", "--dangerously-bypass-approvals-and-sandbox"])
        == AgentLaunchObservation(model: "gpt-5.6-sol", executionMode: .unrestricted))
    #expect(
      AgentRuntimeAdapterRegistry.observe(runtime: runtime, arguments: ["traecli", "-m", "gpt-5.6-sol", "-y"])
        == AgentLaunchObservation(model: "gpt-5.6-sol", executionMode: .unrestricted))
    #expect(
      AgentRuntimeAdapterRegistry.observe(
        runtime: runtime, arguments: ["traecli", "--permission-mode", "bypass_permissions"]
      )
      .executionMode == .unrestricted)
    // A different permission preset is not unrestricted.
    #expect(
      AgentRuntimeAdapterRegistry.observe(runtime: runtime, arguments: ["traecli", "--permission-mode", "auto"])
        .executionMode == nil)
  }

  @Test func accountIsolationRelocatesTheTraeHome() throws {
    let runtime = try #require(AgentProfileRuntime(rawValue: "trae"))
    let adapter = try #require(AgentRuntimeAdapterRegistry.profileAdapter(for: runtime))
    #expect(adapter.supportsModelSelection)
    #expect(adapter.supportsReasoningEffort)
    #expect(adapter.executionModeOptions == [.standard, .unrestricted])
    #expect(adapter.supportsAccountIsolation)
    #expect(adapter.accountHomeEnvironmentVariable == "TRAE_HOME")
    #expect(adapter.accountIsolation?.sessionRootRelativePath == "cli")
    #expect(adapter.signalHooks == nil)
    // TRAE_HOME points at the managed home; traecli stores sessions under its
    // `cli` child, so the session config root is the managed home plus `cli`.
    let managedHome = URL(fileURLWithPath: "/Users/me/.prowl/agent-profiles/trae", isDirectory: true)
    let isolation = try #require(adapter.accountIsolation)
    #expect(isolation.pathArguments.isEmpty)
    #expect(isolation.sessionConfigRoot(for: managedHome).path == "/Users/me/.prowl/agent-profiles/trae/cli")
  }

  // MARK: - Session ownership

  @Test func sessionOwnershipParsesRolloutJSONLUnderTheTraeHome() throws {
    let profile = AgentSessionProfile.profile(for: try agent())
    let id = "01a1247d-ef57-71f0-b191-88f7a3132dea"
    let path = "/Users/me/.trae/cli/sessions/2026/10/10/rollout-2026-10-10T14-26-35-\(id).jsonl"
    let session = try #require(profile.parsePath(path))
    #expect(session.id == id)
    #expect(session.transcriptPath?.path == path)
    // A rollout file outside the sessions tree must not parse.
    #expect(profile.parsePath("/tmp/rollout-2026-10-10T14-26-35-\(id).jsonl") == nil)
  }

  @Test func sessionRootsNarrowToProcessLifetimeDays() throws {
    let profile = AgentSessionProfile.profile(for: try agent())
    let roots = profile.candidateRoots(home, nil, now, now)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy/MM/dd"
    // One day before the process start through today — here the same day, so
    // two day directories: yesterday and today.
    let calendar = Calendar(identifier: .gregorian)
    let yesterday = calendar.startOfDay(for: now.addingTimeInterval(-86_400))
    let today = calendar.startOfDay(for: now)
    #expect(
      roots.map(\.path)
        == [
          "/Users/me/.trae/cli/sessions/\(formatter.string(from: yesterday))",
          "/Users/me/.trae/cli/sessions/\(formatter.string(from: today))",
        ])
    #expect(profile.fallbackRoots(home, nil).map(\.path) == ["/Users/me/.trae/cli/sessions"])
  }

  // MARK: - Screen detection

  @Test func trustDialogReadsAsBlocked() throws {
    let agent = try agent()
    let screen = """
      You are in /Users/me/App

      Do you trust the contents of this directory?

      ❯ 1. Yes, continue
        2. No, quit

      Press enter to continue
      """
    #expect(agent.detectState(in: screen) == .blocked)
  }

  @Test func numberedSelectionDialogReadsAsBlocked() throws {
    let agent = try agent()
    let screen = """
      Allow the agent to run this command?

      rm -rf build

      ❯ 1. Approve
        2. Deny

      Press enter to continue
      """
    #expect(agent.detectState(in: screen) == .blocked)
  }

  @Test func interruptHintReadsAsWorking() throws {
    let agent = try agent()
    let screen = """
      ❯ Refactor the parser

      ──────────────────────────────
      ✻ Thinking… (esc to interrupt)
      """
    #expect(agent.detectState(in: screen) == .working)
  }

  @Test func idleFooterUnderTheComposerReadsAsIdle() throws {
    let agent = try agent()
    let screen = """
      Done.

      ❯
      ────────────────────────────────────────────────
      DeepSeek-V4.1-Flash · Context 100% left · /Users/me/App ▧ Workspace Edit
      """
    #expect(agent.detectState(in: screen) == .idle)
  }

  @Test func transcriptNumberedListWithoutSelectionMarkStaysUnknown() throws {
    let agent = try agent()
    // The composer is gone and no selection glyph is present, so a plain
    // numbered list is transcript history, never a live dialog.
    let screen = """
      Here are the steps to follow:
      1. First
      2. Second
      """
    #expect(agent.detectState(in: screen) == .unknown)
  }

  @Test func unrecognizedScreenFailsTowardUnknown() throws {
    let agent = try agent()
    #expect(agent.detectState(in: "screen without a live rule") == .unknown)
  }

  // MARK: - Screen detection: region anchoring (regressions)

  @Test func quotedTrustQuestionUnderARunningIndicatorReadsAsWorking() throws {
    let agent = try agent()
    // The transcript quotes a trust dialog verbatim, but the live composer box
    // below still carries the interrupt hint: the quoted dialog is history and
    // must not outrank the running turn.
    let screen = """
      The CLI once asked:
      Do you trust the contents of this directory?
      ❯ 1. Yes, continue
        2. No, quit

      ❯
      ────────────────────────────────────────────────
      ✻ Thinking… (esc to interrupt)
      """
    #expect(agent.detectState(in: screen) == .working)
  }

  @Test func numberedDraftInsideAnIdleComposerReadsAsIdle() throws {
    let agent = try agent()
    // A two-line numbered draft typed into the composer is the user's input, not
    // a live choice dialog; the status row below it reads idle.
    let screen = """
      ❯ 1. First draft line
        2. Second draft line
      ────────────────────────────────────────────────
      DeepSeek-V4.1-Flash · Context 100% left · /Users/me/App ▧ Workspace Edit
      """
    #expect(agent.detectState(in: screen) == .idle)
  }

  @Test func interruptWordsInsideAnIdleComposerReadAsIdle() throws {
    let agent = try agent()
    // `to interrupt` typed as the draft must not read as a running turn.
    let screen = """
      ❯ Explain how to interrupt a task
      ────────────────────────────────────────────────
      DeepSeek-V4.1-Flash · Context 100% left · /Users/me/App ▧ Workspace Edit
      """
    #expect(agent.detectState(in: screen) == .idle)
  }

  // MARK: - Screen detection: TraeCode CLI 0.201.7 (on-prem) fixtures

  @Test func onPremIdleComposerWithIndentedStatusRowReadsAsIdle() throws {
    let agent = try agent()
    // Captured from the on-prem 0.201.7 TUI: the built-in status row is indented
    // two spaces below the closing border, so it is read by signature, not column.
    let border = String(repeating: "─", count: 120)
    let screen = """
      ➜  CBrain git:(feature/2.36) traecli
      ╭───────────────────────────────────────────────────╮
      │ █ ◆ ◆ █  TraeCode CLI (v0.201.7)                  │
      ╰───────────────────────────────────────────────────╯

        Tip: Use /statusline to configure which items appear in the status line.

      \(border)
      ❯ Explain this codebase
      \(border)
        DeepSeek-V4.1-Flash · Context 100% left · ~/opt/CBrain · feature/2.36 · +1881 -341  ▧ Workspace Edit
      """
    #expect(agent.detectState(in: screen) == .idle)
  }

  @Test func onPremWorkingIndicatorAboveTheComposerReadsAsWorking() throws {
    let agent = try agent()
    // Captured mid-turn on the on-prem 0.201.7 TUI: the status row is identical
    // to the idle one, so only the `◆ Working… (… esc to interrupt)` line above
    // the box — separated from it by the rotating tip — proves the running turn.
    let border = String(repeating: "─", count: 120)
    let screen = """
      ✔ Auto-reviewer approved TraeCode CLI to run mkdir -p /tmp/probe this time

      ◆ Working… (3m 55s • ↑ 20.8K tokens • esc to interrupt)
        └ Tip: Pipe command output into `traecli exec 'summarize this'` to include stdin as context.
      \(border)
      ❯ Find and fix a bug in @filename
      \(border)
        DeepSeek-V4.1-Flash · Context 74% left · ~/opt/Prowl · fork/trae-cli · +1070 -49  ⛉ Auto Mode
      """
    #expect(agent.detectState(in: screen) == .working)
  }

  @Test func todoChecklistBetweenIndicatorAndComposerReadsAsWorking() throws {
    let agent = try agent()
    // Captured mid-turn on the on-prem 0.201.7 TUI while the agent's todo widget
    // was live: the `❖ … (esc to interrupt)` indicator heads a multi-row block —
    // the running turn, then its checklist — that sits several rows above the box,
    // so the block, not a fixed few rows above the prompt, carries the hint. The
    // status row below the box is identical to the idle one, so missing the
    // indicator reads a running turn as idle.
    let border = String(repeating: "─", count: 120)
    let screen = """
      ✔ Auto-reviewer approved TraeCode CLI to run something this time

      ❖ Root-causing the traecli false-Idle bug… (24m 24s • ↑ 131K tokens • esc to interrupt)
        └ ■ Root-cause why the agent shows idle after a long idle
          ◻ Fix the detector in ScreenHeuristics.swift
          ◻ Add fixtures in TraeSupportTests.swift
          ◻ Run make build-app and make check
      \(border)
      ❯ Find and fix a bug in @filename
      \(border)
        DeepSeek-V4.1-Flash · Context 46% left · ~/opt/Prowl · fork/trae-cli · +1252 -52  ⛉ Auto Mode
      """
    #expect(agent.detectState(in: screen) == .working)
  }

  @Test func todoChecklistAndWrappedTipAboveTheComposerReadAsWorking() throws {
    let agent = try agent()
    // The live block may also carry the rotating tip under the indicator, and at
    // a narrow width the indicator and the tip wrap — the hint still heads the
    // same blank-bounded run, so the running turn must not fall back to the idle
    // status row.
    let border = String(repeating: "─", count: 80)
    let screen = """
      ◆ Working… (12s • esc to interrupt) · 1 shell running
      to manage
        └ Tip: Press Tab to queue a message when a task is
      running; otherwise it sends immediately.
      \(border)
      ❯ Improve documentation in @filename
      \(border)
        DeepSeek-V4.1-Flash · Context 96% left · ~/opt/Prowl · fork/trae-cli  ▧ Workspace Edit
      """
    #expect(agent.detectState(in: screen) == .working)
  }

  @Test func mcpServerBootLineAboveAnIdleComposerReadsAsIdle() throws {
    let agent = try agent()
    // Cold start: before the session is ready traecli heads the live block with a
    // boot progress line that reuses the interrupt footer (`✧ Starting MCP servers
    // (1/3): … (0s • esc to interrupt)`) while the composer below is the ordinary
    // idle box. Reading it as a running turn flashed Working through startup and
    // then let the settle to idle earn a spurious Done badge.
    let border = String(repeating: "─", count: 168)
    let screen = """
      ╭───────────────────────────────────────────────────╮
      │ █ ◆ ◆ █  TraeCode CLI (v0.201.7)                  │
      ╰───────────────────────────────────────────────────╯

        Tip: Press Ctrl+O to open the transcript view.

      ✧ Starting MCP servers (1/3): XcodeBuildMCP, code-review-graph (0s • esc to interrupt)
      \(border)
      ❯ Improve documentation in @filename
      \(border)
        DeepSeek-V4.1-Flash · Context 100% left · /private/tmp/trae-cold2  ▧ Workspace Edit
      """
    #expect(agent.detectState(in: screen) == .idle)
  }

  @Test func interruptHintWithAnUnrelatedStartingTitleStillReadsAsWorking() throws {
    let agent = try agent()
    // The boot-line exclusion is scoped to the MCP progress phrase, not to
    // `Starting`: a real turn indicator whose title happens to begin with
    // `Starting` must still read as Working.
    let border = String(repeating: "─", count: 168)
    let screen = """
      ◆ Starting the refactor… (12s • esc to interrupt)
      \(border)
      ❯ Find and fix a bug in @filename
      \(border)
        DeepSeek-V4.1-Flash · Context 74% left · ~/opt/Prowl  ⛉ Auto Mode
      """
    #expect(agent.detectState(in: screen) == .working)
  }

  @Test func statusRowWithoutAComposerStaysUnknown() throws {
    let agent = try agent()
    // The idle signature alone, with no composer box above it, is not evidence of
    // a live idle prompt — the screen must fail toward unknown.
    let screen = """
      Here is the last line of output.
      DeepSeek-V4.1-Flash · Context 100% left · /Users/me/App ▧ Workspace Edit
      """
    #expect(agent.detectState(in: screen) == .unknown)
  }

  @Test func onPremIndentedApprovalDialogReadsAsBlocked() throws {
    let agent = try agent()
    // Captured live on the on-prem 0.201.7 TUI: an MCP tool approval replaces the
    // composer with a dialog rendered inside the live block's two-space gutter, so
    // the `❯` selection mark is indented, not column-0. Requiring column 0 made the
    // real dialog read unknown, and the state machine then kept the running turn's
    // stale Working instead of clearing it to Blocked.
    let border = String(repeating: "─", count: 168)
    let screen = """
      ◆ Calling mobile-mcp.mobile_save_screenshot({"device":"Pixel_10_Pro_XL","saveTo":"/tmp/shot1.png"})
      \(border)
        Field 1/1
        Allow the mobile-mcp MCP server to run tool "mobile_save_screenshot"?

        device: Pixel_10_Pro_XL
        saveTo: /tmp/shot1.png

        ❯ 1. Allow                   Run the tool and continue.
          2. Allow for this session  Run the tool and remember this choice for this session.
          3. Always allow            Run the tool and remember this choice for future tool calls.
          4. Cancel                  Cancel this tool call
        enter to submit | esc to cancel
      """
    #expect(agent.detectState(in: screen) == .blocked)
  }

  @Test func onPremIndentedElicitationFormReadsAsBlocked() throws {
    let agent = try agent()
    // An elicitation form asks the user to type a value, so it carries no numbered
    // options and no `❯` mark — only the indented fields and the live footer. The
    // footer vocabulary (` to submit`, `to navigate fields|questions`) is verified
    // against the 0.201.7 binary; without it the form read unknown and a running
    // turn's Working never cleared.
    let border = String(repeating: "─", count: 168)
    let screen = """
      ◆ Calling some-mcp.some_tool({})
      \(border)
        Field 1/1
        Enter a name for the new workspace

        name:

        ↑/↓ to navigate fields   esc to cancel
      """
    #expect(agent.detectState(in: screen) == .blocked)
  }

  @Test func selectionMarkWithoutAComposerOrSiblingStaysUnknown() throws {
    let agent = try agent()
    // A stray `❯`-marked numbered line with no closing composer border and no
    // unselected sibling is neither a composer nor a live dialog: unknown.
    let screen = """
      Steps to reproduce:
      ❯ 1. Only one option shown
      """
    #expect(agent.detectState(in: screen) == .unknown)
  }

  // MARK: - Screen detection: review fixes (tail budget, convergence, y/n, auth)

  @Test func tallChecklistPushingTheHintPastTheTailStillReadsAsWorking() throws {
    let agent = try agent()
    // The running indicator heads a blank-bounded block whose todo checklist grows
    // without bound. When the block is taller than a 24-line tail, that fixed tail
    // dropped the hint and the idle status row below the box decided the turn. The
    // detector now reads the whole active screen, so the indicator survives.
    let border = String(repeating: "─", count: 120)
    let todo = (1...30).map { "  ◻ Checklist item number \($0) for the running plan" }
      .joined(separator: "\n")
    let screen = """
      ✔ Auto-reviewer approved TraeCode CLI to run something this time

      ❖ Root-causing the traecli false-Idle bug… (24m 24s • ↑ 131K tokens • esc to interrupt)
      \(todo)
      \(border)
      ❯ Find and fix a bug in @filename
      \(border)
        DeepSeek-V4.1-Flash · Context 46% left · ~/opt/Prowl · fork/trae-cli · +1252 -52  ⛉ Auto Mode
      """
    #expect(agent.detectState(in: screen) == .working)
  }

  @Test func composerWithAnUnrecognizedStatusRowReadsAsIdle() throws {
    let agent = try agent()
    // A composer renders only a live prompt. With no running hint above the box and
    // no recognized status row below it, the turn has settled: returning unknown
    // let the state machine retain the previous turn's stale Working.
    let border = String(repeating: "─", count: 120)
    let screen = """
      \(border)
      ❯ Explain this codebase
      \(border)
        Some footer signature the detector does not know
      """
    #expect(agent.detectState(in: screen) == .idle)
  }

  @Test func quotedComposerAboveTheLiveIdleComposerReadsAsIdle() throws {
    let agent = try agent()
    // A quoted composer left in the transcript carries the running hint, but only
    // the bottom-most prompt+border box is live. Its own blank-bounded block has no
    // indicator and its status row is idle, so the live state is idle regardless of
    // the quoted one above.
    let border = String(repeating: "─", count: 120)
    let screen = """
      ◆ Working… (2m 0s • esc to interrupt)
      ❯ A quoted composer echoed in the transcript
      \(border)

      ❯ A real live prompt
      \(border)
        DeepSeek-V4.1-Flash · Context 100% left · ~/opt/Prowl ▧ Workspace Edit
      """
    #expect(agent.detectState(in: screen) == .idle)
  }

  @Test func bracketedYesNoConfirmationReadsAsBlocked() throws {
    let agent = try agent()
    // traecli renders a y/n confirmation as a bracketed token at the end of the
    // prompt line rather than a numbered menu. Missing it left a blocking question
    // reading unknown, so a running turn's Working never cleared to Blocked.
    let screen = """
      The agent wants to write build/output.bin.

      Overwrite build/output.bin? [y/N]
      """
    #expect(agent.detectState(in: screen) == .blocked)
  }

  @Test func loginScreenReadsAsBlocked() throws {
    let agent = try agent()
    // The interactive login/auth screens replace the composer like a dialog but use
    // a `>` menu or free-form fields, so the numbered/`❯` shapes never match them.
    // A distinctive header plus its Enter/Esc chrome is the live signature.
    let screen = """
      Sign in with browser account
      > Sign in with Device Code

      Press Enter to sign in
      Press Esc to cancel
      """
    #expect(agent.detectState(in: screen) == .blocked)
  }

  @Test func transcriptMentioningLoginWithoutChromeStaysUnknown() throws {
    let agent = try agent()
    // The header phrase alone — echoed transcript text — is not a live login screen:
    // without the Enter/Esc chrome it must not read as blocked.
    let screen = """
      The tool printed: Sign in with browser account failed.
      Retrying the request now.
      """
    #expect(agent.detectState(in: screen) == .unknown)
  }

  @Test func blockerTextReadsTheLiveDialogAndIsNilOtherwise() throws {
    let agent = try agent()
    // `agents read` reports the blocked screen's own text. It reuses the detector's
    // shape rules: the blank-bounded run carrying the bottom-most dialog marker.
    let border = String(repeating: "─", count: 168)
    let blocked = """
      ◆ Calling mobile-mcp.mobile_save_screenshot({})
      \(border)
        Field 1/1
        Allow the mobile-mcp MCP server to run tool "mobile_save_screenshot"?

        device: Pixel_10_Pro_XL
        saveTo: /tmp/shot1.png

        ❯ 1. Allow                   Run the tool and continue.
          2. Allow for this session  Run the tool and remember this choice for this session.
          3. Always allow            Run the tool and remember this choice for future tool calls.
          4. Cancel                  Cancel this tool call
        enter to submit | esc to cancel
      """
    let text = try #require(traeBlockerText(in: agent.detectionSnapshot(from: blocked)))
    // The whole dialog, not just its options: a caller has to be able to tell what it
    // would approve. The question and the tool's parameters are separated from the
    // options by a blank line, and stopping the walk at that blank returned only
    // `❯ 1. Allow …` and the footer.
    #expect(text.contains("Field 1/1"))
    #expect(text.contains("Allow the mobile-mcp MCP server to run tool \"mobile_save_screenshot\"?"))
    #expect(text.contains("device: Pixel_10_Pro_XL"))
    #expect(text.contains("saveTo: /tmp/shot1.png"))
    #expect(text.contains("1. Allow"))
    #expect(text.contains("esc to cancel"))
    // The dialog's own blank lines survive, so the text reads like the pane.
    #expect(text.contains("/tmp/shot1.png\n\n"))

    let idle = """
      \(border)
      ❯ Explain this codebase
      \(border)
        DeepSeek-V4.1-Flash · Context 100% left · ~/opt/Prowl ▧ Workspace Edit
      """
    #expect(traeBlockerText(in: agent.detectionSnapshot(from: idle)) == nil)
  }

  // MARK: - Status-bar content must not decide the state

  @Test func statusBarPathNamingModalChromeStaysIdle() throws {
    let agent = try agent()
    // The status bar carries the working directory, and footer matching used to accept
    // bare substrings from it: a checkout named `/tmp/how to submit` turned a settled
    // composer into Blocked, and `/tmp/how to interrupt` turned it into Working.
    let border = String(repeating: "─", count: 120)
    func idleScreen(_ path: String) -> String {
      """
      \(border)
      ❯ Explain this codebase
      \(border)
        DeepSeek-V4.1-Flash · Context 100% left · \(path) ▧ Workspace Edit
      """
    }
    #expect(agent.detectState(in: idleScreen("/tmp/demo")) == .idle)
    #expect(agent.detectState(in: idleScreen("/tmp/how to submit")) == .idle)
    #expect(agent.detectState(in: idleScreen("/tmp/how to interrupt")) == .idle)
    #expect(agent.detectState(in: idleScreen("/tmp/esc to cancel")) == .idle)

    // It cannot override a real running footer either.
    let footer =
      "◆ traecli has mouse reporting enabled (24m 29s • ↑ 117K tokens • esc to interrupt) "
      + "· 1 shell running… · /ps to manage"
    let working = """
      \(footer)
      \(border)
      ❯ Explain this codebase
      \(border)
        DeepSeek-V4.1-Flash · Context 100% left · /tmp/how to submit ▧ Workspace Edit
      """
    #expect(agent.detectState(in: working) == .working)
  }

  @Test func transcriptMentioningSubmitWithoutChromeStaysUnknown() throws {
    let agent = try agent()
    // Dialog footers are matched by their structure — the cancel/navigate chrome plus
    // the submit phrase — so a transcript line that merely mentions submitting is a
    // screen with no live region at all, not a form waiting for input.
    let screen = """
      The plan says to submit the form and then wait for the upload.
      Nothing else is on screen right now.
      """
    #expect(agent.detectState(in: screen) == .unknown)
    #expect(traeBlockerText(in: agent.detectionSnapshot(from: screen)) == nil)
  }

  // MARK: - Blocker text keeps the whole dialog

  @Test func blockerTextKeepsUnindentedDialogsWhole() throws {
    let agent = try agent()
    // The trust prompt and the login screens render at column 0, so a walk that
    // followed only indented rows kept the footer and dropped everything above it: the
    // question and the choices a caller has to read before approving.
    let trust = """
      You are in /Users/me/App

      Do you trust the contents of this directory?

      ❯ 1. Yes, continue
        2. No, quit

      Press enter to continue
      """
    let trustText = try #require(traeBlockerText(in: agent.detectionSnapshot(from: trust)))
    #expect(trustText.contains("You are in /Users/me/App"))
    #expect(trustText.contains("Do you trust the contents of this directory?"))
    #expect(trustText.contains("❯ 1. Yes, continue"))
    #expect(trustText.contains("2. No, quit"))
    #expect(trustText.contains("Press enter to continue"))

    let login = """
      Sign in with browser account
      > Sign in with Device Code

      Press Enter to sign in
      Press Esc to cancel
      """
    let loginText = try #require(traeBlockerText(in: agent.detectionSnapshot(from: login)))
    #expect(loginText.contains("Sign in with browser account"))
    #expect(loginText.contains("Sign in with Device Code"))
    #expect(loginText.contains("Press Enter to sign in"))
    #expect(loginText.contains("Press Esc to cancel"))
  }

  // MARK: - Active region: composer against dialog

  @Test func historicalComposerAboveTheApprovalDialogReadsAsBlocked() throws {
    let agent = try agent()
    // The transcript can quote a composer box (`❯` row + full-width rule), and traecli
    // renders the live approval below it. Searching the whole screen for a composer let
    // that quoted box decide, so the pane read Idle — and `agents read` returned no
    // blocker — while it was waiting for approval. The lower of the two live regions is
    // the active one, so the dialog wins here.
    let border = String(repeating: "─", count: 120)
    let screen = """
      ❯ Refactor the parser and keep the CLI compatible
      \(border)
        Allow the mobile-mcp MCP server to run tool "mobile_save_screenshot"?

        device: Pixel_10_Pro_XL
        saveTo: /tmp/shot1.png

        ❯ 1. Allow                   Run the tool and continue.
          2. Allow for this session  Run the tool and remember this choice for this session.
          3. Cancel                  Cancel this tool call
        enter to submit | esc to cancel
      """
    #expect(agent.detectState(in: screen) == .blocked)
    let text = try #require(traeBlockerText(in: agent.detectionSnapshot(from: screen)))
    #expect(text.contains("mobile_save_screenshot"))
    #expect(text.contains("saveTo: /tmp/shot1.png"))
    #expect(text.contains("1. Allow"))
    #expect(text.contains("esc to cancel"))
  }

  @Test func quotedApprovalOptionsAboveTheLiveComposerStayIdle() throws {
    let agent = try agent()
    // The mirror image: the quoted block sits *above* the live composer, so the
    // composer is the active region and the past dialog is transcript. Resolving by
    // position has to keep this reading Idle and yield no blocker.
    let border = String(repeating: "─", count: 120)
    let screen = """
        ❯ 1. Allow     Run the tool and continue.
          2. Cancel    Cancel this tool call
        enter to submit | esc to cancel
      \(border)
      ❯ Explain this codebase
      \(border)
        DeepSeek-V4.1-Flash · Context 100% left · ~/opt/Prowl ▧ Workspace Edit
      """
    #expect(agent.detectState(in: screen) == .idle)
    #expect(traeBlockerText(in: agent.detectionSnapshot(from: screen)) == nil)
  }

  // MARK: - Composer boundaries are local to the box

  @Test func separatorWiderThanTheComposerAboveItKeepsTheBox() throws {
    let agent = try agent()
    // The pane's text is extracted non-rectangularly and Ghostty joins soft-wrapped
    // lines, so a historical *logical* line can be wider than the pane: the agent's
    // own output can leave a rule behind that out-measures the live composer. Sizing
    // the composer's borders by the longest rule on screen then read the box as
    // absent, and an idle `❯ Draft` fell through to unknown — which in turn let the
    // state machine keep the previous turn's Working.
    let historical = String(repeating: "─", count: 100)
    let border = String(repeating: "─", count: 80)
    let screen = """
      ✔ Summarized 3 shell commands

      \(historical)

      \(border)
      ❯ Draft
      \(border)
        DeepSeek-V4.1-Flash · Context 100% left · ~/opt/Prowl ▧ Workspace Edit
      """
    #expect(agent.detectState(in: screen) == .idle)
  }

  @Test func numberedDraftUnderAWiderSeparatorStaysIdleInsteadOfBlocked() throws {
    let agent = try agent()
    // The same screen with a numbered draft: the box was lost the same way, and the
    // draft's own rows then matched the dialog shapes — a `❯`-marked option beside an
    // unselected numbered sibling — so a settled composer read Blocked.
    let historical = String(repeating: "─", count: 100)
    let border = String(repeating: "─", count: 80)
    let screen = """
      ✔ Summarized 3 shell commands

      \(historical)

      \(border)
      ❯ 1. First draft line
        2. Second draft line
      \(border)
        DeepSeek-V4.1-Flash · Context 100% left · ~/opt/Prowl ▧ Workspace Edit
      """
    #expect(agent.detectState(in: screen) == .idle)
    #expect(traeBlockerText(in: agent.detectionSnapshot(from: screen)) == nil)
  }

  // MARK: - Clipped live chrome and the title corroboration

  @Test func clippedLiveHeaderKeepingOnlyElapsedChromeReadsAsWorking() throws {
    let agent = try agent()
    // traecli clips live chrome to the pane width before writing it, so a live-block
    // header whose streaming snippet is wide loses its tail: the running footer reaches
    // the terminal as `<glyph> <snippet> (42m 53s • ↑ 183K tokens …`, with neither
    // `esc to interrupt` nor the `/ps` chrome. Reading that frame as a settled composer
    // flipped a running turn to Idle — and earned a spurious Done on an unviewed pane —
    // while the turn was still streaming. The header line below is the one captured live
    // from traecli 0.209.1 at the moment the badge flipped.
    let border = String(repeating: "─", count: 120)
    let clippedHeader =
      "❖ The live block header might be rendered *above* the visible window when the live block is tall "
      + "and the pane is short! (42m 53s • ↑ 183K tokens …"
    let screen = """
      \(clippedHeader)
        └ ■ Fix the false Idle badge
          ◻ Add a regression test
      \(border)
      ❯ Find and fix a bug in @filename
      \(border)
        DeepSeek-V4.1-Flash · Context 64% left · ~/opt/Prowl · feat/traecli-support · +1582 -58  ⛉ Auto Mode
      """
    #expect(agent.detectState(in: screen) == .working)
  }

  @Test func clippedMcpBootLineAboveAnIdleComposerReadsAsIdle() throws {
    let agent = try agent()
    // The MCP boot progress line reuses the interrupt footer, and a narrow pane clips
    // its tail too — leaving the same `<glyph> … (<elapsed> •` remnant as a running
    // turn. The startup exclusion has to cover the clipped form as well, or a cold
    // start would read Working and earn a spurious Done on the settle.
    let border = String(repeating: "─", count: 120)
    let screen = """
      ✦ Starting MCP servers (1/6): XcodeBuildMCP, code-review-graph, mobile-mcp (0s • esc to …
        └ Tip: Press ctrl+r to search your prompt history.
      \(border)
      ❯ Explain this codebase
      \(border)
        DeepSeek-V4.1-Flash (MAX) high · Context 100% left · ~/opt/Prowl ▧ Workspace Edit
      """
    #expect(agent.detectState(in: screen) == .idle)
  }

  @Test func wrappedMcpBootProgressBlockAboveAnIdleComposerReadsAsIdle() throws {
    let agent = try agent()
    // The boot progress line is a logical line: if a terminal wraps it, the
    // `esc to interrupt` footer lands on a row that carries none of the header, and
    // excluding startup per row read the wrapped form as a running turn — a cold start
    // then flashed Working and earned a spurious Done on the settle. The exclusion is
    // applied to the block, so the footer row is recognized as startup chrome.
    let border = String(repeating: "─", count: 120)
    let screen = """
      ✦ Starting MCP servers (1/5): XcodeBuildMCP, code-review-graph, mobile-mcp,
        sentry-mcp (0s • esc to interrupt)
      \(border)
      ❯ Explain this codebase
      \(border)
        DeepSeek-V4.1-Flash (MAX) high · Context 100% left · ~/opt/Prowl ▧ Workspace Edit
      """
    #expect(agent.detectState(in: screen) == .idle)
  }

  @Test func capturedNarrowTerminalBootScreenReadsAsIdle() throws {
    let agent = try agent()
    // Captured from traecli 0.209.1 in a 40-column PTY during startup (the phase counter
    // advanced 0/3 → 1/3 → 2/3 while the spinner glyph rotated). At that width traecli
    // *clips* the progress line instead of wrapping it — the server list ends in `…` and
    // the elapsed/token chrome is gone with the `esc to interrupt` footer — so the screen
    // must read Idle, not Working. The wrapped form above is the defensive case: traecli
    // does not produce it today, and it must not read as a running turn if it ever does.
    let border = String(repeating: "─", count: 40)
    let screen = """
      ◇ Starting MCP servers (0/3): XcodeBuil…
      \(border)
      ❯ Summarize recent commits
      \(border)
        Dee… ▧ Workspace Edit · ← for agents
      """
    #expect(agent.detectState(in: screen) == .idle)
  }

  @Test func proseMentioningElapsedChromeWithoutALiveGlyphStaysIdle() throws {
    let agent = try agent()
    // Only a column-0 live glyph makes a line the live block's header. Prose, tool
    // output, and quoted chrome (`└ Run finished (2s · timeout 2m)`) must not be able
    // to speak for a settled composer, or the badge would stick on Working.
    let border = String(repeating: "─", count: 120)
    let screen = """
      Teardown took (42m 53s • ↑ 183K tokens) in the previous run.

        └ Run finished (2s • timeout 2m)
      \(border)
      ❯ Find and fix a bug in @filename
      \(border)
        DeepSeek-V4.1-Flash · Context 64% left · ~/opt/Prowl · feat/traecli-support · +1582 -58  ⛉ Auto Mode
      """
    #expect(agent.detectState(in: screen) == .idle)
  }

  @Test func titleSpinnerMarksARunningTurn() throws {
    // The TUI animates a braille spinner ahead of the thread title while a turn runs.
    #expect(traeTitleShowsRunningTurn("⠋ 排查修复traecli状态显示异常 | Prowl"))
    #expect(traeTitleShowsRunningTurn("⠸ Fix iOS H5 input keyboard issue | CBrain-S"))
    // Settled turns, unnamed threads, and shells carry no spinner.
    #expect(!traeTitleShowsRunningTurn("排查修复traecli状态显示异常 | Prowl"))
    #expect(!traeTitleShowsRunningTurn("Run tick loop and report ticks | trae-scrolltest"))
    #expect(!traeTitleShowsRunningTurn(""))
    #expect(!traeTitleShowsRunningTurn(nil))
    // A braille glyph anywhere but the front is not the running mark.
    #expect(!traeTitleShowsRunningTurn("Fix ⠋ the spinner"))
  }

  @Test func titleSpinnerCorroboratesAnIdleScreenVerdict() throws {
    let agent = try agent()
    let idle = AgentScreenDetection(state: .idle, reason: .legacyDetector)
    let working = AgentScreenDetection(state: .working, reason: .legacyDetector)
    let blocked = AgentScreenDetection(state: .blocked, reason: .legacyDetector)

    let corroborated = WorktreeTerminalState.corroboratedScreenDetection(
      idle, agent: agent, title: "⠋ Fix the false Idle badge | Prowl")
    #expect(corroborated.state == .working)
    #expect(corroborated.reason == .titleSpinner)

    // A settled title leaves the screen verdict alone, whatever it says.
    #expect(
      WorktreeTerminalState.corroboratedScreenDetection(
        idle, agent: agent, title: "Fix the false Idle badge | Prowl") == idle)
    #expect(
      WorktreeTerminalState.corroboratedScreenDetection(
        working, agent: agent, title: "⠋ Fix the false Idle badge | Prowl") == working)
    // A dialog the screen reports stays reported while the turn keeps running.
    #expect(
      WorktreeTerminalState.corroboratedScreenDetection(
        blocked, agent: agent, title: "⠋ Fix the false Idle badge | Prowl") == blocked)
    // The corroboration is traecli's: another agent's title spinner is not evidence.
    #expect(
      WorktreeTerminalState.corroboratedScreenDetection(
        idle, agent: .codex, title: "⠋ Codex | Prowl") == idle)
  }

  // MARK: - Public 0.209.1 captures

  // The screens below were captured from the public traecli 0.209.1 build in a Prowl pane
  // (`prowl read --source detection`). The public build renders its dialog footers as
  // `<key> <action>` hints joined by `  |  `, not the `enter to submit | esc to cancel`
  // form of the on-prem build.

  private static let publicStatusBar =
    "  gpt-oss:20b medium · Context 100% left · /private/tmp/proj ▧ Workspace Edit · ← for agents"

  @Test func publicApprovalBlockerTextKeepsTheCommandOptionsAndFooter() throws {
    let agent = try agent()
    let border = String(repeating: "─", count: 140)
    let screen = """
      ▍ approve


      ◆ Running echo approved-run > /tmp/prowl-trae-approve.txt

      \(border)

        Would you like to run the following command?

        Reason: Write a marker file outside the sandbox

        $ echo approved-run > /tmp/prowl-trae-approve.txt

      ❯ 1. Yes, proceed (y)
        2. Yes, switch this session to auto mode (r)
        3. Yes, switch this session to full access mode (f)
        4. Yes, and don't ask again for commands that start with `echo approved-run > /tmp/prowl-trae-approve.txt` (p)
        5. No, and tell TRAE CLI what to do differently (esc)

        enter confirm  |  esc cancel
      """
    #expect(agent.detectState(in: screen) == .blocked)
    let text = try #require(traeBlockerText(in: agent.detectionSnapshot(from: screen)))
    #expect(text.hasPrefix("Would you like to run the following command?"))
    #expect(text.contains("$ echo approved-run > /tmp/prowl-trae-approve.txt"))
    #expect(text.contains("❯ 1. Yes, proceed (y)"))
    #expect(text.hasSuffix("enter confirm  |  esc cancel"))
  }

  @Test func publicQuestionBlockerTextKeepsTheFooter() throws {
    let agent = try agent()
    let border = String(repeating: "─", count: 140)
    let screen = """
      ▍ ask


      \(border)

        Question 1/1 (1 unanswered)
        Which color should the button use?

        ❯ 1. Blue               The system accent
          2. Green              A success tone
          3. Red                A warning tone
          4. None of the above  Optionally, add details in notes (tab).

        tab add notes  |  enter submit answer  |  esc interrupt
      """
    #expect(agent.detectState(in: screen) == .blocked)
    let text = try #require(traeBlockerText(in: agent.detectionSnapshot(from: screen)))
    #expect(text.hasPrefix("Question 1/1 (1 unanswered)"))
    #expect(text.hasSuffix("tab add notes  |  enter submit answer  |  esc interrupt"))
  }

  @Test func publicTrustBlockerTextLeavesTheWelcomeBannerOut() throws {
    let agent = try agent()
    // The first-run trust prompt renders at column 0 under the welcome banner, with no
    // other chrome between them, so the dialog region must stop at the banner.
    let screen = """
      ████████ ████████   ███████  ████████    ██████ ██      ██
         ██    ██     ██ ██    ██  ██         ██      ██      ██
         ██    ████████  ████████  ██████     ██      ██      ██
         ██    ██     ██ ██    ██  ████████    ██████ ██████  ██

        Welcome to TRAE CLI — your intelligent coding companion


        Folder access
        /private/tmp/proj

        Do you trust the contents of this directory? Working with untrusted contents comes with
        higher risk of prompt injection.

      ❯ 1. Yes, continue
        2. No, quit

        enter continue  |  esc quit
      """
    #expect(agent.detectState(in: screen) == .blocked)
    let text = try #require(traeBlockerText(in: agent.detectionSnapshot(from: screen)))
    #expect(text.hasPrefix("Folder access"))
    #expect(text.contains("Do you trust the contents of this directory?"))
    #expect(text.hasSuffix("enter continue  |  esc quit"))
    #expect(!text.contains("█"))
    #expect(!text.contains("Welcome to TRAE CLI"))
  }

  @Test func publicFooterWithoutOptionsReadsAsBlocked() throws {
    let agent = try agent()
    // A free-form field has no option rows; its key-hint footer is the dialog's chrome.
    let border = String(repeating: "─", count: 140)
    let screen = """
      \(border)

        Question 1/1 (1 unanswered)
        What should the new file be called?

        enter submit answer  |  esc interrupt
      """
    #expect(agent.detectState(in: screen) == .blocked)
  }

  @Test func keyHintsWithoutEnterAndEscStayUnknown() throws {
    let agent = try agent()
    // The transcript pager's footer is key hints too, but it is not a dialog.
    let border = String(repeating: "─", count: 140)
    let screen = """
      ▍ plan8 slow20
      \(border) 100% ─
       ↑/↓ scroll  |  ctrl+b/ctrl+f page  |  home/end jump  |  ←/→ prompts
       q quit  |  esc/← edit prev  |  / search
      """
    #expect(agent.detectState(in: screen) == .unknown)
  }

  @Test func narrowPaneFooterClippedAfterItsBulletReadsAsWorking() throws {
    let agent = try agent()
    // A 20-column pane: traecli clips the running footer right after the elapsed-time
    // bullet, and the status bar loses its signature.
    let screen = """
      ▍ 20


      ✦ Working… (2s •…
       word0 word1 w… ─
      ❯ Explain this c
      ─────────────────
        ▧ Workspace Edi
      """
    #expect(agent.detectState(in: screen) == .working)
  }

  @Test func publicIdleComposerUnderABackgroundShellReadsAsIdle() throws {
    let agent = try agent()
    let border = String(repeating: "─", count: 140)
    let screen = """
        Worked for <1s • 23:22

      ◈ 1 background shell running… you can still chat · /ps to manage
      \(String(repeating: "─", count: 100)) word0 word1 word2 word3 word4 word5 ─
      ❯ Explain this codebase
      \(border)
      \(Self.publicStatusBar)
      """
    #expect(agent.detectState(in: screen) == .idle)
  }
}
