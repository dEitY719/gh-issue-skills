# gh-issue:issue-create — Step 4 Create Command

Detail companion to SKILL.md Step 4. The procedures are
[`lib/create-issue.sh`](../lib/create-issue.sh) (default) and
[`lib/create-discussion.sh`](../lib/create-discussion.sh) (`DISCUSSION_MODE=1`,
dEitY719/dotfiles#619) — this file is their contract, not code to paste.
확인 질문 없이 즉시 실행.

## Shared prologue

1. Write the drafted body to a `mktemp` file `$BODY` (removed on exit).
2. Append the footer: `bash "$PLUGIN_ROOT/lib/ai-metrics-footer.sh" "$TOKENS"
   "$HUMAN_H" "$ELAPSED" gh-issue-create "$HARNESS" "$LLM_MODEL" >> "$BODY" ||
   echo "[WARN] ai-metrics append failed — continuing." >&2`. The footer's
   bytes are single-sourced in that script, which also honours
   `GH_DISABLE_AI_METRICS=1` itself; the `||` is metrics-helper.md's soft-fail
   rule — never block the create on the footer.

`$TOKENS`, `$HUMAN_H`, `$ELAPSED`, `$HARNESS` and `$LLM_MODEL` come from Step
3.5. `$PLUGIN_ROOT` is the root Step 1's `resolve-target.sh` proved and
exported — never `${CLAUDE_PLUGIN_ROOT:-.}`, whose `$PWD` tier is the repo
under review.

## Issue path (default)

`bash "$PLUGIN_ROOT/lib/create-issue.sh" --title "<title>" --body-file "$BODY"
"${LABEL_ARGS[@]}" "${MILESTONE_ARGS[@]}"` — append `--assignee @me` only when
the user asked for it.

| | `lib/create-issue.sh` |
|---|---|
| Input | `--title T --body-file F` (required); `--label L` / `--assignee A` (repeatable), `--milestone M`; env `GH_HOST`, `TARGET_REPO` (both required), `TARGET_HOST` (must equal `GH_HOST` when set) |
| Runs | `GH_HOST="$GH_HOST" gh issue create --repo "$TARGET_REPO" --title T --body-file F` + the optional flags in the order given |
| Output | gh's stdout: the new issue URL (`NEW_NUM=${URL##*/}` feeds Step 4.5) |
| Exit | gh's own code; **2** on a usage error or when `GH_HOST` / `TARGET_REPO` is empty or the hosts disagree — and then `gh` is never called |

`LABEL_ARGS` / `MILESTONE_ARGS` are the arrays Step 2.5 prepared (one `--label
<name>` per kept label; `--milestone <title>` if resolved). Both are empty when
Step 2.5 was skipped, and the call degrades to its original form. User-supplied
`--label` flags survive Step 2.5 (union with auto labels) unless
`--no-auto-labels` was set, in which case they pass straight through
`LABEL_ARGS` from Step 1.

`GH_HOST` 와 `--repo` 는 둘 다 필수이며 Step 1 이 같은 remote URL 에서 뽑은
쌍이다 (`references/repo-resolution.md`). 하나라도 빠지면 gh CLI 가 자기
`gh repo set-default` 를 따라가 dual-host 로그인에서 다른 서버에 이슈를
만들어 버린다 — 사람이 지워야 되돌아온다 (dEitY719/dotfiles#1403). 그래서
스크립트는 둘 중 하나라도 비면 `gh` 를 부르기 전에 exit 2 로 멈춘다
(`lib/create-issue.selfcheck.sh` §3).

## Discussion path (`DISCUSSION_MODE=1`)

Triggered by `--as-discussion <category>` from Step 1.1; `$CATEGORY` was
validated there against `Ideas` / `Q&A` / `Announcements` / `Lessons`, and
Step 2.5 was skipped, so the label arrays are empty and unused.

`URL=$(bash "$PLUGIN_ROOT/lib/create-discussion.sh" "${TARGET_REPO%%/*}"
"${TARGET_REPO##*/}" "$CATEGORY" "$TITLE" "$BODY")`, then print
`[OK] Discussion (<category>): <url>`.

Its contract (input, URL output, exit 1 = lookup/mutation failure or missing
helper, exit 2 = usage, empty `GH_HOST`, or `GH_HOST` != a set `TARGET_HOST`) is
[[gh-issue:discussion-create]]'s `references/create-cmd.md`. This skill ships a
byte-identical copy of the same script, which is what keeps the two
skills' three GraphQL calls in lock-step. The exported `GH_HOST` is their only
host selector, so the Discussion lands on the same host the Issue path would
have (dEitY719/dotfiles#1403).

The footer's emoji glyphs live in `lib/ai-metrics-footer.sh` alone; this file
quotes none of them. `CLAUDE.md`'s ai-metrics exception covers that script and
nothing else in this skill.
