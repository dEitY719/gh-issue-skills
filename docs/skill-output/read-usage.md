# read 사용 결과

> **한 줄 요약** — 이슈 번호와 remote 를 받아 구조화된 verbatim 요약을 터미널에 출력합니다.

```
이슈 번호 + remote  ──▶  /gh-issue:read  ──▶  구조화 요약 (터미널 출력)
```

읽기 전용 스킬 — GitHub 쓰기 0건.

## 1. 실행한 명령

```
/gh-issue:read <issue-number> [remote]
/gh-issue:read 1676
```

## 2. 입력

- 이슈 번호: `1676`
- cwd: `/home/bwyoon/dotfiles`, origin: `dEitY719/dotfiles`
- Step 1 해석 결과: `TARGET_REPO=dEitY719/dotfiles`, `TARGET_HOST=github.com`

## 3. 결과

Step 2 의 `gh issue view` 1차 시도는 SKILL.md 의 필드 목록을 그대로 써서 exit 1 로
실패했습니다 (`Unknown JSON field: "stateReason"` — gh 2.45.0 미지원). `stateReason` 을
`closed,closedAt` 으로 바꾼 2차 시도가 exit 0, JSON 13,937 bytes 로 성공했습니다.

- `number=1676`, `state=CLOSED`, `closed=true`, `closedAt=2026-09-01T11:09:44Z`
- title: `feat(skills): #1410 Phase 3 — gh-issue-skills repo 생성`
- author `dEitY719` / labels `[feat]` / assignees `[dEitY719]`
- 본문: 8,113 chars / 135 lines (verbatim 보존)
- 코멘트 2건: 2026-09-01T10:41:02Z (333 chars), 2026-09-01T10:45:27Z (511 chars)
- Checklist 추출: 본문 9개 + 코멘트 0개 = 합계 9개
- 마지막 줄: `[ai-metrics:gh-issue-read] ~0 min (read-only — not written to GitHub)`
