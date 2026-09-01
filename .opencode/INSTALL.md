# Installing gh-issue for OpenCode

## Prerequisites

- [OpenCode.ai](https://opencode.ai) installed
- An authenticated `gh` CLI with access to the repo you are working in
- Write access to issues and discussions for everything except `read`
- `implement` and `proceed` additionally need a clean working tree on a feature
  branch — both refuse to run on the default branch

## Installation

Add the plugin to the `plugin` array in your `opencode.json` (global or
project-level):

```json
{
  "plugin": ["gh-issue-skills@git+https://github.com/dEitY719/gh-issue-skills.git"]
}
```

OpenCode installs the package and runs `.opencode/plugins/gh-issue.js`, which
appends this repo's `skills/` directory to `config.skills.paths`. No symlinks
and no further config edits are needed — the native `skill` tool discovers all
six on the next session.

## Verify

```
skill gh-issue:read
```

should load `skills/read/SKILL.md`. If it does not, check that the plugin entry
resolved (OpenCode logs the plugin load) and that `skills/read/SKILL.md` exists
in the installed copy.

## Notes

- The plugin injects **no** per-session bootstrap context. These skills are
  invoked explicitly against a named issue or discussion; four of the six mutate
  a live GitHub repo, so keeping them out of the preamble is deliberate.
- `implement`'s TDD path calls `superpowers:test-driven-development` through
  Claude Code's `Skill()` tool, which OpenCode has no equivalent for. The skill
  detects this and takes its built-in fallback path instead — a complete flow,
  not a degraded one.
- `create`'s clarification guard and `discussion-create`'s category selection
  need a real answer from you. Ask in the conversation and wait for a reply; an
  auto-approve setting is not an answer.
- Per-harness tool mappings live in the sibling repo
  [`harness-skills/references/`](https://github.com/dEitY719/harness-skills/tree/main/references)
  (`opencode-tools.md`). This repo keeps no copy.
