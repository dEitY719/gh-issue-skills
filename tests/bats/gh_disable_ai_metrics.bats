#!/usr/bin/env bats
# tests/bats/gh_disable_ai_metrics.bats
# GH_DISABLE_AI_METRICS (dEitY719/dotfiles#399): the shipped
# lib/ai-metrics-footer.sh prints nothing for the literal value "1" and the
# footer for anything else — unset, empty, 0, 2, true. Guards against drift
# to a truthy coercion that would opt unrelated values into skip.

load 'test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

footer() {
    bash "${REPO_ROOT}/lib/ai-metrics-footer.sh" 1000 1 5 test
}

@test "behaviour: env unset -> footer printed" {
    unset GH_DISABLE_AI_METRICS
    run footer
    assert_success
    assert_output --partial '<!-- ai-metrics:test -->'
}

@test "behaviour: env empty -> footer printed (treated as unset)" {
    GH_DISABLE_AI_METRICS="" run footer
    assert_success
    assert_output --partial '<!-- ai-metrics:test -->'
}

@test "behaviour: env=0 -> footer printed" {
    GH_DISABLE_AI_METRICS=0 run footer
    assert_success
    assert_output --partial '<!-- ai-metrics:test -->'
}

@test "behaviour: env=1 -> nothing printed, exit 0" {
    GH_DISABLE_AI_METRICS=1 run footer
    assert_success
    assert_output ''
}

@test "behaviour: env=2 -> footer printed (only literal '1' opts out)" {
    GH_DISABLE_AI_METRICS=2 run footer
    assert_success
    assert_output --partial '<!-- ai-metrics:test -->'
}

@test "behaviour: env=true -> footer printed (only literal '1' opts out)" {
    GH_DISABLE_AI_METRICS=true run footer
    assert_success
    assert_output --partial '<!-- ai-metrics:test -->'
}
