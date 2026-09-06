#!/bin/sh
# lib/resolve-target.sh — bind one skill run's GitHub target (repo + host).
#
# SSOT for Step 1 "Detect Repo Context" across all six skills in this plugin.
# SOURCE it, never execute it — the exports are the whole product:
#
#   . "${CLAUDE_PLUGIN_ROOT:-.}/lib/resolve-target.sh" "${REMOTE:-origin}" || exit 1
#
# Reads   $1 (remote name, default `origin`), DOTFILES_ROOT, CLAUDE_PLUGIN_ROOT.
# Exports TARGET_REPO, TARGET_HOST, GH_HOST, SHELL_COMMON (whichever
#         shell-common tree actually resolved), and PLUGIN_ROOT (this plugin's
#         own root, for addressing lib/ helpers without a $PWD fallback).
#
# Why GH_HOST and not just `--repo` (dEitY719/dotfiles#1403): `gh api graphql` — the Discussion
# read and write path — accepts no `--repo`, so an inherited GH_HOST is its
# only host selector. Without it `gh` follows its own `gh repo set-default`
# rather than git's remote, and on a dual-host login (github.com + GHES) the
# mutation succeeds against the wrong server with no error at all.
#
# Self-check: lib/resolve-target.selfcheck.sh

# Path of this file, used to locate the vendored shell-common when
# CLAUDE_PLUGIN_ROOT is unset — the normal case on the five non-Claude
# harnesses this plugin supports. This branch MUST stay at file top level:
# zsh rebinds $0 to the sourced file only for this file's own statements, and
# inside a function $0 is the function's own name. Same shape as the branch in
# lib/vendor/shell-common/functions/gh_host.sh.
if [ -n "${ZSH_VERSION-}" ]; then
    _rt_self="$0"
elif [ -n "${BASH_VERSION-}" ]; then
    # shellcheck disable=SC3028  # bash-only var, gated by $BASH_VERSION above
    _rt_self="${BASH_SOURCE[0]-}"
else
    _rt_self=""
fi

_rt_resolve() {
    _rt_remote="${1:-origin}"

    if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
        echo "Not in a git repo. cd into one first." >&2
        return 1
    fi

    # Never fall back to `origin` on a missing remote — that masks a typo and
    # writes to the wrong repo.
    if ! _rt_url=$(git remote get-url "$_rt_remote" 2>/dev/null); then
        echo "Error: remote '$_rt_remote' not found. Available remotes:" >&2
        git remote -v >&2
        return 1
    fi

    # Plugin root, so a skill can address this plugin's own lib/ helpers
    # without composing a path from $PWD — which the repo under review
    # controls (dEitY719/harness-skills#22). Prefer the harness's
    # CLAUDE_PLUGIN_ROOT, else this file's own location; empty when neither
    # resolves, and a caller that needs it must then fail loudly.
    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
    if [ -z "$PLUGIN_ROOT" ]; then
        case "$_rt_self" in
            */lib/resolve-target.sh) PLUGIN_ROOT="${_rt_self%/lib/resolve-target.sh}" ;;
        esac
    fi
    export PLUGIN_ROOT

    _rt_sc="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common"
    if [ ! -f "$_rt_sc/functions/gh_host.sh" ]; then
        # Vendored tier, under whichever root resolved above.
        _rt_sc="${PLUGIN_ROOT:-.}/lib/vendor/shell-common"
    fi
    if [ ! -r "$_rt_sc/functions/gh_host.sh" ]; then
        echo "Error: gh_host.sh not found under $_rt_sc/functions/." >&2
        return 1
    fi
    # Export whichever tree resolved, so helpers sourced later by the calling
    # skill (gh_project_status.sh, gh_discussion.sh) read the same one.
    export SHELL_COMMON="$_rt_sc"
    # shellcheck disable=SC1090,SC1091  # path is resolved at runtime
    . "$_rt_sc/functions/gh_host.sh"

    # Repo and host both come from that one URL, so they can never name
    # different servers.
    TARGET_REPO=$(_gh_parse_owner_repo_url "$_rt_url") || return 1
    TARGET_HOST=$(_gh_host_from_url "$_rt_url") || TARGET_HOST=$(_gh_resolve_host)
    if [ -z "$TARGET_HOST" ]; then
        echo "Error: no host resolved for $_rt_url — refusing to run with an empty GH_HOST (dEitY719/dotfiles#1403)." >&2
        return 1
    fi

    GH_HOST="$TARGET_HOST"
    export TARGET_REPO TARGET_HOST GH_HOST
}

# The call's status becomes the sourcing skill's status.
_rt_resolve "$@"
