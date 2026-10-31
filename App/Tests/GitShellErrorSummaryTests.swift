import Foundation
import Testing

@testable import Prowl

struct GitShellErrorSummaryTests {
  @Test func carriageReturnProgressKeepsOnlyTheFinalState() {
    let progress = (1...99).map { "Updating files:  \($0)% (\($0)/100)" }.joined(separator: "\r")
    let error = ShellClientError(
      command: "wt sw",
      stdout: "",
      stderr: """
        Preparing worktree (new branch 'zesty-badger-331')
        \(progress)\rUpdating files: 100% (100/100), done.
        .git/hooks/post-checkout: line 2: exec: mise: not found
        """,
      exitCode: 127
    )

    let message = gitErrorMessage(for: error)

    #expect(
      message == """
        stderr:
        Preparing worktree (new branch 'zesty-badger-331')
        Updating files: 100% (100/100), done.
        .git/hooks/post-checkout: line 2: exec: mise: not found
        """
    )
  }

  @Test func longOutputKeepsTheLastLines() {
    let lines = (1...50).map { "line \($0)" }
    let error = ShellClientError(
      command: "wt sw",
      stdout: lines.joined(separator: "\n"),
      stderr: "fatal: hook failed\n",
      exitCode: 1
    )

    let message = gitErrorMessage(for: error)

    let expectedStdout = (["…"] + lines.suffix(gitErrorOutputLineLimit)).joined(separator: "\n")
    #expect(message == "stdout:\n\(expectedStdout)\nstderr:\nfatal: hook failed")
  }

  @Test func emptyStreamsAreOmitted() {
    let error = ShellClientError(command: "git status", stdout: " \n", stderr: "", exitCode: 1)

    #expect(gitErrorMessage(for: error).isEmpty)
  }
}

private func gitErrorMessage(for error: ShellClientError) -> String {
  guard case .commandFailed(_, let message) = wrapShellError(error, operation: .worktreeCreate, command: "wt sw")
  else {
    Issue.record("Expected commandFailed")
    return ""
  }
  return message
}
