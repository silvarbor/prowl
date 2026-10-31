import Foundation
import JSONSchema
import ProwlCLIContracts
import ProwlCLIShared
import XCTest

final class CanvasSchemaTests: XCTestCase {
  func testSchemaAcceptsEveryActionAndTheEncodedPayload() throws {
    for action in CanvasAction.allCases {
      try assertValidity(
        #"{"ok":true,"command":"canvas","schema_version":"prowl.cli.canvas.v1","data":{"action":"\#(action.rawValue)","showing":true,"layout":"tile","card_count":3}}"#,
        expected: true
      )
    }
    // `layout` is absent until Canvas has laid out cards once.
    try assertValidity(
      #"{"ok":true,"command":"canvas","schema_version":"prowl.cli.canvas.v1","data":{"action":"status","showing":false,"card_count":0}}"#,
      expected: true
    )
    let payload = CanvasCommandPayload(action: .layout, showing: true, layout: "freeform", cardCount: 2)
    let response = try CommandResponse(
      ok: true,
      command: "canvas",
      schemaVersion: "prowl.cli.canvas.v1",
      data: RawJSON(encoding: payload)
    )
    let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(response), encoding: .utf8))
    try assertValidity(encoded, expected: true)
    try assertValidity(
      #"{"ok":false,"command":"canvas","schema_version":"prowl.cli.canvas.v1","error":{"code":"CANVAS_NOT_SHOWING","message":"Canvas is not showing."}}"#,
      expected: true
    )
  }

  func testSchemaRejectsUnknownValuesAndFields() throws {
    let invalid = [
      #"{"ok":true,"command":"canvas","schema_version":"prowl.cli.canvas.v1","data":{"action":"zoom","showing":true,"card_count":1}}"#,
      #"{"ok":true,"command":"canvas","schema_version":"prowl.cli.canvas.v1","data":{"action":"fit","showing":true,"layout":"spiral","card_count":1}}"#,
      #"{"ok":true,"command":"canvas","schema_version":"prowl.cli.canvas.v1","data":{"action":"fit","showing":true,"card_count":-1}}"#,
      #"{"ok":true,"command":"canvas","schema_version":"prowl.cli.canvas.v1","data":{"action":"fit","showing":true,"card_count":1,"extra":1}}"#,
      #"{"ok":true,"command":"canvas","schema_version":"prowl.cli.canvas.v1","data":{"action":"fit","card_count":1}}"#,
    ]
    for instance in invalid {
      try assertValidity(instance, expected: false)
    }
  }

  private func assertValidity(_ instance: String, expected: Bool) throws {
    let schemaText = try XCTUnwrap(String(data: ProwlCLIContractBundle.schemaData, encoding: .utf8))
    let result = try Schema(instance: schemaText).validate(instance: instance)
    XCTAssertEqual(result.isValid, expected, "Schema errors for \(instance): \(result.errors ?? [])")
  }
}
