# gh-issue:create — Repo + host resolution

Detailed procedure for Step 1 "Detect Repo Context" — remote validation and
owner/repo **plus host** extraction. SKILL.md keeps only the workflow; this
file holds the argument shape and the blast radius.

## Substeps

1. Determine the target remote:
   - If the user passed the `[remote]` positional, use it as the remote name.
   - Otherwise default to `origin`.

2. Bind the target — one sourced line, so the exports survive into the caller:

   ```bash
   . "${CLAUDE_PLUGIN_ROOT:-.}/lib/resolve-target.sh" "${REMOTE:-origin}" || exit 1
   ```

   [`lib/resolve-target.sh`](../../../lib/resolve-target.sh) is the SSOT for
   this step across all six skills — it confirms we are in a git repo, reads
   `git remote get-url "$REMOTE"`, sources `gh_host.sh` from `$DOTFILES_ROOT`
   or the vendored copy under `$CLAUDE_PLUGIN_ROOT/lib/vendor/`, and exports
   `TARGET_REPO`, `TARGET_HOST` and `GH_HOST` (plus `SHELL_COMMON` when the
   vendored copy resolved). Repo and host are read from that **one** URL, so
   they can never name different servers:

   - `https://github.com/<owner>/<repo>.git` → `github.com` + `<owner>/<repo>`
   - `git@github.samsungds.net:<owner>/<repo>.git` → `github.samsungds.net`
     + `<owner>/<repo>`

`TARGET_REPO` and `TARGET_HOST` are consumed by Step 2.5 / Step 4 of the main
workflow.

## Host targeting rule (issue #1403)

이 스킬의 **모든** `gh` 호출 — `gh issue create`, `gh label list`,
`gh api .../milestones`, ai-metrics 코멘트 POST — 은 host 와 repo 를 명시한다:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

`--repo` 없는 `gh` 는 git 의 `origin` 이 아니라 gh CLI 자신의
`gh repo set-default` 를 따른다. github.com 과 GHES 에 동시에 로그인한
상태에서 둘이 어긋나면 **에러 없이 조용히 다른 host 에 붙는다**. 쓰기
스킬인 이 스킬에서는 그 결과가 "이슈가 엉뚱한 repo 에 생성됨" 이고, 되돌리려면
사람이 직접 지워야 한다 (#1403).

`--as-discussion` 경로는 `--repo` 를 받지 않는 `gh api graphql` 을 쓴다 —
`gh_discussion.sh` 의 GraphQL 호출에는 `resolve-target.sh` 가 export 한
`GH_HOST` 만이 유일한 host 선택자다. Issue 는 GHES 에, Discussion 은
github.com 에 생기는 어긋남을 막는 것이 정확히 그 export 다.

## Failure rule

`resolve-target.sh` fails (non-zero, `git remote -v` printed) rather than
falling back to `origin` when the user-specified remote is missing, and
refuses to continue with an empty `TARGET_HOST`. Both are load-bearing here:
a silent fallback masks a typo and creates the issue in the wrong repo, and
an empty `GH_HOST` is exactly the silent mis-creation state of #1403.
