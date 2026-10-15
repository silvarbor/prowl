# 023.004 — Shelf Book-Switch Performance

## Plan and scope (2026-10-11)

Baseline: `4d82ae39`. The user reported renewed spine animation stalls. Preserve the
200 ms book motion, terminal gap layout, focus, menus, and status cues. Investigate
observation fanout, animation-driven descendant work, and main-thread background work
with an isolated multi-book fixture before choosing a change.

The April findings remain in [jank-investigation.md](jank-investigation.md) and
[002-book-switch-jank.md](002-book-switch-jank.md). Their cause-edge counts and timings
are historical, not comparable to current update counts. The earlier structural fixes
remain present. Original April trace files were not found in the searched local archives.

## Decision

Apply `ShelfSpineMotion` to each complete spine in the existing `ForEach`:

```swift
content
  .transaction { $0.animation = nil }
  .geometryGroup()
```

The outer geometry group retains the ancestor's movement animation. The inner transaction
commits selection tint, active-tab proximity highlights, and footer layout immediately.
Descendants can still supply a local animation, including the existing hover feedback.
Modifier order is part of the contract; reversing it would suppress book movement.

This is a deliberate, small UX tradeoff: selection chrome no longer interpolates during
book movement. The original `HStack`, terminal insertion, view identity, menus, keyboard
routing, and terminal lifecycle remain unchanged. There is no new native host, custom
layout, task, queue, or cross-actor state.

## Evidence

Measurements use macOS 27.0.1, Xcode 27.0, Debug builds, and 12 logical CPU cores. The
isolated fixture has 10 plain-folder books, four real idle terminal tabs each, a 1000 ×
700 pt window, 320 pt sidebar, English, dark mode, and Agent Island disabled. Warm all
books, start at Book-01, send 20 next-book and 10 previous-book shortcuts, and wait 350 ms
after each key event. No builds or exports run during a timed workload.

The original app's fresh trace has 31 Shelf body events and 350 spine body events for
30 selections. There is no evidence that the earlier broad body-invalidation problem
returned. Much more work occurs below those bodies during animation.

Final pair, 30 validated selections each:

| Metric | Original | Final | Change |
| --- | ---: | ---: | ---: |
| Total SwiftUI updates | 1,201,736 | 779,346 | -35.1% |
| Animated-frame updates | 71,547 | 12,997 | -81.8% |
| View responder updates | 114,843 | 91,827 | -20.0% |
| Preference-list updates | 100,806 | 35,733 | -64.6% |
| Layout Updates | 41,113 | 41,615 | +1.2% |
| Shelf body events | 31 | 43 | +12 |
| Spine body events | 350 | 360 | +10 |
| Terminal make / update / dismantle | 30 / 60 / 30 | 30 / 60 / 30 | Unchanged |
| Instrumented hitch overlap, ms/selection | 175.0 | 164.9 | -5.8% |

The gain is in descendant animation work, not fewer root bodies or layout queries.
Root body counts vary across captures (the first original run had 46); do not claim a
body-count reduction. The modest hitch change does not establish hitch-free rendering.

Untraced process CPU for the same 30 switches:

- Original: 9.75 / 9.70 / 9.84 s; a later restart control measured 9.49 s.
- Selected boundary as an inline spike: 7.56 / 7.60 / 7.66 s.
- Final extracted modifier: 7.17 / 7.15 / 7.31 s.

The direction reduces CPU by roughly 22–26% in this fixture. Process CPU includes all
app threads and is not selection latency. The later baseline moved 2.7%; host variation
still prevents treating one percentage as a universal guarantee.

Native main-thread sampling attributes 3,943 of 7,006 original samples to
`NSHostingView.layout`, versus 3,004 of 6,531 final samples. The repository core reducer
accounts for only 22 and 11 samples, respectively. These are inclusive samples, not
calls; symbols overlap. Layout remains substantial, so this change does not establish
that all remaining hitches are resolved.

## Rejected alternatives

- Geometry group alone: animated-frame updates fell, but total updates did not.
- A separate `NSHostingView` per spine, with or without a plain NSView container:
  total graph updates fell, but Layout Updates grew from about 41,000 to 129,000–139,000.
- Fixed custom layout: intermediate frames exposed terminal/spine overlap and edges.
- Unanimated inner VStack: reduced CPU by about 18%; the whole-spine boundary did better.
- Disabling terminal-host intrinsic sizing: no CPU improvement.
- A fixed spine row with visual offsets: no CPU improvement despite extra structure.
- Root `containerRelativeFrame(.vertical)`: caused a window constraint-update loop in
  the isolated spike. Reverted before measurement.

Only the selected boundary remains. No separate background-work change was justified by
this workload. Raw spikes and the full report stay outside the repository.

## Validation

The real AppKit-hosted regression fixture checks movement interpolation in both directions,
immediate selection chrome, one native-view mount, and independent hover interpolation.
Geometry group alone fails the chrome assertion; the final boundary passes. The focused
motion, Shelf feature, ordering, and command-key suites pass all 49 tests.

`make check` passes, including 241 script tests, formatting, lint, naming, and localization.
`make build-app` passes. UI acceptance covers closed-book tab menus and selection, split
round trips and focus, tab shortcuts, closed-book tab creation, colored spines, a 25-tab
scrolling list with pinned controls, and window zoom/restore. Raw recordings and keyframes
are linked from the local report.

Limits: one machine and OS, Debug builds, idle shells, no active-agent/status workload,
no Release FPS or energy claim. Full SwiftUI tracing distorts timing and still reports
hitches. Layout-update records are not native layout calls, and cause edges are not calls.

## Repeatable trace recipe

Use a separate `PROWL_DEBUG_DATA_DIRECTORY` and `PROWL_CLI_SOCKET` for the fixture. Keep
book/tab count, window, warm-up, key sequence, delay, and instrumentation identical. Record
the target PID and load. The 2026-10-11 raw fixture, app snapshots, and measurements live
under `~/Library/Logs/Prowl/measurements/shelf-20261011/`.

Write `recording-options.json` with `{"SwiftUI":{"enableLayoutTracing":true}}`, then:

```bash
xcrun xctrace record --template SwiftUI --instrument 'Points of Interest' \
  --recording-options recording-options.json --attach "$PROWL_PID" \
  --time-limit 22s --output run.trace --no-prompt
```

Start the 30-switch sequence about 2.5 seconds after capture begins. Wait for trace
finalization before export; it can take several minutes. Export each table:

```bash
xcrun xctrace export --input run.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"][@category="PointsOfInterest"][1]' \
  --output signposts.xml
xcrun xctrace export --input run.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="swiftui-updates"]' \
  --output updates.xml
xcrun xctrace export --input run.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="hitches"]' \
  --output hitches.xml
python3 scripts/shelf_trace_summary.py \
  --signposts signposts.xml --updates updates.xml --hitches hitches.xml \
  --expected-switches 30 --settle-ms 350 --output counts.json
```

The parser resolves xctrace references, rejects missing/extra selection events, excludes
startup, includes the final animation tail, and clips hitch intervals to the same window.
Keep the first Points of Interest table to avoid duplicate events. Compare counts per
selection; frame-dependent counts still vary with scheduling. Use untraced CPU repeats
and recordings as separate evidence, not instrumented durations as product latency.
