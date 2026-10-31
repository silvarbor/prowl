import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Sharing
import Testing

@testable import Prowl

/// Consent before the first side-channel connection (docs-ai 082, L0 item 12): the stored
/// answer, the panel the first `ssh` raises, and the toolbar status order.
@MainActor
struct RemoteAgentConsentTests {
  private let prompt = RemoteAgentConsentPrompt(worktreeID: "/tmp/repo", surfaceID: UUID(), destination: "mini")

  @Test func theEnvironmentOverridesTheStoredAnswer() {
    #expect(RemoteAgentDetection.mode(environment: [:], consent: .undecided) == .awaitingConsent)
    #expect(RemoteAgentDetection.mode(environment: [:], consent: .enabled) == .enabled)
    #expect(RemoteAgentDetection.mode(environment: [:], consent: .disabled) == .disabled)
    let turnedOff = ["PROWL_REMOTE_AGENT_DETECTION": "0"]
    let turnedOn = ["PROWL_REMOTE_AGENT_DETECTION": "1"]
    #expect(RemoteAgentDetection.mode(environment: turnedOff, consent: .enabled) == .disabled)
    #expect(RemoteAgentDetection.mode(environment: turnedOn, consent: .disabled) == .enabled)
    // Neither value asks: an override never waits for an answer.
    #expect(RemoteAgentDetection.mode(environment: turnedOn, consent: .undecided) == .enabled)
    #expect(RemoteAgentDetection.mode(environment: turnedOff, consent: .undecided) == .disabled)
  }

  @Test func theSwitchShowsOnUnlessTurnedOff() {
    #expect(RemoteAgentDetectionConsent.undecided.showsEnabled)
    #expect(RemoteAgentDetectionConsent.enabled.showsEnabled)
    #expect(!RemoteAgentDetectionConsent.disabled.showsEnabled)
  }

  @Test func theAnswerPersistsAndAnUnknownValueAsksAgain() throws {
    #expect(GlobalSettings.default.remoteAgentDetection == .undecided)
    var settings = GlobalSettings.default
    settings.remoteAgentDetection = .disabled
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(GlobalSettings.self, from: data).remoteAgentDetection == .disabled)

