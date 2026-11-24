#!/usr/bin/env bash
# lib/issue-write.sh — the only two writes gh-issue:issue-reply makes (#86),
# each behind the leak guard.
#
#   bash lib/issue-write.sh comment   <host> <owner/repo> <N> <body-file>
#   bash lib/issue-write.sh edit-body <host> <owner/repo> <N> <orig-file> <new-file>
#
# Executed, never sourced; self-locating ($0), no $PWD fallback.
#
# comment    post <body-file> as an issue comment; one retry on failure.
#            stdout: the comment URL.
# edit-body  replace the issue body with <new-file>, in this order:
#              1. refuse unless the running login is the issue author (the
#                 --no-edit default for everyone else, #86 F-6)
#              2. refuse unless the live body is byte-identical to <orig-file>
#                 — the body the edit was derived from; anything else means
#                 someone edited it meanwhile
#              3. post the original as a `<!-- issue-reply-backup:<sha12> -->`
#                 comment (the preservation step — no backup, no edit)
#              4. gh issue edit --body-file <new-file>
#            stdout: `backup=<url>` then `edited=<sha12-old>..<sha12-new>`.
#
# Leak guard: an internal PC posting to github.com must clear
# LEAK_PATTERNS_ERE first — the gh_issue_review engine's rule, reused: the
# check applies unless shell-common's _gh_push_github_com_forbidden loads and
# says the host is allowed; an empty or broken pattern set blocks.
#
# Exit 0 done · 1 gh failure · 2 bad usage / policy refusal (not the author,
# issue not OPEN) · 3 leak guard held it · 4 body changed since read ·
# 5 original too large to back up in one comment. Every non-zero exit
# leaves the issue body untouched.
#
# Self-check: tests/bats/gh_issue_reply.bats
set -u

ROOT=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
die() { printf '%s\n' "$2" >&2; exit "$1"; }

# shell-common: the dotfiles checkout when it carries gh_host.sh, else the
# vendored copy this skill ships.
SC="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common"
[ -f "$SC/lib/gh_host.sh" ] || SC="$ROOT/lib/vendor/shell-common"
unset -f _gh_push_github_com_forbidden 2>/dev/null || :
export SHELL_COMMON="$SC"
# shellcheck disable=SC1091
[ -f "$SC/lib/gh_host.sh" ] && . "$SC/lib/gh_host.sh" >/dev/null 2>&1

# leak_check <host> <file> — rc 0 safe to post, rc 3 held (reason on stderr).
leak_check() {
    local rc=0
    if [ "$(command -v _gh_push_github_com_forbidden 2>/dev/null)" = _gh_push_github_com_forbidden ] &&
        ! _gh_push_github_com_forbidden "$1"; then
        return 0
    fi
    [ -n "${LEAK_PATTERNS_ERE-}" ] ||
        { echo "leak-guard: LEAK_PATTERNS_ERE is empty, cannot check a github.com post from an internal PC" >&2; return 3; }
    grep -Eq -- "$LEAK_PATTERNS_ERE" "$2" 2>/dev/null || rc=$?
    case "$rc" in
    1) return 0 ;;
    0) echo "leak-guard: $2 matches LEAK_PATTERNS_ERE" >&2 ;;
    *) echo "leak-guard: LEAK_PATTERNS_ERE could not be applied (grep exit $rc)" >&2 ;;
    esac
    return 3
}

# post <host> <repo> <N> <file> — one retry; prints the URL.
post() {
    local url
    url=$(GH_HOST="$1" gh issue comment "$3" --repo "$2" --body-file "$4" 2>/dev/null) ||
        url=$(GH_HOST="$1" gh issue comment "$3" --repo "$2" --body-file "$4") ||
        return 1
    printf '%s\n' "$url"
}

sha12() { sha256sum "$1" | cut -c1-12; }

cmd=${1:-}
case "$cmd" in
comment)
    [ "$#" -eq 5 ] || die 2 "usage: issue-write.sh comment <host> <owner/repo> <N> <body-file>"
    host=$2 repo=$3 issue=$4 file=$5
    [ -s "$file" ] || die 2 "empty or missing body file: $file"
    leak_check "$host" "$file" || exit 3
    post "$host" "$repo" "$issue" "$file" || die 1 "could not post the comment on #$issue (after one retry)"
    ;;
edit-body)
    [ "$#" -eq 6 ] || die 2 "usage: issue-write.sh edit-body <host> <owner/repo> <N> <orig-file> <new-file>"
    host=$2 repo=$3 issue=$4 orig=$5 new=$6
    [ -f "$orig" ] || die 2 "missing <orig-file>: $orig"
    [ -s "$new" ] || die 2 "empty or missing <new-file>: $new"
    cmp -s "$orig" "$new" && die 2 "<new-file> equals <orig-file> — nothing to edit"

    me=$(GH_HOST="$host" gh api user --jq .login) || die 1 "could not resolve the gh login on $host"
    meta=$(GH_HOST="$host" gh issue view "$issue" --repo "$repo" --json author,state \
        --jq '.state + " " + .author.login') || die 1 "could not read #$issue"
    [ "${meta%% *}" = OPEN ] || die 2 "#$issue is ${meta%% *} — never edited"
    [ "${meta#* }" = "$me" ] || die 2 "$me is not the author of #$issue (${meta#* }) — body not edited (--no-edit)"

    tmp=$(mktemp -d) || die 1 "mktemp failed"
    trap 'rm -rf "$tmp"' EXIT
    GH_HOST="$host" gh issue view "$issue" --repo "$repo" --json body --jq .body >"$tmp/live" ||
        die 1 "could not re-read the body of #$issue"
    cmp -s "$orig" "$tmp/live" || die 4 "the body of #$issue changed since it was read — re-run to re-judge"

    old=$(sha12 "$orig") newsha=$(sha12 "$new")
    # A fence longer than any backtick run in the body keeps it verbatim.
    run=$(grep -o '`\+' "$orig" | awk '{ if (length > m) m = length } END { print m + 0 }')
    fence=$(printf '%*s' $((run < 3 ? 3 : run + 1)) '' | tr ' ' '`')
    {
        printf '<!-- issue-reply-backup:%s -->\n' "$old"
        printf '<details>\n<summary>gh-issue:issue-reply — original body before edit (sha %s)</summary>\n\n' "$old"
        printf '%smarkdown\n' "$fence"
        cat "$orig"
        printf '\n%s\n\n</details>\n' "$fence"
    } >"$tmp/backup"
    [ "$(wc -c <"$tmp/backup")" -le 65000 ] ||
        die 5 "the original body of #$issue is too large to back up in one comment — body not edited"
    leak_check "$host" "$tmp/backup" || exit 3
    leak_check "$host" "$new" || exit 3

    url=$(post "$host" "$repo" "$issue" "$tmp/backup") || die 1 "backup comment failed — body not edited"
    printf 'backup=%s\n' "$url"
    GH_HOST="$host" gh issue edit "$issue" --repo "$repo" --body-file "$new" >/dev/null ||
        die 1 "gh issue edit failed — the original is preserved at $url"
    printf 'edited=%s..%s\n' "$old" "$newsha"
    ;;
*) die 2 "usage: issue-write.sh comment|edit-body ..." ;;
esac
