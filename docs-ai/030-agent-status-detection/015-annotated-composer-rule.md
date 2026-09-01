# 015 — The annotated composer rule

Amends [014-claude-full-screen-live-block.md](014-claude-full-screen-live-block.md). The
shape-bounded live status block is reached only when the region above the composer is
found, and the border predicate that finds it assumed a rule made of nothing but rule
characters.

## The failing screen

Captured with `prowl read --source detection` while `prowl agents --json` reported the
pane idle, 2026-08-31, with Claude Code 2.1.251 installed:

```text
⏺ Running. On approval, every /apply gate holds on head e53ee7aaf …

✻ Waiting for 1 background agent to finish

──────────────────────────────────── phase-aware-compaction-recovery ─
❯
──────────────────────────────────────────────────────────────────────
  [Fable 5] | ###############-----  78% | $XXX.XX | ⏱️ 1184m 13s | 🟢
  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents

  ⏺ main
  ◯ spec-tree:implementation-au…  Rendering …    10m 5s · ↓ 247.5k tokens
```

Current Claude Code writes the session name into the rule above the composer. Two panes
on this machine carried one and both reported idle with a background agent running; the
panes without one detected correctly, which is what isolates the rule row rather than the
wait row.

`isBoxBorderLine` required every character to be `─` or `-`, so the annotated rule was not
a border. `contentAbovePrompt` then stopped at the composer line instead of the rule, and
the rule became the bottom-most row handed to `liveStatusBlock`. That block walks upward
only while rows look like live chrome, and a rule is not chrome, so it ended on the first
row it saw. The live status region came back empty on every annotated screen — no
spinner, no elapsed row, no background-agent wait row could match, whatever was above.

The failure is silent in the direction that matters least on a still screen and most on a
long one: a Claude waiting on subagents paints no other live marker, so the pane reads
idle for the whole wait.

## Fix

`isBoxBorderLine` also accepts a rule that opens with a run of at least three `─`,
carries one label, and ends in rule characters. The label may not contain `─` itself, and
the ASCII `-` rule is not annotated at all, because a label is ordinary text and routinely
contains a hyphen — treating a dashed row as a border would promote retired transcript
rows into the live block, which is wrong in the direction that reports working after the
work stopped.

`hasIdleComposer` reads the same predicate, so an annotated screen with nothing live above
it now matches `claude.idleComposer` rather than falling through to `noRuleMatched`. The
state is the same; the reason is now explainable.

## Evidence

Four inline cases in `ClaudeBackgroundAgentDetectionTests` pin the wait row, the elapsed
status row, the idle composer, and the rejection of a row whose own text carries rule
characters. No captured fixture was added: the two live screens are third-party session
transcripts whose redaction would have replaced every prose row, and the shape that
reproduces the bug is the rule row alone.
