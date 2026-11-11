# gh-issue:review-all — Help

Every reviewer CLI reviews one OPEN GitHub issue in parallel and posts one
issue comment each. Nothing else is written.

## Usage

```
/gh-issue:review-all <N|#N|issue-URL> [remote] [--lanes L]
/gh-issue:review-all -h | --help | help
```

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<N>` / `#N` / issue URL | (required) | `N` and `#N` target the repo of `[remote]`. A URL (`https://<host>/<owner>/<repo>/issues/<N>`, `?query` and `#fragment` ignored) targets that host + repo. A `/pull/<N>` URL is refused (exit 2): use `/gh-verify:review-all`. |
| 2 | `[remote]` | `origin`; for a URL, the local remote naming that repo | Git remote that binds `GH_HOST` + `--repo`. With a URL it must name the URL's repo, else exit 2. A URL no local remote names is reviewed from a fresh `--depth 1` clone. |

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--lanes L` | `claude,codex,opencode,agy,hermes` | Comma list of reviewer CLIs to run. Unknown or repeated names → exit 2. The issue text is untrusted input, and only codex and claude run sandboxed (read-only, no Bash/Edit). For an issue written by someone you do not trust, use `--lanes codex,claude`. |
| `--force` | — | Refused (exit 2). The engine skips a lane this `gh` login already reviewed for the same material and has no bypass. To re-review, add a comment to the issue (the hash covers title, body and human comments) or delete the old review comment. |

## Env Vars

| Variable | Default | Description |
|----------|---------|-------------|
| `GH_ISSUE_REVIEW_TIMEOUT_SEC` | `540` | Per-lane cap in seconds. |
| `DOTFILES_ROOT` | `$HOME/dotfiles` | Where `shell-common` is looked up first; the vendored copy is used when it lacks the issue engine. |
| `LEAK_PATTERNS_ERE` | (dotfiles pre-push rules) | Internal PC + github.com only: a comment matching it, or an empty value, is held → `skip(leak-guard)`. |
| `DOTFILES_SETUP_MODE` | `~/.dotfiles-setup-mode` | `internal` / `external` / `public`; an unreadable reader counts as internal. |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | The fan-out ran. Lanes that failed are reported as `skip(<reason>)`, not as an error. |
| 1 | Pre-flight or runtime failure: not logged in, issue missing or not OPEN, tree could not be built. Nothing was posted. |
| 2 | Argument refused. |

## Examples

- `/gh-issue:review-all 70` — all five lanes on `origin`'s issue #70.
- `/gh-issue:review-all #12 upstream --lanes codex,agy` — two lanes on `upstream`.
- `/gh-issue:review-all https://ghes.example.com/team/svc/issues/3` — a GHES issue.
