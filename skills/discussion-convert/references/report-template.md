# Report Template — gh-issue:discussion-convert Step 9

Print exactly one line on success, then the steps summary and the
follow-up hint:

```
[OK] Discussion #<N> -> Issue #<M>: <issue-url>
  steps: comment=<on|off|skip|fail>, lock=<on|off|skip|fail>, close=<on|off|skip|fail>, board=<synced|skipped|failed>
Next: /gh-issue:implement <M>
```

The `steps:` line is not composed here — it is stdout from
[`lib/discussion-post-convert.sh`](../../../lib/discussion-post-convert.sh)
(Steps 6-8), printed verbatim. Tokens:

| Token | Meaning |
|-------|---------|
| `on` / `synced` | the mutation ran and succeeded |
| `off` / `skipped` | the matching `--no-*` flag disabled it |
| `skip` | already in that state — the Discussion was closed/locked before this run |
| `fail` / `failed` | attempted and errored; a `[WARN]` naming it went to stderr |

`fail` is not an abort. Steps 6-8 are best-effort by design — see
[`references/post-create-mutations.md`](post-create-mutations.md) — so the
`[OK]` line still prints, because the Issue that satisfies the policy
invariant already exists.

On failure of Steps 1-5 — show the failing step name and quote the
first stderr line from the helper, mirroring the format used by
[[gh-issue:discussion-create]] Step 5.
