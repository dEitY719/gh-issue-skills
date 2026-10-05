#!/usr/bin/env bash
# lib/link-deps.sh — Step 4.5 of gh-issue:issue-create: link the new issue as
# `Blocked by #N` with GitHub's native Issue Dependencies
# (dEitY719/dotfiles#1424, dEitY719/gh-issue-skills#53).
#
# EXECUTE it, never source it:
#
#   DEP_WARNINGS=$(bash "$PLUGIN_ROOT/lib/link-deps.sh" "$NEW_NUM" $DEP_NUMS)
#
# Reads   GH_HOST and TARGET_REPO (Step 1). The GraphQL endpoint is chosen by
#         host alone, so GH_HOST is exported for both calls (dEitY719/dotfiles#1403).
# Prints  on stdout, per failed N, the NF-1 warning plus an indented `원인:`
#         line carrying the first stderr line of the failing call (omitted
#         when nothing was captured, dEitY719/dotfiles#1458). Empty = every N linked.
# Exit    always 0 (NF-1): the issue already exists, nothing here may abort it.
#
# Per N: one aliased query resolves both node ids, then one `addBlockedBy`
# mutation — AddBlockedByInput is {issueId: ID!, blockingIssueId: ID!}, one
# blocker per call (dEitY719/dotfiles#1445). Never retries, never falls back to
# a label or a body trailer.
#
# Self-check: lib/link-deps.selfcheck.sh
set -u

new=${1:-}
[ "$#" -gt 0 ] && shift

errf=$(mktemp 2>/dev/null) || errf="${TMPDIR:-/tmp}/gh-issue-create-dep-$$.err"
trap 'rm -f "$errf"' EXIT

warn() { # warn <N> <cause-file-or-empty>
    printf '[WARN] Blocked by #%s 링크 실패 — GH UI에서 수동 추가 필요\n' "$1"
    _cause=""
    [ -n "$2" ] && _cause=$(head -n 1 "$2" 2>/dev/null)
    [ -z "$_cause" ] || printf '    원인: %s\n' "$_cause"
}

if [ -z "$new" ] || [ -z "${GH_HOST:-}" ] || [ -z "${TARGET_REPO:-}" ]; then
    printf 'link-deps: new issue number, GH_HOST or TARGET_REPO missing — no gh call made\n' > "$errf"
    for N in "$@"; do warn "$N" "$errf"; done
    exit 0
fi
export GH_HOST

for N in "$@"; do
    # `// ""` keeps a GraphQL null out of the mutation: a missing issue would
    # otherwise send the literal string "null" as an ID!. stderr goes to $errf,
    # not /dev/null, so a rejection names itself (dEitY719/dotfiles#1458).
    # Variables: $owner String!, $name String!, $new Int!, $dep Int!
    # shellcheck disable=SC2016
    ids=$(gh api graphql \
        -f owner="${TARGET_REPO%%/*}" -f name="${TARGET_REPO##*/}" \
        -F new="$new" -F dep="$N" \
        -f query='
          query($owner:String!, $name:String!, $new:Int!, $dep:Int!) {
            repository(owner:$owner, name:$name) {
              newIssue: issue(number:$new) { id }
              depIssue: issue(number:$dep) { id }
            }
          }' --jq '(.data.repository // {}) |
                   "\(.newIssue.id // "") \(.depIssue.id // "")"' 2>"$errf") || ids=""
    new_id=${ids%% *}
    dep_id=${ids##* }
    if [ -n "$new_id" ] && [ -n "$dep_id" ]; then
        # Variables: $issueId ID!, $blockingIssueId ID!
        # shellcheck disable=SC2016
        gh api graphql \
            -f issueId="$new_id" -f blockingIssueId="$dep_id" \
            -f query='
              mutation($issueId:ID!, $blockingIssueId:ID!) {
                addBlockedBy(input:{issueId:$issueId, blockingIssueId:$blockingIssueId}) {
                  issue { number }
                }
              }' >/dev/null 2>"$errf" && continue
    fi
    warn "$N" "$errf"
done
exit 0
