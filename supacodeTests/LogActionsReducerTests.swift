import ComposableArchitecture
import Testing

@testable import supacode

private struct Counter: Reducer {
  struct State: Equatable {
    var count = 0
    var label = ""
  }

  enum Action: Equatable {
    case increment
    case setLabel(String)
  }

  func reduce(into state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .increment:
      state.count += 1
      return .none
    case .setLabel(let value):
      state.label = value
      return .none
    }
  }
}

@MainActor
struct LogActionsReducerTests {
  /// With action logging off (the default), the wrapper must reduce exactly like
  /// its base — same state mutation, no diverging behavior from the gated path.
  @Test func passesActionsThroughToBaseWhenLoggingDisabled() async {
    let store = TestStore(initialState: Counter.State()) { LogActionsReducer(base: Counter()) }

    await store.send(.increment) { $0.count = 1 }
    await store.send(.setLabel("repo")) { $0.label = "repo" }
  }

  /// A no-op action leaves state untouched, so the diff branch has nothing to
  /// print; the reducer must still return the base's effect and state.
  @Test func leavesStateUnchangedForActionsThatDoNotMutate() async {
    let store = TestStore(initialState: Counter.State(count: 5, label: "keep")) {
      LogActionsReducer(base: Counter())
    }

    await store.send(.setLabel("keep"))

    #expect(store.state.count == 5)
    #expect(store.state.label == "keep")
  }
}

struct StateDiffLogChunksTests {
  @Test func keepsAShortDiffInOneChunk() {
    let diff = "  Counter.State(\n-   count: 0,\n+   count: 1,\n  )\n"

    #expect(stateDiffLogChunks(diff) == [diff])
  }

  @Test func returnsNoChunksForAnEmptyDiff() {
    #expect(stateDiffLogChunks("").isEmpty)
  }

  @Test func breaksALongDiffAtLineEnds() {
    let diff = (0..<200).map { "+   item\($0): \"value \($0)\",\n" }.joined()

    let chunks = stateDiffLogChunks(diff, byteBudget: 256)

    #expect(chunks.count > 1)
    #expect(chunks.joined() == diff)
    for chunk in chunks {
      #expect(chunk.utf8.count <= 256)
      #expect(chunk.hasSuffix("\n"))
    }
  }

  @Test func splitsALineLongerThanTheBudget() {
    let line = String(repeating: "x", count: 1_000)
    let diff = "- before\n+ \(line)\n  after"

    let chunks = stateDiffLogChunks(diff, byteBudget: 64)

    #expect(chunks.joined() == diff)
    #expect(chunks.allSatisfy { $0.utf8.count <= 64 })
  }

  @Test func neverSplitsInsideACharacter() {
    // "é" is two UTF-8 bytes and the family emoji is one character of 25 bytes,
    // so an odd budget would cut both if splitting counted bytes alone.
    let diff = String(repeating: "é", count: 40) + String(repeating: "👨‍👩‍👧‍👦", count: 4)

    let chunks = stateDiffLogChunks(diff, byteBudget: 27)

    #expect(chunks.joined() == diff)
    #expect(chunks.allSatisfy { $0.utf8.count <= 27 })
    #expect(chunks.allSatisfy { chunk in chunk.allSatisfy { $0 == "é" || $0 == "👨‍👩‍👧‍👦" } })
  }

  @Test func splitsACharacterLongerThanTheBudgetBetweenScalars() {
    // One base letter with 500 combining acute accents (2 bytes each) is a
    // single Character of 1001 bytes, more than the production budget.
    let oversized = "a" + String(repeating: "\u{0301}", count: 500)
    let diff = "- before\n+ \(oversized)\n  after\n"

    let chunks = stateDiffLogChunks(diff)

    #expect(oversized.count == 1)
    #expect(oversized.utf8.count > stateDiffChunkByteBudget)
    #expect(chunks.count > 1)
    #expect(chunks.allSatisfy { $0.utf8.count <= stateDiffChunkByteBudget })
    #expect(chunks.joined() == diff)
    #expect(Array(chunks.joined().unicodeScalars) == Array(diff.unicodeScalars))
  }

  @Test func leavesRoomForTheLabelUnderTheLogLimit() {
    // The unified log keeps the first 1015 bytes of a message.
    let label = "State diff 999/999:\n"

    #expect(label.utf8.count + stateDiffChunkByteBudget <= 1_015)
  }
}
