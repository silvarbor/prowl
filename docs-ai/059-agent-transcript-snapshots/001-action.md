# 059 — Agent Transcript Snapshots: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-11 | Wrote the snapshot-first plan and established the CLI/result-state contract. | This entry |
| 2026-08-11 | Added `prowl agents read` for explicit Codex/Claude panes, live blocker extraction, fresh transcript attribution, bounded decoders, contracts, and user guidance. | #696 |
| 2026-08-13 | Corrected Codex terminal-event decoding, cropped blockers, and hardened result bounds from live E2E findings. | #696 |

## Outcome & current state (as of 2026-08-13)

- `ProwlCLI/Commands/AgentsCommand.swift` and
  `ProwlCLI/Commands/AgentsReadCommand.swift` expose `prowl agents read <pN|uuid>`
  with immediate-only targeting, a 1–4 MiB result cap, and text-only `--result-only`.
- `supacode/CLIService/AgentReadCommandHandler.swift` keeps live snapshot evidence
  independent from transcript result evidence. It returns `complete`, `pending`,
  `unavailable`, `missing`, `incomplete`, or `too_large` in `AgentReadResult`; only
  `--result-only` turns non-complete states into command errors.
- `supacode/App/supacodeApp.swift` performs an on-demand active-screen detection pass,
  re-identifies the foreground process, and calls the fresh resolver path. It permits
  only exact/high transcript-backed Codex/Claude sessions.
- `supacode/Infrastructure/AgentDetection/AgentTranscriptResultReader.swift` reads a
  bounded, stable JSONL tail with one mutation retry; it decodes the latest Codex
  terminal event and Claude `turn_duration` parent-chain results without returning
  partial text. Codex timestamps follow the native integer Unix-seconds schema,
  aborted turns withhold earlier answers, and the tail budget covers worst-case JSON
  escaping. `AgentSessionResolver.resolveFresh` bypasses only the pid-result cache.
- `ClaudeScreenProfile` and `CodexScreenProfile` now export the raw blocked interaction
  region used by the command. `ProwlCLI/Output/OutputRenderer.swift` renders the normal
  status snapshot or writes result-only bytes directly without a synthetic newline.
- Shared models, routing, 32 MiB socket-frame guards, normative contracts, the user CLI
  guide, and the bundled `prowl-cli` skill were updated together.

## Verification

| Command | Observed result |
| --- | --- |
| `make check` | Passed: changed-file formatting, strict swift-format lint, and SwiftLint. |
| `make test` | Passed: xcresult verified 2,322 tests with zero failures. |
| `make build-cli` | Passed. |
| `make test-cli-smoke` | Passed. |
| `make test-cli-integration` | Passed: 68 tests. |
| `make build-app` | Passed: Debug macOS app build with zero warnings. |

## Follow-up verification

- Live Codex 0.147.0 E2E confirmed numeric `completed_at`, exact final-result output,
  cropped permission blockers, literal `max_tokens` answer text, and withholding an
  earlier answer after a real `turn_aborted/interrupted` event.
- Live Claude Code 2.1.228 E2E confirmed exact latest-result output and trusted
  transcript attribution.
- The final production reader matched an independent terminal-marker oracle across
  310 stable transcripts from the prior 30 days with zero mismatches: Codex reported
  59 complete, 11 incomplete, and 3 missing; Claude reported 108 complete, 2
  incomplete, and 127 missing.

## Deviations from plan

- The decoder tests use compact synthetic JSONL records in
  `supacodeTests/AgentTranscriptResultReaderTests.swift` instead of committing captured
  transcript fixture files. They cover the observed Codex 0.146.1 and Claude Code
  2.1.226 completion shapes without recording user transcript content.

## Open questions

- Native transcript schemas are intentionally narrow. A future Codex or Claude Code
  release that changes its completion markers must add a captured/redacted regression
  case before broadening the decoder.
