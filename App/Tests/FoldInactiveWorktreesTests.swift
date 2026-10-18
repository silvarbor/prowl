import ComposableArchitecture
import CustomDump
import DependenciesTestSupport
import Foundation
import IdentifiedCollections
import Sharing
import Testing

@testable import Prowl

@MainActor
@Suite(.serialized)
struct FoldInactiveWorktreesTests {
  // MARK: - Section split

  @Test func settingOffKeepsEveryUnpinnedWorktreeInTheUnpinnedSection() {
    let fixture = makeFixture()
    let sections = fixture.state.worktreeRowSections(in: fixture.repository)

    #expect(sections.inactive.isEmpty)
    #expect(sections.unpinned.map(\.id) == [fixture.alpha.id, fixture.bravo.id, fixture.charlie.id])
  }

  @Test func settingOnFoldsWorktreesWithoutAnOpenTab() {
    var fixture = makeFixture()
    fixture.state.foldInactiveWorktrees = true
    fixture.state.openedWorktreeIDs = [fixture.bravo.id]
    let sections = fixture.state.worktreeRowSections(in: fixture.repository)

    #expect(sections.unpinned.map(\.id) == [fixture.bravo.id])
    #expect(sections.inactive.map(\.id) == [fixture.alpha.id, fixture.charlie.id])
    #expect(sections.main?.id == fixture.main.id)
  }

  @Test func mainPinnedPendingAndSelectedWorktreesNeverFold() {
    var fixture = makeFixture()
    fixture.state.foldInactiveWorktrees = true
    fixture.state.pinnedWorktreeIDs = [fixture.alpha.id]
    fixture.state.selection = .worktree(fixture.bravo.id)
    fixture.state.pendingWorktrees = [
      PendingWorktree(
        id: "/tmp/repo/pending",
        repositoryID: fixture.repository.id,
        progress: WorktreeCreationProgress(stage: .choosingWorktreeName, worktreeName: "pending")
      )
    ]
    let sections = fixture.state.worktreeRowSections(in: fixture.repository)

    #expect(sections.main?.id == fixture.main.id)
    #expect(sections.pinned.map(\.id) == [fixture.alpha.id])
    #expect(sections.pending.map(\.id) == ["/tmp/repo/pending"])
    #expect(sections.unpinned.map(\.id) == [fixture.bravo.id])
    #expect(sections.inactive.map(\.id) == [fixture.charlie.id])
  }

  @Test func sidebarMultiSelectionKeepsRowsOutOfTheInactiveGroup() {
    var fixture = makeFixture()
    fixture.state.foldInactiveWorktrees = true
    fixture.state.sidebarSelectedWorktreeIDs = [fixture.alpha.id, fixture.charlie.id]
    let sections = fixture.state.worktreeRowSections(in: fixture.repository)

    #expect(sections.inactive.map(\.id) == [fixture.bravo.id])
  }

  @Test func inactiveRowsKeepTheStoredUnpinnedOrder() {
    var fixture = makeFixture()
    fixture.state.foldInactiveWorktrees = true
    fixture.state.worktreeOrderByRepository[fixture.repository.id] = [
      fixture.charlie.id, fixture.alpha.id, fixture.bravo.id,
    ]
    fixture.state.openedWorktreeIDs = [fixture.alpha.id]
    let sections = fixture.state.worktreeRowSections(in: fixture.repository)

    #expect(sections.unpinned.map(\.id) == [fixture.alpha.id])
    #expect(sections.inactive.map(\.id) == [fixture.charlie.id, fixture.bravo.id])
  }

  // MARK: - Moving between groups

  @Test func firstTabMovesAWorktreeOutOfTheInactiveGroupAndLastTabCloseBack() async {
    var fixture = makeFixture()
    fixture.state.foldInactiveWorktrees = true
    let store = TestStore(initialState: fixture.state) {
      RepositoriesFeature()
    }

    #expect(store.state.worktreeRowSections(in: fixture.repository).inactive.count == 3)

    await store.send(.markWorktreeOpened(fixture.bravo.id)) {
      $0.openedWorktreeIDs = [fixture.bravo.id]
    }
    var sections = store.state.worktreeRowSections(in: fixture.repository)
    #expect(sections.unpinned.map(\.id) == [fixture.bravo.id])
    #expect(sections.inactive.map(\.id) == [fixture.alpha.id, fixture.charlie.id])

    await store.send(.markWorktreeClosed(fixture.bravo.id)) {
      $0.openedWorktreeIDs = []
    }
    sections = store.state.worktreeRowSections(in: fixture.repository)
    #expect(sections.unpinned.isEmpty)
    #expect(sections.inactive.map(\.id) == [fixture.alpha.id, fixture.bravo.id, fixture.charlie.id])
  }

