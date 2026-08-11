# 013 — Background-agent wait rule and wrapped status rows

Amends [012-claude-screen-profile.md](012-claude-screen-profile.md), which states that
"No subagent-wait rule was added because no captured failing screen supports one." A
failing screen now exists, and adding the rule exposed a second defect that affects every
row-based rule in the Claude profile.

## The failing screen

Captured with `prowl read --source detection` against Claude Code 2.1.224, sampling
`prowl agents --json` at the same instant as the read:

```text
● Perusing… (1m 38s · ↓ 187 tokens)          ->  agents: done
✻ Waiting for 1 background agent to finish   ->  agents: done
```

The corpus subagent fixtures retain a live spinner because Claude was still working
alongside the subagent. The failing state is the one *after* its own turn ends: the
spinner is replaced by the wait row, which carries a spinner glyph but no `…`, so
`hasSpinnerActivity` rejects it.

The second row is a separate defect. `hasElapsedStatusLine` required a one-word label and
a single `<digits><unit>` token, so a correctly shaped row detected for 59 seconds and
then reported idle for the rest of the turn.

## Why the profile migration preserved both

Neither rule had a captured witness. `claude.elapsedStatus` and `claude.backgroundWork`
were exercised only by inline synthetic screens, and those screens were written from the
same assumptions as the predicates they test — a single-word label with a single elapsed
token, and a row containing the literal `agents done`. A test that restates its
implementation cannot falsify it.

Meanwhile every captured Claude working fixture retains a spinner, so `claude.spinner`
returns first and shadows `claude.elapsedStatus` before it can be observed being wrong.

`AgentScreenRuleCoverageTests` now asserts that every typed rule is fired by at least one
non-quarantined captured fixture. It would have flagged both rules on the day the corpus
landed.

## The switcher block is not a liveness signal

The `⏺ main` plus `◯` block below the prompt is the obvious way to detect background
agents, and it is wrong. A subagent that returns control while it still awaits collection
keeps its row, with the elapsed value frozen at the moment it stopped:

```text
⏺ Agent "Sleep 300 then reply" finished · 1m 54s
...
  ⏺ main
  ◯ general-purpose  Sleep 300 then reply    1m 54s · ↓ 23.0k tokens
```

Observed live on 2.1.224. A single frame cannot separate that from a running agent, so
matching the row shape holds the pane at working after the work has stopped — a worse
failure than the one being fixed, because it is wrong in the direction that hides real
idleness. The rule keys on the wait row instead, and the retained-row case is pinned by
`ClaudeBackgroundAgentDetectionTests.retainedAgentRowAloneDoesNotReportWorking`.

## Wrapped rows

Every rule in the profile read one physical line. Claude wraps a row too wide for the pane
onto continuation lines indented two spaces. Observed at 40 columns on 2.1.225:

```text
✻ Waiting for 1 background agent to
  finish
```

Narrow split panes are ordinary in Prowl, so both rules missed their own captured screens
at realistic widths. Rows are now assembled into logical rows before matching: an adjacent
line indented past its head and starting with ordinary text is a continuation, while a
line opening with its own marker starts a new row. That bound keeps continuation joining
from stitching together rows that were never on screen.

Two related shapes came out of the same narrow-terminal session and are covered by tests:

- At 32 columns Claude *shortens* the row instead of wrapping it, dropping the detail
  segments entirely and leaving `● Razzle-dazzling… (1m 7s)` — an elapsed terminated by
  the closing paren with no `" · "` at all.
- The label is free text and contains parentheses, so the elapsed segment is located from
  the end of the row. Anchoring at the first `(` reads `focused)… (1m 38s` as the elapsed
  and rejects `● Running tests (focused)… (1m 38s · ↓ 187 tokens)`.

Assembling rows is not enough on its own, because the region that selects which rows the
rules see was still counted in physical lines. `ClaudeScreenRegions.liveStatus` took the
last three non-blank lines above the box and only then handed them to the row assembler,
so a row wrapping onto three or more continuations pushed its own head out of the window.
The head is what carries the `●` or the spinner, so the reconstructed row could not match
and the pane reported idle. Surfaces that narrow are reachable, and the shape is not
exotic: `✻ Waiting for 1 background agent to finish` needs only about twenty columns to
wrap that far. The region is now assembled into logical rows first and limited to the last
three of those, which is the same three rows whenever nothing wraps.

## Result

`claude.backgroundWork` matches the wait row in the live status region, keeping the
existing below-prompt `agents done` workflow marker. `claude.elapsedStatus` accepts a
free-text label and a compound elapsed segment, located from the end of the logical row.
Both read logical rows rather than physical lines, and so does the live status region that
feeds them. Two captured fixtures under
`claude/2.1.224/working/` witness the rules, and a narrow capture covers the wrapped shape.
