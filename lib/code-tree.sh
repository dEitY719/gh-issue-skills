#!/usr/bin/env bash
# lib/code-tree.sh — the throwaway tree gh-issue:review-all's reviewer CLIs
# run in (#70). Never the user's working tree: an agentic CLI that edits files
# mid-review can only touch this copy.
#
#   bash lib/code-tree.sh prepare <host> <owner/repo> [<remote>]
#   bash lib/code-tree.sh cleanup <dir>
#
# prepare prints `TREE=<dir>`, `KIND=<kind>` and `BASE=<branch>@<short-sha>`:
#
#   KIND=head            `git worktree add --detach <tmp> HEAD` — local, no
#                        network. Uncommitted changes are not reviewed.
#   KIND=default-branch  setup-mode internal (or unreadable) AND a github.com
#                        target: HEAD may hold internal-only commits, so the
#                        tree is <remote>'s default branch, freshly fetched.
#   KIND=clone           no local remote names the repo (URL input):
#                        `gh repo clone <host>/<owner>/<repo> <tmp> -- --depth 1`.
#
# The internal + github.com decision is gh_host.sh's
# `_gh_push_github_com_forbidden` (from $SHELL_COMMON), which already reads a
# missing setup-mode reader as internal. When gh_host.sh itself cannot be
# loaded, a github.com target is treated the same way (fail closed).
#
# cleanup removes a registered worktree with `git worktree remove --force`, and
# otherwise deletes only a directory this script created (mktemp prefix
# gh-issue-review-tree. under ${TMPDIR:-/tmp}); anything else is refused.
#
# Self-check: lib/code-tree.selfcheck.sh
set -u

TMPROOT=$(cd -P -- "${TMPDIR:-/tmp}" && pwd)
PREFIX="gh-issue-review-tree."

is_github_com() {
    local h
    h=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    case "$h" in github.com | *.github.com) return 0 ;; *) return 1 ;; esac
}

# forbidden <host> — 0 when HEAD must not be used for this target.
forbidden() {
    is_github_com "$1" || return 1
    local gh_host="${SHELL_COMMON:-}/lib/gh_host.sh"
    if [ -n "${SHELL_COMMON:-}" ] && [ -f "$gh_host" ] && [ -r "$gh_host" ]; then
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
            ! git worktree add -q --detach "$tmp" "refs/remotes/$remote/$branch" >/dev/null 2>&1; then
            rm -rf "$tmp"
            echo "Could not build a tree from $remote's default branch (internal PC + github.com target: HEAD is never used)." >&2
            return 1
        fi
        printf 'TREE=%s\nKIND=default-branch\nBASE=%s\n' "$tmp" "$(base_of "$tmp" "$branch")"
        return 0
    fi

    label=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || label=HEAD
    if ! git worktree add -q --detach "$tmp" HEAD >/dev/null 2>&1; then
        rm -rf "$tmp"
        echo "Could not add a detached worktree at HEAD." >&2
        return 1
    fi
    printf 'TREE=%s\nKIND=head\nBASE=%s\n' "$tmp" "$(base_of "$tmp" "$label")"
}

cleanup() {
    local dir="${1:-}" real
    [ -n "$dir" ] && [ -d "$dir" ] || return 0
    real=$(cd -P -- "$dir" && pwd) || return 1
    if git worktree list --porcelain 2>/dev/null | grep -qxF "worktree $real"; then
        git worktree remove --force "$real" >/dev/null 2>&1 || :
    fi
    [ -d "$real" ] || return 0
    case "$real" in
    "$TMPROOT/$PREFIX"*)
        rm -rf "$real"
        git worktree prune 2>/dev/null || :
        ;;
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
