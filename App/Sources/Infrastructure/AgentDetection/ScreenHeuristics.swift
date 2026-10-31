import Foundation

nonisolated let agentDetectionRecentLineLimit = 24
nonisolated let piAgentDetectionRecentLineLimit = 32

extension DetectedAgent {
  nonisolated func detectState(in screen: String) -> AgentRawState {
    detectScreen(in: screen).state
  }

  /// The slice of the active screen this agent's detector consumes.
  ///
  /// Claude reads the full active screen: its rules are region-anchored (the
  /// live status block is walked bottom-up from the composer by row shape,
  /// blockers around the prompt, viewer chrome from the bottom lines), so a
  /// bottom-measured line budget added no false-positive guard — it only cut
  /// the live signal off when a long todo list plus a multi-line status line
  /// pushed the spinner row past the limit and a working agent read as idle.
  ///
  /// Antigravity reads the full screen for the same reason: its detector anchors
  /// on the live composer box by shape and ignores everything below the status
  /// row, so a tail budget only let a long `stack_with_default` status script
  /// push the composer out of the slice and turn a working pane unknown.
  ///
  /// TraeCode CLI reads the full screen too: its running indicator heads a
  /// blank-bounded live block whose todo checklist grows without bound, so a tail
  /// budget let a tall plan push the hint out of the slice and read a running turn
  /// as idle. Its detector anchors on the bottom-most composer box by shape, so the
  /// rest of the viewport cannot speak for the live state.
  ///
  /// Every other detector keeps a bounded tail as its guard against transcript
  /// history. Pi retains 32 non-blank lines so pi-subagents' adaptive widget can
  /// keep its header and live job row together; the remaining detectors keep 24.
  /// For the legacy scanners the tail is load-bearing — they match with whole-text
  /// scans. Codex's structured profile anchors its windows inside the tail instead;
  /// it shares Claude's bounded-bottom exposure in principle and keeps the tail
  /// until its regions are bounded by shape the same way.
  nonisolated func detectionScreenText(from screen: String) -> String {
    switch self {
    case .claude, .antigravity, .trae:
      screen
    case .pi:
      agentDetectionRecentLines(screen, limit: piAgentDetectionRecentLineLimit)
    default:
      agentDetectionRecentText(screen)
    }
  }

  /// The one production entry point for building a profile snapshot. State
  /// detection and blocker extraction must read the same slice; going through
  /// this keeps a call site from pairing a profile with the wrong one.
  nonisolated func detectionSnapshot(from screen: String) -> AgentScreenSnapshot {
    AgentScreenSnapshot(text: detectionScreenText(from: screen))
  }

  nonisolated func detectScreen(in screen: String) -> AgentScreenDetection {
    let text = detectionScreenText(from: screen)
    switch self {
    case .claude:
      return ClaudeScreenProfile.detect(in: AgentScreenSnapshot(text: text))
    case .codex:
      return CodexScreenProfile.detect(in: AgentScreenSnapshot(text: text))
    case .devin:
      return DevinScreenProfile.detect(in: AgentScreenSnapshot(text: text))
    default:
      return AgentScreenDetection(state: detectLegacyScreen(text), reason: .legacyDetector)
    }
  }

  private nonisolated func detectLegacyScreen(_ text: String) -> AgentRawState {
    switch self {
    case .pi: detectPi(text)
    case .omp: detectOMP(text)
    case .gemini: detectGemini(text)
    case .cursor: detectCursor(text)
    case .cline: detectCline(text)
    case .opencode: detectOpenCode(text)
    case .copilot: detectCopilot(text)
    case .kimi: detectKimi(text)
    case .droid: detectDroid(text)
    default: detectLegacyScreenTail(text)
    }
  }

  // Split across two switches so each stays within the complexity budget:
  // claude/codex/devin are dispatched by `detectScreen` before reaching here,
  // so they fall through the tail to `.unknown`.
  private nonisolated func detectLegacyScreenTail(_ text: String) -> AgentRawState {
    switch self {
    case .amp: detectAmp(text)
    case .qoder: detectQoder(text)
    case .qwen: detectQwen(text)
    case .grok: detectGrok(text)
    case .antigravity: detectAntigravity(text)
    case .trae: detectTrae(text)
    default: .unknown
    }
  }
}

nonisolated func agentDetectionRecentText(_ content: String) -> String {
  agentDetectionRecentLines(content, limit: agentDetectionRecentLineLimit)
}

nonisolated func agentDetectionRecentLines(_ content: String, limit: Int) -> String {
  let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  var remainingNonBlankLines = limit
  var startIndex = lines.startIndex

  for index in lines.indices.reversed() {
    guard !lines[index].trimmingCharacters(in: .whitespaces).isEmpty else {
      continue
    }
    remainingNonBlankLines -= 1
    if remainingNonBlankLines == 0 {
      startIndex = index
      break
    }
  }

  return lines[startIndex...].joined(separator: "\n")
}

nonisolated private func detectPi(_ content: String) -> AgentRawState {
  let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map {
    $0.trimmingCharacters(in: .whitespaces)
  }
  let liveFooterLines = lines.filter { !$0.isEmpty }.suffix(5)
  return lines.contains(where: isPiWorkingText)
    || liveFooterLines.contains(where: isPiFramedWorkingFooter)
    || hasPiRunningAsyncSubagentCard(lines)
    ? .working
    : .idle
}

nonisolated private func hasPiRunningAsyncSubagentCard(_ lines: [String]) -> Bool {
  if lines.contains(where: isPiAdaptiveAsyncSubagentRunningLine) {
    return true
  }
  guard lines.count >= 2 else { return false }

  return lines.indices.dropLast().contains { index in
    guard let headerName = piAsyncSubagentName(from: lines[index]) else { return false }
    return isPiAsyncSubagentJobLine(lines[index + 1], matching: headerName)
  }
}

nonisolated private func piAsyncSubagentName(from header: String) -> (name: String, isPrefix: Bool)? {
  let prefix = "async subagent "
  let suffix = " · background"
  guard header.hasPrefix(prefix) else { return nil }

  let title: Substring
  let isPrefix: Bool
  if header.hasSuffix(suffix) {
    title = header.dropFirst(prefix.count).dropLast(suffix.count)
    isPrefix = false
  } else {
    guard header.hasSuffix("…") else { return nil }
    let truncatedTitle = header.dropFirst(prefix.count).dropLast()
    if let separator = truncatedTitle.range(of: " ·") {
      title = truncatedTitle[..<separator.lowerBound]
      isPrefix = false
    } else {
      title = truncatedTitle
      isPrefix = true
    }
  }

  let components = title.split(separator: " ")
  let countToken = components.last
  let completeCount = countToken?.dropFirst().dropLast()
  let hasCompleteCount =
    countToken?.first == "("
    && countToken?.last == ")"
    && completeCount?.isEmpty == false
    && completeCount?.allSatisfy(\.isNumber) == true
  let partialCount = countToken?.dropFirst()
  let hasTruncatedCount =
    isPrefix
    && countToken?.first == "("
    && countToken?.last != ")"
    && partialCount?.allSatisfy(\.isNumber) == true
  let hasTrailingCount = hasCompleteCount || hasTruncatedCount
  let name = hasTrailingCount ? components.dropLast().joined(separator: " ") : String(title)
  let nameIsPrefix = isPrefix && !hasTrailingCount
  return name.contains(where: \.isLetter) ? (name, nameIsPrefix) : nil
}

nonisolated private func isPiAsyncSubagentJobLine(
  _ line: String,
  matching headerName: (name: String, isPrefix: Bool)
) -> Bool {
  guard let content = labeledBrailleSpinnerContent(line), content.hasPrefix(headerName.name) else { return false }
  if headerName.isPrefix {
    return true
  }

  let remainder = content.dropFirst(headerName.name.count)
  if remainder.isEmpty || remainder.hasPrefix(" ·") {
    return true
  }
  return [" [fresh]", " [fork]", " [mixed]"].contains { badge in
    remainder == badge || remainder.hasPrefix("\(badge) ·")
  }
}

nonisolated private func isPiAdaptiveAsyncSubagentRunningLine(_ line: String) -> Bool {
  guard let content = labeledBrailleSpinnerContent(line) else { return false }
  if content.hasSuffix("…") {
    let visiblePrefix = content.dropLast()
    if visiblePrefix.hasPrefix("subagents (") || visiblePrefix.hasPrefix("Async agents · ") {
      return true
    }
  }
  if content == "Async agents · background" {
    return true
  }
  if content.hasPrefix("Async agents · ") {
    return isPiProgressiveAsyncSummary(String(content.dropFirst("Async agents · ".count)))
  }
  return isPiSingleLineAsyncSummary(content)
}

