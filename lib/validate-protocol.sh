#!/bin/sh
# lib/validate-protocol.sh — Step 2.2 schema validator for gh-issue:proceed.
#
# SSOT for the 8-required-section schema (spec: skills/proceed/references/protocol-schema.md).
# EXECUTE it, feeding the issue body on stdin — stdout/exit code are the
# whole product, mirroring lib/ai-metrics-footer.sh's contract:
#
#   bash "$PLUGIN_ROOT/lib/validate-protocol.sh" <<<"$BODY" || exit 1
#
# Exit 0: schema satisfied, nothing printed.
# Exit 1: the exact §4 failure block (protocol-schema.md) on stderr, ready
#         to print verbatim — no comment is posted on the issue (schema
#         failure is caller-side).
#
# ponytail: length() below is byte-based (POSIX awk), so a Korean section's
# character count is undercounted vs. its byte count — makes the 50-char
# "empty" gate slightly *harder* to trip on CJK content, never a false
# positive. Upgrade to a codepoint-aware count only if that direction ever
# matters in practice.
#
# Self-check: lib/validate-protocol.selfcheck.sh

set -u

BODY=$(cat)

RESULT=$(printf '%s\n' "$BODY" | awk '
BEGIN {
    n_keys = split("goal preconditions execution_protocol decision_rules deliverables done_criteria out_of_scope safety", order, " ")
    alias["goal"] = "goal|목표"
    alias["preconditions"] = "preconditions|사전 조건|prerequisites"
    alias["execution_protocol"] = "execution protocol|execution matrix|실행 절차|steps"
    alias["decision_rules"] = "decision rules|결정 규칙|branching|decision matrix"
    alias["deliverables"] = "deliverables|산출물|output|outputs"
    alias["done_criteria"] = "done criteria|종료 조건|acceptance criteria|acceptance"
    alias["out_of_scope"] = "out of scope|out-of-scope|범위 밖"
    alias["safety"] = "safety / abort|safety rules|안전 규칙|safety|abort"
}
{ lines[NR] = $0 }
END {
    total = NR
    hn = 0
    for (i = 1; i <= total; i++) {
        line = lines[i]
        if (match(line, /^#{2,3}[ \t]+/)) {
            hn++
            hidx[hn] = i
            match(line, /^#+/)
            hlvl[hn] = RLENGTH
            text = line
            sub(/^#{2,3}[ \t]+/, "", text)
            gsub(/[ \t]+$/, "", text)
            htext[hn] = tolower(text)
        }
    }

    for (k = 1; k <= n_keys; k++) {
        key = order[k]
        na = split(alias[key], al, "|")
        for (h = 1; h <= hn && found[key] == 0; h++) {
            if (assigned[h] != "") continue
            for (a = 1; a <= na; a++) {
                if (index(htext[h], al[a]) > 0) {
                    found[key] = h
                    assigned[h] = key
                    break
                }
            }
        }
    }

    for (k = 1; k <= n_keys; k++) {
        key = order[k]
        h = found[key]
        if (h == 0) { missing[key] = 1; continue }

        # A section content block runs to the next heading at the SAME OR
        # SHALLOWER level, not to any nested subheading -- a numbered-mode
        # execution_protocol legitimately uses "### 1. ..." step headings
        # nested one level under its own "## Execution Protocol" heading.
        startL = hidx[h] + 1
        endL = total
        for (hh = h + 1; hh <= hn; hh++) {
            if (hlvl[hh] <= hlvl[h]) { endL = hidx[hh] - 1; break }
        }

        strippedLen = 0
        hasChecklist = 0
        hasMatrix = 0
        hasNumbered = 0
        for (i = startL; i <= endL; i++) {
            l = lines[i]
            gsub(/^[ \t]+|[ \t]+$/, "", l)
            if (l ~ /^```/) continue
            if (l ~ /^-[ \t]+\[[ xX]\]/) hasChecklist = 1
            if (l ~ /^[0-9]+\./ || l ~ /^#{2,3}[ \t]+[0-9]+\./) hasNumbered = 1
            low = tolower(l)
            if (index(low, "|") > 0 && index(low, "#") > 0 && \
                (index(low, "workflow") > 0 || index(low, "step") > 0) && \
                (index(low, "command") > 0 || index(l, "명령") > 0)) hasMatrix = 1
            stripped = l
            sub(/^[-*][ \t]+/, "", stripped)
            sub(/^[0-9]+\.[ \t]+/, "", stripped)
            strippedLen += length(stripped)
        }

        if (key == "done_criteria") {
            if (!hasChecklist) empty[key] = 1
        } else if (strippedLen < 50) {
            empty[key] = 1
        } else if (key == "execution_protocol" && !hasMatrix && !hasNumbered) {
            unparseable[key] = 1
        }
    }

    out = ""
    for (k = 1; k <= n_keys; k++) if (missing[order[k]]) out = out "M:" order[k] " "
    for (k = 1; k <= n_keys; k++) if (empty[order[k]]) out = out "E:" order[k] " "
    for (k = 1; k <= n_keys; k++) if (unparseable[order[k]]) out = out "U:" order[k] " "
    print out
}
')

if [ -z "$(printf '%s' "$RESULT" | tr -d '[:space:]')" ]; then
    exit 0
fi

MISSING=""
EMPTY=""
UNPARSEABLE=""
for tok in $RESULT; do
    case $tok in
        M:*) MISSING="$MISSING\n    - ${tok#M:}" ;;
        E:done_criteria) EMPTY="$EMPTY\n    - done_criteria  (heading present, no - [ ] / - [x] checklist item)" ;;
        E:*) EMPTY="$EMPTY\n    - ${tok#E:}  (heading present, content < 50 chars)" ;;
        U:*) UNPARSEABLE="$UNPARSEABLE\n    - ${tok#U:}  (no matrix table and no numbered steps found)" ;;
    esac
done

{
    echo "gh-issue:proceed schema validation failed"
    if [ -n "$MISSING" ]; then
        echo "  Missing required sections:"
        printf '%b\n' "$MISSING"
    fi
    if [ -n "$EMPTY" ]; then
        echo "  Empty required sections:"
        printf '%b\n' "$EMPTY"
    fi
    if [ -n "$UNPARSEABLE" ]; then
        echo "  Unparseable sections:"
        printf '%b\n' "$UNPARSEABLE"
    fi
    echo "  Fix the issue body to satisfy the directive schema, then retry."
    echo "  Reference: skills/proceed/references/protocol-schema.md §3"
    echo "  Next: /gh-issue:read <N>"
} >&2

exit 1
