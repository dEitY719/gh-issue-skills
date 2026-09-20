#!/bin/sh
# lib/claim-issue.sh — the "claim" half of Step 3, shared by gh-issue:implement
# (§3.2-3.5) and gh-issue:proceed (§2.1.2-2.1.5).
#
# SSOT for the four substeps both skills run once an issue has been fetched:
# block-label guard, self-assign, project-board Status transition, depends-on
# guard. EXECUTE it, never source it — unlike lib/resolve-target.sh this helper
# exports nothing; its products are the GitHub mutations, the stdout warnings
# and the exit code. Executing also keeps the caller's shell clean of the
# helper functions the board step sources.
#
#   printf '%s' "$ISSUE_JSON" | "$PLUGIN_ROOT/lib/claim-issue.sh" <N> \
#       --block-labels-default '<csv>' [--duplicate-pr-guard]
#
# The issue JSON arrives on stdin rather than being re-fetched here, so the
# "call `gh issue view` once, parse it many times" rule still holds: the caller
# already needs title/body/comments downstream. The CLOSED refusal stays in the
# caller's references/fetch-issue.md — its wording is per-skill ("refuse to
# implement" vs "refuse to proceed on a closed directive") and it gates the
# fetch, not the claim.
#
# Reads   TARGET_REPO, TARGET_HOST (required; bound by lib/resolve-target.sh),
#         SHELL_COMMON / CLAUDE_PLUGIN_ROOT / DOTFILES_ROOT (board helper),
#         GH_ISSUE_BLOCK_LABELS, GH_ISSUE_SKIP_SELF_ASSIGN,
#         GH_ISSUE_SKIP_DUPLICATE_CHECK, GH_ISSUE_SKIP_BOARD_TRANSITION,
#         GH_ISSUE_SKIP_DEPS_CHECK.
# Writes  nothing to the environment. Warnings on stdout, diagnostics on stderr.
# Exit    0 proceed (every substep but the block guard is soft-fail),
#         2 policy refusal (block label — reserved suite-wide, distinct from 1),
#         1 the helper itself broke (bad usage, missing target binding, no jq).
#
# The two callers differ in exactly two places, and both are arguments rather
# than branches on a caller name, so a reader of either skill's call site sees
# the whole difference:
#
#   --block-labels-default   implement ships a trailing `reference`
#                            (참고용/구현 불필요, dEitY719/dotfiles#1226);
#                            proceed deliberately does not.
#   --duplicate-pr-guard     implement only. proceed opens no PRs, so "an open
#                            PR already closes this issue" is not a duplicate
#                            signal for it.
#
# Self-check: lib/claim-issue.selfcheck.sh (no network, no gh auth).

set -u

N=''
BLOCK_DEFAULT=''
DUP_GUARD=0

die() { printf '[gh-issue:claim] %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --block-labels-default)
            [ $# -ge 2 ] || die "--block-labels-default needs a value"
            BLOCK_DEFAULT="$2"; shift 2 ;;
        --duplicate-pr-guard) DUP_GUARD=1; shift ;;
        -*) die "unknown flag: $1" ;;
        *)
            [ -z "$N" ] || die "unexpected extra argument: $1"
            N="$1"; shift ;;
    esac
done

case "$N" in
    ''|*[!0-9]*) die "usage: claim-issue.sh <issue-number> --block-labels-default <csv> [--duplicate-pr-guard]" ;;
esac
[ -n "$BLOCK_DEFAULT" ] || die "--block-labels-default is required — each caller states its own default so the divergence is visible at the call site"
if [ -z "${TARGET_REPO:-}" ] || [ -z "${TARGET_HOST:-}" ]; then
    die "TARGET_REPO and TARGET_HOST must be bound first (lib/resolve-target.sh, dEitY719/dotfiles#1403)"
fi
command -v jq >/dev/null 2>&1 || die "jq is required to parse the issue JSON"

ISSUE_JSON=$(cat) || die "could not read the issue JSON from stdin"
[ -n "$ISSUE_JSON" ] || die "empty issue JSON on stdin — pipe the Step 3.1 \`gh issue view --json ...\` output in"

# Every gh call below carries both halves of the Step 1 binding: --repo names
# the repo, GH_HOST names the server. Dropping either follows gh CLI's own
# `gh repo set-default` and, on a dual-host login, writes to a stranger's issue
# #N with no error at all (dEitY719/dotfiles#1403).
export GH_HOST="$TARGET_HOST"

