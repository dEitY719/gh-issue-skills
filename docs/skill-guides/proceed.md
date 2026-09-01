# `proceed` — 지시 이슈 프로토콜 실행 스킬 가이드

## 한 줄 요약

**지시 이슈(directive issue)가 본문에 embed 한 8섹션 프로토콜을 무인으로 끝까지
실행한 결과**가 산출물이다. 각 단계의 실행 기록, 안전 게이트 판정, 프로토콜이 허가한
쓰기 동작(commit / PR / comment / close / follow-up 이슈), 그리고 마지막의 감사 리포트가
전부 여기에 포함된다.

## 언제 쓰고 언제 안 쓰는가

**쓸 때**

- 이슈 본문 자체가 실행 가능한 작업 지시서인 경우 — 번호 매긴 절차 또는 workflow
  매트릭스와 결정 규칙, 산출물, 종료 조건이 이미 적혀 있는 이슈.
- verify / triage / 분석 / docs-ship 처럼 "무엇을 어떤 순서로 할지" 가 사람에 의해
  이미 설계된 작업. 스킬은 그 설계를 **실행**할 뿐 작성하거나 고치지 않는다.
- 사람이 중간에 붙어 있지 않아도 되는 무인 실행이 필요할 때.

**안 쓸 때 — 형제 스킬과의 경계**

| 상황 | 맞는 스킬 |
|------|-----------|
| "이 이슈대로 코드를 고쳐라" 형태의 코드 변경 이슈 | `implement` |
| 이슈 본문을 그대로 읽고 싶을 뿐 | `read` |
| PR 을 머지해야 함 | `/gh-pr:merge` / `/gh-pr:merge-emergency` |
| 지시 이슈 자체를 작성해야 함 | 사람 또는 `/spec-flow:trd-to-issues` |

`proceed` 와 `implement` 는 같은 슬롯의 형제다. **`implement` 는 코드 변경 이슈를 보고
파일을 편집**하고, **`proceed` 는 지시 이슈가 embed 한 8섹션 프로토콜을 무인 실행**한다.
지시 이슈는 이미 설계가 끝난 상태이므로 `proceed` 에는 `mode` 인자가 없다 — 실행 모드는
항상 `direct` 이고 plan / brainstorming 으로 분기하지 않는다.

## 호출 형식과 인자

```
/gh-issue:proceed <issue-number> [remote]
```

`references/help.md` 기준 인자:

| # | 이름 | 기본값 | 설명 |
|---|------|--------|------|
| 1 | `<issue-number>` 또는 `-h` / `--help` / `help` | — | 실행할 GitHub 지시 이슈 번호 (양의 정수) |
| 2 | `remote-name` | `origin` | 이슈를 소유한 repo 의 git remote 이름 |

사용 예:

| 명령 | 동작 |
|------|------|
| `/gh-issue:proceed 81` | `origin` repo 의 지시 이슈 #81 을 읽고, 스키마 검증 후 끝까지 실행 |
| `/gh-issue:proceed 81 upstream` | 같은 동작을 `upstream` remote 의 repo 에 대해 수행 |
| `/gh-issue:proceed -h` | help 를 verbatim 출력하고 종료. API 호출 0건 |

환경 변수:

| 변수 | 기본값 | 효과 |
|------|--------|------|
| `GH_ISSUE_BLOCK_LABELS` | `do-not-work,on-hold,보류,Postpone` | 차단 라벨 목록 (claim 가드) |
| `GH_ISSUE_SKIP_SELF_ASSIGN` | unset | `1` 이면 self-assign 생략 |
| `GH_ISSUE_SKIP_BOARD_TRANSITION` | unset | `1` 이면 보드 전이 생략 |
| `GH_ISSUE_SKIP_DEPS_CHECK` | unset | `1` 이면 depends-on 가드 생략 |
| `GH_DISABLE_AI_METRICS` | unset | `1` 이면 ai-metrics 라인 생략 |

## 동작 단계 요약

SKILL.md 의 Step 구조는 4단계이며, 각 단계 성공 시
`[step:gh-issue-proceed/<id>] OK` 마커(`fetch-issue`, `schema-valid`, `execute`,
`report`)를 출력한다.

