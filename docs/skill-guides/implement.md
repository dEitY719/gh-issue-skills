# `implement` — 이슈 구현 스킬 가이드

## 한 줄 요약

이슈 1건을 받아 **파일을 수정하고 테스트를 돌린다**. 산출물은 워킹 트리의 변경분과
테스트 결과 리포트다. 커밋도 PR 도 만들지 않는다.

## 언제 쓰고 언제 안 쓰는가

**쓸 때**

- 코드 변경을 요구하는 이슈를 실제로 구현할 때.
- 이미 전용 워크트리(예: `gwt`)를 만들고 그 안으로 `cd` 한 뒤.

**안 쓸 때 — 형제 스킬과의 경계**

`implement` 와 `proceed` 를 가르는 축은 **이슈의 종류**다.

| 이슈 종류 | 맞는 스킬 | 하는 일 |
|-----------|-----------|---------|
| 코드 변경 이슈 | `implement` | 파일을 고쳐 이슈를 만족시킨다 |
| 지시(directive) 이슈 — 8섹션 프로토콜이 본문에 박혀 있음 | `proceed` | 이슈가 품고 있는 프로토콜을 그대로 실행한다 |

그 외 경계:

- 이슈를 읽기만 할 거라면 `read`.
- 커밋은 `gh-pr:commit`, PR 은 `gh-pr:create`, 이슈부터 PR 까지 한 번에 엮는 것은
  `gh-flow:issue` 다. `implement` 는 "테스트 통과" 에서 멈춘다.
- 워크트리 생성은 `gwt` / `session:worktree-spawn` 의 몫이다.

## 호출 형식과 인자

```
/gh-issue:implement <issue-number> [mode] [remote] [--no-next-hint]
```

`references/help.md` 기준:

| # | 이름 | 기본값 | 설명 |
|---|------|--------|------|
| 1 | `<issue-number>` 또는 `-h` / `--help` / `help` | — | GitHub 이슈 번호 |
| 2 | `mode` | `direct` | `direct`, `plan`, `brainstorming` 중 하나 |
| 3 | `remote-name` | `origin` | 이슈를 소유한 repo 의 git remote |
| flag | `--no-next-hint` | off | Step 6 리포트의 마지막 `Next:` 힌트를 생략 |

사용 예:

| 명령 | 동작 |
|------|------|
| `/gh-issue:implement 16` | direct 모드 — 이슈를 읽고 구현하고 테스트. 사람 개입 없음 |
| `/gh-issue:implement 16 plan` | `superpowers:writing-plans` 먼저, 계획대로 구현 |
| `/gh-issue:implement 16 brainstorming` | brainstorming → plan → 구현 |
| `/gh-issue:implement 16 direct upstream` | `upstream` remote 의 repo 대상 direct 모드 |
| `/gh-issue:implement -h` | help verbatim 출력 후 종료. API 호출 0건 |

## 동작 단계 요약

1. **Step 1 — 인자 파싱 + repo 해석 + 전제조건.** `START_TS` 기록, remote URL 하나에서
   `TARGET_REPO` 와 `TARGET_HOST` 해석. 전제조건 3종을 병렬 검사하고 fail-fast 한다:
   git repo 안인가(`git rev-parse --show-toplevel`), 현재 브랜치가 기본 브랜치가
   **아닌가**(`gh repo view --json defaultBranchRef` 로 얻은 값과 비교),
   워킹 트리가 깨끗한가(`git status --porcelain` 이 비어 있는가).
2. **Step 2 — superpowers 플러그인 탐지.** 플러그인이 없으면 모드를 `direct` 로 강제하고
   경고 1줄. resolve 검사는 `test-driven-development`(Step 5 의 TDD 경로 게이트)와
   `subagent-driven-development`(Step 4 의 계획 경로 TDD 보장 게이트)를 함께 본다.
3. **Step 3 — 이슈 fetch + claim.** 3.1 fetch(CLOSED 는 거부) → 3.2 block-label 가드
   → 3.3 self-assign → 3.3b 중복 PR 소프트 경고 → 3.4 보드 카드 이동
   (`Backlog`/`Ready` 에서만 `In progress` 로) → 3.5 `Depends on #M` 소프트 경고.
   각 단계 뒤에 `[step:gh-issue-implement/<marker>] OK` 마커를 출력한다.
4. **Step 4 — 모드 디스패치.** `direct` 는 바로 Step 5. `plan` 은 모호성 신호가 있으면
   `brainstorming` 으로 승격, 아니면 `writing-plans`. `brainstorming` 은 설계 후 계획,
   승인 뒤 Step 5.
