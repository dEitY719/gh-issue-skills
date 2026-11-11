# gh-issue:review-all — Flow detail

`lib/review-all.sh` is the whole skill; this file explains its choices. Each
helper's header is its own contract, and each has a self-check:
`lib/review-args.selfcheck.sh`, `lib/code-tree.selfcheck.sh` and
`tests/bats/gh_issue_review_all.bats` (repo root).

## Engine (dEitY719/dotfiles#2381)

The review itself is the dotfiles engine `functions/gh_issue_review.sh`
(`_gh_issue_review_main --ai <ai> --repo <owner/repo> --host <host>
--workdir <dir> <N>`), run once per lane by the fan-out core
`lib/ai_fanout.sh`, with the CLI runner and output gate from
`lib/ai_cli_run.sh` — the same code the PR review uses. This skill only
chooses the target, the tree and the lanes, and reports. It looks for
`shell-common` under `$DOTFILES_ROOT` (default `$HOME/dotfiles`) first, and
uses its own vendored copy under `lib/vendor/shell-common/` when that
checkout does not have the issue engine yet. The vendored files are
dotfiles snapshots (`# SSOT: dEitY719/dotfiles` banner); never edit them here.

What the engine owns, so this skill does not repeat it:

- **Prompt.** Title, body and comments, minus earlier `ai-issue-review`
  comments (no anchoring on another harness's review). The common preamble
  puts omissions first and fact-checking against the tree second. The title's
  conventional-commit prefix adds a `feat` or `fix` perspective. A `판정:` /
  `Verdict:` line is mandatory.
- **Output gate.** A rate-limit notice or an empty reply exits 0 from the
  CLI but is not a review. The gate rejects it, and the lane becomes a skip.
- **Duplicate guard.** The marker is `<!-- ai-issue-review:<ai>:<hash12> -->`.
  `<hash12>` is the first 12 hex digits of sha256 over title, body and the
  non-marker comments, so a new human comment also reopens the review. Only
  comments by the current `gh` login on that host count, so nobody else's
  fake marker can block a lane. `updatedAt` is not used: any comment changes it.
- **Leak guard.** On an internal PC (or with an unreadable setup-mode reader)
  with a github.com target, the comment is checked against `LEAK_PATTERNS_ERE`
  before it is posted. A match, or an empty variable, holds it (exit 3).

## Lane outcomes (`lib/review-lane.sh`)

| Engine result | Lane exit | Report |
|---|---|---|
| comment posted | 0, URL saved | `<ai>:ok` + `  <ai>: <url>` |
| `[SKIP] ... already reviewed` (engine rc 0) | 4 | `<ai>:skip(already reviewed)` |
| leak guard (rc 3) | 3 | `<ai>:skip(leak-guard)` |
| CLI missing, rate limit, output gate, any rc | rc | `<ai>:skip(<first stderr line>)` |
| 540s cap | 124 | `<ai>:skip(timeout 540s)` |

The fan-out core reports any non-zero lane as a skip with its first stderr
line. The engine exits 0 on a duplicate, which would otherwise read `ok` with
no comment, so the lane turns that into exit 4.

## Code tree (`lib/code-tree.sh`)

Reviewer CLIs run in a throwaway tree so they can check the issue's claims
against code. An agentic CLI (codex, opencode) that edits files mid-review
then edits a copy, not the user's work.

| Situation | Tree | Why |
|---|---|---|
| a local remote names the repo | `git worktree add --detach <tmp> HEAD` | local, no network, seconds; the user merges fast, so HEAD is current. Uncommitted changes are not reviewed. |
| internal PC (or unreadable reader) + github.com target | `git fetch <remote> <default>` then a worktree at `<remote>/<default>` | internal-only commits must never enter the tree a github.com review reads |
| no local remote names the repo (URL input) | `gh repo clone <host>/<owner>/<repo> <tmp> -- --depth 1` | nothing local to reuse |

The internal + github.com decision is `_gh_push_github_com_forbidden` from
`lib/gh_host.sh`, which counts a missing setup-mode reader as internal. If
`gh_host.sh` itself cannot load, a github.com target counts the same way
(fail closed). The tree is removed on every exit path: a worktree with
`git worktree remove --force`, a clone only when its path carries this
script's `mktemp` prefix.

Tree isolation is not the whole leak defense. A CLI can still read absolute
paths outside the tree, user config or memory. That is why the engine's
`LEAK_PATTERNS_ERE` check runs on the final comment.

## Report

```
issue-review #70: claude:ok codex:skip(already reviewed) opencode:skip(Required CLI 'opencode' not found in PATH) agy:ok hermes:skip(leak-guard)
  base: main@1a2b3c4 (default-branch)
  claude: https://github.com/<owner>/<repo>/issues/70#issuecomment-1
  agy: https://github.com/<owner>/<repo>/issues/70#issuecomment-2
```

Skip reasons are cut to 80 characters. The engine writes the review basis
into each comment from the tree's own HEAD. In a detached worktree that
reads `HEAD@<sha>`; the `base:` line above names the branch it came from.
