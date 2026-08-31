# 064.010 — S3c Pi/OMP/OpenCode Managed Hooks: Plan

## Status

Implemented in [#728](https://github.com/onevcat/Prowl/pull/728) (record: [011-s3c-action.md](011-s3c-action.md)),
closing S3 wave 1 on top of the S3a foundation
([#721](https://github.com/onevcat/Prowl/pull/721), [#723](https://github.com/onevcat/Prowl/pull/723))
and the S3b adapters ([#725](https://github.com/onevcat/Prowl/pull/725)). Slice definition lives
in [006-s3-wave1-plan.md](006-s3-wave1-plan.md); S3 wave 1 is complete only when this PR passes
the full tier-A gate. Owner decisions were settled in a grill session on 2026-08-26 (below).

S3c adds no new signal path, launch path, or trust model. It teaches the last three tier-A
runtimes to feed the S1/S2 bus through the S3a registration boundary and closes the tier-A
documentation. The Active Agents "exact" badge that earlier documents attached to S3c is
**dropped without commitment** (owner decision); `prowl agents --json` `signals.channels`
remains the way to see exact coverage.

## Runtime baseline (re-attested 2026-08-26, this Mac)

All three were upgraded to their latest release before probing. Every row below was measured
with a probe extension in a scratch project; nothing in the user's configuration was modified.

| Runtime | Version | Hook injection | Repeated / discovery-off | Prowl writes to disk? |
| --- | --- | --- | --- | --- |
| Pi | 0.84.3 | `-e <file.ts>` (`--extension`) | additive; `--no-extensions` keeps explicit `-e` | no (file ships in the bundle) |
| Oh My Pi | 18.0.6 (from 17.2.7) | `--hook <file.ts>` or `-e` (identical) | additive; `--no-extensions` keeps explicit paths | no |
| OpenCode | 1.18.23 (from 1.18.11) | `OPENCODE_CONFIG_CONTENT='{"plugin":["file:///abs.ts"]}'` (env) | `plugin[]` **concatenates** across config layers; `--pure` / `OPENCODE_PURE=1` drop every external plugin | no |

Pi is Node (`#!/usr/bin/env node`; the TUI needs Node ≥ 22.15 for zstd — an older `~/.volta`
Node crashed it with `zlib.createZstdDecompress is not a function`, an environment fact, not a
hook fact). OMP and OpenCode are compiled Bun binaries. All three run
`node:child_process.spawn` from inside an extension, inherit the launch environment
(`process.env`), and load the extension from a read-only directory (`chmod -R a-w` verified),
which is what a signed bundle provides.

### Measured lifecycle

| Runtime | Startup | Per prompt | Rotation | Exit |
| --- | --- | --- | --- | --- |
| Pi | `session_start{reason:"startup"}` | `input` → `turn_start` → `agent_start` → `turn_end` → `agent_end` → **`agent_settled`** | `/new`: `session_before_switch` → `session_shutdown{reason:"new"}` → `session_start{reason:"new"}` with a new id | `session_shutdown{reason:"quit"}` |
| OMP | `session_start` | `input` → `agent_start` → `turn_start` → [`tool_approval_requested` → `tool_approval_resolved`] → `turn_end` … → `agent_end` / **`session_stop`** | `/new`: `session_before_switch` → **`session_switch`** (new id; no `session_start`) | `session_shutdown` |
| OpenCode | `plugin.loaded` only; **no session until the first prompt** | `session.created` → `session.status{busy}` → … → `session.status{idle}` + **`session.idle`** | `/new` and session resume emit **nothing** until the next prompt | none (process ends) |

Facts that shape the design:

- **Session ids match the detector.** Pi and OMP expose `ctx.sessionManager.getSessionId()`,
  the UUID in the session file name (`<ts>_<uuid>.jsonl`) that `AgentSessionProfile.uuidJSONL`
  already reports. OpenCode's `properties.sessionID` (`ses_…`) is the `opencode.db` row id.
- **Sub-agents.** OMP's `task` tool runs sub-agents in-process under **their own session
  ids** (UUIDv7, so only the prefix matches the parent's — an easy misread), with the session
  file nested inside the parent's session directory and named after the agent
  (`<ts>_<parent>/PongResponder.jsonl`, even `PongResponder.ExactPong.jsonl` one level deeper);
  their handlers see `ctx.hasUI == false` / `ctx.mode == "print"`. Each sub-agent fires its own
  `session_start` and `agent_end`; with one sub-agent, `agent_end` fired **three times** while
  `session_stop` fired once, at the real end — OMP documents `session_stop` as main-session
  only. Left unfiltered, a sub-agent's `session_start` reads as an announced rotation, retires
  the main session, and the parent's `session_stop` is then rejected (measured live in the first
  gate). OpenCode sub-agents are separate sessions too: `session.created` carries
  `info.parentID`, and the child's own `session.idle` fires **27 s before** the parent's.
- **Process shape.** Pi and OMP are single processes; the OpenCode TUI runs the plugin in the
  TUI process, and `opencode run` forks one engine child (argv0 `opencode`, title `bun`) that
  hosts it — covered by S3b's launch-process generation.
- **cwd form differs.** Pi and OpenCode report the resolved path (`/private/tmp/…`); OMP's
  `ctx.cwd` is the shell's logical path (`/tmp/…`). S3b's symlink-resolving cwd guard covers both.
- **Trust.** Pi loads CLI extensions before `project_trust` and reported `trusted: true` in a
  fresh scratch directory; OMP showed no trust gate; OpenCode has none.
- **Missing extension path.** Pi **refuses to start** (`Failed to load extension … Hint: Start
  without extensions using "pi -ne"`); OMP warns and continues; OpenCode ignores it. Prowl
  degrades *before* launch when the bundled file is missing, as it does for the Copilot plugin.
- **needs-input.** Pi has no permission system. OMP's built-in approval prompt emits
  `tool_approval_requested{sessionId, toolName, toolCallId, approvalMode}`; Prowl's OMP adapter
  always passes `--approval-mode` (`always-ask` unless the Profile is unrestricted). OpenCode
  emits `permission.asked{id, sessionID, permission, patterns, metadata, always, tool}` and
  `question.asked{id, sessionID, questions, tool}` exactly when a dialog is on screen, followed
  by `permission.replied` / `question.replied` and then `session.idle`. **Trap:** under `--auto`
  with a `permission: ask` config, `permission.asked` and `permission.replied{reply:"once"}` fire
  in the same millisecond with nobody waiting — the Copilot/Qoder false positive again. With
  the default (allow) config no `permission.asked` fires at all.
- **Visible footprint.** Pi lists loaded extensions by file name in its startup banner, so the
  bundled file is user-visible; it is named `prowl-hooks.ts` to match the Copilot plugin.
- **Headless stdin.** `omp --print` blocks in `readPipedInput` while stdin is open and not a TTY
  (a probe artifact — Prowl panes are ptys).

## Payload design: relay native events in the Claude-shaped envelope

S3a/S3b decode payloads the runtimes author. Here Prowl authors the extension, so the shape is a
choice. Decision (grill): the extension is a **dumb relay** — it forwards the runtime's own event
name in `hook_event_name` and fills the fields the shared Claude-shaped decoder already reads
(`session_id`, `cwd`, optional `reason`). Nothing new is invented on either side:

- `AgentNativeHookDecoder.decodeClaudeShaped` serves the three new runtimes unchanged, driven by
  a per-runtime event table exactly like Copilot/Droid/Qoder. `nativeEvents` keeps the true
  runtime event name, so `prowl agents --json` `signals.last.native_event` stays honest.
- The event → `AgentSignalEvent` mapping lives in Swift (`AgentRuntimeAdapter` + the decoder
  table), where it is unit-tested; the TypeScript files carry no mapping logic beyond "which
  events to forward", the sub-agent filters, and the fail-open transport.
- `AgentNativeHookRuntime` gains `pi`, `omp`, `opencode` (raw values equal to
  `AgentProfileRuntime`); the public sources are `hook_pi`, `hook_omp`, `hook_opencode`.
  Additive `cli-output-schema.json` entries.
- Transport is the existing hidden `prowl agents _hook <runtime> <event>` with bounded JSON on
  stdin; the token and socket come from the inherited launch environment
  (`PROWL_AGENT_HOOK_TOKEN`, `PROWL_CLI_SOCKET`), so the extension needs no configuration.

## Event mapping

| Runtime | session-start | turn-ended | needs-input | session-end |
| --- | --- | --- | --- | --- |
| Pi | `session_start` | `agent_settled` | — (no permission system) | `session_shutdown` |
| OMP | `session_start`, `session_switch` | `session_stop` | `tool_approval_requested` | `session_shutdown` |
| OpenCode | — (Codex-style, non-announcing) | `session.idle` | `permission.asked` (omitted from the launch table when `--auto` is present), `question.asked` | — |

Deliberately excluded: Pi/OMP `agent_start` / `turn_*` / `input` (intermediate); Pi `agent_end`
(precedes `agent_settled`, the documented idle point); OMP `agent_end` (fires per sub-agent;
its `willContinue` is undocumented and was `undefined` in every measurement) and
`tool_approval_resolved` (Prowl has no "unblocked" signal — the next turn-ended clears it, as for
every runtime); OpenCode `session.status` (duplicates `session.idle`), `session.error`
(`session.idle` follows it anyway), `session.updated`, `session.deleted` (a deleted session is
not the launched agent exiting), `permission.replied` / `question.replied`.

Why OpenCode is non-announcing: its session appears only at the first prompt and `/new` /
resume emit nothing, so declaring `session.created` as SessionStart would leave a resumed
session's events rejected forever. Codex's rules fit exactly — the first `session.idle`
verifies and delivers in one step, and an ordinary event with a new id rotates. The known
cost is that a session retired by an earlier rotation cannot be resumed on the exact channel
(honest heuristic fallback; documented).

Why OMP `session_switch` maps to session-start: OMP rotates with a single event carrying the new
id, so it is the announcing edge the store's rotation rule needs. Pi's
`session_start{reason:"reload"}` re-announces the current id, which is idempotent; `/resume`
re-announces a retired id, which S3b's resume rule reactivates.

Sub-agent protection for the Pi family lives in the extension and must be **stateless**: the
runtime loads a fresh extension instance for every sub-agent session (measured — distinct
module instances sharing one `globalThis`), so nothing learned from the main session's events is
visible where a sub-agent's events arrive. The structural fact that survives this is the file
layout: a main session file sits directly in its session directory as `<timestamp>_<id>.jsonl`
(the id is opaque — `--session-id` accepts any name), while a sub-agent's file is nested inside
the parent's session directory (`<timestamp>_<parent>/<Agent>.jsonl`, deeper again for a
sub-agent's sub-agent). A session whose file has a session-directory ancestor is a sub-agent,
and that directory names the pane's session id. A sub-agent's `session_start` /
`session_shutdown` are dropped; its `tool_approval_requested` — which still blocks the user —
is forwarded under the pane's session id. A session without a file (ephemeral) is treated as the
pane's. `scripts/test_agent_hooks.py` drives the real extensions through Node against a capture
CLI to pin these decisions.

Sub-agent protection for OpenCode (two layers, both required — measured above):

1. the extension remembers every `session.created` whose `info.parentID` is set and drops all
   events for those ids, because `session.idle` itself carries no parent information;
2. `OpenCodeSessionStore` filters `parent_id IS NULL` (the column exists), so the detector never
   moves to a child session — which, for a non-announcing runtime, would retire the hook session
   permanently.

## Injection design per runtime

- **Pi / OMP** — append `-e <bundle>/agent-hooks/pi/prowl-hooks.ts` (OMP: `--hook …/omp/prowl-hooks.ts`)
  to the argv. Both take the prompt as the last positional, so the option is inserted before it
  via the existing `insertionIndex(promptArgumentIndex:)`. Repeated flags are additive, so a
  user's own `-e` and discovered extensions keep working with no merge. Degrade (one
  `managed_hook_degraded` warning, launch unchanged) only when the bundled file is missing.
  Two files, each naming its runtime for `_hook`, rather than one file guessing the runtime from
  `process.title`.
- **OpenCode** — no argv change. `OPENCODE_CONFIG_CONTENT` is delivered **launch-scoped**
  through the existing `commandEnvironmentTokens` prefix (`VAR="$PROWL_LAUNCH_HOOK_ARG_n" opencode …`),
  the same mechanism S3a uses for the token and socket, so the JSON never enters the typed
  command and a later manual `opencode` in the same pane is unaffected. If the Profile already
  overrides `OPENCODE_CONFIG_CONTENT`, Prowl parses it and appends to its `plugin` array (other
  keys untouched); a shell-exported value is resolved through the login shell like Droid's
  `FACTORY_RUNTIME_SETTINGS_PATH` (Profile override > shell-resolved; probe failure degrades).
  Degrade when `--pure` is in the argv, `OPENCODE_PURE` is set (override or shell), or the
  existing content is not a JSON object. Because config layers concatenate `plugin[]`, project
  and global plugins are unaffected. `--auto` (the adapter's unrestricted mode) removes
  `permission.asked` from that launch's registered table, so an auto-approved permission cannot
  read as needs-input; `question.asked` stays.
- **Bundle resources** — `Resources/agent-hooks/{pi,omp,opencode}/prowl-hooks.ts`, registered
  like the Copilot folder reference; `AgentHookResources` grows the three paths and
  `SupacodePaths` the locators. Each file resolves the CLI relative to itself
  (`dirname(import.meta.url)/../../prowl-cli/prowl`), the layout the Copilot plugin uses.

Fail-open rules for the extension code: every handler is wrapped, the spawn uses
`stdio: ["pipe","ignore","ignore"]`, nothing is awaited on the runtime's path, no output is
written to the runtime's UI, and any failure to spawn is swallowed. A hook that cannot reach
Prowl changes nothing for the agent. Deliveries are serialized process-wide through a queue on
`globalThis` (the next bridge process starts only after the previous one closed, with a 5 s kill
bound) so adjacent events keep their order the way a runtime running hook commands sequentially
would — including across the fresh module instances Pi loads on `/reload` and the Pi family
loads per sub-agent session. Reload-reason `session_shutdown` / `session_start` are not
forwarded: the session continues under the same id.

## Docs and closure

- `docs/components/agent-detection.md` "Managed native completion signals": all eight tier-A
  runtimes, the new per-runtime enablement and `needs-input` rules, the OpenCode `--pure` /
  `--auto` caveats, the sub-agent filters.
- `docs/components/cli.md`, `docs-ai/013-prowl-cli/contracts/agents-signal.md`, and
  `cli-output-schema.json`: `hook_pi` / `hook_omp` / `hook_opencode`.
- `skills/prowl-cli/SKILL.md` only if orchestration guidance changes (expected: none).
- `research-agent-completion-signals.md` rows for the three runtimes (versions above, OMP's
  `session_switch` and sub-agent `agent_end`, OpenCode lazy session creation, `plugin[]`
  concatenation, `--auto` permission trap).
- `000-plan.md` (badge no longer promised), `006-s3-wave1-plan.md`, `release-plan.md`: S3b
  merged (#725); S3 wave 1 complete after this PR merges. Then design the drift guard in
  [#726](https://github.com/onevcat/Prowl/issues/726) against all eight runtimes.

## Non-goals

No Active Agents badge, no opt-out setting, no change to dispatch receipts or `agents wait`
semantics, no change to the S3a trust model, no OSC/transcript producers (S4), no runtime
outside tier A.

## Owner decisions (grill session, 2026-08-26)

| Decision | Outcome | Rationale |
| --- | --- | --- |
| Event names in the payload | native names, Claude-shaped fields | mapping in Swift where it is tested; `native_event` stays honest; the envelope is the one Copilot/Droid/Qoder already use |
| OMP turn-ended source | `session_stop` | measured: `agent_end` fires per sub-agent (3× for one sub-agent); `session_stop` is documented main-session only and fired once |
| OpenCode session model | Codex-style, non-announcing | sessions are lazy and resume is silent; announcing would kill the channel on resume |
| OpenCode env scope | launch-scoped via `commandEnvironmentTokens` | already how S3a passes the token/socket; nothing leaks into the pane |
| Active Agents exact badge | dropped, no commitment | owner decision; `agents --json` already exposes coverage |
| OpenCode `--auto` | drop `permission.asked` from the launch table | auto-approval replies in the same millisecond; same reasoning as Copilot/Qoder |

## Verification

Logic layers follow RED → GREEN: decoder tables per runtime; argv rendering for Pi/OMP
(prompt-index insertion, additivity, missing-resource degradation); OpenCode content merge
(absent / object / malformed / `--pure` / `OPENCODE_PURE`, override vs shell precedence,
`--auto` table trimming); store-level registration/verification/rotation for the three runtimes
(`session_switch` rotation, non-announcing OpenCode rotation and retired-session strictness);
`OpenCodeSessionStore` child-session exclusion. Repository gates: `make check`, `make test`,
`make build-cli`, `make test-cli-smoke`, `make test-cli-integration`, `make build-app`. Live
acceptance: the scripted isolated-instance sweep from S3b over all eight tier-A runtimes
(`create tab --profile` → trust → prompt → `agents wait --until idle` → `agents --json`), plus
one permission prompt each for OMP and OpenCode, one OpenCode sub-agent turn (no premature
idle), and `/new` rotation for Pi/OMP.
