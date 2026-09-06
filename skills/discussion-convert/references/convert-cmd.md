# gh-issue:discussion-convert — Step 5-8 Convert Command

Detail companion to SKILL.md Steps 5 through 8. Reads the JSON
captured in Step 2 (the `_gh_discussion_fetch` output) and runs the
emulated convert sequence in order.

Inputs bound by the caller:

- `$TARGET_REPO`        — `owner/repo` from Step 1
- `$TARGET_HOST`        — the host parsed from that same remote URL
                          (Step 1); also exported as `GH_HOST`
- `$N`                  — Discussion number (positional arg)
- `$DISC_JSON`          — path to the temp file holding the JSON from
                          `_gh_discussion_fetch`
- `$OPT_NO_COMMENT`     — `1` if `--no-comment` was passed
- `$OPT_NO_LOCK`        — `1` if `--no-lock` was passed
- `$OPT_NO_CLOSE`       — `1` if `--no-close` was passed
- `$OPT_NO_BOARD_SYNC`  — `1` if `--no-board-sync` was passed

```bash
_GD="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_discussion.sh" # tier 1
# No tier 4 (dEitY719/harness-skills#22): $PWD is caller-controlled here.
[ -f "$_GD" ] || [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] \
    || _GD="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common/functions/gh_discussion.sh" # tier 2
# The second probe proves the tier the first one picked; without it a missing
# helper is sourced as a wrong path instead of stopping. -f and -r both: -r
# alone passes a directory, -f alone passes an unreadable file whose source
# then fails silently.
if [ ! -f "$_GD" ] || [ ! -r "$_GD" ]; then
    printf '[gh-issue:discussion-convert] helper not found at %s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_GD" >&2
    return 1 2>/dev/null || exit 1
fi
# shellcheck disable=SC1091
. "$_GD"
# gh_project_status.sh is NOT sourced here: Steps 6-8 moved into
# lib/discussion-post-convert.sh, which resolves and sources it itself.

DISC_ID=$(jq -r '.id'     "$DISC_JSON")
DTITLE=$(jq -r '.title'   "$DISC_JSON")
DCAT=$(jq -r '.category'  "$DISC_JSON")
DCLOSED=$(jq -r '.closed' "$DISC_JSON")
DLOCKED=$(jq -r '.locked' "$DISC_JSON")

# Step 3 — category guard (done by caller; this file assumes pass).

# Step 4 — idempotency check.
# `// empty` keeps EXISTING the empty string when the array is empty;
# without it jq prints the literal "null" which [ -n ... ] treats as
# non-empty, breaking first-run conversion (PR dEitY719/dotfiles#628 gemini review).
EXISTING=$(GH_HOST="$TARGET_HOST" gh issue list --repo "$TARGET_REPO" --state all \
    --search "in:body \"Originated from discussion #${N}\"" \
    --json number,url --limit 1 --jq '.[0].url // empty')
if [ -n "$EXISTING" ]; then
    printf '[OK] Discussion #%s already converted to %s\n' "$N" "$EXISTING"
    exit 0
fi

# Step 5 — create the issue with the backlink prepended. The trap is
# registered before the file is written so it cannot leak if a later
# step exits early or the process is interrupted. (The comment body's
# temp file now lives inside lib/discussion-post-convert.sh, under that
# script's own trap.)
ISSUE_BODY=$(mktemp)
trap 'rm -f "$ISSUE_BODY"' EXIT INT HUP TERM
printf 'Originated from discussion #%s\n\n' "$N" >"$ISSUE_BODY"
jq -r '.body' "$DISC_JSON" >>"$ISSUE_BODY"

ISSUE_URL=$(GH_HOST="$TARGET_HOST" gh issue create --repo "$TARGET_REPO" \
    --title "$DTITLE" --body-file "$ISSUE_BODY")
# Abort BEFORE Steps 6/7/8 if creation failed — mutating the Discussion
# without an Issue to back-link to violates the SSOT chain documented in
# error-cases.md and discussions-policy.md operating principle #4.
if [ -z "$ISSUE_URL" ]; then
    printf '[FAIL] Step 5: gh issue create failed -- aborting before mutating the Discussion.\n' >&2
    exit 1
fi
ISSUE_NUMBER="${ISSUE_URL##*/}"

# Steps 6-8 — board sync, backlink comment, close + lock. One call:
# lib/discussion-post-convert.sh owns the order, the skip flags and the
# best-effort contract, and prints the report's `steps:` line. It always
# exits 0 — a failed mutation shows up as a `fail` token plus a [WARN],
# never as an abort, because Step 5's Issue already satisfies the SSOT
# invariant. DCLOSED/DLOCKED come from the Step 2 fetch, so an
# already-closed Discussion reports `skip` instead of re-mutating.
export TARGET_REPO DCLOSED DLOCKED
STEPS=$(bash "${PLUGIN_ROOT:?run lib/resolve-target.sh first}/lib/discussion-post-convert.sh" \
    "$DISC_ID" "$ISSUE_NUMBER" \
    "${OPT_NO_COMMENT:-0}" "${OPT_NO_LOCK:-0}" \
    "${OPT_NO_CLOSE:-0}" "${OPT_NO_BOARD_SYNC:-0}")

printf '[OK] Discussion #%s -> Issue #%s: %s\n%s\n' \
    "$N" "$ISSUE_NUMBER" "$ISSUE_URL" "$STEPS"
```

확인 질문하지 말고 즉시 실행.

## Why four primitive mutations instead of one

`Convert to issue` lives only in the GitHub UI as of 2026-05. There
is no documented REST endpoint and the GraphQL schema does not expose
a `convertDiscussion` mutation. Until GitHub ships one, the
combination of `createIssue` + `addDiscussionComment` +
`closeDiscussion` + `lockLockable` reproduces every observable
side-effect of the native convert flow except the "transferred to
issue" UI banner. The lost banner is acceptable; the policy
invariants it visualises (close + bidirectional backlink + lock) are
still mechanically enforced here.

## Why `gh issue create` instead of GraphQL `createIssue`

The Issue mutation needs `repositoryId` (a node ID), default labels,
default assignee, and milestone handling — all of which `gh issue
create` resolves from `owner/repo` automatically and prints a stable
URL we can scrape for the issue number. A raw `createIssue` GraphQL
call would force this skill to re-implement that resolution chain,
duplicating logic that already lives in `gh-issue:create` /
`gh-issue:implement`.

## Why best-effort on Steps 6 / 7 / 8

The SSOT invariant is "decided Discussion -> tracked Issue with
backlink". Step 5 alone satisfies that contract. Steps 6 / 7 / 8 are
ergonomic helpers (board hygiene, reverse backlink, locked forum).
Rolling back the new Issue when one of them flakes would leave the
user in a worse state — Discussion still open, no Issue, work lost.
We warn and keep going.

## Idempotency mechanics

Step 4's `gh issue list --search "in:body ..."` relies on GitHub's
search indexer, which lags writes by a few seconds. The race window
where two near-simultaneous `gh-issue:discussion-convert` invocations could
both miss the index and create duplicate Issues is real but tiny;
human review at the Issue list is the last defense. We do not block
the skill on a sleep-and-recheck because the realistic call pattern
is one human running the skill once.
