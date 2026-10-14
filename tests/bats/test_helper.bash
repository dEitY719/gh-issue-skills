#!/usr/bin/env bash
# tests/bats/test_helper.bash — shared by every tests/bats/*.bats.
# Needs bats-support + bats-assert on BATS_LIB_PATH (see CLAUDE.md "Tests").

bats_load_library bats-support
bats_load_library bats-assert

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

# Temp HOME/XDG so nothing a test runs can reach the developer's real config.
setup_isolated_home() {
    TEST_TEMP_HOME="$(mktemp -d)"
    export HOME="$TEST_TEMP_HOME"
    unset CLAUDE_CONFIG_DIR
    export XDG_CONFIG_HOME="$TEST_TEMP_HOME"
    export XDG_CACHE_HOME="$TEST_TEMP_HOME"
    export XDG_DATA_HOME="$TEST_TEMP_HOME"
    export TERM=dumb
}

teardown_isolated_home() {
    if [ -n "${TEST_TEMP_HOME:-}" ] && [ -d "$TEST_TEMP_HOME" ]; then
        rm -rf "$TEST_TEMP_HOME"
    fi
}