nonisolated private func isPiProgressiveAsyncSummary(_ summary: String) -> Bool {
  let components = summary.split(separator: " ", maxSplits: 2)
  guard components.count == 3,
    let count = Int(components[0]),
    count > 0,
    components[1] == (count == 1 ? "agent" : "agents")
  else {
    return false
  }

  let state = components[2]
  if state == "running" {
    return true
  }
  guard state.hasPrefix("running, ") else { return false }
  return isPiAsyncCountStatus(state.dropFirst("running, ".count), expected: "queued")
}

nonisolated private func isPiSingleLineAsyncSummary(_ content: String) -> Bool {
  let prefix = "subagents ("
  guard content.hasPrefix(prefix), content.hasSuffix(")") else { return false }

  let summary = content.dropFirst(prefix.count).dropLast()
  let components = summary.split(separator: ",", omittingEmptySubsequences: false)
  guard let runningSummary = components.first else { return false }
  let running = runningSummary.split(separator: " ")
  guard running.count == 2, running[1] == "running" else { return false }

  let counts = running[0].split(separator: "/", omittingEmptySubsequences: false)
  guard counts.count == 2,
    let activeCount = Int(counts[0]),
    let totalCount = Int(counts[1]),
    activeCount > 0,
    totalCount >= activeCount
  else {
    return false
  }

  let terminalStates = ["queued", "failed", "stopped", "paused"]
  return components.dropFirst().allSatisfy { component in
    terminalStates.contains { state in
      isPiAsyncCountStatus(component.drop(while: \.isWhitespace), expected: state)
    }
  }
}

nonisolated private func isPiAsyncCountStatus(_ summary: Substring, expected: String) -> Bool {
  let components = summary.split(separator: " ")
  return components.count == 2
    && Int(components[0]).map { $0 > 0 } == true
    && components[1] == Substring(expected)
}

nonisolated private func detectOMP(_ content: String) -> AgentRawState {
  if hasOMPAskPrompt(content) {
    return .blocked
  }
  return hasOMPWorkingLine(content) ? .working : .idle
}

nonisolated private func hasOMPAskPrompt(_ content: String) -> Bool {
  let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
  return lines.contains { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.contains("Enter select") && trimmed.contains("Esc cancel")
  }
}

nonisolated private func hasOMPWorkingLine(_ content: String) -> Bool {
  let lines = content.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty }
  if lines.contains(where: { isPiWorkingText($0) || hasOMPInterruptHint($0) || hasLabeledBrailleSpinner($0) }) {
    return true
  }
  let composerHeaderIndex = ompLiveBoxComposerHeaderIndex(lines)
  if let composerHeaderIndex, ompBoxComposerHeaderHasSpinner(lines[composerHeaderIndex]) {
    return true
  }
  return ompLoaderCandidateRows(lines, composerHeaderIndex: composerHeaderIndex).contains(where: isOMPLoaderRow)
}

/// OMP's loader row leads with the theme's Esc glyph (the interrupt key) and shows the
/// model's self-reported intent: `Working…` before the first token, then free text such as
/// `Running requested command` or `等待命令完成` while a tool runs. The vocabulary is
/// unbounded, so any label counts; the row is only read near the composer.
nonisolated private func isOMPLoaderRow(_ line: String) -> Bool {
  let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
  guard parts.count == 2, ompEscapeGlyphs.contains(String(parts[0])) else { return false }
  return parts[1].contains(where: \.isLetter)
}

nonisolated private let ompEscapeGlyphs: Set<String> = ["󱊷", "⎋", "esc"]

/// The rows that can hold the live loader: the bottom of the screen, plus the rows directly
/// above the live `box` composer, whose queued draft can grow to 18 rows and push the loader
/// out of a bottom-anchored window.
nonisolated private func ompLoaderCandidateRows(_ lines: [String], composerHeaderIndex: Int?) -> [String] {
  var rows = Array(lines.suffix(5))
  if let composerHeaderIndex {
    rows += lines[..<composerHeaderIndex].suffix(5)
  }
  return rows
}

/// The live `box` composer is the last `╭` row that closes the screen: every row after it is
/// a `│` input row and the final row is the `╰` bottom row. That shape covers a one-line
/// prompt (`╭ … ╮` over `╰─ … ─╯`), a multiline draft, and the IME-safe layout that moves the
/// bottom border to its own row. Transcript text after a `╰` row marks a tool box or a quoted
/// frame instead, so an older frame never speaks for a newer composer.
nonisolated private func ompLiveBoxComposerHeaderIndex(_ lines: [String]) -> Int? {
  guard let headerIndex = lines.lastIndex(where: { $0.hasPrefix("╭") }),
    let bottom = lines.last, bottom.hasPrefix("╰"), headerIndex < lines.count - 1
  else { return nil }
  let inputRows = lines[(headerIndex + 1)...].dropLast()
  return inputRows.allSatisfy { $0.hasPrefix("│") } ? headerIndex : nil
}

/// While a turn runs, OMP's status line replaces its brand glyph with a braille spinner and
/// a turn timer (`⠋ 9s`). The `box` composer embeds that status line in its top border,
/// right after the `╭──` run; the other composer shapes start a status row with it, which the
/// leading-spinner rule already reads.
nonisolated private func ompBoxComposerHeaderHasSpinner(_ header: String) -> Bool {
  let status = header.drop(while: { $0 == "╭" || $0 == "─" || $0 == " " })
  return labeledBrailleSpinnerContent(String(status)) != nil
}

nonisolated private let piWorkingMessages: Set<String> = ["Working...", "Working…", "Interrupting…"]

nonisolated private func isPiWorkingText(_ line: String) -> Bool {
  if piWorkingMessages.contains(line) {
    return true
  }

  guard let spinner = line.unicodeScalars.first,
    (0x2800...0x28FF).contains(Int(spinner.value))
  else {
    return false
  }
  let message = String(line.unicodeScalars.dropFirst()).trimmingCharacters(in: .whitespaces)
  return piWorkingMessages.contains(message)
}

nonisolated private func isPiFramedWorkingFooter(_ line: String) -> Bool {
  guard line.hasPrefix("── "), line.hasSuffix("──") else { return false }
  let content = line.trimmingCharacters(in: CharacterSet(charactersIn: "─ "))
  return labeledBrailleSpinnerContent(content) == "Working"
}

nonisolated private func hasOMPInterruptHint(_ line: String) -> Bool {
  let interruptHints = ["⟦esc⟧", "⟨esc⟩", "[esc]"]
  return interruptHints.contains { hint in
    guard line.hasSuffix(hint) else { return false }
    return !line.dropLast(hint.count).trimmingCharacters(in: .whitespaces).isEmpty
  }
}

nonisolated private func hasLabeledBrailleSpinner(_ line: String) -> Bool {
  labeledBrailleSpinnerContent(line) != nil
}

nonisolated private func labeledBrailleSpinnerContent(_ line: String) -> String? {
  guard let first = line.unicodeScalars.first,
    (0x2800...0x28FF).contains(Int(first.value))
  else {
    return nil
  }

  let rest = String(line.unicodeScalars.dropFirst())
  guard rest.hasPrefix(" ") else { return nil }
  let content = rest.dropFirst().trimmingCharacters(in: .whitespaces)
  return content.contains(where: \.isLetter) ? content : nil
}

nonisolated private func detectGemini(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  if lower.contains("waiting for user confirmation")
    || content.contains("│ Apply this change")
    || content.contains("│ Allow execution")
    || content.contains("│ Do you want to proceed")
    || hasConfirmationPrompt(lower)
  {
    return .blocked
  }
  if lower.contains("esc to cancel") {
    return .working
  }
  return .idle
}

nonisolated private func detectCursor(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  if lower.contains("workspace trust required")
    || lower.contains("trust this workspace")
    || hasCursorPermissionPrompt(content: content, lower: lower)
  {
    return .blocked
  }
  if lower.contains("trusting workspace") || lower.contains("ctrl+c to stop") || hasCursorSpinner(content) {
    return .working
  }
  return .idle
}

