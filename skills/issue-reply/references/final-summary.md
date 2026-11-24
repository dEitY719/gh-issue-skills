# gh-issue:issue-reply — Step 9 report

```
[OK] gh-issue:issue-reply #86 — 7/7 items replied
| key | sev | verdict | reply |
|---|---|---|---|
| codex:0123456789ab:1 | BLOCKER | ACCEPT | <url> |
| codex:0123456789ab:2 | FOLLOW-UP | DECLINE | <url> |
| human:4012345678:0 | NOTE | ACK | <url> |
Body: edited 3f2a…→9c1d… (backup <url>) — §흐름: step 6 now names the backup comment; §수용 기준: +1 criterion
Gate: pass=blockers-resolved:2 -> review-passed
Next: /gh-issue:implement 86
```

## First line

- `[OK] gh-issue:issue-reply #<N> — <k>/<n> items replied` when `k == n`.
- `[FAIL] gh-issue:issue-reply #<N> — <k>/<n> items replied (unreplied: <keys>)`
  when any item is unreplied.
- A HARD stop prints `[FAIL] gh-issue:issue-reply #<N> — stopped at <step>: <reason>`
  and `Next: /gh-issue:issue-reply <N>` once the cause is fixed.

A `[WARN]` (label) never turns the verdict into `[FAIL]`.

## Body line

`Body: edited <old>..<new> (backup <url>) — <per-section summary>`,
`Body: unchanged (no-edit: <flag|not author|exit N>)`, or
`Body: unchanged (no accepted item)`.

## `Next:` line (always last, exactly one)

1. `[FAIL]` → `Next: /gh-issue:issue-reply <N>`.
2. Body edited, or a BLOCKER still held → `Next: /gh-issue:issue-review-all <N>` (re-review the new spec).
3. `review-passed` applied → `Next: /gh-issue:implement <N>`.
4. Otherwise → `Next: /gh-issue:issue-review-all <N>`.
