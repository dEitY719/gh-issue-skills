#!/bin/sh
# lib/validate-protocol.sh — Step 2.2 schema validator for gh-issue:proceed.
#
# SSOT for the 8-required-section schema (spec: skills/proceed/references/protocol-schema.md).
# EXECUTE it, feeding the issue body on stdin — stdout/exit code are the
# whole product, mirroring lib/ai-metrics-footer.sh's contract:
#
#   bash "$PLUGIN_ROOT/lib/validate-protocol.sh" "$N" <<<"$BODY" || exit 1
#
# $1 (optional): issue number, for the failure block's "#<N>" line and its
# Next: hint. Omit it (or pass nothing) and both print the literal "<N>".
#
# Exit 0: schema satisfied, nothing printed.
# Exit 1: the exact §4 failure block (protocol-schema.md) on stderr, ready
#         to print verbatim — no comment is posted on the issue (schema
#         failure is caller-side).
#
# Always invoked via `bash`, never executed directly off its own shebang —
# same convention as lib/ai-metrics-footer.sh (also #!/bin/sh, also called
# as `bash "$PLUGIN_ROOT/lib/....sh"` in every SKILL.md that uses it).
#
# ponytail: length() below is byte-based (POSIX awk), so a Korean section's
# character count is undercounted vs. its byte count — makes the 50-char
# "empty" gate slightly *harder* to trip on CJK content, never a false
# positive. Upgrade to a codepoint-aware count only if that direction ever
# matters in practice.
#
# Self-check: lib/validate-protocol.selfcheck.sh

set -u

N=${1:-<N>}

BODY_MSG=$(awk '
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

    # A bare single-word alias ("steps", "output", "abort", ...) must equal
    # the WHOLE heading, not just appear inside it -- otherwise a heading
    # like "## Next Steps" or "## Output Formats" (neither a required
    # section) would false-positive-claim execution_protocol/deliverables.
    # A multi-word alias ("execution protocol", "decision matrix", ...) is
    # specific enough to keep substring matching, per protocol-schema.md.
    for (k = 1; k <= n_keys; k++) {
        key = order[k]
        na = split(alias[key], al, "|")
        for (h = 1; h <= hn && found[key] == 0; h++) {
            if (assigned[h] != "") continue
            for (a = 1; a <= na; a++) {
                is_multi_word = (index(al[a], " ") > 0)
                hit = is_multi_word ? (index(htext[h], al[a]) > 0) : (htext[h] == al[a])
                if (hit) {
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
        hasHeaderRow = 0
        pipeRows = 0
        sepRows = 0
        hasNumbered = 0
        for (i = startL; i <= endL; i++) {
            l = lines[i]
            gsub(/^[ \t]+|[ \t]+$/, "", l)
            if (l ~ /^```/) continue
            if (l ~ /^-[ \t]+\[[ xX]\]/) hasChecklist = 1
            if (l ~ /^[0-9]+\./ || l ~ /^#{2,3}[ \t]+[0-9]+\./) hasNumbered = 1
            low = tolower(l)
            if (index(low, "|") > 0) {
                pipeRows++
                if (l ~ /^[|:>< -]+$/) sepRows++  # the "|---|---|" divider row
                if (index(low, "#") > 0 && \
                    (index(low, "workflow") > 0 || index(low, "step") > 0) && \
                    (index(low, "command") > 0 || index(low, "명령") > 0)) hasHeaderRow = 1
            }
            stripped = l
            sub(/^[-*][ \t]+/, "", stripped)
            sub(/^[0-9]+\.[ \t]+/, "", stripped)
            strippedLen += length(stripped)
        }
        # header row + divider row + at least one real data row.
        hasMatrix = hasHeaderRow && (pipeRows - sepRows - 1 >= 1)

        if (key == "done_criteria") {
            if (!hasChecklist) empty[key] = 1
        } else if (strippedLen < 50) {
            empty[key] = 1
        } else if (key == "execution_protocol" && !hasMatrix && !hasNumbered) {
            unparseable[key] = 1
        }
    }

    mtxt = ""; etxt = ""; utxt = ""
    for (k = 1; k <= n_keys; k++) {
        key = order[k]
        if (missing[key]) {
            tried = alias[key]
            gsub(/\|/, ", ", tried)
            mtxt = mtxt "    - " key "  (aliases tried: " tried ")\n"
        }
        if (empty[key]) {
            if (key == "done_criteria")
                etxt = etxt "    - done_criteria  (heading present, no - [ ] / - [x] checklist item)\n"
            else
                etxt = etxt "    - " key "  (heading present, content < 50 chars)\n"
        }
        if (unparseable[key])
            utxt = utxt "    - " key "  (no matrix table and no numbered steps found)\n"
    }

    if (mtxt != "" || etxt != "" || utxt != "") {
        body = ""
        if (mtxt != "") body = body "  Missing required sections:\n" mtxt
        if (etxt != "") body = body "  Empty required sections:\n" etxt
        if (utxt != "") body = body "  Unparseable sections:\n" utxt
        printf "%s", body
    }
}
')

if [ -z "$BODY_MSG" ]; then
    exit 0
fi

{
    echo "gh-issue:proceed #$N schema validation failed"
    printf '%s\n' "$BODY_MSG"
    echo "  Fix the issue body to satisfy the directive schema, then retry."
    echo "  Reference: skills/proceed/references/protocol-schema.md §3"
    echo "  Next: /gh-issue:read $N"
} >&2

exit 1
