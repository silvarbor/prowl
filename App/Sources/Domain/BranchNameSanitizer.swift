import Foundation

nonisolated enum BranchNameSanitizer {
  static let maxLength = 50

  static func sanitize(_ raw: String) -> String? {
    var name =
      raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    // Multi-line output is garbage
    if name.contains(where: { $0.isNewline }) {
      name = name.components(separatedBy: .newlines).first ?? ""
    }

    name =
      name
      .replacing(/\s+/, with: "-")
      .replacing("_", with: "-")
      .replacing(/[~^:?*\[\]\\@{}\x00-\x1f\x7f]/, with: "")
      .replacing("..", with: ".")
      .replacing(/-{2,}/, with: "-")
      .replacing(/\.{2,}/, with: ".")

    while name.hasPrefix("-") || name.hasPrefix(".") { name.removeFirst() }
    while name.hasSuffix("-") || name.hasSuffix(".") || name.hasSuffix(".lock") {
      if name.hasSuffix(".lock") {
        name = String(name.dropLast(5))
      } else {
        name.removeLast()
      }
    }

    if name.count > maxLength {
      name = String(name.prefix(maxLength))
      while name.hasSuffix("-") || name.hasSuffix(".") { name.removeLast() }
    }

    guard name.count >= 3 else { return nil }
    return name
  }

  /// Branch names behind local and remote-tracking `refs`: `<remote>/` is removed so that
  /// `origin/feat/a` counts as `feat/a`, and duplicates are dropped.
  static func branchNames(fromRefs refs: [String], remotes: [String]) -> [String] {
    var seen: Set<String> = []
    return refs.compactMap { ref in
      let name =
        GitRemoteMatcher.matchingRemote(for: ref, from: remotes)
        .map { String(ref.dropFirst($0.count + 1)) } ?? ref
      return seen.insert(name).inserted ? name : nil
    }
  }

  /// The first path segments (with the trailing `/`) used by `branches`, most frequent first.
  /// Ties keep the order in which the prefixes first appear.
  static func branchPrefixes(in branches: [String]) -> [(prefix: String, count: Int)] {
    var counts: [(prefix: String, count: Int)] = []
    var indexByPrefix: [String: Int] = [:]
    for branch in branches {
      guard let slashIndex = branch.firstIndex(of: "/"), slashIndex != branch.startIndex else { continue }
      let prefix = String(branch[...slashIndex])
      if let index = indexByPrefix[prefix] {
        counts[index].count += 1
      } else {
        indexByPrefix[prefix] = counts.count
        counts.append((prefix: prefix, count: 1))
      }
    }
    // Sorting by count alone is not stable; the index keeps first-appearance order for ties.
    return counts.enumerated()
      .sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
      .map(\.element)
  }

  /// The most frequent prefix in `branches`, or `nil` when there is none or several share the lead.
  /// The prefix is kept as the repository spells it.
  static func detectConventionPrefix(from branches: [String]) -> String? {
    let prefixes = branchPrefixes(in: branches)
    guard let first = prefixes.first else { return nil }
    if prefixes.count > 1, prefixes[1].count == first.count { return nil }
    return first.prefix
  }

  static func ensurePrefix(_ name: String, conventionPrefix: String?) -> String {
    if name.contains("/") { return name }
    let prefix = conventionPrefix ?? "worktree/"
    return prefix + name
  }

  static func validate(
    _ name: String,
    existingBranches: [String]
  ) -> String? {
    guard var sanitized = sanitize(name) else { return nil }
    sanitized = ensurePrefix(sanitized, conventionPrefix: detectConventionPrefix(from: existingBranches))

    // Re-check length after prefix
    if sanitized.count > maxLength {
      return nil
    }

    // Reject duplicates (case-insensitive)
    let lowered = sanitized.lowercased()
    if existingBranches.contains(where: { $0.lowercased() == lowered }) {
      return nil
    }

    return sanitized
  }
}
