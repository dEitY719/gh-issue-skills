# gh-issue:proceed — Reporting (Step 4)

## Verdict line (always first)

One line, derived from the Outcome section below, before the per-step table:

```
[OK] gh-issue:proceed #<N> — <k>/<m> done_criteria met, issue closed
[FAIL] gh-issue:proceed #<N> — aborted at step <i> (Layer-<n>: <pattern>)
[WARN] gh-issue:proceed #<N> — <k>/<m> done_criteria met, issue kept open
```

## Per-step audit (always)

| # | Step | Result | Classification | Verb applied | Duration |
|---|---|---|---|---|---|
| 1 | help | PASS | PASS | continue | 4s |
| 2 | stock list 1 10 | FAIL-CLI | FAIL-CLI | file_issue: #NN | 12s |
| ... | | | | | |

## Write-action audit

```markdown
### Write actions executed
| # | Action | Target | Triggered by step | Triggered by rule |
|---|---|---|---|---|

### Blocked attempts
(none) | <list>

### Aborts
(none) | reason: <layer-N pattern>
```

## Done-criteria reconciliation

Compare the §done_criteria checklist to actual step outcomes. Any unchecked
item lists the reason (`step skipped: SKIP-NET`, `ambiguous match`, etc.).

## Outcome

| All done + no abort | Partial | Abort |
|---|---|---|
| `close_issue: <self>` + final comment | keep-open + final comment `N/M criteria met` | keep-open + final comment `[aborted] <layer> <pattern>` |

## Next (always last, before ai-metrics)

Keyed to the outcome row above:

- Fully met, closed — `Next: gh pr list --repo "$TARGET_REPO"` to review
  whatever the protocol filed, or nothing if no write actions ran.
- Partial — `Next: /gh-issue:proceed <N>` after resolving the unmet criteria
  named in the reconciliation table.
- Aborted — `Next: /gh-issue:read <N>` and fix the directive; an abort is a
  caller-side problem, not something a retry alone fixes.

A schema-validation failure (Step 2.2) never reaches this report — it stops
first with its own §4 failure block, which carries `Next: /gh-issue:read <N>`
too.

## ai-metrics

Appended after the report (omit entirely when `GH_DISABLE_AI_METRICS=1`):

```
[ai-metrics:gh-issue-proceed] ~{ELAPSED} min — write actions: {N}, blocked: {M}
```

The proceed issue thread is the single audit surface: the per-step table,
the write-action audit, and the done-criteria reconciliation together let a
human reconstruct exactly what the skill did and why, without re-reading
the transcript.
