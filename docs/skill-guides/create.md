# `create` — 대화를 이슈로 등록하는 스킬 가이드

## 한 줄 요약

지금까지의 대화를 conventional-commit prefix 로 분류해 **GitHub Issue 1건**을 만든다.
산출물은 실제로 생성된 이슈이며, 출력은 `Issue #N created: <url>` 한 줄이다.

## 언제 쓰고 언제 안 쓰는가

**쓸 때**

- 대화에서 무엇을 할지가 **이미 결정된** 상태이고, 그 결정을 추적 가능한 카드로
  남기고 싶을 때.
- 자동 라벨/마일스톤(SSOT `.gh-issue-defaults.yml`)과 선행 이슈 링크까지 한 번에
  붙이고 싶을 때.

**안 쓸 때 — 형제 스킬과의 경계**

`create` 와 `discussion-create` 를 가르는 축은 **결정됨(decidedness)** 하나다.

| 대화 상태 | 맞는 스킬 | 산출물 |
|-----------|-----------|--------|
| 결론이 났고 할 일이 정해짐 | `create` | Issue |
| 아직 논의 중, 미결이 본질 (RFC) | `discussion-create` | Discussion |

`create` 는 대화가 수렴하지 않았으면 **멈추고 묻는다** (Step 2.1 / Step 3.1).
대화가 결정하지 않은 요구사항을 그럴듯하게 지어내서 이슈로 만드는 일은 없다.
반대로 `discussion-create` 는 이미 결정된 to-do 를 받으면 거부하고 `create` 를 권한다.

