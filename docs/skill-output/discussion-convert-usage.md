# discussion-convert 사용 결과

> **한 줄 요약** — Discussion 번호를 받아 fetch 결과(또는 Issue + 잠긴 Discussion)를 생성합니다.

```
Discussion 번호  ──▶  /gh-issue:discussion-convert  ──▶  fetch 오류 판정 (터미널 출력)
```

GitHub 쓰기 0건 — 비변경 경로만 실행했습니다.

## 1. 실행한 명령

```
/gh-issue:discussion-convert <discussion-number> [remote]
```

이번 실행: `/gh-issue:discussion-convert --help` (Step 2 fetch 는 origin 에 실제 실행)

## 2. 입력

- help 경로: 인자 `--help` 하나. API 호출 없음.
- fetch 경로: Discussion #1, remote `origin` = `dEitY719/gh-issue-skills`.
  이 repo 는 Discussions 기능이 비활성 상태입니다.

## 3. 결과

help 출력 실측: 94 lines / 4,681 chars, 7개 섹션 (Arguments, Flags, Env Vars, What the
skill does, Bidirectional-backlink contract, What the skill will NOT do, Related skills).

Step 2 fetch 실측: `GH_HOST=github.com gh api graphql` 로 `discussion(number:1)` 을 조회한
응답이 `hasDiscussionsEnabled:false`, `discussion:null`, `errors[0].type = NOT_FOUND` 였고,
gh stderr 는 다음과 같습니다.

```
gh: Could not resolve to a Discussion with the number of 1.
```

SKILL.md Step 2 의 "Fetch failure -> abort with stderr" 경로를 그대로 타서 중단했으며,
Step 3(카테고리 가드) 이하로는 진입하지 않았습니다.
