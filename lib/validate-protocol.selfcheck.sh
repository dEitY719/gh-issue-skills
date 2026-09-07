#!/usr/bin/env bash
# Self-check for lib/validate-protocol.sh. No framework, no fixtures dir:
#
#   bash lib/validate-protocol.selfcheck.sh
#
# Builds each fixture body inline and checks only exit status plus which
# section the failure block names. Exits non-zero on the first regression.
set -u

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
TARGET="$ROOT/lib/validate-protocol.sh"
FAIL=0

chk() { # chk <label> <got> <want>
    if [ "$2" = "$3" ]; then
        echo "ok    $1"
    else
        echo "FAIL  $1: got '$2' want '$3'"
        FAIL=1
    fi
}

VALID_BODY='## Goal
This is a sufficiently long goal description that exceeds fifty characters easily for testing.

## Preconditions
This is a sufficiently long preconditions text that exceeds fifty characters for the check.

## Execution Protocol
### 1. Do the first thing
Run some command that does something useful here.

### 2. Do the second thing
Run another command that does something else here.

## Decision Rules
This is a sufficiently long decision rules text that exceeds fifty characters easily.

## Deliverables
This is a sufficiently long deliverables text that exceeds fifty characters easily.

## Done Criteria
- [ ] First criterion met
- [ ] Second criterion met

## Out of Scope
This is a sufficiently long out of scope text that exceeds fifty characters easily.

## Safety
This is a sufficiently long safety text that exceeds fifty characters easily.'

# 1. A fully valid body passes with no output and exit 0.
out=$(printf '%s' "$VALID_BODY" | bash "$TARGET" 2>&1)
rc=$?
chk "valid body: exit code" "$rc" "0"
chk "valid body: no output" "$out" ""

# 2. A matrix-mode execution_protocol also satisfies the schema.
matrix_body="## Goal
This is a sufficiently long goal description that exceeds fifty characters easily for testing.

## Preconditions
This is a sufficiently long preconditions text that exceeds fifty characters for the check.

## Execution Matrix
| # | Workflow | Command | Expected |
|---|---|---|---|
| 1 | stock list | stock list 1 10 | pass |

## Decision Rules
This is a sufficiently long decision rules text that exceeds fifty characters easily.

## Deliverables
This is a sufficiently long deliverables text that exceeds fifty characters easily.

## Done Criteria
- [ ] First criterion met

## Out of Scope
This is a sufficiently long out of scope text that exceeds fifty characters easily.

## Safety
This is a sufficiently long safety text that exceeds fifty characters easily."
rc=$(printf '%s' "$matrix_body" | bash "$TARGET" >/dev/null 2>&1; echo $?)
chk "matrix-mode execution_protocol passes" "$rc" "0"

# 3. Missing a required section (goal) fails and names it.
missing=$(printf '%s' "$VALID_BODY" | sed '/^## Goal$/,/^## Preconditions$/{/^## Preconditions$/!d}')
out=$(printf '%s' "$missing" | bash "$TARGET" 2>&1)
rc=$?
chk "missing goal: exit code" "$rc" "1"
case $out in
    *"Missing required sections:"*"- goal"*) got=match ;;
    *) got="no-match: $out" ;;
esac
chk "missing goal: names it" "$got" "match"

# 4. A required section present but under 50 chars fails as empty.
empty=$(printf '%s' "$VALID_BODY" | sed 's/^This is a sufficiently long preconditions.*/short/')
out=$(printf '%s' "$empty" | bash "$TARGET" 2>&1)
rc=$?
chk "empty preconditions: exit code" "$rc" "1"
case $out in
    *"Empty required sections:"*"- preconditions"*) got=match ;;
    *) got="no-match: $out" ;;
esac
chk "empty preconditions: names it" "$got" "match"

# 5. execution_protocol present and non-empty, but neither a matrix table
#    nor numbered steps -> unparseable, not empty.
prose_ep="## Goal
This is a sufficiently long goal description that exceeds fifty characters easily for testing.

