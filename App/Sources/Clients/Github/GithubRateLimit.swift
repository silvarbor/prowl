import Foundation

// The API a request spends. GitHub keeps a separate hourly budget for each.
nonisolated enum GithubAPIResource: String, Sendable, Hashable, CaseIterable {
  case graphQL
  case rest
}

// The part of the gate that a request goes through: one host and one API. The host is nil for a
// command that lets gh pick the host from the repository's remotes.
nonisolated struct GithubRateLimitScope: Hashable, Sendable {
  var host: String?
  var resource: GithubAPIResource
}

// One gh invocation as the gate sees it.
nonisolated struct GithubRateLimitRequest: Equatable, Sendable {
  var scope: GithubRateLimitScope
  // The gh subcommand, such as `gh api graphql`, which names the request in diagnostics.
  var command: String
  // The size of a GraphQL query, which tells a refusal of one large batch from a limit on the account.
  var query: QueryShape?

  struct QueryShape: Equatable, Sendable {
    var bytes: Int
    var repositories: Int
    var pullRequestLookups: Int
  }

  static let unscoped = GithubRateLimitRequest(
    scope: GithubRateLimitScope(host: nil, resource: .graphQL),
    command: "gh"
  )

  init(scope: GithubRateLimitScope, command: String) {
    self.scope = scope
    self.command = command
  }

  init(arguments: [String]) {
    let subcommand = Array(arguments.prefix { !$0.hasPrefix("-") }.prefix(2))
    command = (["gh"] + subcommand).joined(separator: " ")
    let host = Self.value(after: "--hostname", in: arguments) ?? Self.repositoryHost(in: arguments)
    // `gh repo` and `gh pr` read and write through GraphQL; `gh run`, `gh auth`, and `gh api <path>`
    // use REST.
    let resource: GithubAPIResource =
      switch subcommand.first {
      case "api": subcommand.dropFirst().first == "graphql" ? .graphQL : .rest
      case "repo", "pr": .graphQL
      default: .rest
      }
    scope = GithubRateLimitScope(host: host, resource: resource)
    query = arguments.first { $0.hasPrefix("query=") }.map { argument in
      let text = argument.dropFirst("query=".count)
      return QueryShape(
        bytes: text.utf8.count,
        repositories: text.ranges(of: "repository(").count,
        pullRequestLookups: text.ranges(of: "pullRequests(").count
      )
    }
  }

  private static func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  // `--repo HOST/OWNER/REPO` names the host; `--repo OWNER/REPO` leaves it to gh.
  private static func repositoryHost(in arguments: [String]) -> String? {
    guard let repository = value(after: "--repo", in: arguments) else {
      return nil
    }
    let parts = repository.split(separator: "/")
    return parts.count == 3 ? String(parts[0]) : nil
  }
}

// What GitHub sent with a rate-limit answer, kept so that a block can name its cause.
nonisolated struct GithubRateLimitEvidence: Equatable, Sendable {
  // The part of gh's output that marked the request as refused, so that a wrong reading can be told
  // from a real limit.
  enum Source: String, Equatable, Sendable {
    case graphQLError = "GraphQL errors"
    case responseMessage = "response message"
    case stderr = "gh stderr"
    case headers = "rate-limit headers"
    case status = "HTTP status"
  }

  var status: Int?
  var source: Source?
  // The `type` (or `code`) of the GraphQL error that refused the request.
  var errorType: String?
  // `Retry-After`, the `X-RateLimit-*` fields, and the fields that trace the request to a server or
  // a proxy, with lowercased names.
  var headers: [String: String] = [:]
  // GitHub's own words about the limit, from the body or from gh's stderr. Without them, the start
  // of the refused response's body.
  var message: String?
}

// What one gh invocation said about the account's rate limit. A refusal means GitHub turned the
// request away; an exhausted budget means the request succeeded but spent the last of it, so the
// next one would be refused.
nonisolated struct GithubRateLimitSignal: Equatable, Sendable {
  // A primary limit is the hourly budget of the request's API. A secondary limit, and a refusal
  // that names neither, covers every request of the account on the host.
  enum Limit: Equatable, Sendable {
    case primary
    case secondary
  }

  var isRefusal: Bool
  var limit: Limit = .secondary
  var retryAfter: Duration?
  var retryAfterDate: Date?
  var resetAt: Date?
  var evidence = GithubRateLimitEvidence()
}

