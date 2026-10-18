import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import Prowl

/// `detectAgentState` re-emits on any `PaneAgentState` change, including
/// internal bookkeeping churn (raw-state oscillation, session miss streaks).
/// `emitAgentEntry` must forward only consumer-visible `ActiveAgentEntry`
/// changes so that churn never floods the terminal event stream.
@MainActor
struct AgentEntryEmissionDedupTests {
  @Test func rawStateAndBookkeepingChangesDoNotReEmit() {
    let fixture = makeFixture()
    var received: [ActiveAgentEntry] = []
    fixture.state.onAgentEntryChanged = { received.append($0) }

    // Same visible entry; only rawState (fallbackState) and internal bookkeeping
    // differ across the three emits.
    var paneState = PaneAgentState(detectedAgent: .claude, fallbackState: .working, state: .working)
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: paneState)
    paneState.sessionMissStreak = 1
    paneState.fallbackState = .idle
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: paneState)
    paneState.sessionMissStreak = 2
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: paneState)

    // rawState never renders in the sidebar, so a raw-only flicker must not
    // re-emit; only the first (visible) entry is forwarded.
    #expect(received.count == 1)
    #expect(received.map(\.rawState) == [.working])
  }

  @Test func visibleChangeStillEmits() {
    let fixture = makeFixture()
    var received: [ActiveAgentEntry] = []
    fixture.state.onAgentEntryChanged = { received.append($0) }

    let working = PaneAgentState(detectedAgent: .claude, state: .working)
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: working)
    let idle = PaneAgentState(detectedAgent: .claude, state: .idle)
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: idle)

    #expect(received.map(\.displayState) == [.working, .idle])
  }

  @Test func removalClearsTheCacheSoReattachEmits() {
    let fixture = makeFixture()
    var changed: [ActiveAgentEntry] = []
    var removed: [UUID] = []
    fixture.state.onAgentEntryChanged = { changed.append($0) }
    fixture.state.onAgentEntryRemoved = { removed.append($0) }

    let working = PaneAgentState(detectedAgent: .claude, state: .working)
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: working)
    // Agent went away (no detected agent -> no entry).
    fixture.state.emitAgentEntry(
      surfaceID: fixture.pane.id,
      tabId: fixture.tabId,
      state: PaneAgentState()
    )
    // Same agent comes back with the same visible entry: must emit again.
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: working)

    #expect(changed.count == 2)
    #expect(removed == [fixture.pane.id])
  }

  @Test func entryCarriesItsTabPosition() {
    let fixture = makeFixture()
    var received: [ActiveAgentEntry] = []
    fixture.state.onAgentEntryChanged = { received.append($0) }
    _ = fixture.state.tabManager.createTab(title: "worktree 2", icon: "terminal")

    fixture.state.emitAgentEntry(
      surfaceID: fixture.pane.id,
      tabId: fixture.tabId,
      state: PaneAgentState(detectedAgent: .claude, state: .working)
    )

    #expect(received.map(\.tabIndex) == [0])
  }

  @Test func reorderingTabsRepublishesTheAgentsWhosePositionChanged() {
    let fixture = makeFixture()
    let otherTab = fixture.state.tabManager.createTab(title: "worktree 2", icon: "terminal")
    var received: [ActiveAgentEntry] = []
    fixture.state.surfaceAgentStates[fixture.pane.id] = PaneAgentState(detectedAgent: .claude, state: .working)
    fixture.state.emitAgentEntry(
      surfaceID: fixture.pane.id,
      tabId: fixture.tabId,
      state: PaneAgentState(detectedAgent: .claude, state: .working)
    )
    fixture.state.onAgentEntryChanged = { received.append($0) }

    fixture.state.tabManager.reorderTabs([otherTab, fixture.tabId])
    #expect(received.map(\.tabIndex) == [1])

    // A write to one tab's fields does not move any tab and republishes nothing.
    fixture.state.tabManager.updateDirty(fixture.tabId, isDirty: true)
    #expect(received.count == 1)
  }

  @Test func closingAnEarlierTabRepublishesTheAgentsOfLaterTabs() {
    let fixture = makeFixture()
    let earlier = fixture.state.tabManager.createTab(title: "earlier", icon: nil)
    fixture.state.tabManager.reorderTabs([earlier, fixture.tabId])
    fixture.state.surfaceAgentStates[fixture.pane.id] = PaneAgentState(detectedAgent: .claude, state: .working)
    fixture.state.emitAgentEntry(
      surfaceID: fixture.pane.id,
      tabId: fixture.tabId,
      state: PaneAgentState(detectedAgent: .claude, state: .working)
    )
    var received: [ActiveAgentEntry] = []
    fixture.state.onAgentEntryChanged = { received.append($0) }

    fixture.state.tabManager.closeTab(earlier)

    #expect(received.map(\.tabIndex) == [0])
  }

  @Test func movingAPaneRepublishesTheAgentsWhosePositionChanged() throws {
    let fixture = makeFixture()
    let other = GhosttySurfaceView(
      runtime: fixture.state.runtime,
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/worktree", isDirectory: true),
      fontSize: nil,
      context: GHOSTTY_SURFACE_CONTEXT_SPLIT,
      skipsSurfaceCreationForTesting: true
    )
    fixture.state.surfaces[other.id] = other
    let paneState = PaneAgentState(detectedAgent: .claude, state: .working)
    let original = try SplitTree<GhosttySurfaceView>(view: fixture.pane)
      .inserting(view: other, at: fixture.pane, direction: .right)
    fixture.state.updateTree(original, for: fixture.tabId)
    fixture.state.surfaceAgentStates[fixture.pane.id] = paneState
    fixture.state.surfaceAgentStates[other.id] = paneState
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: paneState)
    fixture.state.emitAgentEntry(surfaceID: other.id, tabId: fixture.tabId, state: paneState)
    var received: [ActiveAgentEntry] = []
    fixture.state.onAgentEntryChanged = { received.append($0) }

    // A resize keeps the pane order and republishes nothing.
    fixture.state.updateTree(original.equalized(), for: fixture.tabId)
    #expect(received.isEmpty)

    let swapped = try SplitTree<GhosttySurfaceView>(view: other)
      .inserting(view: fixture.pane, at: other, direction: .right)
    fixture.state.updateTree(swapped, for: fixture.tabId)

    #expect(Set(received.map(\.surfaceID)) == [fixture.pane.id, other.id])
    #expect(received.first { $0.surfaceID == fixture.pane.id }?.paneIndex == 2)
    #expect(received.first { $0.surfaceID == other.id }?.paneIndex == 1)
  }

  /// `equalsIgnoringRawState` normalizes one field and compares the rest through
  /// the synthesized `==`. Nothing structural stops a later edit from
  /// normalizing a second field, and the damage would be silent: the helper
  /// still compiles, every test above still passes, and the only symptom is a
  /// real change to that field never reaching the sidebar. `emitAgentEntry`
  /// promises "displayState, title, session, …" still emit, so pin the whole
  /// promise — one differing field must always be enough to break equality.
  @Test func everyFieldExceptRawStateBreaksEmissionEquality() {
    let base = Self.entry()
    let variants: [(field: String, entry: ActiveAgentEntry)] = [
      ("id", Self.entry(id: Self.otherID)),
      ("worktreeID", Self.entry(worktreeID: "/tmp/repo/other")),
      ("worktreeName", Self.entry(worktreeName: "other")),
      // Resolves the repository and branch the row displays, so a suppressed
      // change leaves the sidebar naming the directory the agent has left.
      ("workingDirectory", Self.entry(workingDirectory: URL(fileURLWithPath: "/tmp/repo/other"))),
      ("workingDirectory=nil", Self.entry(workingDirectory: nil)),
      ("tabID", Self.entry(tabID: Self.otherTabID)),
      ("paneTitle", Self.entry(paneTitle: "other title")),
      ("surfaceID", Self.entry(surfaceID: Self.otherID)),
      ("paneIndex", Self.entry(paneIndex: 2)),
      // Orders the agent in the Active Agents panel, so a tab that moved must republish it.
      ("tabIndex", Self.entry(tabIndex: 1)),
      ("iconLookupToken", Self.entry(iconLookupToken: "codex")),
      ("agent", Self.entry(agent: .codex)),
      ("launchProfileName", Self.entry(launchProfileName: "Review Profile")),
      // Carries the resume target `prowl agents` reports; a suppressed change
      // would keep pointing at the previous session's transcript.
      ("session", Self.entry(session: Self.otherSession)),
      ("session=nil", Self.entry(session: nil)),
      ("displayState", Self.entry(displayState: .blocked)),
      ("lastChangedAt", Self.entry(lastChangedAt: Date(timeIntervalSince1970: 5_000))),
    ]

    for variant in variants {
      #expect(
        !base.equalsIgnoringRawState(variant.entry),
        "A change to \(variant.field) must still emit; normalizing it would hide the change from the sidebar"
      )
    }

    // The single field the helper exists to ignore.
    #expect(base.equalsIgnoringRawState(Self.entry(rawState: .idle)))
  }

  @Test func diagnosticReasonsDoNotEmitButWorkEvidenceDoes() {
    var base = Self.entry()
    base.stateDecision = AgentStateDecision(
      state: .working, reason: .logOpenWork,
      screenReason: .noRuleMatched, logSessionID: "a", hasOutstandingWork: true)
    var changed = base
    changed.stateDecision?.reason = .fallback(.afterTurn)
    changed.stateDecision?.screenReason = nil
    #expect(base != changed)
    #expect(base.equalsIgnoringRawState(changed))
    #expect(base.equalsIgnoringRawStateAndPaneTitle(changed))
    changed.stateDecision?.hasOutstandingWork = false
    #expect(!base.equalsIgnoringRawState(changed))
    changed = base
    changed.stateDecision?.logSessionID = "b"
    #expect(!base.equalsIgnoringRawState(changed))
    changed = base
    changed.stateDecision?.state = .blocked
    #expect(!base.equalsIgnoringRawState(changed))
    changed.stateDecision = nil
    #expect(!base.equalsIgnoringRawState(changed))
  }

  private static let baseID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
  private static let otherID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
  /// Fixed rather than freshly generated, so two entries under comparison differ
  /// only in the field the case is about.
  private static let baseTabID = TerminalTabID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!)
  private static let otherTabID = TerminalTabID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!)
  private static let baseSession = AgentSession(
    id: "session-1",
    transcriptPath: URL(fileURLWithPath: "/tmp/transcripts/session-1.jsonl"),
    source: .openFile,
    confidence: .exact
  )
  private static let otherSession = AgentSession(
    id: "session-2",
    transcriptPath: URL(fileURLWithPath: "/tmp/transcripts/session-2.jsonl"),
    source: .openFile,
    confidence: .exact
  )

  /// Defaults spell out every field so a case can override exactly one and the
  /// assertion stays about that field alone.
  private static func entry(
    id: UUID = baseID,
    worktreeID: Worktree.ID = "/tmp/repo/worktree",
    worktreeName: String = "worktree",
    workingDirectory: URL? = URL(fileURLWithPath: "/tmp/repo/worktree"),
    tabID: TerminalTabID = baseTabID,
    paneTitle: String = "spx-h",
    surfaceID: UUID = baseID,
    paneIndex: Int = 1,
    tabIndex: Int = 0,
    iconLookupToken: String = "claude",
    agent: DetectedAgent = .claude,
    launchProfileName: String? = nil,
    session: AgentSession? = baseSession,
    rawState: AgentRawState = .working,
    displayState: AgentDisplayState = .working,
    lastChangedAt: Date = Date(timeIntervalSince1970: 1_000)
  ) -> ActiveAgentEntry {
    ActiveAgentEntry(
      id: id,
      worktreeID: worktreeID,
      worktreeName: worktreeName,
      workingDirectory: workingDirectory,
      tabID: tabID,
      paneTitle: paneTitle,
      surfaceID: surfaceID,
      paneIndex: paneIndex,
      tabIndex: tabIndex,
      iconLookupToken: iconLookupToken,
      agent: agent,
      session: session,
      rawState: rawState,
      displayState: displayState,
      lastChangedAt: lastChangedAt,
      launchProfileName: launchProfileName
    )
  }

  private struct Fixture {
    let state: WorktreeTerminalState
    let tabId: TerminalTabID
    let pane: GhosttySurfaceView
  }

  private func makeFixture() -> Fixture {
    let state = WorktreeTerminalState(
      runtime: GhosttyRuntime(),
      worktree: Worktree(
        id: "/tmp/repo/worktree",
        name: "worktree",
        detail: "",
        workingDirectory: URL(fileURLWithPath: "/tmp/repo/worktree"),
        repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
      )
    )
    let pane = GhosttySurfaceView(
      runtime: state.runtime,
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/worktree", isDirectory: true),
      fontSize: nil,
      context: GHOSTTY_SURFACE_CONTEXT_TAB,
      skipsSurfaceCreationForTesting: true
    )
    let tabId = state.tabManager.createTab(title: "worktree 1", icon: "terminal")
    state.surfaces[pane.id] = pane
    state.trees[tabId] = SplitTree<GhosttySurfaceView>(view: pane)
    state.focusedSurfaceIdByTab[tabId] = pane.id
    return Fixture(state: state, tabId: tabId, pane: pane)
  }
}
