# 030.007 — Screen Detection Profiles and Captured Fixture Corpus: Plan

| | |
| --- | --- |
| **Status** | Implemented — stacked PR review in progress |
| **Anchor date** | 2026-08-06 |
| **Primary PRs** | #684 (Phase 1), #685 (Phase 2), #686 (Phase 3), #687 (Phase 4), #688 (Phase 5) |
| **Sources** | Issue #676, PRs #674/#683, herdr `fae0b236` (v0.8.0-era) |
| **Related** | [000-plan.md](000-plan.md), [004-live-region-evidence.md](004-live-region-evidence.md), [005-confirmation-live-structure.md](005-confirmation-live-structure.md), [006-current-cli-pre-session-blockers.md](006-current-cli-pre-session-blockers.md), `docs/components/agent-detection.md` |

## Background

Issue #676 identified a maintenance failure rather than only six stale strings: a known
agent whose current UI no longer matches Prowl silently falls back to `idle`. PRs #674 and
#683 repaired the currently reproduced Claude/Codex states, but capture provenance and
rule ownership remain implicit.

Current `main` has an 883-line `ScreenHeuristics.swift`: 15 detector functions, 48 other
private helpers, and roughly 155 string-containment checks. Its 1,164-line test file has
42 test methods and about 70 multiline screen literals. The implementation is still a
pure `String -> AgentRawState` classifier over the last 24 non-empty lines, cached by the
exact detected agent and active-screen text.

The direction remains **screen-only state detection**. Process inspection continues to
own agent identity/liveness; it is not state evidence. The existing 3-second working
hold, `.unknown` viewer semantics, polling schedule, and scan cache are retained.

## Goals

- Give each migrated Claude/Codex result a stable rule ID or explicit no-match reason.
- Make live UI regions and rule precedence reviewable within a runtime-owned Swift file.
- Test capture-derived, versioned detector inputs independently from constructed predicate
  and boundary microtests.
- Migrate one runtime at a time with reproducible behavior-parity evidence.
- Keep runtime cost and public state behavior unchanged.

## Non-goals

- No hooks, sockets, process liveness, OSC title/progress, or other agent-side state
  authority.
- No TOML/JSON rule DSL, generic `all`/`any`/`not` interpreter, numeric priorities,
  remote updates, or user rule overrides.
- No replacement of stabilization, polling, identity detection, or display-state logic.
- No scheduled authenticated recapture in this migration.
- No obligation to migrate all supported runtimes.

This work does **not** automatically discover a vendor UI shape never captured before.
It makes known shapes regression-testable and live results explainable; proactive latest-CLI
recapture remains a possible later project.

## herdr findings and boundary

The current herdr implementation was reviewed at `fae0b236` (latest release v0.8.0).

| Adopt | Do not port |
| --- | --- |
| Stable rule IDs and explicit known-agent fallback | ~1,500-line generic manifest evaluator and nested matcher DSL |
| Runtime-specific screen regions | TOML manifests, engine versions, validation limits, overrides, remote updates |
| Deterministic precedence and explain output | Hook authority arbitration and visible-idle transition state machine |
| Capture metadata and detector-input source distinction | OSC title/progress rules as state evidence |

herdr's manifest engine improves distribution and reviewability but has not eliminated
runtime-specific drift; its current history still contains Claude, Codex, Cursor, Kiro,
and Grok rule fixes. Its Claude/Codex profiles also lean on OSC regions that Prowl has
explicitly deferred, so Prowl's screen structure must carry more of the classification
load. The transferable value is therefore the **profile/region/reason/capture model**, not
the engine.

## Proposed design

### Detection result

Add an internal result while preserving `detectState(in:)` as the compatibility projection:

```swift
struct AgentScreenDetection: Equatable, Sendable {
  let state: AgentRawState
  let reason: AgentScreenDetectionReason
}

enum AgentScreenDetectionReason: Equatable, Sendable {
  case matched(AgentScreenRuleID)
  case noRuleMatched
  case legacyDetector
}
```

`AgentScreenRuleID` is a small string-backed value. Constants stay beside their owning
profile (`CodexScreenProfile.RuleID.directoryTrust == "codex.directoryTrust"`) rather
than in one global enum. Profiles expose their IDs for a uniqueness/prefix test.