1. **Step 1 — 인자 파싱 + repo 해석.** `START_TS` 기록, 하나의 remote URL 에서
   `TARGET_REPO` 와 `TARGET_HOST` 를 함께 뽑고 `GH_HOST` 를 export 한다. remote 가
   없으면 `git remote -v` 를 보여주고 멈춘다 — 조용한 `origin` fallback 없음.
2. **Step 2 — fetch + claim + 스키마 검증.**
   2.1 fetch → 차단 라벨 가드 → self-assign → 보드 전이 → depends-on 의 5개 claim
   substep. CLOSED 이슈 거부는 스키마 검증보다 앞선다.
   2.2 본문을 아래 8섹션 스키마에 대해 엄격 검증. 누락/공백/파싱 불가 섹션이 하나라도
   있으면 실패 블록을 출력하고 STOP.
   2.3 전제조건 분류(read-only / mutation-required / mixed / verify-only). 기본 브랜치나
   dirty tree 에서의 `mutation-required` 는 STOP.
3. **Step 3 — 프로토콜 실행.** 4단계로 진행한다: pre-flight(Layer 3) → `execution_protocol`
   파싱(알 수 없는 verb 는 파싱 시점에 fail-closed) → step 루프(`TaskCreate` → Layer-1
   금지사항과 Layer-4 모니터 아래 실행 → `decision_rules` 대조 분류 → 매핑된 verb 적용 →
   `TaskUpdate`) → `done_criteria` 대조. 전부 충족되고 abort 가 없으면 이슈를
   self-close + 코멘트, 아니면 `N/M criteria met` 로 열어 둔다.
4. **Step 4 — 리포트.** step 별 표, 쓰기 동작 감사, done-criteria 대조, 최종 결과를
   출력하고 ai-metrics 라인을 덧붙인다.

### 필수 8섹션 스키마 (Step 2.2)

`references/protocol-schema.md` 가 SSOT 다. 각 섹션은 H2/H3 heading 의 정규화된
텍스트가 alias 중 하나와 대소문자 무시 부분일치할 때 매칭된다. "공백"은 앞뒤 공백,
마크다운 리스트 마커(`-`, `*`, `1.`), 코드펜스 구분자를 제거한 뒤 50자 미만인 경우다.

| # | 키 | Alias | 실패 규칙 |
|---|-----|-------|-----------|
| 1 | `goal` | `Goal`, `목표` | 비어 있으면 실패 |
| 2 | `preconditions` | `Preconditions`, `사전 조건`, `Prerequisites` | 비어 있으면 실패 |
| 3 | `execution_protocol` | `Execution Protocol`, `Execution Matrix`, `실행 절차`, `Steps` | 비어 있거나 파싱 가능한 step 이 없으면 실패 |
| 4 | `decision_rules` | `Decision Rules`, `결정 규칙`, `Branching`, `Decision matrix` | 비어 있으면 실패 |
| 5 | `deliverables` | `Deliverables`, `산출물`, `Output`, `Outputs` | 비어 있으면 실패 |
| 6 | `done_criteria` | `Done Criteria`, `종료 조건`, `Acceptance`, `Acceptance Criteria` | `- [ ]` / `- [x]` 체크리스트 항목이 없으면 실패 |
| 7 | `out_of_scope` | `Out of Scope`, `Out-of-scope`, `범위 밖` | 비어 있으면 실패 |
| 8 | `safety` | `Safety`, `Safety / Abort`, `Abort`, `안전 규칙`, `Safety Rules` | 비어 있으면 실패 |

선택 섹션은 `background`, `references`, `track`(mutation 자동 감지를 덮어쓰는
`verify-only` 선언) 세 개이며, 있으면 파싱한다. `execution_protocol` 의 step 파싱은
매트릭스 모드(`#` + `Workflow`/`Step` + `Command`/`명령` 헤더를 가진 표)와 넘버링
모드(`^### \d+\.` 또는 `^\d+\.`) 두 가지를 자동 감지한다.

## 주의사항과 제약

