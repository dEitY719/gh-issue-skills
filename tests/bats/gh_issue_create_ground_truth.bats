#!/usr/bin/env bats
load 'test_helper'

setup() { setup_isolated_home; body="$BATS_TEST_TMPDIR/body"; }
teardown() { teardown_isolated_home; }

@test "non-target internal host warns once across repeated URLs" {
    printf '%s\n' 'https://github.com/a https://internal.example/x http://internal.example/y' > "$body"
    run env TARGET_HOST=github.com bash "$REPO_ROOT/skills/issue-create/lib/draft-audit.sh" "$body"
    assert_success
    assert_output '[WARN] draft-audit: non-target host internal.example — 근거 확인'
}

@test "target-only and link-free drafts are silent" {
    printf '%s\n' '[link](https://github.com/a)' > "$body"
    run env TARGET_HOST=github.com bash "$REPO_ROOT/skills/issue-create/lib/draft-audit.sh" "$body"
    assert_success
    assert_output ''
    printf '%s\n' 'no links' > "$body"
    run env TARGET_HOST=github.com bash "$REPO_ROOT/skills/issue-create/lib/draft-audit.sh" "$body"
    assert_success
    assert_output ''
}

@test "ground truth remains a mandatory issue gate with discussion exception" {
    run grep -F 'references/ground-truth.md' "$REPO_ROOT/skills/issue-create/SKILL.md"
    assert_success
    run grep -F 'DISCUSSION_MODE=1' "$REPO_ROOT/skills/issue-create/references/ground-truth.md"
    assert_success
}