  // MARK: - Navigation

  @Test func navigationSkipsFoldedRowsAndIncludesExpandedOnes() {
    var fixture = makeFixture()
    fixture.state.foldInactiveWorktrees = true
    fixture.state.openedWorktreeIDs = [fixture.bravo.id]
    let repositoryIDs: Set<Repository.ID> = [fixture.repository.id]

    expectNoDifference(
      fixture.state.navigableWorktreeRows(includingRepositoryIDs: repositoryIDs).map(\.id),
      [fixture.main.id, fixture.bravo.id]
    )

    fixture.state.$expandedInactiveRepositoryIDs.withLock { $0 = [fixture.repository.id] }
    expectNoDifference(
      fixture.state.navigableWorktreeRows(includingRepositoryIDs: repositoryIDs).map(\.id),
      [fixture.main.id, fixture.bravo.id, fixture.alpha.id, fixture.charlie.id]
    )
  }

  @Test func offsetNavigationSkipsFoldedRows() {
    var fixture = makeFixture()
    fixture.state.foldInactiveWorktrees = true
    fixture.state.openedWorktreeIDs = [fixture.bravo.id]
    fixture.state.selection = .worktree(fixture.main.id)

    #expect(fixture.state.worktreeID(byOffset: 1) == fixture.bravo.id)
    #expect(fixture.state.worktreeID(byOffset: -1) == fixture.bravo.id)

    fixture.state.$expandedInactiveRepositoryIDs.withLock { $0 = [fixture.repository.id] }
    #expect(fixture.state.worktreeID(byOffset: -1) == fixture.charlie.id)
  }

  @Test func selectNextWorktreeLandsOnTheNextActiveRow() async {
    var fixture = makeFixture()
    fixture.state.foldInactiveWorktrees = true
    fixture.state.openedWorktreeIDs = [fixture.charlie.id]
    fixture.state.selection = .worktree(fixture.main.id)
    let store = TestStore(initialState: fixture.state) {
      RepositoriesFeature()
    }

    await store.send(.selectNextWorktree)
    await store.receive(\.selectWorktree) {
      $0.selection = .worktree(fixture.charlie.id)
      $0.sidebarSelectedWorktreeIDs = [fixture.charlie.id]
      $0.worktreeHistoryBackStack = [fixture.main.id]
      $0.pendingTerminalFocusWorktreeIDs = [fixture.charlie.id]
    }
    await store.receive(\.delegate.selectedWorktreeChanged)
  }

  @Test func paletteRowsStillListEveryWorktree() {
    var fixture = makeFixture()
    let allIDs = Set(fixture.state.orderedWorktreeRows().map(\.id))
    fixture.state.foldInactiveWorktrees = true
    fixture.state.openedWorktreeIDs = [fixture.bravo.id]

    #expect(Set(fixture.state.orderedWorktreeRows().map(\.id)) == allIDs)
    #expect(allIDs.contains(fixture.alpha.id))
    #expect(fixture.state.worktreeRowSections(in: fixture.repository).allRows.count == allIDs.count)
  }

  @Test func collapsedRepositoryStaysOutOfNavigationWhateverTheInactiveState() {
    var fixture = makeFixture()
    fixture.state.foldInactiveWorktrees = true
    fixture.state.$collapsedRepositoryIDs.withLock { $0 = [fixture.repository.id] }
    fixture.state.$expandedInactiveRepositoryIDs.withLock { $0 = [fixture.repository.id] }

    #expect(fixture.state.worktreeID(byOffset: 1) == nil)
  }

  // MARK: - Fold state

