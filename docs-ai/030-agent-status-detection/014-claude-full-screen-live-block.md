# 014 — Claude full-screen input and the shape-bounded live status block

Amends [009-captured-screen-fixture-corpus.md](009-captured-screen-fixture-corpus.md) and
[012-claude-screen-profile.md](012-claude-screen-profile.md): the "canonical 24-line
detector tail" contract those records describe now applies to **non-Claude agents
only**. Claude detection consumes the full active screen, and the Debug canonical-tail
assert on `AgentScreenSnapshot` was replaced by a single production construction seam.

## Problem

Two bottom-measured budgets could each cut the live signal off:

1. The shared detector tail (`agentDetectionRecentText`, 24 non-empty lines from the
   bottom). On a Claude screen the bottom is fixed chrome — composer, multi-line
   statusline — plus the todo block under the spinner row. Past ~16 todo lines the
   spinner fell out of the window and a working agent read as idle
   (`claude.idleComposer`).
2. The live status region itself, previously `claudeLogicalRows(above prompt).suffix(3)`.
   The committed 2.1.223 `foreground-spinner` fixture already had zero slack (spinner,
   queued `❯` message, `◉ xhigh · /effort`): one more queued message or `⎿ Tip:` row
   displaced the spinner even with the tail removed.

Both are the same defect: bounding a region the TUI sizes dynamically by a fixed count
measured from the bottom.

## Fix

- `DetectedAgent.detectionScreenText(from:)` forks the slice policy: Claude gets the
  full active screen (naturally bounded by terminal height via `GHOSTTY_POINT_ACTIVE`);
  every other agent keeps the bounded tail as its guard against transcript history.
- `DetectedAgent.detectionSnapshot(from:)` is the one production entry point for
  building a profile snapshot, so state detection and blocker extraction always read
  the same slice (`detectScreen` and the `agents read` CLI path both go through it).
- The Claude live status region is bounded by **shape, not count**
  (`ClaudeScreenRegions.liveStatusBlock`): logical rows above the composer are taken
  bottom-up while they look like live chrome — spinner-scalar heads, `●` status rows,
  `⎿` attachments, queued `❯` messages, todo checkboxes — and the scan stops at the
  first transcript-shaped row (`⏺` blocks, `◯` rows, prose, borders).

The stop condition is what replaces the tail's false-positive guard: a status row
quoted inside a `⏺` block or prose sits above a non-chrome row, so the walk never
reaches it. Known residual (accepted, present in every prior version too): a quoted
status row that is itself the bottom-most logical row above the composer — with only
chrome-shaped rows below it — still reads as live. Rules stay strict (`…` + complete
elapsed segment), so completed rows like `✻ Crunched for 7s` never match.

## Codex

Codex's structured profile is region-anchored like Claude's and shares the
bounded-bottom exposure in principle (its working footer has zero slack; a ~17-line
approval dialog can push the question out of the tail). It keeps the tail until its
regions are bounded by shape the same way; the `detectionScreenText` doc comment
records this, and `detectionScreenTextSlicesPerAgent` pins the current asymmetry.

## Corpus contract

- Claude fixtures are full active screens: commit captures as read, never trimmed
  (trimming can delete the row above the window that reproduces the bug). The corpus
  check enforces the one mechanical invariant — line count ≤ captured terminal rows.
- Non-Claude fixtures remain exact `agentDetectionRecentText` tails, checked as before.
- The existing 2.1.22x Claude fixtures predate this change and are tail-shaped; they
  stay valid as detector inputs (the detector accepts any screen) but new Claude
  captures must be full screens. Capture step 6 in the fixture README describes the
  per-agent reduction.
