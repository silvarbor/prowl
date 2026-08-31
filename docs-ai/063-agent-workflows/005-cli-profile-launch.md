# 063.005 — Profile Launch Boundary and CLI (A2)

## Context

Release R1 already had deterministic anchored split creation (A1) and per-pane identity (A1b), but Agent Profile launches still depended on mutable focused placement, returned only an optional pane UUID, and always used an interactive start. CLI orchestration could create shells but could not resolve Profiles, seed a runtime-specific prompt, preserve background selection, or synchronously capture the launched tab and pane. The future 064-S3 hook work also needed one launch-scoped invocation/environment seam rather than a second terminal path.

## Change

- `AgentProfileLaunchPlanner.plan(for:intent:homeBaseDirectory:)` now forwards `.interactive` (default), `.prompt`, or `.headless` to the runtime adapter; Amp continues to reject interactive seeded prompts in its adapter.
- `AgentProfileLaunchRequest` carries the compiled plan, per-launch tab/split placement, explicit split anchor, direction, background behavior, working-directory override, and title. `WorktreeTerminalState.launchAgentProfile(_:)` returns `Result<LaunchedSurface, AgentProfileLaunchError>` with exact tab and pane identities.
- Explicit split requests use A1's anchored primitive and never fall back to a tab. The existing plan-only state method and `TerminalClient.Command.launchAgentProfile` remain compatibility wrappers: menu/palette launches retain split-to-tab fallback and `agentProfileLaunched` / `agentProfileLaunchFailed` events.
- `TerminalClient` adds a synchronous result-returning Profile launch closure. The CLI provider plans once, launches through the same terminal boundary, and resolves the returned pane without using focus as targeting input.
- `prowl create tab|pane` accepts `--profile <name|uuid>`, the stdin-only `--prompt -`, and Profile-only `--background`. Enabled Profile lookup is UUID first, then exact unique name; disabled Profiles are not launchable. `prowl.cli.create.v1` adds optional `launch { profile_id, profile_name, agent }`.
- `prowl profiles list` returns every persisted Profile in Settings order under `prowl.cli.profiles.v1`, including `enabled`, runtime, and shell-probe-only availability (`available` / `unavailable` / `unknown`). Runtime-home heuristics remain internal to UI warnings and one-time seeding.
- Parser, wire types, handlers, executable schema, contracts, manual, Agent Profiles guide, and bundled `prowl-cli` skill ship together. The skill includes the explicit reviewer-beside-self recipe and captures `.data.target.pane.id`.

## Decisions

- Background is explicit for both placements. A background tab preserves the selected worktree/tab/pane; a background split inserts beside the resolved anchor with `focusing: false` and never selects a hidden anchor's worktree or tab.
- Foreground pane launch resolves and splits the anchor before changing UI selection. `anchor` in the response remains the pre-split snapshot.
- Availability is advisory and never blocks launch. The CLI contract exposes only login-shell probe truth; the default-home existence heuristic is not reliable enough for automation.
- Disabled Profiles remain discoverable but do not participate in name uniqueness and cannot launch. A matching disabled UUID returns `PROFILE_NOT_FOUND` with an explicit message.
- CLI/workflow launches use the synchronous closure and do not emit the menu/palette recommendation-memory events. The adapter-rendered invocation and surface environment inside the compiled plan remain the clean 064-S3 seam; A2 injects no hooks.

## Review hardening

- A post-implementation review identified that Ghostty writes `initial_input` before the interactive shell enters raw mode. macOS canonical PTYs cap one line at `TTYHOG` (1024 bytes), so a literal prompted invocation could lose its closing quote/newline and stall at `quote>`. Prompted Profile plans now carry the verbatim prompt in reserved `PROWL_LAUNCH_PROMPT` surface environment and render only a variable reference into a short `env -u` command. The form uses no assignment statement or shell builtin, so it runs unchanged in zsh, bash, and fish; the Profile process does not inherit the carrier, while the pane shell retains it. NUL and UTF-8 input over 256 KiB are rejected before surface creation.
- CLI Profile launch providers now return a typed failure. Unsupported prompted starts map to `INVALID_ARGUMENT`; planning, provisioning, split, insertion, and resolution failures retain actionable messages under `CREATE_FAILED`.
- `--prompt -` rejects interactive stdin before reading. The CLI requires launch metadata, so a released older app cannot silently return an ordinary shell. Mismatch errors warn that the older app may already have created a resource and direct callers to inspect `prowl list` and close it. A proposed delivery-protocol field was removed before merge because it defended only unpublished intermediate commits while permanently exposing an implementation detail.
- Manager-level coverage now uses visible and hidden worktrees to prove a background split preserves worktree, tab, and pane selection. Router coverage includes `profiles`, and the manual scopes recommendation memory/toasts to Toolbar and Command Palette launches.
- `profiles list` intentionally remains a non-blocking cache snapshot. It does not trigger a shell probe; negative-result TTL and refresh ownership are unchanged.

## Verification

- TDD RED runs failed on the absent planner intent, launch request/result, CLI flags/wire fields, Profile lookup, profiles command, executable schema, prompt carrier and cross-shell rendering, typed launch failures, TTY and size guards, and launch version-skew validation; the corresponding focused suites were then driven GREEN.
- Focused app suites (`WorktreeTerminalStateAgentProfileTests`, `WorktreeTerminalManagerTests`, `AgentProfileTests`, `AgentRuntimeAdapterTests`, `CLILifecycleCommandHandlerTests`, `CLIProfilesCommandHandlerTests`, `CLICommandRouterTests`): 133 tests passed.
- `make check`, `make build-cli`, `make test-cli-smoke`, and `make test-cli-integration` passed; integration verified 85 socket/schema tests.
- `make build-app` passed with zero errors and warnings.
- Live isolated Debug verification used a dedicated `PROWL_CLI_SOCKET` and the repository CLI. A real Claude Profile received distinct kickoff prompts in an anchored right split and a background tab; `agents --json` identified both returned panes, `read --wait-stable` observed `PROWL_A2_SPLIT_OK` / `PROWL_A2_BACKGROUND_OK`, and the background target remained `selected: false`, `focused: false`. A second regression launch delivered a 2534-byte prompt containing a tab, observed `PROWL_A2_LONG_PROMPT_OK` with no `quote>` continuation, and remained in a background tab. A 256 KiB + 1 byte CLI prompt returned `INVALID_ARGUMENT` without changing the surface count. After the fish portability correction, the final Debug build repeated a long tab-containing background launch, observed `PROWL_A2_PORTABLE_OK` with no `quote>`, and returned only the stable launch metadata. Every created resource was closed and each isolated Debug process was terminated.

## Refs

- Slice: 063-A2
- Branch: `feat/cli-profile-launch`
- PR: #714
- Follows: [003-cli-create-pane.md](003-cli-create-pane.md), [004-pane-identity-env.md](004-pane-identity-env.md)