  @Test func toggleExpandsAndFoldsTheInactiveGroup() async {
    let fixture = makeFixture()
    let store = TestStore(initialState: fixture.state) {
      RepositoriesFeature()
    }

    await store.send(.toggleInactiveWorktreesExpanded(fixture.repository.id)) {
      $0.$expandedInactiveRepositoryIDs.withLock { $0 = [fixture.repository.id] }
    }
    #expect(store.state.isInactiveWorktreesExpanded(in: fixture.repository.id))

    await store.send(.toggleInactiveWorktreesExpanded(fixture.repository.id)) {
      $0.$expandedInactiveRepositoryIDs.withLock { $0 = [] }
    }
    #expect(!store.state.isInactiveWorktreesExpanded(in: fixture.repository.id))
  }

  @Test func reloadPrunesExpandedStateOfRemovedRepositories() async {
    var fixture = makeFixture()
    fixture.state.$expandedInactiveRepositoryIDs.withLock { $0 = [fixture.repository.id, "/tmp/gone"] }
    let store = TestStore(initialState: fixture.state) {
      RepositoriesFeature()
    }
    store.exhaustivity = .off

    await store.send(
      .repositoriesLoaded(
        [fixture.repository],
        failures: [],
        roots: [fixture.repository.rootURL],
        animated: false
      )
    )

    #expect(store.state.expandedInactiveRepositoryIDs == [fixture.repository.id])
  }

  @Test func failedLoadKeepsExpandedStateOfThatRepository() async {
    var fixture = makeFixture()
    fixture.state.$expandedInactiveRepositoryIDs.withLock { $0 = [fixture.repository.id, "/tmp/gone"] }
    let store = TestStore(initialState: fixture.state) {
      RepositoriesFeature()
    }
    store.exhaustivity = .off

    await store.send(
      .repositoriesLoaded(
        [],
        failures: [RepositoriesFeature.LoadFailure(rootID: fixture.repository.id, message: "boom")],
        roots: [fixture.repository.rootURL],
        animated: false
      )
    )

    #expect(store.state.expandedInactiveRepositoryIDs == [fixture.repository.id])
  }

  @Test func setFoldInactiveWorktreesUpdatesState() async {
    let store = TestStore(initialState: RepositoriesFeature.State()) {
      RepositoriesFeature()
    }

    await store.send(.worktreeOrdering(.setFoldInactiveWorktrees(true))) {
      $0.foldInactiveWorktrees = true
    }
  }

  // MARK: - Drag

  @Test func moveInsideTheUnpinnedGroupMapsToTheFullOrder() async {
    var fixture = makeFixture()
    fixture.state.foldInactiveWorktrees = true
    // Full order a, b, c; b is inactive, so the visible unpinned group is a, c.
    fixture.state.worktreeOrderByRepository[fixture.repository.id] = [
      fixture.alpha.id, fixture.bravo.id, fixture.charlie.id,
    ]
    fixture.state.openedWorktreeIDs = [fixture.alpha.id, fixture.charlie.id]

    // Drag c before a: group offsets (1) -> 0 map to full offsets (2) -> 0.
    let move = fixture.state.fullUnpinnedOrderMove(
      in: fixture.repository,
      section: .unpinned,
      offsets: IndexSet(integer: 1),
      destination: 0
    )
    #expect(move?.offsets == IndexSet(integer: 2))
    #expect(move?.destination == 0)

    let store = TestStore(initialState: fixture.state) {
      RepositoriesFeature()
    }
    guard let move else { return }
    await store.send(
      .worktreeOrdering(
        .unpinnedWorktreesMoved(repositoryID: fixture.repository.id, move.offsets, move.destination)
      )
    ) {
      $0.worktreeOrderByRepository[fixture.repository.id] = [fixture.charlie.id, fixture.alpha.id, fixture.bravo.id]
    }
  }

  @Test func moveToTheEndOfTheUnpinnedGroupLandsAfterItsLastRow() {
    var fixture = makeFixture()
    fixture.state.foldInactiveWorktrees = true
    fixture.state.worktreeOrderByRepository[fixture.repository.id] = [
      fixture.alpha.id, fixture.bravo.id, fixture.charlie.id,
    ]
    fixture.state.openedWorktreeIDs = [fixture.alpha.id, fixture.charlie.id]

    // Drag a after c: group offsets (0) -> 2 map to full offsets (0) -> 3.
    let move = fixture.state.fullUnpinnedOrderMove(
      in: fixture.repository,
      section: .unpinned,
      offsets: IndexSet(integer: 0),
      destination: 2
    )
    #expect(move?.offsets == IndexSet(integer: 0))
    #expect(move?.destination == 3)
  }

