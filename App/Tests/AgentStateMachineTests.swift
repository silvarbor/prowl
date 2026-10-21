import Testing

@testable import Prowl

struct AgentStateMachineTests {
  private func screen(_ state: AgentRawState) -> AgentDetectionEvent {
    .screen(AgentScreenDetection(state: state, reason: .noRuleMatched))
  }

  @Test func screenOnlyDecisionPreservesRuleIdentifier() {
    var machine = AgentStateMachine()
    let detection = AgentScreenDetection(state: .working, reason: .matched(AgentScreenRuleID("pi.working")))
    #expect(machine.receive(.screen(detection), now: 0).reason.identifier == "pi.working")
  }

  @Test func screenOnlyPreservesUnknownForEveryAgent() {
    for _ in DetectedAgent.allCases {
      var machine = AgentStateMachine()
      for state in [AgentRawState.working, .blocked, .idle] {
        #expect(machine.receive(screen(state), now: 0).state == state)
        #expect(machine.receive(screen(.unknown), now: 1).state == state)
      }
    }
  }

  @Test func loneIdleScreenFrameCannotEndAConfirmedWorkingTurn() {
    // traecli repaints its live region on the terminal's own clock (0.209.1 draws as
    // slowly as once a second while a turn streams), so a single Idle frame can be a
    // repaint gap: the running footer is the only Working evidence, and the composer's
    // status row reads the same in both states. One frame must not flip the pane.
    var machine = AgentStateMachine()
    machine.requiresConfirmedIdleScreen = true
    // Settling from unknown is immediate: there is no Working state to protect.
    #expect(machine.receive(screen(.idle), now: 0).state == .idle)
    #expect(machine.receive(screen(.working), now: 1).state == .working)

    // A lone Idle frame is held, and a Working frame drops it without a transition.
    #expect(machine.receive(screen(.idle), now: 2).state == .working)
    #expect(machine.receive(screen(.working), now: 3).state == .working)
    #expect(machine.receive(screen(.idle), now: 4).state == .working)
    #expect(machine.receive(screen(.working), now: 5).state == .working)
  }

  @Test func repeatedIdleReadsInsideTheWindowCannotConfirmATurn() {
    // Counting observations instead of time let a burst of Idle frames confirm a
    // running turn. `agents read` polls the pane outside the detection cadence, so two
    // Idle reads of one frame arrive a millisecond apart, and a repaint gap publishes
    // Idle frames at the 300 ms cadence until the footer returns. The verdict has to
    // keep arriving for the window instead, which is what separates a gap from a
    // settled turn.
    var machine = AgentStateMachine()
    machine.requiresConfirmedIdleScreen = true
    machine.confirmedIdleWindow = 2
    _ = machine.receive(screen(.working), now: 0)
    #expect(machine.receive(screen(.idle), now: 1).state == .working)
    // The same frame, re-read out of cadence: no new evidence, no confirmation.
    #expect(machine.receive(screen(.idle), now: 1.001).state == .working)
    // The redraw-gap replay: Working → Idle → Idle → Working at the poll cadence.
    #expect(machine.receive(screen(.idle), now: 1.3).state == .working)
    #expect(machine.receive(screen(.idle), now: 1.6).state == .working)
    #expect(machine.receive(screen(.working), now: 1.9).state == .working)
    // A genuine settle confirms, because the Idle verdict keeps arriving past the
    // window.
    #expect(machine.receive(screen(.idle), now: 5).state == .working)
    #expect(machine.receive(screen(.idle), now: 6.9).state == .working)
    #expect(machine.receive(screen(.idle), now: 7).state == .idle)
  }

  @Test func idleConfirmationGatesOnlyTheWorkingEdge() {
    var machine = AgentStateMachine()
    machine.requiresConfirmedIdleScreen = true
    machine.confirmedIdleWindow = 2
    // Idle → Working stays immediate so a starting turn never lags.
    #expect(machine.receive(screen(.idle), now: 0).state == .idle)
    #expect(machine.receive(screen(.working), now: 1).state == .working)
    // Working → Blocked stays immediate: a dialog is chrome, not a repaint gap.
    #expect(machine.receive(screen(.blocked), now: 2).state == .blocked)
    // A dialog closing back onto the composer is a real transition.
    #expect(machine.receive(screen(.idle), now: 3).state == .idle)
  }

