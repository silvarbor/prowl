# Oh My Pi state provider — program status (OSC 7501)

Status: Oh My Pi is a verified OSC 7501 producer since
[079.006](../079-program-status-osc-7501/006-omp-verified.md). Like Pi it has no file
provider: before 079.006 it had the screen detector alone (the Esc-glyph loader row, the
braille status-line spinner, and the Ask-prompt heuristics), and that detector stays as the
fallback for Oh My Pi versions that do not report and for `terminal.programStatus: false`.

## What decides the state

`ProgramStatusSupport.level(for: .omp) == .verified` in
`App/Sources/Domain/AgentDetection/ProgramStatusEvidence.swift`, with
`DetectedAgent.omp.programStatusApp == "omp"`. The root record Oh My Pi 18.8.7 and later
writes (`app=omp`) is the first-priority state evidence, applied the moment the report
arrives (`osc.working`, `osc.blocked.<kind>`, `osc.idle`, `osc.done`, `osc.error`); while it
decides, the detection loop runs on the delegated schedule (process probe and session
resolution every 2 s, no screen read) and `screen_reason` is `screen.delegated`, except for
the 3 s settle window after a key press or CLI input (079.005). The session is still the
transcript scan over `~/.omp/agent/sessions/<home-relative cwd>/` plus the screen
fingerprint; OSC carries no identity.

Oh My Pi sends no support query and reports `idle` as soon as its TUI mounts. It writes the
root record only (never an `id`), so the root-only rule has nothing to ignore and no child
`blocked` veto can apply. `msg` is sent with `blocked` and `error` only and is never logged
or published by Prowl.

Unlike Pi, Oh My Pi has a permission system, so Blocked comes both from the screen
heuristics (fallback) and from the protocol: a tool approval prompt (`tools.approvalMode`,
`--approval-mode always-ask`) is `osc.blocked.permission`, and the `ask` tool is
`osc.blocked.question`. A failed turn (for example an invalid API key) is `error`: the pane
reads Idle with `osc.error`, badge-eligible, held until the next report. The managed
`--hook agent-hooks/omp/prowl-hooks.ts` extension of Agent Profile launches is untouched and
remains the exact path for completion signals.

A background (`async: true`) bash job keeps the root `working` after the model has replied:
Oh My Pi reports `done` only once the job has finished and its injected result turn has
ended. The pane therefore stays Working for the whole job, the same as a Claude Code
background subagent (decision of 2026-10-11 to keep this behaviour).

Wrapper programs are fenced by `app`: a root with another `app` is logged once as
unmapped, a root without `app` is ineligible, a root with `app=omp` is attributed to the
pane's Oh My Pi. Pi's `app=pi` record does not count for an Oh My Pi pane and the other
way round.

## Boundaries observed (Oh My Pi 18.10.0, isolated Debug instance, 079.006 replay)

See the Oh My Pi table under *Verification inside Prowl* in
[producer-baseline.md](../079-program-status-osc-7501/producer-baseline.md).

## References

- [079 plan](../079-program-status-osc-7501/000-plan.md), [producer baseline](../079-program-status-osc-7501/producer-baseline.md)
  (what Oh My Pi sends, the harness invocations).
- [Pi provider](pi.md) for the closest sibling; [shared architecture](architecture.md).
