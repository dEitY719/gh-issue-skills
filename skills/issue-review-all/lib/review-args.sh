#!/usr/bin/env bash
# lib/review-args.sh — argument normalizer for gh-issue:issue-review-all (#70).
#
#   bash lib/review-args.sh <N|#N|issue-URL> [remote] [--ai L] [--force] [-h]
#
# Executed, never sourced. Prints one `key=value` line per field on stdout:
#
#   help=0|1     1 -> the caller prints references/help.md and stops
#   issue=<N>
#   remote=<name>  the git remote to bind; empty only for a URL whose repo no
#                  local remote names (the caller then clones the repo)
#   host=<host> repo=<owner/repo>   from the URL; empty for N / #N input
#   lanes=<ai>[,<ai>...]            from --ai; default claude,codex,opencode,agy,hermes
#                                   (the key keeps its internal name, #75)
#
# Exit 2 with the reason on stderr for every refusal: a PR URL (that is
# gh-verify:review-all's job), any other URL shape, a remote that names a
# different repo than the URL, an unknown or repeated lane, an unknown flag.
#
# The URL -> remote match is textual on host + owner/repo (case-insensitive),
# so an ssh host alias or `url.insteadOf` remote does not match: pass
# `<N> <remote>` then. Several matching remotes: the first in `git remote`
# order wins. Outside a git repo a URL simply matches no remote.
#
# Self-check: lib/review-args.selfcheck.sh
set -u

ALL_LANES="claude,codex,opencode,agy,hermes"

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

issue="" remote="" host="" repo="" lanes="$ALL_LANES" positional=0
while [ "$#" -gt 0 ]; do
    case "$1" in
    -h | --help | help)
        echo "help=1"
        exit 0
        ;;
    --force)
        # The dotfiles engine (gh_issue_review, dEitY719/dotfiles#2381) skips a
        # lane whose marker this login already posted and has no bypass, so a
        # --force here could only lie about re-running it.
        die "--force is not supported: the gh_issue_review engine has no bypass for its duplicate guard. To re-review, add a comment to the issue (the marker hash covers title, body and human comments) or delete the old review comment."
        ;;
    --ai)
        { [ "$#" -ge 2 ] && [ -n "$2" ]; } || die "--ai requires a value (e.g. --ai codex,claude)"
        lanes="$2"
        shift 2
        continue
        ;;
    --ai=*)
        lanes="${1#--ai=}"
        ;;
    -*)
        die "Unknown flag: $1"
        ;;
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
                    die "$1 is a pull request URL — use /gh-verify:review-all for PR reviews."
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

[ -n "$issue" ] || die "Usage: issue-review-all <N|#N|issue-URL> [remote] [--ai L] — run with -h for help."

# Lanes: a subset of the five reviewer CLIs, no repeats.
case ",$lanes," in *,,*) die "--ai has an empty entry: '$lanes'" ;; esac
seen=","
IFS=, read -r -a _l <<<"$lanes"
for a in "${_l[@]}"; do
    case ",$ALL_LANES," in *",$a,"*) ;; *) die "Unknown lane '$a' (allowed: $ALL_LANES)" ;; esac
    case "$seen" in *",$a,"*) die "Lane repeated: '$a'" ;; esac
    seen="$seen$a,"
done

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

printf '%s\n' "help=0" "issue=$issue" "remote=$remote" "host=$host" "repo=$repo" "lanes=$lanes"
