# 064.008 — S3b Copilot/Droid/Qoder Managed Hooks: Plan

## Status

Delivered (see [009-s3b-action.md](009-s3b-action.md)). Branch `feat/agent-signal-hooks-s3b`, extending the S3a foundation delivered in
[#721](https://github.com/onevcat/Prowl/pull/721) and hardened in
[#723](https://github.com/onevcat/Prowl/pull/723). Slice definition lives in
[006-s3-wave1-plan.md](006-s3-wave1-plan.md); S3 wave 1 completes only after S3c.

S3b adds no new signal path, launch path, or trust model. It teaches three more tier-A
runtimes to feed the existing S1/S2 bus through the S3a registration boundary.

## Runtime baseline (re-attested 2026-08-25)

| Runtime | Version | Hook injection | Repeated flag | cwd flag | Prowl writes to disk? |
| --- | --- | --- | --- | --- | --- |
| Copilot CLI | 1.0.80 | `--plugin-dir <dir>` (`plugin.json` + `hooks.json`) | **additive** — every dir loads | `-C`, last wins | no (dir ships in the bundle) |
| Factory Droid | 0.202.0 | `--settings <path>` (path only) | last wins | `--cwd`, last wins | yes (settings file) |
| Qoder CLI | 1.1.29 | `--settings <inline JSON \| path>` | **first wins** | `--cwd` / `-w`, **first wins** | no (inline carrier) |

Claude Code is now 2.1.243 (S3a attested 2.1.241) and Codex CLI remains 0.149.0; S3b re-ran
the Claude permission matrix below against 2.1.243 and found no S3a regression.

Droid also honors `FACTORY_RUNTIME_SETTINGS_PATH`, and an explicit `--settings` flag beats it.
S3b injects through the flag, so when the user relies on that variable instead, the flag would
override it. The preparer therefore reads the variable — from a Profile environment override, or
from the login shell (rc sourced) via `DroidSettingsEnvironmentProbe`, reusing Codex's shell probe
process — and merges its settings as the base (flag wins; a probe that cannot run degrades rather
than override). Qoder's
`--setting-sources` (any value) suppresses flag-supplied hooks entirely — verified by hooks
never firing — so its presence forces degradation instead of a silently dead channel.

## `PermissionRequest` is not "needs input" (measured)

The Claude-shaped payload tempts a uniform `PermissionRequest -> needs-input` mapping, which
S3a legitimately uses. Direct measurement shows the event means different things per runtime:
Claude fires it only when it is about to ask a human, while Copilot and Qoder fire it whenever
a tool enters the permission service — including when that service auto-approves and nobody is
waiting. Every row below was observed locally, not read from docs.

| Runtime | Scenario | `PermissionRequest` | Real prompt on screen | Verdict |
| --- | --- | --- | --- | --- |
| Claude 2.1.243 | headless default + read-only tool | no | no | |
| | headless default + write (permission-denied) | no | no | |
| | headless `--allowedTools Bash` + bash | no | no | |
| | headless `acceptEdits` + write | no | no | |
| | headless `--dangerously-skip-permissions` + bash | no | no | |
| | **interactive `--allowedTools Bash`, bash auto-allowed and executed** | **no** | no | **safe** |
| | interactive default + approval-gated `touch` | yes | yes | correct |
| Copilot 1.0.80 | **headless `--allow-all-tools` + bash** | **yes** | no | **false positive** |
| | headless default + auto-allowed bash (`ls`) | yes | no | false positive |
| | headless default + read-only tool | no | no | |
| | interactive default + approval-gated `touch` | yes | yes | correct |
| Qoder 1.1.29 | **headless `accept_edits` + write (auto-approved, replied DONE)** | **yes** | no | **false positive** |
| | headless `--allowed-tools Bash` / `skip-permissions` / read-only | no | no | |
| | interactive default + approval-gated `touch` | yes (×2) | yes | correct |
| Droid 0.202.0 | no such event (`Notification` / `PreToolUse` only) | — | — | safe |

Consequences:

- **S3a needs no correction.** Claude's mapping stayed silent through six non-interactive
  scenarios, including a tool that was auto-allowed and actually executed.
- **Copilot and Qoder must exclude `PermissionRequest`** and derive `needs-input` from
  `Notification` alone, matched to `permission_prompt` / `elicitation_dialog`.
- Claude's `PermissionRequest` arrived ~6 s before its `Notification`, so S3a's dual mapping
  buys latency that Copilot/Qoder cannot have. Their `needs-input` is correspondingly later;
  accuracy wins because `agents wait` is a long wait, not a poll.

## Event mapping

| Runtime | session-start | turn-ended | needs-input | session-end |
| --- | --- | --- | --- | --- |
| Copilot | `SessionStart` | `Stop` | `Notification` (`permission_prompt` \| `elicitation_dialog`) | `SessionEnd` |
| Droid | `SessionStart` | `Stop` | same | `SessionEnd` |
| Qoder | `SessionStart` | `Stop`, `StopFailure` | same | `SessionEnd` |

Deliberately excluded: `PermissionRequest` (all three, per the matrix above); Copilot
`subagentStop` (a subagent finishing is not the main turn ending) and `errorOccurred`
(`SessionEnd(reason: error)` already terminates the wait); `idle_prompt` and `auth_success`
(waiting for a human is not the same as needing one — Droid was observed emitting no
`idle_prompt` for 100 s after `Stop`).

## Payload shape asymmetry

Copilot hooks must be configured with **PascalCase** event names to receive the VS Code
compatible payload (`hook_event_name` / `session_id` / `cwd`), which is the same shape S3a
already decodes; camelCase config yields a different field set and is not used. That
conversion is not total, and the exception lands exactly on the one event S3b depends on:

| Runtime | `SessionStart` / `Stop` / `SessionEnd` | `Notification` |
| --- | --- | --- |
| Copilot | `session_id`, `hook_event_name` | `hook_event_name` but **`sessionId`** (camelCase) |
| Droid | `session_id`, `hook_event_name` | documented common fields (`session_id`); confirm in the live gate |
| Qoder | `session_id`, `hook_event_name` | `session_id`, `hook_event_name` (measured) |

Copilot's `PermissionRequest` is fully camelCase and carries no `hook_event_name` at all, which
is moot because it is excluded. But `Notification` is Copilot's *only* `needs-input` source, so a
decoder that insists on `session_id` would reject it and silently drop the capability. The shared
Claude-shaped decoder therefore resolves the session id as `session_id` first, then `sessionId`,
rather than betting on one spelling per runtime.

## Injection design per runtime

- **Copilot** — a static plugin directory ships inside the app bundle (new
  `Resources/agent-hooks/copilot/`, checked in, added as an Xcode folder reference next to the
  existing `Resources/prowl-cli` reference; no Makefile target needed). The launch appends
  `--plugin-dir <abs>`. Because plugin dirs are additive, a user's own `--plugin-dir` and
  `~/.copilot/hooks/*.json` keep working with no merge — verified by running a user-level hook
  and the Prowl plugin together and seeing both fire. Hook commands resolve the bundled CLI via
  `"$COPILOT_PLUGIN_ROOT/../../prowl-cli/prowl"`; a read-only, chmod-`a-w` plugin directory was
  verified to work, which is what a signed bundle provides.
- **Droid** — `--settings` accepts a path only, so a file is unavoidable. With no user
  `--settings`, Prowl writes a hooks-only file (no user data). With one, Prowl bounded-reads it
  through `StableOwnerFileReader`, merges only its own handlers, and writes the result to an
  owner-only `0600` file, because Droid settings may carry secrets such as
  `customModels[].apiKey`. Lifetime reuses `CodexForwardingRecordStore`'s `0700` directory,
  lease, retirement, and orphan-sweep machinery; the file must outlive launch since Droid can
  reload hooks mid-session.
- **Qoder** — `--settings` takes inline JSON, so the S3a argv carrier applies and nothing is
  written to disk. Since repeated `--settings` is *first*-wins, a merged object is inserted
  **before** any user-supplied one; inserting after would silently disable Prowl's hooks, and
  inserting an unmerged object before would silently disable the user's settings.

Degradation follows S3a exactly — the launch proceeds untouched and surfaces one
`managed_hook_degraded` warning — when the bundled plugin directory is missing (Copilot), a
user settings source is unreadable/malformed/oversized or the private file cannot be created
(Droid), or `--setting-sources` is present (Qoder).

## Shared layer

`AgentNativeHookRuntime` in `supacode/CLIService/Shared/AgentNativeHookPayload.swift` gains
`copilot`, `droid`, and `qoder`. Raw values must equal `AgentProfileRuntime`'s, because
`supacode/Features/Terminal/BusinessLogic/AgentObservationStore.swift` converts between them by
raw value — so Qoder's is `qodercli`, and the public source becomes `hook_qodercli`, matching
the agent name already shown by `prowl list`. All three payloads are Claude-shaped, so the
decoder core is shared and each runtime contributes only an event table plus a notification
allowlist. `ProwlCLIContracts/Resources/cli-output-schema.json` gains three additive `source`
values. Verification rules are inherited verbatim from Claude: the first valid event verifies
the channel, and only `SessionStart` may rotate a session.

## Owner decisions (grill session, 2026-08-25)

| Decision | Rationale |
| --- | --- |
| Copilot plugin ships statically in the bundle | Zero writes and no lifecycle; conditional on causing no user-config side effects, which was then verified (see below) |
| Droid merges a user `--settings` into a private `0600` file | Matches S3a's Claude merge; refusing to merge would make Droid the only runtime silently losing exact coverage |
| One PR covers all three runtimes | Shared decoder and verification rules; keeps the recorded S3a/S3b/S3c structure |
| No opt-out switch for managed hooks | Hooks are fail-open observation that never alter agent behavior; a switch would mostly generate "why is my wait imprecise" triage |

Side-effect verification for the Copilot decision: across the whole spike, `~/.copilot/config.json`
`trustedFolders`, `settings.json`, and the installed-plugin list were unchanged. The only trace is
an empty `~/.copilot/plugin-data/_direct/<hash>/` directory keyed by plugin path, and the plugin is
absent from `copilot plugin list` unless that same `--plugin-dir` is passed.

## Non-goals

Pi, OMP, and OpenCode adapters; the Active Agents exact-channel badge; complete tier-A docs
closure — all S3c. No opt-out setting, no change to dispatch receipts, `agents wait` semantics,
or the S3a trust model.

## Verification

Logic layers follow RED → GREEN: payload decoding per runtime, Copilot plugin-argv rendering,
Droid merge and private-file lifecycle, Qoder first-wins insertion and `--setting-sources`
degradation, and per-runtime cwd resolution including the repeated-flag asymmetry. Repository
gates are `make check`, `make test`, `make build-cli`, `make test-cli-smoke`,
`make test-cli-integration`, and `make build-app`. Live acceptance runs each runtime from an
Agent Profile in an isolated Debug instance with a dedicated `PROWL_CLI_SOCKET`, asserting
`verified_live` coverage, a `source=hook_*` turn-ended resolving a wait, a real permission prompt
producing `needs-input`, and that a manually typed runtime stays heuristic.
