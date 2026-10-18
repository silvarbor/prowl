import ComposableArchitecture
import Foundation
import Testing

@testable import Prowl

@MainActor
struct ActiveAgentsSidebarOrderTests {
  // MARK: Rank computation

  @Test func ranksListPinnedWorktreesFirstThenSidebarOrder() {
    let alphaMain = worktree("/alpha", repo: "/alpha")
    let alphaOne = worktree("/alpha-1", repo: "/alpha")
    let alphaTwo = worktree("/alpha-2", repo: "/alpha")
    let betaMain = worktree("/beta", repo: "/beta")
    let betaOne = worktree("/beta-1", repo: "/beta")
    var state = makeState(
      repositories: [
        repository("/alpha", [alphaMain, alphaOne, alphaTwo]),
        repository("/beta", [betaMain, betaOne]),
      ]
    )
    state.pinnedWorktreeIDs = [betaOne.id, alphaTwo.id]

    #expect(
      rankedIDs(state) == [alphaTwo.id, betaOne.id, alphaMain.id, alphaOne.id, betaMain.id]
    )
  }

  @Test func ranksFollowRepositoryOrderAndStoredWorktreeOrder() {
    let alphaMain = worktree("/alpha", repo: "/alpha")
    let alphaOne = worktree("/alpha-1", repo: "/alpha")
    let alphaTwo = worktree("/alpha-2", repo: "/alpha")
    let betaMain = worktree("/beta", repo: "/beta")
    var state = makeState(
      repositories: [
        repository("/alpha", [alphaMain, alphaOne, alphaTwo]),
        repository("/beta", [betaMain]),
      ]
    )
    state.repositoryOrderIDs = ["/beta", "/alpha"]
    state.worktreeOrderByRepository = ["/alpha": [alphaTwo.id, alphaOne.id]]

    #expect(rankedIDs(state) == [betaMain.id, alphaMain.id, alphaTwo.id, alphaOne.id])
  }

  @Test func archivedWorktreeHasNoRank() {
    let main = worktree("/alpha", repo: "/alpha")
    let archived = worktree("/alpha-1", repo: "/alpha")
    var state = makeState(repositories: [repository("/alpha", [main, archived])])
    state.archivedWorktrees = [ArchivedWorktree(id: archived.id, archivedAt: Date(timeIntervalSince1970: 0))]

    #expect(rankedIDs(state) == [main.id])
  }

  // MARK: Sorted entries

  @Test func entriesSortByWorktreeRankOnUpsert() async {
    let store = TestStore(initialState: rankedState(["/a": 0, "/b": 1, "/c": 2])) {
      ActiveAgentsFeature()
    }
    let inC = entry(1, worktree: "/c")
    let inA = entry(2, worktree: "/a")
    let inB = entry(3, worktree: "/b")

    await store.send(.agentEntryChanged(inC, autoShowPanel: false)) { $0.entries = [inC] }
    await store.send(.agentEntryChanged(inA, autoShowPanel: false)) { $0.entries = [inA, inC] }
    await store.send(.agentEntryChanged(inB, autoShowPanel: false)) { $0.entries = [inA, inB, inC] }
  }

  @Test func rankChangeResortsEntries() async {
    var state = rankedState(["/a": 0, "/b": 1])
    let inA = entry(1, worktree: "/a")
    let inB = entry(2, worktree: "/b")
    state.entries = [inA, inB]
    let store = TestStore(initialState: state) { ActiveAgentsFeature() }

    await store.send(.worktreeRanksChanged(["/a": 1, "/b": 0])) {
      $0.worktreeRanks = ["/a": 1, "/b": 0]
      $0.entries = [inB, inA]
    }
  }

  @Test func unchangedRanksAreIgnored() async {
    let state = rankedState(["/a": 0])
    let store = TestStore(initialState: state) { ActiveAgentsFeature() }

    await store.send(.worktreeRanksChanged(["/a": 0]))
  }

  @Test func removedAgentReturnsToItsRankPositionNotTheEnd() async {
    var state = rankedState(["/a": 0, "/b": 1, "/c": 2])
    let inA = entry(1, worktree: "/a")
    let inB = entry(2, worktree: "/b")
    let inC = entry(3, worktree: "/c")
    state.entries = [inA, inB, inC]
    let store = TestStore(initialState: state) { ActiveAgentsFeature() }

    await store.send(.agentEntryRemoved(inA.id)) { $0.entries = [inB, inC] }
    await store.send(.agentEntryChanged(inA, autoShowPanel: false)) { $0.entries = [inA, inB, inC] }
  }

  @Test func agentsOfOneWorktreeSortByTabThenPane() async {
    let store = TestStore(initialState: rankedState(["/a": 0])) { ActiveAgentsFeature() }
    let secondTab = entry(1, worktree: "/a", tabIndex: 1, paneIndex: 1)
    let firstTabSecondPane = entry(2, worktree: "/a", tabIndex: 0, paneIndex: 2)
    let firstTabFirstPane = entry(3, worktree: "/a", tabIndex: 0, paneIndex: 1)

    await store.send(.agentEntryChanged(secondTab, autoShowPanel: false)) { $0.entries = [secondTab] }
    await store.send(.agentEntryChanged(firstTabSecondPane, autoShowPanel: false)) {
      $0.entries = [firstTabSecondPane, secondTab]
    }
    await store.send(.agentEntryChanged(firstTabFirstPane, autoShowPanel: false)) {
      $0.entries = [firstTabFirstPane, firstTabSecondPane, secondTab]
    }
  }

  @Test func movedTabReordersItsAgentOnRepublish() async {
    var state = rankedState(["/a": 0])
    let first = entry(1, worktree: "/a", tabIndex: 0)
    let second = entry(2, worktree: "/a", tabIndex: 1)
    state.entries = [first, second]
    let store = TestStore(initialState: state) { ActiveAgentsFeature() }
    var movedFirst = first
    movedFirst.tabIndex = 2

    await store.send(.agentEntryChanged(movedFirst, autoShowPanel: false)) {
      $0.entries = [second, movedFirst]
    }
  }

  @Test func entryWithoutRankSortsAfterRankedEntries() async {
    let store = TestStore(initialState: rankedState(["/a": 0])) { ActiveAgentsFeature() }
    let unranked = entry(1, worktree: "/unknown")
    let ranked = entry(2, worktree: "/a")

    await store.send(.agentEntryChanged(unranked, autoShowPanel: false)) { $0.entries = [unranked] }
    await store.send(.agentEntryChanged(ranked, autoShowPanel: false)) { $0.entries = [ranked, unranked] }
  }

  @Test func entriesWithEqualKeysKeepArrivalOrder() async {
    let store = TestStore(initialState: ActiveAgentsFeature.State()) { ActiveAgentsFeature() }
    let first = entry(1, worktree: "/x")
    let second = entry(2, worktree: "/y")

    await store.send(.agentEntryChanged(first, autoShowPanel: false)) { $0.entries = [first] }
    await store.send(.agentEntryChanged(second, autoShowPanel: false)) { $0.entries = [first, second] }
  }

  @Test func keyboardNavigationWalksTheSortedOrder() async {
    var state = rankedState(["/a": 0, "/b": 1, "/c": 2])
    let inC = entry(1, worktree: "/c")
    let inA = entry(2, worktree: "/a")
    let inB = entry(3, worktree: "/b")
    state.entries = [inA, inB, inC]
    state.focusedSurfaceID = inA.surfaceID
    let store = TestStore(initialState: state) { ActiveAgentsFeature() }

    await store.send(.selectNextEntry) { $0.focusedSurfaceID = inB.surfaceID }
    await store.receive(\.entryTapped)
    await store.send(.selectNextEntry) { $0.focusedSurfaceID = inC.surfaceID }
    await store.receive(\.entryTapped)
    await store.send(.selectNextEntry) { $0.focusedSurfaceID = inA.surfaceID }
    await store.receive(\.entryTapped)
  }

  @Test func rankChangeKeepsTheIslandSelectionOnTheSameAgent() async {
    var state = rankedState(["/a": 0, "/b": 1])
    let inA = entry(1, worktree: "/a")
    let inB = entry(2, worktree: "/b")
    state.entries = [inA, inB]
    state.isIslandRosterExpanded = true
    state.islandNavigation.start(entries: state.entries, preferredEntryID: inA.id, preferredSurfaceID: nil)
    let store = TestStore(initialState: state) { ActiveAgentsFeature() }

    await store.send(.worktreeRanksChanged(["/a": 1, "/b": 0])) {
      $0.worktreeRanks = ["/a": 1, "/b": 0]
      $0.entries = [inB, inA]
    }
    #expect(store.state.islandNavigation.selectedEntryID == inA.id)
  }

  // MARK: Wiring in RepositoriesFeature

  @Test func firstAgentEntryFetchesTheSidebarRanks() async {
    let main = worktree("/alpha", repo: "/alpha")
    let feature = worktree("/alpha-1", repo: "/alpha")
    var state = makeState(repositories: [repository("/alpha", [main, feature])])
    state.pinnedWorktreeIDs = [feature.id]
    let inMain = entry(1, worktree: main.id)
    let store = TestStore(initialState: state) { RepositoriesFeature() }
    let ranks = [feature.id: 0, main.id: 1]

    await store.send(.activeAgents(.agentEntryChanged(inMain, autoShowPanel: false))) {
      $0.activeAgents.entries = [inMain]
    }
    await store.receive(\.activeAgents.worktreeRanksChanged) {
      $0.activeAgents.worktreeRanks = ranks
    }
  }

  @Test func agentUpdatesNeitherRebuildNorRefreshTheRanks() async {
    let main = worktree("/alpha", repo: "/alpha")
    let feature = worktree("/alpha-1", repo: "/alpha")
    var state = makeState(repositories: [repository("/alpha", [main, feature])])
    let inMain = entry(1, worktree: main.id)
    state.activeAgents.entries = [inMain]
    // A rank map that differs from the sidebar: only a rebuild would notice and replace it.
    let stale = [main.id: 5]
    state.activeAgents.worktreeRanks = stale
    let store = TestStore(initialState: state) { RepositoriesFeature() }
    var updated = inMain
    updated.paneTitle = "renamed"

    await store.send(.activeAgents(.agentEntryChanged(updated, autoShowPanel: false))) {
      $0.activeAgents.entries = [updated]
    }
    await store.send(.activeAgents(.agentEntryRemoved(inMain.id))) {
      $0.activeAgents.entries = []
    }
    #expect(store.state.activeAgents.worktreeRanks == stale)
  }

  @Test func pinningAWorktreeMovesItsAgentToTheTop() async {
    let main = worktree("/alpha", repo: "/alpha")
    let feature = worktree("/alpha-1", repo: "/alpha")
    var state = makeState(repositories: [repository("/alpha", [main, feature])])
    let inMain = entry(1, worktree: main.id)
    let inFeature = entry(2, worktree: feature.id)
    state.activeAgents.entries = [inMain, inFeature]
    state.activeAgents.worktreeRanks = [main.id: 0, feature.id: 1]
    let store = TestStore(initialState: state) { RepositoriesFeature() }

    await store.send(.pinnedWorktreeIDsLoaded([feature.id])) {
      $0.pinnedWorktreeIDs = [feature.id]
    }
    await store.receive(\.activeAgents.worktreeRanksChanged) {
      $0.activeAgents.worktreeRanks = [feature.id: 0, main.id: 1]
      $0.activeAgents.entries = [inFeature, inMain]
    }
  }

  @Test func sidebarChangeWithNoAgentsComputesNoRanks() async {
    let main = worktree("/alpha", repo: "/alpha")
    let feature = worktree("/alpha-1", repo: "/alpha")
    let state = makeState(repositories: [repository("/alpha", [main, feature])])
    let store = TestStore(initialState: state) { RepositoriesFeature() }

    await store.send(.pinnedWorktreeIDsLoaded([feature.id])) {
      $0.pinnedWorktreeIDs = [feature.id]
    }
  }

  // MARK: Helpers

  private func rankedIDs(_ state: RepositoriesFeature.State) -> [Worktree.ID] {
    state.worktreeRanks().sorted { $0.value < $1.value }.map(\.key)
  }

  private func rankedState(_ ranks: [Worktree.ID: Int]) -> ActiveAgentsFeature.State {
    var state = ActiveAgentsFeature.State()
    state.worktreeRanks = ranks
    return state
  }

  private func worktree(_ id: String, repo: String) -> Worktree {
    Worktree(
      id: id,
      name: URL(fileURLWithPath: id).lastPathComponent,
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: id),
      repositoryRootURL: URL(fileURLWithPath: repo)
    )
  }

  private func repository(_ id: String, _ worktrees: [Worktree]) -> Repository {
    Repository(
      id: id,
      rootURL: URL(fileURLWithPath: id),
      name: URL(fileURLWithPath: id).lastPathComponent,
      kind: .git,
      worktrees: IdentifiedArray(uniqueElements: worktrees),
      workspace: nil
    )
  }

  private func makeState(repositories: [Repository]) -> RepositoriesFeature.State {
    var state = RepositoriesFeature.State()
    state.repositories = IdentifiedArray(uniqueElements: repositories)
    state.repositoryRoots = repositories.map(\.rootURL)
    return state
  }

  private func entry(
    _ seed: UInt8,
    worktree: Worktree.ID,
    tabIndex: Int = 0,
    paneIndex: Int = 1
  ) -> ActiveAgentEntry {
    let id = UUID(uuid: (seed, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    return ActiveAgentEntry(
      id: id,
      worktreeID: worktree,
      worktreeName: "wt",
      workingDirectory: nil,
      tabID: TerminalTabID(rawValue: UUID()),
      paneTitle: "1",
      surfaceID: id,
      paneIndex: paneIndex,
      tabIndex: tabIndex,
      iconLookupToken: DetectedAgent.codex.iconLookupToken,
      agent: .codex,
      rawState: .idle,
      displayState: .idle,
      lastChangedAt: Date(timeIntervalSince1970: 10)
    )
  }
}
