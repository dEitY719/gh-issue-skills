# gh-issue:proceed — Step 2.1 Fetch + Claim

Five substeps in order. The algorithm is
[`lib/claim-issue.sh`](../../../lib/claim-issue.sh), shared with
`/gh-issue:implement` (dEitY719/gh-issue-skills#21); this file states the
policy *this* skill runs it under. Worktree creation stays the user's job;
everything else lands here.

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

**No duplicate open-PR guard.** `implement` runs one between its self-assign
and its board move (its `references/claim.md` §3.3b): an open PR that closes
the issue is its fingerprint for "another session already did this". This
skill opens no PRs, so that search would answer about somebody else's work,
not a duplicate of its own. The shared script therefore runs it only when
the caller asks — and this one does not.

## 2.1.1 Fetch issue

See `references/fetch-issue.md` — it owns the `gh issue view` call and the
CLOSED refusal, whose wording ("refuse to proceed on a closed directive")
and ordering (before schema validation) are this skill's own. The JSON it
returns is `$ISSUE_JSON` below and is reused by 2.1.2 (`labels`), 2.1.3
(`assignees`), 2.1.5 (`body`), and Step 2.2 schema validation (`body`) —
call once, parse many times.

## 2.1.2–2.1.5 Run the claim

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
    --block-labels-default 'do-not-work,on-hold,보류,⏸️ Postpone'
_rc=$?
[ "$_rc" -eq 0 ] || exit "$_rc"
```

Executed, not sourced: the helper exports nothing, and its own process keeps
the board helper's functions out of this skill's shell.

**No `reference` in the default block list.** `implement` appends it — a
`reference` issue is 참고용/구현 불필요, so there is nothing to implement
(dEitY719/dotfiles#1226). A directive issue carrying that label is still a
directive, and refusing to execute it would be a policy this skill never
adopted. `GH_ISSUE_BLOCK_LABELS`, when set, replaces the whole list.

## 2.1.2 Block-label guard (fail-closed)

Refuse to proceed on an issue tagged `do-not-work`, `on-hold`, `보류`,
`⏸️ Postpone`, or whatever `GH_ISSUE_BLOCK_LABELS` lists. No escape hatch —
label removal is the only release.

`exit 2` is reserved suite-wide for "policy refusal", distinct from `1`,
which is the implicit code a broken shell command returns; the
`exit "$_rc"` above is what carries it out of the claim and into this
skill's own exit status, so an unattended caller can tell "the directive was
refused" from "the runner broke".

## 2.1.3 Self-assign

`--add-assignee` appends (never `--assignee`, which replaces). Forking a
teammate's claim is worse than a duplicated attempt — warn, don't override.
Already holding it yourself is an idempotent no-op, and any write failure is
one `[WARN]` line and continue.

This is a **write**, so both halves of the Step 1 binding matter:
`--repo "$TARGET_REPO"` names the repo, `GH_HOST="$TARGET_HOST"` names the
server. Dropping the host on a dual-host login would assign someone on
whichever repo `gh repo set-default` picked (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407).

## 2.1.4 Board Status transition

`_gh_project_status_sync issue "$N" "In progress" --only-from "Backlog,Ready"
--repo "$TARGET_REPO"`. `--repo` is explicit (dEitY719/dotfiles#1405) — the helper's
`gh repo view` fallback answers `gh repo set-default`, not the remote
this run resolved.

No-board repos → silent rc 0. `--only-from Backlog,Ready` never bounces
an `In review` / `Done` card backwards, and a card already outside those two
gets one advisory `[WARN]` naming its current Status before the (no-op)
write. Soft-fail: any non-policy error → rc 0.

Locating the helper follows the plugin-root convention
(`harness-skills#10`): tier 1 `$SHELL_COMMON`, tier 2
`$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common`, **no tier 4** — `$PWD` is the
repo under review (dEitY719/harness-skills#22). Sourceable-but-undefined is a
one-line stderr warning and a skipped step, never an abort.

## 2.1.5 Depends-on guard (soft)

Case-insensitive `Depends on #M` in the body; each `M` that is not CLOSED
gets one `[WARN]` line. Soft (warn + continue): the reference may be stale,
or the user may be scaffolding on an in-flight dependency. A failed
`gh issue view <M>` is itself one warn line + continue.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `GH_ISSUE_BLOCK_LABELS` | `do-not-work,on-hold,보류,⏸️ Postpone` | Block-label list for 2.1.2; replaces `--block-labels-default` entirely when set. |
| `GH_ISSUE_SKIP_SELF_ASSIGN` | unset | When `1`, skip 2.1.3. |
| `GH_ISSUE_SKIP_BOARD_TRANSITION` | unset | When `1`, skip 2.1.4. |
| `GH_ISSUE_SKIP_DEPS_CHECK` | unset | When `1`, skip 2.1.5. |

`GH_ISSUE_SKIP_DUPLICATE_CHECK` has no effect here — without
`--duplicate-pr-guard` there is no duplicate search to skip.

There is **no** env var to bypass 2.1.2 (block-label guard) — intentional.

## What this does NOT do

- **Does not create a worktree** — the precondition class (mutation-required)
  still requires the user to be on a feature branch in a worktree
  (`references/preconditions.md`).
- **Does not auto-unassign on later abort.** If Step 3 aborts, the assignee
  + board state stay set. Manual cleanup:
  `GH_HOST="$TARGET_HOST" gh issue edit <N> --repo "$TARGET_REPO"
  --remove-assignee @me` and move the card back on the board.

## Self-check

`lib/claim-issue.selfcheck.sh` extracts the call block above out of this file
and runs it against a fake `gh`, asserting both divergences from `implement`
— no `reference` refusal, no PR search — so a drift between these two docs
and the one script fails CI instead of a run.
