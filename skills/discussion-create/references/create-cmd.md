# gh-issue:discussion-create — Step 4 Create Command

Detail companion to SKILL.md Step 4. The procedure is
[`lib/create-discussion.sh`](../lib/create-discussion.sh) — this file is its
contract and the reasons behind it, not code to paste.

## Contract

Step 4 runs, with no confirmation prompt (확인 질문하지 말고 즉시 실행):

1. Write the drafted body to a `mktemp` file `$BODY` (removed on exit).
2. Append the footer: `bash "$PLUGIN_ROOT/lib/ai-metrics-footer.sh" "$TOKENS"
   "$HUMAN_H" "$ELAPSED" gh-discussion-create >> "$BODY" || echo "[WARN]
   ai-metrics append failed — continuing." >&2`. The footer's bytes are
   single-sourced in that script, which also honours `GH_DISABLE_AI_METRICS=1`
   itself (dEitY719/dotfiles#399 parity). The `||` is the SOFT half of the
   failure policy: never block the create on the footer.
3. `URL=$(bash "$PLUGIN_ROOT/lib/create-discussion.sh" "${TARGET_REPO%%/*}"
   "${TARGET_REPO##*/}" "$CATEGORY" "$TITLE" "$BODY")`.

`$TOKENS` / `$HUMAN_H` / `$ELAPSED` come from Step 3.5, `$TARGET_REPO` and the
exported `GH_HOST` / `PLUGIN_ROOT` from Step 1, `$CATEGORY` (default `Ideas`,
matched case-insensitively against the repo's list) from Step 2, `$TITLE` from
Step 3. `$PLUGIN_ROOT` is the root Step 1's `resolve-target.sh` proved — never
`${CLAUDE_PLUGIN_ROOT:-.}`, whose `$PWD` tier is the repo under review.

| | `lib/create-discussion.sh` |
|---|---|
| Input | `<owner> <repo> <category> <title> <body-file>`; env `GH_HOST` (required), `DOTFILES_ROOT` (optional) |
| Output | the Discussion URL on stdout |
| Exit 0 | created |
| Exit 1 | repo lookup, category lookup or mutation failed — or `gh_discussion.sh` did not resolve; the helper's `[gh-discussion] <reason>` line is on stderr. HARD: Step 5 prints `[FAIL]` quoting it and stops |
| Exit 2 | usage — a missing argument, an unreadable body file, or an empty `GH_HOST`; no `gh` call was made |

`gh api graphql` takes no `--repo`, so the exported `GH_HOST` is the only thing
keeping the three calls on the host the target remote points at
(dEitY719/dotfiles#1403). The script refuses to run without it rather than let
gh fall back to its default host.

`gh_discussion.sh` resolves from tier 0 `$SHELL_COMMON/functions/` (the tree
Step 1's `resolve-target.sh` proved and exported), then tier 1
`$DOTFILES_ROOT/shell-common/functions/` (default `~/dotfiles`), then tier 2 the
script's own `lib/vendor/` sibling — the same order as
`discussion-post-convert.sh`, so one run never loads two different copies —
proved by the function name after the load. There is no `$PWD` tier
(dEitY719/harness-skills#22). Self-check: `lib/create-discussion.selfcheck.sh`.

The same script serves `gh-issue:issue-create --as-discussion`, which ships its
own byte-identical copy — the two skills can no longer drift apart.

## ai-metrics footer note

The footer's emoji glyphs live in `lib/ai-metrics-footer.sh` alone; this
file quotes none of them. `CLAUDE.md`'s ai-metrics exception covers that
script and nothing else in this skill or the helper.

## Why three calls instead of one mutation

`createDiscussion` requires a `repositoryId` and a `categoryId`, both
of which are **node IDs** (opaque base64 strings), not the
human-readable `owner/repo` and `Ideas` strings the user works with.
GitHub's REST API exposes neither write path nor a single "create by
slug" shortcut — the lookups must happen first. Splitting them into
three helper calls keeps the failure modes distinct:

- repo lookup fails -> network/auth/missing repo
- category lookup fails -> Discussions disabled or category typo
- mutation fails -> permission, validation, or partial outage

Each branch yields a different remediation hint.

## Why no category-ID disk cache

See [`cache-decision.md`](cache-decision.md). Short version: one
GraphQL call per skill invocation is cheap; a stale cache after the
user renames a category would be a silent posting bug.