// Reads a rate-limit answer out of gh's output. `gh api --include` prints the response's status line
// and headers ahead of the body; other gh commands report only through stderr.
nonisolated enum GithubRateLimitClassifier {
  static func classify(stdout: String, stderr: String, succeeded: Bool) -> GithubRateLimitSignal? {
    let response = parseResponseHead(stdout)
    let retryAfterField = response.fields["retry-after"]
    let retryAfter = retryAfterField.flatMap(Int.init).map { Duration.seconds($0) }
    let retryAfterDate = retryAfter == nil ? retryAfterField.flatMap(parseHTTPDate) : nil
    let budgetExhausted = response.fields["x-ratelimit-remaining"] == "0"
    let resetAt =
      budgetExhausted
      ? response.fields["x-ratelimit-reset"].flatMap(TimeInterval.init).map { Date(timeIntervalSince1970: $0) }
      : nil
    let failed = !succeeded || (response.status ?? 200) >= 400
    let bodyFinding = bodyRateLimitFinding(stdout, includeTopLevelMessage: failed)
    // gh's stderr speaks only for commands without `--include`. Once GitHub's answer is in stdout,
    // stderr can only repeat it or carry login-shell noise.
    let stderrMessage = succeeded || response.status != nil ? nil : stderrRateLimitLine(stderr)

    let isRefusal: Bool
    switch response.status {
    case 429:
      isRefusal = true
    case 403:
      // A 403 is also a permission answer; GitHub marks the rate-limit kind with these.
      isRefusal = retryAfterField != nil || budgetExhausted || bodyFinding != nil || stderrMessage != nil
    default:
      isRefusal = bodyFinding != nil || stderrMessage != nil
    }
    guard isRefusal || budgetExhausted else {
      return nil
    }
    let message = bodyFinding?.message ?? stderrMessage
    let source: GithubRateLimitEvidence.Source =
      if let bodyFinding {
        bodyFinding.source
      } else if stderrMessage != nil {
        .stderr
      } else if retryAfterField != nil || budgetExhausted {
        .headers
      } else {
        .status
      }
    let isSecondary = retryAfterField != nil || message.map(mentionsSecondaryLimit) == true
    let isPrimary = budgetExhausted || message.map(mentionsPrimaryLimit) == true
    let refusedBody =
      isRefusal && (response.status ?? 0) >= 400 ? response.bodyStart.flatMap { bodyQuote(stdout[$0...]) } : nil
    return GithubRateLimitSignal(
      isRefusal: isRefusal,
      limit: isPrimary && !isSecondary ? .primary : .secondary,
      retryAfter: retryAfter,
      retryAfterDate: retryAfterDate,
      resetAt: resetAt,
      evidence: GithubRateLimitEvidence(
        status: response.status,
        source: source,
        errorType: bodyFinding?.errorType,
        headers: response.fields.filter { isEvidenceHeader($0.key) },
        message: (message ?? refusedBody).map { String($0.prefix(300)) }
      )
    )
  }

  // The start of a refused response's body on one line, such as a proxy's HTML page.
  private static func bodyQuote(_ body: Substring) -> String? {
    let quote = body.prefix(4096).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return quote.isEmpty ? nil : quote
  }

  private static func isEvidenceHeader(_ name: String) -> Bool {
    name == "retry-after" || name.hasPrefix("x-ratelimit-") || name == "x-github-request-id"
      || name == "server" || name == "via"
  }

  // The HTTP status gh printed with `--include`, which shows that GitHub itself answered.
  static func responseStatus(in stdout: String) -> Int? {
    parseResponseHead(stdout).status
  }

  // Retry-After may also be an HTTP date (RFC 9110), such as "Wed, 21 Oct 2026 07:28:00 GMT".
  private static func parseHTTPDate(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.date(from: value)
  }

  private struct ResponseHead {
    var status: Int?
    var fields: [String: String] = [:]
    // Where the body starts, after the header block.
    var bodyStart: String.Index?
  }

  // The status line may follow login-shell noise, so it is searched for rather than assumed first.
  private static func parseResponseHead(_ stdout: String) -> ResponseHead {
    var head = ResponseHead()
    var inHeaders = false
    for line in stdout.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if !inHeaders {
        guard trimmed.hasPrefix("HTTP/") else { continue }
        let parts = trimmed.split(separator: " ")
        head.status = parts.count > 1 ? Int(parts[1]) : nil
        inHeaders = true
        continue
      }
      guard !trimmed.isEmpty, let colon = trimmed.firstIndex(of: ":") else {
        head.bodyStart = line.startIndex
        break
      }
      let name = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
      let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      head.fields[name] = value
    }
    return head
  }

  private struct BodyFinding {
    var source: GithubRateLimitEvidence.Source
    var errorType: String?
    var message: String
  }

  // Only the top-level `errors` array, and on a failed response the top-level `message`, carry
  // GitHub's verdict. Payload text such as a pull request titled "Handle rate limits" never counts.
  private static func bodyRateLimitFinding(_ stdout: String, includeTopLevelMessage: Bool) -> BodyFinding? {
    for span in GithubCLIOutput.balancedJSONSpans(in: stdout) {
      guard let object = try? JSONSerialization.jsonObject(with: Data(span.utf8)) as? [String: Any] else {
        continue
      }
      if let errors = object["errors"] as? [[String: Any]], let error = errors.first(where: isRateLimitError) {
        let errorType = (error["type"] as? String) ?? (error["code"] as? String)
        let message = error["message"] as? String ?? ""
        return BodyFinding(
          source: .graphQLError,
          errorType: errorType,
          message: message.isEmpty ? (errorType ?? "RATE_LIMITED") : message
        )
      }
      if includeTopLevelMessage, let message = object["message"] as? String, mentionsRateLimit(message) {
        return BodyFinding(source: .responseMessage, message: message)
      }
    }
    return nil
  }

  private static func stderrRateLimitLine(_ stderr: String) -> String? {
    stderr.split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .first(where: mentionsRateLimit)
  }

  private static func isRateLimitError(_ error: [String: Any]) -> Bool {
    let type = (error["type"] as? String)?.uppercased() ?? ""
    let code = (error["code"] as? String)?.lowercased() ?? ""
    let message = error["message"] as? String ?? ""
    return type == "RATE_LIMITED" || type == "RATE_LIMIT" || code.contains("rate_limit") || mentionsRateLimit(message)
  }

  private static func mentionsRateLimit(_ text: String) -> Bool {
    let lowered = text.lowercased()
    return lowered.contains("rate limit") || lowered.contains("rate-limit") || lowered.contains("abuse detection")
  }

  // GitHub's words for the hourly budget, such as "API rate limit exceeded for user ID 1."
  private static func mentionsPrimaryLimit(_ text: String) -> Bool {
    text.lowercased().contains("api rate limit")
  }

  private static func mentionsSecondaryLimit(_ text: String) -> Bool {
    let lowered = text.lowercased()
    return lowered.contains("secondary rate limit") || lowered.contains("abuse")
  }
}

