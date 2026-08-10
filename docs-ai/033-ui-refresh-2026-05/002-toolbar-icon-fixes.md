# 033 — Amendment: Toolbar Icon Fixes (2026-06-17)

## Context

Three weeks after the refresh, a second community contributor, **Alex-ai-future**
(Alex), fixed two toolbar icon papercuts left over from the refreshed chrome:

- Hovering the branch title in the toolbar showed an *additional* pencil icon next to
  the branch icon, shifting the layout.
- The notification bell icon read smaller than its neighboring toolbar elements.

## Change

PR #467 (`fix/toolbar-icon`):

- Branch title icon: on hover, the pencil now *replaces* the icon instead of appearing
  beside it, and the icon frame is fixed at 18×18 so differently-sized SF Symbols can't
  shift the layout (`supacode/Features/Repositories/Views/WorktreeDetailTitleView.swift`).
- Bell icon: the PR initially added `.imageScale(.medium)` and tightened the HStack
  spacing in `ToolbarNotificationsPopoverButton.swift`, but the author reverted that
  part in-PR (`44356552`) before merge — only the branch-title fix landed.

## Refs

- PR #467 (merged 2026-06-17), commits `1ed489ce` (fix) + `44356552` (in-PR revert of
  the bell change).

## Current state

At the time of this fix, `WorktreeDetailTitleView.swift` swapped to `pencil` on
hover inside a fixed 18×18 frame. The branch title view was removed on 2026-08-07 by
[058](../058-unified-toolbar-layout/000-plan.md), which made the hover fix obsolete.
`ToolbarNotificationsPopoverButton.swift` retains its pre-#467 icon styling. The same
contributor's later PRs belong to other entries: #532/#539 →
[028](../028-pr-status-tracking/000-plan.md), #540 →
[003](../003-diff-window/000-plan.md).