`detectState(in:)` returns `detectScreen(in:).state`; unmigrated detectors retain their
existing state and report `.legacyDetector`. A positive legacy result is not mislabeled as
a fallback.

Known-agent no-match remains `.idle`. `.unknown` is reserved for a screen that carries no
usable signal, such as a viewer overlay: the stabilizer preserves the previous state on
`.unknown`, so using it for ordinary no-match could freeze `working` indefinitely.

`AgentScreenScan` caches the complete result instead of only the state. Existing diagnostics
may log the stable reason string, never screen text. Phase 3 also adds an optional,
Release-visible `detection_reason` field to `prowl agents --json` while leaving text output
and UI unchanged.

### Snapshot, regions, and profiles

`AgentScreenSnapshot` has a deliberately small contract:

- constructed after the existing 24-non-empty-line truncation;
- retains canonical text and a split-once line representation;
- may cache mechanical per-line normalization;
- never owns named runtime regions or rule semantics.

`CodexScreenRegions` and `ClaudeScreenRegions` own prompt/menu/footer boundaries. Each
profile uses ordinary Swift predicates and early returns; source order is precedence.
There is no profile protocol or generic rule array initially.

Existing cross-runtime predicates keep one shared owner. Profiles may call shared
mechanical predicates such as spinner/numbered-choice checks; a predicate becomes private
only when its last other caller is removed. Region extraction and rule ordering remain
profile-owned. This avoids copying shared glyph tables into independently drifting files.

### Captured fixture corpus

Normal fixture path:

```text
supacodeTests/Fixtures/AgentScreenDetection/
  <runtime>/<cli-version>/<expected-raw-state>/<scenario>.txt
```

`done` is never a fixture state because it is derived from `idle + unseen`. Each `.txt`
has same-basename metadata recording capture timestamp, exact CLI version, terminal
geometry, capture source, and redaction summary. Reconstructed or synthetic screens remain
inline tests and are never presented as captured/version-stamped evidence.

A corpus fixture is the plain-text, active-screen input the detector actually receives,
normalized to the canonical 24-non-empty-line tail. It is not an arbitrary matched-region
snippet. Account, path, repository, prompt, and model-output data are redacted without
changing runtime chrome, ordering, marker positions, wrapping, or blank-line boundaries.
Raw captures go to an ignored private staging directory and are never committed.

The harness enumerates files relative to `#filePath`, validates path/metadata/state/runtime,
asserts at least one fixture ran, and reports the relative path on failure. Corpus tests
assert end-to-end state; focused inline tests assert rule IDs, precedence, and parser
boundaries. Existing constructed tests are not mechanically moved into files.

If a fresh capture exposes a current bug, it is not omitted. It enters a machine-checked
quarantine path containing expected state, current observed state, and linked issue. The
quarantine test asserts current behavior, then fails when a later fix makes promotion to
the normal corpus necessary.

Retain the newest verified capture for each scenario/UI shape. Keep an older version only
when its distinct shape remains intentionally supported; prune byte-equivalent history.

## Phased migration

### Phase 1 — detector-faithful capture seam

- Add an explicit way to read the exact `readActiveText()` / `GHOSTTY_POINT_ACTIVE` input
  used by production detection; current `prowl read` uses the viewport and is not equivalent
  when scrolled.
- Prove capture bytes and production detector input share the same source/normalization.
- Establish ignored, private raw-capture staging.

Implementation decision: ship an explicit read-only `prowl read` detection source in normal
builds, documented and tested. Its default remains the existing viewport behavior.

Exit: a live pane can be captured reproducibly without instrumenting or patching the app
locally.

### Phase 2 — corpus harness and fresh baseline

- Add the loader, metadata validator, policy README, and quarantine convention.
- Run fresh manual sessions against installed Claude and Codex versions.
- Seed Codex directory trust, hook review, sign-in, permission, working footer, idle, and
  stale/quoted negatives.
- Seed Claude trust, permission, foreground spinner/elapsed work, viewer/no-signal, idle,
  and reproducible background/subagent forms. Do not invent a subagent-wait fixture.

