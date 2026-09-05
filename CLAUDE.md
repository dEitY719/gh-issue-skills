# gh-issue-skills — Contributor Guidelines

This file is the AI context document for this repo. `AGENTS.md` is a symlink to
it, so Claude Code, Codex, Gemini CLI, and every other harness read the same
text. Edit `CLAUDE.md`; never replace the symlink with a second copy.

## What this repo is

A single-plugin skill marketplace. The plugin is named `gh-issue` and it owns
the **issue and discussion lifecycle** — everything that happens to a card
before a branch exists, and the one skill that turns a card into edits:

| Skill | Artifact it produces | Role |
|-------|----------------------|------|
| `read` | terminal output | Fetches one issue and prints it verbatim. Mutates nothing. |
| `create` | a GitHub Issue | Classifies the current chat by conventional-commit prefix and files it, with auto-labels and a dependency scan. |
| `implement` | file edits | Claims the issue, moves its board card, captures a pre-edit test baseline, edits and tests. No commit, no PR. |
| `proceed` | whatever the protocol says | Executes the 8-section protocol a *directive* issue embeds, unattended, with a safety gate per step. |
| `discussion-create` | a GitHub Discussion | Saves a pre-decision chat as an RFC-shaped Discussion. Refuses a decided to-do. |
| `discussion-convert` | an Issue + a locked Discussion | Promotes a decided `Ideas` Discussion into a backlinked Issue, then locks and closes it. |

Four of the six write to a live GitHub repo. That is why every safety contract
below is a hard rule rather than a preference.

