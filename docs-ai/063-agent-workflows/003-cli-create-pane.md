# 063.003 — Anchored Split and `prowl create pane` (A1)

## Context

Release R1 needs deterministic split creation for both direct CLI orchestration and the profile launch boundary in A2. The terminal already split a supplied surface for Ghostty actions, but that path returned only a Boolean; the CLI had no pane-creation leaf under the action-first lifecycle grammar.

## Change

- `WorktreeTerminalState.createSplit(of:direction:initialInput:additionalEnvironment:focusing:)` resolves an explicit anchor, returns the created surface UUID, and reports typed `SplitCreationError` failures.
- Existing focused-surface and Ghostty action paths delegate to that primitive.
- `prowl create pane <pane> --direction right|left|up|down` accepts a pane UUID or current `pN`; `up` maps to the terminal layer's `.top` direction.
- The lifecycle handler receives a dedicated `createPane` provider. The app splits the resolved anchor before changing worktree or tab selection, so mutable UI focus cannot retarget creation.
- `prowl.cli.create.v1` remains additive: pane responses include `resource`, the resolved `anchor`, public `direction`, and created `target`; tab responses remain unchanged.
- Parser, handler, socket/schema, terminal-layer, contracts, user manual, and bundled skill coverage ship together.

## Decisions

- Pane creation inherits the anchor through Ghostty's existing split-surface configuration path; A1 does not add command execution or profile launch behavior.
- The provider selects the created pane only after direct anchored creation succeeds. This preserves normal focused-result behavior without using focus as an input to targeting.
- Bare numeric handles are rejected for the new pane anchor. Only UUIDs and explicit `pN` handles participate in this pane-only grammar.
- The anchor stays explicit (review decision 2026-08-22): no caller-pane default, so an unset shell variable fails with `INVALID_ARGUMENT` instead of silently splitting the caller's own pane. Agent self-identification is delivered separately through a per-pane `PROWL_PANE_ID` environment variable (its own R1 slice in [release-plan.md](release-plan.md)).
- Creating beside a non-visible anchor selects the anchor's worktree and tab, mirroring `create tab`; a background placement is deferred to A2's launch `placement`.
- The `anchor` payload is the pre-split resolution snapshot, so its `focused` / `selected` flags describe the state before creation.

## Verification

- Terminal and lifecycle handler suites: 12 tests passed; their RED runs first failed on the missing anchored primitive and pane provider/wire types.
- Parser suite: 5 tests passed; focused create socket/schema coverage: 3 tests passed.
- `make check` passed.
- `make build-cli` and `make test-cli-smoke` passed; `make test-cli-integration` passed 79 tests.
- `make test` verified 2,371 tests with zero failures; five dependency-scan warnings remain pre-existing.
- `make build-app` passed with zero warnings and errors.
- Live Debug verification created an `up` split through an isolated socket, confirmed the response anchor/direction/new UUID and list visibility, then closed the created pane successfully.

## Refs

- Slice: 063-A1
- Branch: `feat/cli-create-pane`
- Issue: #699
- PR: #710
