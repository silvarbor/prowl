# 059 — Agent Transcript Snapshots: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-11 |
| **Primary PRs** | #696 |
| **Related** | [013 — Prowl CLI](../013-prowl-cli/000-plan.md), [045 — Native agent session detection](../045-native-agent-session-detection/000-plan.md), [issue #473](https://github.com/onevcat/Prowl/issues/473), [relay-tracker #53](https://github.com/onevcat/relay-tracker/issues/53) |

## Background

`prowl agents` identifies the detected coding-agent panes, but its only follow-up is
`prowl read`, which exposes rendered terminal text rather than the agent's current
semantic state or a trustworthy final answer. A coordinating agent therefore has to
screen-scrape a TUI, poll ambiguously, and cannot distinguish a completed result from
an in-progress transcript fragment.

The command should be a snapshot, not a result waiter. Live state and a transcript
result are independent evidence: a session-resolution failure must not hide a current
blocker, while an untrusted session must never yield another agent's answer.

## Goals

- Add immediate, read-only `prowl agents read <pN|pane-uuid>` for Codex and Claude
  Code, with clear `--help` and direct reuse of handles from `prowl agents`.
- Return the live detected status on every successful snapshot, and return the raw,
  actionable current interaction region for a blocked agent.
- Return a latest final answer only after fresh, exact/high session attribution and a
  complete native transcript turn; never use the sticky `PaneAgentState.session` as
  authority and never return partial output.
- Keep a machine-readable, versioned JSON contract and a concise, uncoloured Markdown
  text snapshot. Provide `--result-only` for exact raw-result stdout pipelines.
- Bound results to 1 MiB by default and 4 MiB maximum, and make the socket response
  ceiling 32 MiB so a permitted payload can travel safely.

### Non-goals

- Do not alter `prowl read` viewport/scrollback semantics or add a terminal-text
  fallback for this command.
- Do not add `agents send`/`agents answer`; writes remain `prowl send` and `prowl key`
  operations and are not atomic with a prior read.
- Do not extend `AgentRuntimeAdapter`, `AgentSessionProfile`, or
  `TranscriptFragmentCache`, and do not support transcript results for other detected
  runtimes in this release.
- Do not promise cross-runtime elapsed-time or token accounting; existing screen
  status timestamps remain the only common activity metadata.

## Command and response contract

```bash
prowl agents
prowl agents read <pN|pane-uuid> [--max-bytes <1...4194304>] [--result-only] [--json]
```

`agents read` accepts exactly one explicit pane handle or UUID: no focus-derived target,
worktree/tab target, `--timeout`, or wait mode. It captures one immediate snapshot.
`pN` comes directly from text `prowl agents`; JSON callers pass
`.data.agents[].pane.id`. `--max-bytes` defaults to 1,048,576. `--result-only` is
text-mode only; it is invalid with `--json` and writes exactly `result.text` without a
header or synthetic newline.

The default text renderer is a plain Markdown snapshot with `Agent`, `Status`,
`Reason`, and `Changed` fields, followed by either `Blocker` or `Latest result`. A
blocker preserves the current active-screen interaction region verbatim enough to show
the question, numbered choices, selected marker, and keyboard hints; V1 deliberately
does not invent a lossy structured-choice schema.

The JSON response uses `prowl.cli.agents.read.v1` and carries resolved target metadata,
agent type/status/raw state/detection reason/last change, the trusted session evidence,
an optional blocker, and an independent result object. `result.state` is one of:

| State | Meaning |
| --- | --- |
| `complete` | Exact/high session attribution and one verified, closed turn; includes `text`. |
| `pending` | Working agent has no earlier completed result. |
| `unavailable` | No exact/high current session can be established. |
| `missing` | Idle/done agent has no completed answer in its trusted transcript. |
| `incomplete` | A candidate terminal turn is incomplete, malformed, unsupported, or max-token limited. |
| `too_large` | A complete answer exceeds `max_bytes`; no text is returned. |

A normal snapshot succeeds for every state above: state observation remains useful even
when transcript evidence is absent. `--result-only` asserts `complete`; every other
state is a non-zero error using `SESSION_UNRESOLVED`, `RESULT_NOT_FOUND`,
`RESULT_INCOMPLETE`, or `RESULT_TOO_LARGE`. Snapshot failures remain reserved for an
invalid/missing pane, no longer-active agent, unsupported runtime, unreadable active
screen, or unreadable blocker region.

## Design / Approach

1. Extend the nested `AgentsCommand` CLI grammar, shared input/envelope/router models,
   payload models, error constants, response renderer, and app router composition for a
   distinct `agents.read` wire command. Resolve only `TargetSelector.pane`, run an
   on-demand detection pass for the resolved live surface, and preserve the established
   display status (`working`, `blocked`, `done`, `idle`) alongside the freshly captured
   raw detection/reason.
2. Add a small on-demand agent-read capture at the terminal/app boundary. It re-identifies
   the foreground process, reads `readActiveContentsForCLI()`, records the matched
   Codex/Claude screen rule, captures the relevant profile launch root and cwd, and
   asks the session resolver for a fresh resolution. A new resolver entry point bypasses
   the pid-result cache but may retain safe file/root parsing caches; only `exact` and
   `high` resolutions are eligible for transcript reading.
3. Promote the existing Codex and Claude typed screen regions into narrowly scoped
   blocker extractors. They must be gated by their current blocked rule and return the
   raw interaction region, not a viewport or reconstructed prose. If no coherent
   interaction region is available, fail with `BLOCKER_UNREADABLE` rather than claim an
   actionable blocker.
4. Add an independent transcript-result reader beside the existing agent-detection
   infrastructure. It reads a bounded, race-checked JSONL snapshot and has separate
   Codex and Claude decoders:
   - Codex accepts only the latest terminal `event_msg.payload.type == "task_complete"`
     record with a non-empty `turn_id`, integer Unix-seconds `completed_at`, non-empty
     `last_agent_message`, and no error; a newer `turn_aborted` remains incomplete.
   - Claude accepts `system/turn_duration` as a close marker, follows its bounded
     same-session parent chain back through summaries to an assistant message, and
     accepts text-only content with `end_turn` or `stop_sequence`.
   The reader makes no partial return: malformed/unclosed records, broken chains,
   unsupported schema, unfinished tool turns, and `max_tokens` are `incomplete`.
   A file mutation during reading gets one bounded retry before classification.
5. Use the reader only after exact/high attribution. For working/blocked snapshots, a
   missing trusted session yields `unavailable` while preserving status/blocker; a
   missing prior closed turn is `pending`. Idle/done snapshots retain their status and
   report `missing`, `unavailable`, `incomplete`, or `too_large` rather than turning a
   usable observation into a transport failure.
6. Lift both client and server framed-response validation from 10 MB to 32 MiB, while
   applying the smaller per-result byte limit before payload encoding. The command never
   writes overflow output to disk and never truncates a result.
7. Update the living CLI input/schema contracts, add the `agents read` contract, and
   update the user manual and bundled `prowl-cli` skill with discovery, blocker,
   `--result-only`, result-state, and non-atomic write examples.

## Verification

- Add Swift Testing coverage for envelope round trips, router dispatch, parser validation,
  handler state/error mapping, text rendering, result-only byte-exact output, and the
  32 MiB transport boundary.
- Extend the existing Codex/Claude screen-profile fixture tests to assert blocker-region
  extraction for permission, trust, hook-review, sign-in, and generic confirmation
  screens, including quoted historical prompts that must not become blockers.
- Add redacted, version-pinned JSONL fixtures and pure decoder tests for valid terminal
  turns; earlier-result lookup while working; Claude parent-summary traversal; missing
  text; malformed/truncated JSONL; broken parent chains; unclosed tool turns;
  `max_tokens`; oversized answers; and files changed during a read.
- Add app-composition tests proving the new handler is wired, only pane selectors are
  accepted, fresh exact/high identity is required before transcript access, and the
  normal snapshot still preserves a blocked screen when result evidence is unavailable.
- Run `make check`, focused test classes, `make test`, and `make build-app` after
  implementation. Record actual commands and outcomes in `001-action.md`.

## Alternatives & decisions

| Alternative | Decision |
| --- | --- |
| Wait for a new final result and return old text on timeout | Rejected. The command is immediate snapshot inspection; no default wait or timeout exists. |
| Treat transcript failure as a top-level failure for every state | Rejected. It hides the useful current status/blocker; result availability is an independent JSON state. |
| Accept a freshly resolved `medium` session | Rejected. It can silently attribute another concurrent or stale same-cwd conversation. |
| Return generic terminal viewport text | Rejected. It cannot distinguish agent output from TUI chrome and violates the result completeness guarantee. |
| Parse structured blocker options | Deferred. Raw typed-profile interaction text is more complete and remains usable with existing `prowl key`/`prowl send`. |

## Amendments
