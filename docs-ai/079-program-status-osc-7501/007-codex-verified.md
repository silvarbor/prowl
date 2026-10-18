# 079.007 — Codex verified

## Context and plan

Codex 0.163.0 includes OpenAI PR #52725. Its TUI emits an OSC 7501 root with
`app=codex` whenever stdout is a terminal. It does not probe for support or expose
an OSC-specific opt-out. The release source emits `idle`, `working`, `blocked`,
and `clear`, without a kind, message, child id, `done`, or `error`.

Extend the existing producer table and app attribution after replaying the installed
binary. Keep the generic arbitration, record lifetime, session resolver, hooks,
and workflow receipts. In particular, `idle` must not manufacture a Done badge or
completion receipt, and `blocked` must remain `osc.blocked.unspecified`.

Validation: first fail the production-table and Codex lifecycle tests, then enable
the mapping and run the OSC suites. Build and run an isolated Debug instance with
its own preferences and socket. Exercise real TUI startup, a completed turn,
permission and question prompts, cancellation, session reset, and exit. Inspect
Prowl's published reasons and readiness, and record untested boundaries explicitly.
Finish with `make check`, `make build-app`, a PR, and the Review Loop workflow.

## Outcome

`ProgramStatusSupport.level(for:)` now verifies Codex, and `programStatusApp` maps
it to `codex`. No parser, coordinator, scheduling, signal, or receipt code changed.
The production-table tests cover initial attribution and terminal publication;
Codex lifecycle regressions cover immediate pushes, unspecified blockers, idle
without a Done badge, clear restoring provider sampling, and foreign/stale roots.

| Validation | Result |
| --- | --- |
| Red, two affected suites | 3 expected failures, 42 passes: coordinator table, Codex lifecycle, terminal table |
| Green, seven OSC/condition/bridge suites | 86 passed, 0 failed; 0 build warnings |
| `make check` | Passed, including formatting, lint, 241 script tests, naming and localization checks |
| `make build-app` | Passed, 0 build warnings |
| PTY producer replay | Startup, complete turn, approval rejection, Plan question cancellation, exit |
| Isolated Debug app | Startup, working/idle, command approval and acceptance, question and answer, cancellation, `/new` and next turn, suspend/resume, normal and abrupt exit, Profile dispatch and redispatch |
| Managed notification | Valid notifier fixture: explicit dispatch succeeded; `hook_codex` remained `verified_live` at `exact` while state used OSC |

The detailed producer and app observations are in [producer-baseline.md](producer-baseline.md).
Local raw evidence is under `/tmp/prowl-codex-osc/`; it is not a repository artifact.

## Boundaries

- Codex's Idle is not completion evidence: cancellation also emits Idle. The
  semantic reader returned `incomplete` after cancellation. Explicit dispatch and
  workflow receipts remain required.
- Root-only status follows Codex's own lifecycle. Live child/background work,
  authentication, provider failures, remote/multiplexed sessions, and the external
  editor were not exercised. No support is inferred for states/kinds it does not emit.
- A quiet `/new` still showed the preceding session identity before its next turn;
  the next turn resolved the new session and returned its distinct result. This
  change does not extend session attribution.
- The first Profile fixture used `notify=[]`, which the existing preservation
  policy rejects as an invalid notifier. Its dispatch still succeeded but it had
  no managed channel. Retesting with `notify=["/usr/bin/true"]` verified coexistence.

## Refs

[OpenAI PR #52725](https://github.com/openai/codex/pull/52725),
[Codex 0.163.0 release](https://github.com/openai/codex/releases/tag/rust-v0.163.0).

