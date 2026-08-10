# 030.006 — Current CLI pre-session blockers

## Context

Issue #676 reported stale Claude Code and Codex state detection. Before changing the
classifier, the current installed CLIs were exercised in isolated temporary workspaces:
Claude Code 2.1.223 and Codex CLI 0.146.1.

Claude's current workspace-trust dialog retains its numbered `❯ 1. Yes` selection
structure, so the existing Claude detector already classifies it as `blocked`. Its
subagent UI now keeps the parent spinner visible while listing the active subagent, so
it is already classified as `working`; the historical `Waiting for 1 background agent`
line was not observed.

Codex 0.146.1 has three unclassified pre-session blockers, all currently falling back
to `idle`:

- directory trust;
- hook review after a directory is trusted;
- first-run sign-in selection.

## Change

Added narrowly scoped Codex screen rules for the three observed dialog structures.
Directory trust and hook review require a current selected choice plus their adjacent
options and footer, anchored to the last `›` prompt line on screen. Sign-in requires
Codex's startup heading, its complete three-way choice menu, and its selected option as
the last `›`/`>` selection-marker line on screen — the live menu renders no composer
below it, so a later marker line means the menu text is stale transcript or a
quotation. This keeps transcript text from becoming a blocker merely by quoting a
confirmation phrase or a full menu.

Normalized excerpts from the live captures are inline regression fixtures in
`supacodeTests/ScreenHeuristicsTests.swift`, following the existing test convention.
The fixtures also prove stale directory-trust and sign-in screens followed by an
ordinary input remain `idle`. `docs/components/agent-detection.md` documents the
recognized Codex pre-session blockers.

## Non-goals

- Do not use hooks, process liveness, sockets, or agent-side integration as state
  evidence.
- Do not introduce a declarative rule engine or an external fixture corpus in this
  repair.
- Do not change Claude heuristics without a current failing capture.

## Validation

- The three new Codex fixtures failed against the pre-change detector because all fell
  through to `idle`.
- The stale sign-in fixture failed against the unanchored sign-in rule (classified
  `blocked`) and passes with the last-marker anchor.
- Focused and complete `ScreenHeuristicsTests` passed after the change.
- `make check` passed.
- `make build-app` passed with 0 errors and 0 warnings.

## Refs

- Issue #676
- `supacode/Infrastructure/AgentDetection/ScreenHeuristics.swift`
- `supacodeTests/ScreenHeuristicsTests.swift`
- `docs/components/agent-detection.md`