# ---------------------------------------------------------------- 3.2 block
# Fail-closed, no escape hatch: removing the label is the only release
# (AgentToolbox #233 policy, inherited). Exit 2, not 1 — 1 is the implicit code
# for a broken shell command, 2 is reserved suite-wide for "refused on policy",
# so a wrapper can tell the two apart.
BLOCK_LABELS="${GH_ISSUE_BLOCK_LABELS:-$BLOCK_DEFAULT}"
ISSUE_LABELS=$(printf '%s' "$ISSUE_JSON" | jq -r '.labels[]?.name // empty')
# Matched in this shell, not down a pipeline: a `while read` fed by a pipe runs
# in a subshell, where an `exit 2` would refuse nothing at all. Split by
# parameter expansion rather than `for x in $VAR`, which zsh does not word-split
# — an executed script takes its shebang, but a guard that silently stops
# refusing under one shell is not the kind to leave shell-dependent. Commas
# separate the block list, newlines the issue's labels; a space is part of a
# label, so nothing is trimmed.
_hit=''
_labels_nl="
$ISSUE_LABELS
"
_rest="$BLOCK_LABELS"
while [ -n "$_rest" ]; do
    case "$_rest" in
        *,*) _blocked="${_rest%%,*}"; _rest="${_rest#*,}" ;;
        *)   _blocked="$_rest";       _rest='' ;;
    esac
    [ -n "$_blocked" ] || continue
    case "$_labels_nl" in
        *"
$_blocked
"*) _hit="$_blocked"; break ;;
    esac
done
if [ -n "$_hit" ]; then
    printf "Refusing to start #%s — blocked by label '%s'.\n" "$N" "$_hit"
    printf '  Remove the label and re-run, or check whether\n'
    printf '  the issue should stay parked.\n'
    exit 2
fi

# ---------------------------------------------------------- 3.3 self-assign
# Soft-fail throughout: the claim broadcasts intent, it is not load-bearing.
if [ -z "${GH_ISSUE_SKIP_SELF_ASSIGN:-}" ]; then
    if _me=$(gh api user -q .login 2>/dev/null) && [ -n "$_me" ]; then
        _assignees=$(printf '%s' "$ISSUE_JSON" | jq -r '.assignees[]?.login // empty')
        _held_by_me=0
        case "
$_assignees
" in *"
$_me
"*) _held_by_me=1 ;; esac
        _other="${_assignees%%
*}"
        if [ "$_held_by_me" -eq 1 ]; then
            : # idempotent no-op
        elif [ -z "$_assignees" ]; then
            # --add-assignee APPENDS. --assignee replaces, which would silently
            # boot a reviewer already on the issue — never use it here.
            gh issue edit "$N" --repo "$TARGET_REPO" --add-assignee @me >/dev/null 2>&1 \
                || printf '[WARN] Could not self-assign issue #%s (no write permission, or a transient API error) — continuing.\n' "$N"
        else
            # Forking a teammate's claim is worse than a duplicated attempt.
            printf '[WARN] Issue #%s is assigned to %s; not overriding.\n' "$N" "$_other"
            printf '    Coordinate via the issue thread, or rerun with\n'
            printf '    GH_ISSUE_SKIP_SELF_ASSIGN=1 to suppress this warning.\n'
        fi
    else
        printf '[WARN] Could not resolve the current gh user — skipping self-assign on #%s.\n' "$N"
    fi
fi

# ------------------------------------------------- 3.3b duplicate open-PR
# implement only (--duplicate-pr-guard). Catches what 3.3 structurally cannot:
# *I* am already the assignee because another of my own sessions claimed this
# issue minutes ago (dEitY719/dotfiles#1507 — dEitY719/dotfiles#1482 was implemented
# twice, 13 minutes apart). Read-only, advisory, never blocks. Silent on the
# empty result AND on its own failure: a line on every clean run would train
# the reader to scroll past exactly the signal this guard exists to add.
if [ "$DUP_GUARD" -eq 1 ] && [ -z "${GH_ISSUE_SKIP_DUPLICATE_CHECK:-}" ]; then
    # Both footer keywords gh-pr:commit accepts — a `Fixes #N` PR is just as
    # good a duplicate signal as a `Closes #N` one (codex review, PR dEitY719/dotfiles#1509).
    _dup=$(gh pr list --repo "$TARGET_REPO" --state open \
               --search "\"Closes #$N\" OR \"Fixes #$N\" in:body" \
               --json number -q '.[].number' 2>/dev/null | head -n 1)
    if [ -n "$_dup" ]; then
        printf '[WARN] Issue #%s 을 이미 닫는 open PR #%s 이 있습니다 — 중복 구현 가능성. 계속 진행하기 전에 확인하세요.\n' "$N" "$_dup"
    fi
