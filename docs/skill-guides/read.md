# `read` — 이슈 읽기 스킬 가이드

## 한 줄 요약

GitHub 이슈 1건을 가져와 **터미널에 구조화된 verbatim 요약을 출력**한다.
산출물은 화면에 찍히는 텍스트 그 자체이며, GitHub 상태는 하나도 바뀌지 않는다.

## 언제 쓰고 언제 안 쓰는가

**쓸 때**

- 이슈 번호만 알고 본문/코멘트 전문을 그대로 확인하고 싶을 때.
- 구현이나 프로토콜 실행 전에 입력 자료를 먼저 확보하고 싶을 때.
  출력이 verbatim 이라 `implement` / `proceed` 의 입력으로 그대로 흘려보낼 수 있다.
- 다른 remote(예: `upstream`)가 소유한 이슈를 확인할 때.

**안 쓸 때 — 형제 스킬과의 경계**

| 상황 | 맞는 스킬 |
|------|-----------|
| 이슈 내용대로 코드를 고쳐야 함 | `implement` |
| 이슈에 실행 가능한 8섹션 프로토콜이 박혀 있음 (지시 이슈) | `proceed` |
| 대화를 이슈로 남겨야 함 | `create` |

`read` 는 이 6개 스킬 중 **유일하게 아무것도 바꾸지 않는 스킬**이다.
`gh issue edit` / `close` / `comment` 를 절대 호출하지 않는다. 라벨을 붙이거나
담당자를 지정하는 동작도 없다. "읽고 나서 이왕이면 라벨도" 같은 확장은 이 스킬의
경계 밖이며, 그런 쓰기는 `create` 나 `implement` 가 맡는다.

또한 연결된 PR 이나 참조 이슈를 따라가지 않는다. 대상은 인자로 받은 이슈 1건뿐이다.

## 호출 형식과 인자

```
/gh-issue:read <issue-number> [remote]
```

`references/help.md` 기준:

| # | 이름 | 기본값 | 설명 |
|---|------|--------|------|
| 1 | `<issue-number>` 또는 `-h` / `--help` / `help` | — | 조회할 GitHub 이슈 번호 (help 가 아니면 필수) |
| 2 | `remote-name` | `origin` | 이슈를 소유한 repo 의 git remote 이름 |

사용 예:

| 명령 | 동작 |
|------|------|
| `/gh-issue:read 42` | `origin` 의 repo 에서 #42 를 가져와 구조화 요약 출력 |
| `/gh-issue:read 42 upstream` | `upstream` remote 의 repo 에서 조회 |
| `/gh-issue:read -h` | help 를 verbatim 출력하고 종료. API 호출 0건 |

## 동작 단계 요약

SKILL.md 의 Step 구조는 4단계다.

1. **Step 1 — 인자 파싱 + repo 해석.** `START_TS` 기록, 이슈 번호 검증,
   `git remote get-url <remote>` 한 개의 URL 에서 `TARGET_REPO` 와 `TARGET_HOST` 를
   **함께** 뽑고 `GH_HOST` 를 export 한다. 이슈 번호가 없거나 잘못됐으면
   `Run /gh-issue:read -h for usage.` 를 찍고 멈춘다. remote 가 없으면
   `git remote -v` 를 보여주고 멈춘다 — `origin` 으로 조용히 되돌아가지 않는다.
2. **Step 2 — 이슈 fetch.** `GH_HOST="$TARGET_HOST" gh issue view <N> --repo
   "$TARGET_REPO" --json ...` 로 번호/제목/본문/작성자/라벨/상태/코멘트/담당자/
   타임스탬프/URL 을 한 번에 받는다. 실패하면 `gh` 의 stderr 를 그대로 출력하고
   멈춘다 — fallback 재시도를 하지 않는다.
3. **Step 3 — 출력 조립.** `references/output-format.md` 의 순서를 따른다:
   Header → Summary → Body → Discussion → Meta → Checklist.
   Body 와 Discussion 은 verbatim, Summary 만 2~4줄 추출이다.
   Checklist 는 본문과 코멘트에서 `- [ ]` / `- [x]` 라인을 전부 긁어 모은다.
   섹션 제목은 대화 언어를 따르되 내용은 원문 언어를 유지한다.
4. **Step 4 — 리포트.** 서두("이슈 내용은 다음과 같습니다")나 맺음말 없이 출력만
   찍고, 마지막에 `[ai-metrics:gh-issue-read] ~{ELAPSED} min (read-only — not
   written to GitHub)` 한 줄을 붙인다.

## 주의사항과 제약

- **모든 `gh` 호출이 `GH_HOST` 와 `--repo` 를 함께 넘긴다 (dEitY719/dotfiles#1403).** 둘 다 Step 1 이
  같은 remote URL 에서 뽑은 쌍이어야 한다. `--repo` 가 없는 `gh` 는 git 의 `origin`
  이 아니라 gh CLI 자신의 `gh repo set-default` 를 따라가므로, github.com 과 GHES 에
  동시 로그인한 상태에서는 **에러 없이 조용히 다른 서버를 조회한다**. 읽기 전용
  스킬에서는 그 결과가 사용자에게 "이슈 없음" 으로 그대로 보고되는데 실제로는 OPEN
  이슈였던 것이 dEitY719/dotfiles#1403 이다. 예상 밖의 `gh` 결과를 `--repo` 를 빼거나 remote 를 바꿔서
  우회하지 말고 host 를 먼저 검증한다.
- **`TARGET_HOST` 가 빈 채로 진행하지 않는다.** 빈 `GH_HOST` 는 정확히 dEitY719/dotfiles#1403 의
  조용한 오조회 상태다.
- **본문과 코멘트를 자르거나 바꿔 쓰지 않는다.** 요약해서 없애기, 줄바꿈 재정렬,
  번역 모두 금지다. 보존된 기록이 이 스킬의 산출물이다.
- **존재하지 않는 remote 를 받았을 때 `origin` 으로 fallback 하지 않는다.**
  오타를 가려서 엉뚱한 repo 를 읽게 만들기 때문이다.
- **CLOSED 이슈의 종료 사유는 별도 REST 읽기로 가져온다.** Header 의
  `(CLOSED — completed)` 괄호는 `gh issue view --json stateReason` 이 아니라
  `gh api "repos/$TARGET_REPO/issues/<N>" --jq .state_reason` 에서 온다.
  `stateReason` 은 비교적 최신 gh 에서만 `--json` 필드로 제공되고, 없는 버전에
  요청하면 `Unknown JSON field: "stateReason"` 로 **fetch 전체가 exit 1** 이 되어
  아무것도 출력되지 않는다. REST 필드는 모든 버전이 노출하므로 이 경로가 안전하다.
  추가 읽기는 `state` 가 `CLOSED` 일 때만 실행하고, 실패하거나 `null` 이면 괄호만
  생략한다 — 이미 성공한 fetch 를 뒤엎지 않는다. GET 이라 읽기 전용 계약도 유지된다.
- **`--json` 필드 목록은 한 줄로 유지한다.** 백슬래시로 이어붙인 다음 줄에
  들여쓰기가 있으면 그 공백이 인자 구분자가 되어 목록이 두 개의 인자로 쪼개지고,
  `gh` 가 `accepts 1 arg(s), received 2` 로 거절한다.
