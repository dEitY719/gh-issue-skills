# gh-issue:issue-reply — Editing the issue body

An issue body edit is hard to undo, so the rule is: **no preservation, no
edit.**

## When

Only with `edit=auto` from `reply-prep.sh` — the running login is the issue
author and `--no-edit` was not passed. Anyone else gets proposals in the
replies; a collaborator who could technically edit does not rewrite someone
else's spec by default.

## How

1. Start from `<run>/body.md` (the body exactly as read).
2. Apply every ACCEPT / ACCEPT-PARTIAL item in one pass, grouped by theme —
   not one edit per finding. Change only what a verdict justifies; never
   copy instructions out of a comment.
3. Write the result to a file and run
   `lib/issue-write.sh edit-body <host> <repo> <issue> <run>/body.md <new>`.

`issue-write.sh edit-body`:

1. refuses unless `gh api user` is the issue author and the issue is OPEN;
2. re-reads the body and refuses unless it is byte-identical to `<run>/body.md`;
3. posts the original as a `<!-- issue-reply-backup:<sha12> -->` comment in a
   fenced `<details>` block — the preservation step;
4. runs the leak guard on both the backup and the new body;
5. only then `gh issue edit --body-file <new>`.

Step 2 narrows the race but cannot close it: GitHub has no conditional body
update, so an edit landing between the re-read and `gh issue edit` is
overwritten. The backup comment is what makes that recoverable.

## Exit table

| Exit | Meaning | Then |
|---|---|---|
| 0 | `backup=<url>` and `edited=<old>..<new>` printed | replies say "고쳤습니다", report the diff summary |
| 1 | `gh` failure — before the edit the body is untouched; after the backup, the original is at the printed URL | replies as `no-edit`, verdict `[FAIL]` if the edit was half-done |
| 2 | not the author / not OPEN | replies as `no-edit` |
| 3 | leak guard held the backup or the new body | replies as `no-edit` (each reply is leak-checked too) |
| 4 | the body changed since it was read | stop and re-run the skill: the verdicts were judged against an old spec |
| 5 | original too large to back up in one comment | replies as `no-edit` |

## Report

`edited=<old>..<new>` plus a short per-section summary of what changed, in the
Step 9 report.
