#!/usr/bin/env bash
# lib/reply-args.sh — argument normalizer for gh-issue:issue-reply (#86).
# Derived from lib/review-args.sh (issue-review-all), minus the lane list.
#
#   bash lib/reply-args.sh <N|#N|issue-URL> [remote] [--no-edit] [-h]
#
# Executed, never sourced. Prints one `key=value` line per field on stdout:
#
#   help=0|1       1 -> the caller prints references/help.md and stops
#   issue=<N>
#   remote=<name>  the git remote to bind; empty only for a URL whose repo no
#                  local remote names (the caller then binds the URL's own
#                  host + repo)
#   host=<host> repo=<owner/repo>   from the URL; empty for N / #N input
#   no_edit=0|1    1 -> never edit the issue body, only propose edits in replies
#
# Exit 2 with the reason on stderr for every refusal: a PR URL (that is
# gh-pr:reply's job), any other URL shape, a remote that names a different
# repo than the URL, an unknown flag, a missing or malformed issue number.
#
# The URL -> remote match is textual on host + owner/repo (case-insensitive).
#
# Self-check: tests/bats/gh_issue_reply.bats
set -u

die() { printf '%s\n' "$1" >&2; exit 2; }

# url_slug <git-remote-url> -> "<host> <owner>/<repo>" lowercased, or nothing.
url_slug() {
    local u="$1" host path
    case "$u" in
    *://*)
        u=${u#*://}
        host=${u%%/*}
        path=${u#*/}
        ;;
    *:*)
        host=${u%%:*}
        path=${u#*:}
        ;;
    *) return 1 ;;
    esac
    host=${host##*@}
    host=${host%%:*}
    path=${path%/}
    path=${path%.git}
    case "$path" in */*/* | '' | /*) return 1 ;; */*) ;; *) return 1 ;; esac
    printf '%s %s\n' "$host" "$path" | tr '[:upper:]' '[:lower:]'
}

issue="" remote="" host="" repo="" no_edit=0 positional=0
while [ "$#" -gt 0 ]; do
    case "$1" in
    -h | --help | help)
        echo "help=1"
        exit 0
        ;;
    --no-edit) no_edit=1 ;;
    -*) die "Unknown flag: $1" ;;
    *)
        positional=$((positional + 1))
        case "$positional" in
        1)
            case "$1" in
            http://* | https://*)
                u=${1%%#*}
                u=${u%%\?*}
                u=${u%/}
                rest=${u#*://}
                host=${rest%%/*}
                rest=${rest#*/}
                owner=${rest%%/*}
                rest=${rest#*/}
                name=${rest%%/*}
                rest=${rest#*/}
                case "$rest" in
                pull/* | pulls/*)
                    die "$1 is a pull request URL — use /gh-pr:reply for PR review comments."
                    ;;
                issues/*) issue=${rest#issues/} ;;
                *) die "Not an issue URL (expected https://<host>/<owner>/<repo>/issues/<N>): $1" ;;
                esac
                case "$host" in '' | *[!A-Za-z0-9.:-]*) die "Bad host in URL: $1" ;; esac
                case "$owner/$name" in *[!A-Za-z0-9._/-]* | /* | */) die "Bad owner/repo in URL: $1" ;; esac
                repo="$owner/$name"
                ;;
            \#*) issue=${1#\#} ;;
            *) issue=$1 ;;
            esac
            case "$issue" in '' | *[!0-9]* | 0*) die "<issue> must be N, #N or an issue URL: '$1'" ;; esac
            ;;
        2) remote=$1 ;;
        *) die "Unexpected argument: $1" ;;
        esac
        ;;
    esac
    shift
done

[ -n "$issue" ] || die "Usage: issue-reply <N|#N|issue-URL> [remote] [--no-edit] — run with -h for help."

if [ -n "$repo" ]; then
    want=$(printf '%s %s\n' "$host" "$repo" | tr '[:upper:]' '[:lower:]')
    if [ -n "$remote" ]; then
        url=$(git remote get-url "$remote" 2>/dev/null) || die "Remote '$remote' not found."
        [ "$(url_slug "$url")" = "$want" ] ||
            die "Remote '$remote' ($url) is not $host/$repo — drop the remote argument or pass the matching one."
    else
        for r in $(git remote 2>/dev/null); do
            url=$(git remote get-url "$r" 2>/dev/null) || continue
            if [ "$(url_slug "$url")" = "$want" ]; then
                remote=$r
                break
            fi
        done
    fi
else
    [ -n "$remote" ] || remote=origin
fi

printf '%s\n' "help=0" "issue=$issue" "remote=$remote" "host=$host" "repo=$repo" "no_edit=$no_edit"
