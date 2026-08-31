import Foundation
import ProwlCLIShared
import XCTest

final class WorkflowDiscoveryTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appending(path: "prowl-workflow-discovery-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  private func directory(_ name: String) throws -> URL {
    let url = root.appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func write(_ yaml: String, to directory: URL, name: String) throws {
    try Data(yaml.utf8).write(to: directory.appending(path: name))
  }

  private func context(_ scope: WorkflowScope) -> WorkflowValidationContext {
    WorkflowValidationContext(scope: scope, bundledSkillIDs: ["prowl.adversarial-reviewer"])
  }

  func testUnreadableDirectoriesThrowInsteadOfHidingTheirFiles() throws {
    let user = try directory("user")
    try write(WorkflowFixtures.minimal(id: "demo"), to: user, name: "demo.yaml")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: user.path(percentEncoded: false))
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: user.path(percentEncoded: false)) }
    XCTAssertThrowsError(try WorkflowDiscovery.files(in: user, scope: .user, context: context(.user)))
    XCTAssertThrowsError(
      try WorkflowDiscovery.catalog(sources: WorkflowSources(bundle: nil, user: user, repo: nil), context: context))
  }

  func testMissingDirectoriesYieldNoFiles() throws {
    let catalog = try WorkflowDiscovery.catalog(
      sources: WorkflowSources(bundle: nil, user: root.appending(path: "absent"), repo: nil), context: context)
    XCTAssertEqual(catalog, [])
  }

  func testFilesAreParsedValidatedAndOrderedByName() throws {
    let user = try directory("user")
    try write(WorkflowFixtures.minimal(id: "zeta"), to: user, name: "zeta.yml")
    try write(WorkflowFixtures.minimal(id: "alpha"), to: user, name: "alpha.yaml")
    try write("not: [valid", to: user, name: "broken.yaml")
    try write("ignored", to: user, name: "notes.txt")
    try write(WorkflowFixtures.minimal(id: "hidden"), to: user, name: ".hidden.yaml")

    let files = try WorkflowDiscovery.files(in: user, scope: .user, context: context(.user))
    XCTAssertEqual(files.map(\.url.lastPathComponent), ["alpha.yaml", "broken.yaml", "zeta.yml"])
    XCTAssertEqual(files.map(\.id), ["alpha", nil, "zeta"])
    XCTAssertEqual(files.map(\.isValid), [true, false, true])
    XCTAssertEqual(files[1].diagnostics.map(\.code), ["yaml_syntax"])
    XCTAssertEqual(files.map(\.scope), [.user, .user, .user])
  }

  func testValidationDiagnosticsFollowParseDiagnostics() throws {
    let user = try directory("user")
    try write(WorkflowFixtures.minimal(id: "prowl.mine"), to: user, name: "mine.yaml")
    let files = try WorkflowDiscovery.files(in: user, scope: .user, context: context(.user))
    XCTAssertEqual(files.map(\.isValid), [false])
    XCTAssertEqual(files[0].diagnostics.map(\.code), ["reserved_id"])
    XCTAssertNotNil(files[0].definition, "A file that parses keeps its definition even when validation fails")
  }

  func testPrecedenceAndShadowing() throws {
    let bundle = try directory("bundle")
    let user = try directory("user")
    let repo = try directory("repo")
    try write(WorkflowFixtures.adversarialReview, to: bundle, name: "adversarial-review.yaml")
    try write(WorkflowFixtures.minimal(id: "shared"), to: bundle, name: "shared.yaml")
    try write(WorkflowFixtures.minimal(id: "shared"), to: user, name: "shared.yaml")
    try write(WorkflowFixtures.minimal(id: "demo"), to: user, name: "demo.yaml")
    try write(WorkflowFixtures.minimal(id: "demo"), to: user, name: "demo-copy.yaml")
    try write(WorkflowFixtures.adversarialReview, to: user, name: "override.yaml")
    try write(WorkflowFixtures.minimal(id: "demo"), to: repo, name: "demo.yaml")

    let catalog = try WorkflowDiscovery.catalog(
      sources: WorkflowSources(bundle: bundle, user: user, repo: repo), context: context)
    let rows = catalog.map { "\($0.file.id ?? "-") \($0.file.scope.rawValue) \($0.file.url.lastPathComponent) \($0.shadowed ? "shadowed" : ($0.file.isValid ? "wins" : "invalid"))" }
    XCTAssertEqual(
      rows,
      [
        "demo repo demo.yaml wins",
        "demo user demo-copy.yaml shadowed",
        "demo user demo.yaml shadowed",
        "prowl.adversarial-review bundle adversarial-review.yaml wins",
        "prowl.adversarial-review user override.yaml invalid",
        "shared user shared.yaml wins",
        "shared bundle shared.yaml shadowed",
      ]
    )
  }

  func testSameSourceDuplicatesKeepTheFirstFileByName() throws {
    let user = try directory("user")
    try write(WorkflowFixtures.minimal(id: "demo"), to: user, name: "b.yaml")
    try write(WorkflowFixtures.minimal(id: "demo"), to: user, name: "a.yaml")
    let catalog = try WorkflowDiscovery.catalog(
      sources: WorkflowSources(bundle: nil, user: user, repo: nil), context: context)
    XCTAssertEqual(catalog.map { "\($0.file.url.lastPathComponent) \($0.shadowed)" }, ["a.yaml false", "b.yaml true"])
  }

  func testInvalidFilesNeverShadowValidOnes() throws {
    let user = try directory("user")
    let repo = try directory("repo")
    try write(WorkflowFixtures.minimal(id: "demo"), to: user, name: "demo.yaml")
    try write(WorkflowFixtures.minimal(id: "demo", extraSteps: "  - id: x\n    close: ghost"), to: repo, name: "demo.yaml")
    let catalog = try WorkflowDiscovery.catalog(
      sources: WorkflowSources(bundle: nil, user: user, repo: repo), context: context)
    XCTAssertEqual(
      catalog.map { "\($0.file.scope.rawValue) valid=\($0.file.isValid) shadowed=\($0.shadowed)" },
      ["user valid=true shadowed=false", "repo valid=false shadowed=false"])
  }

  func testOnlyRegularFilesAndLinksToThemAreRead() throws {
    let user = try directory("user")
    try write(WorkflowFixtures.minimal(id: "real"), to: user, name: "real.yaml")
    try FileManager.default.createDirectory(at: user.appending(path: "folder.yaml"), withIntermediateDirectories: true)
    let elsewhere = try directory("elsewhere")
    try write(WorkflowFixtures.minimal(id: "linked"), to: elsewhere, name: "source.yaml")
    try FileManager.default.createSymbolicLink(
      at: user.appending(path: "link.yaml"), withDestinationURL: elsewhere.appending(path: "source.yaml"))
    try FileManager.default.createSymbolicLink(
      at: user.appending(path: "dangling.yaml"), withDestinationURL: elsewhere.appending(path: "missing.yaml"))

    XCTAssertEqual(mkfifo(user.appending(path: "pipe.yaml").path(percentEncoded: false), 0o644), 0)

    let files = try WorkflowDiscovery.files(in: user, scope: .user, context: context(.user))
    XCTAssertEqual(files.map(\.url.lastPathComponent), ["link.yaml", "real.yaml"])
    XCTAssertEqual(files.map(\.id), ["linked", "real"])
  }

  func testSourceDirectoryHelpers() {
    let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
    XCTAssertEqual(WorkflowSources.userDirectory(home: home).path(percentEncoded: false), "/Users/me/.prowl/workflows/")
    let repo = URL(filePath: "/Projects/App", directoryHint: .isDirectory)
    XCTAssertEqual(WorkflowSources.repoDirectory(root: repo).path(percentEncoded: false), "/Projects/App/.prowl/workflows/")
    let resources = URL(filePath: "/Applications/Prowl.app/Contents/Resources", directoryHint: .isDirectory)
    XCTAssertEqual(
      WorkflowSources.bundleDirectory(resourcesURL: resources).path(percentEncoded: false),
      "/Applications/Prowl.app/Contents/Resources/workflows/")
  }
}
