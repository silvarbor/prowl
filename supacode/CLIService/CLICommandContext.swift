// supacode/CLIService/CLICommandContext.swift
// Per-connection context threaded from the socket server to handlers.

import Foundation

nonisolated struct CallerProcessIdentity: Sendable, Equatable {
  let processID: pid_t
  let startedAt: Date?
}

/// Connection-scoped facts about the calling `prowl` process. The ancestry is
/// frozen at accept time because a short-lived hook may exit before MainActor
/// routing begins.
nonisolated struct CLICommandContext: Sendable, Equatable {
  let callerProcessID: pid_t?
  let callerProcessAncestry: [CallerProcessIdentity]

  init(callerProcessID: pid_t? = nil) {
    self.callerProcessID = callerProcessID
    callerProcessAncestry = []
  }

  init(
    callerProcessID: pid_t?,
    callerProcessAncestry: [CallerProcessIdentity]
  ) {
    self.callerProcessID = callerProcessID
    self.callerProcessAncestry = callerProcessAncestry
  }
}

/// A pane owned by the process ancestry of a CLI caller.
nonisolated struct CallerPane: Sendable, Equatable {
  let worktreeID: Worktree.ID
  let surfaceID: UUID
  let processAncestry: [AgentProcessGeneration]

  init(
    worktreeID: Worktree.ID,
    surfaceID: UUID,
    processAncestry: [AgentProcessGeneration] = []
  ) {
    self.worktreeID = worktreeID
    self.surfaceID = surfaceID
    self.processAncestry = processAncestry
  }
}

/// Resolves the calling `prowl` process to the pane whose shell spawned it by
/// walking the caller's process ancestry against the live shell-PID map. A
/// caller outside any Prowl pane (another terminal app, a script, tmux's
/// server-owned processes) resolves to nil — never to a guess.
nonisolated enum CallerPaneResolver {
  static func processAncestry(
    forCallerProcess callerPID: pid_t,
    parentProcessID: (pid_t) -> pid_t? = { pid in
      ProcessDetection.processBSDInfo(pid: pid).map { pid_t($0.pbi_ppid) }
    },
    processStartDate: (pid_t) -> Date? = ProcessDetection.processStartDate
  ) -> [CallerProcessIdentity] {
    var pid = callerPID
    var hops = 0
    var ancestry: [CallerProcessIdentity] = []
    while pid > 1, hops < 32 {
      ancestry.append(
        CallerProcessIdentity(processID: pid, startedAt: processStartDate(pid))
      )
      guard let parent = parentProcessID(pid), parent != pid else { break }
      pid = parent
      hops += 1
    }
    return ancestry
  }

  static func pane(
    forCallerProcess callerPID: pid_t,
    paneByShellPID: [pid_t: CallerPane],
    parentProcessID: (pid_t) -> pid_t? = { pid in
      ProcessDetection.processBSDInfo(pid: pid).map { pid_t($0.pbi_ppid) }
    },
    processStartDate: (pid_t) -> Date? = ProcessDetection.processStartDate
  ) -> CallerPane? {
    pane(
      forCallerProcessAncestry: processAncestry(
        forCallerProcess: callerPID,
        parentProcessID: parentProcessID,
        processStartDate: processStartDate
      ),
      paneByShellPID: paneByShellPID
    )
  }

  static func pane(
    forCallerProcessAncestry identities: [CallerProcessIdentity],
    paneByShellPID: [pid_t: CallerPane]
  ) -> CallerPane? {
    var generations: [AgentProcessGeneration] = []
    for identity in identities {
      if let startedAt = identity.startedAt {
        generations.append(
          AgentProcessGeneration(pid: identity.processID, startedAt: startedAt)
        )
      }
      if let pane = paneByShellPID[identity.processID] {
        return CallerPane(
          worktreeID: pane.worktreeID,
          surfaceID: pane.surfaceID,
          processAncestry: generations
        )
      }
    }
    return nil
  }
}
