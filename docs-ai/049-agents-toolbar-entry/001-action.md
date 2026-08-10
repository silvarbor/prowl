# 049 — Agents Toolbar Entry: Action

| | |
| --- | --- |
| **Status** | PR1 delivered on `feature/hand-off`; PR2 deferred indefinitely |
| **Anchor date** | 2026-07-20 |
| **Plan** | [000-plan.md](000-plan.md) |
| **Related** | [047.003 plan calibration](../047-cross-agent-handoff/003-plan-calibration.md), [048 agent-runtime-adapters](../048-agent-runtime-adapters/000-plan.md) |

## Delivered

- **Agents capsule** (`AgentsToolbarButton`) left of the branch title: brand
  badge + agent name for the selected pane, resolved with the Active Agents
  panel's two-step icon-token fallback. Disabled generic form without a
  detected agent (surface reserved for the future quick launcher). It draws
  its own interactive glass capsule: `sharedBackgroundVisibility(.hidden)`
  is the only way to keep it out of the branch title's glass group (a fixed
  `ToolbarSpacer` does not split the navigation group), and leaving the
  group also forfeits the system chrome, so padding, hover (a tint on the
  Glass material — translucent fills under `glassEffect` are swallowed by
  material compositing), and typography (mirroring the branch title's
  title3-medium metrics) are self-drawn.
- **Popover** as the durable agent-actions container: one full-row action —
  `Hand Off…` with a plain-language explanation underneath ("Pass this task
  to another agent in a new tab", plus "codex will summarize its progress
  first" when the session is resumable) — highlighted as one button; future
  actions land as additional rows.
- **`HandoffHudFeature` + overlay**: staged choose → briefing → save →
  archive → launch flow driven through `HandoffCoordinator` (same artifacts
  and log lines as the CLI). Skip cancels the briefing child process and
  continues mechanically; Cancel during briefing aborts with zero artifact
  and log changes; stage guards drop racing briefing results; a key-capture
  NSView keeps arrows/Return/Escape/**S** out of the live terminal. Execution
  state is reducer-owned — the HUD is a projection.
- **Briefing cancellation integrity**: source replies remain transient until
  `HandoffHudFeature` accepts them while still briefing; late replies after
  Skip or Cancel cannot write `current.md`. Skip is also available through
  the HUD's `S` shortcut, which the key-capture view consumes before input can
  reach the live terminal. See [002-briefing-cancellation.md](002-briefing-cancellation.md).
- **Palette convergence**: one `Hand Off…` row opening the HUD; the two
  direct-execution rows are gone, and the post-palette focus restore skips
  hand-off so the HUD keeps first responder.
- **Preparation-prompt hardening** (during review): reader framing,
  per-section guidance, snapshot semantics for `current.md` (each
  preparation rewrites it fresh from the source session's knowledge; the
  rolling carry-forward instruction and a brief embedding attempt were
  dropped — see the plan amendments), a no-redo instruction plus an
  `archive/` pointer in the kickoff prompt, and a normalizer that discards
  post-fence chatter.
- Event-stream hygiene surfaced during review: `emitAgentEntry` deduplicates
  against the last consumer-visible `ActiveAgentEntry`, keeping raw-state
  oscillation and session-miss bookkeeping out of the TCA action stream.

## Verification

- `HandoffHudFeatureTests` (state machine, Skip/Cancel semantics, race
  guards, artifact assertions against a real temp store),
  `AppFeatureHandoffTests` (palette → HUD → run end-to-end, source
  attribution, no-agent gating), `HandoffCommandHandlerTests` (prompt/
  template/validator section contract, prompt independence from the
  existing artifact),
  `HandoffStoreTests` (fence/chatter fixtures), `AgentEntryEmissionDedupTests`.
  Full suite green (1,910+), `make check` clean.
- Live debug-app verification: capsule enabled/disabled forms, agent
  detection driving the capsule, HUD rendering, and an
  `AXUIElementCreateApplication` dump confirming the capsule is a proper
  `AXButton` (closing the accessibility concern). Interactive polish
  (heights, hover, popover) was verified by onevcat across review rounds.

## Deviations from plan

- The pull-down is a popover, not a system `Menu` (macOS flattens custom
  toolbar-menu labels to text).
- The display-state dot was removed permanently; the capsule identifies the
  hand-off source and carries no status.
- Palette convergence shipped as plan option (a): the direct-execution rows
  were removed rather than kept as HUD-execute shortcuts.
- **PR2 (dismiss-while-running) is deferred indefinitely**: Skip covers the
  waiting pain, hand-off is low-frequency, and the reducer-owned state
  means a future wave starts with zero rework.

## Later layout evolution

The placement and custom glass treatment above describe the initial delivery. On
2026-08-07, [058 unified toolbar layout](../058-unified-toolbar-layout/000-plan.md)
removed the redundant branch title and placed Agents + Quick Launch first, followed
by a separately surfaced notifications capsule, across Normal, Shelf, and Canvas. The
Agents popover and hand-off behavior remain the durable entry point delivered here.