Exit: every freshly captured current shape is either green in the normal corpus or visible
in quarantine; zero captured failures are silently dropped.

### Phase 3 — explainable result plumbing

- Add `AgentScreenDetection`, profile-owned rule IDs, and reasons.
- Keep `detectState(in:)` as a state-only projection and wrap unmigrated detectors as legacy.
- Cache the complete result and include reason IDs in existing transition diagnostics.
- Add an optional `detection_reason` to `prowl agents --json`; text output and UI remain
  unchanged.

Exit: all raw/stabilized states are unchanged; cache tests cover reason reuse and invalidation.

### Phase 4 — Codex profile

- Move Codex region extraction, predicates, and ordered decisions into its profile.
- Preserve #674/#683 anchors and blocker-over-working precedence.
- Add positive live-idle recognition only where current chrome is structurally reliable;
  otherwise retain `.idle + noRuleMatched`.
- Use two reviewable commits: profile + temporary legacy-parity test, then legacy removal.
  No dual production classifier ships.

Exit: parity over all existing Codex tests and corpus fixtures, except separately reviewed
capture-backed behavior fixes; stable rule IDs cover every matched profile path.

### Phase 5 — Claude profile

- Move viewer, current-selection blocker, live status, elapsed status, background-work,
  and reliable idle regions into its profile.
- Preserve `.unknown` viewer behavior and the 3-second hold.
- Use the same two-commit parity protocol as Codex.
- Add no subagent-wait rule without a captured failing screen.

Exit: parity over all existing Claude tests and corpus fixtures, except separately reviewed
capture-backed behavior fixes; stable rule IDs cover every matched profile path.

### Adoption gate

After both profiles ship, measure readability, corpus upkeep, changed-frame detection cost,
and the usefulness of reasons. A third runtime migrates only with fresh fixture provenance
and demonstrated maintenance pressure. Shared abstractions are extracted only from proven
duplication; leaving legacy detectors in place is an acceptable steady state.

## Validation and invariants

Every implementation PR preserves:

- screen-only state authority and last-24-non-empty-lines semantics;
- exact `(agent, active-screen text)` cache identity;
- existing state precedence, `.unknown` behavior, and 3-second hold;
- no raw screen content in logs, analytics, or agent-status payloads;
- focused tests, complete detection/cache tests, `make check`, full tests as required, and
  `make build-app`;
- non-zero Swift Testing execution counts (suite/method selectors must not silently match
  zero tests).

Record an opt-in Release median over the corpus before and after each profile migration;
do not add an absolute CI timing gate. Snapshot splitting and region normalization should
occur once per changed screen.

## Risks and controls

| Risk | Control |
| --- | --- |
| Infrastructure outgrows the heuristic code | No DSL, profile protocol, numeric priority, remote update, or generic region registry |
| Migration changes correct behavior | One runtime per phase; reproducible parity commit; intentional differences require fresh captures |
| Strict rules create false idle | Explicit no-match reason, positive idle tripwire where reliable, quarantine for discovered failures |
| Broad rules match transcript prose | Runtime-owned live regions plus mandatory stale/quoted negative fixtures |
| Shared helpers drift after copying | Single shared owner; last-user-takes-private rule |
| Corpus becomes an archive | Newest-per-shape retention and deliberate pruning |
| Captures leak private data | Private ignored raw staging, required metadata/redaction review, no automatic commit |
| Metadata causes UI churn | Cache/diagnostics only; optional additive JSON field, no view state |
| Changed-frame CPU regresses | Parse once, preserve memoization, compare Release corpus medians |
| Partial migration creates two frameworks | Explicit legacy path; no production dual-run; no ritual migration target |

## Aligned decisions

- The detector-faithful capture seam ships as an explicit, documented, read-only
  `prowl read` source in normal builds rather than a Debug-only facility.
- Phase 3 adds optional `detection_reason` to `prowl agents --json`; it contains only a
  stable rule/fallback/legacy identifier and never raw screen text. Text output and UI do
  not change.
- Manual fixture refresh remains the initial policy. Even with positive idle rules and a
  Release-visible reason, Prowl will not proactively alert on unknown vendor UI drift; that
  limitation is explicitly accepted unless a later recapture/telemetry design is approved.
