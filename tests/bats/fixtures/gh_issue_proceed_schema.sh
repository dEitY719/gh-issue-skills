#!/usr/bin/env bash
# tests/bats/fixtures/gh_issue_proceed_schema.sh
# Runs the shipped lib/validate-protocol.sh — the 8-section schema validator
# specified in skills/proceed/references/protocol-schema.md — on FAKE_BODY.
#
# Inputs:
#   FAKE_BODY — the GitHub directive issue body (markdown)

# gh_proceed_validate_schema [N]
# Exit 0 and no output when the schema is satisfied; exit 1 with the
# helper's failure block (stderr, folded into stdout here) otherwise.
gh_proceed_validate_schema() {
    printf '%s\n' "${FAKE_BODY-}" | bash "${REPO_ROOT}/lib/validate-protocol.sh" "${1:-}" 2>&1
}