The skills were extracted from `dEitY719/dotfiles`
(`claude/skills/{gh-issue-read,gh-issue-create,gh-issue-implement,gh-issue-proceed,gh-discussion-create,gh-discussion-convert}`)
as a content snapshot at source commit
`42c0d83fd263bca99b3d085ba06b2b5906c480eb` — no history rewriting. That source
tree no longer exists: Phase 4 of that repo's migration plan removed the
dotfiles copies as planned (dEitY719/dotfiles#1410 NF-1 / NF-3). This is
Phase 3 of dEitY719/dotfiles#1410, alongside the two sibling repos
`gh-pr-skills` and `gh-flow-skills`; `packaging-skills` was Phase 0 and
`harness-skills` was Phase 1 and owns the shared assets.

## Layout: root manifests, one flat `skills/`

This repo deliberately does **not** use the nested `plugins/<name>/skills/`
"mono" layout. Every harness manifest sits at the repo root and points at a
single flat `./skills/` directory:

```
.claude-plugin/{marketplace,plugin}.json   Claude Code
.codex-plugin/plugin.json                  Codex
.kimi-plugin/plugin.json                   Kimi CLI
.hermes-plugin/{plugin.yaml,__init__.py}   Hermes Agent
.opencode/plugins/gh-issue.js              OpenCode
.agents/plugins/marketplace.json           Antigravity
gemini-extension.json + GEMINI.md          Gemini CLI
skills/<name>/SKILL.md                     the skills themselves
```

Only Claude Code understands the nested mono layout. The other five harnesses
resolve manifests at the repo root and a skills tree at `./skills/`, so nesting
would silently cut this plugin down to Claude-Code-only. **Do not move the
manifests under a `plugins/` directory.**

## Shared assets live elsewhere — link, never copy

This repo owns none. Both belong to `dEitY719/harness-skills`:

**1. Per-harness tool mappings** (`references/*-tools.md` there, dEitY719/dotfiles#1410
F-5). Do not create a `references/` directory at this repo's root. If a doc here
needs a mapping, link to
`https://github.com/dEitY719/harness-skills/blob/main/references/<harness>-tools.md`.
One tool rename must stay one edit, not fifteen (NF-2). The single sanctioned
mirror is the condensed summary inside `.kimi-plugin/plugin.json`'s
`skillInstructions`, because Kimi CLI cannot read a reference file at load time;
keep it short and keep it pointing upstream.

**2. The reusable CI workflow** (`.github/workflows/skill-check.yml` there,
D-10). This repo's `validate.yml` calls it with `plugin-name: gh-issue` and a
short `allow-emoji-paths` list. Do not fork it into a standalone workflow — a
check added upstream should apply here on the next run, which is the whole
point.

## Rules for changing skills

- **Skill directory name is the identity.** `skills/<name>/` must match the
  `name:` field in that skill's `SKILL.md` frontmatter, and that field is the
  **bare** name (`implement`), never namespaced (`gh-issue:implement`). CI fails
  on a `:` in the name. The harness supplies the `gh-issue:` prefix at
  invocation time.
- **The old `gh-issue-` / `gh-` prefixes are gone and stay gone.** They
  stuttered against the namespace (`/gh-issue:gh-issue-implement`), so the
  migration dropped them (dEitY719/dotfiles#1410 F-4). Do not reintroduce them, and do not
  shorten the remaining names further — `discussion-create`, not `discuss`.
- **Invocation form in prose is namespaced.** Body text referring to a skill as
  a command writes `/gh-issue:create`. The old colon form (`gh:issue-create`)
  and the dash-form aliases (`/gh-issue-create`) were both dropped in the
  migration — do not reintroduce either.
- **Cross-repo references use the *new* namespace, not the old one.** Unlike the
  Phase 2 repos, this one was migrated after the Phase 3 names were fixed, so
  `gh-pr:commit`, `gh-pr:create`, `gh-pr:merge`, `gh-flow:issue`,
  `gh-flow:autopilot`, and `spec-flow:trd-to-issues` are written here in their
  final form even where the sibling repo does not exist yet (dEitY719/dotfiles#1676 §2). Do not
  "correct" them back to `gh:commit` / `devx:autopilot`.
- **Marker strings are a wire format, not an invocation form.** The
  `[step:gh-issue-implement/<id>] OK` lines `implement` prints, and the
  `[step:gh-issue-proceed/<id>] OK` lines `proceed` prints, are matched verbatim
  by `dEitY719/dotfiles/claude/hooks/skill_completion_guard.py` against its
  `skill_step_catalog.yml` keys. They were **not** renamed in the migration and
  must not be — `gh-issue` + `implement` happens to spell the old key exactly,
  and `proceed` is guarded the same way (dEitY719/dotfiles#1676 NF-4). The same goes for the
  `<!-- ai-metrics -->` footer markers: an interop format shared with the skills
  in `gh-pr-skills` that write cards, not something to renamespace.
- **Progressive disclosure.** `SKILL.md` stays under 100 lines (CI enforces it)
  and names which `references/` file to read and when. Detail lives in
  `references/`. `implement` is exactly at the limit — anything added there has
  to come out of somewhere else.
- **Description budget.** CI sums every skill description and fails past 5,440
  characters — Codex's context budget. The current total is 1,373. Keep new
  descriptions tight anyway.

## Safety contracts

These are acceptance criteria carried over from dotfiles, not advice:

- **Every `gh` call carries `GH_HOST` and `--repo`, both resolved from the same
  remote URL.** A bare `gh issue view <N>` follows gh CLI's own
  `gh repo set-default`, not git's `origin`. On a dual-host login (github.com
  plus GHES) that succeeds silently against the wrong server: an OPEN issue comes
  back "not found", and a write lands on a stranger's issue #N (dEitY719/dotfiles#1403).
  Never work around a surprising `gh` result by dropping `--repo` or switching
  remotes — verify the host first.
- **`read` mutates nothing and prints verbatim.** No summarising the body away,
  no reformatting comments. The verbatim record is the product.
- **`create` never invents requirements the chat did not decide.** When the
  conversation has not converged it stops and asks. A pre-decision RFC is routed
  to `discussion-create`, not filed as an issue with a plausible-looking spec.
- **`implement` never commits, never opens a PR, never creates a worktree, and
  never runs on the default branch.** It also never fixes a test that was already
  failing before it edited anything: a baseline run taken *before* the first edit
  defines PRE-EXISTING vs CAUSED, and that split outranks even the TDD skill's
  blanket "other tests fail? fix now". The fallback path retries at most 3 times;
  the TDD path has no counter and stops on judgment instead.
- **`proceed` validates the protocol schema strictly** and refuses to guess a
  missing section. Every write step passes its safety gate first; the gate is
  fail-closed.
- **A block label is a hard refusal, with no escape hatch.** `do-not-work`,
  `on-hold`, and the rest of `GH_ISSUE_BLOCK_LABELS` abort `implement` and
  `proceed` with exit 2 (reserved across this family for "policy refusal", as
  distinct from 1 = "the skill broke"). Removing the label is the only release —
  a force flag was proposed and rejected.
- **`discussion-convert` is idempotent.** An already-converted Discussion is
  recognised and not duplicated, and the Issue it creates carries a back-link.

## Harness portability

These six are `gh` CLI calls and file writes, so they port cleanly with one
exception: `implement` calls `superpowers:test-driven-development` through
Claude Code's `Skill()` tool on its TDD path. That path is gated on the plugin
resolving *and* a test runner being detected; when either is missing the skill
takes its built-in fallback path, which is a complete flow (baseline, edits,
tests, bounded failure loop, full report) rather than a degraded one. Nothing
here requires superpowers.

The other harness-shaped gap is confirmation prompts: `create`'s clarification
guard and `discussion-create`'s category selection need a real answer. Harnesses
without a structured question tool must ask in the conversation and wait. If you
add a step that depends on a Claude-Code-only capability, say so in
`README.md`'s harness-support matrix and open an issue against `harness-skills`
so its `references/*-tools.md` gain the fallback.

## Version bumps

The version appears in seven manifests: `.claude-plugin/marketplace.json`,
`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`,
`.kimi-plugin/plugin.json`, `.hermes-plugin/plugin.yaml`,
`gemini-extension.json`, and `package.json`. CI checks that they agree — bump
all of them together. Versioning is independent per repo (dEitY719/dotfiles#1410 D-9); this repo
does not release in lockstep with its siblings.
