# 063.011 — Workflow Start Sheet and Entry Points (C2)

## Status

Drafted 2026-08-31; decisions frozen in the grill session of 2026-09-01. C2 is the first
R2b slice ([release plan](release-plan.md)), on B3 (#744) and C1 (#747), implemented on
`feat/workflow-start-sheet-c2` and opened as
[#752](https://github.com/onevcat/Prowl/pull/752). Four adversarial review rounds ran over
the PR (findings and dispositions in its comments): six findings fixed, one rejected with
rationale, one coverage gap closed; the closing round reports no open P0/P1. A CLI
regression smoke pass (isolated Debug instance, `workflow run` from a live Claude pane to a
completed run record) is green. The live GUI E2E pass is complete: an `ask` run started
from the palette (sheet with source picker, defaulted + required inputs, skip choice,
Run gating) ran to a completed record with both input values rendered into the typed
instruction; the `auto` run started from the palette with no sheet; the Agents popover
lists runnable rows with the "Run with Options…" escape hatch (verified to force the sheet)
and names the validation-failing file as an inert diagnostic row; the Active Agents menu's
`Run Workflow ▸` submenu starts with the row's pane pinned (read-only source row); the
`in <workflow> · <role>` subtitle appears the moment a run starts; Esc dismisses via the
key anchor; 061 visuals verified in Normal, Shelf, and Canvas plus a constrained-width
window. The pass also caught a real integration bug — view-scope `@Dependency` readers
(popover, context menu) resolved the empty `liveValue` stub instead of the assembled
client — fixed by publishing the live client through `WorkflowStartClientRegistry`.

## Product contract

R2a left exactly one way to start a workflow: `prowl workflow run` from a terminal. C2 gives
GUI users the same power without changing what a run *is*: every start still goes through the
same admission, binding resolution, and validation the CLI path uses, and the status center
(C1) takes over the moment the run exists.

Three entry points, per [000-plan](000-plan.md):

- the Agents capsule popover gains a **Workflows** section (`Hand Off…` stays its first row);
- the Command Palette gains `Run Workflow: <name>` commands;
- Active Agents rows gain a `Run Workflow ▸` context menu, and rows that belong to a run show
  an `in <workflow> · <role>` subtitle.

The **start sheet** (`WorkflowStartOverlay`, the handoff HUD's centered keyboard-capturing
card pattern — not window-modal) collects what the run needs before it exists:

- title/description; a "You" source row for the `current` role (a picker — see decision 2);
- one profile picker per `launch` role — filtered by `agents`, pre-selected from binding
  resolution (dsl-spec §3), unavailable rows dimmed with the reason, and
  "Create profile from suggestion…" when nothing matches;
- one pane picker per `pick` role — detected agents in the source worktree, excluding panes
  already in a run and the current pane;
- inputs (defaults pre-filled), a "Skip <step title>" choice for steps skippable at start
  (§9 `--skip` rule), and a "Don't ask again for this workflow" toggle when `bind: ask`;
- a CLI-not-installed banner with an inline Install action that disables Run;
- Cancel / Run.

`bind: auto` with unambiguous resolution and fully defaulted inputs skips the sheet entirely.

## Decisions frozen before implementation (grilled 2026-09-01)

1. **One start path.** The GUI never grows its own run-creation logic: the sheet gathers the
   same overrides/inputs/skips `workflow run` accepts and submits through the same
   coordinator entry; admission errors surface with the CLI's error semantics.
2. **The sheet's "You" row is a source picker** — the GUI equivalent of the CLI's `[source]`
   positional. It pre-selects the selected worktree's focused pane (capsule popover, palette)
   or the clicked row's pane (Active Agents menu, fixed there), and lets the user re-pick
   among the source worktree's detected agent panes when the pre-selection is unqualified or
   wrong. A workflow without a `current` role runs against the selected worktree. Run is
   disabled inside the sheet only when the whole worktree holds no qualified source.
3. **Entry-point visibility differs by surface.** Workflows disabled in Settings
   (`disabledWorkflowIDs`) appear nowhere; validation-failing ones appear only in the capsule
   popover, dimmed with the reason (the popover is the diagnostic surface); enabled + valid
   ones appear in all three entry points.
4. **"Create profile from suggestion…" is an inline confirm block** inside the picker: it
   shows the profile about to be created (editable name defaulting from the role/agent, the
   `suggest` fields as a read-only summary), and Create persists a normal profile and selects
   it. No silent one-click creation, no round-trip to the Settings editor.
5. **Bind-mode override is tri-state** (`nil` = follow the YAML `bind` / force `ask` / force
   `auto`), keyed like `disabledWorkflowIDs` and stored beside the binding memory in
   `UserGlobalSettings`; the sheet's "Don't ask again" writes `auto`, and D1's Settings page
   drives the same value. The capsule popover row carries a secondary **"Run with Options…"**
   action that forces the sheet — the GUI escape hatch matching an explicit CLI `--role`
   (the only place it is offered).
6. **Auto-skip needs no extra feedback and never skips required inputs.** When the sheet is
   skipped, C1's toolbar status item is the start feedback; a workflow with a required,
   defaultless input still presents the sheet to collect it.
7. **C2 does not touch handoff.** The HUD keeps its choose stage until D3; "replaces" in the
   000-plan is the end state, not this slice.
8. **One atomic PR**, C1-style, with the 061 toolbar rules and Normal/Shelf/Canvas visual
   verification for every entry-point surface.

## Implementation shape

- A pure start-sheet presentation model derived from the workflow definition, binding
  resolution output, detected agents, and CLI install status; `WorkflowStartFeature` (TCA)
  owns selection state and submits typed intents.
- Binding resolution reuses B3's pure resolver; the sheet is only the `ask` tier's UI and
  never re-derives eligibility.
- Entry-point wiring: palette commands from the discovery list (enabled + valid definitions
  visible to the worktree), capsule popover section, Active Agents context menu + subtitle.
- Reducer tests for every sheet transition (resolution tiers, unavailable pickers, skip
  consequences, banner gating, auto-skip path); no `Task.sleep`, `TestClock` only.

## Verification

`make check`, `make test`, `make build-app`; isolated-Debug E2E: an `ask` run started from
each entry point end to end, an `auto` run that skips the sheet, the CLI-missing banner; 061
visual verification in Normal, Shelf, and Canvas at normal and constrained widths.

## Implementation notes (decisions taken while building, recorded per the working agreement)

- **The presentation model folded into `WorkflowStartFeature.State`.** The plan sketched a
  separate pure model (C1's shape); the sheet's derived values (`canRun`, skip-aware source
  requirement, per-step skip consequence) read naturally as State computed properties and are
  tested through the reducer, so a parallel model type would only add indirection. The raw
  material stays a separate pure layer (`WorkflowStartContext`, assembled by the live client).
- **Start-time `endsRun` skips are never armed.** §9 refuses them at admission; the sheet
  disables the toggle and shows the reason instead of letting Run fail. The consequence is
  recomputed against the other chosen skips, so ordering effects (skipping a reader frees its
  producer) present correctly. `WorkflowRunMachine.startSkipConsequence` exposes the existing
  rule; the in-run Skip path is untouched.
- **A pick-role workflow always presents the sheet**, mirroring the CLI, where `pick` bindings
  are always explicit (`--role r=pN`).
- **Popover rows for validation-failing files are inert** (dimmed, named, with the error
  count); the "dimmed but clickable" rule stays specific to launcher availability warnings,
  which are heuristic — a failing validation is not.
- **The palette lists workflows from a state snapshot refreshed on palette open** — the
  assembler runs on every body evaluation and must not scan the filesystem. In Canvas the
  snapshot uses the reducer-side action target, which matches the palette's own target in
  every case except a Canvas card focused between opening the palette and activating a row.
- **The Active Agents subtitle is replaced, not appended**, while a pane is bound to an active
  run (`in <workflow> · <role>`), synced from `WorkflowRunsFeature` state on every
  `workflowRuns` action; the branch/title subtitle returns when the run ends.
- **The CLI banner's Install acts inline** via the same `CLIInstallClient.install` path
  Settings uses, and a success flips the sheet's own `cliInstalled` gate without reopening.
- **`cliInstalled` treats `installedDifferentSource` as installed** — the slot holds a live
  `prowl`; distinguishing foreign installs is Settings' business, not the sheet's.
- **Keyboard**: the sheet relies on `keyboardShortcut(.cancelAction/.defaultAction)` and
  focusable controls rather than the handoff HUD's swallow-everything key capture, because the
  sheet hosts text fields. Verified live; if keys ever leak to the terminal below, a
  conditional capture view is the follow-up.
- **A dedicated `docs/components/workflows.md` page remains D1's deliverable**; C2 documents
  the entry points in `command-palette.md`, `active-agents.md`, and `agent-profiles.md`.
- **Toolchain note**: reducer bodies in this codebase must spell `some Reducer<State, Action>`
  — `some ReducerOf<Self>` fails to satisfy the `Reducer` conformance under Swift 6.2's
  default-MainActor isolation with no useful diagnostic.

## Out of scope

Settings › Workflows page and authoring skill (D1), built-in workflows (D2), handoff
migration (D3), headless roles and the GUI editor (V2).