nonisolated private func detectCline(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  if lower.contains("let cline use this tool")
    || ((lower.contains("[act mode]") || lower.contains("[plan mode]")) && lower.contains("yes"))
    || hasClineNumberedChoicePrompt(content)
  {
    return .blocked
  }
  if hasInterruptPattern(lower) {
    return .working
  }
  return .idle
}

nonisolated private func detectOpenCode(_ content: String) -> AgentRawState {
  if content.contains("△ Permission required")
    || hasOpenCodeQuestionPrompt(content)
  {
    return .blocked
  }
  if hasInterruptPattern(content.lowercased()) {
    return .working
  }
  return .idle
}

nonisolated private func detectCopilot(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  let lines = lower.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty }
  if hasCopilotSelectionPrompt(lines)
    || lower.contains("│ do you want")
    || (lower.contains("confirm with") && lower.contains("enter"))
  {
    return .blocked
  }
  let hasWorkingFooter = lines.suffix(5).contains(where: isCopilotWorkingFooter)
  if hasWorkingFooter || lower.contains("esc to cancel") {
    return .working
  }
  return .idle
}

nonisolated private func isCopilotWorkingFooter(_ line: String) -> Bool {
  // Copilot 1.0.83 uses these frames in its normal and alternate-screen animations.
  // Streaming response size is optional and appears before the interrupt shortcut.
  let pattern = #"^[∙∘○◎◉]\s+working(?:\s+·\s+\d+(?:\.\d+)?\s+[kmgt]?i?b)?\s+esc\s+interrupt(?:\s|$)"#
  return line.range(of: pattern, options: .regularExpression) != nil
}

nonisolated private func hasCopilotSelectionPrompt(_ lines: [String]) -> Bool {
  // The trust/permission picker shares "esc to cancel" with the legacy working footer.
  // Require live dialog chrome so a completed choice in transcript history does not block.
  guard lines.last?.hasPrefix("╰") == true,
    lines.suffix(3).contains(where: { $0.contains("enter to select") && $0.contains("esc to cancel") })
  else { return false }
  return lines.suffix(16).contains { line in
    line.range(of: #"^│\s*❯\s*\d+\."#, options: .regularExpression) != nil
  }
}

nonisolated private func detectKimi(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  let blockedPatterns = [
    "allow?", "confirm?", "approve?", "proceed?", "[y/n]", "(y/n)",
  ]
  if blockedPatterns.contains(where: lower.contains)
    || hasConfirmationPrompt(lower)
    || hasKimiApprovalPanel(content: content, lower: lower)
  {
    return .blocked
  }

  let workingPatterns = [
    "thinking", "processing", "generating", "waiting for response", "ctrl+c to cancel", "ctrl-c to cancel",
  ]
  if workingPatterns.contains(where: lower.contains)
    || hasKimiMoonSpinner(content)
    || hasKimiToolSpinner(content: content, lower: lower)
  {
    return .working
  }
  return .idle
}

nonisolated private func detectDroid(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  let hasExecute = content.contains("EXECUTE")
  let hasSelectionChrome =
    lower.contains("enter to select")
    || lower.contains("↑↓ to navigate")
    || lower.contains("esc to cancel")
  let hasSelectionOptions =
    lower.contains("> yes, allow")
    || lower.contains("> no, cancel")

  if hasExecute && (hasSelectionChrome || hasSelectionOptions) {
    return .blocked
  }
  if hasSelectionChrome && hasSelectionOptions {
    return .blocked
  }
  if hasDroidSpinner(content) || lower.contains("esc to stop") {
    return .working
  }
  return .idle
}

// Amp (0.0.1791547250) is a full-screen TUI whose composer box owns the bottom
// rows: `╭───… ─ <mode> ─╮`, `│ … │` rows, and a bottom border
// `╰ <spinner> <status> ───… <path> (<branch>) ─╯`. The status is the thread
// client's live state — `Connecting`, `Sending`, `Waiting`, `Thinking`,
// `Streaming`, `Streaming 45 tok`, `Running Tools`, … — behind a spinner that
// cycles `∼`, `≈`, `≋`; an idle composer leaves the border bare. Any status is
// Working: the label set is open (a token counter trails `Streaming`, a
// half-painted frame reads `Streami Too`), while the bare border is the only
// idle shape, so an allowlist flaps on every frame it misses. `Disconnected` and
// `Amp Is Redeploying` (the two labels in Amp's table that are not turn
// progress) retain the prior state. Approval and feedback dialogs render as a
// separate box directly above the composer — `╭─ Approval Required ─…─╮` with
// `‣`-marked option rows, `╭─ Tell Amp what to do differently ─…─╮` with a `>`
// input row — while the border keeps `Running Tools`, so the dialog read runs
// first; the `Out of Credits` dialog puts its `‣` rows inside the composer
// itself. A screen without a complete composer (startup, a viewer, a redraw
// caught mid-frame) is unknown so the state machine keeps the prior state;
// there is no older Amp UI to fall back to, because the service refuses to
// start threads from a stale CLI.
nonisolated private func detectAmp(_ content: String) -> AgentRawState {
  // Blank rows carry nothing here (every box row has borders), and dropping
  // them also discards trailing whitespace-only screen rows below the footer.
  let lines = content.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty }
  let isTop = { (line: String) -> Bool in line.hasPrefix("╭─") && line.hasSuffix("╮") }
  let isBottom = { (line: String) -> Bool in line.hasPrefix("╰") && line.hasSuffix("╯") }
  let isInterior = { (line: String) -> Bool in line.hasPrefix("│") && line.hasSuffix("│") }
  let isSelection = { (line: String) -> Bool in line.hasPrefix("│ ‣ ") }

  guard let footer = lines.indices.last, isBottom(lines[footer]) else { return .unknown }
  var composerTop = footer - 1
  while composerTop >= 0, isInterior(lines[composerTop]) {
    composerTop -= 1
  }
  guard composerTop >= 0, isTop(lines[composerTop]), composerTop < footer - 1 else { return .unknown }

  if lines[(composerTop + 1)..<footer].contains(where: isSelection) {
    return .blocked
  }

  // A box whose bottom border touches the composer's top border is a dialog
  // when it is titled as one or carries a selection row; a long command can
  // push the title above the detection window, so the rows alone suffice.
  if composerTop > 0, isBottom(lines[composerTop - 1]) {
    var dialogTop = composerTop - 2
    var hasSelection = false
    while dialogTop >= 0, isInterior(lines[dialogTop]) {
      hasSelection = hasSelection || isSelection(lines[dialogTop])
      dialogTop -= 1
    }
    let dialogTitles = ["╭─ Approval Required ", "╭─ Tell Amp what to do differently "]
    let title = dialogTop >= 0 && isTop(lines[dialogTop]) ? lines[dialogTop] : ""
    if hasSelection || dialogTitles.contains(where: { title.hasPrefix($0) }) {
      return .blocked
    }
  }

  let status = lines[footer].dropFirst().prefix { $0 != "─" }
    .trimmingCharacters(in: CharacterSet(charactersIn: " ∼≈≋"))
  if status.isEmpty {
    return .idle
  }
  if status == "Disconnected" || status == "Amp Is Redeploying" {
    return .unknown
  }
  return .working
}

nonisolated func isNumberedChoice(_ option: String) -> Bool {
  guard let firstToken = option.split(whereSeparator: { $0.isWhitespace }).first,
    firstToken.last == "."
  else {
    return false
  }
  let number = firstToken.dropLast()
  return !number.isEmpty && number.allSatisfy(\.isNumber)
}

nonisolated private func hasCursorPermissionPrompt(content: String, lower: String) -> Bool {
  if lower.contains("(y) (enter)") {
    return true
  }

  let hasPermissionHeader =
    lower.contains("run this command?")
    || lower.contains("run command?")
    || lower.contains("not in allowlist")
    || lower.contains("to allowlist?")
    || lower.contains("allow execution")
  guard hasPermissionHeader else { return false }

  let hasConfirmAction = content.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
    guard trimmed.contains("(y)") else { return false }
    return trimmed.contains("run") || trimmed.contains("allow")
  }
  let hasCancelAction =
    lower.contains("skip (esc or n)")
    || lower.contains("keep (n)")

  return hasConfirmAction || hasCancelAction
}

nonisolated private func hasClineNumberedChoicePrompt(_ content: String) -> Bool {
  content.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
    guard let suffix = line.range(of: " or type)") else { return false }
    let prefix = line[..<suffix.lowerBound]
    guard let openParen = prefix.lastIndex(of: "(") else { return false }
    let between = prefix[prefix.index(after: openParen)...]
    return between.contains("-") && between.allSatisfy { $0.isNumber || $0 == "-" }
  }
}

