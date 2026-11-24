#!/usr/bin/env bash
# lib/reply-gate.sh — gh-issue:issue-reply Step 8 (#86): the label verdict.
# gh-pr:reply's review-passed gate (ORIGINS `<reviewer>:<severity>:<verdict>`)
# cut down to an issue: the ledger is the reply markers themselves, so there
# is no separate origin comment to forge or keep in sync.
#
#   <raw comment array> | bash lib/reply-gate.sh <expected-login>
#   <raw comment array> | bash lib/reply-gate.sh <expected-login> --apply <host> <owner/repo> <N>
#
# Executed, never sourced. Same input and trust rule as split-review-items.sh
# (which it runs): only reviews and replies <expected-login> wrote count, and
# only the latest trusted review per reviewer <ai> (a re-review supersedes the
# older one's items — silence does not, the old review stays until replaced).
#
# Output: one DECISION token on stdout —
#
#   pass=no-blocker                 no BLOCKER in any current review
#   pass=blockers-resolved:<n>      every current BLOCKER replied ACCEPT,
#                                   ACCEPT-PARTIAL or DECLINE (with a reason)
#   hold=unreplied-blocker:<key>    a current BLOCKER has no reply yet
#   hold=unresolved-blocker:<key>   a current BLOCKER was answered QUESTION
#   hold=no-external-review         no trusted ai-issue-review comment at all
#
# --apply then writes the labels, soft-fail (a [WARN] line, exit 0):
#   pass=*  -> add review-passed, remove review-blocked
#   hold=un* -> add review-blocked, remove review-passed
#   hold=no-external-review -> no write (nothing reviewed, nothing to certify)
#
# Exit 2 on bad arguments, otherwise the split-review-items.sh exit status.
#
# Self-check: tests/bats/gh_issue_reply.bats
set -u

HERE=$(cd -P -- "$(dirname -- "$0")" && pwd)
me=${1:-}
apply=0
if [ "${2:-}" = --apply ]; then
    [ "$#" -eq 5 ] || { echo "usage: reply-gate.sh <login> [--apply <host> <owner/repo> <N>]" >&2; exit 2; }
    apply=1 host=$3 repo=$4 issue=$5
elif [ "$#" -ne 1 ]; then
    echo "usage: reply-gate.sh <login> [--apply <host> <owner/repo> <N>]" >&2
    exit 2
fi

items=$(bash "$HERE/split-review-items.sh" "$me") || exit $?

decision=$(printf '%s\n' "$items" | awk -F'\t' '
    $1 !~ /^human:/ { reviewed = 1 }
    $1 !~ /^human:/ && $4 == "1" && $2 == "BLOCKER" {
        n++
        if ($3 == "open") { print "hold=unreplied-blocker:" $1; held = 1; exit }
        if ($3 == "replied:QUESTION") { print "hold=unresolved-blocker:" $1; held = 1; exit }
    }
    END {
        if (held) exit
        if (!reviewed) print "hold=no-external-review"
        else if (n == 0) print "pass=no-blocker"
        else print "pass=blockers-resolved:" n
    }')
printf '%s\n' "$decision"

[ "$apply" -eq 1 ] || exit 0
case "$decision" in
pass=*) add=review-passed del=review-blocked ;;
hold=no-external-review) exit 0 ;;
*) add=review-blocked del=review-passed ;;
esac
GH_HOST="$host" gh issue edit "$issue" --repo "$repo" --add-label "$add" >/dev/null 2>&1 ||
    printf '[WARN] could not add label %s to #%s (soft)\n' "$add" "$issue"
# Removing a label the issue does not carry is not an error worth a warning.
GH_HOST="$host" gh issue edit "$issue" --repo "$repo" --remove-label "$del" >/dev/null 2>&1 || :
exit 0
