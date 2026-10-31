import ArgumentParser
import ProwlCLIShared
import XCTest

@testable import prowl

final class CanvasCommandParsingTests: XCTestCase {
  func testRootRoutesEverySubcommand() throws {
    XCTAssertTrue(try ProwlCommand.parseAsRoot(["canvas", "show"]) is CanvasShowCommand)
    XCTAssertTrue(try ProwlCommand.parseAsRoot(["canvas", "hide"]) is CanvasHideCommand)
    XCTAssertTrue(try ProwlCommand.parseAsRoot(["canvas", "layout", "tile"]) is CanvasLayoutCommand)
    XCTAssertTrue(try ProwlCommand.parseAsRoot(["canvas", "fit"]) is CanvasFitCommand)
    XCTAssertTrue(try ProwlCommand.parseAsRoot(["canvas", "status", "--json"]) is CanvasStatusCommand)
  }

  func testLayoutParsesEveryLayoutAndTheShowFlag() throws {
    for layout in CanvasLayoutName.allCases {
      let command = try CanvasLayoutCommand.parse([layout.rawValue])
      XCTAssertEqual(command.layout, layout)
      XCTAssertFalse(command.show)
    }
    XCTAssertTrue(try CanvasLayoutCommand.parse(["organize", "--show"]).show)
    XCTAssertTrue(try CanvasFitCommand.parse(["--show"]).show)
  }

  func testLayoutRejectsAnUnknownOrMissingLayout() {
    XCTAssertThrowsError(try CanvasLayoutCommand.parse(["spiral"]))
    XCTAssertThrowsError(try CanvasLayoutCommand.parse([]))
  }

  func testShowAndHideTakeNoShowFlag() {
    XCTAssertThrowsError(try CanvasShowCommand.parse(["--show"]))
  }
}
