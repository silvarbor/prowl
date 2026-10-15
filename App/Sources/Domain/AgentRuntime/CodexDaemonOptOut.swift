import Foundation

/// Keeps a Codex launched from an Agent Profile out of the shared app-server daemon (issue #911).
///
/// Codex 0.157+ attaches a plain interactive `codex` to one background daemon and runs every
/// thread's shell commands there, with the environment and ancestry of whichever process last
/// started that daemon. A profile launch then loses its pane identity: `PROWL_*` variables, the
/// dispatch id, the hook token, and the process tree that callers resolve through. Prowl's
/// managed notifier happens to force embedded mode (any non-allowlisted `-c` does), but a launch
/// whose hook preparation degrades has no `-c` at all, so the opt-out is applied on its own.
nonisolated enum CodexDaemonOptOut {
  static let argument = "--no-daemon"
  /// The first release that accepts `--no-daemon` (openai/codex#46088). 0.157.0 is the first
  /// release that starts the daemon by default, so older releases need no opt-out.
  static let minimumVersion = (0, 156, 0)

  /// Subcommands that do not run the interactive TUI (`codex --help`, 0.162.1, with aliases and
  /// earlier names). They either never use the daemon or reject the flag; `resume` and `fork`
  /// accept it.
  private static let nonInteractiveSubcommands: Set<String> = [
    "agents", "exec", "e", "review", "login", "logout", "mcp", "mcp-server", "plugin", "app-server",
    "remote-control", "app", "completion", "update", "doctor", "sandbox", "debug", "apply", "a", "queue",
    "archive", "delete", "migrate-rollouts", "unarchive", "cloud", "exec-server", "features", "help",
  ]
  /// Interactive subcommands that accept the flag; the arguments after them are their own.
  private static let interactiveSubcommands: Set<String> = ["resume", "fork"]

  /// Whether `codex --version` output (`codex-cli 0.162.1`, `codex-cli 0.163.0-alpha.11`)
  /// names a release that accepts the flag.
  static func isSupported(versionOutput: String) -> Bool {
    guard
      let token = versionOutput.split(whereSeparator: \.isWhitespace).first(where: {
        $0.first?.isNumber == true
      })
    else { return false }
    let core = token.prefix { $0 != "-" && $0 != "+" }
    let parts = core.split(separator: ".").map { Int($0) }
    guard parts.count == 3, let major = parts[0], let minor = parts[1], let patch = parts[2] else {
      return false
    }
    return (major, minor, patch) >= minimumVersion
  }

  /// Top-level options that take a separate value (`codex --help`, 0.162.1). Their values can
  /// spell a subcommand, such as `--cd app`.
  private static let valueOptions: Set<String> = [
    "-c", "--config", "--enable", "--disable", "--remote", "--remote-auth-token-env", "-i", "--image", "-m",
    "--model", "--local-provider", "-p", "--profile", "-s", "--sandbox", "-C", "--cd", "--add-dir", "-a",
    "--ask-for-approval",
  ]

  /// Whether the invocation starts the interactive TUI and does not already opt out. Profile
  /// options come before the extra arguments, so a subcommand can follow them. Known options
  /// consume their values. A positional that names a non-interactive subcommand skips the flag
  /// even after an unknown option, because skipping is safe and a wrong flag stops the launch.
  static func applies(to arguments: [String], promptArgumentIndex: Int?) -> Bool {
    let options = arguments.indices.prefix { arguments[$0] != "--" }.filter { $0 != promptArgumentIndex }
    // `resume` and `fork` accept the flag after them too, and Codex rejects it twice.
    guard !options.contains(where: { arguments[$0] == argument }) else { return false }
    var index = arguments.startIndex
    while index < arguments.endIndex, arguments[index] != "--" {
      defer { index += 1 }
      guard index != promptArgumentIndex else { continue }
      let current = arguments[index]
      if nonInteractiveSubcommands.contains(current) { return false }
      if interactiveSubcommands.contains(current) { return true }
      if valueOptions.contains(current), index + 1 != promptArgumentIndex { index += 1 }
    }
    return true
  }

  /// Inserts the flag ahead of the prompt positional and any `--` sentinel. The prompt stays the
  /// last argument, so the returned index replaces the caller's prompt index.
  static func applying(
    to invocation: AgentInvocation,
    promptArgumentIndex: Int?
  ) -> (invocation: AgentInvocation, promptArgumentIndex: Int?) {
    guard applies(to: invocation.arguments, promptArgumentIndex: promptArgumentIndex) else {
      return (invocation, promptArgumentIndex)
    }
    var arguments = invocation.arguments
    let insertionIndex = ManagedHookSettings.insertionIndex(
      promptArgumentIndex: promptArgumentIndex,
      arguments: arguments
    )
    arguments.insert(argument, at: insertionIndex)
    let promptIndex = promptArgumentIndex.map { $0 >= insertionIndex ? $0 + 1 : $0 }
    return (AgentInvocation(executable: invocation.executable, arguments: arguments), promptIndex)
  }
}

/// Reads `codex --version` from the executable a profile launch resolved through the login
/// shell. A failed or slow probe answers nil, and the launch keeps its arguments.
nonisolated enum CodexVersionProbe {
  static func query(executableURL: URL) async -> String? {
    // An npm-installed `codex` is a `#!/usr/bin/env node` script; the app's launchd PATH does not
    // reach node, which usually sits next to the shim.
    var environment = ProcessInfo.processInfo.environment
    let directory = executableURL.deletingLastPathComponent().path(percentEncoded: false)
    environment["PATH"] = [directory, environment["PATH"]].compactMap(\.self).joined(separator: ":")
    let process = CodexShellProbeProcess(
      timeout: 1,
      maximumOutputBytes: 1_024,
      shellOverride: executableURL,
      shellOverrideArguments: ["--version"],
      environment: environment
    )
    guard let output = try? await process.run(cwd: FileManager.default.homeDirectoryForCurrentUser, script: ""),
      output.exitCode == 0
    else { return nil }
    return output.stdout
  }
}
