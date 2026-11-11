#!/usr/bin/env bats
# tests/bats/gh_issue_review_all.bats
# gh-issue:review-all (#70) against the shipped lib/review-lane.sh and
# lib/review-all.sh, running the VENDORED dotfiles engine
# (lib/vendor/shell-common/functions/gh_issue_review.sh, dEitY719/dotfiles#2381)
# with `gh` and the reviewer CLIs stubbed. No network, no real AI CLI.
#
#   lane: posted -> URL recorded; same material by this login -> skip(already
#         reviewed); changed body -> reviewed again; another login's marker ->
#         ignored; internal PC + github.com with no patterns -> skip(leak-guard)
#   driver: report line, a failing lane is a skip not a failure, the
#         throwaway tree is gone afterwards, CLOSED / unauthenticated -> exit 1
load 'test_helper'

setup() {
    setup_isolated_home
    STUB="$TEST_TEMP_HOME/bin"
    mkdir -p "$STUB"
    export GH_FIXTURE="$TEST_TEMP_HOME/issue.json" GH_LOG="$TEST_TEMP_HOME/gh.log"
    export POSTED="$TEST_TEMP_HOME/posted.md" GH_LOGIN=me GH_AUTH_RC=0
    export DOTFILES_ROOT="$TEST_TEMP_HOME/no-dotfiles" DOTFILES_SETUP_MODE=external LEAK_PATTERNS_ERE=""
    export SHELL_COMMON="$REPO_ROOT/lib/vendor/shell-common"
    export AI_REPLY='[FOLLOW-UP] 완료 기준 — 테스트 이름 없음
판정: 우려있음'
    write_fixture "Body text" ""
    cat >"$STUB/gh" <<'EOF'
#!/bin/bash
echo "GH_HOST=$GH_HOST $*" >>"$GH_LOG"
case "$1 $2" in
"auth status") exit "$GH_AUTH_RC" ;;
"issue view")
    q=""
    while [ "$#" -gt 0 ]; do [ "$1" = "--jq" ] && q="$2"; shift; done
    jq -r "$q" "$GH_FIXTURE" ;;
"api user") echo "$GH_LOGIN" ;;
"issue comment")
    while [ "$#" -gt 0 ]; do [ "$1" = "--body-file" ] && cp "$2" "$POSTED"; shift; done
    echo "https://github.com/o/r/issues/7#issuecomment-1" ;;
*) echo "unexpected gh call: $*" >&2; exit 9 ;;
esac
EOF
    cat >"$STUB/codex" <<'EOF'
#!/bin/sh
pwd -P >"$GH_LOG.cwd"
cat >/dev/null
printf '%s\n' "$AI_REPLY"
EOF
    cat >"$STUB/hermes" <<'EOF'
#!/bin/sh
echo "Error: rate limit exceeded for this subscription" >&2
exit 1
EOF
    chmod +x "$STUB/gh" "$STUB/codex" "$STUB/hermes"
    export PATH="$STUB:$PATH"
    REPO="$TEST_TEMP_HOME/repo"
    git init -q -b feature "$REPO"
    git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
    git -C "$REPO" remote add origin https://github.com/o/r.git
}

teardown() {
    teardown_isolated_home
}

# write_fixture <body> <marker-comment-json-or-empty> [state]
write_fixture() {
    local extra=""
    [ -z "$2" ] || extra=",$2"
    cat >"$GH_FIXTURE" <<EOF
{"title":"feat(x): add y","state":"${3:-OPEN}","body":"$1","comments":[
 {"author":{"login":"alice"},"createdAt":"2026-01-01T00:00:00Z","body":"human comment"}$extra]}
EOF
}

# The engine's material hash: title, body and the non-marker comments.
material_hash() {
    local c
    c=$(jq -r '.comments[] | select(.body | contains("<!-- ai-issue-review:") | not) | "--- comment by @\(.author.login) at \(.createdAt) ---\n\(.body)\n"' "$GH_FIXTURE")
    printf '%s\n%s\n%s' "$(jq -r .title "$GH_FIXTURE")" "$(jq -r .body "$GH_FIXTURE")" "$c" | sha256sum | cut -c1-12
}

lane() { # lane <ai>
    URLS="$TEST_TEMP_HOME/urls"
    mkdir -p "$URLS"
    run bash "$REPO_ROOT/lib/review-lane.sh" "$URLS" o/r github.com "$REPO" 7 "$1"
}

