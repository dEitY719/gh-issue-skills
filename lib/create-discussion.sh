#!/usr/bin/env bash
# lib/create-discussion.sh — Step 4 of gh-issue:discussion-create, and the
# `--as-discussion` path of gh-issue:issue-create (dEitY719/gh-issue-skills#53).
#
# EXECUTE it, never source it:
#
#   bash "$PLUGIN_ROOT/lib/create-discussion.sh" \
#       "${TARGET_REPO%%/*}" "${TARGET_REPO##*/}" "$CATEGORY" "$TITLE" "$BODY"
#
# Reads   GH_HOST (exported by Step 1). `gh api graphql` takes no --repo, so
#         that export is the only host selector the three calls have
#         (dEitY719/dotfiles#1403); empty -> exit 2 before any gh call.
#         TARGET_HOST, when set, must equal GH_HOST (same reason, #57).
#         SHELL_COMMON (optional, tier 0), DOTFILES_ROOT (optional, tier 1).
# Prints  the Discussion URL on stdout.
# Exit    0 created | 1 a lookup or the mutation failed, or gh_discussion.sh
#         did not resolve (the helper's own `[gh-discussion]` line is on
#         stderr) | 2 usage: missing argument, unreadable body file, empty
#         GH_HOST, or GH_HOST != a set TARGET_HOST.
#
# The body file is the caller's: it already holds the drafted body plus the
# ai-metrics footer (lib/ai-metrics-footer.sh). This script adds no bytes.
#
# gh_discussion.sh resolves from tier 0 `$SHELL_COMMON/functions/` (what Step 1's
# resolve-target.sh proved and exported), then tier 1
# `$DOTFILES_ROOT/shell-common/functions/` (default ~/dotfiles), then tier 2 this
# script's own `vendor/` sibling — the copy shipped inside the skill. Same order
# as discussion-post-convert.sh, so one run loads one copy (#56). There is no cwd tier (dEitY719/harness-skills#22):
# $PWD is the repo under review.
#
# Self-check: lib/create-discussion.selfcheck.sh
set -u

if [ "$#" -ne 5 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
    echo "usage: create-discussion.sh <owner> <repo> <category> <title> <body-file>" >&2
    exit 2
fi
if [ ! -f "$5" ] || [ ! -r "$5" ]; then
    printf '[FAIL] body file not readable: %s\n' "$5" >&2
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
unset -f _gh_discussion_repo_id _gh_discussion_category_id _gh_discussion_create 2>/dev/null
# shellcheck disable=SC1090
. "$_gd"
if [ "$(command -v _gh_discussion_create)" != _gh_discussion_create ]; then
    printf '[FAIL] %s did not define _gh_discussion_create.\n' "$_gd" >&2
    exit 1
fi

# Three calls, not one: each failure mode gets its own [gh-discussion] line
# (skills/discussion-create/references/create-cmd.md "Why three calls").
repo_id=$(_gh_discussion_repo_id "$1" "$2") || exit 1
category_id=$(_gh_discussion_category_id "$1" "$2" "$3") || exit 1
url=$(_gh_discussion_create "$repo_id" "$category_id" "$4" "$5") || exit 1
printf '%s\n' "$url"
