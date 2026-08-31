# CLI Contract: `prowl send`

> Living normative contract of entry 013. Migrated from `doc-onevcat/contracts/cli/send.md` on 2026-07-12; update in place.

Status: draft truth source for `#67`.

This file defines the **JSON output contract** for:

- `prowl send ... --json`

## Contract goals

- `send` must report **where** text was delivered and **how** it was delivered.
- JSON output must never echo the full text payload back by default; scripts often send secrets, prompts, or long commands.
- The success payload must describe whether Enter was sent and whether the command had to create a tab first.

## Supported targeting

`send` uses the shared generic target grammar in [targeting.md](targeting.md),
including `pN` / `tN` in `--target` and target-first positional forms. With one
positional argument, `send p12` remains text for the focused pane; target-first
send requires `send p12 'text'`.

## Supported input forms

- positional text argument
- stdin text
- `--no-enter`, `--no-wait`, `--capture`, and `--timeout <1...300>`

`--capture` is shipped behavior. It requires shell integration, sends Enter, and
cannot combine with `--no-wait` or `--no-enter`.

## Wait behavior

By default, `send` waits for the delivered command to finish before returning. This relies on shell integration (OSC 133) to detect command completion. When the command finishes, the response includes exit code and duration.

- `--no-wait`: return immediately after text delivery without waiting for completion.
- `--timeout <seconds>`: maximum time to wait (default: 30, range: 1–300). Ignored when `--no-wait` is used.
- If the terminal does not have shell integration enabled, the wait will time out and return `WAIT_TIMEOUT`.

### Input source semantics

`data.input.source` is **inferred from where the accepted payload came from**. It is not a separate `--source` flag.

- `"argv"`
  - means the payload came from the positional text argument of `prowl send`
  - typical trigger: `prowl send "echo hello"`
  - use for short, explicit, human-authored inline sends
- `"stdin"`
  - means the payload came from process stdin, usually via a pipe or redirection
  - typical trigger: `printf 'echo hello\n' | prowl send`
  - use for multiline text, generated text, file/pipe input, or payloads you do not want to expose inline in shell history

## Success payload

```json
{
  "ok": true,
  "command": "send",
  "schema_version": "prowl.cli.send.v1",
  "data": {
    "target": {
      "worktree": {
        "id": "Prowl:/Users/onevcat/Projects/Prowl",
        "name": "Prowl",
        "path": "/Users/onevcat/Projects/Prowl",
        "root_path": "/Users/onevcat/Projects/Prowl",
        "kind": "git"
      },
      "tab": {
        "id": "2FC00CF0-3974-4E1B-BEF8-7A08A8E3B7C0",
        "title": "Prowl 1",
        "selected": true
      },
      "pane": {
        "id": "6E1A2A10-D99F-4E3F-920C-D93AA3C05764",
        "title": "zsh",
        "cwd": "/Users/onevcat/Projects/Prowl",
        "focused": true
      }
    },
    "input": {
      "source": "argv",
      "characters": 10,
      "bytes": 10,
      "trailing_enter_sent": true
    },
    "created_tab": false,
    "wait": {
      "exit_code": 0,
      "duration_ms": 1234
    }
  }
}
```

## Required top-level fields

- `ok`: boolean, must be `true` on success.
- `command`: string, must be `"send"`.
- `schema_version`: string, currently `"prowl.cli.send.v1"`.
- `data`: object.

## `data.target` shape

### `worktree`

- `id`: string
- `name`: string
- `path`: string, absolute path
- `root_path`: string, absolute path
- `kind`: `"git"` | `"plain"`

### `tab`

- `id`: string, UUID text form
- `title`: string
- `selected`: boolean, should be `true` when the target tab is also the selected tab

### `pane`

- `id`: string, UUID text form
- `title`: string
- `cwd`: string or `null`
- `focused`: boolean

## `data.input` fields

- `source`: `"argv"` | `"stdin"`
  - `"argv"`: accepted payload came from the positional command argument
  - `"stdin"`: accepted payload came from stdin
  - the reported value must match the actual accepted payload source
- `characters`: integer, count of Unicode scalar content accepted for delivery
- `bytes`: integer, UTF-8 byte count of content accepted for delivery
- `trailing_enter_sent`: boolean
  - `true` for default behavior
  - `false` when `--no-enter` is used

