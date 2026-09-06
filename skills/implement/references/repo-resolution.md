# gh-issue:implement — Repo + host resolution

Detailed procedure for Step 1 "Detect Repo Context" — remote validation and
owner/repo **plus host** extraction. SKILL.md keeps only the workflow; this
file holds the argument shape and the blast radius.

## Substeps

1. Determine the target remote:
   - If the user passed the third positional (`<issue-number> [mode] [remote]`),
     use it as the remote name.
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

`TARGET_REPO` and `TARGET_HOST` are consumed by Step 3 of the main workflow.

## Host targeting rule (issue dEitY719/dotfiles#1403)

이 스킬이 실행하는 **모든** `gh` 호출은 host 와 repo 를 명시한다:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

`--repo` 없이 부른 `gh` 는 git 의 `origin` 이 아니라 gh CLI 자신의
`gh repo set-default` 값을 따른다. github.com 과 GHES 두 host 에 동시에
로그인한 상태에서 그 둘이 어긋나면 **에러 없이 조용히 엉뚱한 host 를 조회한다**
— OPEN 인 이슈가 "not found" 로 돌아온 dEitY719/dotfiles#1403 이 그 사례다.

`resolve-target.sh` 의 `export GH_HOST` 는 이 스킬이 source 하는 헬퍼
(`gh_project_status.sh` 등) 까지 같은 host 를 상속시킨다 — 그 헬퍼들은 자기가
`gh` 를 부르면서 host 를 달리 알 방법이 없다. 그래도 아래 참조 파일들의 예제
명령은 복사-붙여넣기 안전을 위해 접두사를 그대로 표기한다.

## Failure rule

`resolve-target.sh` fails (non-zero, `git remote -v` printed) rather than
falling back to `origin` when the user-specified remote is missing, and
refuses to continue with an empty `TARGET_HOST` — 빈 `GH_HOST` 는 바로 dEitY719/dotfiles#1403
의 조용한 오조회 상태다. `_gh_host_from_url` 이 실패(github 계열이 아닌
remote)하면 `_gh_resolve_host` 로 폴백하되, 그 결과도 비면 실패한다.
