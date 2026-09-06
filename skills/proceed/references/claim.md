# gh-issue:proceed — Step 2.1 Fetch + Claim

Five substeps in order. This mirrors `/gh-issue:implement`'s claim policy
(kept as a self-contained copy per the dotfiles per-skill references
convention). Worktree creation stays the user's job; everything else
lands here.

## Substep order

```
2.1.1 Fetch issue              (gates everything; CLOSED refusal here)
2.1.2 Block-label guard        (HARD abort exit 2; cheapest "no")
2.1.3 Self-assign              (broadcast claim ASAP)
2.1.4 Board Status transition  (idempotent; verify-pair absorbs race)
2.1.5 Depends-on guard         (slowest; soft-warn, do last)
```

The HARD aborts (2.1.1, 2.1.2) come before any mutation (2.1.3, 2.1.4) so
an abort never leaves a stale claim or board state.

## 2.1.1 Fetch issue

See `references/fetch-issue.md`. The `gh issue view` JSON it returns is
reused by 2.1.2 (`labels`), 2.1.3 (`assignees`), 2.1.5 (`body`), and Step
2.2 schema validation (`body`) — call once, parse multiple times.

## 2.1.2 Block-label guard (fail-closed)

Refuse to proceed on an issue tagged `do-not-work`, `on-hold`, `보류`,
`⏸️ Postpone`, or whatever `GH_ISSUE_BLOCK_LABELS` lists. No escape hatch —
label removal is the only release.

```
labels = json.labels[].name
block  = split(GH_ISSUE_BLOCK_LABELS, ",")   # default above
for L in labels:
    if L in block:
        print "Refusing to start #<N> — blocked by label '<L>'."
        exit 2
```

`exit 2` is reserved suite-wide for "policy refusal" (distinct from `1`,
the implicit shell-error code).

## 2.1.3 Self-assign

```
me        = GH_HOST="$TARGET_HOST" gh api user -q .login   # no --repo: not repo-scoped
assignees = json.assignees[].login
if GH_ISSUE_SKIP_SELF_ASSIGN set: return 0
if me in assignees:               return 0   # idempotent
if assignees == []:
    GH_HOST="$TARGET_HOST" gh issue edit <N> --repo "$TARGET_REPO" \
      --add-assignee @me                     # soft-fail on API error
    return 0
print "[WARN] Issue #<N> is assigned to <other>; not overriding."
return 0
```

`--add-assignee` appends (never `--assignee`, which replaces). Forking a
teammate's claim is worse than a duplicated attempt — warn, don't override.

This is a **write**, so both halves of the Step 1 binding matter:
`--repo "$TARGET_REPO"` names the repo, `GH_HOST="$TARGET_HOST"` names the
server. Dropping the host on a dual-host login would assign someone on
whichever repo `gh repo set-default` picked (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407).

## 2.1.4 Board Status transition

```
if GH_ISSUE_SKIP_BOARD_TRANSITION set: return 0
_SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"                        # tier 1
# Tier 2 is guarded, never defaulted into a path: there is no tier 4. `$PWD` is
# caller-controlled and this family runs inside the repo under review, so a PR
# that ships lib/vendor/shell-common/ would get it sourced
# (dEitY719/harness-skills#22). With CLAUDE_PLUGIN_ROOT unset nothing is left to
# know, so `$_SC` keeps the tier-1 path and the proof below warns naming it.
[ -f "$_SC/functions/gh_project_status.sh" ] || [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] \
    || _SC="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common"                  # tier 2
_HELPER="$_SC/functions/gh_project_status.sh"
# Drop any inherited definition BEFORE sourcing, so the check below proves this
# load defined the function rather than an earlier one. A file-mode test cannot:
# -f passes an unreadable file, -r passes a directory, and neither notices a
# helper that sources halfway.
#
# Every step here is errexit-safe: a pasted block inherits the caller's `set -e`,
# and this transition is documented soft-fail — it must warn and skip, never
# abort the run. `unset -f` on an undefined name, a bare `[ ... ] && cmd` whose
# test fails, and a failed `.` are all non-zero, so each is neutralised.
unset -f _gh_project_status_sync 2>/dev/null || :
if [ -f "$_HELPER" ] && [ -r "$_HELPER" ]; then
    . "$_HELPER" || :
fi
if command -v _gh_project_status_sync >/dev/null 2>&1; then
    export SHELL_COMMON="$_SC"   # export only after the load is proved
    _gh_project_status_sync issue <N> "In progress" \
      --only-from "Backlog,Ready" --repo "$TARGET_REPO" || :
else
    printf '[gh-issue:proceed] gh_project_status.sh did not load from %s — board transition skipped. On any harness other than Claude Code, export CLAUDE_PLUGIN_ROOT=<plugin dir>.\n' \
        "$_SC" >&2
fi
```

`--repo "$TARGET_REPO"` (Step 1) is explicit (dEitY719/dotfiles#1405) — the helper's
`gh repo view` fallback answers `gh repo set-default`, not the remote
this run resolved.

No-board repos → silent rc 0. `--only-from Backlog,Ready` never bounces
an `In review` / `Done` card backwards. Soft-fail: any non-policy error
→ rc 0.

## 2.1.5 Depends-on guard (soft)

```
if GH_ISSUE_SKIP_DEPS_CHECK set: return 0
deps = grep -oEi 'Depends on #[0-9]+' <body> | sed 's/.*#//'
for M in deps:
    state = GH_HOST="$TARGET_HOST" gh issue view <M> --repo "$TARGET_REPO" --json state -q .state
    [ "$state" != CLOSED ] && print "[WARN] #<N> depends on #<M> (still <state>)."
```

Soft (warn + continue): the reference may be stale, or the user may be
scaffolding on an in-flight dependency. A `gh issue view <M>` error itself
→ one warn line + continue.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `GH_ISSUE_BLOCK_LABELS` | `do-not-work,on-hold,보류,⏸️ Postpone` | Block-label list for 2.1.2. |
| `GH_ISSUE_SKIP_SELF_ASSIGN` | unset | When `1`, skip 2.1.3. |
| `GH_ISSUE_SKIP_BOARD_TRANSITION` | unset | When `1`, skip 2.1.4. |
| `GH_ISSUE_SKIP_DEPS_CHECK` | unset | When `1`, skip 2.1.5. |

There is **no** env var to bypass 2.1.2 (block-label guard) — intentional.

## What this does NOT do

- **Does not create a worktree** — the precondition class (mutation-required)
  still requires the user to be on a feature branch in a worktree
  (`references/preconditions.md`).
- **Does not auto-unassign on later abort.** If Step 3 aborts, the assignee
  + board state stay set. Manual cleanup:
  `GH_HOST="$TARGET_HOST" gh issue edit <N> --repo "$TARGET_REPO"
  --remove-assignee @me` and move the card back on the board.
