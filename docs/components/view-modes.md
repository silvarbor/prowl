# View Modes — Normal / Canvas / Shelf

> The same open worktrees, three layouts. Switching modes rearranges the view; it
> never changes your running sessions.

**Keywords:** view mode, layout, normal, canvas, shelf, switch view, toggle canvas, toggle shelf, default view

**Related:** [canvas](canvas.md) · [shelf](shelf.md) · [concepts](../concepts.md) · [repositories-and-worktrees](repositories-and-worktrees.md)

## The three modes

| Mode | Layout | Strength | Toggle |
|------|--------|----------|--------|
| **Normal** | Sidebar of worktrees + the focused worktree's tabs/panes | Deep, focused work on one branch | default (exit Canvas/Shelf) |
| **Canvas** | Zoomable board of live terminal cards | See many agents at once; **broadcast** | `⌘⌥↩` |
| **Shelf** | Vertical "book spines" you flip through | Fast keyboard triage of many worktrees | `⌘⇧↩` |

## How to switch

- **Canvas:** `⌘⌥↩` (`toggle_canvas`), the sidebar Canvas button, or Command
  Palette → "Toggle Canvas".
- **Shelf:** `⌘⇧↩` (`toggle_shelf`), the sidebar Shelf button, or Command Palette →
  "Toggle Shelf".
- **Back to Normal:** toggle the active mode off, or select a worktree in the
  sidebar.

Toggling Canvas or Shelf with **no open worktrees** does nothing.

## What's preserved across switches

- Your running terminals, tabs, and panes are untouched.
- Canvas persists card positions/sizes/z-order across launches.
- Entering Shelf keeps your current worktree open (or jumps to the first available
  one if you were on Canvas / archived / nothing).
- Exiting Canvas returns you to the focused card's worktree, the worktree you had
  before Canvas, your last focused worktree, or the first available — in that
  order.

## Launch behavior

`defaultViewMode` (Settings) chooses which mode Prowl opens in:
`normal`, `shelf`, or `canvas`.

`canvasDefaultLayout` (Settings) chooses the layout a fresh Canvas starts in:
`uniform` (same-size cards packed to fit) or `tile` (resize cards to fill the
screen — the default). Canvas then keeps whichever layout you choose last.

## Which to recommend

- Supervising a fleet / sending the same command everywhere → **Canvas**
  ([details](canvas.md)).
- Cycling agents one-by-one with the keyboard → **Shelf** ([details](shelf.md)).
- Heads-down on a single branch → **Normal**.