두 방향 모두 명시적 사용자 의도로만 넘어간다. `--as-discussion <category>` 로 이
스킬에서 Discussion 경로로 넘길 수는 있지만, AI 가 "이건 Discussion 같다" 고 스스로
판정해 분기하는 것은 금지다 (dEitY719/dotfiles#619 Non-Goal).

이슈 내용을 실제로 구현하는 것은 `implement` 의 몫이다. `create` 는 코드를 만지지 않는다.

## 호출 형식과 인자

```
/gh-issue:create [remote] [flags]
```

`references/help.md` 기준 — 인자:

| # | 이름 | 기본값 | 설명 |
|---|------|--------|------|
| 1 | `remote-name` 또는 `-h` / `--help` / `help` | `origin` | 새 이슈를 소유할 repo 의 git remote |

플래그:

| 플래그 | 기본값 | 설명 |
|--------|--------|------|
| `--no-auto-labels` | off | Step 2.5 스킵 — `.gh-issue-defaults.yml` 기반 라벨/마일스톤 자동 부착 안 함. 사용자가 준 `--label` 은 그대로 적용 |
| `--no-auto-deps` | off | Step 2.6 스킵 — 대화 속 선행-이슈 문구 탐지와 Step 4.5 의 `addBlockedBy` 링크를 모두 안 함 |
| `--auto-label-debug` | off | 이슈 생성 전에 Stage-1 탐지 트레이스와 kept/dropped 라벨 집합을 stderr 로 출력 |
| `--no-ask` | off | Step 3.1 미결 게이트에서 묻지 않고 자율 결정. repo 관행 → 보수적 선택 → 별도 이슈로 분리 순으로 정하고 `(자율 판단)` + 근거를 기록. 게이트를 끄는 플래그가 아니다 |
| `--as-discussion <category>` | off | Issue 대신 `discussion-create` 로 라우팅. `Ideas` / `Q&A` / `Announcements` / `Lessons` (대소문자 무관). Step 2.5 스킵, `--label` / `--assignee` 는 경고 1줄과 함께 무시. 잘못된 카테고리는 API 호출 없이 exit 3 |

이 밖에 `--label`, `--assignee @me`, 환경변수 `GH_DISABLE_AI_METRICS=1` 이 있다
(전체 목록은 `references/options.md`).

사용 예: `/gh-issue:create`, `/gh-issue:create upstream`,
`/gh-issue:create --no-auto-labels`, `/gh-issue:create --as-discussion Ideas`,
`/gh-issue:create -h`.

## 동작 단계 요약

1. **Step 1 — repo 컨텍스트 탐지.** `START_TS` 기록, git repo 확인, 지정 remote 의 URL
   하나에서 `TARGET_REPO` 와 `TARGET_HOST` 를 함께 해석하고 `GH_HOST` export.
2. **Step 2 — 대화 분류.** `references/prefix-table.md` 로 `feat` / `fix` / `refactor` /
   `perf` / `docs` / `test` / `chore` / `misc` 중 지배적 의도 하나를 고른다. 이 선택이
   제목 형식과 본문 템플릿(`references/templates/<prefix>.md`)을 결정한다.
3. **Step 2.1 — 확인 및 범위 가드.** 동사 없는 명사 나열, 컴포넌트 3개 이상 혼재,
   범위 미정의 같은 신호가 잡히면 1~2줄 확인이나 분리안을 먼저 보내고, 응답 전에는
   `gh issue create` 를 호출하지 않는다.
4. **Step 2.5 — 자동 라벨 + 마일스톤.** SSOT 파일이 있을 때만. `gh label list` 검증을
   통과한 라벨만 남기며, 없는 라벨을 자동 생성하지 않는다.
5. **Step 2.6 — 의존성 자동 탐지.** `#13 완료 후`, `depends on #13` 같은 명시 문구만
   잡아 `DEP_NUMS` 로 보관한다. GitHub 상태를 건드리지 않는다.
6. **Step 3 / 3.1 — 본문 초안 + 미결 게이트.** 템플릿으로 본문을 쓰되 압축하지 않는다.
   초안에 미결이 남아 있으면 결정으로 전환하기 전까지 이슈를 만들지 않는다.
7. **Step 3.5 / 4 / 4.5 — 메트릭 계산, 이슈(또는 Discussion) 생성, 선행 링크.**
   생성은 `mktemp` 임시 파일을 통해 이뤄지고, 링크는 이슈 번호가 생긴 뒤에 붙는다.
8. **Step 5 — 리포트.** `[OK]` / `[FAIL]` 판정 한 줄과 `Next:` 힌트로 끝난다.

## 주의사항과 제약

- **모든 `gh` 호출이 `GH_HOST` 와 `--repo` 를 함께 넘긴다 (dEitY719/dotfiles#1403).** 두 값은 Step 1 이
  같은 remote URL 에서 뽑은 쌍이며 절대 따로 구하지 않는다. `--repo` 가 없으면 gh CLI 가
  자기 `gh repo set-default` 를 따라가, dual-host 로그인에서 **에러 없이 엉뚱한 서버에
  이슈를 만든다**. 쓰기 스킬이므로 이 실패는 되돌리기 어렵다.
- **지정한 remote 가 없으면 즉시 실패한다.** `origin` 으로 조용히 되돌아가지 않는다.
- **대화가 결정하지 않은 요구사항을 만들어 내지 않는다.** 수렴하지 않은 대화는 멈추고
  묻는다. 미결을 본문에서 지워서 게이트를 통과시키는 것도 금지이며, 결정으로 전환하거나
  `--no-ask` 로 자율 결정하고 근거를 `## 확정 사항 (Decisions)` 에 남긴다 (dEitY719/dotfiles#1446).
- **압축 금지.** 파일 경로, 명령 출력, 에러 로그, 결정과 그 근거, 논의 로그를 그대로
  남긴다. 200줄짜리 이슈도 대화가 그럴 만했다면 정상이다. Discussion 경로에서도 동일하다.
- **"만들까요?" 라고 묻지 않는다.** 스킬을 실행한 것 자체가 확인이다.
- **`--assignee` 는 사용자가 요청했을 때만** 붙는다.
- **선행 링크 실패는 non-fatal.** 이슈는 이미 만들어진 뒤이므로 중단하거나 재시도하지
  않고 `[WARN]` 한 줄과 `원인:` 라인만 남긴다 (dEitY719/dotfiles#1424 NF-1).
- **오탐 링크 금지.** `#13 참고` 같은 단순 언급으로는 링크하지 않고, `owner/repo#13`
  cross-repo 참조는 v1 범위 밖이라 경고 후 스킵한다 (dEitY719/dotfiles#1424 NF-2).
