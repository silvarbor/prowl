import Foundation
import ProwlCLIShared
import XCTest

@testable import prowl

final class WorkflowCommandExecutorTests: XCTestCase {
  private var root: URL!
  private var home: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appending(path: "prowl-workflow-executor-\(UUID().uuidString)", directoryHint: .isDirectory)
      .standardizedFileURL
    home = root.appending(path: "home", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  private func executor(bundledSkillIDs: Set<String>? = ["prowl.adversarial-reviewer"]) -> WorkflowCommandExecutor {
    WorkflowCommandExecutor(bundledSkillIDs: bundledSkillIDs, homeDirectory: home, currentDirectory: root)
  }

  @discardableResult
  private func write(_ yaml: String, at relativePath: String) throws -> URL {
    let url = root.appending(path: relativePath, directoryHint: .notDirectory)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(yaml.utf8).write(to: url)
    return url
  }

  func testValidateReportsAValidFileWithItsIdentity() throws {
    let url = try write(WorkflowFixtures.minimal(id: "demo"), at: "flows/demo.yaml")
    let payload = try executor().validate(path: "flows/demo.yaml", scope: nil)
    XCTAssertTrue(payload.valid)
    XCTAssertEqual(payload.path, url.path(percentEncoded: false))
    XCTAssertEqual(payload.workflow, WorkflowIdentity(id: "demo", name: "Demo"))
    XCTAssertEqual(payload.diagnostics, [])
  }

  func testValidateReportsErrorsWithPositions() throws {
    try write(WorkflowFixtures.minimal(id: "demo", extraSteps: "  - id: b\n    close: ghost"), at: "bad.yaml")
    let payload = try executor().validate(path: "bad.yaml", scope: nil)
    XCTAssertFalse(payload.valid)
    XCTAssertEqual(payload.workflow?.id, "demo", "A file that parses keeps its identity")
    XCTAssertEqual(payload.diagnostics.map(\.code), ["undefined_role"])
    XCTAssertEqual(payload.diagnostics.first?.line, 12)
  }

  func testScopeIsInferredFromTheDirectoryUnlessOverridden() throws {
    try write(WorkflowFixtures.adversarialReview, at: "home/.prowl/workflows/review.yaml")
    try write(WorkflowFixtures.adversarialReview, at: "repo/.prowl/workflows/review.yaml")
    try write(WorkflowFixtures.adversarialReview, at: "elsewhere/review.yaml")
    let executor = executor()

    XCTAssertEqual(executor.inferredScope(of: root.appending(path: "home/.prowl/workflows/review.yaml")), .user)
    XCTAssertEqual(executor.inferredScope(of: root.appending(path: "repo/.prowl/workflows/review.yaml")), .repo)
    XCTAssertEqual(executor.inferredScope(of: root.appending(path: "elsewhere/review.yaml")), .user)

    let inferred = try executor.validate(path: "repo/.prowl/workflows/review.yaml", scope: nil)
    XCTAssertEqual(inferred.diagnostics.map(\.code), ["reserved_id"])
    let bundle = try executor.validate(path: "repo/.prowl/workflows/review.yaml", scope: .bundle)
    XCTAssertTrue(bundle.valid)
  }

  func testSkillsAreUncheckedWithoutABundle() throws {
    try write(WorkflowFixtures.adversarialReview, at: "review.yaml")
    let payload = try executor(bundledSkillIDs: nil).validate(path: "review.yaml", scope: .bundle)
    XCTAssertTrue(payload.valid)
    XCTAssertEqual(payload.diagnostics.map(\.code), ["skill_unchecked"])
  }

  func testMissingAndDirectoryPathsFailWithTypedErrors() throws {
    XCTAssertThrowsError(try executor().validate(path: "missing.yaml", scope: nil)) { error in
      XCTAssertEqual((error as? ExitError)?.code, CLIErrorCode.pathNotFound)
    }
    XCTAssertThrowsError(try executor().validate(path: "home", scope: nil)) { error in
      XCTAssertEqual((error as? ExitError)?.code, CLIErrorCode.invalidArgument)
    }
  }

  func testSchemaPayloadCarriesTheDefinitionSchema() throws {
    let payload = try executor().schema()
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload.schema.bytes) as? [String: Any])
    XCTAssertEqual(object["$id"] as? String, WorkflowJSONSchema.identifier)
    XCTAssertEqual(object["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
  }
}
