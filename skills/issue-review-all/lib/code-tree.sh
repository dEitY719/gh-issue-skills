#!/usr/bin/env bash
# lib/code-tree.sh — the throwaway tree gh-issue:issue-review-all's reviewer CLIs
# run in (#70). Never the user's working tree, and never a worktree of the
# user's repo: the tree is a separate repo holding one commit (depth 1), so an
# agentic CLI that runs git in it cannot reach the user's branches, refs or
# object store (review of PR #71).
#
#   bash lib/code-tree.sh prepare <host> <owner/repo> [<remote>]
#   bash lib/code-tree.sh cleanup <dir>
#
# prepare prints `TREE=<dir>`, `KIND=<kind>` and `BASE=<branch>@<short-sha>`:
#
#   KIND=head            HEAD's commit, fetched depth 1 from the local repo
#                        over file:// — no network. Uncommitted changes are
#                        not reviewed.
#   KIND=default-branch  setup-mode internal (or unreadable) AND a github.com
#                        target: HEAD may hold internal-only commits, so the
#                        tree is <remote>'s default branch, freshly fetched,
#                        then copied depth 1 the same way — no internal object
#                        is in the tree's repo.
#
# The tree's branch is named after its source (<branch> above), so the
# engine's `리뷰 기준: <branch>@<sha>` line names it instead of `HEAD`.
#   KIND=clone           no local remote names the repo (URL input):
#                        `gh repo clone <host>/<owner>/<repo> <tmp> -- --depth 1`.
#
# The internal + github.com decision is gh_host.sh's
# `_gh_push_github_com_forbidden` (from $SHELL_COMMON), which already reads a
# missing setup-mode reader as internal. When gh_host.sh itself cannot be
# loaded, a github.com target is treated the same way (fail closed).
#
# cleanup deletes only a directory this script created (mktemp prefix
# gh-issue-review-tree. under ${TMPDIR:-/tmp}); anything else is refused.
#
# Self-check: lib/code-tree.selfcheck.sh
set -u

TMPROOT=$(cd -P -- "${TMPDIR:-/tmp}" && pwd)
PREFIX="gh-issue-review-tree."

is_github_com() {
    local h
    h=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    h=${h%%:*} # github.com:443 is still github.com — a port must not skip the leak guard
    case "$h" in github.com | *.github.com) return 0 ;; *) return 1 ;; esac
}

# forbidden <host> — 0 when HEAD must not be used for this target.
forbidden() {
    is_github_com "$1" || return 1
    local gh_host=""
    [ -z "${SHELL_COMMON:-}" ] || gh_host="$SHELL_COMMON/lib/gh_host.sh"
    if [ -n "$gh_host" ] && [ -f "$gh_host" ] && [ -r "$gh_host" ]; then
        unset -f _gh_push_github_com_forbidden 2>/dev/null || :
        # shellcheck disable=SC1090
        . "$gh_host" >/dev/null 2>&1 || :
        if [ "$(command -v _gh_push_github_com_forbidden 2>/dev/null)" = _gh_push_github_com_forbidden ]; then
            _gh_push_github_com_forbidden "$1"
            return
        fi
    fi
    return 0
}

base_of() { # base_of <dir> -> <branch>@<short-sha>
    printf '%s@%s\n' "$2" "$(git -C "$1" rev-parse --short HEAD)"
}

# snapshot <tmp> <commit> <branch> — a one-commit repo at <tmp>, sharing
# nothing with the current one. file:// (not a plain path) so --depth applies.
snapshot() {
    local top
    top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
    git init -q "$1" &&
        git -C "$1" fetch -q --depth 1 "file://$top" "$2" 2>/dev/null &&
        git -C "$1" checkout -q -b "$3" FETCH_HEAD 2>/dev/null
}

prepare() {
    local host="${1:-}" repo="${2:-}" remote="${3:-}" tmp branch label
    { [ -n "$host" ] && [ -n "$repo" ]; } || { echo "usage: code-tree.sh prepare <host> <owner/repo> [<remote>]" >&2; return 2; }
    tmp=$(mktemp -d "$TMPROOT/${PREFIX}XXXXXX") || { echo "Could not create a temp dir under $TMPROOT" >&2; return 1; }

    if [ -z "$remote" ]; then
        if ! GH_HOST="$host" gh repo clone "$host/$repo" "$tmp" -- --depth 1 -q >/dev/null 2>&1; then
            rm -rf "$tmp"
            echo "Could not clone $host/$repo (gh repo clone failed — check 'gh auth status --hostname $host')." >&2
            return 1
        fi
        branch=$(git -C "$tmp" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=unknown
        printf 'TREE=%s\nKIND=clone\nBASE=%s\n' "$tmp" "$(base_of "$tmp" "$branch")"
        return 0
    fi

    if forbidden "$host"; then
        branch=$(git ls-remote --symref "$remote" HEAD 2>/dev/null |
            sed -n 's@^ref: refs/heads/\(.*\)[[:space:]]HEAD$@\1@p')
        if [ -z "$branch" ] ||
            ! git fetch -q "$remote" "+refs/heads/$branch:refs/remotes/$remote/$branch" 2>/dev/null ||
            ! snapshot "$tmp" "$(git rev-parse "refs/remotes/$remote/$branch")" "$branch"; then
            rm -rf "$tmp"
            echo "Could not build a tree from $remote's default branch (internal PC + github.com target: HEAD is never used)." >&2
            return 1
        fi
        printf 'TREE=%s\nKIND=default-branch\nBASE=%s\n' "$tmp" "$(base_of "$tmp" "$branch")"
        return 0
    fi

    label=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || label=detached
    [ "$label" != HEAD ] || label=detached
    if ! snapshot "$tmp" "$(git rev-parse HEAD 2>/dev/null)" "$label"; then
        rm -rf "$tmp"
        echo "Could not copy HEAD into a throwaway tree." >&2
        return 1
    fi
    printf 'TREE=%s\nKIND=head\nBASE=%s\n' "$tmp" "$(base_of "$tmp" "$label")"
}

cleanup() {
    local dir="${1:-}" real
    [ -n "$dir" ] && [ -d "$dir" ] || return 0
    real=$(cd -P -- "$dir" && pwd) || return 1
    case "$real" in
    "$TMPROOT/$PREFIX"*) rm -rf "$real" ;;
    *)
        echo "Refusing to delete $real: not a tree this script created." >&2
        return 1
        ;;
    esac
}

case "${1:-}" in
prepare) shift; prepare "$@" ;;
cleanup) shift; cleanup "$@" ;;
*) echo "usage: code-tree.sh prepare <host> <owner/repo> [<remote>] | cleanup <dir>" >&2; exit 2 ;;
esac