nonisolated private func hasKimiApprovalPanel(content: String, lower: String) -> Bool {
  lower.contains("requesting approval")
    || (lower.contains("approve once") && lower.contains("approve for this session") && lower.contains("reject"))
    || (content.contains("─ approval") && content.contains("↵ confirm"))
}

nonisolated private func hasKimiMoonSpinner(_ content: String) -> Bool {
  let moonSpinners: Set<Character> = ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"]
  return content.contains { moonSpinners.contains($0) }
}

nonisolated private func hasKimiToolSpinner(content: String, lower: String) -> Bool {
  guard lower.contains("using ") else { return false }
  return content.split(separator: "\n").contains { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.unicodeScalars.first else { return false }
    return (0x2800...0x28FF).contains(Int(first.value))
  }
}

nonisolated func hasConfirmationPrompt(_ lower: String) -> Bool {
  guard
    let range = lower.range(of: "do you want") ?? lower.range(of: "would you like")
  else {
    return false
  }
  let after = lower[range.lowerBound...]
  return after.contains("yes") || after.contains("❯")
}

nonisolated private func hasInterruptPattern(_ lower: String) -> Bool {
  lower.contains("esc to interrupt")
    || lower.contains("ctrl+c to interrupt")
    || (lower.contains("esc") && lower.contains("interrupt"))
}

private nonisolated let agentSpinnerScalars: Set<UnicodeScalar> = [
  "·", "✱", "✲", "✳", "✴", "✵", "✶", "✷", "✸", "✹", "✺", "✻", "✼", "✽", "✾", "✿",
  "❀", "❁", "❂", "❃", "❇", "❈", "❉", "❊", "❋", "✢", "✣", "✤", "✥", "✦", "✧", "✨",
  "⊛", "⊕", "⊙", "◉", "◎", "◍", "⁂", "⁕", "※", "⍟", "☼", "★", "☆",
]

nonisolated func isAgentSpinnerScalar(_ scalar: UnicodeScalar) -> Bool {
  agentSpinnerScalars.contains(scalar)
}

nonisolated func hasSpinnerActivity(_ content: String) -> Bool {
  content.split(separator: "\n").contains { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.unicodeScalars.first else { return false }
    let rest = String(trimmed.unicodeScalars.dropFirst())
    return isAgentSpinnerScalar(first)
      && rest.hasPrefix(" ")
      && rest.contains("…")
      && rest.contains(where: \.isLetter)
  }
}

nonisolated private func hasCursorSpinner(_ content: String) -> Bool {
  content.split(separator: "\n").contains { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
    return (trimmed.hasPrefix("⬡") || trimmed.hasPrefix("⬢")) && trimmed.contains("ing")
  }
}

nonisolated private func hasDroidSpinner(_ content: String) -> Bool {
  content.split(separator: "\n").contains { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
    guard let first = trimmed.unicodeScalars.first else { return false }
    return (0x2800...0x28FF).contains(Int(first.value)) && trimmed.contains("esc to stop")
  }
}

nonisolated private func hasOpenCodeQuestionPrompt(_ content: String) -> Bool {
  let lower = content.lowercased()
  let hasEnterAction =
    lower.contains("enter confirm")
    || lower.contains("enter submit")
    || lower.contains("enter toggle")
  let hasQuestionNavigation =
    content.contains("↑↓ select")
    || content.contains("⇆ tab")

  return lower.contains("esc dismiss") && hasEnterAction && hasQuestionNavigation
}

nonisolated private func detectQwen(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  if lower.contains("waiting for user confirmation")
    || lower.contains("do you want to proceed?")
    || hasConfirmationPrompt(lower)
  {
    return .blocked
  }
  if lower.contains("esc to cancel")
    || lower.contains("ctrl+c to cancel")
    || hasBrailleSpinner(content)
  {
    return .working
  }
  return .idle
}

// Qoder CLI (verified 1.0.48, live session): blocked dialogs are ephemeral
// overlays that vanish once answered, so full-window matching is safe.
// Permission menus always pair "Allow once" with "Reject and type something"
// (the second row varies by tool: "Allow for this session" for edits,
// "Always allow \"<cmd>\" for future sessions" for exec/MCP). Ask-user
// questions render an "Asking User" header with a fixed "Type Something"
// row; the plan-ready dialog pairs "Yes, start executing" with "Reject
// plan". An active turn shows a braille spinner footer ending in
// "(esc to cancel, <elapsed>)". Multi-token matches only — single labels
// like "Allow once" or "No" can appear in transcript text.
nonisolated private func detectQoder(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  if hasQoderPermissionMenu(lower) || hasQoderQuestionPrompt(lower) || hasQoderPlanReadyPrompt(lower) {
    return .blocked
  }
  if hasQoderWorkingFooter(content) {
    return .working
  }
  return .idle
}

nonisolated private func hasQoderPermissionMenu(_ lower: String) -> Bool {
  lower.contains("allow once") && lower.contains("reject and type something")
}

nonisolated private func hasQoderQuestionPrompt(_ lower: String) -> Bool {
  lower.contains("asking user") && lower.contains("type something")
}

nonisolated private func hasQoderPlanReadyPrompt(_ lower: String) -> Bool {
  lower.contains("yes, start executing") && lower.contains("reject plan")
}

nonisolated private func hasQoderWorkingFooter(_ content: String) -> Bool {
  content.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.unicodeScalars.first else { return false }
    return (0x2800...0x28FF).contains(Int(first.value))
      && trimmed.lowercased().contains("(esc to cancel,")
  }
}

// Grok Build (verified 0.2.101): cancel mid-turn is Ctrl+C (Esc is a no-op).
// Approval dialogs pair numbered yes-rows ("Yes, proceed", "Yes, allow all
// edits during this session") with a reject row ("No, reject (type to add
// feedback)") above a "Ctrl+o:always-approve" footer; ask-user dialogs render
// "Waiting on answers for …" with a "Type your answer here" row. Working
// turns show a braille spinner line ("⠧ Thinking… 0.2s"). Multi-token matches
// only — single words like "approve" or "loading" appear in transcript text.
nonisolated private func detectGrok(_ content: String) -> AgentRawState {
  if hasGrokPermissionPrompt(content) || hasGrokQuestionPrompt(content) {
    return .blocked
  }
  if hasGrokWorkingSignal(content) {
    return .working
  }
  return .idle
}

nonisolated private func hasGrokPermissionPrompt(_ content: String) -> Bool {
  let lower = content.lowercased()
  // Tool approval dialog (verified on-screen, 0.2.101): a yes-row and a
  // reject-row are always rendered together. Requiring the pair keeps
  // transcript prose containing one of the phrases from matching.
  let hasApprovalYesRow =
    lower.contains("yes, proceed")
    || lower.contains("yes, allow")
    || lower.contains("yes, always allow")
    || lower.contains("(always-approve mode)")
  let hasApprovalNoRow =
    lower.contains("no, reject")
    || lower.contains("no, and tell grok")
  if hasApprovalYesRow && hasApprovalNoRow {
    return true
  }
  // Footer rendered only while an approval dialog is pending.
  if lower.contains("ctrl+o:always-approve") {
    return true
  }
  let hasAllowOnce = lower.contains("allow once")
  let hasAlwaysAllow =
    lower.contains("always allow this command")
    || lower.contains("always allow on all sessions")
    || lower.contains("always allow this exact command")
  let hasReject = lower.contains("reject")
  if hasAllowOnce && (hasAlwaysAllow || hasReject) {
    return true
  }
  if hasAlwaysAllow && hasReject {
    return true
  }
  if lower.contains("yes, and always allow this exact command")
    || lower.contains("yes, allow all edits")
  {
    return true
  }
  return false
}

nonisolated private func hasGrokQuestionPrompt(_ content: String) -> Bool {
  let lower = content.lowercased()
  // Ask-user dialog (verified on-screen, 0.2.101): "◆ Waiting on answers for
  // <question>" header plus a free-form "z (○) Type your answer here" row.
  return lower.contains("waiting on answers for")
    || lower.contains("type your answer here")
    || lower.contains("pending: question")
    || lower.contains("pending: other (type your own answer")
    || (lower.contains("awaiting your input")
      && (lower.contains("?") || lower.contains("select") || lower.contains("enter")))
}

