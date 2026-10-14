#!/usr/bin/env bash
# tests/bats/fixtures/gh_issue_implement_claim.sh
# Runs the shipped lib/claim-issue.sh (Step 3 claim of gh-issue:implement,
# skills/implement/references/claim.md) one substep at a time.
#
# Each gh_issue_* function below executes the real helper with every other
# substep skipped, a stub `gh` on PATH and a stub board helper as
# SHELL_COMMON, then reports what the helper did. Only the two external
# programs are faked; the control flow under test is the shipped one.
#
# Inputs (all FAKE_*, read by the stubs):
#   FAKE_LABELS         — comma-separated label names on the issue
#   FAKE_ASSIGNEES      — comma-separated current assignees
#   FAKE_ME             — current user login (default: me)
#   FAKE_BODY           — issue body text (depends-on grep target)
#   FAKE_DEPS_STATES    — "M:STATE,M2:STATE2" for `gh issue view M`.
#                         Missing key -> OPEN.
#   FAKE_BOARD_ATTACHED — "0" when no projectV2 is attached (default: 1).
#   FAKE_BOARD_STATUS   — current board Status column. Unset -> unknown.
#   FAKE_OPEN_PRS_CLOSING      — comma-separated open PRs closing the issue.
#   FAKE_DUPLICATE_PR_API_FAIL — "1" makes the PR search itself fail.

# The implement caller's --block-labels-default, read from claim.md so the
# suite tests the default the skill actually passes.
_claim_block_default() {
    sed -n "s/.*--block-labels-default '\([^']*\)'.*/\1/p" \
        "${REPO_ROOT}/skills/implement/references/claim.md" | head -n 1
}

# _claim_run <N> [claim-issue.sh flags...]
# Sets CLAIM_OUT (stdout+stderr), CLAIM_RC, CLAIM_LOG (stub call log).
_claim_run() {
    local _n="$1"; shift
    local _t
    _t=$(mktemp -d) || return 1
    mkdir -p "$_t/bin" "$_t/sc/functions"
    cat >"$_t/bin/gh" <<'GH'
#!/bin/sh
printf '%s\n' "$*" >> "$CLAIM_GH_LOG"
case "$1 ${2:-}" in
    "api user") printf '%s\n' "${FAKE_ME:-me}" ;;
    "pr list")
        [ "${FAKE_DUPLICATE_PR_API_FAIL:-0}" != 1 ] || exit 1
        [ -z "${FAKE_OPEN_PRS_CLOSING:-}" ] || printf '%s\n' "$FAKE_OPEN_PRS_CLOSING" | tr ',' '\n' ;;
    "issue edit") : ;;
    "issue view")
        printf '%s\n' "${FAKE_DEPS_STATES:-}" | tr ',' '\n' |
            awk -F: -v k="$3" '$1 == k { print $2; f = 1 } END { if (!f) print "OPEN" }' ;;
    *) exit 1 ;;
esac
GH
    chmod +x "$_t/bin/gh"
    cat >"$_t/sc/functions/gh_project_status.sh" <<'SC'
_gh_project_status_sync() {
    if [ "${FAKE_BOARD_ATTACHED:-1}" = 0 ]; then echo no-board; else echo "sync $*"; fi >> "$CLAIM_GH_LOG"
}
_gh_project_status_query_current() {
    [ "${FAKE_BOARD_ATTACHED:-1}" != 0 ] && [ -n "${FAKE_BOARD_STATUS:-}" ] || return 1
    printf '%s\n' "$FAKE_BOARD_STATUS"
}
SC
    : >"$_t/gh.log"
    local _json
    _json=$(LBL="${FAKE_LABELS-}" ASG="${FAKE_ASSIGNEES-}" BODY="${FAKE_BODY-}" jq -nc '
        {number: 7, title: "t", state: "OPEN", url: "u", comments: [], body: env.BODY,
         labels:    (env.LBL | if . == "" then [] else split(",") | map({name: .}) end),
         assignees: (env.ASG | if . == "" then [] else split(",") | map({login: .}) end)}')
    CLAIM_OUT=$(printf '%s' "$_json" | env PATH="$_t/bin:$PATH" SHELL_COMMON="$_t/sc" \
        CLAIM_GH_LOG="$_t/gh.log" TARGET_REPO=acme/widget TARGET_HOST=github.com \
        FAKE_ME="${FAKE_ME-}" FAKE_DEPS_STATES="${FAKE_DEPS_STATES-}" \
        FAKE_BOARD_ATTACHED="${FAKE_BOARD_ATTACHED-}" FAKE_BOARD_STATUS="${FAKE_BOARD_STATUS-}" \
        FAKE_OPEN_PRS_CLOSING="${FAKE_OPEN_PRS_CLOSING-}" \
        FAKE_DUPLICATE_PR_API_FAIL="${FAKE_DUPLICATE_PR_API_FAIL-}" \
        GH_ISSUE_BLOCK_LABELS="${GH_ISSUE_BLOCK_LABELS-}" \
        GH_ISSUE_SKIP_SELF_ASSIGN="${GH_ISSUE_SKIP_SELF_ASSIGN-}" \
        GH_ISSUE_SKIP_DUPLICATE_CHECK="${GH_ISSUE_SKIP_DUPLICATE_CHECK-}" \
        GH_ISSUE_SKIP_BOARD_TRANSITION="${GH_ISSUE_SKIP_BOARD_TRANSITION-}" \
        GH_ISSUE_SKIP_DEPS_CHECK="${GH_ISSUE_SKIP_DEPS_CHECK-}" \
        "$@" \
        sh "${REPO_ROOT}/lib/claim-issue.sh" "$_n" \
        --block-labels-default "$(_claim_block_default)" --duplicate-pr-guard 2>&1)
    CLAIM_RC=$?
    CLAIM_LOG=$(cat "$_t/gh.log")
    rm -rf "$_t"
}

