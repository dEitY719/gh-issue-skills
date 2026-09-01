# gh-issue-skills

Six skills for the GitHub **issue and discussion lifecycle** — everything that
happens to a card before a branch exists, plus the one skill that turns a card
into file edits. Read an issue verbatim, file the current chat as a classified
issue, implement it, execute the protocol a directive issue embeds, and author
or promote an RFC-shaped Discussion. Packaged as a single plugin named
`gh-issue`, installable on six coding-agent harnesses.

Its siblings own the rest of the pipeline:
[`gh-pr-skills`](https://github.com/dEitY719/gh-pr-skills) (commit -> PR ->
review -> merge) and [`gh-flow-skills`](https://github.com/dEitY719/gh-flow-skills)
(one-shot compositions). Like
[`gh-setup-skills`](https://github.com/dEitY719/gh-setup-skills), this repo owns
no shared assets — it links out for the
[per-harness tool mappings and the CI workflow](#shared-assets).

## Skills

| Skill | Invoke | What it does |
|-------|--------|--------------|
| `read` | `/gh-issue:read <N> [remote]` | Fetches one issue and prints a structured, **verbatim** summary — body and comments unaltered. Read-only; it mutates nothing. |
| `create` | `/gh-issue:create [options]` | Saves the current conversation as an Issue, classified by conventional-commit prefix, with auto-labels, a dependency scan, and an ai-metrics footer. Stops and asks rather than inventing requirements the chat never decided. |
| `implement` | `/gh-issue:implement <N> [mode] [remote]` | Claims the issue, moves its board card to `In progress`, captures a pre-edit test baseline, then edits and tests. **Never commits and never opens a PR.** |
| `proceed` | `/gh-issue:proceed <N> [remote]` | Executes the 8-section protocol a *directive* issue embeds, unattended — strict schema validation, a safety gate per write step. Not a code implementer. |
| `discussion-create` | `/gh-issue:discussion-create [category]` | Saves a pre-decision chat as an RFC-shaped Discussion (default `Ideas`). Refuses a decided to-do and routes it to `create`. |
| `discussion-convert` | `/gh-issue:discussion-convert <N>` | Promotes a decided `Ideas` Discussion into a backlinked Issue, then locks and closes it. Idempotent. |

`create` and `discussion-create` are a pair split by *decidedness*: a converged
to-do becomes an Issue, an open question becomes a Discussion.
`discussion-convert` is the bridge back once the question is settled.

`read` is the only skill here that mutates nothing, which is why it is also the
one safe to point at someone else's repo.

### Visual guides and worked examples (GitHub Pages)

- `read` — [visual guide](https://deity719.github.io/gh-issue-skills/skill-guides/read.html) · [usage example](https://deity719.github.io/gh-issue-skills/skill-output/read-usage.html) (issue number to verbatim terminal summary)
- `create` — [visual guide](https://deity719.github.io/gh-issue-skills/skill-guides/create.html) · [usage example](https://deity719.github.io/gh-issue-skills/skill-output/create-usage.html) (conversation to GitHub Issue)
- `implement` — [visual guide](https://deity719.github.io/gh-issue-skills/skill-guides/implement.html) · [usage example](https://deity719.github.io/gh-issue-skills/skill-output/implement-usage.html) (issue to file edits and test run)
- `proceed` — [visual guide](https://deity719.github.io/gh-issue-skills/skill-guides/proceed.html) · [usage example](https://deity719.github.io/gh-issue-skills/skill-output/proceed-usage.html) (directive issue to executed protocol)
- `discussion-create` — [visual guide](https://deity719.github.io/gh-issue-skills/skill-guides/discussion-create.html) · [usage example](https://deity719.github.io/gh-issue-skills/skill-output/discussion-create-usage.html) (conversation to RFC Discussion)
- `discussion-convert` — [visual guide](https://deity719.github.io/gh-issue-skills/skill-guides/discussion-convert.html) · [usage example](https://deity719.github.io/gh-issue-skills/skill-output/discussion-convert-usage.html) (Ideas Discussion to backlinked Issue)

Each page is generated from a Markdown source under
[`docs/skill-guides/`](docs/skill-guides) and [`docs/skill-output/`](docs/skill-output).

## Requirements

| Skill | Needs |
|-------|-------|
| `read` | An authenticated `gh` CLI with read access. Host and repo both resolve from one remote URL and are passed explicitly on every call. |
| `create` | `gh` with write access to issues. Discussion routing additionally needs the discussion scopes. |
| `implement` | `gh` with write access, plus a **clean working tree on a feature branch** — it refuses to run on the default branch and never creates a worktree for you. A test runner is detected if present; without one the test steps are skipped, not faked. |
| `proceed` | `gh` with write access, same branch preconditions as `implement`, plus whatever the individual protocol's steps require. |
| `discussion-create`, `discussion-convert` | `gh` with the GraphQL discussion scopes. `discussion-convert` also needs permission to lock and close. |

Every skill carries `GH_HOST` **and** `--repo` on every `gh` call, both resolved
from the same remote URL. `--repo` alone names no server: on a dual-host login
(github.com plus a GHES instance) a bare call silently queries the wrong one and
reports an OPEN issue as "not found" (dotfiles #1403).

## Install

### Claude Code

```
/plugin marketplace add dEitY719/gh-issue-skills
/plugin install gh-issue@gh-issue-skills
```

### Codex

```
codex plugin install dEitY719/gh-issue-skills
```

### Kimi CLI

```
kimi plugin install dEitY719/gh-issue-skills
```

### Hermes Agent

```
hermes plugins install dEitY719/gh-issue-skills
```

### OpenCode

See [`.opencode/INSTALL.md`](.opencode/INSTALL.md).

### Gemini CLI / Antigravity

```
gemini extensions install https://github.com/dEitY719/gh-issue-skills
```

Antigravity (`agy`) shares `~/.gemini`, so it inherits the install.

## Harness support

These are `gh` CLI calls and file writes, so they port cleanly with one
exception — `implement`'s TDD path calls `superpowers:test-driven-development`
through Claude Code's `Skill()` tool. Every gap and its workaround is documented
per harness in
[`harness-skills/references/`](https://github.com/dEitY719/harness-skills/tree/main/references);
read the one file for the harness you are on.

| Skill | Claude Code | Codex | Kimi | Gemini / Antigravity | Hermes | OpenCode |
|-------|:-----------:|:-----:|:----:|:--------------------:|:------:|:--------:|
| `read` | full | full | full | full | full | full |
| `create` | full | full, confirm in chat | full | full on Gemini, confirm in chat on Antigravity | full, confirm in chat | full, confirm in chat |
| `implement` | full | fallback path | fallback path | fallback path | fallback path | fallback path |
| `proceed` | full | full | full | full | full | full |
| `discussion-create` | full | full, confirm in chat | full | full on Gemini, confirm in chat on Antigravity | full, confirm in chat | full, confirm in chat |
| `discussion-convert` | full | full | full | full | full | full |

*fallback path* — `implement` picks between two complete routes. The TDD path
needs `superpowers:test-driven-development` to resolve **and** a test runner to be
detected; otherwise it runs the built-in path (pre-edit baseline, edits, test run,
bounded 3-attempt failure loop, full report), as harnesses without a `Skill()`
equivalent always do. Same finish line — the skill never requires the plugin.

*confirm in chat* — two steps need a real answer: `create`'s clarification guard
(conversation has not converged) and `discussion-create`'s category selection.
Kimi (`AskUserQuestion`) and Gemini CLI (`ask_user`) have a structured question
tool; Codex, Hermes, Antigravity, and OpenCode do not, so ask and wait for a real
reply. An auto-approve session setting is not the user's answer.

## Shared assets

This repo owns none — deliberately.

- **Per-harness tool mappings** live in
  [`harness-skills/references/`](https://github.com/dEitY719/harness-skills/tree/main/references)
  (`{codex,kimi,gemini,antigravity,hermes,opencode}-tools.md`). That repo is
  their sole owner; the other fourteen `*-skills` repos link there rather than
  carrying copies, so one tool rename is one edit, not fifteen
  (dotfiles #1410 F-5 / NF-2). The only condensed mirror here is
  `.kimi-plugin/plugin.json`'s `skillInstructions`, because Kimi CLI cannot read
  a reference file at load time — it points back to the canonical file.
- **The reusable CI workflow** is
  [`harness-skills/.github/workflows/skill-check.yml`](https://github.com/dEitY719/harness-skills/blob/main/.github/workflows/skill-check.yml)
  (#1410 D-10). See [CI](#ci).

## Layout

Manifests live at the repo root and all point at one flat `skills/` directory:

```
.
├── skills/{read,create,implement,proceed,discussion-create,discussion-convert}/
│   ├── SKILL.md
│   └── references/
├── .claude-plugin/{marketplace,plugin}.json     Claude Code
├── .codex-plugin/plugin.json                    Codex
├── .kimi-plugin/plugin.json                     Kimi CLI
├── .hermes-plugin/{plugin.yaml,__init__.py}     Hermes Agent
├── .opencode/plugins/gh-issue.js + INSTALL.md   OpenCode
├── .agents/plugins/marketplace.json             Antigravity
├── gemini-extension.json + GEMINI.md            Gemini CLI
├── package.json
├── CLAUDE.md · AGENTS.md -> CLAUDE.md
└── LICENSE
```

Only Claude Code understands a nested `plugins/<name>/skills/` layout; the other
five resolve manifests at the repo root and a skills tree at `./skills/`, so this
repo keeps everything flat. Skill directory names dropped their old `gh-issue-` /
`gh-` prefixes in the migration — `/gh-issue:gh-issue-implement` stutters and the
namespace already carries that meaning (#1410 F-4). `.kimi-plugin/` is
pre-provisioned for a CLI not yet installed. Rationale: [`CLAUDE.md`](CLAUDE.md).

## Cross-repo names

Unlike the Phase 2 repos, this one was migrated **after** the Phase 3 names were
fixed, so references to sibling repos are written in their final form even where
the sibling does not exist yet (#1676 §2):

| Old | New | Lives in |
|-----|-----|----------|
| `gh:issue-read` / `-create` / `-implement` / `-proceed` | `gh-issue:read` / `:create` / `:implement` / `:proceed` | this repo |
| `gh:discussion-create` / `-convert` | `gh-issue:discussion-create` / `:discussion-convert` | this repo |
| `gh:commit` | `gh-pr:commit` | `gh-pr-skills` |
| `gh:pr` | `gh-pr:create` | `gh-pr-skills` |
| `gh:pr-merge` | `gh-pr:merge` | `gh-pr-skills` |
| `gh:issue-flow` | `gh-flow:issue` | `gh-flow-skills` |
| `devx:autopilot` | `gh-flow:autopilot` | `gh-flow-skills` |
| `devx:trd-to-issues` | `spec-flow:trd-to-issues` | `spec-flow-skills` |

One thing deliberately did **not** move: the `[step:gh-issue-implement/<id>] OK`
and `[step:gh-issue-proceed/<id>] OK` marker lines — a wire format matched
verbatim by dotfiles' `claude/hooks/skill_completion_guard.py` against its
`skill_step_catalog.yml` keys. Renaming them would break the guard (#1676 NF-4).

## CI

[`.github/workflows/validate.yml`](.github/workflows/validate.yml) calls the
reusable workflow owned by `harness-skills`:

```yaml
jobs:
  validate:
    uses: dEitY719/harness-skills/.github/workflows/skill-check.yml@main
    with:
      plugin-name: gh-issue
      allow-emoji-paths: |
        skills/create/references/
        ...
```

It validates manifests, skill frontmatter (the `name:` must be bare and match
the directory), progressive-disclosure line limits, the Codex description budget,
version agreement across all seven manifests, shell scripts, and the no-emoji
rule. There is no local copy to keep in sync; a check added upstream applies here
on the next run.

The `allow-emoji-paths` entries cover text the skills **quote** rather than
decorate with: the ai-metrics footer, whose glyphs are the wire format itself
(dotfiles #317 F-2, PR #320), and the `Postpone` block label that `implement` and
`proceed` refuse to start on. Nothing else in the repo may carry an emoji.

## Provenance

Extracted from [`dEitY719/dotfiles`](https://github.com/dEitY719/dotfiles)
(`claude/skills/{gh-issue-read,gh-issue-create,gh-issue-implement,gh-issue-proceed,gh-discussion-create,gh-discussion-convert}`)
as a content snapshot — no history rewriting, behaviour unchanged. Only the
namespace moved, from `gh:` to `gh-issue:`, and the directory names lost their
now-redundant prefixes; the dotfiles copies go in Phase 4 (#1410 NF-1 / NF-3).
This is Phase 3, shared with `gh-pr-skills` and `gh-flow-skills`;
`packaging-skills` was Phase 0 and `harness-skills` (Phase 1) owns the shared assets.

## License

MIT. See [LICENSE](LICENSE).
