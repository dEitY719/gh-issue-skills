# proceed 사용 결과

> **한 줄 요약** — 지시 이슈 본문을 받아 8섹션 스키마 판정과 실행 결과를 생성합니다.

```
지시 이슈 본문  ──▶  /gh-issue:proceed  ──▶  스키마 판정 (터미널 출력)
```

GitHub 쓰기 0건 — 비변경 경로만 실행했습니다.

## 1. 실행한 명령

```
/gh-issue:proceed <issue-number> [remote]
```

이번 실행: `/gh-issue:proceed --help` (Step 2.2 스키마 검증은 dotfiles#1676 본문에 적용)

## 2. 입력

- help 경로: 인자 `--help` 하나. API 호출 없음.
- 스키마 검증 경로: `dEitY719/dotfiles` 이슈 #1676 의 본문. 지시 이슈가 아닌
  일반 feat 이슈를 대상으로 `references/protocol-schema.md` 의 8섹션 스키마를 적용.

## 3. 결과

help 출력 실측: 81 lines / 3,592 chars, 8개 섹션 (Arguments, Usage, What a directive
issue is, The 8 required sections (strict schema), What the skill does, Safety posture,
What the skill will NOT do, Environment variables).

Step 2.2 스키마 검증 실측: 본문 heading 18개를 스캔해 8개 필수 섹션 + alias 와 대조한
결과 `goal` 만 present, 나머지 7개(`preconditions`, `execution_protocol`,
`decision_rules`, `deliverables`, `done_criteria`, `out_of_scope`, `safety`)는 MISSING.
8개 중 7개 누락이므로 SCHEMA INVALID 판정 후 STOP.

스킬 규약대로 이슈에 코멘트를 쓰지 않았습니다 — 스키마 실패는 caller-side 문제입니다.
