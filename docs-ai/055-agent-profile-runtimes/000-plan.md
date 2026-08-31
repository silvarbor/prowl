# 055 — Agent Profile Runtimes: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-01 |
| **Primary PRs** | [#643](https://github.com/onevcat/Prowl/pull/643) |
| **Related** | [045 native-agent-session-detection](../045-native-agent-session-detection/000-plan.md), [047 cross-agent-handoff](../047-cross-agent-handoff/000-plan.md), [048 agent-runtime-adapters](../048-agent-runtime-adapters/000-plan.md), [053 agent-profiles](../053-agent-profiles/000-plan.md), [runtime research](research-agent-profile-runtimes.md), `docs/components/agent-profiles.md`, `docs/components/handoff.md` |

## Background

Prowl recognizes fourteen agent families, but `AgentRuntimeAdapterRegistry` and
`AgentProfileRuntime` currently expose only Claude Code and Codex. The current
`AgentRuntimeAdapter` protocol requires every adapter to observe a live launch,
construct interactive and headless starts, support a side-effect-free native-session
resume, and optionally relocate its account home. That all-or-nothing boundary was a
safe first implementation for handoff and Agent Profiles, but it conflates independent
runtime capabilities.

The coupling becomes a maintenance problem as the product expands. A CLI may have a
verified interactive invocation suitable for a launch profile while exposing different
native resume semantics. Another may support model selection or a dedicated config root
but not a portable unrestricted mode. Requiring the weakest capability before
registering the runtime would unnecessarily block Profile support; native resume belongs
to a separate product contract rather than Profile launch eligibility.

This wave researches the current released CLIs, validates them locally where credentials
permit, separates those capability gates, and extends Agent Profiles to every recognized
runtime whose interactive launch can be verified.

## Goals

- Produce a current matrix for every `DetectedAgent`: executable and aliases, installed
  version, interactive start, prompt/headless start, model and reasoning flags,
  permission/unrestricted mode, account-home relocation, native session resume,
  and local end-to-end evidence.
- Verify command contracts from official documentation and local `--help`; use source
  inspection for open-source agents when the first two layers appear insufficient.
- Exercise locally available agents inside disposable Prowl panes and distinguish
  successful launch/detection from successful authenticated task completion.
- Refactor runtime adapters so Profile launch, live observation, and account isolation
  are independently represented capabilities; keep native resume outside that registry.
- Preserve the existing Claude/Codex persisted profile format and launch behavior.
- Add Profile support for every recognized agent with a verified interactive launch,
  while exposing only the settings that the adapter can render honestly.
- Keep the resulting launch abstraction reusable by profile-based handoff and future
  cross-agent workflows without making those workflows part of this implementation.
- Add focused test-first coverage for every invocation mapping and capability boundary,
  then validate formatting, the relevant suites, CLI gates, and the macOS app build.

### Non-goals

- Installing or configuring paid credentials on the user's behalf.
- Claiming authenticated runtime behavior when only documentation or `--help` was
  available; such rows remain explicitly marked best-effort/community verification.
- Expanding Prowl's detected-agent catalog beyond its current cases unless research
  proves an existing case cannot be launched under its recorded token.
- Implementing profile-based handoff, dispatch, cross-review, or session pre-minting in
  this PR. The capability model must enable those waves without guessing their UX.
- Sharing credentials, sessions, or mutable config directories between profile homes.

## Design / Approach

### 1. Evidence before adapter code

Maintain the durable matrix in `research-agent-profile-runtimes.md`. For each runtime,
collect evidence in this order:

1. installed binary path, version, and top-level/subcommand help;
2. official CLI documentation for unclear or potentially changed flags;
3. disposable-pane launch through `prowl`, followed by Prowl detection and controlled
   exit; run a trivial authenticated prompt only when the existing account permits it;
4. upstream source inspection when docs/help suggest a capability is absent or unsafe.

The matrix uses separate confidence for launch, configuration, account isolation, and
resume. A missing credential may prevent task completion without invalidating a proven
interactive launch contract.

### 2. Split runtime capabilities

Keep one catalog keyed by `DetectedAgent`, but stop treating registration as proof of all
operations. The intended boundary is:

- a **launch adapter** builds interactive/prompt/headless invocations and reports the
  options it supports for Profiles;
- **launch observation** parses only settings that argv proves explicitly;
- **account isolation** is optional metadata on the launch adapter, including the
  runtime's default config location and verified relocation variable/flag;
- native resume behavior is research evidence only; it does not participate in the
  generic launch adapter or Handoff contract.

`canStart` and Profile eligibility derive from the launch registry. Handoff briefing is
provided explicitly by the live source agent or omitted with `--no-brief`; it never
acquires a second native-session owner through the runtime registry.

### 3. Honest Profile configuration

Persist the expanded runtime tokens without changing existing Claude/Codex encodings.
All verified runtimes get name, icon, placement, extra argv, and launch-scoped environment
overrides. Model, reasoning effort, unrestricted execution, and dedicated-home controls
appear only when the adapter declares a verified rendering for them.

An unsupported dedicated home is never approximated with `HOME` and cannot be supplied
through the environment override table. Switching a profile to a runtime with fewer
capabilities normalizes fields whose old semantics cannot be preserved safely, while
literal extra argv stays under explicit user control.

### 4. Test-first implementation

Before adding a runtime implementation, add tests for its expected invocation and
capability surface and observe the focused suite fail. Implement the smallest adapter to
make it pass. Add regression tests for:

- start and optional prompt/headless argv ordering;
- model/reasoning/unrestricted mappings only where supported;
- Profile launch eligibility remaining independent from native resume research;
- persisted runtime decoding and seeded-profile coverage;
- runtime switching and unsupported-field normalization;
- planner behavior with and without dedicated-home support;
- handoff requiring explicit `--brief` or `--no-brief` input.

After logic tests are green, validate real launches from the current app, then run
`make check`, the focused/full relevant test gates, CLI build/smoke/integration tests if
CLI code changes, and `make build-app`.

### 5. Documentation and delivery

Update `docs/components/agent-profiles.md` with the shipped runtime matrix and per-runtime
limitations. Update `docs/components/handoff.md` only if the refactor changes current
handoff behavior. Complete `001-action.md` with the actual evidence, deviations, commits,
and final PR, then commit in reviewable layers and submit a non-draft PR to
`onevcat/Prowl`.

## Alternatives & decisions

- **Extend the existing monolithic adapter for all agents — rejected.** Default methods
  that throw would make registration ambiguous, while requiring real resume support
  would exclude otherwise valid Profile runtimes. Future callers would continue to ask
  the wrong question: “does an adapter exist?” instead of “does this operation exist?”
- **Create a Profile-only command table — rejected.** It would duplicate executable,
  model, permission, quoting, and display metadata beside handoff, recreating the drift
  that entry 048 originally removed.
- **Capability-based runtime catalog — selected.** It preserves one reviewed invocation
  path while allowing each product workflow to require exactly the guarantees it needs.
  It also makes unsupported settings representable in the UI instead of relying on empty
  strings or runtime failures.
- **Use arbitrary user-authored command templates — rejected.** Extra argv and
  launch-scoped environment overrides already cover expert customization without moving
  executable selection, shell quoting, or secret handling outside reviewed code.

## Amendments

- Updated 2026-08-01: Correct execution-policy semantics and separate Pi from
  Oh My Pi throughout detection and session identity — see
  [002-execution-policy-and-pi-omp-separation.md](002-execution-policy-and-pi-omp-separation.md).
- Updated 2026-08-01: Remove the obsolete resume/fork briefing fallback and
  keep native resume outside the Profile/Handoff adapter contract — see
  [047.006](../047-cross-agent-handoff/006-remove-fork-briefing.md).
- The launch catalog remains keyed by `AgentProfileRuntime`, with a one-to-one
  mapping to canonical detection identity. Pi and Oh My Pi now have distinct
  executables, icons, option contracts, availability checks, heuristics, and
  session stores.
- A relocated Profile home now records its native session/config root
  separately from the provisioned root. Gemini nests state under `.gemini`,
  while Cline uses an explicit `data/tasks` subtree; assuming both paths are
  identical would break bound-session resolution.
- Handoff destination admission is an explicit product policy and remains
  Claude Code/Codex-only. A runtime being Profile-launchable does not imply
  any native resume operation.
- Amp supports bare interactive Profiles and headless execution, but not a
  seeded interactive prompt through argv. The adapter rejects that intent
  explicitly instead of silently changing the requested interaction mode.
- Updated 2026-08-22: the "profile-based handoff, cross-review, and other cross-agent orchestration" follow-up waves are planned as [063-agent-workflows](../063-agent-workflows/000-plan.md), consuming the launch intent and capability model established here.
- Updated 2026-08-22: 063-A2 implemented that consumption in PR #714: CLI Profile launches compile through each runtime adapter, preserve unsupported-intent errors, and return exact pane identity. Runtime capability ownership remains here; completion-hook rendering is deferred to 064-S3.
