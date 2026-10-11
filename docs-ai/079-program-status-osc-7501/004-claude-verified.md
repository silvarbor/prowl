# 079.004 — Claude Code verified (slice 3)

## Context

Slice 3 of [000-plan.md](000-plan.md): flip Claude Code to `.verified` so that the root
record Claude Code 2.1.295+ writes decides the pane state, the detection loop delegates
while it does, and the native registry and the screen rules become the fallback. The
plan's *Slice 3 — Claude Code verified* section is the normative spec; this record lists
what landed, what the gates showed, and the one limitation the review surfaced.

## Change

| Layer | Files | What |
| --- | --- | --- |
| Support table | `App/Sources/Domain/AgentDetection/ProgramStatusEvidence.swift` | `ProgramStatusSupport.level(for:)` returns `.verified` for `.claude`; every other agent stays `.unverified` (Pi flips in slice 4) |
| Tests | `App/Tests/AgentCoordinatorProgramStatusTests.swift`, `App/Tests/WorktreeTerminalStateProgramStatusTests.swift` | the production table is pinned at both levels (red before the flip, green after): the coordinator built with the default table delegates a Claude root and must not sample the native provider, while a Pi root keeps `legacy.detector`; the terminal owner built with the default table publishes a Claude push (`osc.working`, delegated schedule) and publishes nothing for a Pi push |
| Session identity (added 2026-10-11 after review finding 1) | `App/Sources/Infrastructure/AgentDetection/AgentPidArtifacts.swift` (`ClaudeSessionRegistry`), `ClaudeRuntimeDecoder.swift` (`sessionID(_:process:)`), `AgentSessionProfile.swift` | the Claude profile gains `pidKeyedSession` and `rootedPIDKeyedSession`: the registry's `sessionId` (`<root>/sessions/<pid>.json`, validated against the live pid and start second; the status fields are not consulted) is the pane's session with `process_log` / `exact`, and the transcript path is reported once the first prompt created it. The transcript scan and fingerprint stay the fallback for versions without the registry. `alphanumericDashed` became internal so the registry can derive the transcript path from the record's cwd |
| Session hold (round 4 finding 1) | `App/Sources/Infrastructure/AgentDetection/AgentSessionResolver.swift` | a pid-keyed lookup (Claude registry, Copilot log, Qwen sidecar, Grok rows) that named the process's session once is held through up to three consecutive uncached misses (`pidKeyedHoldMisses`), so a transient read failure keeps the exact identity instead of promoting a fingerprint guess that would rotate the evidence epoch; a removed artifact falls back to the scan at the fourth miss. The hold is the poll's policy only: a fresh read (`resolveFresh`, used by `agents read`) during a miss reports the frame's exact or high evidence or nothing, and neither consumes the hold's budget nor overwrites the held identity (round 5 finding) |
| Tests (session identity) | `App/Tests/ClaudeSessionRegistryTests.swift`, `App/Tests/ClaudeRuntimeProviderTests.swift` | the registry read with and without the transcript, stale claims from a reused pid and malformed or oversized records, the profile hooks under the home and under a relocated root, the rotation end to end through `AgentSessionResolver` with this test process as the agent (the rewrite shows once the 5 s result cache expires, with stale screen text), and the hold (registry removed with two scoreable transcripts and a stale frame matching the outgoing one: exact identity for three misses, the scan's `transcript_match` at the fourth, exact again once the registry is back), and a fresh read during the outage (the frame's `transcript_match` or nothing, with the poll's hold and budget intact); the decoder yields the identity for a status it does not know |
| Docs | `docs/components/agent-detection.md`, `docs-ai/068-agent-state-providers/architecture.md`, `claude.md` (new *Program status* section with the observed boundary table), `docs-ai/013-prowl-cli/contracts/agents.md`, [producer-baseline.md](producer-baseline.md) (the Claude "Verification inside Prowl" table and the harness rows for child records, `/clear`, and `/resume`), `000-plan.md` (boundary rows corrected from the observations) |

No other code changed: the push path, the delegated tick, the withdrawal fence, the
command-finished release, readiness, and the CLI surface are slice 2's (#893).

## Review

A read-only Pi Reviewer loop against the branch (brief: plan, 003, baseline, 068, 064.024,
the diff, and the code paths the flip activates). Round 1 returned three findings:

| # | Finding | Disposition |
| --- | --- | --- |
| 1 | A delegated tick hands the session resolver the screen text of the last full tick, so after a same-PID `/clear` or `/resume` the fingerprint matcher can keep selecting the outgoing session with high confidence until the next key press (no fresh miss ages it); the plan's "a few ticks longer" understated this | Accepted. First recorded as a known limitation; after onevcat's decision on 2026-10-11 it is fixed in this PR by taking the session from Claude's pid registry (see *Session identity under delegation*); the plan's `/clear` row and `068/claude.md` state the new behaviour |
| 2 | The table was flipped before the inside-Prowl acceptance record existed | Closed by this record and the baseline table; the gate runs are below |
| 3 | The manual described a finished command as an unconditional fallback and delegated work as "process only" | Accepted: `agent-detection.md` now says `clear` withdraws authority, a finished command wakes a probe that keeps the authority for the same owner and releases a confirmed exit, and delegated ticks probe the process and resolve the session |

Round 4 (2026-10-11, against the session identity commits) returned five findings, all
accepted: one code change and four documentation corrections.

| # | Finding | Disposition |
| --- | --- | --- |
| 1 | A transient registry read failure returned the same `nil` as "no registry", so the resolver fell through to the fingerprint and could promote the outgoing session at `high` confidence for 5 s — and a non-medium identity change rotates the evidence epoch and clears the hook channels and signals that waits and dispatch admission consume | Fixed: the resolver holds a pid-keyed exact identity through three consecutive uncached misses before the scan takes over (`pidKeyedHoldMisses`), with a resolver test for the hold, the fallback, and the recovery |
| 2 | The manual said the registry "is not read" while OSC decides, which now holds for the native state provider only, and stated a flat 5 s bound | Fixed in `agent-detection.md`: the provider does not sample the registry, the resolver still reads it for identity; the bound is the 5 s cache plus one delegated tick while the registry stays readable |
| 3 | "`/clear` was never affected" overstated the old scan: the fingerprint recovery needs a distinctive first prompt, and the quiet window before it showed the outgoing session on both paths | Fixed in *Session identity under delegation* |
| 4 | The impact statement ("only the roster") omitted that an exact or high session feeds the evidence epoch, so session-bound hook evidence (channels, signals, dispatch admission) changes with identity | Fixed in *Session identity under delegation* |
| 5 | The retained background-agent observation said Claude "does not end the turn", contradicting the harness account of a `Stop` hook before the wait | Fixed: the observation now says the root record stays `working` after the parent's `Stop` and `done` follows the auto-submitted result turn |

Round 5 (confirmation of the round 4 fixes) returned one finding, accepted: the hold also
applied to `resolveFresh`, so during a registry outage `agents read` could have reported the
held session (and its transcript) instead of the frame's current evidence, and repeated fresh
reads consumed the hold's budget. Fixed: a fresh read during a miss returns the frame's exact
or high evidence or nothing and leaves the cache entry untouched; tested with fresh reads
inside the outage between held polls.

Round 2 (against the docs written after the replay) returned four findings, all accepted
and all documentation corrections: `seen` starts true, so the Done badge seen after the
trust dialog cannot come from `osc.idle` (the explanation was rewritten); the session
limitation does not extend to `agents read`, which resolves again from a fresh screen; the
new Claude provider section had described a confirmed exit as a provider resumption; and
`prowl agents` reads the published pane decision, not the coordinator's current one. Round 3
confirmed the four fixes against the code with no new finding.

## Verification

| Gate | Result |
| --- | --- |
| TDD | `defaultTableVerifiesClaudeCodeOnly()` and `productionTableVerifiesClaudeCodeAndNotPi()` failed before the flip (`.unverified` for `.claude`; the pushed pane stayed `idle`) and passed after it; the five program-status test classes (63 tests) passed on the flipped tree. Session identity (2026-10-11): the four `ClaudeSessionRegistryTests` and `sessionIdentityIgnoresTheStatusFields()` failed to build before the change (`ClaudeSessionRegistry` and `ClaudeRuntimeDecoder.sessionID` did not exist) and passed after it together with `AgentSessionProfileTests` and `AgentSessionResolverTests`. The hold (round 4 finding 1): `transientRegistryFailureHoldsTheExactSessionBeforeTheScanTakesOver()` failed before the resolver change (the fingerprint took over at the first miss) and passed after it, with the registry, resolver, profile, and daemon-resolution suites (71 tests) |
| `make check` | passed on the final tree (swift-format, SwiftLint strict after two test locals were renamed for `identifier_name`, script tests, naming and localization checks); passed again on the session identity tree, and on the hold (after SwiftLint's `large_tuple` turned the resolver's three-member result into `UncachedResolution`) |
| `make test` | passed on the final tree: ProwlTests 3799 passed / 0 failed (verified xcresult 3805 tests, one more than #893), event monitor 12, mirror 72 (1 skipped), shell cancellation 3; the 12 build warnings are the pre-existing ones on `main` | Session identity tree: ProwlTests 3804 passed / 0 failed (verified xcresult 3810, the five new tests), event monitor 12, mirror 53 (1 skipped), shell cancellation 3; the same 12 pre-existing build warnings. Final tree (hold and fresh-read guard): ProwlTests 3806 passed / 0 failed (verified xcresult 3812), event monitor 12, mirror 53 (1 skipped), shell cancellation 3 |
| `make build-app` | passed with 0 warnings on the final tree, again on the session identity tree, and again after the hold and the fresh-read guard |
| Isolated Debug run (gate 6) | Branch build in a second instance (`CFFIXED_USER_HOME=/tmp/prowl-079-s3-home`, own socket, `script -F` log) with Claude Code 2.1.296; the real `~/.claude/sessions` and `~/.claude/projects` linked read-only into the isolated home so the native and session paths are observable. Every row of the plan's acceptance list was replayed and is recorded in the baseline's *Verification inside Prowl* table: trust → `claude.blockedPrompt` → `osc.idle` delegated; prompt → `osc.working` (≈ 100–350 ms CLI-polled); Bash write → `osc.blocked.permission` → `osc.done` → Done → viewed → Idle; AskUserQuestion → `osc.blocked.question`; foreground subagent → root-driven; background subagent → root `working` while Claude waits for it (see below); Esc and `/clear` → `osc.idle`; invalid API key → `osc.blocked.auth`; `/exit` 545–793 ms and `kill -9` 394 ms to release (CLI-polled; `main` 1.8–2.1 s); relaunch → own `osc.idle`; close + undo (`prowl key <pane> cmd-z`) → restored pane carries `osc.done` from the retained store; `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1` → `native.*` with the screen rules; `Claude Test` Profile (sonnet, bypass permissions, managed hooks) → launch dispatch receipt, `agents wait --until idle`, and a re-dispatch all resolved with `hook_claude` at `exact`. The Pi pane in the same instance stayed `legacy.detector` with shadow lines. No case was found where OSC was wrong and the legacy decision right: on every disagreement-prone row (`/compact`, background agents) the fresh screen rule read by `agents read` agreed with the root record Session identity (2026-10-11, same instance setup with the registry linked, Claude Code 2.1.296): the roster showed the registry's session as `process_log` / `exact` from the first `osc.idle` with no transcript path; the path appeared 6.3 s after the first prompt (the file is created on submit, read at the next uncached resolution); `/clear` with no further input moved the roster to the new session 2.1 s after the command (the registry had rotated, and 2.1.296 creates the new transcript at `/clear`); an in-process `/resume` back to the first session, with no input after the picker's Enter, moved the roster back 4.2 s later with the first transcript's path — the case that was stuck before. `agents read` reported the same session with its transcript |
| CPU (gate 2) | `make measure-cpu` on the slice build against the slice 2 baseline on `main` (one Claude pane and one Pi pane). Idle: `20261011-013537-61800` mean 1.0 %, `detectAgentState` 0.52 % of a core, `AgentSessionResolver.resolve` 0.06 % (baseline `20261010-214229-57604`: mean 1.0 %, 0.49 %, 0.04 %). Working, both agents writing essays for the whole sample: `20261011-014153-69839` mean 9.5 %, `detectAgentState` 0.31 %, `AgentSessionResolver.resolve` 0.03 %, SwiftUI `stepTransactionFlush` 5.4 % (baseline `20261010-214500-60944`: mean 26.1 %, 0.52 %, 0.02 %, 7.8 %). The working mean is not a like-for-like saving: the display was off and the screen locked during this run, the Claude pane ran the `sonnet` model, and the baseline window was key; the per-symbol numbers are the comparable part. Load 1.6–2.8 on 12 cores. An earlier working sample in which Claude finished mid-window (`20261011-013707-63680`) showed `detectAgentState` at 1.08 % and is kept only as a caution about short tasks |
| Review loop (gate 7) | six rounds: 3 findings, then 4 documentation corrections, then 0 for the flip; then 5 (1 code, 4 docs), 1 (code), and 0 for the session identity change; every finding was verified by reading the code before it was accepted |

## Observations

- **Harness replay of a background subagent (2026-10-11, recorded in the baseline).**
  Claude Code 2.1.296 does send child records: `state=working:id=<agent id>:title=<base64>`
  when the Agent tool starts and `state=clear:id=<agent id>` when it finishes, each within
  0.05 s of the `SubagentStart` / `SubagentStop` hooks. The root re-sends `working` 1.1 s
  after the `Stop` hook of Claude's own turn and keeps it while the TUI waits; when the
  agent finishes, Claude auto-submits its result as a new turn (`UserPromptSubmit`, `Stop`)
  and only then sends `done`. So "root working with a live child" is distinguishable from
  OSC alone, "the root's own turn ended" is not (the `Stop` hook and the screen row are the
  only signals), and an Idle-while-background decision would be followed by a short Working
  for the auto-submitted turn. onevcat decided on 2026-10-11 to keep the current behaviour.
- **Background agents keep the pane Working.** Claude Code 2.1.296 keeps the root record
  `working` while it waits for a background subagent, even after the `Stop` hook of its own
  turn (see the harness replay above): the TUI shows `✻ Waiting for 1 background agent to
  finish`, the prompt box is usable, and `done` arrives only after the auto-submitted result
  turn ends. The fallback screen rule `claude.backgroundWork` reads the same frame as
  Working, so the two paths agree. The product decision of
  2026-10-10 (background work leaves the pane Idle and never blocks a workflow) is
  implemented on Prowl's side (child `working` is ignored) but does not take effect for
  Claude until Claude Code reports the main turn as `done` with the subagent as a child
  record; that is a producer gap to report upstream, not a Prowl change.
- **`osc.blocked.auth`.** An invalid `ANTHROPIC_API_KEY` accepted at launch makes the first
  prompt fail with `Invalid API key`; Claude reports `blocked kind=auth` and holds it, so
  the pane is Blocked where the legacy path showed an idle composer. Treated as correct:
  the agent cannot continue without the user.
- **Done badge after the trust dialog.** The first manual pane showed Done when the trust
  dialog gave way to `osc.idle`. `seen` starts true and `osc.idle` neither earns nor clears
  the badge, so the badge cannot come from that report; the legacy poll runs at 300 ms while
  the dialog is Blocked, and a legacy Blocked → Idle transition on the mounting TUI, before
  Claude's `idle` report arrived, is the only path in the code that earns it (observed cause,
  not instrumented). A relaunch without the dialog went `fallback.noRuleMatched` → `osc.idle`
  and stayed Idle, which agrees.
- **Roster status can trail the reason by one hop.** `prowl agents` reads `detection_reason`
  from the published terminal pane decision (`surfaceAgentStates`) and `status` from the
  reducer's Active Agents entry, which the push updates asynchronously, so a single poll
  taken between the two can show the old status with the new reason. Readiness (`agents
  wait`, dispatch, workflows) reads the coordinator's current decision instead, which drops
  an `osc.*` reason at once on a withdrawal while the published decision waits for the fresh
  observe. Pre-existing architecture.
- **Isolated homes hide the registry.** With `CFFIXED_USER_HOME` the native provider reads
  `<home>/.claude/sessions`, which is empty, so slice 2's runs saw `screen.logUnavailable`
  where the plan expected `native.*`; linking the real `sessions` directory into the
  isolated home restores the `native.*` fallback. The transcript scan, on the other hand,
  cannot resolve any session for a pane under `/tmp` (found in slice 4's replay, 005): the
  resolver's `workingDirectoryVariants` derives the physical path with
  `URL.resolvingSymlinksInPath()`, which strips `/private`, so it scans `-tmp-x` while
  Claude writes `-private-tmp-x`. That is why this slice's replay showed no transcript
  session before the registry change; the registry identity does not depend on the cwd
  and resolved in the same instance. Pre-existing on `main`, left for a follow-up.
- **Undo-close under a locked screen.** A posted ⌘Z never reached Ghostty's keybinding while
  `loginwindow` was frontmost; `prowl key <other pane> cmd-z` within the undo timeout did.

## Session identity under delegation

Review finding 1, studied on 2026-10-11 after the first record. Under delegation the tick
reuses the frame of the last full tick, which a key press, a CLI input, a finished command,
an OSC withdrawal, a probe miss, or a process change triggers; nothing on a timer reads the
screen again. Claude's `/clear` sends `working` then `idle` and an in-process `/resume`
sends only `idle` (harness, baseline), neither a withdrawal, so a rotation woke nothing.
What that meant for the resolver, which runs every delegated tick with the stale text:

- `/clear` ordinarily recovered: the frame of the first prompt's Enter carries the prompt
  text, and once the new transcript held it the fingerprint selected the new session at
  the next uncached resolution — the same as on `main`. That recovery was conditional
  (a prompt of at least 12 normalized characters that scores against the new transcript
  and clears the margin over the old one), and the quiet window between `/clear` and
  that prompt showed the outgoing session on both paths, because nothing but the
  registry can attribute an empty new transcript.
- An in-process `/resume` to a session that already had a process-lifetime transcript
  (two candidates, so only the fingerprint could decide) was stuck: the frame of the
  picker's Enter either matched nothing — the outgoing session was retained for three
  fresh misses (about 7–10 s) and then the roster showed no session — or matched the
  outgoing session's tail and kept it with `high` confidence. Either way nothing
  corrected it until the next input, after which the cache (5 s) plus one delegated
  tick (2 s) bound the recovery at about 7 s. `main` corrects the same case within
  5 s because its 300 ms loop re-reads the settled frame.
- The stale identity was visible in the roster, `prowl agents --json`, and the Active
  Agents row's session log actions; `agents read` resolves from a fresh frame. OSC state
  selection and explicit dispatch receipts do not derive from the session, but session-
  bound hook evidence does: an exact or high pane session feeds the evidence epoch, and a
  change rotates it, clearing the current channels and signals that idle, blocked, and
  changed waits and dispatch admission consume (`updateEvidenceEpoch`,
  `AgentConditionEvidence`). A `high` fingerprint guess that moved and moved back
  therefore cost more than a wrong roster line.

The fix takes Claude out of the screen's hands: the registry record that the native
provider already decodes names the current session for the live pid (`/new` and
`/resume` update it before any model input, 068), so `ClaudeSessionRegistry` reads it as
the pane's session (`process_log`, `exact`) through the profile's `pidKeyedSession`
hooks, under the default home and under a Prowl-relocated root. The rotation is now
visible within the resolver's 5 s cache plus one tick, on `main`'s cadence and on the
delegated one alike, and it also covers the window between `/clear` and the first
prompt and a resume of a session from an earlier process, which the transcript scan
could not attribute on either path. An exact session takes part in the evidence epoch
the way `transcript_match` (`high`) already did: a rotation rotates the epoch and the
managed hook's reversible supersession handles the hook's own `SessionStart`.

Pi has no pid registry, so the generic cover — keeping the active cadence for a short
settle window after each input, option (c) above — lands in #896; once both merge it
also covers Claude versions without the registry.

## Open questions

- Child records are stored but not observable from inside Prowl: there is no per-report
  diagnostic for verified producers, and the CLI exposes only the root decision. The
  harness showed on 2026-10-11 that Claude Code 2.1.296 does send them for subagents
  (baseline). A Debug-only report line (state, id, app, kind; never `msg`) would make the
  next producer's replay cheaper.

## Refs

Builds on #887 (slice 1), #892 (plan), #893 (slice 2); parallel to #896 (slice 4, Pi). #891
(legacy background-work semantics) stays open. PR #895.
