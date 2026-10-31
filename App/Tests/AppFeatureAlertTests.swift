import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import Prowl

@MainActor
struct AppFeatureAlertTests {
  private static func stateWithAlert() -> AppFeature.State {
    var state = AppFeature.State()
    state.alert = AlertState {
      TextState("Quit Prowl?")
    } actions: {
      ButtonState(action: .confirmQuit) {
        TextState("Quit")
      }
      ButtonState(role: .cancel, action: .dismiss) {
        TextState("Cancel")
      }
    }
    return state
  }

  @Test(.dependencies) func cancelButtonClearsAlert() async {
    let store = TestStore(initialState: Self.stateWithAlert()) {
      AppFeature()
    }

    await store.send(.alert(.presented(.dismiss))) {
      $0.alert = nil
    }
  }

  @Test(.dependencies) func quitButtonClearsAlertAndTerminates() async {
    let terminated = LockIsolated(false)
    let store = TestStore(initialState: Self.stateWithAlert()) {
      AppFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_000)
      $0.appLifecycleClient.terminate = {
        terminated.setValue(true)
      }
    }

    await store.send(.alert(.presented(.confirmQuit))) {
      $0.alert = nil
    }
    await store.finish()

    #expect(terminated.value)
  }

  @Test(.dependencies) func dismissClearsAlert() async {
    let store = TestStore(initialState: Self.stateWithAlert()) {
      AppFeature()
    }

    await store.send(.alert(.dismiss)) {
      $0.alert = nil
    }
  }
}