## `data.created_tab`

- boolean
- `true` only when targeting a worktree that had no current tab and Prowl had to create one before sending.

## `data.wait`

- object or `null`
- `null` when `--no-wait` is used (fire-and-forget mode).
- When present (default behavior), contains:
  - `exit_code`: integer or `null`. The command's exit code reported by shell integration (OSC 133;D). `null` if the shell did not report an exit code.
  - `duration_ms`: integer. Wall-clock time in milliseconds from text delivery to command completion.

## Output invariants

- The payload must describe the **resolved pane** that received the text.
- The payload must **not** include the original text body.
- If stdin is empty, the command should fail instead of pretending that an empty payload was delivered.
- `characters` and `bytes` refer only to the text payload, not the synthetic Enter keypress.

## Error payload

```json
{
  "ok": false,
  "command": "send",
  "schema_version": "prowl.cli.send.v1",
  "error": {
    "code": "EMPTY_INPUT",
    "message": "No text payload was provided"
  }
}
```

## Error codes for v1

- `APP_NOT_RUNNING`
- `INVALID_ARGUMENT`
- `TARGET_NOT_FOUND`
- `TARGET_NOT_UNIQUE`
- `EMPTY_INPUT`
- `SEND_FAILED`
- `WAIT_TIMEOUT`
- `CAPTURE_UNSUPPORTED`

## Notes

- `send` is text delivery, not general key simulation. Control inputs such as `ctrl-c` belong to `key`.
- Returning byte and character counts gives scripts enough confirmation without leaking payload contents into logs.
- A future implementation may add optional debug echo flags, but v1 default JSON must stay redaction-friendly.
- Wait behavior depends on shell integration (OSC 133). Without it, `onCommandFinished` never fires and the wait will time out. The `WAIT_TIMEOUT` error message should hint at this possible cause.
- `--no-wait` combined with `--no-enter` is the purest "paste text" mode — no Enter, no waiting.
- `--capture` returns `capture` with `text`, `line_count`, `source: "screen_diff"`,
  and `truncated`; it is omitted when capture was not requested. Capture requires
  shell integration and fails with `CAPTURE_UNSUPPORTED` when unavailable.

## Example: stdin + `--no-enter`

```json
{
  "ok": true,
  "command": "send",
  "schema_version": "prowl.cli.send.v1",
  "data": {
    "target": {
      "worktree": {
        "id": "Prowl:/Users/onevcat/Projects/Prowl",
        "name": "Prowl",
        "path": "/Users/onevcat/Projects/Prowl",
        "root_path": "/Users/onevcat/Projects/Prowl",
        "kind": "git"
      },
      "tab": {
        "id": "2FC00CF0-3974-4E1B-BEF8-7A08A8E3B7C0",
        "title": "Prowl 1",
        "selected": true
      },
      "pane": {
        "id": "6E1A2A10-D99F-4E3F-920C-D93AA3C05764",
        "title": "Claude",
        "cwd": "/Users/onevcat/Projects/Prowl",
        "focused": true
      }
    },
    "input": {
      "source": "stdin",
      "characters": 24,
      "bytes": 24,
      "trailing_enter_sent": false
    },
    "created_tab": false,
    "wait": {
      "exit_code": 0,
      "duration_ms": 350
    }
  }
}
```

## Example: `--no-wait` (fire-and-forget)

```json
{
  "ok": true,
  "command": "send",
  "schema_version": "prowl.cli.send.v1",
  "data": {
    "target": {
      "worktree": {
        "id": "Prowl:/Users/onevcat/Projects/Prowl",
        "name": "Prowl",
        "path": "/Users/onevcat/Projects/Prowl",
        "root_path": "/Users/onevcat/Projects/Prowl",
        "kind": "git"
      },
      "tab": {
        "id": "2FC00CF0-3974-4E1B-BEF8-7A08A8E3B7C0",
        "title": "Prowl 1",
        "selected": true
      },
      "pane": {
        "id": "6E1A2A10-D99F-4E3F-920C-D93AA3C05764",
        "title": "zsh",
        "cwd": "/Users/onevcat/Projects/Prowl",
        "focused": true
      }
    },
    "input": {
      "source": "argv",
      "characters": 5,
      "bytes": 5,
      "trailing_enter_sent": true
    },
    "created_tab": false,
    "wait": null
  }
}
```
