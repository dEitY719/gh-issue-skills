#!/usr/bin/env bash
# lib/review-lane.sh — one reviewer lane of gh-issue:review-all (#70).
#
#   bash lib/review-lane.sh <url-dir> <owner/repo> <host> <workdir> <issue#> <ai>
#
# The entry command `ai_fanout_run` starts once per lane (the lane name comes
# last, as that core appends it). Runs the dotfiles engine
# `_gh_issue_review_main` from $SHELL_COMMON (dEitY719/dotfiles#2381) and turns
# its outcome into what the fan-out core reports:
#
#   posted            exit 0; the comment URL is written to <url-dir>/<ai>
#   already reviewed  exit 4, stderr `already reviewed` — the engine exits 0
#                     on its duplicate guard, which would otherwise read `ok`
#   leak guard        exit 3, stderr `leak-guard`
#   anything else     the engine's rc, stderr = its first line that is not a
#                     [WARN] block (the fan-out core shows the first line only)
#
# Self-check: tests/bats/gh_issue_review_all.bats
set -u

[ "$#" -eq 6 ] || { echo "usage: review-lane.sh <url-dir> <owner/repo> <host> <workdir> <issue#> <ai>" >&2; exit 2; }
urldir=$1 repo=$2 host=$3 workdir=$4 issue=$5 ai=$6

if [ -z "${SHELL_COMMON:-}" ] || [ ! -r "$SHELL_COMMON/functions/gh_issue_review.sh" ]; then
    echo "engine not found: ${SHELL_COMMON:-SHELL_COMMON unset}/functions/gh_issue_review.sh" >&2
    exit 1
fi

# Plain text only: the first stderr line becomes the report's skip reason.
# shellcheck disable=SC2317  # called by the sourced engine
ux_error() { printf '%s\n' "$1" >&2; }
export NO_COLOR=1 DOTFILES_FORCE_INIT=1
unset -f _gh_issue_review_main 2>/dev/null || :
# shellcheck disable=SC1091
. "$SHELL_COMMON/functions/gh_issue_review.sh" 2>/dev/null
[ "$(command -v _gh_issue_review_main 2>/dev/null)" = _gh_issue_review_main ] ||
    { echo "engine did not load from $SHELL_COMMON" >&2; exit 1; }

out=$(mktemp) err=$(mktemp)
trap 'rm -f "$out" "$err"' EXIT
rc=0
_gh_issue_review_main --ai "$ai" --repo "$repo" --host "$host" --workdir "$workdir" "$issue" \
    >"$out" 2>"$err" || rc=$?

if [ "$rc" -eq 0 ]; then
    if grep -q '^\[SKIP\]' "$out"; then
        echo "already reviewed" >&2
        exit 4
    fi
    sed -n 's/^\[OK\] .* comment: //p' "$out" | sed -n '1p' >"$urldir/$ai"
    # No URL means the engine's output changed shape: never report ok blind.
    [ -s "$urldir/$ai" ] || { echo "posted, but no comment URL in the engine output" >&2; exit 1; }
    exit 0
fi
if [ "$rc" -eq 3 ]; then
    echo "leak-guard" >&2
    exit 3
fi
why=$(grep -v -e '^\[WARN\]' -e '^[[:space:]]' -e '^$' "$err" | sed -n '1p')
echo "${why:-exit $rc}" >&2
exit "$rc"
