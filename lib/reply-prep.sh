#!/usr/bin/env bash
# lib/reply-prep.sh — gh-issue:issue-reply Steps 1-4 (#86), read-only:
# arguments, target, pre-flight, comment fetch, item split.
#
#   bash lib/reply-prep.sh <N|#N|issue-URL> [remote] [--no-edit] [-h]
#
# Executed, never sourced; self-locating ($0), so it needs no
# CLAUDE_PLUGIN_ROOT and never resolves anything from $PWD
# (dEitY719/harness-skills#22). Writes nothing to GitHub.
#
# stdout, one `key=value` per line (help=1 alone for -h):
#
#   host= repo= issue=   the bound target; every later gh call uses these
#   login=               the account whose markers are trusted
#                        (GH_ISSUE_REPLY_TRUSTED_LOGIN overrides `gh api user`)
#   author=              the issue author
#   edit=auto|no-edit    auto only when login == author and no --no-edit
#   run=<dir>            mktemp dir holding comments.json (raw REST array),
#                        body.md (the body as read — edit-body's <orig-file>)
#                        and items.tsv (split-review-items.sh output)
#   items= open=         item count, and how many have no reply yet
#
# Exit 2 refusal (bad args, PR URL, remote naming another repo, bad login),
# 1 pre-flight failure (not logged in, issue missing or not OPEN, fetch
# failed). Nothing is written on either; the run dir is removed.
#
# Self-check: tests/bats/gh_issue_reply.bats
set -uo pipefail

ROOT=$(cd -P -- "$(dirname -- "$0")/.." && pwd)

parsed=$(bash "$ROOT/lib/reply-args.sh" "$@") || exit $?
help=0 issue="" remote="" host="" repo="" no_edit=0
while IFS='=' read -r k v; do
    case "$k" in
    help) help=$v ;; issue) issue=$v ;; remote) remote=$v ;;
    host) host=$v ;; repo) repo=$v ;; no_edit) no_edit=$v ;;
    esac
done <<EOF
$parsed
EOF
if [ "$help" = 1 ]; then
    echo "help=1"
    exit 0
fi

if [ -n "$remote" ]; then
    # shellcheck disable=SC1091
    GH_RESOLVE_TARGET_ROOT="$ROOT" GH_RESOLVE_TARGET_REMOTE="$remote" . "$ROOT/lib/resolve-target.sh" || exit 1
    if [ -n "$repo" ] && [ "$(printf '%s %s' "$TARGET_HOST" "$TARGET_REPO" | tr '[:upper:]' '[:lower:]')" != \
        "$(printf '%s %s' "$host" "$repo" | tr '[:upper:]' '[:lower:]')" ]; then
        echo "Remote '$remote' resolved to $TARGET_HOST/$TARGET_REPO, not $host/$repo." >&2
        exit 2
    fi
else
    TARGET_HOST=$host TARGET_REPO=$repo
fi
export GH_HOST="$TARGET_HOST"

GH_HOST="$TARGET_HOST" gh auth status --hostname "$TARGET_HOST" >/dev/null 2>&1 ||
    { echo "gh is not logged in to $TARGET_HOST (gh auth login --hostname $TARGET_HOST)." >&2; exit 1; }
meta=$(GH_HOST="$TARGET_HOST" gh issue view "$issue" --repo "$TARGET_REPO" --json state,author \
    --jq '.state + " " + .author.login' 2>/dev/null) ||
    { echo "Could not read issue #$issue in $TARGET_REPO on $TARGET_HOST (not found, no access, or network error)." >&2; exit 1; }
state=${meta%% *} author=${meta#* }
[ "$state" = OPEN ] || { echo "Issue #$issue is $state; only OPEN issues are replied to." >&2; exit 1; }

login=${GH_ISSUE_REPLY_TRUSTED_LOGIN:-$(GH_HOST="$TARGET_HOST" gh api user --jq .login 2>/dev/null)}
[[ "$login" =~ ^[A-Za-z0-9-]+(\[bot\])?$ ]] || { echo "Unexpected gh login: '$login'" >&2; exit 2; }

edit=no-edit
[ "$no_edit" = 1 ] || [ "$login" != "$author" ] || edit=auto

run=$(mktemp -d "${TMPDIR:-/tmp}/issue-reply.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
fail() { rm -rf "$run"; echo "$1" >&2; exit "$2"; }
# --paginate prints one JSON array per page; jq -s joins them.
GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/issues/$issue/comments" --paginate 2>/dev/null |
    jq -s 'add // []' >"$run/comments.json" || fail "Could not fetch the comments of #$issue." 1
GH_HOST="$TARGET_HOST" gh issue view "$issue" --repo "$TARGET_REPO" --json body --jq .body >"$run/body.md" 2>/dev/null ||
    fail "Could not read the body of #$issue." 1
bash "$ROOT/lib/split-review-items.sh" "$login" <"$run/comments.json" >"$run/items.tsv" || fail "Could not split the comments of #$issue." 1

printf '%s\n' "host=$TARGET_HOST" "repo=$TARGET_REPO" "issue=$issue" "login=$login" "author=$author" \
    "edit=$edit" "run=$run" "items=$(grep -c . "$run/items.tsv")" "open=$(awk -F'\t' '$3 == "open"' "$run/items.tsv" | grep -c .)"