// Why the gate holds back a scope: the request that GitHub refused, and what GitHub sent.
nonisolated struct GithubRateLimitCause: Equatable, Sendable {
  var request: GithubRateLimitRequest
  var limit: GithubRateLimitSignal.Limit
  var evidence: GithubRateLimitEvidence
}

nonisolated extension GithubRateLimitCause {
  // A plain account of the refusal, kept in English like the gh output it quotes.
  var summary: String {
    var requestLine = request.command
    if let query = request.query {
      requestLine +=
        ": \(query.repositories) repositories, \(query.pullRequestLookups) branches, \(query.bytes)-byte query"
    }
    var verdict = evidence.status.map { "HTTP \($0)" } ?? "no HTTP status"
    verdict += ", \(limit == .primary ? "primary" : "secondary") limit"
    if let source = evidence.source {
      verdict += ", from \(source.rawValue)"
      if let errorType = evidence.errorType {
        verdict += " (\(errorType))"
      }
    }
    var lines = [requestLine, verdict]
    for (name, value) in evidence.headers.sorted(by: { $0.key < $1.key }) {
      lines.append("\(name): \(value)")
    }
    if let message = evidence.message {
      lines.append(message)
    }
    return lines.joined(separator: "\n")
  }
}

// A scope that the gate holds back, with the time it sends the scope's next request.
nonisolated struct GithubRateLimitBlock: Equatable, Sendable {
  var scope: GithubRateLimitScope
  var retryAt: Date
  var cause: GithubRateLimitCause
}

