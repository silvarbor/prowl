# 079.006 — Oh My Pi verified

## Context

Oh My Pi 18.8.7 (2026-10-09) added OSC 7501 reporting (`terminal.programStatus`, default
on). This amendment repeats slices 3 and 4 of [000-plan.md](000-plan.md) for it: record the
producer's baseline, replay it inside Prowl, then flip `omp` to `.verified` so that the root
record it writes decides the pane state and the detection loop delegates while it does. The
plan's slice 4 table had listed Oh My Pi as "separate agent, `app` unknown, stays
`.unverified`"; the producer now names itself `app=omp`.

## Change

| Layer | Files | What |
| --- | --- | --- |
| Support table | `App/Sources/Domain/AgentDetection/ProgramStatusEvidence.swift` | `ProgramStatusSupport.level(for:)` returns `.verified` for `.omp`; `DetectedAgent.programStatusApp` maps `.omp` to `"omp"` |
| Tests | `App/Tests/AgentCoordinatorProgramStatusTests.swift`, `App/Tests/WorktreeTerminalStateProgramStatusTests.swift` | the production table tests now cover Oh My Pi (renamed `defaultTableVerifiesClaudeCodePiAndOMP()` and `productionTableVerifiesClaudeCodePiAndOMP()`): the coordinator built with the default table delegates an `app=omp` root without sampling a provider, and the terminal owner publishes an Oh My Pi push (`osc.working`, delegated schedule); the codex control still publishes nothing |
| Docs | `docs/components/agent-detection.md` (Oh My Pi paragraph, attribution `app`, support table, escape hatch, the OSC 133 release note), new living doc `docs-ai/068-agent-state-providers/omp.md`, `architecture.md`, `pi.md`, `docs-ai/013-prowl-cli/contracts/agents.md`, [producer-baseline.md](producer-baseline.md) (harness rows and the Oh My Pi *Verification inside Prowl* table), `000-plan.md`, `001-action.md`, `docs-ai/README.md` |

No other code changed: the push path, the delegated tick, the settle window, the withdrawal
fence, the command-finished release, readiness, and the CLI surface are slice 2's and
079.005's. Oh My Pi's screen rules and the managed `--hook prowl-hooks.ts` extension are
untouched.

| Oh My Pi boundary | Handling |
| --- | --- |
| tool approval prompt, `ask` tool | `osc.blocked.permission`, `osc.blocked.question`; the screen heuristics remain the fallback |
| failed turn (invalid key, provider error) | Idle, `osc.error`, badge-eligible; held until the next report |
| bash `async` job after the model replied | the root stays `working` until the job's injected result turn ends, so the pane stays Working; same as a Claude Code background subagent, kept by the decision of 2026-10-11 |
| child records | none: omp writes the root only |
| support query | omp sends none; reports without a probe are accepted (revision 0.3) |
| wrapper writing the root | another `app` → fenced; no `app` → ineligible; `app=omp` → trusted; Pi's `app=pi` does not count for an Oh My Pi pane |
| `terminal.programStatus: false`, < 18.8.7 | no reports → the screen rules |

## Review