  @Test func unreadableScreenNeitherConfirmsNorCancelsTheIdleHold() {
    var machine = AgentStateMachine()
    machine.requiresConfirmedIdleScreen = true
    machine.confirmedIdleWindow = 2
    _ = machine.receive(screen(.working), now: 0)
    #expect(machine.receive(screen(.idle), now: 1).state == .working)
    // `unknown` renders no verdict, so it neither confirms the hold nor re-arms it.
    // Re-arming would strand a pane whose screen alternates Idle and unreadable on a
    // stale Working, which is the failure that reading a hint-less composer as Idle
    // exists to avoid.
    #expect(machine.receive(screen(.unknown), now: 2).state == .working)
    // The hold started at the first Idle frame and keeps running, so the window
    // elapses here even though this is only the second readable Idle verdict.
    #expect(machine.receive(screen(.idle), now: 4).state == .idle)
  }

  @Test func agentsWithoutTheConfirmationPublishIdleOnTheFirstFrame() {
    var machine = AgentStateMachine()
    _ = machine.receive(screen(.working), now: 0)
    #expect(machine.receive(screen(.idle), now: 1).state == .idle)
  }

  @Test func quietTurnNeverExpiresAndBlockedScreenWins() {
    var machine = AgentStateMachine()
    _ = machine.receive(screen(.idle), now: 0)
    _ = machine.receive(.inventory(["a"]), now: 0)
    #expect(machine.receive(.turnStarted(session: "a", turn: "1"), now: 1).state == .working)
    #expect(machine.receive(.tick, now: 10_000).state == .working)
    #expect(machine.receive(screen(.blocked), now: 10_001).state == .blocked)
    #expect(machine.receive(screen(.idle), now: 10_002).state == .working)
  }

  @Test func ambiguityRecoversAtClosedActivityDeadline() {
    var machine = AgentStateMachine()
    _ = machine.receive(screen(.idle), now: 0)
    _ = machine.receive(.inventory(["a", "b"]), now: 0)
    _ = machine.receive(.turnStarted(session: "a", turn: "1"), now: 0)
    _ = machine.receive(.turnEnded(session: "a", turn: "1"), now: 1)
    #expect(machine.receive(.turnStarted(session: "b", turn: "2"), now: 10).logSessionID == nil)
    #expect(machine.receive(.tick, now: 120.999).logSessionID == nil)
    #expect(machine.receive(.tick, now: 121).logSessionID == "b")
  }

  @Test func childOutlivesParentAndOldEndCannotCloseNewTurn() {
    var machine = AgentStateMachine()
    _ = machine.receive(screen(.idle), now: 0)
    _ = machine.receive(.inventory(["a"]), now: 0)
    _ = machine.receive(.turnStarted(session: "a", turn: "1"), now: 0)
    _ = machine.receive(.childStarted(root: "a", child: "c", work: "c1"), now: 1)
    #expect(machine.receive(.turnEnded(session: "a", turn: "1"), now: 2).hasOutstandingWork)
    #expect(machine.receive(.tick, now: 1000).state == .working)
    _ = machine.receive(.turnStarted(session: "a", turn: "2"), now: 1001)
    _ = machine.receive(.childEnded(root: "a", child: "c", work: "c1"), now: 1002)
    #expect(machine.receive(.turnEnded(session: "a", turn: "1"), now: 1003).state == .working)
  }

  @Test func logFailureUsesScreenHistoryRatherThanLogWorking() {
    var machine = AgentStateMachine()
    _ = machine.receive(screen(.idle), now: 0)
    _ = machine.receive(.inventory(["a"]), now: 0)
    _ = machine.receive(.turnStarted(session: "a", turn: "1"), now: 1)
    _ = machine.receive(screen(.unknown), now: 2)
    #expect(machine.receive(.unavailable, now: 3).state == .idle)
    #expect(machine.receive(.inventory(["a"]), now: 4).logSessionID == nil)
  }

  @Test func incompleteInventorySuspendsAuthorityWithoutLosingOpenWork() {
    var machine = AgentStateMachine()
    _ = machine.receive(screen(.idle), now: 0)
    _ = machine.receive(.inventory(["a"]), now: 0)
    _ = machine.receive(.turnStarted(session: "a", turn: "1"), now: 1)
    #expect(machine.receive(.suspended, now: 2).state == .idle)
    #expect(machine.receive(.inventory(["a"]), now: 3).state == .working)
  }
  @Test func completionFencesRetainedBlockerButNotNewInteraction() {
    var machine = AgentStateMachine()
    _ = machine.receive(.inventory(["a"]), now: 0)
    _ = machine.receive(.turnStarted(session: "a", turn: "1"), now: 1)
    _ = machine.receive(screen(.blocked), now: 2)
    #expect(machine.receive(.turnEnded(session: "a", turn: "1"), now: 3).state == .idle)
    #expect(machine.receive(screen(.blocked), now: 4).state == .idle)
    #expect(machine.receive(.interaction, now: 5).state == .blocked)
  }