# Env assignments that switch off every substep but the one under test.
_claim_only() {
    local _keep="$1" _v
    for _v in SELF_ASSIGN DUPLICATE_CHECK BOARD_TRANSITION DEPS_CHECK; do
        [ "$_v" = "$_keep" ] || printf 'GH_ISSUE_SKIP_%s=1\n' "$_v"
    done
}

# 3.2 Block-label guard. Prints the helper's refusal; returns its exit (2 = refused).
gh_issue_block_label_guard() {
    # shellcheck disable=SC2046  # one VAR=1 word per line, no spaces
    _claim_run "${1:-7}" $(_claim_only none)
    [ -z "$CLAIM_OUT" ] || printf '%s\n' "$CLAIM_OUT"
    return "$CLAIM_RC"
}

# 3.3 Self-assign. Echoes what the helper did:
#   skip       — never asked gh who "me" is (GH_ISSUE_SKIP_SELF_ASSIGN)
#   add        — ran `gh issue edit --add-assignee @me`
#   warn-other — warned that someone else holds it, did not override
#   noop-self  — already assigned to me, no write
gh_issue_self_assign_decide() {
    # shellcheck disable=SC2046
    _claim_run 7 $(_claim_only SELF_ASSIGN)
    case "$CLAIM_LOG" in *"api user"*) ;; *) printf 'skip'; return 0 ;; esac
    case "$CLAIM_LOG" in *"issue edit 7 --repo acme/widget --add-assignee @me"*) printf 'add'; return 0 ;; esac
    case "$CLAIM_OUT" in *"; not overriding."*) printf 'warn-other'; return 0 ;; esac
    printf 'noop-self'
}

# 3.3b Duplicate open-PR guard. Prints the helper's [WARN] line, or nothing.
gh_issue_duplicate_pr_guard() {
    # shellcheck disable=SC2046
    _claim_run "${1:-7}" $(_claim_only DUPLICATE_CHECK)
    [ -z "$CLAIM_OUT" ] || printf '%s\n' "$CLAIM_OUT"
    return "$CLAIM_RC"
}

# 3.4 Board Status transition. Prints the helper's output, then one tag:
#   skip                — the board helper was never called
#   no-board            — called, but no projectV2 is attached
#   already-in-progress — the helper warned that Status is past Backlog/Ready
#   synced              — the helper called _gh_project_status_sync quietly
gh_issue_board_transition_decide() {
    # shellcheck disable=SC2046
    _claim_run "${1:-7}" $(_claim_only BOARD_TRANSITION)
    [ -z "$CLAIM_OUT" ] || printf '%s\n' "$CLAIM_OUT"
    case "$CLAIM_LOG" in
        *no-board*) printf 'no-board' ;;
        *"sync issue"*)
            case "$CLAIM_OUT" in *"Status 가 이미"*) printf 'already-in-progress' ;; *) printf 'synced' ;; esac ;;
        *) printf 'skip' ;;
    esac
}

# 3.5 Depends-on guard. Prints the helper's [WARN] lines; always returns 0.
gh_issue_deps_guard() {
    # shellcheck disable=SC2046
    _claim_run "${1:-7}" $(_claim_only DEPS_CHECK)
    [ -z "$CLAIM_OUT" ] || printf '%s\n' "$CLAIM_OUT"
    return "$CLAIM_RC"
}
