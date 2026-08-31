# 064-S2 — Paired Dispatch and Agent Wait

## Status

Complete and merged in PR [#718](https://github.com/onevcat/Prowl/pull/718).

## Delivered behavior

- Prompted CLI Profile creation atomically issues and binds a dispatch, injects a child-only
  `PROWL_DISPATCH_ID`, and appends the versioned completion instruction. Unprompted Profile
  creation remains dispatch-free.
- `agents dispatch-complete` records an ancestry-verified succeeded/failed summary receipt;
  `agents dispatch-abandon` explicitly releases pending coordinator capacity without acting
  on the worker.
- The app-lifetime MainActor store retains 256 immutable records with terminal-first
  eviction, pending protection, first-write-wins/idempotent mutations, non-destructive
  waiters, immutable launch targets, and 300 ms completion-priority lifecycle coalescing.
- `agents wait --dispatch` accepts only an opaque id and returns strict receipt outcomes.
  Generic pane waits implement idle/blocked/changed/exit, confidence thresholds, labelled
  two-second heuristic fallback, optional stable detection-screen evidence on success and
  structured errors, overflow resubscription, and request cancellation cleanup.
- Cooperative evidence is bound to PID plus process start time and an exact/high current
  session where available; medium session guesses remain diagnostic. Only a transition into
  normalized working invalidates terminal evidence; title churn while already working does not.
  The first dispatch process generation must have started within ten seconds of launch binding, preventing a missed
  short-lived runtime from lending its epoch to a later agent. Stale, mismatched, and
  unverifiable signals remain diagnostic. Existing
  detected-agent JSON rows expose current-epoch signal channels without adding shell rows.
- The socket server monitors peer EOF/extra input after the request frame and cancels the
  route instead of retaining a long-lived subscriber.
- Shared wire models, executable response schemas, text/JSON rendering, CLI grammar, manuals,
  normative contracts, and TDD coverage ship in the same slice.

## Contract decisions

No frozen product rule changed. Implementation uses Xcode 26.6 because the handover's Xcode
26.4 path is not installed; this is a validation-environment deviation only. A parallel
focused test run exposed an Xcode 26.6 worker-finalization hang after all selected tests had
passed, so final gates run with the repository defaults or one macOS test worker where a
focused rerun is needed. The final repository gate completed with 2453 reported passes and
2455 tests verified in xcresult, with zero failures. The final audit also binds evidence to
the dispatch launch epoch, replays active nonterminal evidence to late waiters, gives buffered
evidence priority over timeout startup, and rolls back the exact launched resource if target
resolution fails.

## Verification

The exact commands, executed-test evidence, and isolated Debug E2E results are maintained in
[004-s2-work-note.md](004-s2-work-note.md). Its authenticated rerun records real Codex and
Claude child panes each completing their own prompted dispatch with a succeeded receipt; both
coordinator waits returned the corresponding immutable target and summary.