A read-only reviewer loop against the uncommitted branch (brief: plan, 005, the baseline, the
diff, and the code paths the flip activates). Round 1 returned 9 findings, all
documentation: the user manual `docs/components/terminal.md` still listed only Claude Code
and Pi and promised a one-probe release for every agent; `001-action.md` claimed the same
release for every agent and lacked omp in its session-identity bullet and refs; the plan's
attribution mapping and escape-hatch list were stale; and five nits (release timing range,
the A/B/C/D wording, the test counts, the record's refs, the architecture provider row).
The reviewer verified the code path (`programStatusApp` is read by the attribution fence,
the coordinator's rebind, and the unmapped-app log; omp has no provider to sample), that
the tests fail without the change, and the OSC 133 explanation against Ghostty's
`stream_handler.zig` and `Surface.zig`. Round 2 confirmed the 9 fixes and returned 1 nit
(the `prowl send` sentence contradicted the resumed-session case), fixed.

## Verification

| Gate | Result |
| --- | --- |
| Harness | `scripts/program_status_probe.py` against omp 18.10.0 (isolated `--profile`, deepseek-flash): every row of the producer table in [producer-baseline.md](producer-baseline.md) |
| TDD | with the two table tests extended and the source change reverted, a run of `AgentCoordinatorProgramStatusTests` and `WorktreeTerminalStateProgramStatusTests` (43 tests) failed exactly `defaultTableVerifiesClaudeCodePiAndOMP()` and `productionTableVerifiesClaudeCodePiAndOMP()`; with the change, those two classes plus `AgentStateMachineProgramStatusTests`, `ProgramStatusRecordStoreTests`, and `AgentConditionEvidenceProgramStatusTests` (78 tests) passed |
| `make check` | passed |
| `make test` | passed: ProwlTests 3809 passed / 0 failed / 5 skipped (verified xcresult 3814 tests), event monitor 12, mirror 53, shell cancellation 3; 0 build warnings |
| `make build-app` | passed with 0 warnings |
| Isolated Debug run | Branch build in a second instance (`CFFIXED_USER_HOME=/tmp/prowl-omp-home`, own socket, `script -F` log) with omp 18.10.0. The acceptance list is recorded in the baseline's Oh My Pi *Verification inside Prowl* table: launch → `osc.idle`; prompt → `osc.working` → `osc.done`; Esc → `osc.idle`; approval → `osc.blocked.permission`; `ask` → `osc.blocked.question`; invalid key → `osc.error`; async job → `osc.working` until its result turn ends, with `agents wait --until idle` resolving only then; `terminal.programStatus: false` → `legacy.detector`; relaunch (time fence); `OMP Test` Profile (managed hook) → launch dispatch receipt, `agents wait --until idle`, and a re-dispatch resolved with `hook_omp` at `exact`. No case was found where OSC was wrong and the legacy decision right |
| CPU | `make measure-cpu` on the isolated instance (one Oh My Pi pane, the selected tab; load 2.4–2.5 on 10 cores). Idle under OSC authority: `20261012-111655-74806` mean 0.3 %, `detectAgentState` 0.11 % of a core. Working, omp streaming an essay for the whole window: `20261012-111837-75360` mean 14.6 %, `detectAgentState` 0.03 %, SwiftUI `stepTransactionFlush` 3.6 % (the selected streaming pane's rendering). The slice 2 baseline on `main` (`20261010-214229-57604` idle, `20261010-214500-60944` working) had `detectAgentState` at 0.49 % and 0.52 % with one Claude and one Pi pane; the agent mix differs, so only the per-symbol detection cost is comparable |

## Observations

- **omp writes OSC 133 itself.** `@oh-my-pi/pi-tui` (`chat/user-message.ts`) opens each user
  message bubble with `133;A` and closes it with `133;B`, `133;C`, and `133;D;0`, so
  jump-to-prompt works and Ghostty's sticky `.input` cursor state is cleared. In Ghostty a C
  replaces the surface's command timer and a D consumes it, raising `COMMAND_FINISHED` only
  when a timer was set. Ghostty raises `COMMAND_FINISHED` for those inner
  pairs while omp runs (the fresh probe finds the same owner and changes nothing): a
  `prowl send 'omp …'` waiting for its command returned the moment the first prompt was
  submitted, with exit 0 and a 0 ms duration. The inner C replaced the timer the shell's C
  had started for `omp` and the inner D consumed it, so the shell's own D at exit raises
  nothing. A resumed session that draws earlier user messages at launch is expected to do
  the same before any new turn (read from the source, not replayed). The exit is then released by the six-miss path (2.1–3.4 s
  observed) instead of the command-finished fast path, the same as `main` before 079; a
  fresh session without a turn still releases within 0.3 s. Not a regression of this
  change, and not fixable on Prowl's side without distinguishing a nested program's 133
  from the shell's.
- **The Profile keeps both channels.** The managed hook stays `verified_live` at `exact`
  and supplies the completion signals and receipts; OSC supplies the pane state and takes
  part in idle admission, as for Pi.
- **`agents read` stays unsupported for omp** (`AGENT_UNSUPPORTED`), as its contract says;
  the blocked text is not read from the screen while OSC decides.

## Refs

Builds on #887 (slice 1), #893 (slice 2), #895 (slice 3), #896 (slice 4, the Pi flip this
repeats). PR #900. Living doc [068/omp.md](../068-agent-state-providers/omp.md); baseline
[producer-baseline.md](producer-baseline.md). Oh My Pi's OSC 7501 support shipped in
18.8.7 (`@oh-my-pi/pi-coding-agent` CHANGELOG).
