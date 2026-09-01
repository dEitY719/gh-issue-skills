# `discussion-create` — 대화를 RFC Discussion 으로 남기는 스킬 가이드

## 한 줄 요약

현재 대화를 **GitHub Discussion 1건**(기본 카테고리 `Ideas`, RFC 형태)으로 만든다.
`createDiscussion` GraphQL 뮤테이션으로 Open-Questions 중심 본문을 올리고, 화면에는
생성된 Discussion URL 만 출력한다.

## 언제 쓰고 언제 안 쓰는가

**쓸 때**

- 아직 결론이 나지 않은 설계 탐색 — "할까 말까", 대안 비교, 열린 질문이 남은 대화.
- 스스로에게 남기는 "왜 X 를 Y 방식으로 했지?" 같은 질문 기록(`Q&A`).
- SSOT/정책 변경 공지(`Announcements`), 재사용 가능한 학습 기록(`Lessons`).

**안 쓸 때 — 형제 스킬과의 경계**

`create` 와 `discussion-create` 를 가르는 기준은 주제도 규모도 아니고 **결정됨
(decidedness)** 단 하나다.

| 대화의 상태 | 맞는 스킬 | 근거 |
|-------------|-----------|------|
| 수렴된 to-do — 무엇을 어떻게 할지 정해짐 | `create` (Issue) | 운영 원칙 #1 "Issue is default" |
| 열린 질문이 남은 RFC — 아직 결정 전 | `discussion-create` (Discussion) | 추적 대상이 되기엔 너무 이르다 |
| 결정 자체가 끝난 뒤의 공지/회고 | `discussion-create` | 추적 대상이 되기엔 너무 늦음 |

Discussion 은 Issue 로 추적하기에 **너무 이르거나(RFC) 너무 늦은(공지·학습)** 항목을
담는 자리다. 그래서 Step 2.1 의 라우팅 가드가 "결정된 to-do" 신호를 감지하면 뮤테이션을
호출하지 않고 `/gh-issue:create` 로 되돌려 보낸다.

반대 방향의 다리는 `discussion-convert` 다. 열린 질문이 나중에 결정되면 그 Discussion 을
Issue 로 승격시켜 트래커로 되돌린다.

## 호출 형식과 인자

```
/gh-issue:discussion-create [remote] [category] [--force-discussion]
```

`references/help.md` 기준 인자:

| # | 이름 | 기본값 | 설명 |
|---|------|--------|------|
| 1 | remote-name **또는** category, 또는 `-h` / `--help` / `help` | `origin` / `Ideas` | 첫 번째 non-flag positional. `Ideas`, `Q&A`, `Announcements`, `Lessons` 중 하나면 카테고리로, 아니면 remote 이름으로 해석 |
| 2 | 남은 하나 (remote 또는 category) | 위 참조 | 두 번째 positional 이 비어 있는 슬롯을 채운다 |

플래그와 환경 변수:

