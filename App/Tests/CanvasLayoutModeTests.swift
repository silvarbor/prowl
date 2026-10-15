import Foundation
import Testing

@testable import Prowl

struct CanvasLayoutModeTests {
  @Test(arguments: [CanvasLayoutMode.freeform, .automatic(.arrange), .automatic(.organize), .automatic(.tile)])
  func roundTripsThroughJSON(mode: CanvasLayoutMode) throws {
    let data = try JSONEncoder().encode([mode])
    #expect(try JSONDecoder().decode([CanvasLayoutMode].self, from: data) == [mode])
  }

  @Test func encodesAsAPlainString() throws {
    let data = try JSONEncoder().encode([CanvasLayoutMode.automatic(.tile), .freeform])
    #expect(String(bytes: data, encoding: .utf8) == #"["tile","freeform"]"#)
  }

  @Test func rejectsAnUnknownValue() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode([CanvasLayoutMode].self, from: Data(#"["spiral"]"#.utf8))
    }
  }

  @Test func automaticLayoutRelayoutsWhenItCan() {
    let mode = CanvasLayoutMode.automatic(.tile)
    #expect(mode.cardSetChangeAction(canRelayoutNow: true) == .relayout(.tile))
    #expect(mode.cardSetChangeAction(canRelayoutNow: false) == .placeNewCardsAndRelayoutLater)
  }

  @Test func freeformOnlyPlacesNewCards() {
    #expect(CanvasLayoutMode.freeform.cardSetChangeAction(canRelayoutNow: true) == .placeNewCards)
    #expect(CanvasLayoutMode.freeform.cardSetChangeAction(canRelayoutNow: false) == .placeNewCards)
  }
}