nonisolated private func hasGrokWorkingSignal(_ content: String) -> Bool {
  let lower = content.lowercased()
  if lower.contains("tool calls in flight")
    || lower.contains("working tools")
    || lower.contains("still running:")
  {
    return true
  }
  // Status flag rendered while a turn is in progress (distinct from the
  // idle "Awaiting input" / "Awaiting your input" flags).
  if content.split(separator: "\n", omittingEmptySubsequences: false).contains(where: { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed == "Loading" || trimmed.hasPrefix("Loading…") || trimmed.hasPrefix("Loading...")
  }) {
    return true
  }
  if hasBrailleSpinner(content) || hasSpinnerActivity(content) {
    return true
  }
  return false
}

nonisolated private func hasBrailleSpinner(_ content: String) -> Bool {
  content.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.unicodeScalars.first else { return false }
    return (0x2800...0x28FF).contains(Int(first.value))
      && trimmed.contains(where: \.isLetter)
  }
}

// TraeCode CLI (`traecli`/`traex`, verified 0.201.7): a Codex-CLI fork with its
// own glyphs (`❯` for the composer and the selection mark, not Codex's `›`). The
// live region sits at the bottom of the screen: a `─` composer border, a column-0
// `❯` prompt row (wrapped input continues on indented rows), a closing `─` border,
// and the built-in status row directly below it
// — `<model> · Context <n>% left · <cwd> ▧ Workspace Edit` — rendered with a
// two-space gutter. That status row reads the same whether a turn runs or not,
// so it is only ever evidence of an idle composer: a running turn is signalled
// by `◆ Working… (… esc to interrupt)` rendered just above the box, with the
// rotating `Tip:` line between it and the top border. Live dialogs — a
// directory trust prompt, a tool approval, or an elicitation form — replace the
// composer with an indented block of numbered option rows (`❯` marks the
// selection) above a submit/navigate footer. Composer and dialog are resolved by
// relative position, because the transcript quotes both shapes: the lower of the
// two is the live region, so a quoted composer above current approval options
// cannot hide the dialog, and a quoted dialog above the live composer cannot
// present as Blocked. Inside the box everything is the user's draft, so a
// numbered draft or the words `to interrupt` typed as input can never speak for
// the live state. A screen that shows none of these is `.unknown`, never
// affirmative idle. A typed profile stays deferred, mirroring Antigravity.
nonisolated private func detectTrae(_ content: String) -> AgentRawState {
  let screen = TraeScreen(content)
  let composer = traeComposer(screen)
  let dialog = traeLiveDialog(screen)

  // The newer of the two live regions decides. A live composer replaces a dialog,
  // but a dialog that renders *below* a composer box supersedes it: the box is then
  // a quoted one from the transcript, and reading its status row would report a
  // settled turn (`Idle`) and hide the approval the pane is actually waiting on.
  if let dialog, dialog.marker > (composer?.bottom ?? -1) { return .blocked }

  // With no dialog below it, the composer box is authoritative: its own rows decide
  // the state and any quoted transcript above it — even a verbatim trust dialog —
  // is not evidence.
  if let composer {
    // The running indicator wins over the status row, which is identical in
    // both states, so it must be read first.
    if composer.hasWorkingIndicator { return .working }
    if let status = composer.status { return status }
    // A composer renders only a live prompt: with no running hint above it and no
    // recognized status row, the turn has settled. Returning `unknown` here would
    // let the state machine retain the previous turn's stale Working.
    return .idle
  }

  // No composer. A running indicator in the live tail beats a quoted question,
  // and a real dialog carries no such indicator.
  if screen.rows.indices.suffix(10).contains(where: { traeRowShowsRunningTurn(screen, $0) }) {
    return .working
  }
  return .unknown
}

/// The active screen parsed into non-blank rows. `raw` keeps the column so
/// indented input can never pose as column-0 chrome; `text` carries the
/// signatures. `blankBefore` records whether a blank raw line preceded each kept
/// row, so the live block above the composer can be read by shape (blank-bounded)
/// instead of a fixed row count.
private struct TraeScreen {
  let rows: [(raw: String, text: String)]
  let lines: [String]
  let blankBefore: [Bool]

  nonisolated init(_ content: String) {
    var rows: [(raw: String, text: String)] = []
    var blankBefore: [Bool] = []
    var afterBlank = true
    for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
      let raw = String(line)
      let text = raw.trimmingCharacters(in: .whitespaces)
      if text.isEmpty {
        afterBlank = true
        continue
      }
      rows.append((raw: raw, text: text))
      blankBefore.append(afterBlank)
      afterBlank = false
    }
    self.rows = rows
    self.lines = rows.map(\.text)
    self.blankBefore = blankBefore
  }
}

/// The live composer box: a column-0 `❯` prompt row, its indented continuation
/// rows, the closing `─` separator, and the built-in status row directly below the
/// separator. The box is delimited by its own rows — the separator is the rule the
/// prompt's draft run ends on — never by a screen-wide width, because the pane's
/// text is read non-rectangularly and a historical logical line can out-measure the
/// live border. Everything inside the box is the user's own draft, so a numbered
/// draft or the words `to interrupt` typed into it must never read as a dialog
/// option or a running turn. Returns nil when no such box renders (a choice dialog
/// replaces the composer).
private struct TraeComposer {
  let status: AgentRawState?
  let hasWorkingIndicator: Bool
  /// The row of the closing separator, so a dialog below the box can supersede it.
  let bottom: Int
}

nonisolated private func traeComposer(_ screen: TraeScreen) -> TraeComposer? {
  let rows = screen.rows
  let lines = screen.lines
  let isColumnZero = { (index: Int) -> Bool in !rows[index].raw.hasPrefix(" ") }
  // The closing border is the column-0 `─` rule that the prompt row's own draft run
  // ends on, read from the box's local rows alone. Its width is never measured
  // against the rest of the screen: traecli's screen text arrives through a
  // non-rectangular read and Ghostty joins soft-wrapped lines, so a historical
  // *logical* line can be wider than the pane and wider than the live border — the
  // agent's own output leaving a rule behind is enough. Sizing the border by the
  // longest rule on screen dropped the whole box on such a screen: an idle
  // `❯ Draft` read `.unknown` and kept the previous turn's Working, and a numbered
  // draft fell through to the dialog shapes and read as approval options.
  let isRule = { (index: Int) -> Bool in
    isColumnZero(index) && lines[index].allSatisfy { $0 == "─" }
  }
  let isPrompt = { (index: Int) -> Bool in isColumnZero(index) && isTraePromptRow(lines[index]) }

  var composer: TraeComposer?
  var index = rows.startIndex
  while index < rows.endIndex {
    guard isPrompt(index) else {
      index += 1
      continue
    }
    var bottom = index + 1
    while bottom < rows.endIndex, !isColumnZero(bottom) { bottom += 1 }
    guard bottom < rows.endIndex, isRule(bottom) else {
      index += 1
      continue
    }
    // A later prompt+border supersedes an earlier one: only the bottom-most box is
    // live, so a quoted composer left in the transcript can never drive the state.
    // The live status row is indented (a two-space gutter) directly below the
    // closing border, so it is matched by signature rather than by column. Only
    // this row — never the rows above the box — can speak for the live state.
    let status = bottom + 1 < rows.endIndex ? traeStatusState(rows[bottom + 1].raw) : nil
    // The running indicator renders at the top of the live block above the box:
    // it and every row under it — a rotating `Tip:`, the agent's todo checklist,
    // a wrapped indicator — form the contiguous non-blank run directly above this
    // box's prompt, separated from the transcript by a blank line. Reading that
    // whole run keeps a tall block (a multi-item plan) from pushing the hint past
    // a fixed row count, which would let the idle status row decide a running
    // turn.
    var start = index
    while start > rows.startIndex, !screen.blankBefore[start] {
      start -= 1
    }
    let window = start..<index
    composer = TraeComposer(
      status: status,
      hasWorkingIndicator: window.contains(where: { traeRowShowsRunningTurn(screen, $0) }),
      bottom: bottom)
    index = bottom + 1
  }
  return composer
}

