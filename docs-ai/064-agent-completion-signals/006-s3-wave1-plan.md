# 064.006 — S3 Wave 1 PR Plan

## Status

Complete. S3a merged in [#721](https://github.com/onevcat/Prowl/pull/721) (hardened
in [#723](https://github.com/onevcat/Prowl/pull/723)). Implementation record:
[007-s3a-action.md](007-s3a-action.md). S3b merged in [#725](https://github.com/onevcat/Prowl/pull/725) (plan
[008-s3b-plan.md](008-s3b-plan.md), record [009-s3b-action.md](009-s3b-action.md)). S3c merged
in [#728](https://github.com/onevcat/Prowl/pull/728) (plan
[010-s3c-plan.md](010-s3c-plan.md), record [011-s3c-action.md](011-s3c-action.md)), completing
S3 wave 1.

- Planning branch: `feat/agent-signal-hooks-s3a`
- Prerequisites: 063-A2, 064-S1, and 064-S2 are merged.
- Runtime baseline rechecked 2026-08-23: Claude Code 2.1.241; Codex CLI 0.149.0.
- Re-attested 2026-08-25 for S3b: Claude Code 2.1.243; Codex CLI 0.149.0; Copilot CLI 1.0.80;
  Factory Droid 0.202.0; Qoder CLI 1.1.29.
- Re-attested 2026-08-26 for S3c: Pi 0.84.3; Oh My Pi 18.0.6; OpenCode 1.18.23.
- S3 has no wave 2. Managed hooks are limited to runtimes that accept process-scoped
  flag/environment injection without global-config, dedicated-home, or project-file writes.

## S3 wave 1 PR breakdown

S3 wave 1 is one complete R1 release slice, delivered as three sequential merge-safe PR
scopes. S3c passed the complete tier-A gate in #728.

| PR | Runtime scope | Foundation / closure scope | Depends |
| --- | --- | --- | --- |
| **S3a** | Claude Code, Codex | Trusted launch-channel registration, native-hook ingress and payload normalization, self-check/channel lifecycle, launch-epoch integration, bundled CLI/resource locator | S2 |
| **S3b** | Copilot, Droid, Qoder | Plugin/settings adapters and fixtures on the S3a foundation | S3a |
| **S3c** | Pi, OMP, OpenCode | Extension/plugin adapters, complete docs and tier-A live verification (the exact-channel badge was dropped on 2026-08-26) | S3b |

Every PR kept `main` shippable. S3c completed the tier-A runtime set and closed the wave.

## S3a objective

Make Prowl Agent Profile launches of Claude Code or Codex automatically report supported
native runtime events into the existing S1/S2 signal bus, with honest `verified_live`
coverage, no global configuration writes, and no loss of an existing user notifier. When
Prowl cannot prepare a managed hook without preserving user behavior, the launch proceeds
without that hook and exposes no exact coverage.

S3a normalizes only runtime facts:

- Claude `SessionStart` -> `session-start`;
- Claude `Stop` and `StopFailure` -> `turn-ended`;
- Claude `PermissionRequest` and supported elicitation events -> `needs-input`;
- Claude `SessionEnd` -> `session-end`;
- Codex `agent-turn-complete` notify -> `turn-ended`.

A hook `turn-ended` never completes a dispatch or workflow step. S2 receipt priority and the
300 ms terminal-evidence coalescing window remain authoritative: a matching
`dispatch-complete` receipt wins; a turn edge without a receipt is `DISPATCH_INCOMPLETE`.

### Non-goals

- No Copilot, Droid, Qoder, Pi, OMP, or OpenCode adapters (S3b/S3c).
- No Gemini, Qwen, Grok, Cline, Kimi, Cursor, or Amp managed hooks.
- No Active Agents exact badge (later dropped from S3c without commitment).
- No transcript/OSC producers, workflow watchdog changes, result capture, or full
  `last_assistant_message` storage.
- No public configured/degraded channel state, token persistence, cryptographic trust model,
  global config editing, or project-file writes.
- No redesign of `agents wait`, dispatch receipts, or the signal bus.

## Research findings and existing seams

### Reusable foundations

The repository already has the required downstream behavior:

- `AgentSignal.Source.hook` in
  `supacode/Domain/AgentDetection/AgentSignal.swift`;
- process generation, session freshness, evidence epochs, and per-source channels in
  `supacode/Features/Terminal/BusinessLogic/AgentObservationStore.swift`;
- exact caller attribution through socket peer PID ancestry in
  `supacode/CLIService/CLICommandContext.swift`;
- strict dispatch/evidence handling in
  `supacode/Features/Terminal/BusinessLogic/AgentDispatchStore.swift`;
- `verified_live` wait gating in `supacode/CLIService/AgentWaitCommandHandler.swift`;
- child-only launch carriers and the shared A2 launch boundary in
  `supacode/Domain/AgentProfile/AgentProfileLaunchPlan.swift` and
  `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`;
- an app-bundled CLI at `Resources/prowl-cli/prowl` in Debug and Release builds.

S3a adds producers and registration to these boundaries; it does not create a second signal
or launch path.

### Blocking implementation constraints

1. **One Profile launch epoch.** `bindAgentDispatch` currently calls
   `beginDispatchEpoch` after the Profile surface has launched. S3 registration must begin
   after the exact surface identity exists but before its initial input can execute, so dispatch
   binding adopts that epoch rather than minting another one and clearing early hook evidence.
2. **Early native events.** Claude `SessionStart` can reach Prowl before surface creation
   returns and before periodic detection has resolved the agent PID. The launch token must
   already be registered to the exact caller pane before initial input delivery. Its event is
   accepted as pending process evidence, then bound when the first launch generation appears
   within the existing acquisition window; it must not be downgraded or lost.
3. **Prompt/config carriers.** `AgentProfileLaunchPlan.terminalInput` currently replaces only
   the final prompt argv value. Claude settings JSON is a non-final argument and can exceed the
   canonical PTY limit. Shell rendering must support typed argv-index -> environment-carrier
   replacement without putting hook JSON or tokens into initial input/history.
4. **Every A2 path.** Registration belongs in `WorktreeTerminalManager` so typed CLI launches
   and menu/palette compatibility launches share preparation, exact returned surface identity,
   rollback, and cleanup. Manually typing `claude` or `codex` into a shell is not covered.
5. **Fail-open observation.** A native hook must emit no stdout, make no runtime decision, use
   a bounded socket attempt, and exit successfully even when Prowl rejects or cannot receive
   the event. Hook failure may remove an optimization; it must never block or alter the agent.
6. **Codex internal work.** Codex can emit notify events for internal memories work. The
   decoder/registration must reject a cwd outside the effective launch directory, including
   `~/.codex/memories`.
7. **Codex notifier preservation.** Codex accepts one effective `notify: array<string>`
   command. Prowl may replace it process-locally only after resolving the complete effective
   user notifier and registering a transparent forward target. If resolution fails, Prowl
   preserves the user's launch and omits its managed Codex hook instead of swallowing a
   notifier it cannot reproduce.
8. **Asynchronous launch preparation.** Codex's own `app-server config/read` is the source of
   truth for merged config parsing and must run with a bounded timeout off the main actor.
   Every A2 launcher therefore needs one shared asynchronous preparation boundary before any
   dispatch issuance or launch mutation, while preview remains pure and deterministic. After
   a dispatch slot is issued, no new suspension point may occur before synchronous
   launch/bind/rollback; peer disconnect during preflight has no dispatch state to leak.
9. **Forwarding-record retirement.** Revoking hook trust and deleting the only forward argv
   cannot be one operation: a Codex notifier helper may already be spawned but not yet have
   opened its record. The bridge must open/validate/read before transport, while close,
   replacement, and rollback retire the record through a lock-aware grace rather than unlinking
   it immediately.
10. **No notifier is success.** A valid effective Codex configuration with no `notify` is the
   common direct-injection path, not an empty/malformed-forward-target degradation.
11. **Stable launch context across preflight.** Codex preserves user `-C/--cd` arguments, and
   menu split/tab inheritance currently depends on live focus/cwd at creation time. Async
   preflight cannot resolve config or register launch-cwd trust against one context and then
   let the synchronous launch silently choose another. Capture a typed target/base/effective
   cwd before preflight and revalidate it before dispatch issuance.

## Proposed S3a design

### 1. Adapter-owned capability and deterministic base plan

Add a small `AgentSignalHookCapability`/launch-template model exposed by runtime adapters.
Claude and Codex render their own native flags before a positional prompt. The base
`AgentProfileLaunchPlan` remains deterministic and preview-safe: it contains a hook template,
covered events, absolute bundled CLI path, socket transport setup, and carrier descriptors,
but no random execution token.

Production planner callers pass an injected resource descriptor instead of having the pure
planner read the filesystem. Settings preview uses the same descriptor and redacted carrier
rendering.

Runtime-specific rendering:

- Claude: exactly one effective `--settings <json>` source with command hooks. Existing normal
  user/project/local settings continue to merge additively. If a Profile already supplies one
  or more explicit `--settings value` / `--settings=value` arguments, resolve the final effective
  source using the pinned CLI precedence, bounded-read a file source or decode an inline object,
  preserve every unknown/unrelated field and existing hook handler, append only Prowl's missing
  event handlers, and render the merged object through a carrier. Duplicate Prowl handlers are
  not appended. If the effective source is unreadable, malformed, non-object, oversized, or
  changes during preparation, retain the user's argv unchanged, omit managed hooks, and warn.
- Codex: when notifier preparation succeeds, one structured TOML `-c notify=[...]` override
  containing the bundled CLI absolute path and hidden native-hook arguments. Never pass
  `--dangerously-bypass-hook-trust`; never inject the override until any displaced notifier
  has an exact forwarding registration.

### 2. Codex effective-notifier resolver and transparent dispatcher

Before a Codex surface is created, capture a typed `CodexLaunchContext`: exact target/anchor,
inherited base cwd, effective cwd after the final supported `-C/--cd` form, effective
`CODEX_HOME`, and ordered config/profile overrides. Menu/palette launches must not re-resolve a
different focused pane after the await. Revalidate target existence and cwd immediately before
dispatch issuance; a mismatch retries preparation against the new explicit context or preserves
the unmodified launch with one degradation warning. Registration binds the exact surface and
its effective post-`--cd` launch cwd.

A bounded `CodexEffectiveNotifyResolver` resolves the notifier that this frozen unmodified
launch would execute. Its typed result is exactly one of:

- `.absent`: effective config has no `notify`; inject Prowl directly with no forwarding record;
- `.present(nonEmptyArgv)`: prepare the private record, then inject Prowl's dispatcher;
- `.degraded(reason)`: preserve the unmodified launch, inject nothing, and surface one warning.

Resolution precedence:

1. query Codex 0.149's official `app-server config/read` protocol with the frozen effective
   `CODEX_HOME`, effective post-`--cd` cwd, and relevant `-c/--config` overrides;
2. structurally recognize `-p/--profile`, whose profile file has higher precedence than the
   base config; because `codex app-server` rejects `--profile`, let Codex parse that file in an
   isolated temporary parser home and use only a profile-owned `notify` value, otherwise fall
   back to the merged base result;
3. let the final top-level CLI `-c notify=...` override win, preserving the exact decoded argv;
4. treat an explicitly configured empty, malformed, oversized, or recursively Prowl-managed
   forward target as `.degraded`, without conflating it with `.absent`.

The resolver never edits user, dedicated-home, or project config. Temporary parser state is
owner-only, contains no generated agent account, and is removed immediately. It does not log
or persist returned config or notifier argv. A timeout, unsupported Codex protocol, malformed
response, or unreadable selected profile produces `.degraded`: preserve the original launch,
omit the Prowl `notify` override, and expose no `verified_live` Codex channel. The launch still
succeeds but returns one non-blocking degradation warning.

GUI and CLI launchers await this preflight before issuing an optional dispatch slot. Cancellation
at this suspension point removes scratch/parser/forwarding artifacts but has no launch, epoch,
or dispatch state to roll back. Once a dispatch is issued, plan rendering, surface creation,
pre-input registration, dispatch binding, and rollback remain one synchronous transaction.

For `.present`, Prowl atomically creates one session-scoped forwarding record under
a random directory in its private runtime area. The directory is `0700`, the record is `0600`,
and only an opaque locator—not its contents—crosses the child-only launch carrier. The record
contains no hook token or provider config and is never placed in user config, a dedicated
agent home, the worktree, terminal input, preview, logs, or durable Prowl state.

The hidden bridge first opens the record with no-follow semantics, validates owner/type/mode,
acquires a shared lease, and reads the bounded argv before attempting socket transport. It then
makes the bounded Prowl signal attempt and `exec`s the original notifier directly—no shell—with
the inherited cwd/environment and original Codex JSON payload appended unchanged. Before
`exec`, it removes Prowl's internal hook token and forwarding locator from the environment.
Prowl transport success or failure cannot suppress forwarding, and the original notifier
retains the process/exit semantics Codex would have observed. Prowl evidence and user
forwarding are independent and each occurs at most once per native notification.

Surface creation failure removes a record that was never exposed to a child. Surface close,
process replacement, and rollback revoke hook trust immediately but move an exposed record to
a retired set for a bounded spawn grace. Cleanup takes an exclusive lease after that grace and
defers a locked record, so an already-started bridge cannot lose its sole argv copy between
spawn and read. App startup and an age-bounded orphan sweep clean crash leftovers without
touching registered live or leased records. Record creation, permission enforcement,
validation, retirement, or cleanup setup failure is a pre-launch degradation: preserve the
original Codex launch and do not inject Prowl's `notify` override.

### 3. Execution-scoped token and child-only transport

Immediately before surface creation, `WorktreeTerminalManager` generates an opaque UUID
channel token and patches only the execution copy of the launch plan:

- the surface receives opaque carrier values;
- `env(1)` copies the token and exact `PROWL_CLI_SOCKET` path into the launched agent process;
- `env -u` removes the carriers from the child environment;
- the pane shell never receives the public hook token variable, so a later manually launched
  runtime does not inherit the channel.

Surface creation becomes two-phase at the manager/state boundary: create and install the exact
surface identity without arming initial input; begin one Profile launch epoch and register
`{token, surface, runtime, launch cwd, covered events, epoch, optional forward record}`; then arm
initial input. A lower-level pre-input callback is also acceptable if it proves the same order.
Creation or pre-input registration failure rolls back the surface and registration before any
agent command executes. Dispatch binding adopts this epoch. Target-resolution rollback,
process replacement, and surface close revoke trust immediately and retire any exposed
forwarding record through the lease protocol above.

The token is a correctness capability, not a hostile-process secret. It never appears in CLI
arguments, prompt text, output payloads, logs, or persisted Profile/run state. A displaced user
notifier may contain credentials, so its argv is sensitive: the only at-rest copy Prowl creates
is the owner-only ephemeral forwarding record, and neither its contents nor path is public API.

### 4. Hidden native-hook bridge over the existing signal command

Add a hidden `prowl agents _hook <runtime> <native-event>` leaf. It is bundled-internal, not a
user command or targetable API.

- Claude mode reads bounded stdin JSON.
- Codex mode reads the final bounded argv JSON payload.
- Pure decoders validate the native event, extract a bounded session/thread id and small
  event-specific detail, ignore unknown future fields, and never copy the full last assistant
  message.
- The bridge reads the token from its inherited environment and sends an internal hook context
  through the existing `agents.signal` envelope/socket route.
- Public `prowl agents signal` cannot provide hook context and remains
  `source=cooperative_cli`.
- The app validates token, exact caller pane, configured runtime/native event, launch cwd, and
  current/pending process generation before constructing `.hook(...)`.
- Codex forwarding is driven by the private launch record, not by a successful app response;
  public `agents signal` never receives forwarding instructions or record contents.

The hook bridge uses the app-bundled CLI path, not `PATH` or `/usr/local/bin/prowl`, suppresses
all output, does not auto-launch Prowl, and has bounded connect/read/write behavior. Delivery
failure exits zero so observation cannot interfere with the runtime.

### 5. Channel verification and lifecycle

Keep registration state inside `AgentObservationStore`; do not add a parallel store.
Internally a registration may be pending, verified, or degraded, but the existing public
channel model remains:

- unverified/degraded: no `verified_live` channel is exposed, so `auto` wait may use honest
  heuristic fallback;
- verified: channel state is `verified_live` with the adapter-declared covered events;
- process replacement/surface close: registration and verified coverage are removed;
- a same-process Claude session replacement rotates signal freshness while retaining the
  launch channel, provided a valid new `SessionStart` establishes the new session;
- cooperative signals update only their own channel and never erase hook liveness.

Claude's first valid native event, normally `SessionStart`, verifies its configured hook set.
A 60-second active/non-blocked grace may record an internal degraded diagnostic; blocked
workspace trust pauses the diagnostic grace, and any later valid event recovers. This timer
never changes wait behavior by itself.

Codex has no startup notify. Transport/resource preflight is diagnostic only; the first valid
`agent-turn-complete` is the only end-to-end verification and covers only `turn-ended`.

## TDD implementation order for S3a

Logic-layer work follows strict RED -> GREEN; bridge/runtime behavior adds isolated live
verification where unit tests cannot prove third-party behavior.

### Phase 0 — freeze fixtures and transport policy

- Capture current Claude/Codex versions and help in the work note.
- Capture the exact Codex 0.149 app-server initialize/`config/read` JSONL transcript and a
  scratch-home precedence matrix for absent/base/profile/final-CLI-override `notify`, including
  proof that project-layer `notify` is ignored; retain sanitized fixtures, not returned
  user/provider config.
- Freeze supported Codex `-C/--cd` token forms, repeated-option behavior, relative-path base, and
  config-read cwd against 0.149 help/live probes. Phase 0 found that repeated cwd options are
  rejected rather than last-wins; S3a therefore degrades without injection and preserves argv.
- Use scratch homes/directories only; never edit live user/global config.
- Add representative official native payload fixtures, including optional/unknown fields,
  malformed data, oversized strings, Codex memories cwd, and paths with spaces/non-ASCII.
- Reconfirm Claude 2.1.241 payload/trust behavior in an isolated scratch workspace.
- Record the resolved Codex notifier-preservation decision before production rendering.

### Phase 1 — pure models, renderers, and decoders

RED/GREEN coverage:

- Claude settings JSON generation and native event mapping;
- final-effective Claude settings collision parsing across repeated `--settings value` /
  `--settings=value`, inline objects, and file sources;
- merge preserves unknown/unrelated fields and every existing hook handler, appends Prowl
  handlers exactly once, and keeps existing normal user/project/local settings additive;
- bounded read, malformed/unreadable/non-object/changed settings preserve original argv exactly,
  inject no hook, and produce one degradation warning;
- Codex TOML argv rendering and structural `-p/--profile` plus top-level
  `-c/--config notify` recognition;
- no hook trust bypass or recursive Prowl forwarding target;
- Claude stdin and Codex final-argv decoding;
- unknown native events and malformed/oversized payloads fail closed;
- session/thread extraction, cwd validation, and last-message exclusion;
- interactive/prompt/headless argument order keeps the positional prompt final.

Primary files/tests:

- `supacode/Domain/AgentRuntime/AgentRuntimeAdapter.swift`;
- new focused shared hook model/decoder files;
- `supacodeTests/AgentRuntimeAdapterTests.swift`;
- new `AgentNativeHookPayloadTests`.

### Phase 2 — Codex effective-notifier resolution

RED/GREEN coverage:

- bounded app-server JSONL initialization and `config/read` request/response handling;
- clean scratch home resolves `.absent`, injects Prowl directly, creates no forward record, and
  emits no degradation warning;
- effective base/system notifier resolution under the launch `CODEX_HOME` and cwd;
- selected profile notifier wins base, absent profile notifier falls back to base;
- final top-level CLI `-c notify` wins profile, while unrelated config overrides do not;
- exact argv preservation for spaces, empty arguments, Unicode, quotes, and secret-like values;
- unsupported protocol, timeout, malformed config/response, unreadable profile, empty argv, and
  recursive Prowl target all produce a no-injection degradation rather than user-notifier loss;
- temporary parser homes are owner-only and removed on success, failure, and cancellation;
- typed launch context freezes target/anchor, inherited base cwd, effective post-`--cd` cwd,
  `CODEX_HOME`, and ordered overrides before preflight;
- target/focus/PWD mutation while preflight is suspended cannot launch with a stale resolver
  result: revalidate before issuance, then retry or degrade without injection;
- cancellation/peer disconnect during preflight leaves no dispatch slot, surface, registration,
  epoch, or forwarding artifact;
- no effective config or notifier argv reaches logs, durable settings/state, previews, or
  terminal carriers; only the private ephemeral forwarding record may hold resolved argv.

Primary files/tests:

- new focused `CodexEffectiveNotifyResolver` and app-server protocol models;
- `supacodeTests/CodexEffectiveNotifyResolverTests.swift`;
- scratch-home live contract tests against the pinned Codex CLI, including project-level
  `notify` exclusion and supported `-C/--cd` forms.

### Phase 3 — deterministic plan and generalized carriers

RED/GREEN coverage:

- typed arbitrary-argument carrier rendering in `AgentInvocation`/`AgentProfileLaunchPlan`;
- hook JSON/token/socket values absent from terminal initial input and preview;
- carrier cleanup works unchanged under zsh, bash, and fish;
- long prompt + long hook JSON remains below canonical PTY limits;
- Profile environment overrides cannot replace reserved Prowl hook variables;
- unavailable bundled CLI degrades without mutating the user's launch.

Primary files/tests:

- `supacode/Domain/AgentProfile/AgentProfileLaunchPlan.swift`;
- `supacode/Support/SupacodePaths.swift`;
- `supacodeTests/AgentProfileTests.swift`;
- `supacodeTests/AppFeatureAgentProfileTests.swift`.

### Phase 4 — launch epoch, registration, and rollback

RED/GREEN coverage:

- two-phase surface creation installs exact identity and registration before initial input;
- explicit typed CLI targets and menu/palette compatibility targets keep their frozen anchor/cwd
  through preflight; anchor removal and cwd drift follow tested retry/degradation semantics;
- a synchronously delivered `SessionStart` during launch cannot beat token registration;
- one launch epoch shared by hook registration and dispatch binding;
- valid early `SessionStart` queues before detector generation and binds afterward;
- first timely process generation attaches; late/replacement generation revokes;
- wrong token, pane, runtime, native event, cwd, session, or generation cannot verify;
- target-resolution rollback, split/tab failure, process replacement, and surface close clean
  registrations and pending events;
- typed CLI and menu/palette compatibility launches both register exact resulting surfaces;
- unprompted Profile launch gets hooks; manual shell launch does not;
- Codex forwarding records use random paths, `0700`/`0600` permissions, atomic creation, and
  lease-aware retirement/cleanup on failure, rollback, process replacement, surface close, and
  orphan sweep;
- deterministic close/replacement-versus-bridge-open tests prove an already-spawned bridge can
  read before exclusive cleanup, while trust revocation remains immediate;
- record contents never enter the child environment; only an opaque locator does;
- GUI and CLI Profile launchers await the same bounded preparation before dispatch issuance or
  surface creation, without blocking the main actor;
- cancellation at every suspension boundary cleans preparation, while the post-dispatch
  launch/bind/rollback transaction contains no suspension point;
- a degraded GUI launch emits exactly one non-blocking warning toast;
- a degraded CLI launch succeeds with `warnings: [LifecycleCommandWarning]`, omitted when
  empty; the first stable warning is `{code: "managed_hook_degraded", runtime, message}`;
- `prowl.cli.create.v1` closed-schema fixtures accept the additive warning array, existing
  decoders tolerate it, JSON mode keeps it in stdout, and text mode renders it exactly once to
  stderr;
- degradation never becomes a persistent public channel state and never changes dispatch
  receipt behavior.

Primary files/tests:

- `supacode/Features/Terminal/BusinessLogic/AgentObservationStore.swift`;
- `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`;
- `supacode/CLIService/Shared/LifecycleCommandPayload.swift`;
- `ProwlCLI/Output/OutputRenderer.swift`;
- `ProwlCLIContracts/Resources/cli-output-schema.json`;
- `supacode/App/supacodeApp.swift`;
- `supacodeTests/AgentEvidenceEpochTests.swift`;
- `supacodeTests/AgentObservationTests.swift`;
- `supacodeTests/WorktreeTerminalStateAgentProfileTests.swift`;
- `supacodeTests/CLILifecycleCommandHandlerTests.swift`.

### Phase 5 — hidden CLI ingress, forwarding, and schema contract

RED/GREEN coverage:

- hidden parser is absent from normal help/completion;
- public `agents signal` wire/receipt behavior remains cooperative and unchanged;
- native hook input round-trips over a real framed Unix socket with kernel peer PID ancestry;
- stale/missing token and outside-pane callers fail closed in the app while the hook process
  itself stays silent and exits zero;
- Codex forwarding uses exact argv boundaries and the unchanged native payload, never a shell;
- the bridge scrubs Prowl's token/locator and `exec`s the original notifier after the bounded
  signal attempt, whether that attempt succeeds or fails;
- user notifier failure cannot suppress a recorded Prowl signal, and Prowl transport failure
  cannot suppress, recursively invoke, or duplicate the user notifier;
- bounded payload and socket deadlines; listener loss and malformed responses do not affect
  the runtime;
- hook response sources validate as `hook_claude` / `hook_codex` without exposing a token.

Primary files/tests:

- `ProwlCLI/Commands/AgentsSignalCommand.swift` plus a hidden hook command;
- `supacode/CLIService/Shared/InputModels.swift`;
- `supacode/CLIService/AgentSignalCommandHandler.swift`;
- `ProwlCLIContracts/Resources/cli-output-schema.json`;
- `ProwlCLITests/AgentsCommandParsingTests.swift`;
- `ProwlCLITests/ProwlCLIIntegrationTests.swift`;
- `supacodeTests/CLIAgentSignalCommandHandlerTests.swift`;
- `supacodeTests/CLISocketServerTests.swift`.

### Phase 6 — current docs and live acceptance

Update:

- `docs-ai/013-prowl-cli/contracts/create.md` for warning shape, omission, and output-channel
  behavior;
- `docs-ai/013-prowl-cli/contracts/agents-signal.md`;
- `docs/components/agent-detection.md`;
- `docs/components/cli.md`;
- `docs/components/agent-profiles.md` as needed;
- `skills/prowl-cli/SKILL.md` only where orchestration guidance changes;
- 064 plan/research/action records with verified runtime versions and behavior.

Live isolated Debug gates use a custom socket and freshly embedded CLI:

Claude:

1. Scratch existing user/project hook plus Prowl CLI settings both fire exactly once; live
   settings files remain unchanged.
2. Inline and file-backed explicit Profile `--settings` each preserve unknown fields and
   existing hook arrays while the existing hook and Prowl handler fire exactly once; a malformed
   explicit source launches unchanged with one warning and no exact coverage.
3. `SessionStart` produces `verified_live` coverage.
4. `Stop` resolves generic idle wait with `source=hook_claude`.
5. A harmless permission request produces `needs-input` before user response.
6. Dispatch completion receipt still wins over the adjacent Stop hook.
7. Fresh workspace trust never creates false coverage before acceptance; a later valid event
   recovers.

Codex:

1. A clean scratch home with no notifier injects Prowl directly, creates no forwarding record,
   and `agent-turn-complete` resolves with `source=hook_codex` and no trust-bypass flag.
2. Internal memories cwd is ignored.
3. Existing base, selected-profile, and explicit CLI-override notifiers each receive the exact
   original payload once while Prowl also records the hook once.
4. User notifier exit failure cannot alter Codex or Prowl evidence; resolver failure preserves
   the original notifier and omits exact Prowl coverage.
5. Notifier argv containing secret-like values appears only in the private `0600` session
   record—not logs, preview, terminal input/environment, durable registration, or public CLI
   output—and the record is deleted with its launch.
6. A manually launched Codex remains honestly heuristic/cooperative.

Both:

- bundled absolute CLI works with `/usr/local/bin/prowl` unavailable;
- custom socket/token survives the native hook environment;
- invalid token, listener loss, and helper failure never alter runtime behavior;
- created test resources and isolated app/socket state are removed afterward.

Repository gates:

```bash
make build-cli
make test-cli-smoke
make test-cli-integration
make check
make test
make build-app
```

## Acceptance invariants

- Only an app-issued, live launch registration plus exact caller-pane ancestry can produce
  `source=hook` / `verified_live`; `--origin` and `PROWL_PANE_ID` never can.
- Native hook signals are observation evidence only; dispatch/workflow completion remains a
  separate explicit protocol.
- One Profile launch owns one evidence epoch shared by hook registration and optional dispatch.
- No hook configuration is written to user global settings, dedicated homes, or repositories.
- Hook failure is fail-open for the runtime and fail-closed for trust/verification.
- Unverified coverage never suppresses heuristic `auto` fallback.
- The base Profile and preview remain deterministic; execution tokens are memory-only and
  surface-scoped.
- No token, user environment value, full assistant result, credential, notifier argv, or
  provider config is logged or durably persisted by Prowl. The sole notifier-argv exception is
  the owner-only ephemeral forwarding record required for transport-independent chaining.
- A process-scoped Codex `notify` override is legal only while the displaced effective user
  notifier has a validated private forwarding record; uncertain resolution or record setup
  preserves the user's launch and forfeits the managed hook.

## Resolved owner decisions

### 1. Codex `notify` ownership — resolved 2026-08-23

Codex exposes one legacy `notify: array<string>` command rather than an additive notifier list.
The owner accepted transparent dispatcher semantics:

- resolve the notifier that the unmodified Prowl Agent Profile launch would execute;
- inject Prowl's process-scoped notifier only after preparing exact, once-per-event forwarding
  of the unchanged Codex payload;
- if resolution is uncertain, preserve the user's launch, omit Prowl's managed Codex hook, and
  expose no `verified_live` coverage;
- never rewrite user config, place notifier argv in a terminal carrier, durably persist/log
  returned config, or pass hook trust bypass.

### 2. Codex launch-degradation disclosure — resolved 2026-08-23

The owner accepted a successful launch plus one explicit warning:

- GUI launch shows one non-blocking warning toast;
- CLI launch remains successful and adds optional
  `warnings: [{code: "managed_hook_degraded", runtime, message}]` to
  `prowl.cli.create.v1`; JSON retains it in stdout and text renders it once to stderr;
- no persistent degraded state or repeated toast is added before S3c's exact-channel badge;
- S2 dispatch receipts and runtime behavior remain unchanged.

The supported worst case is bounded launch-preflight latency followed by the whole session
falling back to pre-S3 heuristic/cooperative observation. Generic wait may become less precise
or time out, but the user notifier, Codex process, config, and S2 receipt path remain intact;
degradation must never create false exact evidence.

### 3. Codex forwarding durability — resolved 2026-08-23

The owner accepted the recommended private session-record tradeoff so user forwarding does not
depend on a live Prowl socket response:

- random Prowl runtime directory `0700`, forwarding record `0600`;
- opaque child-only locator; notifier argv never enters command text, shell history, environment,
  logs, or durable settings/state;
- bridge attempts Prowl delivery, scrubs internal variables, then `exec`s the original notifier
  regardless of Prowl transport outcome;
- immediate trust revocation plus shared-read/exclusive-cleanup leasing, a bounded retirement
  grace, and startup/age-bounded orphan cleanup;
- the bridge opens, leases, and reads before transport, so transport rejection and concurrent
  lifecycle cleanup cannot suppress forwarding;
- any inability to prepare this boundary degrades before override injection.

## Residual risks

- Claude workspace trust can indefinitely delay every hook; fallback must remain honest.
- Codex legacy `notify` may be deprecated in favor of native hooks; keep its resolver,
  renderer, decoder, and dispatcher isolated behind the adapter capability.
- `app-server config/read` adds bounded launch-preparation latency and may drift independently
  of `codex` runtime flags; pin fixtures, time out safely, and preserve the user launch on any
  mismatch. Local scratch measurements were 24 ms warm median and 210 ms cold, so use a 1-second
  hard timeout rather than an unbounded launch stall.
- Forwarding records temporarily hold sensitive argv. Enforce owner-only creation, refuse
  symlinks/non-regular files or permission drift, never print contents, and test every cleanup
  edge plus stale-orphan collection.
- Third-party payloads and flag semantics can drift. Fixture tests pin supported shapes, while
  live gates record the exact shipping versions.
- Early-event buffering and dispatch epoch adoption touch S2 correctness boundaries; focused
  lifecycle tests and full dispatch regression gates are mandatory before merge.
