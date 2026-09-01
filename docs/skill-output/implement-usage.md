# implement 사용 결과

> **한 줄 요약** — 이슈 번호를 받아 파일 수정과 테스트 실행을 수행합니다 (커밋/PR 없음).

```
이슈 번호 + mode + remote  ──▶  /gh-issue:implement  ──▶  파일 수정 + 테스트 결과 리포트
```

GitHub 쓰기 0건 — `--help` 와 Step 1/Step 2 의 비변경 경로만 실행했습니다
(Step 3 claim 이하 미진입).

## 1. 실행한 명령

```
/gh-issue:implement <issue-number> [mode] [remote] [--no-next-hint]
/gh-issue:implement --help
```

## 2. 입력

- 인자: `--help` (arg #1)
- cwd: `/home/bwyoon/para/project/skills/gh-issue-skills-feat-1`
- 현재 브랜치 `wt/feat/1`, 기본 브랜치 `main`, origin `dEitY719/gh-issue-skills`

## 3. 결과

help 출력 실측: **65 lines / 3,805 chars**. 섹션 6개 — Arguments, Usage,
Precondition (by convention), What the skill does, superpowers plugin not installed
-> fallback, What the skill will NOT do.

Step 1 전제조건 3종을 실제로 실행해 **3/3 통과** (fail-fast 미발동):
`git rev-parse --show-toplevel` -> `/home/bwyoon/para/project/skills/gh-issue-skills-feat-1` OK,
current `wt/feat/1` vs default `main` -> 불일치 OK,
`git status --porcelain` -> 0 lines (clean) OK.

Step 2 탐지: superpowers 6.3.0 의 `test-driven-development` 와
`subagent-driven-development` 모두 resolve. 테스트 러너는 미검출
(`package.json` 은 있으나 `scripts` 키 없음, `pytest.ini`/`pyproject.toml`/`Makefile`/
`Cargo.toml`/`go.mod` 없음) — 따라서 Step 5 는 TDD 경로가 아니라 **fallback 경로**로,
러너가 없어 테스트는 skip 됩니다.
