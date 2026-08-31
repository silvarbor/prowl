import Foundation
import Testing

@testable import supacode

struct CallerPaneResolverTests {
  @Test func resolvesDirectAndNestedCallerAncestry() {
    let pane = CallerPane(worktreeID: "wt", surfaceID: UUID())
    let parents: [pid_t: pid_t] = [400: 300, 300: 200, 200: 100]

    #expect(
      CallerPaneResolver.pane(
        forCallerProcess: 100,
        paneByShellPID: [100: pane],
        parentProcessID: { parents[$0] },
        processStartDate: { _ in nil }
      ) == pane
    )
    #expect(
      CallerPaneResolver.pane(
        forCallerProcess: 400,
        paneByShellPID: [100: pane],
        parentProcessID: { parents[$0] },
        processStartDate: { _ in nil }
      ) == pane
    )
  }

  @Test func resolvesFromAnAncestrySnapshotAfterTheCallerIsGone() throws {
    let pane = CallerPane(worktreeID: "wt", surfaceID: UUID())
    let callerStart = Date(timeIntervalSince1970: 100)
    let agentStart = Date(timeIntervalSince1970: 90)
    let identities = [
      CallerProcessIdentity(processID: 400, startedAt: callerStart),
      CallerProcessIdentity(processID: 300, startedAt: agentStart),
      CallerProcessIdentity(processID: 100, startedAt: nil),
    ]

    let resolved = try #require(
      CallerPaneResolver.pane(
        forCallerProcessAncestry: identities,
        paneByShellPID: [100: pane]
      )
    )

    #expect(resolved.surfaceID == pane.surfaceID)
    #expect(
      resolved.processAncestry == [
        AgentProcessGeneration(pid: 400, startedAt: callerStart),
        AgentProcessGeneration(pid: 300, startedAt: agentStart),
      ]
    )
  }

  @Test func unresolvedAndCyclicAncestryNeverGuess() {
    let focusedButUnrelated = CallerPane(worktreeID: "focused", surfaceID: UUID())

    #expect(
      CallerPaneResolver.pane(
        forCallerProcess: 400,
        paneByShellPID: [100: focusedButUnrelated],
        parentProcessID: { _ in nil },
        processStartDate: { _ in nil }
      ) == nil
    )
    #expect(
      CallerPaneResolver.pane(
        forCallerProcess: 400,
        paneByShellPID: [100: focusedButUnrelated],
        parentProcessID: { $0 },
        processStartDate: { _ in nil }
      ) == nil
    )
  }

  @Test func ancestryWalkIsBounded() {
    let pane = CallerPane(worktreeID: "wt", surfaceID: UUID())

    #expect(
      CallerPaneResolver.pane(
        forCallerProcess: 100,
        paneByShellPID: [67: pane],
        parentProcessID: { $0 - 1 },
        processStartDate: { _ in nil }
      ) == nil
    )
    #expect(
      CallerPaneResolver.pane(
        forCallerProcess: 100,
        paneByShellPID: [69: pane],
        parentProcessID: { $0 - 1 },
        processStartDate: { _ in nil }
      ) == pane
    )
  }
}