// The blocks that one refusal set, shown as one entry: a secondary limit holds back every API of
// its host with the same cause and retry time.
nonisolated struct GithubRateLimitBlockGroup: Equatable, Sendable, Identifiable {
  var host: String?
  var resources: [GithubAPIResource]
  var retryAt: Date
  var cause: GithubRateLimitCause

  var id: GithubRateLimitScope {
    GithubRateLimitScope(host: host, resource: resources[0])
  }

  static func grouping(_ blocks: [GithubRateLimitBlock]) -> [Self] {
    var groups: [Self] = []
    for block in blocks {
      if let index = groups.firstIndex(where: {
        $0.host == block.scope.host && $0.retryAt == block.retryAt && $0.cause == block.cause
      }) {
        groups[index].resources.append(block.scope.resource)
      } else {
        groups.append(
          Self(host: block.scope.host, resources: [block.scope.resource], retryAt: block.retryAt, cause: block.cause))
      }
    }
    return groups
  }
}

// The blocks that keep a repository's pull request status from refreshing. Only a GraphQL block on
// one of the repository's hosts does that; the REST blocks of the same hosts come along as context.
nonisolated struct GithubRateLimitStatus: Equatable, Sendable {
  let retryAt: Date
  let blocks: [GithubRateLimitBlock]

  init?(blocks: [GithubRateLimitBlock], hosts: Set<String>) {
    let relevant = blocks.filter { $0.scope.host.map(hosts.contains) == true }
    guard let retryAt = relevant.filter({ $0.scope.resource == .graphQL }).map(\.retryAt).min() else {
      return nil
    }
    self.retryAt = retryAt
    self.blocks = relevant
  }
}

