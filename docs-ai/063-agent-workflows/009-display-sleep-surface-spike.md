# 063.009 — Display-Sleep Surface Creation Spike

## Status

Accepted investigation, 2026-08-30, in two rounds against `main` at `299b5a5d` (includes
[#744](https://github.com/onevcat/Prowl/pull/744)). Neither round changed production code:
every experimental edit was reverted after the result was established.

The first round concluded that no Ghostty surface can be created while the display is asleep
and recommended a headless fallback. The second round re-verified that claim and **falsified
it**: surface creation only fails because the pinned GhosttyKit makes a CoreVideo display link
a hard precondition of renderer initialization, and Ghostty already exposes the switch
(`window-vsync`) that removes that precondition. Upstream Ghostty fixed the same failure on
2026-08-05. The recommendation below supersedes the first-round one.

This is not an R2a release blocker. The required surface-level fix is implemented in
[#746](https://github.com/onevcat/Prowl/pull/746), which backports the upstream repair into the
GhosttyKit fork. No Prowl-side display override or execution-mode substitution remains planned
for this issue; see [Outcome](#outcome).

## Problem summary

Long-running agent work commonly continues while the Mac display is asleep. In that state, a
CLI-driven Agent Profile launch fails with `CREATE_FAILED`:

> The terminal surface for Agent Profile “…” could not be created.

The unified log shows the native cause:

```text
CVDisplayLinkCreateWithCGDisplays error -6661 due to invalid display count (0)
com.mitchellh.ghostty:embedded_window: error initializing surface err=error.OutOfMemory
```

`pmset -g log` shows `Display is turned off`; waking the display makes the same launch succeed.
The question for both rounds:

> Can Prowl preserve an interactive launch by changing when or how it creates and attaches the
> Ghostty surface while the display remains asleep?

## Current launch boundary

An Agent Profile launch intentionally stages the Swift-side tab/split with
`defersSurfaceCreation: true`, registers the managed signal channel through
`onAgentProfileSurfacePrepared`, and then calls `GhosttySurfaceView.armSurfaceCreation()`.
Failure rolls the tab or split back and becomes `.surfaceCreationFailed`.

This ordering is required for managed hooks: the launch-scoped environment must be prepared
before the child process starts. It also makes the Profile path honest about native creation
failure.

Ordinary tab and split creation use the immediate `GhosttySurfaceView` initializer instead. The
initializer calls `armSurfaceCreation()` but discards its Boolean result. Consequently, the
Swift-side tab or split can be returned even when `ghostty_surface_new` returned `nil`. A visible
tab UUID is therefore not evidence that a working terminal surface exists.

Relevant boundaries:

- `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift`
- `supacode/Infrastructure/Ghostty/GhosttyRuntime.swift` (`loadConfig`, `reloadConfig`,
  `loadTerminalProgramOverrides`, the `screensDidSleep`/`screensDidWake` observers)
- `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`
- `supacode/App/WorkflowRuntimeComposition.swift`
- `ThirdParty/ghostty/src/renderer/generic.zig`, `ThirdParty/ghostty/pkg/macos/video/display_link.zig`

## Method

Both rounds used a separately launched Debug app with a scratch `CFFIXED_USER_HOME`, a scratch
Git repository seeded through `~/.prowl/repository-entries.json`, a hand-written Codex Profile in
`~/.prowl/global.onevcat.json`, and a dedicated `PROWL_CLI_SOCKET`; the installed Prowl instance
and its sessions were not touched. Display state was driven with `pmset displaysleepnow` and
verified from `pmset -g log`; a `caffeinate -u -t 3` wake trap restored the display after each
bounded attempt. Attempts that did not stay inside the logged display-off interval were discarded.

The second round additionally ran a one-second CoreGraphics/CoreVideo probe during every
display-off interval so each result is paired with the display state Ghostty actually saw:

```text
active=0 online=2 main=2 mainAsleep=1 mainActive=0 screens=2 cv[active=-6661 main=0]
```

`CGGetActiveDisplayList` reports zero displays while both displays stay online and
`NSScreen.screens` still lists them. `CVDisplayLinkCreateWithActiveCGDisplays` fails with
`kCVReturnInvalidDisplay` (-6661); `CVDisplayLinkCreateWithCGDisplay(CGMainDisplayID())` still
succeeds. Every pane's health was checked from inside the display-off interval with
`prowl send … --capture` (a dead shell times out with `WAIT_TIMEOUT`), and again after wake.

## Round 1 experiments (Swift-side ordering)

Experimental code lived temporarily on `spike/profile-launch-display-sleep` and was deleted.

| Experiment | Result | Interpretation |
| --- | --- | --- |
| Baseline Profile launch with the display awake | Succeeded | The current #744/Profile/CLI wiring is functional under its normal display precondition. |
| Unmodified Profile launch during a stable display-off interval | Failed with `CREATE_FAILED` at native surface creation | Reproduced the known issue on current `main`. |
| Build the Swift tab/split structure detached, prepare hooks, then attach and arm the surface | Unit test was red before staging and green after it; real tab and split Profile launches still failed while the display was off | Tree attachment and managed-hook ordering are not the cause. |
| Disable deferred creation and create the native Profile surface during initialization | Failed while the display was off | Deferral itself is not the cause. |
| Remove Ghostty `initial_input` and attempt post-create text injection | Failed before input could be delivered | Initial input is not the cause. |
| Remove the Profile launch's `surfaceEnvironment` | Failed while the display was off | Launch-scoped carriers and managed-hook environment are not the cause. |
| Create ordinary tabs and splits with temporary logging at the native boundary | Swift-side creation returned identifiers, but native Ghostty surface creation failed | These paths ignore the failed arm result and leave a non-functional shell. |
| Wake the display and repeat the same Profile launch | Succeeded | The failure follows display availability, not #744's workflow wiring or the selected Profile. |

Round 1 correctly established that Swift-side ordering is irrelevant. Its conclusion that “every
path that ultimately calls `ghostty_surface_new` needs an active display” over-generalized from
the default configuration; it never varied the Ghostty renderer configuration.

## Round 2: where the precondition actually lives

Reading the pinned GhosttyKit (`onevcat/ghostty` at `48365577c`, v1.3.1 plus four fork patches):

- `pkg/macos/video/display_link.zig` — `createWithActiveCGDisplays()` maps **any**
  `CVDisplayLinkCreateWithActiveCGDisplays` failure to `error.OutOfMemory`. The logged
  “OutOfMemory” is this mapping, not memory pressure.
- `src/renderer/generic.zig` (`init`) — `if (options.config.vsync) try
  DisplayLink.createWithActiveCGDisplays() else null`. With `window-vsync = true` (the default)
  the `try` aborts renderer initialization, which aborts `ghostty_surface_new`. With
  `window-vsync = false` no display link is created and the renderer runs in its existing
  change-driven mode (`hasVsync()` returns false; `renderer.Thread` draws after each render and
  on its 8 ms animation timer). Every other use of `display_link` is already `orelse`-guarded.
- `src/config/Config.zig` — `window-vsync` is documented as macOS-only and “changing this value
  at runtime will only affect new terminals”, i.e. the choice is fixed per surface at creation.

Upstream Ghostty removed the precondition in
[ghostty-org/ghostty#13639](https://github.com/ghostty-org/ghostty/pull/13639) (“macos: tolerate
display link creation failures”, merged 2026-08-05, commit `a177ba90af`): display link creation
became lazy and non-fatal (`syncDisplayLink`), retried on the next display-ID update, with
`CreationFailed` replacing the misleading `OutOfMemory`. Follow-ups
[#14035](https://github.com/ghostty-org/ghostty/pull/14035) and
[#14068](https://github.com/ghostty-org/ghostty/pull/14068) (2026-08-26/29) extend the same
`syncDisplayLink` path so the link is also re-synced from rendering activity. None of these are
in a tagged release yet (v1.3.1 is the latest tag; `main` is ~2,400 commits ahead of it). The
patch does not apply cleanly to v1.3.1 because `generic.zig` drifted, but a hand port is about
70 lines and was prepared on a throwaway submodule branch (`zig fmt` clean, deleted afterwards).

Prowl already has the hook the lazy path needs: `GhosttySurfaceView.windowDidChangeScreen()`
pushes `ghostty_surface_set_display_id` on `NSWindow.didChangeScreenNotification`, and
`GhosttyRuntime` observes `screensDidSleep`/`screensDidWake` (currently log-only).

## Round 2 experiments (renderer configuration)

All rows below ran inside logged display-off intervals with the probe reporting `active=0`.

| Experiment | Result | Interpretation |
| --- | --- | --- |
| Unmodified app, default `window-vsync`: `send` to a pane created while awake | Worked (`OFF-A-…` captured) | Existing surfaces keep running while the display sleeps; only creation is affected. |
| Same, `create tab` / `create pane` | Returned identifiers; shells dead (`WAIT_TIMEOUT`), still dead after wake; `READ_FAILED` | Re-confirms round 1: the non-Profile paths hide native failure. |
| Same, Profile launch | `CREATE_FAILED`, log shows `-6661` then `error.OutOfMemory` | Reproduced. |
| Unmodified app relaunched with `window-vsync = false` in the scratch `~/.config/ghostty/config`; `create tab`, `create pane`, Profile launch while dark | **All succeeded**; shells answered from inside the dark interval (`OFF-B-…`, `OFF-C-…`); Codex started in the Profile pane; no Ghostty error lines | The display link is the only native precondition. The same GhosttyKit binary creates fully working surfaces without a display. |
| Wake the display; `send` to those surfaces again; screenshot the window | Worked (`WAKE-B-…`, `WAKE-C-…`); the panes rendered normally | Change-driven rendering is functional after wake, not only while dark. |
| Default config at launch; flip `window-vsync = false` at runtime via Ghostty's `reload_config` (`prowl key … cmd-shift-comma`); go dark; `create tab` and Profile launch | Both succeeded | `GhosttyRuntime.reloadConfig` → `ghostty_app_update_config` is enough to switch the mode for surfaces created afterwards; no relaunch needed. |
| Still dark: flip back to `window-vsync = true` via `reload_config`; probe the earlier panes; `create tab` again | Earlier panes unaffected (`OFF-A2-…`, `OFF-B2-…`); the new tab was a dead shell again | The switch is evaluated per surface at creation time and is safe to toggle in both directions while surfaces are live. |

A locally rebuilt GhosttyKit with the ported upstream fix initially could not be tested: `zig build`
(zig 0.15.2) fails to link its own build runner under Xcode 26.6 (`undefined symbol: _waitpid`,
`_sigaction`, … — libSystem is not linked). The cause is the SDK, not the cache or `SDKROOT`
(zig asks `xcrun --sdk macosx --show-sdk-path`, which ignores `SDKROOT`): from SDK 26.4 on,
`libSystem.tbd` lists `arm64e-macos` instead of `arm64-macos`, and zig 0.15.2's Mach-O linker
cannot match its `aarch64-macos` target to it (ziglang/zig#31658; fixed on the 0.16 line, never
released for 0.15). Xcode 26.3 (SDK 26.2) is the last toolchain that works and is now the
documented requirement in the ghostty fork-sync runbook. Two shortcuts were tried and rejected:
the leftover Command Line Tools 15.4 SDK links the runner but produces objects whose auto-link
metadata no longer resolves against the 26.5 SDK, and a patched 26.5 SDK overlay works but is
not worth maintaining for a toolchain that changes again with the next Ghostty release.

## Conclusion

Surface creation without an active display is possible with the pinned GhosttyKit today, and is
the default behavior of upstream Ghostty since 2026-08-05. The only native precondition is the
eager CoreVideo display link that `window-vsync = true` demands; a surface created with
`window-vsync = false` is a fully working terminal in Ghostty's change-driven rendering mode,
during display sleep and after wake.

Final decision:

- [#746](https://github.com/onevcat/Prowl/pull/746) resolves display sleep at the Ghostty layer;
  no display-specific Prowl launch policy is required.
- “A path that truly works without a display must not create a Ghostty/AppKit terminal
  surface” is withdrawn. Headless execution is no longer justified by display sleep; the
  `on_display_unavailable` policy and the `HeadlessAgentExecutor` scope expansion are dropped
  from this problem's plan (headless stays a V2 topic on its own merits, see
  [the DSL specification](dsl-spec.md#12-reserved-for-v2)).
- Honest propagation of an otherwise unknown native surface-creation failure remains useful
  generic hardening, independent of display sleep and outside the R2a release gate.

## Resolution and residual hardening

### 1. Take the upstream fix into the fork — implemented in #746

The durable fix is upstream #13639: surfaces created without a display get their display link
lazily once a display is available. [#746](https://github.com/onevcat/Prowl/pull/746)
backports it onto `onevcat/ghostty` `release/v1.3.1-patched` (`a0671ce9`), rebuilds GhosttyKit
with Xcode 26.3, and re-pins the prebuilt artifacts. Drop the fork patch when the submodule
moves to an upstream tag that contains `a177ba90af`.

### 2. Prowl-side `window-vsync` override — not planned

Before the GhosttyKit rebuild succeeded, the viable Prowl-only contingency was to detect zero
active displays, create the surface with `window-vsync = false`, and restore the user's setting
afterwards through the existing `GhosttyRuntime.reloadConfig` / `applyConfig` path. The live
spike proved that mechanism works, but #746 makes it unnecessary and avoids its per-surface
non-vsync trade-off.

Do not implement this override while the fork carries the upstream fix. If a future Ghostty pin
regresses, restore or forward-port the upstream behavior first; use this experiment as diagnosis
and a bounded contingency, not as a standing product fallback.

Zero-code interim for users: `window-vsync = false` in the user's Ghostty config removes the
failure on a build that does not yet contain #746.

### 3. Make ordinary tab and split creation honest — optional generic hardening

The non-Profile paths currently ignore the `armSurfaceCreation()` result. Independently of
display sleep, they should eventually roll back the Swift tab/split/target state and return an
honest failure when `ghostty_surface_new` fails for an unknown reason. Profile launches already
do this through `.surfaceCreationFailed`.

Do not add a display-specific `DISPLAY_UNAVAILABLE` contract without a reproducible residual
failure after #746. This hardening is not part of the display-sleep fix or the R2a release gate.

### 4. Workflow semantics

No execution-mode substitution is needed. An interactive role launched while the display sleeps
is the same Ghostty pane with the same `message` / `repeat` / `focus` / `close` semantics. C1
needs no display-sleep fallback state.

## Outcome

With the backport in place, the same live protocol (default `window-vsync`, probe `active=0` for
the whole dark interval) produced the intended result on the rebuilt GhosttyKit: `create tab`,
`create pane`, and a Profile launch all succeeded while dark and answered from inside the
interval; the unified log shows `error creating display link; using fallback rendering
err=error.CreationFailed` for each dark surface and, after wake, `created display link` followed
by `updating display link display id=2` — Prowl's `windowDidChangeScreen` →
`ghostty_surface_set_display_id` is the retry trigger, exactly as upstream intended. The
Prowl-side override is therefore not needed. If a future Ghostty pin regresses, the default
response is to restore this upstream behavior rather than substitute execution modes or retain
a parallel Prowl policy.

## Release impact

R2a remains B3 plus C1 as recorded in [the release plan](release-plan.md#r2a--workflow-engine-and-cli).
Once #746 ships, interactive-workflow verification no longer needs the “keep the display awake”
caveat. Generic native-failure propagation for ordinary tabs/splits remains optional hardening,
not display-sleep work and not an R2a requirement.

## Non-goals of this spike

- No production fallback was implemented; the `window-vsync` runs used the user-config and
  `reload_config` paths only.
- No virtual-display or screen-wake workaround was attempted.
- No fallback was proposed for arbitrary launch failures: hook, Profile, credential, renderer,
  and unknown native failures still fail closed.
- No Prowl-side fallback was implemented or remains planned; the fork backport made it
  unnecessary.

## References

- [063.008 — Workflow Runner Wiring (B3)](008-b3-runner-wiring.md)
- [063 workflow DSL, V2 reservations](dsl-spec.md#12-reserved-for-v2)
- [064.011 — S3c action, original display-sleep finding](../064-agent-completion-signals/011-s3c-action.md#display-sleep-is-the-create_failed-behind-the-intermittent-profile-launches)
- [065.005 — K3 settings and verification note](../065-bundled-agent-skills/005-k3-settings-agent-skills.md)
- [ghostty-org/ghostty#13639 — macos: tolerate display link creation failures](https://github.com/ghostty-org/ghostty/pull/13639)
- [ghostty-org/ghostty#14035 — renderer: park DisplayLink while idle](https://github.com/ghostty-org/ghostty/pull/14035)
