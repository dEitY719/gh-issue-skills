# discussion-create 사용 결과

> **한 줄 요약** — 현재 대화를 받아 라우팅 판정(또는 Discussion 1건)을 생성합니다.

```
현재 대화  ──▶  /gh-issue:discussion-create  ──▶  라우팅 가드 판정 (터미널 출력)
```

GitHub 쓰기 0건 — 비변경 경로만 실행했습니다.

## 1. 실행한 명령

```
/gh-issue:discussion-create [remote] [category] [--force-discussion]
```

이번 실행: `/gh-issue:discussion-create --help` (Step 2.1 라우팅 가드는 현재 대화에 적용)

## 2. 입력

- help 경로: 인자 `--help` 하나. API 호출 없음.
- 라우팅 가드 경로: 현재 대화 자체. `references/scope-guard.md` 의 decided-to-do
  신호 목록과 대조.

## 3. 결과

help 출력 실측: 85 lines / 3,914 chars, 8개 섹션 (Arguments, Flags, Env Vars, What the
skill does, Title format, Detail preservation, What the skill will NOT do, Related skills).

Step 2.1 라우팅 가드 실측: decided-to-do 신호 2개가 매치되었습니다.

- 신호 #1 (Acceptance criteria 가 구체적) — "4. 검증" 의 6열 확인표, 링크 수 = 스킬 수 x 2
  카운트 규칙
- 신호 #2 (구현 계획 확정) — `docs/skill-guides/<skill>.md`,
  `docs/skill-output/<skill>-usage.md` 파일 경로가 명시됨

따라서 거부 경로로 진입해 뮤테이션을 호출하지 않았고 Step 3~5 를 건너뛰었습니다.
출력은 `references/scope-guard.md` 의 "Refusal format" 그대로이며, 권장 대체 명령으로
`/gh-issue:create` 를, 우회 수단으로 `--force-discussion` 을 안내합니다.
