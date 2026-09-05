# `discussion-convert` — 결정된 Discussion 을 Issue 로 승격하는 스킬 가이드

## 한 줄 요약

결정이 끝난 `Ideas` Discussion 1건을 **백링크를 가진 Issue 1건 + 잠기고 닫힌
Discussion** 으로 바꾼다. GitHub 에는 공개된 `convertDiscussion` 뮤테이션이 없으므로,
UI 의 `Convert to issue` 경로를 4개의 원시 뮤테이션으로 흉내 낸다. 출력은 새 Issue URL
한 줄이다.

## 언제 쓰고 언제 안 쓰는가

**쓸 때**

- `Ideas` Discussion 의 열린 질문이 결론에 도달했고, 이제 칸반 보드에서 추적해야 할 때.
- 운영 원칙 #2 "결정되면 즉시 convert" 를 기계적으로 집행하고 싶을 때.

**안 쓸 때 — 형제 스킬과의 경계**

| 상황 | 맞는 스킬 |
|------|-----------|
| 아직 결정 전인 대화를 RFC 로 남겨야 함 | `discussion-create` |
| 대화가 이미 수렴된 to-do 이고 Discussion 단계를 거치지 않음 | `create` |
| Discussion 을 다시 쓰거나 재분류해야 함 | 사람이 GitHub UI 에서 |

`discussion-create` 와 `discussion-convert` 는 한 생애주기의 앞뒤다. 앞쪽이 결정 전
RFC 를 열고, 뒤쪽이 결정된 것을 트래커로 승격시킨다. 즉 `create` 와
`discussion-create` 를 가르는 "결정됨(decidedness)" 기준에서, **질문이 결정된 뒤
되돌아오는 다리**가 이 스킬이다.

## 호출 형식과 인자

```
/gh-issue:discussion-convert <discussion-number> [remote] [--no-*] [--force-category]
```

`references/help.md` 기준 인자:

| # | 이름 | 기본값 | 설명 |
|---|------|--------|------|
| 1 | `<discussion-number>` 또는 `-h` / `--help` / `help` | (필수) | 변환할 Ideas Discussion 번호 (양의 정수) |
| 2 | `[remote]` | `origin` | Discussion 과 새 Issue 를 소유할 repo 의 git remote |

플래그:

| 플래그 | 기본값 | 설명 |
|--------|--------|------|
| `--no-comment` | off | Step 7(`Linked to issue #<M>` 역방향 백링크 코멘트) 생략. 역방향 링크는 사람이 관리 |
| `--no-lock` | off | Step 8.2(`Lock conversation`, reason Resolved) 생략 |
| `--no-close` | off | Step 8.1(`closeDiscussion`) 생략. Discussion 을 계속 열어 둘 때 |
| `--no-board-sync` | off | Step 6(프로젝트 보드 `In progress` 전이) 생략 |
| `--force-category` | off | Step 3 의 `Ideas` 전용 가드 우회. Q&A / Announcements / Lessons 변환에 필요하며 정책상 원래 금지 |

환경 변수:

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `GH_DISABLE_AI_METRICS=1` | off | ai-metrics 처리 억제 (`discussion-create` 와 parity) |
| `GH_PROJECT_STATUS_SYNC=0` | on | 보드 동기화 전역 생략 (`_gh_project_status_sync` 헬퍼가 처리) |

사용 예:

| 명령 | 동작 |
|------|------|
| `/gh-issue:discussion-convert 42` | `origin` repo 의 Discussion #42 를 변환 |
| `/gh-issue:discussion-convert 42 upstream` | `upstream` repo 에 대해 변환 |
| `/gh-issue:discussion-convert 42 --no-comment --no-lock` | 백링크가 붙은 Issue 만 만들고 Discussion 은 열린 채 조용히 둔다 |
| `/gh-issue:discussion-convert -h` | help 를 verbatim 출력하고 종료. API 호출 0건 |

## 동작 단계 요약

SKILL.md 의 Step 구조는 9단계다.

1. **Step 1 — repo 컨텍스트 감지.** `START_TS` 기록, git repo 확인, 선택한 remote 의
   URL 하나에서 `TARGET_REPO` 와 `TARGET_HOST` 를 함께 뽑고 `GH_HOST` 를 export 한다.
   remote 가 없으면 즉시 실패 — 조용한 `origin` fallback 없음.
2. **Step 2 — Discussion fetch.** `gh_discussion.sh` 를 source 하고
   `_gh_discussion_fetch` 로 GraphQL 한 번 호출해 `.id` / `.number` / `.title` /
   `.body` / `.url` / `.category` / `.closed` / `.locked` 를 읽는다. fetch 실패 시
   stderr 를 그대로 내보내고 abort 한다.
3. **Step 3 — 카테고리 가드.** `.category != "Ideas"` 이고 `--force-category` 가 없으면
   `references/error-cases.md` 의 거부 메시지를 verbatim 출력하고 exit 1, Step 4~9 를
   건너뛴다.