  @Test func moveInsideTheInactiveGroupWritesOneStoredOrder() async {
    var fixture = makeFixture()
    fixture.state.foldInactiveWorktrees = true
    fixture.state.worktreeOrderByRepository[fixture.repository.id] = [
      fixture.alpha.id, fixture.bravo.id, fixture.charlie.id,
    ]
    fixture.state.openedWorktreeIDs = [fixture.bravo.id]

    // Inactive group is a, c. Drag c before a.
    let move = fixture.state.fullUnpinnedOrderMove(
      in: fixture.repository,
      section: .inactive,
      offsets: IndexSet(integer: 1),
      destination: 0
    )
    #expect(move?.offsets == IndexSet(integer: 2))
    #expect(move?.destination == 0)

    let store = TestStore(initialState: fixture.state) {
      RepositoriesFeature()
    }
    guard let move else { return }
    await store.send(
      .worktreeOrdering(
        .unpinnedWorktreesMoved(repositoryID: fixture.repository.id, move.offsets, move.destination)
      )
    ) {
      $0.worktreeOrderByRepository[fixture.repository.id] = [fixture.charlie.id, fixture.alpha.id, fixture.bravo.id]
    }
  }

  @Test func moveWithoutFoldingMapsToItself() {
    let fixture = makeFixture()
    let move = fixture.state.fullUnpinnedOrderMove(
      in: fixture.repository,
      section: .unpinned,
      offsets: IndexSet(integer: 0),
      destination: 3
    )

    #expect(move?.offsets == IndexSet(integer: 0))
    #expect(move?.destination == 3)
  }

  @Test func moveOutsideTheGroupIsRejected() {
    let fixture = makeFixture()

    #expect(
      fixture.state.fullUnpinnedOrderMove(
        in: fixture.repository,
        section: .inactive,
        offsets: IndexSet(integer: 0),
        destination: 0
      ) == nil
    )
  }

  // MARK: - Settings

  @Test func settingDecodesAsOffWhenMissing() throws {
    var settings = GlobalSettings.default
    settings.foldInactiveWorktrees = true
    var object = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
    )
    object.removeValue(forKey: "foldInactiveWorktrees")
    let data = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(GlobalSettings.self, from: data)

    #expect(decoded.foldInactiveWorktrees == false)
  }

  @Test func settingRoundTrips() throws {
    var settings = GlobalSettings.default
    settings.foldInactiveWorktrees = true
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(GlobalSettings.self, from: data)

    #expect(decoded.foldInactiveWorktrees == true)
  }

  // MARK: - Fixtures

  private struct Fixture {
    var state: RepositoriesFeature.State
    let repository: Repository
    let main: Worktree
    let alpha: Worktree
    let bravo: Worktree
    let charlie: Worktree
  }

  private func makeFixture() -> Fixture {
    let repoRoot = "/tmp/repo"
    let main = makeWorktree(id: repoRoot, name: "main", repoRoot: repoRoot)
    let alpha = makeWorktree(id: "/tmp/repo/a", name: "a", repoRoot: repoRoot)
    let bravo = makeWorktree(id: "/tmp/repo/b", name: "b", repoRoot: repoRoot)
    let charlie = makeWorktree(id: "/tmp/repo/c", name: "c", repoRoot: repoRoot)
    let repository = Repository(
      id: repoRoot,
      rootURL: URL(fileURLWithPath: repoRoot),
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [main, alpha, bravo, charlie])
    )
    var state = RepositoriesFeature.State()
    state.repositories = IdentifiedArray(uniqueElements: [repository])
    state.repositoryRoots = [repository.rootURL]
    return Fixture(state: state, repository: repository, main: main, alpha: alpha, bravo: bravo, charlie: charlie)
  }

  private func makeWorktree(id: String, name: String, repoRoot: String) -> Worktree {
    Worktree(
      id: id,
      name: name,
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: id),
      repositoryRootURL: URL(fileURLWithPath: repoRoot)
    )
  }
}