## Preconditions
This is a sufficiently long preconditions text that exceeds fifty characters for the check.

## Execution Protocol
This is just prose describing the protocol at length without any table or any numbered list markers at all here, still long enough to clear the 50-char empty gate on its own.

## Decision Rules
This is a sufficiently long decision rules text that exceeds fifty characters easily.

## Deliverables
This is a sufficiently long deliverables text that exceeds fifty characters easily.

## Done Criteria
- [ ] First criterion met

## Out of Scope
This is a sufficiently long out of scope text that exceeds fifty characters easily.

## Safety
This is a sufficiently long safety text that exceeds fifty characters easily."
out=$(printf '%s' "$prose_ep" | bash "$TARGET" 2>&1)
rc=$?
chk "unparseable execution_protocol: exit code" "$rc" "1"
case $out in
    *"Unparseable sections:"*"- execution_protocol"*) got=match ;;
    *) got="no-match: $out" ;;
esac
chk "unparseable execution_protocol: names it" "$got" "match"

# 6. done_criteria present and long enough, but with no checklist item.
no_checklist=$(printf '%s' "$VALID_BODY" | sed \
    -e 's/^- \[ \] First criterion met$/Just prose here, no checklist markers present at all in this section./' \
    -e '/^- \[ \] Second criterion met$/d')
out=$(printf '%s' "$no_checklist" | bash "$TARGET" 2>&1)
rc=$?
chk "done_criteria without checklist: exit code" "$rc" "1"
case $out in
    *"Empty required sections:"*"- done_criteria"*"checklist item"*) got=match ;;
    *) got="no-match: $out" ;;
esac
chk "done_criteria without checklist: names it" "$got" "match"

# 7. Numbered steps nested as "### N." headings under "## Execution
#    Protocol" must not truncate that section's content at the first
#    numbered sub-heading (regression guard for the heading-nesting fix).
rc=$(printf '%s' "$VALID_BODY" | bash "$TARGET" >/dev/null 2>&1; echo $?)
chk "numbered ### sub-steps do not truncate the section" "$rc" "0"

# 8. A matrix header row with no data rows is unparseable, not valid
#    (codex review BLOCKER on PR #23: a header-only table let a malformed
#    directive through).
header_only=$(printf '%s' "$matrix_body" | sed '/^| 1 | stock list | stock list 1 10 | pass |$/d')
rc=$(printf '%s' "$header_only" | bash "$TARGET" >/dev/null 2>&1; echo $?)
chk "matrix header with no data rows fails" "$rc" "1"

# 9. A single-word alias ("steps") must match the WHOLE heading, not just
#    appear inside an unrelated one -- otherwise "## Next Steps" would
#    hijack execution_protocol before the real "## Execution Protocol"
#    heading is ever seen (agy review BLOCKER on PR #23).
hijack_attempt=$(printf '%s' "$VALID_BODY" | sed '/^## Execution Protocol$/i\
## Next Steps\
Unrelated notes that happen to contain the word steps in the heading.\
')
rc=$(printf '%s' "$hijack_attempt" | bash "$TARGET" >/dev/null 2>&1; echo $?)
chk "ambiguous 'Next Steps' heading does not hijack execution_protocol" "$rc" "0"

# 10. The failure block carries the issue number passed as $1, and a
#     missing section's message names the aliases that were tried
#     (codex review BLOCKER on PR #23: the block dropped both).
out=$(printf '%s' "$missing" | bash "$TARGET" 99 2>&1)
case $out in
    "gh-issue:proceed #99 schema validation failed"*) got=match ;;
    *) got="no-match: $out" ;;
esac
chk "failure block carries the passed issue number" "$got" "match"
case $out in
    *"- goal  (aliases tried: goal, 목표)"*) got=match ;;
    *) got="no-match: $out" ;;
esac
chk "failure block names the aliases tried" "$got" "match"

[ "$FAIL" = "0" ] && echo "All checks passed." || echo "SOME CHECKS FAILED."
exit "$FAIL"