  @Test func staleChildEndCannotCloseReusedChild() {
    var machine = AgentStateMachine()
    _ = machine.receive(.inventory(["a"]), now: 0)
    _ = machine.receive(.childStarted(root: "a", child: "c", work: "old"), now: 1)
    _ = machine.receive(.childStarted(root: "a", child: "c", work: "new"), now: 2)
    #expect(machine.receive(.childEnded(root: "a", child: "c", work: "old"), now: 3).hasOutstandingWork)
    #expect(!machine.receive(.childEnded(root: "a", child: "c", work: "new"), now: 4).hasOutstandingWork)
  }

  @Test func lateSchedulingNoticeCannotReplaceAnObservedChildTurn() {
    var machine = AgentStateMachine()
    _ = machine.receive(.inventory(["a"]), now: 0)
    _ = machine.receive(.turnStarted(session: "a", turn: "main"), now: 1)
    _ = machine.receive(.childStarted(root: "a", child: "c", work: "actual"), now: 2)
    _ = machine.receive(.childScheduled(root: "a", child: "c", work: "pending"), now: 3)
    _ = machine.receive(.turnEnded(session: "a", turn: "main"), now: 4)
    #expect(machine.receive(.childEnded(root: "a", child: "c", work: "actual"), now: 5).state == .idle)
  }

  @Test func changedBlockerWithSameRuleIsFreshEvidence() {
    var machine = AgentStateMachine()
    let blocker = AgentScreenDetection(state: .blocked, reason: .noRuleMatched)
    _ = machine.receive(.inventory(["a"]), now: 0)
    _ = machine.receive(.turnStarted(session: "a", turn: "1"), now: 1)
    _ = machine.receive(.screen(blocker, contentID: 1), now: 2)
    _ = machine.receive(.turnEnded(session: "a", turn: "1"), now: 3)
    #expect(machine.receive(.screen(blocker, contentID: 1), now: 4).state == .idle)
    #expect(machine.receive(.screen(blocker, contentID: 2), now: 5).state == .blocked)
  }

  @Test func childCompletionDoesNotRefreshMainActivityWindow() {
    var machine = AgentStateMachine()
    _ = machine.receive(.inventory(["a", "b"]), now: 0)
    _ = machine.receive(.turnStarted(session: "a", turn: "1"), now: 0)
    _ = machine.receive(.turnEnded(session: "a", turn: "1"), now: 1)
    _ = machine.receive(.childStarted(root: "a", child: "c", work: "1"), now: 2)
    _ = machine.receive(.turnStarted(session: "b", turn: "2"), now: 10)
    #expect(machine.receive(.tick, now: 1000).logSessionID == nil)
    #expect(machine.receive(.childEnded(root: "a", child: "c", work: "1"), now: 1001).logSessionID == "b")
  }

  @Test func suspensionRecoveryRetainsCompletedFrameFence() {
    for state in [AgentRawState.working, .blocked] {
      var machine = AgentStateMachine()
      _ = machine.receive(.inventory(["a"]), now: 0)
      _ = machine.receive(.turnStarted(session: "a", turn: "1"), now: 0)
      _ = machine.receive(screen(state), now: 0)
      _ = machine.receive(.turnEnded(session: "a", turn: "1"), now: 1)
      #expect(machine.receive(.suspended, now: 2).state == .idle)
      #expect(machine.receive(.inventory(["a"]), now: 3).state == .idle)
    }
  }

  @Test func activityExpiryDoesNotReviveCompletedFrame() {
    for state in [AgentRawState.working, .blocked] {
      var machine = AgentStateMachine()
      _ = machine.receive(.inventory(["a"]), now: 0)
      _ = machine.receive(.turnStarted(session: "a", turn: "1"), now: 0)
      _ = machine.receive(screen(state), now: 0)
      _ = machine.receive(.turnEnded(session: "a", turn: "1"), now: 1)
      #expect(machine.receive(.tick, now: 121).state == .idle)
      #expect(machine.decision.logSessionID == nil)
      #expect(machine.receive(.interaction, now: 122).state == state)
    }
  }

  @Test func completionFenceDoesNotHideAnotherRootsBlocker() {
    var machine = AgentStateMachine()
    _ = machine.receive(.inventory(["a", "b"]), now: 0)
    _ = machine.receive(.turnStarted(session: "a", turn: "1"), now: 0)
    _ = machine.receive(screen(.blocked), now: 0)
    _ = machine.receive(.turnEnded(session: "a", turn: "1"), now: 1)
    #expect(machine.receive(.childStarted(root: "b", child: "c", work: "1"), now: 122).state == .blocked)
  }

}
