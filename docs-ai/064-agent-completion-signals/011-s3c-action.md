# 064.011 — S3c Pi/OMP/OpenCode Managed Hooks: Action

## Status

Implemented in [#728](https://github.com/onevcat/Prowl/pull/728) from `feat/agent-signal-hooks-s3c`.
Plan: [010-s3c-plan.md](010-s3c-plan.md). With this PR merged, S3 wave 1 — launch-scoped hooks for
all eight tier-A runtimes — is complete.

## Delivered behavior

- `AgentNativeHookRuntime` gains `pi`, `omp`, and `opencode` (raw values equal to
  `AgentProfileRuntime`); the public CLI sources are `hook_pi`, `hook_omp`, and `hook_opencode`.
- `AgentNativeHookDecoder.nativeEvents(for:)` is now the single source of every runtime's hook
  table: the decoder validates against it and each adapter's `signalHooks` declares it, so a
  registered event is always one the bridge can decode. The relayed runtimes decode through the
  existing Claude-shaped path with their native event names:
  - Pi: `session_start`, `agent_settled` (`turn-ended`), `session_shutdown`.
  - Oh My Pi: `session_start` and `session_switch` (session-start), `session_stop`
    (`turn-ended`), `tool_approval_requested` (`needs-input`), `session_shutdown`.
  - OpenCode: `session.idle` (`turn-ended`), `permission.asked` and `question.asked`
    (`needs-input`); no session-start, so it is non-announcing like Codex.
- Three bundled extensions in `Resources/agent-hooks/{pi,omp,opencode}/prowl-hooks.ts` (the
  existing folder reference picks them up). Each is a dumb relay: it forwards only its listed
  events to `prowl agents _hook <runtime> <event>` with `hook_event_name`, `session_id`, `cwd`,
  and an optional `reason`, resolves the CLI relative to itself, skips silently without a launch
  token, and swallows every failure. The OpenCode plugin additionally remembers sub-agent
  sessions from `session.created.info.parentID` and drops their events.
- Injection in `ManagedHookRendering.swift` / `AgentManagedHookPreparer.swift`:
  - **Pi / Oh My Pi** — `ExtensionFlagHookRenderer` inserts `-e` / `--hook` with a carrier value
    before the prompt positional; additive, so user extensions and `--no-extensions` are untouched.
    Oh My Pi's `--cwd` (last wins) is registered as the launch directory. A missing bundled file
    degrades before launch, because Pi refuses to start on a missing `-e` path.
  - **OpenCode** — `OpenCodeHookPluginPreparer` appends the plugin's `file://` URL to the
    `plugin` list of the effective `OPENCODE_CONFIG_CONTENT` (Profile override, else the login
    shell via the new `ShellEnvironmentProbe`), preserving every other key. The merged JSON is
    delivered launch-scoped through a new `environmentValues` carrier on
    `AgentHookPreparedInvocation` → `PROWL_LAUNCH_HOOK_ENV_n` → `OPENCODE_CONFIG_CONTENT="$…"`
    in `commandEnvironmentTokens`, appended after any Profile override so `env(1)` lets the merged
    content win. Degrades on `--pure`, `OPENCODE_PURE` (set unless `0`/`false`; empty counts),
    malformed content, an ambiguous project positional, or a probe that cannot run. `--auto`
    removes `permission.asked` from that launch's registered table.
    `OpenCodeLaunchDirectory` reads the TUI's `[project]` positional and `run --dir`.
- `ShellEnvironmentProbe` resolves several variables in one login-shell spawn, keeps "set but
  empty" apart from "unset", and survives multi-line values; `DroidSettingsEnvironmentProbe` now
  delegates to it.
- `OpenCodeSessionStore` filters `parent_id IS NULL`, so the detector never moves to a sub-agent
  session (which, for a non-announcing runtime, would have retired the hook session permanently).
- Docs: `agent-detection.md`, `agent-profiles.md`, `cli.md`, the `agents-signal` contract, the
  `prowl-cli` skill, `cli-output-schema.json`, and the research matrix rows.

## Verification

Repository gates on the branch: `make check` (35 script tests), `make build-cli`,
`make test-cli-integration` (97 tests), `make build-app`, focused `xcodebuild test` over the hook
suites, and `make test` (recorded below).

Focused coverage lives in `supacodeTests/AgentS3cHookPayloadTests.swift` (tables, adapter/decoder
agreement, relayed envelope decoding, excluded events, raw-value round trips),
`AgentS3cHookRenderingTests.swift` (flag insertion and additivity, missing-resource degradation,
OMP `--cwd`, OpenCode content merge / `--pure` / `OPENCODE_PURE` / directory scan / override vs
shell precedence / `--auto` trimming, the real `/bin/sh` probe), `AgentProfileHookCarrierTests`
(environment carriers never reach the typed command; override ordering), `AgentObservationTests`
(OMP `session_switch` rotation with delayed-event rejection and idempotent sub-agent
`session_start`; OpenCode non-announcing verification and rotation),
`AgentSessionProfileTests` (sub-agent rows excluded), and `AgentsCommandParsingTests` (stdin relay
for the three runtimes).

### Live acceptance

Run in an isolated Debug instance (`CFFIXED_USER_HOME`, dedicated `PROWL_CLI_SOCKET`, scratch
repository, real agent credentials in the pane shell) with `caffeinate -d -u` keeping the display
awake — see "Display sleep" below. Each Profile: `create tab --profile` → answer any trust/setup
prompt → one prompt → `agents wait --until idle` → `agents --json`.

| Check | Result |
| --- | --- |
| Pi 0.84.3 reaches `verified_live` with `source=hook_pi`; `turn-ended` resolves the wait, `binding=current` | PASS |
| Oh My Pi 18.0.6 reaches `verified_live` with `source=hook_omp`; `turn-ended` resolves the wait | PASS |
| OpenCode 1.18.23 reaches `verified_live` with `source=hook_opencode` from the first `session.idle` | PASS |
| OMP approval prompt: `agents wait --until blocked` resolves with `source=hook_omp` while the Approve/Deny dialog is on screen; Enter → `turn-ended` on the same channel | PASS |
| OpenCode question tool: `wait --until blocked` resolves with `source=hook_opencode` while the options dialog is on screen; Enter → `turn-ended` | PASS |
| Pi `/new`: channel rotates to the new session id and stays `verified_live` | PASS |
| OMP `/new` (`session_switch`): channel rotates to the new session id and stays `verified_live` | PASS |
| OpenCode sub-agent turn: the wait resolves (15 s, `hook_opencode`) only with the parent's `DONE` on screen | PASS |
| OMP sub-agent turn: the `task` approval reports `needs-input` on `hook_omp`; after approval the wait resolves (26 s) on the parent's `session_stop` with `DONE` on screen | PASS (after the sub-agent fix below) |
| Claude 2.1.245 / Codex 0.149.1 / Copilot 1.0.80 / Droid 0.203.0 / Qoder 1.1.29 regression on the same build: `verified_live`, `turn-ended`, `binding=current` | PASS ×5 |

### Oh My Pi sub-agents have their own session ids

The first OMP sub-agent run failed: `agents wait --until idle` never resolved and the app log
showed `managed hook rejected omp/session_stop reason=retired-session`. The plan had recorded
sub-agents as sharing the parent's session id — a misread of UUIDv7 ids whose time prefix
matches. In fact each in-process `task` sub-agent starts its own session (file nested inside the
parent's session directory and named after the agent, `<ts>_<parent>/PongResponder.jsonl`,
even `PongResponder.ExactPong.jsonl` one level deeper) and fires its own `session_start`, so the
relay announced a rotation, the store retired the main session, and the parent's real
`session_stop` was rejected. Two attempts preceded the final rule. A file-name test
(`<timestamp>_<uuid>.jsonl` = main) dropped every event of a Pi session started with a custom
`--session-id`, which review caught. A stateful rule ("the first announcer, or a UI context's
re-announcement, is the main session") passed its harness and failed live: the runtime loads a
**fresh extension instance for every sub-agent session** (measured — distinct module instances
sharing one `globalThis`), so the sub-agent's instance saw its own `session_start` as the first.
The final rule is stateless and structural: a sub-agent's session file is nested inside the
parent's session directory (`<timestamp>_<parent>/<Agent>.jsonl`, deeper for nested sub-agents),
so a session whose file has a session-directory ancestor is a sub-agent and that directory names
the pane's session id — the id itself is never interpreted. Its `session_start` /
`session_shutdown` are dropped while its `tool_approval_requested` — which still blocks the user
— is forwarded under the pane's session. Pi carries the same guard, and
`scripts/test_agent_hooks.py` runs the real extensions through Node against a capture CLI
(custom ids, nested and doubly nested files, ephemeral sessions, `/new`, OMP `session_switch`,
sub-agent approvals, OpenCode `parentID` filtering, no-token silence). Re-verified live: the
approval reported `needs-input` on the pane's session and the wait resolved on the parent's
`session_stop`.

### Review fixes

- OpenCode's TUI `--replay-limit <N>` was missing from the value-option table, so `7` would
  have been registered as the project directory and every hook rejected on the cwd guard with
  no warning. The table now matches the 1.18.23 `--help`, and — because OpenCode refuses to
  start in a directory that does not exist — a positional that is not an existing directory is
  treated as the value of an unknown option and the launch directory stays inherited.
- `ShellEnvironmentProbe` declared a 256 KiB bound but ran the Codex probe process at its 16 KiB
  default, so a ~20 KiB exported `OPENCODE_CONFIG_CONTENT` degraded the launch. The process
  bound now follows the probe's; covered at the process level and through the production runner.
- The relays spawned one bridge process per event without waiting, so adjacent lifecycle events
  (Pi's `agent_settled` and `session_shutdown` are milliseconds apart at exit; a `/new` is a
  `session_shutdown` immediately followed by a `session_start`) could reach Prowl out of order,
  where a late session start clears the terminal evidence a wait relies on. The native-hook
  runtimes run their hook commands sequentially; the extensions now do the same per instance —
  a promise queue starts the next bridge only after the previous one closed, the runtime callback
  never waits on it, and a bridge that hangs is killed after 5 s so later events keep flowing.
  The Node harness fires every step back to back and asserts strict order, including a 36-event
  burst. `make test-scripts` now runs in CI alongside the other test tasks.
- A per-instance queue still raced across instances: Pi's `/reload` has the old instance report
  `session_shutdown{reason:"reload"}` and, 4 ms later, a fresh instance report
  `session_start{reason:"reload"}` for the same session id (measured), so a late shutdown could
  become the live session's exact `session-end` and complete `agents wait --until exit` while
  the runtime is alive. Two changes: reload-reason lifecycle events are not forwarded at all (the
  session neither ends nor changes; OMP has no `/reload` — the text is treated as input), and the
  delivery queue now lives on `globalThis`, which every module instance in the process shares
  (measured), so sub-agent instances and reloads keep one order. The harness loads extra
  instances through a cache-busting import and pins both the reload sequence and cross-instance
  ordering; both tests fail against the previous relay.

### Display sleep is the CREATE_FAILED behind the "intermittent" Profile launches

The first sweep failed every Profile launch of every runtime with `CREATE_FAILED` ("The terminal
surface for Agent Profile … could not be created") while plain `create tab` kept working — the
symptom S3b recorded as an intermittent obstruction. The unified log names the cause:
`CVDisplayLinkCreateWithCGDisplays error -6661 due to invalid display count (0)` followed by
`com.mitchellh.ghostty:embedded_window: error initializing surface err=error.OutOfMemory`. The
Mac's display had turned off (`pmset -g log`: "Display is turned off" at 18:59); the deferred
Ghostty surface (`armSurfaceCreation`) cannot initialize without an active display, so
`WorktreeTerminalState.launchAgentProfile` returns `.surfaceCreationFailed`. Waking the display
(`caffeinate -u`) made the same launch succeed immediately. The same cause explains the flaky
`deferredProfileAppliesFontSizeAdjustmentAfterSurfaceCreation()` test, which arms a real deferred
surface: the first full `make test` on this branch failed exactly that test at 19:58, ten seconds
after the display turned off again, and it passes with the display awake. Not an S3c defect and
not fixed here; it is a candidate issue (retry arming once a display is available, or fall back
to immediate creation for CLI-driven launches) and a runbook rule for every future live sweep
and full test run on this machine (`caffeinate -d -u`).

## Open questions

- Drift protection ([#726](https://github.com/onevcat/Prowl/issues/726)) can now be designed
  against all eight runtimes.
- Display-sleep surface creation (above) deserves its own issue.
- Resuming a session that an earlier rotation retired stays outside the exact channel for
  OpenCode (documented, honest heuristic fallback).

## Refs

- Slice: 064-S3c
- Branch: `feat/agent-signal-hooks-s3c`
- Follows: [009-s3b-action.md](009-s3b-action.md)
