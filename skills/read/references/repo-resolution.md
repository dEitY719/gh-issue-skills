# gh-issue:read — Repo + host resolution

Detailed procedure for Step 1 "Detect Repo Context" — remote validation and
owner/repo **plus host** extraction. SKILL.md keeps only the workflow; this
file holds the argument shape and the blast radius.

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
   exports `TARGET_REPO`, `TARGET_HOST`, `GH_HOST` and `SHELL_COMMON`. Repo and
   host are read from that **one** URL, so they can never name different
   servers:

   - `https://github.com/<owner>/<repo>.git` → `github.com` + `<owner>/<repo>`
   - `git@github.samsungds.net:<owner>/<repo>.git` → `github.samsungds.net`
     + `<owner>/<repo>`

`TARGET_REPO` and `TARGET_HOST` are consumed by Step 2 of the main workflow.

## Host targeting rule (issue dEitY719/dotfiles#1403)

이 스킬의 **모든** `gh` 호출은 host 와 repo 를 명시한다:

```bash
GH_HOST="$TARGET_HOST" gh issue view <N> --repo "$TARGET_REPO" ...
```

`--repo` 없는 `gh` 는 git 의 `origin` 이 아니라 gh CLI 자신의
`gh repo set-default` 를 따른다. github.com 과 GHES 에 동시에 로그인한
상태에서 그 둘이 어긋나면 **에러 없이 조용히 다른 host 를 조회한다** —
읽기 전용 스킬인 만큼 결과가 그대로 사용자에게 "이슈 없음" 으로 보고되고,
실제로는 OPEN 인 이슈였던 것이 dEitY719/dotfiles#1403 이다.

## Failure rule

`resolve-target.sh` fails (non-zero, `git remote -v` printed) rather than
falling back to `origin` when the user-specified remote is missing, and
refuses to continue with an empty `TARGET_HOST`. 빈 `GH_HOST` 는 정확히
dEitY719/dotfiles#1403 의 조용한 오조회 상태다.