4. **Step 4 — 멱등성 검사 (모든 뮤테이션보다 앞).** 본문에 백링크 마커
   `Originated from discussion #<N>` 이 이미 있는 Issue 를 검색한다. 있으면
   `[OK] Discussion #<N> already converted to <url>` 을 찍고 exit 0. 검색 자체가
   실패하면(rate limit / auth) 경고만 하고 계속 진행한다 — 중복은 사람이 정리할 수
   있지만 조용한 abort 는 Issue 를 아예 남기지 않기 때문이다.
5. **Step 5 — Issue 생성.** 백링크를 앞에 붙인 원본 Discussion 본문으로
   `gh issue create` 를 실행하고 새 번호 `<M>` 을 잡는다. 실패하면 stderr 첫 줄과
   `[FAIL] Step 5` 를 찍고 abort — Step 6~8 은 돌지 않는다.
6. **Step 6~8 — 사후 뮤테이션 (전부 best-effort).**
   Step 6 보드 동기화(`In progress`, `--only-from "Backlog,Ready"`),
   Step 7 Discussion 에 `Linked to issue #<M> -- decision tracked there.` 코멘트,
   Step 8 닫기(`closeDiscussion` reason RESOLVED) + 잠그기(`lockLockable` reason
   RESOLVED). 이미 닫혔거나 잠긴 Discussion 은 해당 뮤테이션을 건너뛰고 리포트에
   `close=skip` / `lock=skip` 으로 보고한다.
7. **Step 9 — 리포트.** `[OK]` 라인 + `steps:` 요약 + `Next:` 힌트. 실패 시 실패한
   step 이름과 헬퍼 stderr 첫 줄을 인용한다.

## 주의사항과 제약

- **모든 `gh` 호출이 `GH_HOST` 와 `--repo` 를 함께 넘긴다 (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407).** 둘 다
  Step 1 이 같은 remote URL 에서 뽑은 쌍이고, `gh_discussion.sh` 의 GraphQL 헬퍼들도
  export 된 `GH_HOST` 를 상속한다. `--repo` 없는 `gh` 는 git 의 `origin` 이 아니라
  gh CLI 자신의 `gh repo set-default` 를 따라가므로, github.com 과 GHES 에 동시
  로그인한 상태면 에러 없이 남의 repo 에 Issue 를 만든다. 예상 밖의 `gh` 결과를
  `--repo` 를 빼거나 remote 를 바꿔서 우회하지 말고 host 를 먼저 검증한다.
  Step 6 의 보드 동기화 헬퍼에도 `--repo "$TARGET_REPO"` 를 명시한다(dEitY719/dotfiles#1405).
- **멱등이다.** 두 번 호출해도 Issue 가 두 개 생기지 않는다. Step 4 의 백링크 마커
  검색이 모든 뮤테이션보다 먼저 돌기 때문이다. 다만 백링크 마커가 검색 인덱스에
  반영되기 전에 재호출하면 중복이 가능하고, 그때는 사람 검토가 마지막 방어선이다.
- **`Ideas` 외 카테고리는 `--force-category` 없이 거부한다.** 운영 원칙 #2
  "결정되면 즉시 convert" 는 Ideas 버킷만을 가리킨다. Announcements 는 일회성,
  Lessons 는 Discussion-first, Q&A 는 답변되고 변환되지 않는 것 — 생애주기가 달라서
  트래커로 조용히 끌어오면 안 된다. 거부 메시지가 `dEitY719/dotfiles/docs/.ssot/discussions-policy.md`
  운영 원칙 #2 를 인용하는 것은 감사 기록에 기계적 거절이 아니라 정책 근거를 남기기
  위해서다. `--force-category` 는 1회용 우회이지 가드 제거가 아니다.
- **양방향 백링크 불변식을 지킨다.** Issue → Discussion 방향(Step 5 가 본문 앞에 붙이는
  `Originated from discussion #<N>`)은 **끌 수 있는 플래그가 없다**. Discussion → Issue
  방향(Step 7 코멘트)만 `--no-comment` 로 끌 수 있다. Step 5 만 성공하면 정책
  불변식은 이미 충족된 것으로 본다.
- **Step 5 이후 단계가 실패해도 새 Issue 를 롤백하지 않는다.** 백링크를 가진 Issue 가
  존재하는 순간 SSOT 사슬은 온전하므로, close / lock / comment 실패는 abort 가 아니라
  경고다. 반대로 Step 5 가 실패하면 Discussion 쪽 뮤테이션은 하나도 돌지 않는다.
- **존재하지 않는 `convertDiscussion` 엔드포인트를 쓰려 하지 않는다.** 2026-05 기준
  REST / GraphQL 어디에도 없어서 4개 원시 뮤테이션으로 UI 흐름을 흉내 낸다.
- **없는 remote 를 받았을 때 `origin` 으로 fallback 하지 않는다.**
- **Discussion 을 재분류하거나 다른 repo 로 옮기지 않는다.**
- **"변환할까요?" 같은 확인 질문을 하지 않는다.** 스킬 실행 자체가 컨펌이다.