- **모든 `gh` 호출이 `GH_HOST` 와 `--repo` 를 함께 넘긴다 (#1403 / #1407).** 둘 다
  Step 1 이 같은 remote URL 에서 뽑은 쌍이어야 한다. `--repo` 없는 `gh` 는 git 의
  `origin` 이 아니라 gh CLI 자신의 `gh repo set-default` 를 따라가므로, github.com 과
  GHES 에 동시 로그인한 상태에서는 에러 없이 조용히 다른 서버로 간다. 읽기라면 OPEN
  이슈가 "없음" 으로 보이고, 쓰기라면 남의 repo 이슈 #N 에 착지한다. 예상 밖의 `gh`
  결과를 `--repo` 를 빼거나 remote 를 바꿔서 우회하지 말고 host 를 먼저 검증한다.
- **차단 라벨은 우회 플래그 없는 하드 거부다.** `do-not-work`, `on-hold`, `보류`,
  `Postpone` 등 `GH_ISSUE_BLOCK_LABELS` 에 있는 라벨이 붙어 있으면 claim 단계
  2.1.2 에서 `exit 2` 로 즉시 중단한다. 우회용 환경 변수나 force 플래그는 의도적으로
  존재하지 않으며, 라벨을 떼는 것만이 유일한 해제 방법이다. 이 계열에서 **`exit 2` 는
  "정책 거부", `exit 1` 은 "스킬이 고장남"** 으로 예약된 구분이다.
- **스키마를 엄격 검증하고 누락 섹션을 추측하지 않는다.** 8섹션 중 하나라도 없거나
  비어 있거나 파싱 불가면 실패 블록만 출력하고 STOP 한다. 그리고 **스키마 실패 시
  이슈에 코멘트를 쓰지 않는다** — 스키마 실패는 caller-side 문제이고, 잘못된 지시서에
  쓰기를 하면 쓰레기를 근거로 행동하게 되기 때문이다.
- **안전 게이트는 fail-closed 다.** Layer 1(절대 금지)은 이슈 본문이 허가해도 무시하고
  중단한다: 기본 브랜치 force-push, 모든 force-push(`--force-with-lease` 만 예외), `$PWD`
  밖 `rm -rf`, 파괴적 DB 조작, 출력에 섞인 시크릿, 다른 worktree 로의 쓰기, `gh pr merge`,
  브랜치 삭제, 남이 닫은 이슈 재오픈. 패턴 매칭은 대소문자 무시 + 따옴표 허용이라
  사소한 난독화로는 우회되지 않는다. 시크릿 스캐너는 유일하게 절대 override 불가다.
- **조건부 권한은 default-deny 다.** bulk-close(≥5), bulk-create-issue(≥5),
  force-with-lease, 비허용 아웃바운드 네트워크, cross-repo 뮤테이션은 이슈 본문
  `§safety` 에 대응하는 `allow:` 토큰(`allow: bulk-close`, `allow: bulk-create-issue`,
  `allow: force-with-lease`, `allow: net: <host glob>`, `allow: cross-repo: <owner/repo>`)이
  정확히 있을 때만 허용된다. 토큰이 없으면 Layer-1 abort 로 승격된다.
- **결과 클래스나 액션 verb 를 지어내지 않는다.** `decision_rules` 와 고정된 verb
  레지스트리에 대해 fail-closed 로 동작한다.
- **`mutation-required` 를 기본 브랜치나 dirty tree 에서 실행하지 않는다.**
- **런타임 모니터가 항상 걸려 있다.** step 당 5분 / 전체 60분 타임아웃(`§preconditions`
  에서 상향 가능), 출력 시크릿 스캐너(override 불가), 쓰기 동작 쿼터(타입별 5, 전체 20 —
  `§safety` 토큰으로 타입별만 50 까지 상향 가능하고 전체 20 은 `allow: total-quota: <N>`
  이 따로 있어야 바뀐다). proceed 이슈 자신에 대한 코멘트와 self-close 는 쿼터에
  포함되지 않는다.
- **지시서를 작성하거나 편집하지 않는다.** 그것은 사람 또는 `/spec-flow:trd-to-issues`
  의 몫이다. PR 머지도 이 스킬의 범위 밖이다.