/// A live modal dialog (approval, choice, or elicitation form) replaces the
/// composer. traecli renders most of them inside the live block's two-space gutter,
/// but the first-run trust prompt and the login screens render at column 0, so the
/// mark is matched by shape, never by column. Four shapes qualify: a `❯`-marked
/// option row with an unselected numbered sibling, a form whose only chrome is its
/// submit/navigate footer (a free-form field has no options), a bracketed y/n
/// confirmation, or one of the interactive login/auth screens. Output that merely
/// quotes a question carries none of these and cannot read as blocked.
///
/// Returned with its marker — the block's bottom-most chrome row, which resolves a
/// dialog against a composer box above it — and the region the dialog occupies, so
/// state detection and `agents read`'s blocker extraction cannot disagree about
/// where it starts.
nonisolated private func traeLiveDialog(_ screen: TraeScreen) -> TraeDialog? {
  let window = Array(screen.rows.indices.suffix(10))
  let lines = screen.lines
  // The composer's status bar is dynamic chrome (model, context, path, permission
  // mode), never a dialog row: a checkout at `/tmp/esc to cancel` must not present
  // as a footer.
  let candidates = window.filter { !isTraeStatusBarRow(lines[$0]) }
  guard hasTraeDialogShape(lines, candidates),
    let marker = candidates.last(where: { isTraeDialogMarker(lines[$0]) })
  else { return nil }
  return TraeDialog(marker: marker, region: traeDialogRegion(screen, marker: marker))
}

/// The four live-dialog shapes, over the rows that may carry them.
nonisolated private func hasTraeDialogShape(_ lines: [String], _ candidates: [Int]) -> Bool {
  if candidates.contains(where: { isTraeSelectionRow(lines[$0]) }),
    candidates.contains(where: { isTraeUnselectedOptionRow(lines[$0]) })
  {
    return true
  }
  if candidates.contains(where: { isTraeDialogFooterRow(lines[$0]) }) { return true }
  if candidates.contains(where: { isTraeYesNoPromptRow(lines[$0]) }) { return true }
  return hasTraeAuthPrompt(lines, candidates)
}

/// A live dialog: where its bottom-most chrome sits, and the rows it occupies.
private struct TraeDialog {
  /// The row of the dialog's bottom-most chrome: the option row, footer, prompt, or
  /// auth line that left the composer behind.
  let marker: Int
  /// The dialog's own rows, from its head down to the marker.
  let region: ClosedRange<Int>
}

/// The dialog's rows, walked back from its marker.
///
/// Indentation alone cannot delimit a dialog: an approval form renders inside the
/// live block's two-space gutter, but the trust prompt and the login screens put
/// their question and choices at column 0. The region therefore stops at the rows
/// that belong to *other* chrome — the composer box and its status bar, the live
/// block's own glyph-headed rows — and is capped, so a screen whose transcript runs
/// straight into the dialog without any of that chrome cannot hand `agents read` an
/// unbounded slice of history.
nonisolated private func traeDialogRegion(_ screen: TraeScreen, marker: Int) -> ClosedRange<Int> {
  var start = marker
  var steps = 0
  while start > screen.rows.startIndex, steps < traeDialogRegionLimit {
    let index = start - 1
    guard isTraeDialogContent(screen, index) else { break }
    start = index
    steps += 1
  }
  return start...marker
}

/// The rows a dialog can carry. Everything that belongs to the composer (its prompt
/// row, its `─` rules, the status bar under it) or to the transcript (a
/// glyph-headed tool call, a live-block footer, the welcome box) ends the region.
nonisolated private func isTraeDialogContent(_ screen: TraeScreen, _ index: Int) -> Bool {
  let raw = screen.rows[index].raw
  let line = screen.lines[index]
  if isTraeStatusBarRow(line) { return false }
  if isTraeWelcomeBannerRow(line) { return false }
  if line.allSatisfy({ $0 == "─" }) { return false }
  if isTraePromptRow(line), !isTraeSelectionRow(line) { return false }
  return !isTraeLiveFooterLead(raw)
}

/// The welcome banner — block-element art and its greeting. The first-run trust prompt
/// renders at column 0 directly under it, with no other chrome between them.
nonisolated private func isTraeWelcomeBannerRow(_ line: String) -> Bool {
  if line.lowercased().hasPrefix("welcome to trae cli") { return true }
  return line.unicodeScalars.allSatisfy { $0 == " " || (0x2580...0x259F).contains($0.value) }
}

/// How far above its marker a dialog's rows are read. The widest known form — an
/// approval with a question, its parameters, and four options — is ten rows.
nonisolated private let traeDialogRegionLimit = 16

/// Whether the row is the composer's status bar: live chrome below the box carrying
/// dynamic values — the model, the context percentage, the working directory, the
/// permission mode. It reads the same whether a turn runs or not, so nothing on it
/// can speak for the dialog or the running turn.
nonisolated private func isTraeStatusBarRow(_ line: String) -> Bool {
  let lower = line.lowercased()
  if lower.contains("▧ workspace edit") { return true }
  return lower.contains("context ") && lower.contains("% left")
}

/// traecli's live dialog footer. The on-prem build renders
/// `<key> to submit[_ all| answer] | esc to cancel` on approval forms and
/// `↑/↓ to navigate fields   esc to cancel` on elicitation forms; the public 0.209.1 build
/// renders key hints joined by `  |  ` (`enter confirm  |  esc cancel`).
/// The row has to carry the cancel/navigate chrome as well as the phrase: matching
/// the phrase alone let ordinary content forge modal chrome — a working directory
/// like `/tmp/how to submit` turned a settled composer into Blocked.
nonisolated private func isTraeDialogFooterRow(_ line: String) -> Bool {
  let lower = line.lowercased()
  if isTraeKeyHintFooterRow(lower) { return true }
  guard lower.contains("esc to ") else { return false }
  return lower.contains(" to submit")
    || lower.contains("to navigate fields")
    || lower.contains("to navigate questions")
}

/// The public build's dialog footer: `enter continue  |  esc quit`,
/// `tab add notes  |  enter submit answer  |  esc interrupt`. It needs an `enter` hint and
/// an `esc` hint as their own `|`-separated segments, which the transcript pager's footer
/// (`q quit  |  esc/← edit prev  |  / search`) does not carry.
nonisolated private func isTraeKeyHintFooterRow(_ lowercasedLine: String) -> Bool {
  let segments = lowercasedLine.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
  guard segments.count >= 2 else { return false }
  return segments.contains { $0.hasPrefix("enter ") } && segments.contains { $0.hasPrefix("esc ") }
}

/// traecli's y/n confirmation renders as a bracketed choice at the end of the
/// prompt line (`Overwrite existing file? [y/N]`) rather than a numbered menu.
/// Requiring the token at the line's end keeps a transcript line that merely
/// mentions `[y/n]` from reading as live chrome.
nonisolated private func isTraeYesNoPromptRow(_ line: String) -> Bool {
  let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
  return traeYesNoTokens.contains { trimmed.hasSuffix($0) }
}

nonisolated private let traeYesNoTokens = ["[y/n]", "[y/n]:", "(y/n)", "(y/n):"]

/// traecli's interactive login/auth screens (phrases verified against 0.201.7)
/// replace the composer like a dialog but use a `>` menu or free-form fields, so
/// the numbered/`❯` shapes never match them. A distinctive header phrase plus its
/// Enter/Esc chrome is required, so transcript text cannot forge one — and the
/// chrome row has to *open* with its key chord, so a line that merely mentions
/// pressing Esc does not count.
nonisolated private func hasTraeAuthPrompt(_ lines: [String], _ window: [Int]) -> Bool {
  window.contains { isTraeAuthHeaderRow(lines[$0]) }
    && window.contains { isTraeAuthChromeRow(lines[$0]) }
}

nonisolated private func isTraeAuthHeaderRow(_ line: String) -> Bool {
  let lower = line.lowercased()
  return traeAuthHeaderNeedles.contains { lower.contains($0) }
}

nonisolated private func isTraeAuthChromeRow(_ line: String) -> Bool {
  let lower = line.trimmingCharacters(in: .whitespaces).lowercased()
  // The chrome opens with its key chord — `Press Esc to cancel`, `esc to cancel`,
  // `Press Enter to sign in` — so a line that only mentions pressing Esc somewhere
  // inside it does not count.
  guard lower.hasPrefix("press ") || lower.hasPrefix("esc ") else { return false }
  return lower.contains("enter to sign in") || lower.contains("enter to continue")
    || lower.contains("esc to cancel") || lower.contains("esc to go back")
}

nonisolated private let traeAuthHeaderNeedles = [
  "sign in with ", "sign into traecode", "traecode login", "personal access token",
  "bytecloud device code", "bytedance sso", "api key login is disabled", "login is disabled",
]

