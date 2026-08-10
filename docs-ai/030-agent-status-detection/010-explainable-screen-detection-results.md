# 030.010 — Explainable Screen Detection Results: Action

| | |
| --- | --- |
| **Status** | Implemented |
| **Date** | 2026-08-07 |
| **Branch** | `feat/agent-detection-reasons` |
| **PR** | #686 (stacked on #685) |
| **Plan** | [007-screen-profile-migration-plan.md](007-screen-profile-migration-plan.md), Phase 3 |

## Result

Screen classification now returns an internal typed result without changing any raw or
stabilized state:

```swift
struct AgentScreenDetection {
  let state: AgentRawState
  let reason: AgentScreenDetectionReason
}
```

`detectState(in:)` remains the state-only compatibility projection. Every runtime still
uses its existing classifier in this phase and reports `legacy.detector`; profile-owned
rule matches and `fallback.noRuleMatched` become reachable only when the Codex and Claude
profiles migrate in later PRs.

`AgentScreenRuleID` is a small string-backed value rather than a global rule enum. This
keeps future constants beside their runtime profile and avoids introducing a matcher DSL,
profile protocol, or shared priority table.

## Cache and diagnostics

`AgentScreenScan` now caches the complete `AgentScreenDetection` for the same exact
`(agent, active-screen text)` identity. Cache hits preserve both state and reason; changing
either the screen or detected runtime recomputes both. Agent release removes the scan
before its asynchronous roster entry disappears, so the CLI cannot expose a stale reason
in that window. Stabilization, the 3-second working hold, `.unknown` handling, polling
cadence, and UI state remain untouched.

Existing transition diagnostics append only the stable reason identifier. They never log
screen text.

## CLI contract

`prowl agents --json` adds optional `detection_reason`:

- a future profile match emits its stable rule ID, such as `codex.directoryTrust`;
- an ordinary migrated-profile miss emits `fallback.noRuleMatched`;
- an unmigrated classifier emits `legacy.detector`;
- the field is omitted when no current screen result is available.

The existing `prowl.cli.agents.v1` schema remains additive. Older app payloads without the
field still decode, while text-mode output and all app UI remain unchanged. The handler
projects state and reason from the same cached result, so a reason cannot describe a
different raw scan. Payloads contain no screen text.

## Validation

TDD evidence:

- initial focused compile failed with 40 expected missing-type/API errors;
- diagnostic-reason coverage was separately observed red before adding reason plumbing;
- detection result, cache, corpus, heuristic, and CLI handler tests passed after
  implementation;
- cache tests include a sentinel matched rule ID to prove a cache hit preserves the full
  result rather than reconstructing only the state;
- CLI compatibility tests cover modern payload decoding, old payload decoding, and
  unchanged text output.

Executed verification:

- focused app tests: 55 passed before diagnostic plumbing; 10 focused result/cache/CLI
  tests passed after it;
- complete captured corpus remains green with unchanged current classification for all 15
  fixtures;
- full app suite after review fixes: xcsift reported 2,282 passed; xcresult independently
  verified 2,284 tests and zero failures;
- `make build-cli`, `make test-cli-smoke`, and `make test-cli-integration`: 68 integration
  tests passed;
- `make check` and `make build-app` passed after final diagnostic plumbing;
- `make bench`: 6 passed; at `e1e09444` the 15-fixture corpus measured 3.116 ms
  median versus Phase 2's 3.142 ms (-0.8%, within run-to-run noise).

A second Debug app successfully served the new CLI socket, but the host was at the locked
`loginwindow`; Ghostty surfaces therefore never became active and no live
`detection_reason` result was claimed. Retry the independent-app check when the GUI session
is unlocked, and again on the final simulated-integration branch.
