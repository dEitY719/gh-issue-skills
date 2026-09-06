# Post-Create Mutations — gh-issue:discussion-convert Steps 6-8

All three run **after** the Issue exists (Step 5), and all of them live in
[`lib/discussion-post-convert.sh`](../../../lib/discussion-post-convert.sh)
rather than in this file. Nothing about the ordering or the skip logic needs
judgment, so the skill calls the script instead of re-deriving it:

```bash
export TARGET_REPO DCLOSED DLOCKED   # Step 1 / Step 2
STEPS=$(bash "$PLUGIN_ROOT/lib/discussion-post-convert.sh" \
    "$DISC_ID" "$ISSUE_NUMBER" \
    "$OPT_NO_COMMENT" "$OPT_NO_LOCK" "$OPT_NO_CLOSE" "$OPT_NO_BOARD_SYNC")
```

`PLUGIN_ROOT` is exported by `lib/resolve-target.sh` in Step 1 — never compose
this path from `$PWD` (dEitY719/harness-skills#22). `GH_HOST` is inherited from
the same step; `gh api graphql` takes no `--repo`, so it is the Discussion
half's only host selector.

Stdout is the one `steps:` line Step 9 prints verbatim. Failures go to stderr
as `[WARN]`, and the script **always exits 0** — see "Best-effort" below.

## What the script does

| Step | Mutation | Skipped when |
|------|----------|--------------|
| 6 | `_gh_project_status_sync issue <M> "In progress" --only-from "Backlog,Ready" --repo "$TARGET_REPO"` | `--no-board-sync` |
| 7 | `_gh_discussion_comment "$DISC_ID"` with body `Linked to issue #<M> -- decision tracked there.` | `--no-comment` |
| 8 | `_gh_discussion_close "$DISC_ID" RESOLVED` | `--no-close`, or `DCLOSED=true` |
| 8 | `_gh_discussion_lock "$DISC_ID"` | `--no-lock`, or `DLOCKED=true` |

Step 6's helper is a no-op on repos with no project board attached, and
`--only-from` keeps an already-progressed card from bouncing back to
`In progress`. `--repo` is explicit (dEitY719/dotfiles#1405): without it the
helper resolves via `gh repo view`, i.e. `gh repo set-default`'s pick rather
than the remote this run resolved.

Step 7 is the reverse half of the bidirectional backlink; the forward half
(Issue body -> Discussion) is already on the Issue from Step 5.

## Best-effort, and why it is now testable

A failure emits a warning but never rolls back the new Issue — the policy
invariant "Issue must exist with backlink" is already satisfied by Step 5, and
rolling the Issue back because a board sync flaked leaves the user strictly
worse off (Discussion still open, no Issue, work lost).

That used to be a promise in prose. It is now an assertion:
`lib/discussion-post-convert.selfcheck.sh` runs the script against stub helpers
whose exit codes it controls, and requires exit 0 plus
`comment=fail, lock=fail, close=fail, board=failed` when all four error. It
also pins the call order, the per-flag skips, and the tier-5 refusal to source
`lib/vendor/shell-common` from the cwd. `tests/lib-selfchecks.sh` runs it in CI.
