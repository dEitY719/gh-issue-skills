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

SKILL.md 의 Step 2 블록을 문서에서 그대로 추출해 실행했고 exit 0, JSON 10,324 bytes
(키 11개) 로 성공했습니다. `state` 가 `CLOSED` 라 Header 의 종료 사유는 추가 REST
읽기에서 가져왔습니다 — `gh api repos/dEitY719/dotfiles/issues/1676 --jq .state_reason`
→ `completed`.

- `number=1676`, `state=CLOSED`, `state_reason=completed`
- title: `feat(skills): #1410 Phase 3 — gh-issue-skills repo 생성`
- author `dEitY719` / labels `[feat]` / assignees `[dEitY719]`
- 본문: 8,113 chars / 135 lines (verbatim 보존)
- 코멘트 2건: 2026-09-01T10:41:02Z (333 chars), 2026-09-01T10:45:27Z (511 chars)
- Checklist 추출: 본문 9개 + 코멘트 0개 = 합계 9개
- 마지막 줄: `[ai-metrics:gh-issue-read] ~0 min (read-only — not written to GitHub)`
- 대조 실행: `#1665` → `not_planned`, OPEN 인 `#1678` → 추가 읽기 생략
