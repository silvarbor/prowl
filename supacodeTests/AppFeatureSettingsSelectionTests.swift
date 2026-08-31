import ComposableArchitecture
import Dependencies
import DependenciesTestSupport
import Foundation
import Sharing
import Testing

@testable import supacode

@MainActor
struct AppFeatureSettingsSelectionTests {
  @Test func selectingRepositoryCreatesRepositorySettingsState() async {
    let repository = Repository(
      id: "repo-id",
      rootURL: URL(fileURLWithPath: "/tmp/repo"),
      name: "Repo",
      worktrees: []
    )
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: RepositoriesFeature.State(repositories: [repository]),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    }

    await store.send(.settings(.setSelection(.repository(repository.id)))) {
      $0.settings.selection = .repository(repository.id)
      $0.settings.repositorySettings = RepositorySettingsFeature.State(
        rootURL: repository.rootURL,
        repositoryID: repository.id,
        repositoryKind: repository.kind,
        settings: .default,
        userSettings: .default
      )
    }
  }

  @Test func selectingMissingRepositoryClearsRepositorySettingsState() async {
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: RepositoriesFeature.State(repositories: []),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    }

    await store.send(.settings(.setSelection(.repository("missing")))) {
      $0.settings.selection = .repository("missing")
      $0.settings.repositorySettings = nil
    }
  }

  @Test func selectingPlainRepositoryCreatesPlainRepositorySettingsState() async {
    let repository = Repository(
      id: "folder-id",
      rootURL: URL(fileURLWithPath: "/tmp/folder"),
      name: "Folder",
      kind: .plain,
      worktrees: []
    )
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: RepositoriesFeature.State(repositories: [repository]),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    }

    await store.send(.settings(.setSelection(.repository(repository.id)))) {
      $0.settings.selection = .repository(repository.id)
      $0.settings.repositorySettings = RepositorySettingsFeature.State(
        rootURL: repository.rootURL,
        repositoryID: repository.id,
        repositoryKind: .plain,
        settings: .default,
        userSettings: .default
      )
    }
  }

  @Test(.dependencies) func selectingRepositorySeedsAppearanceSynchronously() async {
    // Regression: selecting a repo whose appearance is already in
    // @Shared used to construct a State with `.empty` appearance and
    // load asynchronously via .task. The async hop raced with the
    // user's first click, sometimes wiping previously-saved fields.
    // The State must now carry the appearance from frame zero.
    let storage = SettingsTestStorage()
    let appearancesURL = URL(fileURLWithPath: "/tmp/appearances-\(UUID().uuidString).json")
    let savedAppearance = RepositoryAppearance(
      icon: .sfSymbol("hammer.fill"), color: .blue
    )
    let repository = Repository(
      id: "appearance-repo",
      rootURL: URL(fileURLWithPath: "/tmp/appearance-repo"),
      name: "AppearanceRepo",
      worktrees: []
    )

    await withDependencies {
      $0.settingsFileStorage = storage.storage
      $0.repositoryAppearancesFileURL = appearancesURL
    } operation: {
      @Shared(.repositoryAppearances) var appearances
      $appearances.withLock {
        $0[repository.id] = savedAppearance
      }

      let store = TestStore(
        initialState: AppFeature.State(
          repositories: RepositoriesFeature.State(repositories: [repository]),
          settings: SettingsFeature.State()
        )
      ) {
        AppFeature()
      } withDependencies: {
        $0.settingsFileStorage = storage.storage
        $0.repositoryAppearancesFileURL = appearancesURL
      }

      await store.send(.settings(.setSelection(.repository(repository.id)))) {
        $0.settings.selection = .repository(repository.id)
        $0.settings.repositorySettings = RepositorySettingsFeature.State(
          rootURL: repository.rootURL,
          repositoryID: repository.id,
          repositoryKind: repository.kind,
          settings: .default,
          userSettings: .default,
          appearance: savedAppearance
        )
      }
    }
  }

  @Test func selectingNonRepositoryClearsRepositorySettingsState() async {
    let repository = Repository(
      id: "repo-id",
      rootURL: URL(fileURLWithPath: "/tmp/repo"),
      name: "Repo",
      worktrees: []
    )
    var state = AppFeature.State(
      repositories: RepositoriesFeature.State(repositories: [repository]),
      settings: SettingsFeature.State()
    )
    state.settings.selection = .repository(repository.id)
    state.settings.repositorySettings = RepositorySettingsFeature.State(
      rootURL: repository.rootURL,
      repositoryKind: repository.kind,
      settings: .default,
      userSettings: .default
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    }

    await store.send(.settings(.setSelection(.general))) {
      $0.settings.selection = .general
      $0.settings.repositorySettings = nil
    }
  }

  @Test(.dependencies) func openAgentProfilesSettingsSelectsProfiles() async {
    let shown = LockIsolated(false)
    var state = AppFeature.State(settings: SettingsFeature.State())
    state.settings.selection = .commandLineTool
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.settingsWindowClient.show = {
        shown.withValue { $0 = true }
      }
    }

    await store.send(.openAgentProfilesSettings)
    await store.receive(\.settings.setSelection) {
      $0.settings.selection = .profiles
      $0.settings.agentProfiles = .init()
    }
    await store.finish()

    #expect(shown.value)
  }

  @Test(arguments: [SettingsSection.general, .commandLineTool])
  func selectingAnotherSectionClearsAgentProfileEditorState(section: SettingsSection) async {
    let profile = AgentProfile(name: "Codex", runtime: .codex)
    var state = AppFeature.State(settings: SettingsFeature.State())
    state.settings.selection = .profiles
    var agentProfiles = AgentProfilesFeature.State()
    agentProfiles.settings = UserGlobalSettings(customCommands: [], agentProfiles: [profile])
    agentProfiles.path.append(AgentProfileEditorFeature.State(profile: profile))
    state.settings.agentProfiles = agentProfiles
    let store = TestStore(initialState: state) {
      AppFeature()
    }

    await store.send(.settings(.setSelection(section))) {
      $0.settings.selection = section
      $0.settings.agentProfiles = nil
      if section == .commandLineTool {
        $0.settings.agentSkills = .init()
      }
    }
  }

  @Test func selectingCommandLineToolInitialisesAgentSkillsState() async {
    let store = TestStore(initialState: AppFeature.State(settings: SettingsFeature.State())) {
      AppFeature()
    }

    await store.send(.settings(.setSelection(.commandLineTool))) {
      $0.settings.selection = .commandLineTool
      $0.settings.agentSkills = .init()
    }
  }

  @Test(arguments: [SettingsSection.general, .profiles])
  func selectingAnotherSectionClearsAgentSkillsState(section: SettingsSection) async {
    var state = AppFeature.State(settings: SettingsFeature.State())
    state.settings.selection = .commandLineTool
    state.settings.agentSkills = .init()
    let store = TestStore(initialState: state) {
      AppFeature()
    }

    await store.send(.settings(.setSelection(section))) {
      $0.settings.selection = section
      $0.settings.agentSkills = nil
      if section == .profiles {
        $0.settings.agentProfiles = .init()
      }
    }
  }
}