fi

# ------------------------------------------------------------- 3.4 board
if [ -z "${GH_ISSUE_SKIP_BOARD_TRANSITION:-}" ]; then
    _SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}" # tier 1
    # No tier 4 (dEitY719/harness-skills#22): $PWD is the repo under review, so a
    # PR shipping its own lib/vendor/shell-common would get it sourced here.
    [ -f "$_SC/functions/gh_project_status.sh" ] || [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] \
        || _SC="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common" # tier 2
    _HELPER="$_SC/functions/gh_project_status.sh"
    # Drop any inherited definition BEFORE sourcing, so the check below proves
    # this load defined the function rather than an earlier one. A file-mode
    # test cannot: -f passes an unreadable file, -r passes a directory, and
    # neither notices a helper that sources halfway.
    unset -f _gh_project_status_sync 2>/dev/null || :
    if [ -f "$_HELPER" ] && [ -r "$_HELPER" ]; then
        # shellcheck disable=SC1090  # path is resolved at runtime
        . "$_HELPER" || :
    fi
    if command -v _gh_project_status_sync >/dev/null 2>&1; then
        # export only after the load is proved — an unproven export poisons
        # every later ${SHELL_COMMON:-...} default in the same run.
        export SHELL_COMMON="$_SC"
        # Warn when --only-from is about to absorb the write (dEitY719/dotfiles#1507 F-2).
        # Deliberately non-committal about why: the non-Backlog/Ready
        # complement also holds Done and custom columns, where "another session
        # started this" would be the wrong read (codex review, PR dEitY719/dotfiles#1509).
        # Reading the Status is itself best-effort (NF-1).
        if command -v _gh_project_status_query_current >/dev/null 2>&1 \
           && _status=$(_gh_project_status_query_current issue "$N" "$TARGET_REPO" 2>/dev/null) \
           && [ -n "$_status" ] && [ "$_status" != "Backlog" ] && [ "$_status" != "Ready" ]; then
            printf '[WARN] Issue #%s Status 가 이미 "%s" 입니다 — 다른 세션의 중복 착수이거나, 이슈가 이미 다른 단계로 넘어갔을 수 있습니다.\n' "$N" "$_status"
        fi
        # --repo is explicit (dEitY719/dotfiles#1405): the helper's own `gh repo view`
        # fallback answers `gh repo set-default`, not the remote this run bound.
        _gh_project_status_sync issue "$N" "In progress" \
            --only-from "Backlog,Ready" --repo "$TARGET_REPO" || :
    else
        # Defense-in-depth (dEitY719/dotfiles#724): sourceable but undefined would be a
        # silent no-op without this guard. One stderr line, never blocks.
        printf '[gh-issue:claim] _gh_project_status_sync did not load from %s — board transition skipped (dEitY719/dotfiles#724). On any harness other than Claude Code, export CLAUDE_PLUGIN_ROOT=<plugin dir>.\n' \
            "$_HELPER" >&2
    fi
fi

# --------------------------------------------------------- 3.5 depends-on
# Soft, unlike AgentToolbox claude-check-deps: the reference may be stale, or
# the user may be scaffolding on an in-flight dependency.
if [ -z "${GH_ISSUE_SKIP_DEPS_CHECK:-}" ]; then
    _body=$(printf '%s' "$ISSUE_JSON" | jq -r '.body // empty')
    # Case-insensitive; only whole `#<digits>` — not `#dep-3` or `#1.2.3`.
    for _m in $(printf '%s\n' "$_body" | grep -oEi 'Depends on #[0-9]+' | sed 's/.*#//' | awk '!seen[$0]++'); do
        if _state=$(gh issue view "$_m" --repo "$TARGET_REPO" --json state -q .state 2>/dev/null) \
           && [ -n "$_state" ]; then
            [ "$_state" != "CLOSED" ] || continue
            printf '[WARN] Issue #%s depends on #%s which is still %s.\n' "$N" "$_m" "$_state"
            printf '    The work may be premature — review or close #%s first.\n' "$_m"
        else
            printf '[WARN] Could not check dependency #%s of issue #%s (deleted, cross-repo, or a network error) — continuing.\n' "$_m" "$N"
        fi
    done
fi

exit 0
