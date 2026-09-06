# gh-issue:proceed — Repo + host resolution

Detailed procedure for Step 1 remote validation and owner/repo **plus host**
extraction. SKILL.md keeps only the workflow; this file holds the argument
shape and the blast radius.

## Substeps

1. Determine the target remote:
   - If the user passed the second positional (`<issue-number> [remote]`), use
     it as the remote name.
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
   exports `TARGET_REPO`, `TARGET_HOST`, `GH_HOST`, `SHELL_COMMON` and
   `PLUGIN_ROOT` (this plugin's own root, for addressing `lib/` helpers). Repo and
   host are read from that **one** URL, so they can never name different
   servers:

   - `https://github.com/<owner>/<repo>.git` → `github.com` + `<owner>/<repo>`
   - `git@github.samsungds.net:<owner>/<repo>.git` → `github.samsungds.net`
     + `<owner>/<repo>`

`TARGET_REPO` and `TARGET_HOST` are consumed by Step 2 of the main workflow.

## Host targeting rule (issues dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407)

Every `gh` call this skill runs — the Step 2.1 fetch/claim, the Step 3
protocol directives, the Step 4 report — names both host and repo:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

`--repo <owner>/<repo>` carries no host, so a bare `gh` follows its own
`gh repo set-default` instead of git's remote. On a dual-host login
(github.com + GHES) the two disagree and the call silently hits the wrong
server — an OPEN issue comes back "not found" (dEitY719/dotfiles#1403), or worse, a
directive's write (self-assign, comment, close) lands in the wrong repo.

`resolve-target.sh`'s `export GH_HOST` also makes the sourced helpers
(`gh_project_status.sh`) inherit the same host; the reference files still
spell the prefix out so every example stays copy-paste safe.

## Failure rule

`resolve-target.sh` fails (non-zero, `git remote -v` printed) rather than
falling back to `origin` when the user-specified remote is missing, and
refuses to continue with an empty `TARGET_HOST`. A silent fallback masks a
typo and proceeds against the wrong repo; an empty `GH_HOST` is exactly the
silent-misroute state dEitY719/dotfiles#1403 described.
