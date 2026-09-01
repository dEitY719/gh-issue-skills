# create 사용 결과

> **한 줄 요약** — 현재 대화를 받아 conventional-commit prefix 로 분류된 GitHub Issue 1건을 생성합니다.

```
현재 대화 + remote  ──▶  /gh-issue:create  ──▶  GitHub Issue 1건 (#N + URL)
```

GitHub 쓰기 0건 — 이번에는 비변경 경로(`--help`)만 실행했습니다.

## 1. 실행한 명령

```
/gh-issue:create [remote] [flags]
/gh-issue:create --help
```

## 2. 입력

- 인자: `--help` (arg #1)
- cwd: `/home/bwyoon/para/project/skills/gh-issue-skills-feat-1`
- SKILL.md 의 `## Help` 규약에 따라 `references/help.md` 를 verbatim 출력하고 정지.
  API 호출 없음.

## 3. 결과

help 출력 실측: **144 lines / 8,506 chars**.

포함된 섹션 8개: Arguments, Flags, Usage, What the skill does, Title format,
Detail preservation, What the skill will NOT do, Error cases.

이슈 생성 경로(Step 2~5)는 진입하지 않았으므로 GitHub 쓰기는 0건입니다.
