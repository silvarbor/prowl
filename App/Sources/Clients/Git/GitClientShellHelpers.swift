import Foundation
import Sentry

nonisolated let gitLogger = ProwlLogger("Git")

/// Only direct Git discovery can establish that a folder is not a repository.
/// Existing or inaccessible metadata makes the result uncertain, even if Git says otherwise.
nonisolated func isConfirmedNonRepository(_ error: Error, at directory: URL) -> Bool {
  guard let error = error as? ShellClientError, error.exitCode == 128 else { return false }
  let message = error.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
  let lines = message.split(separator: "\n", omittingEmptySubsequences: false)
  let stoppedAtBoundary =
    lines.count == 2
    && lines[0].hasPrefix("fatal: not a git repository (or any parent up to mount point /")
    && lines[0].hasSuffix(")")
    && lines[1] == "Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set)."
  guard
    message == "fatal: not a git repository (or any of the parent directories): .git"
      || stoppedAtBoundary
  else {
    return false
  }
  var current = directory.resolvingSymlinksInPath().standardizedFileURL
  while true {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: current.path) else {
      return false
    }
    if names.contains(".git") || (names.contains("HEAD") && names.contains("objects")) {
      return false
    }
    let parent = current.deletingLastPathComponent().standardizedFileURL
    if parent.path == current.path { return true }
    current = parent
  }
}

/// The most output lines per stream that a Git error message keeps.
nonisolated let gitErrorOutputLineLimit = 20

/// Keeps the end of a command's output, where Git and hooks report the failure.
/// Progress output rewrites one line with carriage returns, so only the text after
/// the last carriage return of each line stays.
nonisolated func gitErrorOutputSummary(_ output: String) -> String {
  let lines =
    output
    .split(separator: "\n", omittingEmptySubsequences: false)
    .map { line in
      line.split(separator: "\r").last { !$0.allSatisfy(\.isWhitespace) }.map(String.init) ?? ""
    }
    .filter { !$0.allSatisfy(\.isWhitespace) }
  guard lines.count > gitErrorOutputLineLimit else { return lines.joined(separator: "\n") }
  return (["…"] + lines.suffix(gitErrorOutputLineLimit)).joined(separator: "\n")
}

nonisolated func wrapShellError(
  _ error: Error,
  operation: GitOperation,
  command: String
) -> GitClientError {
  let gitError: GitClientError
  var exitCode: Int32 = -1
  if let shellError = error as? ShellClientError {
    exitCode = shellError.exitCode
    var messageParts: [String] = []
    let stdout = gitErrorOutputSummary(shellError.stdout)
    if !stdout.isEmpty {
      messageParts.append("stdout:\n\(stdout)")
    }
    let stderr = gitErrorOutputSummary(shellError.stderr)
    if !stderr.isEmpty {
      messageParts.append("stderr:\n\(stderr)")
    }
    let message = messageParts.joined(separator: "\n")
    gitError = .commandFailed(command: command, message: message)
  } else {
    gitError = .commandFailed(command: command, message: error.localizedDescription)
  }
  gitLogger.warning("git command failed operation=\(operation.rawValue) exit_code=\(exitCode)")
  #if !DEBUG
    SentrySDK.logger.error(
      "git command failed",
      attributes: [
        "operation": operation.rawValue,
        "exit_code": Int(exitCode),
      ]
    )
  #endif
  return gitError
}
