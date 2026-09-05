# gh-issue:discussion-convert — Repo + host resolution

Detailed procedure for Step 1 "Detect Repo Context". SKILL.md keeps only the
workflow; this file holds the argument shape and the blast radius.

## Substeps

1. Determine the target remote:
   - If a second non-flag positional was passed (after the discussion
     number), treat it as the remote name.
   - Otherwise default to `origin`.

2. Bind the target — one sourced line, so the exports survive into the caller:

   ```bash
   . "${CLAUDE_PLUGIN_ROOT:-.}/lib/resolve-target.sh" "${REMOTE:-origin}" || exit 1
   ```

   [`lib/resolve-target.sh`](../../../lib/resolve-target.sh) is the SSOT for
   this step across all six skills — it confirms we are in a git repo, reads
   `git remote get-url "$REMOTE"`, sources `gh_host.sh` from `$DOTFILES_ROOT`
   or the vendored copy under `lib/vendor/` (located via `CLAUDE_PLUGIN_ROOT`,
   falling back to the helper's own directory when no harness exports it), and
   exports `TARGET_REPO`, `TARGET_HOST`, `GH_HOST` and `SHELL_COMMON`. Repo and
   host are read from that **one** URL, so they can never name different
   servers:

   - `https://github.com/<owner>/<repo>.git` -> `github.com` + `<owner>/<repo>`
   - `git@github.samsungds.net:<owner>/<repo>.git` -> `github.samsungds.net`
     + `<owner>/<repo>`

`TARGET_REPO` is consumed by Step 2 onward, split into
`_owner="${TARGET_REPO%%/*}"` and `_repo="${TARGET_REPO##*/}"` for the GraphQL
helpers in `gh_discussion.sh` — they inherit the exported `GH_HOST`, so the
Discussion mutations hit the same server as the Issue creation.

## Host targeting rule (issues #1403 / #1407)

Every `gh` call this skill runs names both host and repo:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

`--repo <owner>/<repo>` carries no host, so a bare `gh` follows its own
`gh repo set-default` rather than git's remote. On a dual-host login
(github.com + GHES) the two disagree and the call silently hits the wrong
server. Here that is worse than a bad read: Step 4's idempotency search
would miss an existing Issue and Step 5 would create the promoted Issue in
the wrong repo, splintering the very backlink chain this skill exists to
keep intact. The Discussion half of the flow is `gh api graphql`, which takes
no `--repo` at all — the exported `GH_HOST` is its only host selector.

## Failure rule

`resolve-target.sh` fails (non-zero, `git remote -v` printed) rather than
falling back to `origin` when the user-specified remote is missing, and
refuses to continue with an empty `TARGET_HOST`. A silent fallback converts a
Discussion in the wrong repo, splintering the SSOT chain across forks.
