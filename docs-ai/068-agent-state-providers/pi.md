# Pi state provider — program status (OSC 7501)

Status: Pi is a verified OSC 7501 producer since
[079 slice 4](../079-program-status-osc-7501/005-pi-verified.md); this is Pi's first and
only state provider. Pi has no file provider: before 079 it had the screen legacy detector
alone (`legacy.detector`, Working/Idle, never Blocked), and that detector stays as the
fallback for Pi versions that do not report and for `PI_PROGRAM_STATUS=0`.

## What decides the state

`ProgramStatusSupport.level(for: .pi) == .verified` in
`App/Sources/Domain/AgentDetection/ProgramStatusEvidence.swift`. The root record Pi 1.1.0
and later writes (`app=pi`) is the first-priority state evidence, applied the moment the
report arrives (`osc.working`, `osc.blocked.<kind>`, `osc.idle`, `osc.done`, `osc.error`);
while it decides, the detection loop runs on the delegated schedule (process probe and
session resolution every 2 s, no screen read) and `screen_reason` is `screen.delegated`,
except for the 3 s settle window after a key press or CLI input, when the 300 ms loop
reads the screen again (docs-ai 079.005). Pi has no pid registry, so its session is still
the transcript scan over `~/.pi/agent/sessions/<cwd>/` plus the screen fingerprint; the
settle window is what lets a `/new` or `/resume` rotation be attributed from the frame it
settles into instead of the frame of the key press that caused it.
Pi sends `idle` within about 10 ms of the query echo, before the first probe has bound the
agent, so the report wakes the probe and the first observe pulls the store snapshot. A
`clear` (ctrl+d) withdraws the authority and the next poll reads the screen again with the
`legacy.detector` reason; a confirmed exit after OSC 133 releases the entry.

Blocked exists for Pi only through the protocol: Pi's built-in tools never ask for
confirmation and Pi has no permission setting, so `blocked` comes from extension dialogs
(`ctx.ui.confirm` → `osc.blocked.permission`; `ctx.ui.select`, `input`, `editor` →
`osc.blocked.question`) and from an OAuth login wait (`kind=auth`). A provider failure
during a turn is `error`: the pane reads Idle with `osc.error`, badge-eligible, held until
the next report. Pi's own selectors (`/model`, `/settings`) send nothing, so the previous
root state stands while they are open (no regression: Pi never had Blocked). The managed
`-e prowl-hooks.ts` extension of Agent Profile launches is untouched and remains the exact
path; Oh My Pi is a separate agent whose `app` is unknown and stays unverified.

The root-only rule applies: a `pi-subagents` card still running after the root is `done`
leaves the pane Idle; the fallback rule `hasPiRunningAsyncSubagentCard` keeps Working only
for versions that do not report. Wrapper programs are fenced by `app`: a root with another
`app` is logged once as unmapped, a root without `app` is ineligible, a root with `app=pi`
is attributed to the pane's Pi.

## Boundaries observed (Pi 1.1.0, isolated Debug instance, slice 4 replay)

| Pi boundary | Observed |
| --- | --- |
| launch | `idle` arrives before the first probe binds the agent; the report wakes the probe and the first roster entry is already `osc.idle`, delegated |
| prompt, turn end | `osc.working` on submit (≈ 100 ms through the CLI), `osc.done` at the end of the turn (Done badge while unviewed) |
| interrupt (Esc) | `osc.idle` ("Operation aborted"), not `error` |
| extension dialog `ctx.ui.confirm` | `osc.blocked.permission`; answering returns `osc.working` then `osc.done` |
| extension dialog `ctx.ui.select` | `osc.blocked.question`; same return path |
| built-in selectors (`/model`, `/settings`) | no report; the previous root state stands (documented gap, no regression) |
| provider auth failure (expired Anthropic OAuth) | `osc.working` then `osc.error` within a second; held until the next report; reads as Idle with the Done badge |
| ctrl+d, `kill -9` | the entry is released by the fresh probe after OSC 133 (tens to hundreds of milliseconds through the CLI) |
| relaunch in the same pane | one `legacy.detector` poll, then the new process's own `osc.idle`; the predecessor's records are fenced by arrival time |
| `PI_PROGRAM_STATUS=0`, < 1.1.0 | no reports: `legacy.detector` from the screen rules, unchanged |
| `/new`, in-process `/resume` (2026-10-11, settle window) | `osc.idle` once the session is picked, never `clear`; the pane's session is the transcript scan plus fingerprint, read from the settled frame inside the 3 s window: a new session's transcript resolved 1.1 s after its first prompt, and a `/resume` back to an earlier session moved the roster 2.5 s after the picker's Enter with no further input |
| Agent Profile launch (managed `-e prowl-hooks.ts`) | the Profile keeps its exact hook channel while OSC supplies the pane state and takes part in idle admission; the kickoff and a later assignment completed through explicit dispatch receipts, and the idle wait and the re-dispatch admission succeeded |
| `pi-subagents` running after root `done` | not exercised in the replay (root-only rule by code: the pane reads Idle; the fallback `hasPiRunningAsyncSubagentCard` applies only without reports) |

## References

- [079 plan](../079-program-status-osc-7501/000-plan.md), [producer baseline](../079-program-status-osc-7501/producer-baseline.md)
  (what Pi sends, the gate extension used to replay `blocked`).
- [Shared architecture](architecture.md); [Claude provider](claude.md) for the native
  provider interplay that Pi does not have.
