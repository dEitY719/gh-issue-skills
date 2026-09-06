#!/bin/sh
# lib/discussion-post-convert.sh — Steps 6-8 of gh-issue:discussion-convert.
#
# EXECUTE it, never source it: the `steps:` line on stdout is the whole product.
#
#   bash "$PLUGIN_ROOT/lib/discussion-post-convert.sh" \
#       "$DISC_ID" "$ISSUE_NUMBER" "$OPT_NO_COMMENT" "$OPT_NO_LOCK" \
#       "$OPT_NO_CLOSE" "$OPT_NO_BOARD_SYNC"
#
# Reads   TARGET_REPO (Step 1), DCLOSED / DLOCKED (the Step 2 fetch JSON),
#         SHELL_COMMON / DOTFILES_ROOT / CLAUDE_PLUGIN_ROOT / PLUGIN_ROOT.
#         GH_HOST is inherited from Step 1 — `gh api graphql` takes no --repo,
#         so that export is the Discussion half's only host selector (dEitY719/dotfiles#1403).
# Prints  "  steps: comment=<t>, lock=<t>, close=<t>, board=<t>" — the line
#         references/report-template.md renders under the [OK] line.
#
# Exit 0 whatever the three mutations did. That IS the contract: the SSOT
# invariant ("decided Discussion -> tracked Issue with backlink") is already
# satisfied by the Issue the caller created in Step 5, and rolling that Issue
# back because a board sync flaked leaves the user strictly worse off. Failures
# surface as a `fail`/`failed` token plus a [WARN] on stderr, never as an abort.
#
# Self-check: lib/discussion-post-convert.selfcheck.sh

set -u

DISC_ID="${1:-}"
ISSUE_NUMBER="${2:-}"
NO_COMMENT="${3:-0}"
NO_LOCK="${4:-0}"
NO_CLOSE="${5:-0}"
NO_BOARD="${6:-0}"

if [ -z "$DISC_ID" ] || [ -z "$ISSUE_NUMBER" ]; then
    echo "usage: discussion-post-convert.sh <discussion-node-id> <issue-number> [no-comment] [no-lock] [no-close] [no-board-sync]" >&2
    exit 2
fi
if [ -z "${TARGET_REPO:-}" ]; then
    echo "Error: TARGET_REPO is unset — run lib/resolve-target.sh (Step 1) first." >&2
    exit 2
fi

# Helper tree. Tier 0 is whatever Step 1 already proved and exported; then the
# dotfiles monorepo; then the vendored copy under a plugin root the harness
# named. There is no cwd tier (dEitY719/harness-skills#22) — $PWD is the repo
# under review, which could ship its own lib/vendor/shell-common.
_dp_sc="${SHELL_COMMON:-}"
if [ -z "$_dp_sc" ] || [ ! -r "$_dp_sc/functions/gh_discussion.sh" ]; then
    _dp_sc="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common"
fi
if [ ! -r "$_dp_sc/functions/gh_discussion.sh" ]; then
    _dp_root="${CLAUDE_PLUGIN_ROOT:-}"
    [ -n "$_dp_root" ] || _dp_root="${PLUGIN_ROOT:-}"
    if [ -z "$_dp_root" ]; then
        echo "Error: cannot locate this plugin's root — CLAUDE_PLUGIN_ROOT and PLUGIN_ROOT are both unset. Export CLAUDE_PLUGIN_ROOT=<plugin dir>; refusing to resolve lib/vendor/shell-common from the current directory (dEitY719/harness-skills#22)." >&2
        exit 1
    fi
    _dp_sc="$_dp_root/lib/vendor/shell-common"
fi
# Prove the tier the probe above picked, for both helpers. -f and -r both: -r
# alone passes a directory, -f alone passes an unreadable file whose source then
# fails silently.
for _f in gh_discussion.sh gh_project_status.sh; do
    if [ ! -f "$_dp_sc/functions/$_f" ] || [ ! -r "$_dp_sc/functions/$_f" ]; then
        printf '[gh-issue:discussion-convert] helper not found at %s/functions/%s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
            "$_dp_sc" "$_f" >&2
        exit 1
    fi
done
# shellcheck disable=SC1090,SC1091  # path is resolved at runtime
. "$_dp_sc/functions/gh_discussion.sh"
# shellcheck disable=SC1090,SC1091
. "$_dp_sc/functions/gh_project_status.sh"

# Tokens: on = ran, off = disabled by a --no-* flag, skip = already in that
# state, fail = attempted and errored (board: synced/skipped/failed).
S_COMMENT=off
S_LOCK=off
S_CLOSE=off
S_BOARD=skipped

# Step 6 — board sync. --repo is explicit (dEitY719/dotfiles#1405): without it
# the helper resolves via `gh repo view`, i.e. `gh repo set-default`'s pick
# rather than the remote this run resolved. --only-from stops an
# already-progressed card bouncing back.
if [ "$NO_BOARD" != "1" ]; then
    if _gh_project_status_sync issue "$ISSUE_NUMBER" "In progress" \
        --only-from "Backlog,Ready" --repo "$TARGET_REPO" >/dev/null; then
        S_BOARD=synced
    else
        S_BOARD=failed
        printf '[WARN] board sync failed -- continuing\n' >&2
    fi
fi

# Step 7 — the reverse half of the bidirectional backlink. The forward half
# (Issue body -> Discussion) is already on the Issue from Step 5.
if [ "$NO_COMMENT" != "1" ]; then
    CBODY=$(mktemp) || exit 1
    trap 'rm -f "$CBODY"' EXIT INT HUP TERM
    printf 'Linked to issue #%s -- decision tracked there.\n' "$ISSUE_NUMBER" >"$CBODY"
    if _gh_discussion_comment "$DISC_ID" "$CBODY" >/dev/null; then
        S_COMMENT=on
    else
        S_COMMENT=fail
        printf '[WARN] discussion comment failed -- continuing\n' >&2
    fi
fi

# Step 8 — close, then lock. Both conditional on the current state read in
# Step 2, so a re-run on an already-closed Discussion reports skip, not fail.
if [ "$NO_CLOSE" = "1" ]; then
    :
elif [ "${DCLOSED:-false}" = "true" ]; then
    S_CLOSE=skip
elif _gh_discussion_close "$DISC_ID" RESOLVED >/dev/null; then
    S_CLOSE=on
else
    S_CLOSE=fail
    printf '[WARN] discussion close failed -- continuing\n' >&2
fi

if [ "$NO_LOCK" = "1" ]; then
    :
elif [ "${DLOCKED:-false}" = "true" ]; then
    S_LOCK=skip
elif _gh_discussion_lock "$DISC_ID" >/dev/null; then
    S_LOCK=on
else
    S_LOCK=fail
    printf '[WARN] discussion lock failed -- continuing\n' >&2
fi

printf '  steps: comment=%s, lock=%s, close=%s, board=%s\n' \
    "$S_COMMENT" "$S_LOCK" "$S_CLOSE" "$S_BOARD"
