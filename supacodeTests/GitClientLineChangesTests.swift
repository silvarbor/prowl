import Foundation
import Testing

@testable import supacode

actor LineChangesShellCallStore {
  private(set) var calls: [[String]] = []

  func record(_ arguments: [String]) {
    calls.append(arguments)
  }
}

struct GitClientLineChangesTests {
  @Test func lineChangesUsesShortstatAndParsesOutput() async throws {
    let store = LineChangesShellCallStore()
    let shell = ShellClient(
      run: { _, arguments, _ in
        await store.record(arguments)
        if arguments.contains("--shortstat") {
          return ShellOutput(
            stdout: " 1 file changed, 12 insertions(+), 3 deletions(-)\n", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let changes = await client.lineChanges(at: URL(fileURLWithPath: "/tmp/repo"))

    #expect(changes?.added == 12)
    #expect(changes?.removed == 3)
    let calls = await store.calls
    #expect(calls.count == 2)
    let diffArgs = try #require(calls.first { $0.contains("--shortstat") })
    #expect(diffArgs.first == "git")
    #expect(diffArgs.contains("diff"))
    #expect(diffArgs.contains("HEAD"))
    #expect(!diffArgs.contains("--numstat"))
    let untrackedArgs = try #require(calls.first { $0.contains("ls-files") })
    #expect(untrackedArgs.contains("--others"))
    #expect(untrackedArgs.contains("--exclude-standard"))
    #expect(untrackedArgs.contains("-z"))
  }

  @Test func lineChangesHandlesMissingDeletions() async {
    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("--shortstat") {
          return ShellOutput(stdout: " 1 file changed, 5 insertions(+)\n", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let changes = await client.lineChanges(at: URL(fileURLWithPath: "/tmp/repo"))

    #expect(changes?.added == 5)
    #expect(changes?.removed == 0)
  }

  @Test func lineChangesParsesShortstatLine() async {
    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("--shortstat") {
          return ShellOutput(
            stdout: "1 file changed, 10 insertions(+), 4 deletions(-)\n", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let changes = await client.lineChanges(at: URL(fileURLWithPath: "/tmp/repo"))

    #expect(changes?.added == 10)
    #expect(changes?.removed == 4)
  }

  @Test func lineChangesHandlesEmptyOutput() async {
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "\n", stderr: "", exitCode: 0) },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let changes = await client.lineChanges(at: URL(fileURLWithPath: "/tmp/repo"))

    #expect(changes?.added == 0)
    #expect(changes?.removed == 0)
  }

  @Test func lineChangesIncludesUntrackedFileLines() async throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let gitDirectory = tempRoot.appending(path: ".git")
    try fileManager.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
    let headURL = gitDirectory.appending(path: "HEAD")
    try "ref: refs/heads/main\n".write(to: headURL, atomically: true, encoding: .utf8)

    let untrackedFile = tempRoot.appending(path: "new_file.swift")
    try "line1\nline2\nline3\n".write(to: untrackedFile, atomically: true, encoding: .utf8)

    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("--shortstat") {
          return ShellOutput(
            stdout: " 1 file changed, 10 insertions(+), 2 deletions(-)\n", stderr: "", exitCode: 0)
        }
        if arguments.contains("ls-files") {
          return ShellOutput(stdout: "new_file.swift\0", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let changes = await client.lineChanges(at: tempRoot)

    #expect(changes?.added == 13)
    #expect(changes?.removed == 2)
  }

  @Test func lineChangesSkipsBinaryUntrackedFiles() async throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let gitDirectory = tempRoot.appending(path: ".git")
    try fileManager.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
    let headURL = gitDirectory.appending(path: "HEAD")
    try "ref: refs/heads/main\n".write(to: headURL, atomically: true, encoding: .utf8)

    let binaryFile = tempRoot.appending(path: "image.png")
    var binaryData = Data("PNG\n".utf8)
    binaryData.append(0x00)
    binaryData.append(contentsOf: Data(repeating: 0x0A, count: 100))
    try binaryData.write(to: binaryFile)

    let textFile = tempRoot.appending(path: "readme.txt")
    try "hello\nworld\n".write(to: textFile, atomically: true, encoding: .utf8)

    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("--shortstat") {
          return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        if arguments.contains("ls-files") {
          return ShellOutput(stdout: "image.png\0readme.txt\0", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let changes = await client.lineChanges(at: tempRoot)

    #expect(changes?.added == 2)
    #expect(changes?.removed == 0)
  }

  @Test func lineChangesParsesNULSeparatedUntrackedFilePaths() async throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let gitDirectory = tempRoot.appending(path: ".git")
    try fileManager.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
    let headURL = gitDirectory.appending(path: "HEAD")
    try "ref: refs/heads/main\n".write(to: headURL, atomically: true, encoding: .utf8)

    let relativePath = " leading space\nname.txt"
    try "alpha\nbeta".write(to: tempRoot.appending(path: relativePath), atomically: true, encoding: .utf8)

    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("--shortstat") {
          return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        if arguments.contains("ls-files") {
          return ShellOutput(stdout: "\(relativePath)\0", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let changes = await client.lineChanges(at: tempRoot)

    #expect(changes?.added == 2)
    #expect(changes?.removed == 0)
  }

  @Test func lineChangesSkipsWhenIndexLocked() async throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let gitDirectory = tempRoot.appending(path: ".git")
    try fileManager.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
    let headURL = gitDirectory.appending(path: "HEAD")
    try "ref: refs/heads/main\n".write(to: headURL, atomically: true, encoding: .utf8)
    let lockURL = gitDirectory.appending(path: "index.lock")
    try Data().write(to: lockURL)
    let store = LineChangesShellCallStore()
    let shell = ShellClient(
      run: { _, arguments, _ in
        await store.record(arguments)
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let changes = await client.lineChanges(at: tempRoot)

    #expect(changes == nil)
    let calls = await store.calls
    #expect(calls.isEmpty)
  }

  @Test func indexEntryCountReadsGitIndexHeader() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let gitDirectory = tempRoot.appending(path: ".git")
    try fileManager.createDirectory(at: gitDirectory, withIntermediateDirectories: true)

    try writeGitIndexHeader(entryCount: 42_000, to: gitDirectory.appending(path: "index"))

    let count = GitClient.indexEntryCount(at: tempRoot)
    #expect(count == 42_000)
  }

  @Test func indexEntryCountRejectsInvalidHeader() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let gitDirectory = tempRoot.appending(path: ".git")
    try fileManager.createDirectory(at: gitDirectory, withIntermediateDirectories: true)

    var invalidMagic = Data()
    invalidMagic.append(contentsOf: "NOPE".utf8)
    invalidMagic.append(contentsOf: [0, 0, 0, 2])
    invalidMagic.append(contentsOf: [0, 0, 0, 1])
    try invalidMagic.write(to: gitDirectory.appending(path: "index"))

    #expect(GitClient.indexEntryCount(at: tempRoot) == nil)

    try writeGitIndexHeader(version: 99, entryCount: 1, to: gitDirectory.appending(path: "index"))

    #expect(GitClient.indexEntryCount(at: tempRoot) == nil)
  }

  @Test func indexEntryCountReturnsNilForMissingIndex() {
    let count = GitClient.indexEntryCount(at: URL(fileURLWithPath: "/nonexistent"))
    #expect(count == nil)
  }

  @Test func countLinesInFilesCountsNewlines() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fileManager.removeItem(at: tempRoot) }
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    try "a\nb\nc\n".write(to: tempRoot.appending(path: "a.txt"), atomically: true, encoding: .utf8)
    try "x\ny\n".write(to: tempRoot.appending(path: "b.txt"), atomically: true, encoding: .utf8)

    let count = GitClient.countLinesInFiles(["a.txt", "b.txt"], relativeTo: tempRoot)
    #expect(count == 5)
  }

  @Test func countLinesInFilesCountsFinalLineWithoutTrailingNewline() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fileManager.removeItem(at: tempRoot) }
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    try "hello".write(to: tempRoot.appending(path: "single.txt"), atomically: true, encoding: .utf8)
    try "a\nb".write(to: tempRoot.appending(path: "multi.txt"), atomically: true, encoding: .utf8)

    let count = GitClient.countLinesInFiles(["single.txt", "multi.txt"], relativeTo: tempRoot)
    #expect(count == 3)
  }

  @Test func countLinesInFilesSkipsBinaryFiles() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fileManager.removeItem(at: tempRoot) }
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    try "text\nfile\n".write(to: tempRoot.appending(path: "ok.txt"), atomically: true, encoding: .utf8)
    var binary = Data("header\n".utf8)
    binary.append(0x00)
    binary.append(contentsOf: Data(repeating: 0x0A, count: 50))
    try binary.write(to: tempRoot.appending(path: "img.bin"))

    let count = GitClient.countLinesInFiles(["ok.txt", "img.bin"], relativeTo: tempRoot)
    #expect(count == 2)
  }

  /// A capture-sized untracked file must not be read at all. The badge counts
  /// lines you are adding, and nobody typed 2 MiB of `sample(1)` output.
  @Test func countLinesInFilesSkipsFilesAtOrAboveTheByteLimit() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fileManager.removeItem(at: tempRoot) }
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    try "a\nb\n".write(to: tempRoot.appending(path: "small.txt"), atomically: true, encoding: .utf8)
    // Text, not binary: the NUL probe would pass it and count every newline.
    let oversized = Data(repeating: 0x0A, count: GitClient.untrackedLineCountByteLimit)
    try oversized.write(to: tempRoot.appending(path: "sample.txt"))

    let count = GitClient.countLinesInFiles(["small.txt", "sample.txt"], relativeTo: tempRoot)
    #expect(count == 2, "Only the small file should contribute")
  }

  /// The boundary is the whole point of the guard, so pin the side that must
  /// still count. One byte under the limit is an ordinary file.
  @Test func countLinesInFilesStillCountsJustUnderTheByteLimit() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fileManager.removeItem(at: tempRoot) }
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let justUnder = Data(repeating: 0x0A, count: GitClient.untrackedLineCountByteLimit - 1)
    try justUnder.write(to: tempRoot.appending(path: "big.txt"))

    let count = GitClient.countLinesInFiles(["big.txt"], relativeTo: tempRoot)
    #expect(count == GitClient.untrackedLineCountByteLimit - 1)
  }

  @Test func countLinesInFilesSkipsMissingFiles() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fileManager.removeItem(at: tempRoot) }
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    try "a\nb\n".write(to: tempRoot.appending(path: "exists.txt"), atomically: true, encoding: .utf8)

    let count = GitClient.countLinesInFiles(["exists.txt", "gone.txt"], relativeTo: tempRoot)
    #expect(count == 2)
  }

  private func writeGitIndexHeader(
    version: UInt32 = 2,
    entryCount: UInt32,
    to url: URL
  ) throws {
    var header = Data()
    header.append(contentsOf: "DIRC".utf8)
    header.append(UInt8((version >> 24) & 0xff))
    header.append(UInt8((version >> 16) & 0xff))
    header.append(UInt8((version >> 8) & 0xff))
    header.append(UInt8(version & 0xff))
    header.append(UInt8((entryCount >> 24) & 0xff))
    header.append(UInt8((entryCount >> 16) & 0xff))
    header.append(UInt8((entryCount >> 8) & 0xff))
    header.append(UInt8(entryCount & 0xff))
    try header.write(to: url)
  }
}
