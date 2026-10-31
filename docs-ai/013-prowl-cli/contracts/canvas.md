# `prowl canvas` Contract

## Status

Current version: `prowl.cli.canvas.v1`.

`prowl canvas` switches to and from the Canvas view, applies an automatic layout, fits the
board, and reports the Canvas state. It lets automation lay out the cards it created (#760).

## Input

```bash
prowl canvas show [--json]
prowl canvas hide [--json]
prowl canvas layout <arrange|organize|tile> [--show] [--json]
prowl canvas fit [--show] [--json]
prowl canvas status [--json]
```

The commands accept no target: Canvas shows every open tab of every worktree.

- `show` switches to Canvas; it is a no-op when Canvas is already showing.
- `hide` leaves Canvas for the normal view; it is a no-op when Canvas is hidden.
- `layout` applies an automatic layout and makes it the board's layout mode: Canvas keeps
  applying it as cards are added or closed until a card is moved by hand. `arrange` packs
  cards at their current sizes, `organize` uses a uniform grid, and `tile` resizes cards to
  fill the window. The view refits to show every card.
- `fit` zooms and pans so every card is visible. It does not change the layout mode.
- `layout` and `fit` act on the Canvas view, so they require Canvas to be showing. With
  `--show`, they switch to Canvas first; without it they fail with `CANVAS_NOT_SHOWING`.
- `status` changes nothing.

`show`, `layout`, and `fit` return after Canvas has applied the change (up to a few
seconds). After `layout`, the reported `layout` is the new mode. On a first `show`, Canvas
settles its default layout once it has measured itself, so `layout` may still be absent or
`freeform` in that response; a later `status` reports the settled mode. A request Canvas
did not apply (it closed, or another request replaced it) fails and is never applied later.

## Success

Every action returns the Canvas state after it ran:

```json
{
  "ok": true,
  "command": "canvas",
  "schema_version": "prowl.cli.canvas.v1",
  "data": {
    "action": "layout",
    "showing": true,
    "layout": "tile",
    "card_count": 6
  }
}
```

- `action` echoes the subcommand.
- `showing` is whether Canvas is the current view.
- `layout` is the remembered layout mode: `arrange`, `organize`, `tile`, or `freeform` (cards
  placed by hand). It is absent until Canvas has laid out cards once.
- `card_count` counts open tabs whose terminal exists; each is one card.

Text mode prints one line, for example `Canvas  showing  layout: tile  6 cards`.

## Errors

| Code | Meaning |
| --- | --- |
| `CANVAS_NOT_SHOWING` | `layout` or `fit` while Canvas is hidden, without `--show`. |
| `CANVAS_UNAVAILABLE` | Canvas cannot open: there is no open worktree or folder to show. |
| `CANVAS_FAILED` | Canvas did not apply the change in time, closed first, or received another request first. |
| `INVALID_ARGUMENT` | A socket client sent `layout` without a layout name (the `prowl` parser rejects this before sending). |

Errors use the common error envelope in
[`cli-output-schema.json`](../../../CLI/Sources/ProwlCLIContracts/Resources/cli-output-schema.json).
An app older than the CLI cannot decode the command and closes the connection
(`TRANSPORT_FAILED`); update or restart Prowl.
