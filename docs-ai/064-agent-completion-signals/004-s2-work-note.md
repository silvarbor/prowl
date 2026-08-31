# 064-S2 — Implementation Work Note

This note tracks the authorized S2 execution. The frozen product contract remains
`003-s2-dispatch-wait-design.md`; delivered behavior and durable implementation evidence are
recorded in the existing 064 plan/action documents.

## Starting point

- Branch: `feat/agent-dispatch-wait-s2`
- Base: `origin/main` at `e93b73c2`
- Draft PR: [#718](https://github.com/onevcat/Prowl/pull/718)
- PR #716: merged; owner-reviewed S2 design and both review dispositions are frozen acceptance criteria
- Worktree: clean at branch creation
- Protected ignored path: `scripts/__pycache__/` (do not touch)
- `test-driven-development` skill: loaded and mandatory for logic, parser, store, schema, and serialization work
- `write-ai-doc` skill: not available in the current environment; this note follows the established 064 template

## RED checklist

- [x] Wire grammar and schemas: create dispatch, completion, abandonment, both wait modes, conflicts, UTF-8 bounds, strict tagged unions, error details, renderer, executable schema, and raw socket.
- [x] Dispatch store: issuance/binding, immutable target, completion/replay/conflict, concurrent waiters, terminal-first eviction, all-pending capacity, abandonment/races, gone retention, and app reset.
- [x] Launch pairing: child-only id, versioned prompt instruction, rollback, unprompted parity, and old-app fail-closed behavior.
- [x] Lifecycle ordering: direct close fan-out plus deterministic 300 ms completion-priority coalescing for turn/session/close candidates.
- [x] Evidence epochs: process start time, PID reuse, replacement, session replacement, diagnostic mismatches/sessionless signals, channel invalidation, and generic confidence/freshness.
- [x] Wait transport: snapshot/outcomes/timeout, overflow resubscription, stable screen, multiple waiters, peer EOF, killed CLI, task cancellation, and subscriber cleanup.
- [x] App composition: real handlers/stores and closed-surface immutable target payloads.

## GREEN / validation checklist

- [x] Focused CLI and app tests remain green after each increment.
- [x] `make build-cli`
- [x] `make test-cli-smoke`
- [x] `make test-cli-integration` — 92 framed-socket tests, zero failures.
- [x] `make check` — swift-format, SwiftLint, and 27 supporting checks passed.
- [x] `make test` — 2453 reported passes; repository xcresult verifier found 2455 executed tests, zero failures.
- [x] `make build-app` — zero errors and warnings.
- [x] Isolated Debug app/socket E2E with the freshly built CLI, including real Codex and Claude
  completion receipts after the local login repair.
- [x] Final scoped diff and protected ignored-path audit; `scripts/__pycache__/` remained ignored and untouched.

## Decisions and deviations

- No frozen product transition, trust, retention, cancellation, payload, or scope rule changed.
- Xcode 26.4 was not installed. All app validation used the repository-selected Xcode 26.6
  (`/Applications/Xcode-26.6.0.app`).
- One parallel focused run passed every selected test but Xcode 26.6 stalled while finalizing
  an extra test worker. The one-worker focused rerun and repository full gate both completed;
  this was a harness-finalization issue, not a product test failure.
- Full-suite load exposed two iterations of the same scheduling edge: a timeout child could
  beat already-buffered needs-input evidence. The initial fixture-only mitigation was
  insufficient; the final production fix makes each evidence event carry its receipt snapshot
  and consumes the initial event before starting the timeout.
- Final semantic audit tightened two production boundaries: late waiters now replay active
  needs-input/incomplete evidence, and dispatch evidence must match the launch-bound process
  epoch so a replacement agent in the same pane cannot settle an older dispatch. Failed target
  resolution also closes the exact just-launched tab or pane before returning failure.
- Focused tests for the final audit passed 22/22; the final full gate passed 2453 reported /
  2455 verified tests with zero failures.
- Skill Workshop proposal `prowl-cli-20260823-a59b46f453` was applied to the managed workspace
  during the original implementation. Review follow-up then synchronized the approved dispatch
  wait flow, heuristic rubric, and structured errors into tracked `skills/prowl-cli/SKILL.md`,
  with a repository contract test preventing the bundled copy from drifting back to polling.

## Progress log

- 2026-08-23 — Read the implementation prompt, complete handover, repository rules, all authoritative
  064/063 artifacts, and the frozen S2 design. Confirmed `origin/main` and local `main` both at
  `e93b73c2`, then created this branch and work note before tests or production changes.
- 2026-08-23 — Added strict CLI grammar/wire/schema/rendering first, including structured
  `CommandError.details`, pending create metadata, strict tagged records, command-specific
  schemas, old-app fail-closed checks, and raw framed-socket coverage for complete, abandon,
  and both wait modes.
- 2026-08-23 — Implemented the MainActor dispatch store, atomic prompted launch pairing,
  ancestry-verified completion, explicit abandonment, immutable target retention, direct
  surface-close fan-out, and 300 ms completion-priority candidate ordering. Deterministic
  store/lifecycle tests drove each transition.
- 2026-08-23 — Added PID+start-time/session evidence epochs, current/unbound/stale bindings,
  per-source JSON channels, generic confidence/freshness rules, TestClock stabilization,
  stable screen evidence, overflow resubscription, and cancellation subscriber cleanup.
- 2026-08-23 — Added request-scoped `DispatchSourceRead` peer monitoring. A real Unix socket
  test writes a complete wait frame, closes the peer, and proves the route task observes
  cancellation without a 600-second leak.
- 2026-08-23 — First `make test-cli-integration` run correctly failed the legacy prompted
  create fixture because it omitted the now-required dispatch object. Updated the fixture,
  added explicit dispatch command round trips, and reran 92 tests successfully.
- 2026-08-23 — Final automated gates: `make build-cli`, `make test-cli-smoke`,
  `make test-cli-integration`, `make check`, `make test`, and `make build-app` all passed.
- 2026-08-23 — Final semantic audit added late-evidence replay, launch-bound evidence-epoch
  enforcement, resolver-failure rollback, and buffered-evidence timeout priority. Re-ran every
  gate successfully after those changes; the final app build had zero errors and warnings.
- 2026-08-23 — Applied Skill Workshop proposal `prowl-cli-20260823-a59b46f453` after owner
  authorization. The managed workspace skill is live and scan-clean; direct synchronization
  into the repository copy remains prohibited by the current Workshop target model.
- 2026-08-23 — GitHub Actions exposed a runner-dependent test fixture: synthetic PID `400`
  happened to be live on the hosted runner, so the default process start-date lookup added an
  unexpected ancestry generation. The resolver test now injects a nil start-date provider for
  its fake PID graph. Focused tests passed 3/3, `make check` passed, and the full gate again
  passed 2453 reported / 2455 verified tests with zero failures.
- 2026-08-23 — Review follow-up synchronized the approved S2 flow and heuristic rubric into the
  tracked bundled skill. Repository tests now require strict dispatch waiting, structured error
  details, timeout re-arming, and explicit rejection of heuristic task completion.
- 2026-08-23 — Review follow-up made requested stable-screen evidence symmetric across success
  and structured dispatch/condition errors. Handler and executable-schema regressions cover a
  failed receipt and a condition timeout without changing their primary exit codes.
- 2026-08-23 — Review follow-up bounded first-generation attachment by process start time. A
  launch generation started within ten seconds still attaches even if observed late; a process
  started after that window rotates the epoch and cannot drive the missed dispatch.
- 2026-08-23 — Adversarial review round 1 found that generic non-exit waits ignored exact
  surface closure and timed out. They now return structured `AGENT_GONE` immediately with an
  exact surface observation and optional requested screen evidence.
- 2026-08-23 — The same review found that wait screen evidence read the scrollback-inclusive
  screen while labelling it `detection`. The provider now uses the active detection buffer,
  enforced by a source-contract regression test.
- 2026-08-23 — The injected completion protocol now states that summaries are single-line and
  control-free, matching validation instead of letting real agents discover the constraint only
  after a rejected final tool action.
- 2026-08-23 — Review follow-up distinguished a real transition into working from metadata churn
  while already working. Animated title emissions no longer erase fresh exact terminal evidence
  or clear dispatch attention/incomplete replay.
- 2026-08-23 — Adversarial review round 2 covered the detector's presence-release edge: a
  same-process `nil` → working re-detection now counts as activity and clears stale terminal
  evidence, while working → working metadata churn remains inert.
- 2026-08-23 — The bundled skill now requires newer activity or stable screen evidence after
  intervening on `DISPATCH_NEEDS_INPUT` / `DISPATCH_INCOMPLETE` before re-arming the strict wait.
  Error references also distinguish signal, dispatch, and condition meanings of `AGENT_GONE`.

## Fresh Debug E2E

Used the newly built Debug app executable and `./.build/debug/prowl` with the isolated socket
`/tmp/pr-s2-e2e.sock`; the normal Prowl socket and panes were not used.

- Prompted Codex and Claude Profile creates returned pending dispatches and immutable target
  snapshots. Both real runtimes reached their expected local credential blockers: Codex had
  no login and Claude reported an expired login. Runtime-autonomous completion therefore
  could not be claimed.
- From a launched pane's shell, an explicitly one-command-scoped `PROWL_DISPATCH_ID` exercised
  the real socket peer ancestry and completion handler. A succeeded receipt round-tripped
  through `agents wait --dispatch` with the exact summary and target. A separate failed
  receipt returned nonzero `DISPATCH_FAILED` with structured details.
- Explicit abandon woke an already-running coordinator wait with nonzero
  `DISPATCH_ABANDONED`, preserving reason and target.
- Exiting a blocked Codex process and closing its pending pane produced retained
  `AGENT_GONE` with `gone_reason=surface_closed` and the launch-time target.
- An unprompted Codex Profile create returned launch metadata with no dispatch object.
- Generic `--until blocked` resolved after exactly 2000 ms as `source=detection`,
  `confidence=heuristic`; requested screen evidence stabilized in 800 ms and returned the
  requested trailing lines. `agents --json` kept channels on detected rows only.
- A 600-second exact generic wait was killed at the CLI process. The app remained responsive
  immediately afterward; unit coverage additionally verified the observation subscriber
  count returned to zero, and the real peer-EOF socket test covered server route cancellation.
- Cleanup stopped only the isolated Debug app and removed exactly its temporary socket and
  lock files. No repository files were modified by the E2E workers.

### Authenticated rerun (2026-08-23)

The local Codex and Claude CLI logins were repaired after the first run. Rebuilt with
`make build-cli` and `make build-app`, then repeated the isolated Debug E2E using the same
temporary socket. The test launcher deliberately removed the automation session's isolated
`CODEX_HOME`, so the Codex child exercised the verified normal `~/.codex` ChatGPT login; it
also prepended `./.build/debug` to `PATH`, so the protocol's `prowl` command resolved to the
fresh checkout CLI rather than relying on an installed binary. These are test-harness
environment controls; no product source changed for the rerun.

- A prompted Codex Profile create returned pending dispatch
  `69481D53-7B57-43DD-A4FA-A1DB0F49ACA9`. After the one-time trusted-directory confirmation,
  the real child runner executed `prowl agents dispatch-complete --outcome succeeded` itself.
  The coordinator wait returned exit 0 in 3251 ms with summary `Codex real runner completion`
  and the original immutable target.
- A prompted Claude Code Profile create returned pending dispatch
  `D26EEEEE-C5F8-4C81-8F5D-7CEEE0B5EB85`. Claude ran normally, requested its standard one-time
  approval for the exact local completion command, then executed it itself. The coordinator
  wait returned exit 0 in 61248 ms with summary `Claude real runner completion` and the
  original immutable target.
- Both panes reached the actual task UI rather than a login screen. The preceding login-page
  result was traced to the automation process's inherited isolated `CODEX_HOME`, not to a
  missing local Codex credential; without the checkout CLI on `PATH`, the runner likewise
  correctly reported `prowl: command not found` instead of fabricating a receipt.