// One gate for every gh call that reaches GitHub. Several tools and agents share the account, and a
// refused request can extend a secondary limit for all of them, so once GitHub refuses, Prowl sends
// nothing more to that scope until the retry time. Then exactly one request goes out as a probe; the
// others wait for GitHub's answer to it instead of racing it.
//
// Each host and API has its own lane, because GitHub keeps a separate budget for each. A primary
// limit holds back only the lane of the refused request; a secondary limit holds back every lane of
// the host, because it applies to all requests of the account there.
actor GithubRateLimitGate {
  static let shared = GithubRateLimitGate()

  static let initialBackoff: Duration = .seconds(60)
  static let maximumBackoff: Duration = .seconds(3600)

  nonisolated private static let logger = ProwlLogger("GithubRateLimit")

  struct Ticket: Sendable, Equatable {
    let request: GithubRateLimitRequest
    let isProbe: Bool

    init(isProbe: Bool, request: GithubRateLimitRequest = .unscoped) {
      self.request = request
      self.isProbe = isProbe
    }
  }

  private enum Phase: Equatable {
    case open
    case blocked(until: Date)
    case probing(lastUntil: Date)
  }

  private struct Waiter {
    let id: UUID
    let request: GithubRateLimitRequest
    let continuation: CheckedContinuation<Ticket, Error>
  }

  private struct Lane {
    var phase: Phase = .open
    var consecutiveRefusals = 0
    var waiters: [Waiter] = []
    var cause: GithubRateLimitCause?
  }

  private let now: @Sendable () -> Date
  private let jitter: @Sendable () -> Double
  private var lanes: [GithubRateLimitScope: Lane] = [:]
  private var observers: [UUID: AsyncStream<[GithubRateLimitBlock]>.Continuation] = [:]

  init(
    now: @escaping @Sendable () -> Date = { Date() },
    jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }
  ) {
    self.now = now
    self.jitter = jitter
  }

  // Exponential from one minute, doubling per consecutive refusal, with up to 25% added jitter so
  // several clients do not return in step. Never above one hour.
  nonisolated static func backoff(afterRefusals refusals: Int, jitter: Double) -> Duration {
    let exponent = Double(min(max(refusals - 1, 0), 16))
    let initial = initialBackoff.timeInterval
    let delay = initial * pow(2.0, exponent) * (1.0 + 0.25 * min(max(jitter, 0), 1))
    return .seconds(min(delay, maximumBackoff.timeInterval))
  }

  var waitingRequestCount: Int {
    lanes.values.reduce(0) { $0 + $1.waiters.count }
  }

  // The scopes held back while GitHub refuses them, empty while requests flow. Each subscriber
  // receives the current value first.
  func blocks() -> AsyncStream<[GithubRateLimitBlock]> {
    let (stream, continuation) = AsyncStream<[GithubRateLimitBlock]>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    observers[id] = continuation
    continuation.onTermination = { _ in
      Task { await self.removeObserver(id) }
    }
    continuation.yield(currentBlocks)
    return stream
  }

  func admit(_ request: GithubRateLimitRequest = .unscoped) async throws -> Ticket {
    let scope = request.scope
    switch lanes[scope]?.phase ?? .open {
    case .open:
      return Ticket(isProbe: false, request: request)
    case .blocked(let until):
      if now() < until {
        throw GithubCLIError.rateLimited(retryAt: until)
      }
      lanes[scope, default: Lane()].phase = .probing(lastUntil: until)
      return Ticket(isProbe: true, request: request)
    case .probing:
      let id = UUID()
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
          } else {
            lanes[scope, default: Lane()].waiters.append(Waiter(id: id, request: request, continuation: continuation))
          }
        }
      } onCancel: {
        Task { await self.cancelWaiter(id, scope: scope) }
      }
    }
  }

  // Records how a ticket's request ended. `answered` means GitHub itself responded: gh succeeded, or
  // its output carries an HTTP status. Returns the retry time when the request must be reported as
  // rate-limited, nil when its own result stands.
  func record(_ ticket: Ticket, signal: GithubRateLimitSignal?, answered: Bool) -> Date? {
    let scope = ticket.request.scope
    let phase = lanes[scope]?.phase ?? .open
    guard let signal else {
      if ticket.isProbe, case .probing = phase {
        if answered {
          reopen(scope)
        } else {
          // A local failure says nothing about GitHub; one more request has to find out.
          handOffProbe(scope)
        }
      }
      return nil
    }
    switch phase {
    case .open:
      let until = block(for: signal, request: ticket.request)
      return signal.isRefusal ? until : nil
    case .probing where ticket.isProbe:
      let until = block(for: signal, request: ticket.request)
      return signal.isRefusal ? until : nil
    case .probing(let lastUntil):
      // A request admitted before the gate closed: the refusal it carries is already counted.
      return signal.isRefusal ? lastUntil : nil
    case .blocked(let until):
      return signal.isRefusal ? until : nil
    }
  }

  // A probe cancelled before GitHub answered settles nothing.
  func abandon(_ ticket: Ticket) {
    guard ticket.isProbe, case .probing = lanes[ticket.request.scope]?.phase else {
      return
    }
    handOffProbe(ticket.request.scope)
  }

  // Lets the next request to every held-back scope go out as a probe now, instead of at the retry
  // time. A probe that GitHub refuses again holds the scope back with the next backoff step.
  func retryNow() {
    let current = now()
    var changed = false
    for (scope, lane) in lanes {
      guard case .blocked(let until) = lane.phase, until > current else {
        continue
      }
      lanes[scope]?.phase = .blocked(until: current)
      changed = true
    }
    if changed {
      publish()
    }
  }

  private var currentBlocks: [GithubRateLimitBlock] {
    lanes.compactMap { scope, lane -> GithubRateLimitBlock? in
      guard let cause = lane.cause else {
        return nil
      }
      switch lane.phase {
      case .open:
        return nil
      case .blocked(let until), .probing(let until):
        return GithubRateLimitBlock(scope: scope, retryAt: until, cause: cause)
      }
    }
    .sorted { lhs, rhs in
      let lhsHost = lhs.scope.host ?? ""
      let rhsHost = rhs.scope.host ?? ""
      if lhsHost != rhsHost {
        return lhsHost < rhsHost
      }
      return lhs.scope.resource.rawValue < rhs.scope.resource.rawValue
    }
  }

  private func handOffProbe(_ scope: GithubRateLimitScope) {
    guard case .probing(let lastUntil) = lanes[scope]?.phase else {
      return
    }
    guard let next = lanes[scope]?.waiters.first else {
      lanes[scope]?.phase = .blocked(until: lastUntil)
      return
    }
    lanes[scope]?.waiters.removeFirst()
    next.continuation.resume(returning: Ticket(isProbe: true, request: next.request))
  }

  private func cancelWaiter(_ id: UUID, scope: GithubRateLimitScope) {
    guard let index = lanes[scope]?.waiters.firstIndex(where: { $0.id == id }) else {
      return
    }
    lanes[scope]?.waiters.remove(at: index).continuation.resume(throwing: CancellationError())
  }

  private func removeObserver(_ id: UUID) {
    observers.removeValue(forKey: id)
  }

  private func publish() {
    let value = currentBlocks
    for observer in observers.values {
      observer.yield(value)
    }
  }

  private func reopen(_ scope: GithubRateLimitScope) {
    let admitted = lanes[scope]?.waiters ?? []
    lanes[scope] = Lane()
    for waiter in admitted {
      waiter.continuation.resume(returning: Ticket(isProbe: false, request: waiter.request))
    }
    publish()
  }

  private func block(for signal: GithubRateLimitSignal, request: GithubRateLimitRequest) -> Date {
    let current = now()
    let scope = request.scope
    if signal.isRefusal {
      lanes[scope, default: Lane()].consecutiveRefusals += 1
    }
    let until: Date
    if let retryAfter = signal.retryAfter {
      until = current.addingTimeInterval(retryAfter.timeInterval)
    } else if let retryAfterDate = signal.retryAfterDate, retryAfterDate > current {
      until = retryAfterDate
    } else if let resetAt = signal.resetAt, resetAt > current {
      until = resetAt
    } else {
      let refusals = max(lanes[scope]?.consecutiveRefusals ?? 0, 1)
      until = current.addingTimeInterval(Self.backoff(afterRefusals: refusals, jitter: jitter()).timeInterval)
    }
    let cause = GithubRateLimitCause(request: request, limit: signal.limit, evidence: signal.evidence)
    let heldScopes =
      switch signal.limit {
      case .primary: [scope]
      case .secondary: GithubAPIResource.allCases.map { GithubRateLimitScope(host: scope.host, resource: $0) }
      }
    for heldScope in heldScopes {
      var lane = lanes[heldScope] ?? Lane()
      // A lane that an earlier refusal holds back longer keeps its own retry time and cause.
      if heldScope != scope, case .blocked(let existing) = lane.phase, existing >= until {
        continue
      }
      lane.phase = .blocked(until: until)
      lane.cause = cause
      let refused = lane.waiters
      lane.waiters.removeAll()
      lanes[heldScope] = lane
      for waiter in refused {
        waiter.continuation.resume(throwing: GithubCLIError.rateLimited(retryAt: until))
      }
    }
    Self.logger.warning(Self.describe(cause, heldScopes: heldScopes, until: until))
    publish()
    return until
  }

  nonisolated private static func describe(
    _ cause: GithubRateLimitCause,
    heldScopes: [GithubRateLimitScope],
    until: Date
  ) -> String {
    let host = cause.request.scope.host ?? "default host"
    let resources = heldScopes.map(\.resource.rawValue).joined(separator: "+")
    let account = cause.summary.split(separator: "\n").joined(separator: "; ")
    return "Holding back \(host) \(resources) until \(until.formatted(.iso8601)): \(account)"
  }
}

extension Duration {
  nonisolated fileprivate var timeInterval: TimeInterval {
    let parts = components
    return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
  }
}