| 이름 | 기본값 | 설명 |
|------|--------|------|
| `--force-discussion` | off | Step 2.1 라우팅 가드 우회. 결정된 to-do 처럼 보이지만 실제로는 RFC 인 대화용. 가드의 판단 근거는 감사용으로 한 번 출력된다 |
| `GH_DISABLE_AI_METRICS=1` (env) | off | Discussion 본문의 ai-metrics footer 생략 (#399 parity) |

사용 예:

| 명령 | 동작 |
|------|------|
| `/gh-issue:discussion-create` | `origin` repo 에 `Ideas` Discussion 생성 |
| `/gh-issue:discussion-create upstream` | `upstream` repo 에 `Ideas` Discussion 생성 |
| `/gh-issue:discussion-create Q&A` | `origin` repo 에 `Q&A` Discussion 생성 |
| `/gh-issue:discussion-create upstream Lessons` | `upstream` repo 에 `Lessons` Discussion 생성 |
| `/gh-issue:discussion-create -h` | help 를 verbatim 출력하고 종료. API 호출 0건 |

카테고리 4종과 본문 골격은 `references/category-table.md` 가 SSOT 다.

| 카테고리 | 고를 때 | 기본 본문 골격 |
|----------|---------|----------------|
| `Ideas` (기본) | RFC, 설계 탐색, "할까 말까" | TL;DR + Why + Goals/Non-Goals + Requirements + Design + Alternatives + Open Questions |
| `Q&A` | 자문 또는 외부 질문 | Q(1줄) + Context + Best answer so far + Follow-up |
| `Announcements` | SSOT/정책 변경 공지 | Announcement(1~2줄) + Background + Effective date + Links |
| `Lessons` | 재사용 가능한 학습 | Source link + Summary + Key takeaways + When to revisit |

어느 쪽에도 깔끔히 맞지 않으면 `Ideas` 로 떨어진다. NLP 식 자동 분류는 목표가 아니다.

## 동작 단계 요약

SKILL.md 의 Step 구조는 5단계(+ 3.5)다.

1. **Step 1 — repo 컨텍스트 감지.** `START_TS` 기록, 인자 파싱, git repo 확인,
   remote URL 에서 `TARGET_REPO=<owner>/<repo>` 해석. remote 가 없으면 즉시 실패하고
   `origin` 으로 조용히 되돌아가지 않는다.
2. **Step 2 — 대화 분류.** 카테고리를 정확히 하나 고른다(기본 `Ideas`). 명시적
   `[category]` 를 줘도 Step 2.1 가드는 그대로 돈다 — 바뀌는 것은 본문 골격뿐이다.
3. **Step 2.1 — 라우팅 가드.** `references/scope-guard.md` 의 신호를 적용한다.
   **결정된 to-do** 신호(구체적·시한 있는 acceptance criteria / 확정된 구현 계획 /
   담당자 지정 / PR·브랜치 예정)가 하나라도 매치되면 "Refusal format" 을 출력하고
   멈춘다. **모호함** 신호(동사 없는 명사 나열, 컴포넌트 3개 이상 혼재, Open Questions
   부재)면 거부 대신 1~2줄 확인 질문을 던지고 답을 기다린다.
4. **Step 3 — 본문 작성.** `references/rfc-template.md` 골격에 맞춰 대화 언어로 쓴다.
   과압축 금지 — 파일 경로, 출력, 결정과 트레이드오프, 논의 로그를 보존한다.
   200줄짜리 RFC 도 괜찮다.
5. **Step 3.5 — ai-metrics 계산.** `create` 의 `references/metrics-baseline.md` 를 읽어
   `TOKENS`, `HUMAN_H`, `ELAPSED` 를 바인딩한다.
6. **Step 4 — 생성.** `gh_discussion.sh` 를 source 하고 `references/create-cmd.md` 의
   bash 블록을 verbatim 실행한다 — 임시 본문 파일, `GH_DISABLE_AI_METRICS=1`
   숏서킷, ai-metrics footer, 3개의 GraphQL 호출(repo node ID 조회, category ID 조회,
   `createDiscussion`)을 처리한다. 확인 질문 없이 즉시 실행한다.
7. **Step 5 — 리포트.** `[OK]` / `[FAIL]` 블록과 `Next:` 힌트를 출력한다. Step 2.1
   거부는 자체 메시지를 찍고 Step 3~5 를 통째로 건너뛴다.

## 주의사항과 제약

- **모든 `gh` 호출은 `--repo "$TARGET_REPO"` 를 명시한다.** 암묵적 repo 감지에
  의존하지 않는다. 이 계열 전체의 규약은 `GH_HOST` 와 `--repo` 를 **같은 remote URL
  에서 뽑아 함께** 넘기는 것이다(#1403). `--repo` 없는 `gh` 는 git 의 `origin` 이 아니라
  gh CLI 자신의 `gh repo set-default` 를 따라가므로, github.com 과 GHES 에 동시
  로그인한 상태면 에러 없이 다른 서버에 글을 쓴다. 예상 밖의 `gh` 결과를 `--repo` 를
  빼거나 remote 를 바꿔서 우회하지 말고 host 를 먼저 검증한다.
- **라우팅 가드를 SSOT 갱신 없이 끄지 않는다.** 가드는 issue #617 의 F-3 + F-4 를
  구현한 load-bearing 요구사항이다. 이것이 없으면 "이제 X 를 코딩하겠다" 급 대화가
  전부 `Ideas` 에 쌓이고, 칸반 보드가 없는 Discussions 포럼이 사실상의 이슈 트래커가
  되며, `discussion-convert` 의 백링크 감사 사슬이 의미를 잃는다. `--force-discussion`
  은 **1회용 우회 전용**이지 가드 제거가 아니다. 가드를 없애고 싶다면
  `docs/.ssot/discussions-policy.md` 를 먼저 고쳐야 한다.
- **`Ideas` 외 카테고리에서도 가드는 동일하게 작동한다.** 바뀌는 것은 본문 골격뿐이다.
- **없는 remote 를 받았을 때 `origin` 으로 fallback 하지 않는다.** 오타를 가려서 엉뚱한
  repo 에 Discussion 을 올리게 되기 때문이다.
- **대화 로그를 2~3줄로 압축하지 않는다.** Discussion 은 future-self 검색의 1차 SSOT
  이고, 나중에 `discussion-convert` 가 이슈 본문의 씨앗으로 재사용한다.
- **Discussion 카테고리를 자동 생성하지 않는다.** API 가 허용하지 않으므로 사용자가
  repo 설정에서 먼저 만들어 두어야 한다.
- **카테고리 ID 를 디스크에 캐시하지 않는다.** 조회는 GraphQL 한 번이면 되고, 캐시
  staleness 위험이 절약보다 크다 (`references/cache-decision.md`).
- **"만들까요?" 같은 확인 질문을 하지 않는다.** 스킬 실행 자체가 컨펌이다.
