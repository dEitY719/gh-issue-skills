#!/usr/bin/env bash
# lib/discussion-fetch.sh — Step 2 of gh-issue:discussion-convert
# (dEitY719/gh-issue-skills#58).
#
# EXECUTE it, never source it:
#
#   DISC_JSON=$(mktemp)
#   bash "$PLUGIN_ROOT/lib/discussion-fetch.sh" \
#       "${TARGET_REPO%%/*}" "${TARGET_REPO##*/}" "$N" > "$DISC_JSON" || exit 1
#
# Reads   GH_HOST (exported by Step 1). `gh api graphql` takes no --repo, so
#         that export is the fetch's only host selector (dEitY719/dotfiles#1403);
#         empty -> exit 2 before any gh call. TARGET_HOST, when set, must equal
#         GH_HOST (#57). SHELL_COMMON (optional, tier 0), DOTFILES_ROOT
#         (optional, tier 1).
# Prints  the `_gh_discussion_fetch` JSON on stdout: id, number, title, body,
#         url, locked, closed, category.
# Exit    0 fetched | 1 the fetch failed (the helper's own `[gh-discussion]`
#         line is on stderr), or gh_discussion.sh did not resolve | 2 usage:
#         missing argument, empty GH_HOST, or GH_HOST != a set TARGET_HOST.
#
# gh_discussion.sh resolves in the same order as create-discussion.sh and
# discussion-post-convert.sh, so one run loads one copy: tier 0
# `$SHELL_COMMON/functions/`, tier 1 `$DOTFILES_ROOT/shell-common/functions/`
# (default ~/dotfiles), tier 2 this script's own `vendor/` sibling. There is no
# cwd tier (dEitY719/harness-skills#22): $PWD is the repo under review.
#
# Self-check: lib/discussion-fetch.selfcheck.sh
set -u

if [ "$#" -ne 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "usage: discussion-fetch.sh <owner> <repo> <discussion-number>" >&2
    exit 2
fi
if [ -z "${GH_HOST:-}" ]; then
    echo "[FAIL] GH_HOST is empty — Step 1 must export it; gh api graphql has no other host selector (dEitY719/dotfiles#1403)." >&2
    exit 2
fi
if [ -n "${TARGET_HOST:-}" ] && [ "$TARGET_HOST" != "$GH_HOST" ]; then
    printf '[FAIL] GH_HOST (%s) != TARGET_HOST (%s) — host and repo must come from one remote URL.\n' "$GH_HOST" "$TARGET_HOST" >&2
    exit 2
fi
export GH_HOST

_gd=""
[ -z "${SHELL_COMMON:-}" ] || _gd="$SHELL_COMMON/functions/gh_discussion.sh" # tier 0
if [ ! -f "$_gd" ] || [ ! -r "$_gd" ]; then
    _gd="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_discussion.sh" # tier 1
fi
if [ ! -f "$_gd" ] || [ ! -r "$_gd" ]; then
    _gd="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/vendor/shell-common/functions/gh_discussion.sh" # tier 2
fi
if [ ! -f "$_gd" ] || [ ! -r "$_gd" ]; then
    printf '[FAIL] gh_discussion.sh not found at %s — the skill install is missing lib/vendor; reinstall it.\n' "$_gd" >&2
    exit 1
fi
# Prove the load by the function name, not the file: an inherited exported
# function of the same name must not stand in for a failed source.
unset -f _gh_discussion_fetch 2>/dev/null
# shellcheck disable=SC1090
. "$_gd"
if [ "$(command -v _gh_discussion_fetch)" != _gh_discussion_fetch ]; then
    printf '[FAIL] %s did not define _gh_discussion_fetch.\n' "$_gd" >&2
    exit 1
fi

_gh_discussion_fetch "$1" "$2" "$3" || exit 1