nonisolated private func isTraePromptRow(_ line: String) -> Bool {
  line == "❯" || line.hasPrefix("❯ ")
}

/// `❯ 1. Yes, continue` — the `❯` selection mark plus a numbered option.
nonisolated private func isTraeSelectionRow(_ line: String) -> Bool {
  guard line.hasPrefix("❯ ") else { return false }
  return isTraeNumberedOption(String(line.dropFirst(2)))
}

/// `  2. No, quit` — a numbered option without the selection mark.
nonisolated private func isTraeUnselectedOptionRow(_ line: String) -> Bool {
  guard !line.hasPrefix("❯") else { return false }
  return isTraeNumberedOption(line)
}

nonisolated private func isTraeNumberedOption(_ text: String) -> Bool {
  guard let dot = text.firstIndex(of: ".") else { return false }
  let number = text[..<dot]
  guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return false }
  return text[text.index(after: dot)...].hasPrefix(" ")
}

/// Binary-verified `" to interrupt"` (the fork reuses Codex's interrupt footer),
/// minus the boot progress lines that reuse the same footer. A cold start shows
/// `✦ Starting MCP servers (0/3): … (0s • esc to interrupt)` above an otherwise
/// idle composer; counting it as a running turn flashed Working during startup
/// and let the settle to the idle composer earn a spurious Done badge.
///
/// traecli also clips live chrome to the pane width before writing it, so a wide
/// live-block header loses the tail: `✦ <streaming snippet> (42m 53s • ↑ 183K
/// tokens …` arrives with neither `esc to interrupt` nor the `/ps` chrome, and a
/// running turn then read as a settled composer — a false Idle badge, and a
/// spurious Done on an unviewed pane. See `isTraeClippedRunningFooter`.
///
/// Takes the raw row: the clipped form is recognized by its column-0 glyph, which
/// the trimmed `text` of a screen row would have dropped.
nonisolated private func hasTraeInterruptHint(_ rawLine: String) -> Bool {
  let lower = rawLine.lowercased()
  // The startup exclusion covers both forms: a boot line wide enough to lose its
  // own tail keeps its `Starting MCP servers` head, so it must not come back as a
  // clipped footer and earn the settle to Idle a spurious Done.
  if isTraeStartupProgressLine(lower) { return false }
  // The status bar carries the working directory, so a checkout at
  // `/tmp/how to interrupt` must not read as a running turn.
  if isTraeStatusBarRow(lower) { return false }
  if hasTraeInterruptChrome(lower) { return true }
  return isTraeClippedRunningFooter(rawLine)
}

/// The running footer's interrupt chrome, parentheses included: `(esc to interrupt)`,
/// `(23s • esc to interrupt)`, `(50m 45s • ↓ 91.5K tokens • esc to interrupt • thought
/// for 2s)`. Requiring the parentheses — rather than the bare phrase anywhere on the
/// row — keeps ordinary content that merely mentions interrupting, such as a working
/// directory named `/tmp/how to interrupt`, from reading as a running turn.
nonisolated private func hasTraeInterruptChrome(_ lowercasedLine: String) -> Bool {
  guard let phrase = lowercasedLine.range(of: "to interrupt") else { return false }
  guard lowercasedLine[..<phrase.lowerBound].contains("(") else { return false }
  return lowercasedLine[phrase.upperBound...].contains(")")
}

/// Whether the row at `index` is the live block's running mark, read for the whole
/// block rather than for the single row.
///
/// traecli's boot progress line is logical, not physical: on a narrow terminal it
/// wraps, so `Starting MCP servers …` can sit on one row and its `esc to interrupt`
/// footer on the next. Excluding startup per row therefore missed the wrapped form
/// and read a cold start as Working (and earned the settle to Idle a spurious Done).
/// A row that opens the block with a live glyph is the live region's own footer and
/// always counts; any other row with an interrupt hint belongs to the block it sits
/// in, so it is startup noise when that block carries a progress head.
nonisolated private func traeRowShowsRunningTurn(_ screen: TraeScreen, _ index: Int) -> Bool {
  let raw = screen.rows[index].raw
  guard hasTraeInterruptHint(raw) else { return false }
  if isTraeLiveFooterLead(raw) { return true }
  return !isInTraeStartupProgressBlock(screen, index)
}

/// Whether the row at `index` shares its blank-bounded block with a startup progress
/// head (`isTraeStartupProgressLine`). The block is the live block: a wrapped boot
/// line and its footer, or a running turn's indicator, tips, and todo checklist.
nonisolated private func isInTraeStartupProgressBlock(_ screen: TraeScreen, _ index: Int) -> Bool {
  var start = index
  while start > screen.rows.startIndex, !screen.blankBefore[start] {
    start -= 1
  }
  var end = index
  while end + 1 < screen.rows.endIndex, !screen.blankBefore[end + 1] {
    end += 1
  }
  return (start...end).contains { isTraeStartupProgressLine(screen.lines[$0].lowercased()) }
}

/// The lead of a live-block footer or of its clipped remnant: a column-0 live glyph
/// followed by a space. Transcript rows carry prose, tool output (`└`, indented), or
/// their own `◆ Called …` heads, so nothing else in the block claims this shape — and
/// the composer's `❯` mark is excluded, because a prompt or a dialog's option row
/// opens a row the same way without being live chrome.
nonisolated private func isTraeLiveFooterLead(_ rawLine: String) -> Bool {
  let scalars = rawLine.unicodeScalars
  guard let glyph = scalars.first, (0x2000...0x2BFF).contains(Int(glyph.value)),
    glyph.value != 0x276F
  else { return false }
  return scalars.dropFirst().first == " "
}

/// The live-block header's clipped remnant: a column-0 live glyph, then the
/// elapsed-time chrome that precedes the token/shell chrome, e.g.
/// `❖ The live block header might be rendered above the visible window (42m 53s •`.
/// The opening parenthesis and its duration are the last marks traecli renders
/// before it truncates, so they survive where the interrupt hint does not; in a narrow
/// pane the clip can fall right after the bullet (`✦ Working… (2s •…`). The
/// column-0 glyph keeps transcript prose and tool output (`  └ (2s · timeout 2m)`,
/// which uses `·`, not `•`, and is indented) from speaking for the live state.
nonisolated private func isTraeClippedRunningFooter(_ rawLine: String) -> Bool {
  guard isTraeLiveFooterLead(rawLine) else { return false }
  var remainder = rawLine[...]
  while let open = remainder.firstIndex(of: "(") {
    let rest = remainder[remainder.index(after: open)...]
    if let bullet = rest.range(of: " •"), isTraeElapsedDuration(rest[..<bullet.lowerBound]) {
      return true
    }
    remainder = rest
  }
  return false
}

/// `42m 53s`, `23s`, `1h 02m 03s` — the elapsed time traecli renders inside live
/// chrome. Only digits, the `h`/`m`/`s` units, and single separating spaces.
nonisolated private func isTraeElapsedDuration(_ text: Substring) -> Bool {
  guard text.last == "s", text.first != " ", text.contains(where: \.isNumber) else { return false }
  var previousWasSpace = false
  for character in text {
    if character == " " {
      guard !previousWasSpace else { return false }
      previousWasSpace = true
      continue
    }
    guard character.isNumber || character == "h" || character == "m" || character == "s" else {
      return false
    }
    previousWasSpace = false
  }
  return true
}

/// traecli's boot progress line (`✦ Starting MCP servers (n/m): <names> (0s •
/// esc to interrupt)`): startup work, not an agent turn, so it must never
/// decide the live state.
nonisolated private func isTraeStartupProgressLine(_ lowercasedLine: String) -> Bool {
  lowercasedLine.contains("starting mcp server")
}

/// The composer's status row, below the closing border. It carries the idle signature
/// (`<model> · Context <n>% left · <cwd> ▧ Workspace Edit`), and it can carry the
/// running footer's own chrome in some renderings. Both are matched by structure: the
/// row's values are dynamic — model, context percentage, working directory, permission
/// mode — so a path such as `/tmp/how to interrupt` must not present as a running turn
/// (see `isTraeStatusBarRow` and `hasTraeInterruptChrome`).
nonisolated private func traeStatusState(_ line: String) -> AgentRawState? {
  if hasTraeInterruptHint(line) { return .working }
  let lower = line.lowercased()
  if line.contains(" · ") && lower.contains("context ") && lower.contains("left") { return .idle }
  return nil
}

