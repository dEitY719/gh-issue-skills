#!/usr/bin/env bash
# lib/review-all.sh — gh-issue:review-all driver (#70): every reviewer CLI
# reviews one GitHub issue in parallel, one issue comment each.
#
#   bash lib/review-all.sh <N|#N|issue-URL> [remote] [--lanes L] [-h]
#
# Executed, never sourced; self-locating ($0), so it needs no CLAUDE_PLUGIN_ROOT
# and never resolves anything from $PWD (dEitY719/harness-skills#22). Steps:
#
#   1. lib/review-args.sh            normalize the arguments (exit 2 on refusal)
#   2. lib/resolve-target.sh         GH_HOST + --repo from one remote URL; a URL
#                                    no remote names binds its own host + repo
#   3. pre-flight                    gh auth status on that host; issue OPEN
#   4. lib/code-tree.sh prepare      throwaway tree the CLIs run in
#   5. ai_fanout_run                 every lane at once, lib/review-lane.sh each,
#                                    540s cap per lane (GH_ISSUE_REVIEW_TIMEOUT_SEC)
#   6. report                        `issue-review #N: <ai>:ok <ai>:skip(<why>) ...`
#                                    then one `  <ai>: <comment-url>` per post
#
# The tree is removed on every exit path. A lane failure is a `skip`, never a
# failed run: exit 0 once the fan-out ran, 1 for a pre-flight / runtime
# failure, 2 for an argument refusal.
set -u

ROOT=$(cd -P -- "$(dirname -- "$0")/.." && pwd)

parsed=$(bash "$ROOT/lib/review-args.sh" "$@") || exit $?
help=0 issue="" remote="" host="" repo="" lanes=""
while IFS='=' read -r k v; do
    case "$k" in
    help) help=$v ;; issue) issue=$v ;; remote) remote=$v ;;
    host) host=$v ;; repo) repo=$v ;; lanes) lanes=$v ;;
    esac
done <<EOF
$parsed
EOF
if [ "$help" = 1 ]; then
    if [ -r "$ROOT/references/help.md" ]; then cat "$ROOT/references/help.md"; else echo "Usage: review-all <N|#N|issue-URL> [remote] [--lanes L] [-h]"; fi
    exit 0
fi

# ---- 2. target ----
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

# Engine tree: dotfiles first, only when it already carries the issue engine
# (an older checkout has gh_host.sh but not this), else the vendored copy.
SC="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common"
for f in functions/gh_issue_review.sh lib/ai_fanout.sh lib/ai_cli_run.sh; do
    [ -f "$SC/$f" ] || { SC="$ROOT/lib/vendor/shell-common"; break; }
done
unset -f ai_fanout_run 2>/dev/null || :
export SHELL_COMMON="$SC"
# shellcheck disable=SC1091
[ -f "$SC/lib/ai_fanout.sh" ] && . "$SC/lib/ai_fanout.sh"
[ "$(command -v ai_fanout_run 2>/dev/null)" = ai_fanout_run ] ||
    { echo "$SC did not load a usable lib/ai_fanout.sh — broken install." >&2; exit 1; }

# ---- 3. pre-flight ----
GH_HOST="$TARGET_HOST" gh auth status --hostname "$TARGET_HOST" >/dev/null 2>&1 ||
    { echo "gh is not logged in to $TARGET_HOST (gh auth login --hostname $TARGET_HOST)." >&2; exit 1; }
state=$(GH_HOST="$TARGET_HOST" gh issue view "$issue" --repo "$TARGET_REPO" --json state --jq .state 2>/dev/null) ||
    { echo "Could not read issue #$issue in $TARGET_REPO on $TARGET_HOST (not found, no access, or network error)." >&2; exit 1; }
[ "$state" = OPEN ] || { echo "Issue #$issue is $state; only OPEN issues are reviewed." >&2; exit 1; }

# ---- 4. code tree ----
tree_out=$(bash "$ROOT/lib/code-tree.sh" prepare "$TARGET_HOST" "$TARGET_REPO" "$remote") || exit 1
TREE=$(printf '%s\n' "$tree_out" | sed -n 's/^TREE=//p')
BASE=$(printf '%s\n' "$tree_out" | sed -n 's/^BASE=//p')
# An empty TREE would make the fan-out run the CLIs in the caller's cwd.
[ -n "$TREE" ] || { echo "code-tree.sh printed no TREE= line." >&2; exit 1; }
URLS=$(mktemp -d) || { bash "$ROOT/lib/code-tree.sh" cleanup "$TREE"; exit 1; }
# shellcheck disable=SC2317  # invoked by the EXIT trap
cleanup() {
    bash "$ROOT/lib/code-tree.sh" cleanup "$TREE" || :
    rm -rf "$URLS"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---- 5. fan-out ----
lines=$(ai_fanout_run "$TREE" "${GH_ISSUE_REVIEW_TIMEOUT_SEC:-540}" "$lanes" \
    bash "$ROOT/lib/review-lane.sh" "$URLS" "$TARGET_REPO" "$TARGET_HOST" "$TREE" "$issue") ||
    { echo "fan-out failed to start" >&2; exit 1; }

# ---- 6. report ----
summary=""
while IFS= read -r line; do
    [ -n "$line" ] || continue
    # Match on the lane token only: a skip reason may itself end in ":ok".
    case "${line%%	*}" in
    *:skip) summary="$summary ${line%%:*}:skip($(printf '%s' "${line#*	}" | cut -c1-80))" ;;
    *:ok) summary="$summary ${line%%:*}:ok" ;;
    esac
done <<EOF
$lines
EOF
printf 'issue-review #%s:%s\n' "$issue" "$summary"
printf '  base: %s (%s)\n' "$BASE" "$(printf '%s\n' "$tree_out" | sed -n 's/^KIND=//p')"
for f in "$URLS"/*; do
    [ -s "$f" ] && printf '  %s: %s\n' "${f##*/}" "$(cat "$f")"
done
exit 0