@test "lane: a review is posted and its comment URL recorded" {
    lane codex
    assert_success
    assert_equal "$(cat "$URLS/codex")" "https://github.com/o/r/issues/7#issuecomment-1"
    grep -qF "<!-- ai-issue-review:codex:$(material_hash) -->" "$POSTED"
    grep -qF '판정: 우려있음' "$POSTED"
}

@test "lane: same material already reviewed by this login -> skip(already reviewed)" {
    write_fixture "Body text" ""
    h=$(material_hash)
    write_fixture "Body text" "{\"author\":{\"login\":\"me\"},\"createdAt\":\"2026-01-02T00:00:00Z\",\"body\":\"<!-- ai-issue-review:codex:$h -->\"}"
    lane codex
    assert_failure 4
    assert_output "already reviewed"
    [ ! -e "$POSTED" ]
}

@test "lane: body changed since the last review -> reviewed again" {
    write_fixture "Old body" ""
    h=$(material_hash)
    write_fixture "New body" "{\"author\":{\"login\":\"me\"},\"createdAt\":\"2026-01-02T00:00:00Z\",\"body\":\"<!-- ai-issue-review:codex:$h -->\"}"
    lane codex
    assert_success
    [ -s "$POSTED" ]
}

@test "lane: a marker posted by another account is ignored" {
    write_fixture "Body text" ""
    h=$(material_hash)
    write_fixture "Body text" "{\"author\":{\"login\":\"mallory\"},\"createdAt\":\"2026-01-02T00:00:00Z\",\"body\":\"<!-- ai-issue-review:codex:$h -->\"}"
    lane codex
    assert_success
    [ -s "$POSTED" ]
}

@test "lane: internal PC + github.com with no leak patterns -> skip(leak-guard), nothing posted" {
    DOTFILES_SETUP_MODE=internal lane codex
    assert_failure 3
    assert_output "leak-guard"
    [ ! -e "$POSTED" ]
}

@test "lane: a failing CLI reports its own first stderr line" {
    lane hermes
    assert_failure
    assert_output --partial "rate limit exceeded"
}

@test "driver: one report line, a failed lane is a skip, the tree is removed" {
    export TMPDIR="$TEST_TEMP_HOME/tmp"
    mkdir -p "$TMPDIR"
    cd "$REPO"
    run bash "$REPO_ROOT/lib/review-all.sh" 7 --lanes codex,hermes
    assert_success
    assert_line --index 0 --regexp '^issue-review #7: codex:ok hermes:skip\(.*rate limit exceeded.*\)$'
    assert_line --regexp '^  base: feature@[0-9a-f]+ \(head\)$'
    assert_line "  codex: https://github.com/o/r/issues/7#issuecomment-1"
    # The CLI ran in the throwaway tree, never in the user's tree.
    case "$(cat "$GH_LOG.cwd")" in "$(cd -P "$TMPDIR" && pwd)"/gh-issue-review-tree.*) ;; *) false ;; esac
    [ -z "$(find "$TMPDIR" -maxdepth 1 -name 'gh-issue-review-tree.*')" ]
    [ "$(git -C "$REPO" worktree list | wc -l)" -eq 1 ]
    grep -q '^GH_HOST=github.com issue comment 7 --repo o/r ' "$GH_LOG"
    # The snapshot keeps the source branch name, so the comment names it.
    grep -qF '리뷰 기준: `feature@' "$POSTED"
}

@test "driver: a CLOSED issue is refused with exit 1 before any lane runs" {
    write_fixture "Body text" "" CLOSED
    cd "$REPO"
    run bash "$REPO_ROOT/lib/review-all.sh" 7 --lanes codex
    assert_failure 1
    assert_output --partial "is CLOSED"
    [ ! -e "$GH_LOG.cwd" ]
}

@test "driver: gh not logged in to the host -> exit 1" {
    export GH_AUTH_RC=1
    cd "$REPO"
    run bash "$REPO_ROOT/lib/review-all.sh" 7 --lanes codex
    assert_failure 1
    assert_output --partial "not logged in to github.com"
}

@test "driver: a PR URL is refused with exit 2" {
    cd "$REPO"
    run bash "$REPO_ROOT/lib/review-all.sh" https://github.com/o/r/pull/7
    assert_failure 2
    assert_output --partial "gh-verify:review-all"
}
