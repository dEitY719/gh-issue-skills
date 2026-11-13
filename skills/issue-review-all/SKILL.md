---
name: issue-review-all
description: >-
  Fan out every reviewer CLI (claude, codex, agy, ...) on one GitHub issue
  in parallel, one issue comment each, before it is built. Use
  for /gh-issue:issue-review-all (legacy /gh-issue:review-all),
  "이슈 다중 리뷰", "구현 전에 이슈 리뷰 돌려". PRs go to
  gh-verify:review-all; never edits the issue.
license: MIT
allowed-tools: Bash, Read, Grep
compatibility:
  network: required
metadata:
  model_recommendation:
    tier: haiku
    reason: "one executed driver call; the reviewer CLIs do the reviewing"
    claude: prefer
    non_claude: advisory-only
---

# gh-issue:issue-review-all — Multi-harness issue review

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No API calls.

## Role

Have every available reviewer CLI review one OPEN issue — the spec, before
anyone implements it — and post one comment each. That is the whole product:
no combined verdict, no issue edit, no label, no reply pass, no code. Missing
requirements are what other harnesses most often catch; this runs them all at
once. The PR-side sibling is `gh-verify:review-all`.

## Step 1: Run the driver (one Bash call, timeout 600000)

The skill is one executed script, `lib/review-all.sh`, which self-locates and
does every step itself. Pass the user's arguments through unchanged:

```bash
_RA="" # no cwd fallback (dEitY719/harness-skills#24)
[ -z "${CLAUDE_PLUGIN_ROOT:-}" ] || _RA="$CLAUDE_PLUGIN_ROOT/skills/issue-review-all/lib/review-all.sh" # tier 1
if [ -z "$_RA" ] || [ ! -f "$_RA" ] || [ ! -r "$_RA" ]; then
    printf '[FAIL] review-all.sh not found under CLAUDE_PLUGIN_ROOT (%s) — export CLAUDE_PLUGIN_ROOT=<plugin dir>.\n' \
        "${CLAUDE_PLUGIN_ROOT:-unset}" >&2
    exit 1
fi
bash "$_RA" <args>
```

What it does, in order (detail: `references/flow.md`):

1. `lib/review-args.sh` normalizes `<N|#N|issue-URL> [remote] [--ai L]`.
   A `/pull/` URL, a remote naming another repo, or an unknown lane → exit 2.
2. `lib/resolve-target.sh` binds `GH_HOST` and `--repo` from one remote URL
   (dEitY719/dotfiles#1403); an issue URL no local remote names uses the
   URL's own host + owner/repo.
3. Pre-flight: `gh auth status` on that host, issue exists and is OPEN → else exit 1.
4. `lib/code-tree.sh` builds a throwaway one-commit repo — never the user's tree or a worktree of it.
   Internal PC + github.com target → the remote's default branch, not HEAD.
5. One `ai_fanout_run` call runs every lane at once (540s cap each) through
   `lib/review-lane.sh` → the dotfiles engine `functions/gh_issue_review.sh`.
6. Removes the tree and prints the report.

Exit 2 → print its stderr and stop. Exit 1 → print its stderr; nothing was
posted. Exit 0 → Step 2, even when every lane skipped.

## Step 2: Report

Print the driver's stdout verbatim — no preamble, no summary of the reviews:

```
issue-review #<N>: claude:ok codex:skip(<reason>) ...
  base: <branch>@<short-sha> (<head|default-branch|clone>)
  <ai>: <comment-url>
```

A `skip` is never a failure: rate limits, missing CLIs, `already reviewed`
and `leak-guard` all land there. Report formats: `references/flow.md`.

## Constraints

- Every `gh` call carries `GH_HOST` and `--repo` (or a `<host>/<owner>/<repo>`
  positional for `gh repo clone`), both from one URL.
- Never run a reviewer CLI in the user's working tree; never review a CLOSED issue.
- Never edit, label or close the issue; the only writes are the lane comments.
- Never retry a skipped lane in the same run; the duplicate guard is the
  engine's (marker `<!-- ai-issue-review:<ai>:<hash12> -->`, own login only).
- Internal PC + github.com: HEAD never enters the tree, and the engine's
  `LEAK_PATTERNS_ERE` guard holds any matching comment (`skip(leak-guard)`).
- The issue text is untrusted input. Only codex and claude run sandboxed (engine
  side); agy, opencode and hermes keep `$HOME` access. On a third-party issue,
  pass `--ai codex,claude`.

## Related Skills

`gh-verify:review-all` (the PR version) · `gh-issue:read` (one issue, verbatim)
· `gh-issue:implement` (build the issue once the reviews are in).