/// The live dialog's own text, for `agents read`. TraeCode CLI has no typed screen
/// profile, so this reuses the same shape rules as `detectTrae`: the dialog that
/// carries the bottom-most marker — the question, its command or parameters, the
/// option rows and their footer, a y/n prompt, or the login/auth chrome. Returns nil
/// unless the current screen reads Blocked.
///
/// The rows come from `traeDialogRegion`, the same region the detector resolves, so
/// the two cannot disagree about where the dialog starts. Walking the rows directly —
/// by indentation, or by stopping at the first preceding blank line — returned only
/// the options and the footer of the trust prompt and the login screen, whose
/// question and choices render at column 0, and dropped a form's question and
/// parameters when they were separated from the options by a blank line. The dialog's
/// own blank lines are restored so the text reads the way the pane renders it.
nonisolated func traeBlockerText(in snapshot: AgentScreenSnapshot) -> String? {
  guard detectTrae(snapshot.text) == .blocked else { return nil }
  let screen = TraeScreen(snapshot.text)
  guard let dialog = traeLiveDialog(screen) else { return nil }
  var components: [String] = []
  for index in dialog.region {
    if screen.blankBefore[index], !components.isEmpty { components.append("") }
    components.append(screen.lines[index])
  }
  let text = components.joined(separator: "\n").trimmingCharacters(in: .newlines)
  return text.isEmpty ? nil : text
}

nonisolated private func isTraeDialogMarker(_ line: String) -> Bool {
  isTraeSelectionRow(line) || isTraeUnselectedOptionRow(line) || isTraeDialogFooterRow(line)
    || isTraeYesNoPromptRow(line) || isTraeAuthHeaderRow(line) || isTraeAuthChromeRow(line)
}

/// Whether the pane's terminal title says a traecli turn is running. The TUI
/// animates a braille spinner ahead of the thread title while a turn streams
/// (`⠋ 排查修复…`) and drops it the moment the turn settles — a background shell
/// that outlives the turn does not keep it up, which is why a pane left waiting
/// on one still reads Idle (docs-ai 083).
///
/// The screen is the primary evidence, but it is a rendering of the live tail and
/// can be stolen: traecli clips the live-block header to the pane width (see
/// `isTraeClippedRunningFooter`), and a pane scrolled into history or caught mid
/// repaint can show a settled-looking composer while the turn is still running.
/// The title mark is written by the TUI itself, so it survives all three — it is
/// corroboration that a screen Idle verdict must not settle a running turn.
nonisolated func traeTitleShowsRunningTurn(_ title: String?) -> Bool {
  guard let title else { return false }
  guard let first = title.trimmingCharacters(in: .whitespaces).unicodeScalars.first else {
    return false
  }
  return (0x2800...0x28FF).contains(Int(first.value))
}

// Antigravity CLI (`agy`, verified live on 1.3.2): the live region is the
// composer — a full-width `─` border, a column-0 `>` prompt row (wrapped input
// continues on indented rows), and a full-width `─` bottom border — and the
// built-in status row renders directly below it: `esc to cancel` /
// `esc to interrupt` while a turn runs, `? for shortcuts` when idle, padded away
// from a right-aligned model label (`Gemini 3.8 Flash · high`,
// `Claude Sonnet 4.6 (Thinking)`, or nothing until the label resolves). The
// `stack_with_default` setting renders a user's status script verbatim below
// that row, so nothing below the status row is evidence. A typed draft hides
// the signature (the status row keeps only the model label), which reads
// unknown and retains the prior state. Permission, ask-user,
// and workspace-trust dialogs replace the composer with option rows (`> ` marks
// the selection) above a `↑/↓ Navigate …` hint; a permission dialog keeps
// `esc to cancel`, so the dialog read runs first and is never vetoed by what
// renders below the hint. Full width is the longest
// `─`-only column-0 row on screen: the echoed prompt's rule is narrower, agent
// responses render indented, and a stacked script would have to draw a
// terminal-wide `─`/`>`/`─` box of its own to forge a composer (documented
// residual; it fails toward `.unknown`). A screen with neither a live dialog
// nor a composer followed by a status row is `.unknown`, never affirmative
// idle — screen heuristics are this runtime's only evidence channel.
nonisolated private func detectAntigravity(_ content: String) -> AgentRawState {
  // Trimmed `text` carries the signatures; `raw` keeps the column so typed or
  // wrapped input (always indented inside the box) cannot pose as chrome.
  let rows = content.split(separator: "\n", omittingEmptySubsequences: false)
    .map { (raw: String($0), text: $0.trimmingCharacters(in: .whitespaces)) }
    .filter { !$0.text.isEmpty }
  let lines = rows.map(\.text)
  let isColumnZero = { (index: Int) -> Bool in !rows[index].raw.hasPrefix(" ") }
  let isRule = { (index: Int) -> Bool in isColumnZero(index) && lines[index].allSatisfy { $0 == "─" } }
  let fullWidth = rows.indices.filter(isRule).map { lines[$0].count }.max() ?? 0
  let isBorder = { (index: Int) -> Bool in isRule(index) && lines[index].count == fullWidth }
  let isPrompt = { (index: Int) -> Bool in
    isColumnZero(index) && (lines[index] == ">" || lines[index].hasPrefix("> "))
  }

  // Composer boxes in screen order. A bottom border may double as the next
  // box's top border, so the scan resumes on it.
  var composers: [(top: Int, bottom: Int)] = []
  var index = rows.startIndex
  while index < rows.endIndex {
    guard isBorder(index), index + 1 < rows.endIndex, isPrompt(index + 1) else {
      index += 1
      continue
    }
    var bottom = index + 2
    while bottom < rows.endIndex, !isColumnZero(bottom) {
      bottom += 1
    }
    guard bottom < rows.endIndex, isBorder(bottom) else {
      index += 1
      continue
    }
    composers.append((top: index, bottom: bottom))
    index = bottom
  }

  // The status row is the signature alone or the signature padded (two or more
  // spaces) away from the model label. A custom row that continues the
  // signature with a single space (`? for shortcuts custom help`) is not one.
  let statusState = { (index: Int) -> AgentRawState? in
    guard index < lines.endIndex, isColumnZero(index) else { return nil }
    let signatures: [(String, AgentRawState)] = [
      ("esc to cancel", .working), ("esc to interrupt", .working), ("? for shortcuts", .idle),
    ]
    return signatures.first { lines[index] == $0.0 || lines[index].hasPrefix($0.0 + "  ") }?.1
  }

  // Dialog chrome is terminal. A `↑/↓ Navigate` hint with a column-0 `> `
  // selection within eight rows above it (long permission menus) is Blocked,
  // whatever follows: agent responses render indented, so column-0 chrome is
  // either the live dialog or the user's own echoed text, and a quoted dialog
  // that reads Blocked until it scrolls off costs a delay where a vetoed live
  // dialog would cost a dispatch into a modal prompt. A bare hint — selection
  // cropped, or residue — denies the composer evidence below it instead.
  let isHint = { (line: String) -> Bool in
    line.hasPrefix("↑/↓ Navigate") || line.hasPrefix("↑↓ Navigate")
  }
  if let hint = lines.lastIndex(where: isHint) {
    // The slash-command autocomplete popup (`> /` draft, option rows, the same
    // hint shape) renders below a live composer box and rewrites the status
    // row to `esc to cancel` whatever the turn state, so it is unknown: the
    // state machine keeps the state from before the user started typing.
    // Dialogs replace the composer, so no box sits above their hint.
    if let composer = composers.last, composer.bottom < hint {
      return .unknown
    }
    let selected = rows.indices[..<hint].suffix(8).contains { isColumnZero($0) && lines[$0].hasPrefix("> ") }
    return selected ? .blocked : .unknown
  }
  // Option shape alone (a column-0 `> ` row over an indented sibling) is not
  // dialog evidence: a slash command echoes exactly that way with no `─` rule
  // above it, an answered question echoes its choice the same way, and so
  // does any echoed prompt whose rule scrolled off the top of the screen.
  // Every live dialog carries the hint, so a dialog with unrecognized hint
  // copy falls through to the composer read and fails toward unknown.

  // The last composer is the live one; a redraw caught without its status row,
  // or a screen without a composer at all, is unknown rather than idle.
  guard let composer = composers.last else { return .unknown }
  return statusState(composer.bottom + 1) ?? .unknown
}
