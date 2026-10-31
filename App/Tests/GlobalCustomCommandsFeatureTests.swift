import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import Prowl

@MainActor
struct GlobalCustomCommandsFeatureTests {
  @Test(.dependencies) func taskLoadsPersistedGlobalSettings() async throws {
    let storage = UserGlobalSettingsTestStorage()
    let url = URL(fileURLWithPath: "/tmp/prowl-global-settings-\(UUID().uuidString).json")
    let persisted = UserGlobalSettings(customCommands: [makeCommand()])
    let encoder = JSONEncoder()
    try storage.storage.save(try encoder.encode(persisted), url)

    let store = TestStore(initialState: GlobalCustomCommandsFeature.State()) {
      GlobalCustomCommandsFeature()
    } withDependencies: {
      $0.settingsFileStorage = storage.storage
      $0.userGlobalSettingsURL = url
    }

    await store.send(.task)
    await store.receive(\.settingsLoaded) {
      $0.settings = persisted
    }
  }

  @Test(.dependencies) func bindingNormalizesPersistsAndNotifiesDelegate() async throws {
    let storage = UserGlobalSettingsTestStorage()
    let url = URL(fileURLWithPath: "/tmp/prowl-global-settings-\(UUID().uuidString).json")
    let command = makeCommand(
      shortcut: UserCustomShortcut(key: " B ", modifiers: .init(command: true, shift: true))
    )
    let expected = UserGlobalSettings(customCommands: [command])

    let store = TestStore(initialState: GlobalCustomCommandsFeature.State()) {
      GlobalCustomCommandsFeature()
    } withDependencies: {
      $0.settingsFileStorage = storage.storage
      $0.userGlobalSettingsURL = url
    }

    await store.send(.binding(.set(\.settings, UserGlobalSettings(customCommands: [command])))) {
      $0.settings = expected
    }
    await store.receive(\.delegate.settingsChanged)

    let saved = try JSONDecoder().decode(
      UserGlobalSettings.self,
      from: #require(storage.data(at: url))
    )
    #expect(saved == expected)
    #expect(saved.customCommands.first?.shortcut?.key == "b")
  }

  @Test(.dependencies) func bindingPersistsInsideTheReducer() throws {
    // Reduce without running the returned effect: the shared write must
    // already be visible, so a Settings sidebar switch that tears this pane
    // down can never drop the edit.
    let storage = UserGlobalSettingsTestStorage()
    let url = URL(fileURLWithPath: "/tmp/prowl-global-settings-\(UUID().uuidString).json")
    let edited = UserGlobalSettings(customCommands: [makeCommand()])
    withDependencies {
      $0.settingsFileStorage = storage.storage
      $0.userGlobalSettingsURL = url
    } operation: {
      var state = GlobalCustomCommandsFeature.State()
      _ = GlobalCustomCommandsFeature()._reduce(into: &state, action: .binding(.set(\.settings, edited)))
      @Shared(.userGlobalSettings) var stored
      #expect(stored == edited)
    }
  }

  @Test(.dependencies) func bindingKeepsFieldsWrittenElsewhereWhileOpen() throws {
    // The pane's settings are a load-time snapshot; agent profiles saved
    // by another pane in the meantime must survive a custom-command edit.
    let storage = UserGlobalSettingsTestStorage()
    let url = URL(fileURLWithPath: "/tmp/prowl-global-settings-\(UUID().uuidString).json")
    let profile = AgentProfile(name: "Codex", runtime: .codex)
    withDependencies {
      $0.settingsFileStorage = storage.storage
      $0.userGlobalSettingsURL = url
    } operation: {
      var state = GlobalCustomCommandsFeature.State()
      @Shared(.userGlobalSettings) var stored
      $stored.withLock { $0.agentProfiles = [profile] }
      _ = GlobalCustomCommandsFeature()._reduce(
        into: &state,
        action: .binding(.set(\.settings, UserGlobalSettings(customCommands: [makeCommand()])))
      )
      #expect(stored.customCommands == [makeCommand()])
      #expect(stored.agentProfiles == [profile])
    }
  }

  private func makeCommand(shortcut: UserCustomShortcut? = nil) -> UserCustomCommand {
    UserCustomCommand(
      id: "global-build",
      title: "Build Everywhere",
      systemImage: "globe",
      command: "make build",
      execution: .shellScript,
      shortcut: shortcut
    )
  }
}
