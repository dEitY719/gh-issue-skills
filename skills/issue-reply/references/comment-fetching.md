# gh-issue:issue-reply — Comments, items and markers

## One endpoint

`lib/reply-prep.sh` reads `repos/<repo>/issues/<N>/comments --paginate` once,
joined with `jq -s 'add // []'`, and keeps the **raw** array
(`<run>/comments.json`: `id`, `user.login`, `body`, `html_url`). An issue has
no inline comments and no review summaries, so unlike `gh-pr:reply` there is
nothing else to fetch. Never reduce it to bodies first: the author is what
makes a marker trustworthy.

## Items (`lib/split-review-items.sh`)

`<run>/items.tsv`, one line per item:

```
<key>  <severity>  <status>  <current>  <comment-id>  <author>  <text>
```

| Source | key | severity |
|---|---|---|
| a `[BLOCKER]` / `[FOLLOW-UP]` / `[PRAISE]` line inside a trusted review block | `<ai>:<hash12>:<idx>` (idx 1-based, in line order) | the tag |
| a trusted review block with no tagged line | `<ai>:<hash12>:0` | `NOTE` |
| any other comment | `human:<comment-id>:0` | `NOTE` |

`status` is `open` or `replied:<VERDICT>`. `current` is `1` for items of the
latest trusted review of that `<ai>` (and for human items). Only items that
are `open` **and** `current=1` are answered — `reply-prep.sh`'s `open=` counts
exactly those; a superseded review's findings are covered by its successor. A
review posted twice with the same `<ai>:<hash12>` yields items once. The full comment is in `comments.json` by id — read it
there; `text` is cut to 300 characters.

## Trust (acceptance criterion 6)

A review block is `<!-- ai-issue-review:<ai>:<hash12> -->` …
`<!-- /ai-issue-review:<ai>:<hash12> -->`, the format the
`gh_issue_review` engine writes for `gh-issue:issue-review-all`. It is trusted
only when the comment's `user.login` is the expected login
(`GH_ISSUE_REPLY_TRUSTED_LOGIN`, else `gh api user`) **and** the closing
marker is present. Anyone can type the marker, so a forged block from another
account is treated as a plain human comment: one `NOTE` item, and its
`[BLOCKER]` lines never reach the label gate. Same rule as `gh-pr:reply`'s
marker-authorship check (dEitY719/dotfiles#1639).

Reply markers obey the same rule: only the expected login's (or the running
`me` login's, when `GH_ISSUE_REPLY_TRUSTED_LOGIN` names another account)
`<!-- issue-reply:… -->` counts as "already answered", otherwise anyone could
silence a finding by posting a fake reply.

Both markers count only as a whole line. A reply quotes the comment it
answers with `> ` on every line, so a marker quoted from a forged comment
never becomes a trusted review or reply.

## Own comments are not findings

A comment by the expected (or running) login with an `issue-reply`,
`issue-reply-backup` or `ai-metrics` marker line is machine output and yields
no item. Any other comment of theirs is a human item. A reply marker inside a
trusted review or a body backup is never read as an answer: reviewer CLIs can
echo issue text, and a backup is a verbatim copy. A trusted review by that same login
is the finding source, not an answer (the `gh-pr:reply` #44 trap).

## Idempotency and re-review

The reply marker is `<!-- issue-reply:<key>:<VERDICT> -->`. Because the key
carries the review's `<hash12>`, a re-run skips every answered item, and a
re-review (`/gh-issue:issue-review-all <N>` after the body or comments
changed) produces a new hash and therefore new open items. The older review's
items stop being `current`, so its verdicts no longer drive the label.
