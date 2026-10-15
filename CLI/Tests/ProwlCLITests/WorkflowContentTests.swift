import Foundation
import Testing
@testable import ProwlCLIShared
@testable import prowl

struct WorkflowContentTests {
  @Test func taskReferencesGrantOnlyExplicitKnownResources() throws {
    let root = URL(filePath: "/history/run")
    let granted = root.appending(path: "deliveries/review.1.md")
    let other = root.appending(path: "deliveries/private.2.md")
    let content = WorkflowTaskContent.make(
      text: "Read \(granted.path)", task: (UUID(), 1), runDirectory: root,
      knownPaths: [granted.path, other.path, "/etc/passwd"], skill: nil)
    #expect(content.resources.count == 1)
    #expect(content.resources.values.first == granted.path)
    #expect(!content.text.contains(granted.path))
    #expect(content.text.contains("workflow-resource:"))
    #expect(content.resources.values.contains(other.path) == false)
    #expect(content.resources.values.contains("/etc/passwd") == false)
  }

  @Test func taskInputsCannotGrantMetadataOrAnotherRolesInstructions() {
    let root = URL(filePath: "/history/run")
    let paths = [root.appending(path: "run.json").path, root.appending(path: "prompts/private.2.md").path]
    let content = WorkflowTaskContent.make(
      text: paths.joined(separator: " "), task: (UUID(), 1), runDirectory: root, knownPaths: paths, skill: nil)
    #expect(content.resources.isEmpty)
  }

  @Test func readCommandUsesRunAndInvocation() throws {
    let command = try WorkflowCommand.parseAsRoot(["read", "resource-1", "--run", UUID().uuidString, "--invocation", "3", "--json"])
    #expect(command is WorkflowReadCommand)
  }

  @Test func readCommandAcceptsTheStepToken() throws {
    let command = try WorkflowCommand.parseAsRoot([
      "read", "--run", UUID().uuidString, "--invocation", "3", "--token", "TOKEN-1",
    ])
    #expect((command as? WorkflowReadCommand)?.token == "TOKEN-1")
  }

  @Test func typedGuidanceSpellsTheTokenAndLaunchGuidanceDoesNot() {
    let runID = UUID()
    let content = WorkflowTaskContent(runID: runID, invocation: 2, text: "Task", resources: [:], skill: nil)
    let command = "prowl workflow read --run \(runID.uuidString) --invocation 2"
    #expect(content.readCommand == command)
    #expect(content.readCommand(token: "TOKEN-1") == "PROWL_WORKFLOW_TOKEN=TOKEN-1 " + command)
    #expect(content.guidance(token: "TOKEN-1").contains("`PROWL_WORKFLOW_TOKEN=TOKEN-1 \(command) <resource-id>`"))
    #expect(!content.guidance.contains("PROWL_WORKFLOW_TOKEN"))
  }
}