5. **Step 5 — 구현 + 테스트.** 공통 단계(fetch, 의도 추출, repo 스캔, `$TEST_CMD` 탐지,
   **편집 전 baseline** 캡처) 후 분기한다. 러너가 검출되고 superpowers 도 있으면
   **TDD 경로**(시도 횟수 제한 없음, 판단으로 멈춤), 그 외에는 **fallback 경로**
   (편집 → 러너가 있으면 테스트 → 실패 루프 최대 3회). 러너가 없으면 baseline 과 테스트
   단계를 건너뛰고 "No test runner detected, skipping tests." 로 보고한다.
6. **Step 6 — 리포트.** 변경 파일, 어떤 경로가 돌았는지(`tdd`/`fallback`), 테스트 결과,
   ai-metrics 라인, 그리고 `--no-next-hint` 가 없으면 `Next:` 힌트.

## 주의사항과 제약

- **모든 `gh` 호출이 `GH_HOST` 와 `--repo` 를 함께 넘긴다 (dEitY719/dotfiles#1403).** 두 값은 Step 1 이
  같은 remote URL 에서 뽑은 쌍이다. `--repo` 가 없으면 gh CLI 는 git 의 `origin` 이 아니라
  자기 `gh repo set-default` 를 따라가고, github.com 과 GHES 동시 로그인 상태에서는
  **에러 없이 성공한다** — OPEN 이슈가 "없음" 으로 돌아오고, 쓰기(self-assign, 보드 이동)는
  남의 이슈 #N 에 꽂힌다. 이상한 `gh` 결과를 재시도, `--repo` 제거, remote 교체로 우회하지
  말고 host 를 먼저 검증할 것.
- **block label 은 우회 불가능한 하드 거부.** `GH_ISSUE_BLOCK_LABELS`
  (기본값: `do-not-work`, `on-hold`, `보류`, `Postpone` 계열, `reference`) 중 하나라도 이슈에 붙어 있으면
  Step 3.2 가 fail-closed 로 **exit 2** 하고 멈춘다. 이 계열에서 exit 2 는 "정책상 거부",
  exit 1 은 "스킬이 깨짐" 을 뜻한다. 강제 실행 플래그는 제안됐다가 기각됐다 — 라벨을 떼는
  것만이 유일한 해제 방법이다.
- **커밋도 PR 도 만들지 않는다.** "파일 수정됨, 테스트 돌림" 에서 멈춘다. 사람이 diff 를
  먼저 보고, 여러 시도를 하나로 squash 하고, repo 별 커밋 스타일을 고를 수 있게 하기 위한
  의도적 경계다. 여기서 `git commit` 을 실행하려 한다면 멈추고 리포트를 출력할 것.
- **워크트리를 만들지 않는다.** 이 스킬이 돌 때 사용자는 이미 올바른 디렉터리에 있다.
  내부에서 워크트리를 만들면 중첩되어 정리 흐름을 망친다.
- **기본 브랜치에서 실행하지 않는다.** `main` / `master` 에서 직접 구현하면 진행 중인 모든
  피처 브랜치의 base 가 오염된다. Step 1 이 이를 강제하며, 걸리면 우회하지 않는다.
- **기존 실패 테스트를 고치지 않는다.** 첫 편집 **이전**에 찍은 baseline 이 PRE-EXISTING
  (이 스킬 실행 전부터 실패)과 CAUSED(이 스킬 편집이 유발)를 가른다. PRE-EXISTING 은
  리포트에만 적고 고칠지 여부는 사람이 정한다. 이 규칙은 **모든 경로에 적용되며**, TDD
  스킬의 "Other tests fail? Fix now." 문구보다 우선한다. TDD 스킬 자체를 고쳐서 이 예외를
  박아 넣지 말 것.
- **테스트 실패 루프는 최대 3회** — fallback 경로에 한정된 카운터다. TDD 경로에는 카운터가
  없고 앞으로도 만들지 않는다. 같은 실패 반복, 초록 테스트를 깨는 수정, 설명 불가한 실패에서
  판단으로 멈춘다.
- **superpowers 를 필수로 요구하지 않는다.** `direct` 모드는 항상 동작하고, fallback 경로는
  baseline 캡처, 편집, 테스트, 제한된 실패 루프, 완전한 리포트를 갖춘 **온전한** 흐름이다.
  열등한 경로가 아니라 같은 결승선으로 가는 다른 길이다.
