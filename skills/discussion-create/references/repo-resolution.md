# gh-issue:discussion-create — Repo + host resolution

Detailed procedure for Step 1 "Detect Repo Context" — remote validation and
owner/repo **plus host** extraction. SKILL.md keeps only the workflow; this
file holds the argument shape and the blast radius.

## Substeps

1. Determine the target remote:
   - If a non-flag positional that does NOT match a known category
     (`Ideas`, `Q&A`, `Announcements`, `Lessons`) was passed, use it
     as the remote name.
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

`TARGET_REPO` is consumed by Step 4, split into `_owner="${TARGET_REPO%%/*}"`
and `_repo="${TARGET_REPO##*/}"` for the GraphQL helpers in
`gh_discussion.sh`.

## Host targeting rule (issue #1403)

This skill runs no `gh issue` and no `gh api repos/...`; every call it makes
is `gh api graphql`, via the three `_gh_discussion_*` helpers in Step 4. **The
GraphQL endpoint accepts no `--repo` flag**, so the `GH_HOST` that
`resolve-target.sh` exports is the *only* host selector on this path — the
skill's "항상 `--repo`" constraint cannot cover it.

Without that export `gh` follows its own `gh repo set-default` rather than
git's remote. On a dual-host login (github.com + GHES) the two disagree and
`createDiscussion` **succeeds against the wrong server**: GitHub creates the
Discussion under the same `<owner>/<repo>` slug on the other host and the
skill prints that URL as `[OK]`. Nothing errors, and undoing it means deleting
the Discussion by hand.

## Failure rule

`resolve-target.sh` fails (non-zero, `git remote -v` printed) rather than
falling back to `origin` when the user-specified remote is missing, and
refuses to continue with an empty `TARGET_HOST` — an empty `GH_HOST` is
exactly the silent wrong-host mutation described above.
