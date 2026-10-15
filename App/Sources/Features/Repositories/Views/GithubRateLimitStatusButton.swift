import SwiftUI

// The toolbar status while GitHub refuses the selected repository's hosts. A click shows which
// request GitHub refused and what it answered, and lets the user send the next probe now.
struct GithubRateLimitStatusButton: View {
  let status: GithubRateLimitStatus
  let onRetry: () -> Void
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .accessibilityHidden(true)
        Text("GitHub rate-limited, retrying at \(status.retryAt, format: .dateTime.hour().minute())")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .buttonStyle(.plain)
    .contentShape(.rect)
    .help("GitHub refused requests for its rate limit. Click to see the cause or to retry now.")
    .popover(isPresented: $isPresented) {
      VStack(alignment: .leading, spacing: 12) {
        Text("GitHub Rate Limit")
          .font(.headline)
        Text(
          """
          GitHub refused a request for its rate limit. Prowl sends nothing more to these hosts and APIs \
          until the retry time, so that other tools on the account keep working.
          """
        )
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        GithubRateLimitBlockList(blocks: status.blocks)
        HStack {
          Spacer()
          Button("Retry Now") {
            isPresented = false
            onRetry()
          }
          .help("Send the next request to GitHub now instead of at the retry time")
        }
      }
      .padding()
      .frame(width: 360)
    }
  }
}

// The held-back hosts and APIs, each with the request that GitHub refused and its answer.
struct GithubRateLimitBlockList: View {
  let blocks: [GithubRateLimitBlock]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(GithubRateLimitBlockGroup.grouping(blocks)) { group in
        let host = group.host ?? String(localized: "Default host")
        let resources = group.resources.map(\.displayName).joined(separator: " + ")
        let retryTime = group.retryAt.formatted(date: .omitted, time: .shortened)
        VStack(alignment: .leading, spacing: 2) {
          Text("\(host) · \(resources) · until \(retryTime)")
            .font(.callout.weight(.medium))
          Text(group.cause.summary)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
      }
    }
  }
}

extension GithubAPIResource {
  var displayName: String {
    switch self {
    case .graphQL: "GraphQL"
    case .rest: "REST"
    }
  }
}
