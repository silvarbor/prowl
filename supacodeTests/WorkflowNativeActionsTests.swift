import Foundation
import Testing

@testable import supacode

struct WorkflowNativeActionsTests {
  nonisolated private static let now = Date(timeIntervalSince1970: 1_760_000_000)

  private func makeRepo() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "workflow-actions-tests", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    for arguments in [
      ["init", "-q", "-b", "main"], ["config", "user.email", "t@example.com"], ["config", "user.name", "T"],
    ] {
      try runGit(arguments, in: url)
    }
    try "hello\n".write(to: url.appending(path: "README.md"), atomically: true, encoding: .utf8)
    try runGit(["add", "."], in: url)
    try runGit(["commit", "-q", "-m", "init"], in: url)
    return url
  }

  private func runGit(_ arguments: [String], in directory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", directory.path(percentEncoded: false)] + arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw NSError(domain: "WorkflowNativeActionsTests.Git", code: Int(process.terminationStatus))
    }
  }

  private func context(root: URL) -> WorkflowActionContext {
    WorkflowActionContext(
      runID: UUID(uuidString: "0BADCAFE-0000-4000-8000-000000000042")!,
      rootURL: root,
      roleAgents: ["source": "claude", "receiver": "codex", "shell": nil],
      outgoingAgent: "claude",
      now: Self.now)
  }

  private let briefing = """
    # Handoff
    ## Objective
    Ship.
    ## Current State
    Green.
    ## Next Steps
    1. Review.
    """

  @Test func transitionWithBriefingArchivesFirstAndReturnsTheBriefingKickoff() async throws {
    let root = try makeRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HandoffStore(rootURL: root)
    try store.writeBriefing(
      "# Handoff\n## Objective\nold\n## Current State\nx\n## Next Steps\ny\n", archivingPrevious: false, now: Self.now)
    let briefingURL = root.appending(path: "brief.md")
    try briefing.write(to: briefingURL, atomically: true, encoding: .utf8)

    let outputs = try await WorkflowNativeActionRunner().execute(
      actionID: "handoff.transition",
      inputs: [
        "briefing": briefingURL.path(percentEncoded: false), "from": "source", "to": "receiver", "note": "round 1",
      ],
      context: context(root: root))

    #expect(outputs["has_briefing"] == "true")
    #expect(outputs["artifact_path"] == store.currentURL.path(percentEncoded: false))
    #expect(outputs["kickoff_prompt"] == HandoffCommandHandler.kickoffPrompt(hasBriefing: true))
    #expect(try String(contentsOf: store.currentURL, encoding: .utf8) == briefing + "\n")
    let archive = try FileManager.default.contentsOfDirectory(
      atPath: store.archiveDirectory.path(percentEncoded: false))
    #expect(archive.count == 1)
    #expect(archive.first?.contains("-claude-to-codex") == true)
    #expect(FileManager.default.fileExists(atPath: store.contextURL.path(percentEncoded: false)))
    let log = try String(contentsOf: store.logURL, encoding: .utf8)
    #expect(log.contains("claude → codex  launch=requested  briefing=inline"))
    #expect(log.contains("source=workflow 0BADCAFE-0000-4000-8000-000000000042"))
    #expect(log.contains("note=\"round 1\""))
  }

  @Test func transitionWithoutBriefingRemovesTheStaleArtifact() async throws {
    let root = try makeRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HandoffStore(rootURL: root)
    try store.writeBriefing(
      "# Handoff\n## Objective\nold\n## Current State\nx\n## Next Steps\ny\n", archivingPrevious: false, now: Self.now)

    let outputs = try await WorkflowNativeActionRunner().execute(
      actionID: "handoff.transition", inputs: ["from": "source", "to": "receiver"], context: context(root: root))

    #expect(outputs["has_briefing"] == "false")
    #expect(outputs["kickoff_prompt"] == HandoffCommandHandler.kickoffPrompt(hasBriefing: false))
    #expect(!store.hasCurrentArtifact)
    #expect(FileManager.default.fileExists(atPath: store.contextURL.path(percentEncoded: false)))
    let archive = try FileManager.default.contentsOfDirectory(
      atPath: store.archiveDirectory.path(percentEncoded: false))
    #expect(archive.count == 1)
  }

  @Test func transitionValidatesRolesAndBriefing() async throws {
    let root = try makeRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let runner = WorkflowNativeActionRunner()
    await #expect(throws: WorkflowActionError.missingInput("to")) {
      try await runner.execute(actionID: "handoff.transition", inputs: ["from": "source"], context: context(root: root))
    }
    await #expect(throws: WorkflowActionError.unknownRole("ghost")) {
      try await runner.execute(
        actionID: "handoff.transition", inputs: ["from": "source", "to": "ghost"], context: context(root: root))
    }
    let invalidURL = root.appending(path: "invalid.md")
    try "just prose".write(to: invalidURL, atomically: true, encoding: .utf8)
    await #expect(throws: WorkflowActionError.invalidBriefing(path: invalidURL.path(percentEncoded: false))) {
      try await runner.execute(
        actionID: "handoff.transition",
        inputs: ["briefing": invalidURL.path(percentEncoded: false), "from": "source", "to": "receiver"],
        context: context(root: root))
    }
    #expect(!HandoffStore(rootURL: root).hasCurrentArtifact)
    let missing = root.appending(path: "missing.md").path(percentEncoded: false)
    await #expect(throws: WorkflowActionError.unreadableBriefing(path: missing)) {
      try await runner.execute(
        actionID: "handoff.transition", inputs: ["briefing": missing, "from": "source", "to": "receiver"],
        context: context(root: root))
    }
    await #expect(throws: WorkflowActionError.unsafePath("/etc/passwd")) {
      try await runner.execute(
        actionID: "handoff.transition", inputs: ["briefing": "/etc/passwd", "from": "source", "to": "receiver"],
        context: context(root: root))
    }
    await #expect(throws: WorkflowActionError.unknownAction("nope")) {
      try await runner.execute(actionID: "nope", inputs: [:], context: context(root: root))
    }
  }

  @Test func briefingLinksAreResolvedAndMustStayInsideTheWorktree() async throws {
    let root = try makeRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let briefingURL = root.appending(path: "brief.md")
    try briefing.write(to: briefingURL, atomically: true, encoding: .utf8)
    let inside = root.appending(path: "link-inside.md")
    try FileManager.default.createSymbolicLink(at: inside, withDestinationURL: briefingURL)
    let outputs = try await WorkflowNativeActionRunner().execute(
      actionID: "handoff.checkpoint", inputs: ["briefing": inside.path(percentEncoded: false)],
      context: context(root: root))
    #expect(outputs["has_briefing"] == "true")

    let outside = root.appending(path: "link-outside.md")
    try FileManager.default.createSymbolicLink(at: outside, withDestinationURL: URL(filePath: "/etc/hosts"))
    await #expect(throws: WorkflowActionError.unsafePath(outside.path(percentEncoded: false))) {
      try await WorkflowNativeActionRunner().execute(
        actionID: "handoff.checkpoint", inputs: ["briefing": outside.path(percentEncoded: false)],
        context: context(root: root))
    }
    let directory = root.appending(path: "dir", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    await #expect(throws: WorkflowActionError.unreadableBriefing(path: directory.path(percentEncoded: false))) {
      try await WorkflowNativeActionRunner().execute(
        actionID: "handoff.checkpoint", inputs: ["briefing": directory.path(percentEncoded: false)],
        context: context(root: root))
    }
  }

  @Test func briefingSectionsInsideFencesAreNotAccepted() async throws {
    let root = try makeRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let fencedURL = root.appending(path: "fenced.md")
    try "# Handoff\n```text\n## Objective\n## Current State\n## Next Steps\n```\n".write(
      to: fencedURL, atomically: true, encoding: .utf8)
    #expect(HandoffStore.validatedBriefing(from: try String(contentsOf: fencedURL, encoding: .utf8)) == nil)
    await #expect(throws: WorkflowActionError.invalidBriefing(path: fencedURL.path(percentEncoded: false))) {
      try await WorkflowNativeActionRunner().execute(
        actionID: "handoff.checkpoint", inputs: ["briefing": fencedURL.path(percentEncoded: false)],
        context: context(root: root))
    }
    #expect(!HandoffStore(rootURL: root).hasCurrentArtifact)
  }

  @Test func checkpointKeepsAnEarlierBriefingWithoutANewOne() async throws {
    let root = try makeRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HandoffStore(rootURL: root)
    let earlier = "# Handoff\n## Objective\nold\n## Current State\nx\n## Next Steps\ny\n"
    try store.writeBriefing(earlier, archivingPrevious: false, now: Self.now)

    let contextOnly = try await WorkflowNativeActionRunner().execute(
      actionID: "handoff.checkpoint", inputs: [:], context: context(root: root))
    #expect(contextOnly["has_briefing"] == "false")
    #expect(try String(contentsOf: store.currentURL, encoding: .utf8) == earlier)

    let briefingURL = root.appending(path: "brief.md")
    try briefing.write(to: briefingURL, atomically: true, encoding: .utf8)
    let withBriefing = try await WorkflowNativeActionRunner().execute(
      actionID: "handoff.checkpoint", inputs: ["briefing": briefingURL.path(percentEncoded: false)],
      context: context(root: root))
    #expect(withBriefing["has_briefing"] == "true")
    #expect(withBriefing["artifact_path"] == store.currentURL.path(percentEncoded: false))
    #expect(try String(contentsOf: store.currentURL, encoding: .utf8) == briefing + "\n")
    let archive = try FileManager.default.contentsOfDirectory(
      atPath: store.archiveDirectory.path(percentEncoded: false))
    #expect(archive.contains { $0.contains("replaced-current") })
  }

  @Test func gitContextWritesTheHandoffContextAndReportsTheBranch() async throws {
    let root = try makeRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let outputs = try await WorkflowNativeActionRunner().execute(
      actionID: "git.context", inputs: ["root": root.path(percentEncoded: false)], context: context(root: root))
    let store = HandoffStore(rootURL: root)
    #expect(outputs["path"] == store.contextURL.path(percentEncoded: false))
    #expect(outputs["branch"] == "main")
    let contextText = try String(contentsOf: store.contextURL, encoding: .utf8)
    #expect(contextText.hasPrefix("# Handoff Context (generated)"))
    #expect(contextText.contains("Outgoing agent (detected): claude"))
    let defaulted = try await WorkflowNativeActionRunner().execute(
      actionID: "git.context", inputs: [:], context: context(root: root))
    #expect(defaulted["branch"] == "main")
    await #expect(throws: WorkflowActionError.unsafePath("/tmp")) {
      try await WorkflowNativeActionRunner().execute(
        actionID: "git.context", inputs: ["root": "/tmp"], context: context(root: root))
    }
  }
}
