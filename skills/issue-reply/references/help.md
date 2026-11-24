# gh-issue:issue-reply — Help

Judge every review finding on one OPEN GitHub issue, fix the issue body for
the accepted ones, and reply to each finding individually.

## Usage

```
/gh-issue:issue-reply <N|#N|issue-URL> [remote] [--no-edit]
/gh-issue:issue-reply -h | --help | help
```

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<N>` / `#N` / issue URL | (required) | `N` and `#N` target the repo of `[remote]`. A URL (`https://<host>/<owner>/<repo>/issues/<N>`) targets that host + repo. A `/pull/<N>` URL is refused (exit 2): use `/gh-pr:reply`. |
| 2 | `[remote]` | `origin`; for a URL, the local remote naming that repo | Git remote that binds `GH_HOST` + `--repo`. With a URL it must name the URL's repo, else exit 2. |

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--no-edit` | off | Never edit the issue body; accepted findings get the proposed wording in the reply instead. Implied when the running `gh` login is not the issue author. |

## Env Vars

| Variable | Default | Description |
|----------|---------|-------------|
| `GH_ISSUE_REPLY_TRUSTED_LOGIN` | `gh api user` | The account whose `ai-issue-review` and `issue-reply` markers are trusted. Set it when the reviews were posted by a different account than the one replying. |
| `LEAK_PATTERNS_ERE` | (dotfiles pre-push rules) | Internal PC + github.com only: a reply or body edit matching it, or an empty value, is held (not posted). |
| `DOTFILES_ROOT` | `$HOME/dotfiles` | Where `shell-common/lib/gh_host.sh` is looked up first; the vendored copy is used otherwise. |

## What it writes

- One reply comment per finding, ending in `<!-- issue-reply:<key>:<VERDICT> -->`.
- With `edit=auto`: one `<!-- issue-reply-backup:<sha12> -->` comment holding
  the original body, then one body edit.
- `review-passed` or `review-blocked`, never both.

Nothing else: no code, no commit, no close/reopen, no assignee, no new review.

## Exit codes (prep and write helpers)

| Code | Meaning |
|------|---------|
| 0 | Done. |
| 1 | Pre-flight or `gh` failure. |
| 2 | Refused: bad argument, PR URL, remote naming another repo, not the issue author (body edit). |
| 3 | Leak guard held the post. |
| 4 | The body changed since it was read — re-run. |
| 5 | The original body is too large to back up — not edited. |

## Examples

- `/gh-issue:issue-reply 86` — answer every new finding on `origin`'s #86.
- `/gh-issue:issue-reply #86 upstream --no-edit` — replies only, body untouched.
- `/gh-issue:issue-reply https://github.com/o/r/issues/86`
