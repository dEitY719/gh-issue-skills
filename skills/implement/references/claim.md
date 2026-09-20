# gh-issue:implement — Step 3 Fetch + Claim

This file is the SSOT for Step 3 **policy** of `gh-issue:implement`; the
algorithm itself is [`lib/claim-issue.sh`](../../../lib/claim-issue.sh), which
this skill and `gh-issue:proceed` both run (dEitY719/gh-issue-skills#21). The
skill absorbs four session-start tasks that AgentToolbox handles in
`claude-enter-issue` (worktree creation stays the user's job; everything
else lands here):

1. Block-label guard (fail-closed abort).
2. Self-assign (`@me`).
3. Project board Status transition (`In progress`).
4. `Depends on #M` cross-issue check.

On top of those it adds one dotfiles-native guard AgentToolbox has no
equivalent for — the duplicate-attempt detector of 3.3b (issue dEitY719/dotfiles#1507).

## Substep order — why this sequence

```
3.1  Fetch issue              (gates everything; CLOSED refusal here)
3.2  Block-label guard        (HARD abort; cheapest "no" — never write to
                              an issue we won't work on)
3.3  Self-assign              (broadcast claim ASAP, before mode dispatch)
3.3b Duplicate open-PR guard  (soft warn; runs once the claim is out there
                              but before the board is touched)
3.4  Board Status transition  (idempotent; verify-pair absorbs race)
3.5  Depends-on guard         (slowest — N+1 issue lookups; do last and
                              soft-warn so blockers learned mid-loop
                              don't undo the claim)
```

The HARD aborts (3.1, 3.2) come before any mutation (3.3, 3.4) so an
abort never leaves a stale claim or board state.

**Why 3.3b sits between 3.3 and 3.4**: not earlier than 3.3, because it
costs a search API call and there is no point paying for it on an issue
3.2 is about to refuse; not later than 3.4, so the warning reads against
the board's pre-run state rather than mixed in with this run's own
`In progress` write.

## 3.1 Fetch issue

See `references/fetch-issue.md` — it owns the `gh issue view` call and the
CLOSED refusal, whose wording is this skill's own. The JSON it returns is
`$ISSUE_JSON` below and is reused by 3.2 (`labels`), 3.3 (`assignees`), 3.5
(`body`), and Step 5 (title, body, comments) — call once, parse many times.

## 3.2–3.5 Run the claim

`$N` is the issue number from Step 1; `$TARGET_REPO` / `$TARGET_HOST` /
`$PLUGIN_ROOT` are the exports `lib/resolve-target.sh` made there. No cwd
fallback (dEitY719/harness-skills#24): `$PWD` is caller-controlled — a PR
checkout under review — and a defaulted splice would run THAT CHECKOUT'S OWN
`claim-issue.sh`.

```bash
_CI="" # no cwd fallback (dEitY719/harness-skills#24)
[ -z "${PLUGIN_ROOT:-}" ] || _CI="$PLUGIN_ROOT/lib/claim-issue.sh"
if [ -z "$_CI" ] || [ ! -f "$_CI" ] || [ ! -r "$_CI" ]; then
    printf '[FAIL] claim-issue.sh not found — Step 1 must export PLUGIN_ROOT (export CLAUDE_PLUGIN_ROOT=<plugin dir>).\n' >&2
    exit 1
fi
printf '%s' "$ISSUE_JSON" | "$_CI" "$N" \
    --block-labels-default 'do-not-work,on-hold,보류,⏸️ Postpone,reference' \
    --duplicate-pr-guard
_rc=$?
[ "$_rc" -eq 0 ] || exit "$_rc"
```

Executed, not sourced: unlike `resolve-target.sh` this helper exports
nothing, and running it in its own process is what keeps the board helper's
functions out of the skill's shell and makes the caller's `set -e` irrelevant
to a documented soft-fail step.

**The two flags are this skill's half of the policy** — the whole of what
`gh-issue:proceed` does differently, stated at the call site rather than
hidden behind a caller name inside the script:

- `--block-labels-default` carries the trailing `reference`, which marks
  참고용/구현 불필요 issues (issue dEitY719/dotfiles#1226). `proceed` omits it.
  `GH_ISSUE_BLOCK_LABELS`, when set, replaces the whole list either way.
- `--duplicate-pr-guard` turns on 3.3b. `proceed` opens no PRs, so "an open
  PR already closes this issue" is not a duplicate signal there.

## Substep policy

> **Host targeting (dEitY719/dotfiles#1403)** — every `gh` call the helper makes runs as
> `GH_HOST="$TARGET_HOST" gh ... --repo "$TARGET_REPO"`, using the pair Step 1
> bound from one and the same remote URL (`references/repo-resolution.md`).
> Dropping either half sends the write to the wrong GitHub server without an
> error.

### 3.2 Block-label guard (fail-closed)

**Goal**: refuse to start work on an issue tagged `do-not-work`,
`on-hold`, `보류`, `⏸️ Postpone`, `reference`, or whatever the team's
parking-lot label happens to be. AgentToolbox `#233` policy: no escape hatch
(`GH_ISSUE_FORCE_BLOCKED=1` was rejected) — label removal is the only
way to release. dotfiles inherits that posture. Commas separate the list;
a space is part of a label, so don't pad them.

**Why exit 2 and not 1**: `1` is the implicit failure code for many
shell errors. `2` is reserved across this skills suite for "policy
refusal" (mirrors `_gh_project_status_sync`'s Approved guard return
code). A wrapper script can distinguish "the skill broke" from "the
skill correctly refused". The `exit "$_rc"` above is what propagates it.

### 3.3 Self-assign

**Goal**: broadcast on the issue page, in `gh issue list --repo "$TARGET_REPO"
--assignee @me`, and on issue-list badges that this issue is being worked.

**Why `--add-assignee` not `--assignee`**:
- `--add-assignee` *appends* to the existing list. Safe when a reviewer
  is already assigned.
- `--assignee` *replaces* the list — would silently boot the prior
  assignee. Never use it here.

**Why warn-no-override on conflict**: forking a teammate's claim is
worse than a duplicated implement attempt. The warning gives the human
a chance to coordinate; AgentToolbox `claude-enter-issue` takes the
same posture. Already holding it yourself is an idempotent no-op.

**Soft-fail rule**: no write permission (fork, readonly token), a
transient API error, or a locked issue → single-line `[WARN]` + continue.
The implement flow proceeds — the claim is informational, not load-bearing.

### 3.3b Duplicate open-PR guard (soft)

**Goal**: catch the case 3.3 structurally cannot — *I* am already the
assignee because *another one of my own sessions* claimed this issue
minutes ago from a sibling worktree. To 3.3 that is indistinguishable
from a plain restart, so it says nothing. Issue
dEitY719/dotfiles#1482 was implemented twice, 13 minutes apart, producing PRs dEitY719/dotfiles#1488 and
dEitY719/dotfiles#1489 that later collided in a merge train.

The reliable fingerprint of "someone already did this" is an **open PR
that closes this issue**. Read-only, one search call, one warning line
naming the first PR the search returns — the point is to send the human to
the PR list, not to enumerate it. It never blocks: a second session is
sometimes exactly what the user wants (a rewrite, an abandoned first
attempt), so the decision stays with the human. The search matches both
footer keywords this repo's `gh-pr:commit` accepts — `Closes` and `Fixes` —
since a `Fixes #<N>` PR is just as valid a duplicate signal (codex review,
PR dEitY719/dotfiles#1509).

**Why silence on the empty result matters**: this guard fires on every
implement run, so a line that also prints on the common "no duplicate"
case would train users to scroll past it — costing exactly the signal
dEitY719/dotfiles#1507 exists to add.

**Soft-fail rule** (NF-1): a failure of the search itself (transient API
error, search unavailable or rate-limited, `gh` too old for `--search` on
`pr list`) prints **nothing at all**. Unlike 3.3, a failure here is not even
worth a warn line: the check is an advisory read, and a "could not check for
duplicates" line on an otherwise-fine run is noise of the same kind the
previous paragraph rejects. Never abort — a duplicate warning that blocks
would break every legitimate restart.

### 3.4 Board Status transition

**Goal**: move the issue card from `Backlog`/`Ready` to `In progress`
on every projectV2 it belongs to, via `_gh_project_status_sync` from
`shell-common/functions/gh_project_status.sh`. The helper handles:

- **Explicit `--repo`**: `$TARGET_REPO` from Step 1 (dEitY719/dotfiles#1405). Without it
  the helper resolves via `gh repo view`, i.e. whatever
  `gh repo set-default` picked — which need not be the remote this run
  resolved.
- **No-board repos**: returns 0 silently when the issue belongs to no
  projectV2.
- **`--only-from` whitelist**: `Backlog,Ready` — never bounces an
  already-`In review` / `Done` card backwards. Other custom columns
  (`In design`, `Spec`, etc.) are left untouched; teams that want
  those moved should override the helper or skip with
  `GH_ISSUE_SKIP_BOARD_TRANSITION=1` and run the transition manually.
- **Verify pair (race absorption, dEitY719/dotfiles#393)**: after the mutation the
  helper sleeps `_GH_PROJECT_STATUS_VERIFY_SLEEP` (default 1 s) and
  re-queries. Re-issues the mutation once if a builtin workflow
  reverted the value. Second mismatch → loud stderr, still rc 0.

Locating that helper follows the plugin-root convention
(`harness-skills#10`): tier 1 `$SHELL_COMMON`, tier 2
`$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common`, **no tier 4** — `$PWD` is the
repo under review (dEitY719/harness-skills#22). Sourceable-but-undefined is
a one-line stderr warning and a skipped step, never an abort
(dEitY719/dotfiles#724).

**Warn when `--only-from` absorbs the write (dEitY719/dotfiles#1507, F-2)**: before
handing off, the helper's `_gh_project_status_query_current` reads the card's
current Status, and when it is neither `Backlog` nor `Ready` one line prints
before the (no-op) mutation. This changes nothing about the mutation — the
whitelist still absorbs it, exactly as before. It only stops the absorption
from being *silent*. A card already sitting in `In progress` is the
board-side fingerprint of the same duplicate-session failure 3.3b watches
for on the PR side, and the two signals are independent: the other session
may have moved the board without opening a PR yet, or opened a PR in a repo
with no board at all. A restart of your own abandoned run also lands here,
which is fine — the line is advisory, not a refusal.

The wording is deliberately non-committal about *why* the Status isn't
`Backlog`/`Ready`: the same non-empty complement also includes terminal
columns like `Done` or custom ones like `Spec`, where "another session
already started this" would be the wrong read (codex review, PR dEitY719/dotfiles#1509)
— the message names the fact (current Status) and offers duplicate-start
as one possible explanation, not the only one.

Reading the Status is itself best-effort: a non-zero return skips the
warning and lets `_gh_project_status_sync` run as usual (NF-1) — the same
soft-fail posture 3.3b uses.

**Soft-fail rule**: the helper always returns 0 for non-policy errors —
the implement flow proceeds regardless of board state.

### 3.5 Depends-on guard

**Goal**: warn the user when the issue body mentions `Depends on #M`
and `M` is still OPEN. AgentToolbox `claude-check-deps` is fail-closed
(refuses to start). dotfiles is **soft** because:

- The reference may already be stale (M was closed but the body wasn't
  updated).
- The user may legitimately want to start scaffolding on top of an
  in-flight dependency (stacked work).
- A hard refusal here would frustrate users in repos that don't enforce
  the pattern.

A loud warning is enough — the user can abort with Ctrl-C if relevant.
The pattern is case-insensitive ("Depends on", "depends on", "DEPENDS ON"
all match) and only matches whole `#<digits>` — not `#dep-3` or `#1.2.3`.

**Failure mode**: if the `gh issue view <M>` lookup itself errors (deleted
issue, cross-repo reference, network), one warn line and continue. Do
not abort — the dependency check is informational.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `GH_ISSUE_BLOCK_LABELS` | `do-not-work,on-hold,보류,⏸️ Postpone,reference` | Comma-separated block-label list for 3.2; replaces `--block-labels-default` entirely when set. Spaces inside a label are part of the label (don't pad commas). `reference` marks 참고용/구현 불필요 issues (issue dEitY719/dotfiles#1226). |
| `GH_ISSUE_SKIP_SELF_ASSIGN` | unset | When `1`, skip 3.3 entirely. |
| `GH_ISSUE_SKIP_DUPLICATE_CHECK` | unset | When `1`, skip 3.3b entirely — no search call, no warning. For a deliberate second implementation of the same issue (issue dEitY719/dotfiles#1507). |
| `GH_ISSUE_SKIP_BOARD_TRANSITION` | unset | When `1`, skip 3.4 entirely (its F-2 Status warning included). |
| `GH_ISSUE_SKIP_DEPS_CHECK` | unset | When `1`, skip 3.5 entirely. |

There is **no** env var to bypass 3.2 (block-label guard). That is
intentional — see "Block-label guard (fail-closed)" above.

## Behavior matrix

| Case | 3.2 block | 3.3 self-assign | 3.3b dup PR | 3.4 board | 3.5 deps | Net |
|---|---|---|---|---|---|---|
| Normal (board, unassigned, deps OK) | pass | add `@me` | silent | `In progress` (verified) | OK | proceed |
| Block-label attached | **abort exit 2** | n/a | n/a | n/a | n/a | refuse |
| Already self-assigned | pass | no-op | silent | `In progress` | OK | proceed |
| Assigned to another user | pass | warn + skip | silent | `In progress` | OK | proceed |
| Dependency `#M` OPEN | pass | add `@me` | silent | `In progress` | warn | proceed |
| No board attached | pass | add `@me` | silent | silent skip | OK | proceed |
| Open PR already closes `#N` | pass | no-op | **warn** | `In progress` | OK | proceed |
| Board Status already `In progress` | pass | no-op | silent | **warn** + no-op | OK | proceed |
| Duplicate search API error | pass | add `@me` | silent | `In progress` | OK | proceed |
| `GH_ISSUE_SKIP_SELF_ASSIGN=1` | pass | skip | silent | `In progress` | OK | proceed |
| `GH_ISSUE_SKIP_DUPLICATE_CHECK=1` | pass | add `@me` | skip | `In progress` | OK | proceed |
| `GH_ISSUE_SKIP_BOARD_TRANSITION=1` | pass | add `@me` | silent | skip | OK | proceed |
| `GH_ISSUE_SKIP_DEPS_CHECK=1` | pass | add `@me` | silent | `In progress` | skip | proceed |

The two duplicate-attempt rows are the dEitY719/dotfiles#1507 additions; "silent" in the
3.3b column means the guard ran and found nothing, which is the normal
outcome. Both warn rows still end in `proceed` — neither signal blocks.

## Placement rationale (why Step 3, not earlier or later)

- **After Step 1 preconditions**: claiming an issue while the working
  tree is dirty would force a rollback if Step 5 can't proceed.
- **After Step 2 superpowers detection**: mode dispatch happens in
  Step 4 — the claim must already exist so a long brainstorming
  session doesn't leave teammates wondering whether the issue is being
  worked.
- **Before Step 4 mode dispatch**: `writing-plans` / `brainstorming`
  can take many minutes; the assignee badge needs to be live before
  that.
- **Before Step 5 implement**: a board card stuck in `Backlog` while
  edits are landing is exactly the inconsistency this absorption fixes.

## What this does NOT do

- **Does not create a worktree.** `gh-issue:implement`'s precondition
  still requires the user to be in a feature branch + worktree.
- **Does not auto-unassign on later failure.** If Step 5's test loop
  exhausts, the assignee + board state stay set. Manual cleanup is
  one line each:
  - `GH_HOST="$TARGET_HOST" gh issue edit <N> --repo "$TARGET_REPO" --remove-assignee @me`
  - move the card back to `Backlog` on the project board.
- **Does not enforce stacked-PR `Depends on #parent-pr`.** Only issue
  references are scanned. PR-to-PR stacking is `gh-pr:create`'s territory.

## Self-check

`lib/claim-issue.selfcheck.sh` runs the behavior matrix above against
`lib/claim-issue.sh` with a fake `gh` on `PATH` and a stub board helper — no
network, no `gh` auth. It also extracts the call block above out of this file
and runs it, so a change to the flags here that the script does not implement
fails CI rather than a run. `tests/lib-selfchecks.sh` is what CI executes.