    var dictionary = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    dictionary["remoteAgentDetection"] = "askLater"
    let future = try JSONSerialization.data(withJSONObject: dictionary)
    #expect(try JSONDecoder().decode(GlobalSettings.self, from: future).remoteAgentDetection == .undecided)
    dictionary.removeValue(forKey: "remoteAgentDetection")
    let older = try JSONSerialization.data(withJSONObject: dictionary)
    #expect(try JSONDecoder().decode(GlobalSettings.self, from: older).remoteAgentDetection == .undecided)
  }

  @Test(.dependencies) func theFirstSSHShowsThePanelAndTurnOnStoresTheAnswer() async {
    let commands = LockIsolated<[TerminalClient.Command]>([])
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in commands.withValue { $0.append(command) } }
    }
    store.exhaustivity = .off

    await store.send(
      .terminalEvent(
        .remoteAgentConsentNeeded(
          worktreeID: prompt.worktreeID, surfaceID: prompt.surfaceID, destination: prompt.destination))
    ) {
      $0.remoteAgentConsentPrompt = prompt
    }
    await store.send(.remoteAgentConsent(.turnOn)) {
      $0.remoteAgentConsentPrompt = nil
    }
    await store.receive(\.settings.setRemoteAgentDetection) {
      $0.settings.remoteAgentDetection = .enabled
    }
    await store.receive(\.settings.delegate.settingsChanged)
    await store.finish()
    #expect(commands.value.contains(.setRemoteAgentDetection(.enabled)))
    @Shared(.settingsFile) var settingsFile
    #expect(settingsFile.global.remoteAgentDetection == .enabled)
  }

  @Test(.dependencies) func notNowWaitsForTheNextLaunch() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }
    store.exhaustivity = .off
    let event = TerminalClient.Event.remoteAgentConsentNeeded(
      worktreeID: prompt.worktreeID, surfaceID: prompt.surfaceID, destination: prompt.destination)

    await store.send(.terminalEvent(event)) {
      $0.remoteAgentConsentPrompt = prompt
    }
    await store.send(.remoteAgentConsent(.notNow)) {
      $0.remoteAgentConsentPrompt = nil
      $0.isRemoteAgentConsentDeferred = true
    }
    // Another `ssh` in this launch does not ask again, and nothing is stored.
    await store.send(.terminalEvent(event))
    #expect(store.state.remoteAgentConsentPrompt == nil)
    #expect(store.state.settings.remoteAgentDetection == .undecided)
  }

  @Test(.dependencies) func turnOffStoresTheAnswer() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }
    store.exhaustivity = .off

    await store.send(
      .terminalEvent(
        .remoteAgentConsentNeeded(
          worktreeID: prompt.worktreeID, surfaceID: prompt.surfaceID, destination: prompt.destination)))
    await store.send(.remoteAgentConsent(.turnOff)) {
      $0.remoteAgentConsentPrompt = nil
    }
    await store.receive(\.settings.setRemoteAgentDetection) {
      $0.settings.remoteAgentDetection = .disabled
    }
  }

  @Test(.dependencies) func aStoredAnswerNeverShowsThePanel() async {
    var state = AppFeature.State()
    state.settings.remoteAgentDetection = .disabled
    let store = TestStore(initialState: state) {
      AppFeature()
    }

    await store.send(
      .terminalEvent(
        .remoteAgentConsentNeeded(
          worktreeID: prompt.worktreeID, surfaceID: prompt.surfaceID, destination: prompt.destination)))
  }

  @Test(.dependencies) func answeringInSettingsClosesThePanel() async {
    var state = AppFeature.State()
    state.remoteAgentConsentPrompt = prompt
    let store = TestStore(initialState: state) {
      AppFeature()
    }
    store.exhaustivity = .off
    var settings = GlobalSettings.default
    settings.remoteAgentDetection = .enabled

    await store.send(.settings(.delegate(.settingsChanged(settings)))) {
      $0.remoteAgentConsentPrompt = nil
    }
  }

  @Test func theConsentPanelOutranksWorkAndTheChannelSitsAbovePullRequests() {
    let idle = WorkflowStatusCenterPresentation(
      state: WorkflowRunsFeature.State(), selectedWorktreeID: nil, now: Date(timeIntervalSince1970: 0))
    let channel = RemoteChannelToolbarStatus(
      .connected(host: "dev@mini", ssh: LocalProcessGeneration(pid: 1, startedAt: .distantPast)))
    #expect(channel != nil)

    #expect(
      ToolbarStatusSelection(
        toast: .success("Saved"), workflow: idle, pullRequest: nil, remoteAgentConsent: prompt)
        == .toast(.success("Saved")))
    #expect(
      ToolbarStatusSelection(
        toast: nil, workflow: idle, pullRequest: nil, remoteAgentConsent: prompt, remoteChannel: channel)
        == .remoteAgentConsent(prompt))
    #expect(
      ToolbarStatusSelection(toast: nil, workflow: idle, pullRequest: nil, remoteChannel: channel)
        == .remoteChannel(channel!))
    #expect(ToolbarStatusSelection(toast: nil, workflow: idle, pullRequest: nil) == .motivational)
  }

  @Test func onlyAPaneWithASideChannelShowsInTheToolbar() throws {
    let ssh = LocalProcessGeneration(pid: 1, startedAt: .distantPast)
    let failed = try #require(
      RemoteChannelToolbarStatus(.connected(host: "mini", ssh: ssh, issue: .probeUnavailable(.authentication))))
    #expect(failed.host == "mini")
    #expect(failed.issue == .probeUnavailable(.authentication))
    // Prowl never connects for an `ssh` outside the grammar, and an ended one has no channel.
    #expect(RemoteChannelToolbarStatus(.connected(host: "mini", ssh: ssh, issue: .unsupported("-N"))) == nil)
    #expect(RemoteChannelToolbarStatus(.ended(host: "mini", endedAt: .distantPast)) == nil)
    #expect(RemoteChannelToolbarStatus(nil) == nil)
  }
}
