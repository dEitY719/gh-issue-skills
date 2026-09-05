# gh-issue — skill index

Six skills for the GitHub issue and discussion lifecycle. Each lives in this
extension's `skills/` directory. They are explicitly invoked, never ambient:
load the one that matches the request by reading its `SKILL.md`, then follow it.
Do not load all six.

| Skill | Read | Use when |
|-------|------|----------|
| `read` | `@./skills/read/SKILL.md` | Fetching one issue and printing it verbatim. Read-only — it never mutates. |
| `create` | `@./skills/create/SKILL.md` | Saving the current conversation as an issue, classified by conventional-commit prefix. A pre-decision RFC goes to `discussion-create` instead. |
| `implement` | `@./skills/implement/SKILL.md` | Turning an issue into file edits plus a test run. Never commits, never opens a PR. |
| `proceed` | `@./skills/proceed/SKILL.md` | Executing the 8-section protocol a *directive* issue embeds, unattended. Not a code implementer — that is `implement`. |
| `discussion-create` | `@./skills/discussion-create/SKILL.md` | Saving a pre-decision chat as an RFC-shaped Discussion. Refuses a decided to-do. |
| `discussion-convert` | `@./skills/discussion-convert/SKILL.md` | Promoting a decided `Ideas` Discussion into a backlinked Issue, then locking and closing it. |

Each skill's `references/` directory holds the detail it loads on demand.
`SKILL.md` says which file to read and when. Do not read `references/` up front.

## What each skill needs

- **All six** — an authenticated `gh` CLI. Every call carries `GH_HOST` **and**
  `--repo`: `--repo` alone names no server, and on a dual-host login (github.com
  plus a GHES instance) a bare call silently queries the wrong one and reports an
  OPEN issue as "not found" (dEitY719/dotfiles#1403).
- **`read`** — read scope only. It is the one skill here that mutates nothing.
- **`create`, `discussion-create`, `discussion-convert`** — write access to
  issues and discussions. `discussion-*` use the GraphQL API, which needs the
  discussion scopes on the token.
- **`implement`, `proceed`** — write access plus a clean working tree on a
  feature branch. Both refuse to run on the default branch.

## Tool mapping for Gemini CLI

The skills speak in actions. On Gemini CLI these resolve to:

- "Read a file" -> `read_file` / `read_many_files`
- "Create a file" / "edit a file" -> `write_file`, `replace`
- "Run a shell command" -> `run_shell_command` (this is how every `gh` call is made)
- "Search file contents" -> `grep_search`
- "Find files by name" -> `glob`
- "Create a todo" -> `write_todos`
- "Ask the user" -> `ask_user`
- "Dispatch a subagent" -> `invoke_agent` with `agent_name: "generalist"`

The full mapping, including every capability gap and its workaround, lives in
the sibling repo: `https://github.com/dEitY719/harness-skills/blob/main/references/gemini-tools.md`.
This repo owns no copy. Read it when a skill names a tool you do not recognise.
On Antigravity read `antigravity-tools.md` in that same directory instead —
`agy` shares `~/.gemini` but not Gemini CLI's tool names.

## Capability gaps on Gemini CLI

- **`Skill()` has no equivalent.** `implement` calls
  `superpowers:test-driven-development` on its TDD path. Without a
  skill-invocation tool, take its built-in fallback path — baseline capture,
  edits, tests, a bounded 3-attempt failure loop, full report. That path is a
  complete flow, not a degraded one, and the skill is written to never require
  the plugin.
- **Confirmation prompts.** `create` runs a clarification guard and
  `discussion-create` picks a category; both need a real answer. Use `ask_user`.
  On Antigravity `ask_user` does not exist — ask in the conversation and wait for
  a real reply. An auto-approve session setting is not the user's answer.
- `proceed` tracks its 8 protocol sections as todos. Use `write_todos`.

## Safety rules

- **`read` never mutates**, and prints the body and comments verbatim. Do not
  summarise the body away or reformat comments — a verbatim record is the
  product.
- **`create` never invents requirements the chat did not decide.** When the
  conversation has not converged, it stops and asks rather than filling the
  template with plausible text. A pre-decision RFC belongs in
  `discussion-create`.
- **`implement` never commits and never opens a PR.** It also never runs on the
  default branch, never creates a worktree, and never fixes a test that was
  already failing before it edited anything — that split is captured by a
  baseline run taken *before* the first edit.
- **`proceed` validates its protocol schema strictly** and refuses to guess a
  missing section. Every write step passes a safety gate first.
- **`discussion-convert` is idempotent** — an already-converted Discussion is
  recognised, not duplicated.
- **A block label is a hard refusal** in both `implement` and `proceed`
  (`do-not-work`, `on-hold`, and the rest of `GH_ISSUE_BLOCK_LABELS`). There is
  no override flag; removing the label is the only release.
