import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing

@testable import supacode

@MainActor
struct AppFeatureWorkflowNoticeTests {
  @Test func completedRunNotifiesAndShowsToastInTheSelectedWorktree() async {
    let worktree = makeWorktree(id: "selected")
    var repositories = RepositoriesFeature.State(
      repositories: [makeRepository(worktrees: [worktree])]
    )
    repositories.snapshotPersistencePhase = .active
    repositories.selection = .worktree(worktree.id)
    let delivered = LockIsolated<[(Worktree.ID, WorkflowRuntimeNotification)]>([])
    let notice = makeNotice(kind: .completed, worktree: worktree)
    let store = TestStore(
      initialState: AppFeature.State(repositories: repositories)
    ) {
      AppFeature()
    } withDependencies: {
      $0.workflowRuntimeClient.notify = { target, notification in
        delivered.withValue { $0.append((target.id, notification)) }
      }
    }
    store.exhaustivity = .off

    await store.send(.workflowRuns(.delegate(.notice(notice))))
    await store.receive(\.repositories.showToast)
    await store.finish()

    #expect(delivered.value.map(\.0) == [worktree.id])
    #expect(delivered.value.first?.1.title == "Review completed")
    #expect(delivered.value.first?.1.targetSurfaceID == notice.targetSurfaceID)
    #expect(store.state.repositories.statusToast == .success("Review completed"))
  }

  @Test func backgroundAttentionNotifiesWithoutTakingOverTheSelectedToolbar() async {
    let selected = makeWorktree(id: "selected")
    let background = makeWorktree(id: "background")
    var repositories = RepositoriesFeature.State(
      repositories: [makeRepository(worktrees: [selected, background])]
    )
    repositories.snapshotPersistencePhase = .active
    repositories.selection = .worktree(selected.id)
    let delivered = LockIsolated<[(Worktree.ID, WorkflowRuntimeNotification)]>([])
    let notice = makeNotice(kind: .needsAttention, worktree: background)
    let store = TestStore(
      initialState: AppFeature.State(repositories: repositories)
    ) {
      AppFeature()
    } withDependencies: {
      $0.workflowRuntimeClient.notify = { target, notification in
        delivered.withValue { $0.append((target.id, notification)) }
      }
    }
    store.exhaustivity = .off

    await store.send(.workflowRuns(.delegate(.notice(notice))))
    await store.finish()

    #expect(delivered.value.map(\.0) == [background.id])
    #expect(store.state.repositories.statusToast == nil)
  }

  @Test func explicitCompletionNotificationStillShowsToastWithoutPostingAgain() async {
    let worktree = makeWorktree(id: "selected")
    var repositories = RepositoriesFeature.State(
      repositories: [makeRepository(worktrees: [worktree])]
    )
    repositories.snapshotPersistencePhase = .active
    repositories.selection = .worktree(worktree.id)
    let delivered = LockIsolated<[WorkflowRuntimeNotification]>([])
    var notice = makeNotice(kind: .completed, worktree: worktree)
    notice = WorkflowRunNotice(
      kind: notice.kind,
      runID: notice.runID,
      worktreeID: notice.worktreeID,
      workflowName: notice.workflowName,
      title: notice.title,
      body: notice.body,
      targetSurfaceID: notice.targetSurfaceID,
      postsNotification: false
    )
    let store = TestStore(
      initialState: AppFeature.State(repositories: repositories)
    ) {
      AppFeature()
    } withDependencies: {
      $0.workflowRuntimeClient.notify = { _, notification in
        delivered.withValue { $0.append(notification) }
      }
    }
    store.exhaustivity = .off

    await store.send(.workflowRuns(.delegate(.notice(notice))))
    await store.receive(\.repositories.showToast)
    await store.finish()

    #expect(delivered.value.isEmpty)
    #expect(store.state.repositories.statusToast == .success("Review completed"))
  }

  @Test(arguments: [WorkflowRunNotice.Kind.skipped, .maxRoundsReached])
  func selectedNonSuccessTerminalOutcomeShowsAWarning(kind: WorkflowRunNotice.Kind) async {
    let worktree = makeWorktree(id: "selected")
    var repositories = RepositoriesFeature.State(
      repositories: [makeRepository(worktrees: [worktree])]
    )
    repositories.snapshotPersistencePhase = .active
    repositories.selection = .worktree(worktree.id)
    let notice = makeNotice(kind: kind, worktree: worktree)
    let store = TestStore(
      initialState: AppFeature.State(repositories: repositories)
    ) {
      AppFeature()
    } withDependencies: {
      $0.workflowRuntimeClient.notify = { _, _ in }
    }
    store.exhaustivity = .off

    await store.send(.workflowRuns(.delegate(.notice(notice))))
    await store.receive(\.repositories.showToast)
    await store.finish()

    #expect(store.state.repositories.statusToast == .warning(notice.title))
  }

  private func makeNotice(
    kind: WorkflowRunNotice.Kind,
    worktree: Worktree
  ) -> WorkflowRunNotice {
    let title =
      switch kind {
      case .needsAttention: "Review needs attention"
      case .completed: "Review completed"
      case .skipped: "Review ended after a skipped step"
      case .maxRoundsReached: "Review reached its round limit"
      }
    return WorkflowRunNotice(
      kind: kind,
      runID: UUID(),
      worktreeID: worktree.id,
      workflowName: "Review",
      title: title,
      body: "Status changed.",
      targetSurfaceID: UUID(),
      postsNotification: true
    )
  }

  private func makeWorktree(id: String) -> Worktree {
    Worktree(
      id: id,
      name: id,
      detail: "",
      workingDirectory: URL(filePath: "/tmp/\(id)", directoryHint: .isDirectory),
      repositoryRootURL: URL(filePath: "/tmp/repo", directoryHint: .isDirectory)
    )
  }

  private func makeRepository(worktrees: [Worktree]) -> Repository {
    Repository(
      id: "/tmp/repo",
      rootURL: URL(filePath: "/tmp/repo", directoryHint: .isDirectory),
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: worktrees)
    )
  }
}
