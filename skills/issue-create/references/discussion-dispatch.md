# gh-issue:issue-create — Create dispatch (Step 4)

Both paths share one prologue (`mktemp` body file + ai-metrics footer call;
the helper honours `GH_DISABLE_AI_METRICS=1` itself, issue dEitY719/dotfiles#399)
and then execute one helper — contracts in `references/create-cmd.md`:

- **Issue path** (default, `DISCUSSION_MODE` unset) —
  `lib/create-issue.sh` with `LABEL_ARGS` / `MILESTONE_ARGS` from Step 2.5.
- **Discussion path** (`DISCUSSION_MODE=1`) — `lib/create-discussion.sh`,
  which loads `gh_discussion.sh` from `$SHELL_COMMON/functions/`, then
  `$DOTFILES_ROOT/shell-common/functions/`, then this skill's own
  `lib/vendor/` copy (no `$PWD` tier,
  dEitY719/harness-skills#22) and runs the three lookups
  (`_gh_discussion_repo_id`, `_gh_discussion_category_id`,
  `_gh_discussion_create`). Print the Discussion URL instead of an
  issue URL. A non-zero exit is `[FAIL]` quoting its stderr line.

확인 질문 없이 즉시 실행.
