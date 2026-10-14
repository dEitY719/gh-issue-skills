#!/usr/bin/env bash
# tests/bats/fixtures/gh_issue_create_dependency_detect.sh
# Step 2.6 detection + Step 4.5 link outcome of gh-issue:issue-create.
#
# Detection (text -> issue numbers) has no shipped shell: it is prose in
# skills/issue-create/references/dependency-detect.md, so it is MIRRORED
# here and the suite's drift guards grep that doc for the lines this mirror
# relies on. If a trigger phrase is added or removed there, mirror it here.
#
# Linking is NOT mirrored: gh_issue_create_dep_link_outcome runs the shipped
# lib/link-deps.sh against a stub `gh` on PATH, so the suite exercises the
# real NF-1 classification. The fixture never touches the network.

# An issue reference, with the cross-repo `owner/repo` prefix optional so
# NF-2 can detect and reject it rather than silently mis-linking it to a
# same-numbered issue in $TARGET_REPO.
_GH_DEPS_REF='([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)?#[0-9]+'

# The F-1 trigger set. Korean forms trail the reference ("#13 완료 후"),
# English forms lead it ("depends on #13"). Plain mentions ("#13 참고",
# "#13 관련", a bare "#13") match nothing by construction.
#
# The 완료/해결 branch enumerates the conjugations that actually show up in
# chat (완료 후 / 완료되면 / 완료하고 / 해결 후 / …) instead of a looser
# "#N .* 후" — the reference and the trigger word must stay adjacent, or
# "#13 참고. 검토 후 진행" would link #13 to an unrelated clause.
# The colon after 선행 이슈 is optional so "선행이슈 #13" also matches.
_GH_DEPS_TRIGGERS="\
${_GH_DEPS_REF}[[:space:]]*(완료|해결)[[:space:]]*(후|뒤|되면|하고|하면)|\
${_GH_DEPS_REF}[[:space:]]*이후|\
depends[[:space:]]+on[[:space:]]+${_GH_DEPS_REF}|\
blocked[[:space:]]+by[[:space:]]+${_GH_DEPS_REF}|\
선행[[:space:]]*이슈[[:space:]]*[:：]?[[:space:]]*${_GH_DEPS_REF}"

# gh_issue_create_detect_deps
#   $1 — conversation text to scan
#   $2 — "1" if --no-auto-deps, "0" otherwise (default "0")
#
# Stdout: same-repo issue numbers, ascending and de-duped, one per line.
# Stderr: one `dependency-detect: cross-repo ...` line per NF-2 skip.
# Returns: 0 always — detection never blocks issue creation (NF-1).
gh_issue_create_detect_deps() {
    _text="$1"
    _no_auto="${2:-0}"

    # F-3: the escape hatch skips detection itself, not just the linking.
    if [ "$_no_auto" = "1" ]; then
        return 0
    fi

    # Two greps, never one per match: the first anchors a reference to a
    # trigger phrase (that anchoring is the whole false-positive defence),
    # the second pulls the reference back out. Every trigger alternative
    # embeds exactly one reference, so the two streams stay 1:1 and each
    # surviving line is either a same-repo number or an NF-2 cross-repo skip.
    # The trailing `|| true` is load-bearing, not defensive noise: "no
    # trigger in this conversation" is the common case and makes grep exit
    # 1, which under a caller's `set -e` + `set -o pipefail` would abort
    # before `return 0` and take the whole issue creation down with it.
    printf '%s\n' "$_text" |
        grep -oiE "$_GH_DEPS_TRIGGERS" |
        grep -oE "$_GH_DEPS_REF" |
        while IFS= read -r _ref; do
            case "$_ref" in
                */*)
                    printf 'dependency-detect: cross-repo dependency detected but not supported in v1 — skip (%s)\n' \
                        "$_ref" >&2
                    ;;
                *)
                    printf '%s\n' "${_ref#\#}"
                    ;;
            esac
        done | sort -n -u || true
    return 0
}

# gh_issue_create_dep_link_outcome
#   $1 — new issue node id the lookup returns ("" = null / failed lookup)
#   $2 — dep  issue node id the lookup returns ("" = null / failed lookup)
#   $3 — addBlockedBy exit status ("0" = applied); never reached when an id
#        is empty
#   $4 — dep issue number
#   $5 — stderr the failing call prints ("" when it says nothing)
#
# Runs the real lib/link-deps.sh with a stub `gh` that answers from $1-$3/$5.
# link-deps.sh prints its warnings on stdout (the caller stacks them into
# $DEP_WARNINGS); they are moved to stderr here, the channel Step 2.6/4.5
# surface them on.
# Returns: link-deps.sh's exit status, which is 0 always (NF-1).
gh_issue_create_dep_link_outcome() {
    _stub=$(mktemp -d) || return 1
    cat >"$_stub/gh" <<'GH'
#!/bin/sh
case "$*" in
    *addBlockedBy*)
        [ -z "$STUB_ERR" ] || printf '%s\n' "$STUB_ERR" >&2
        exit "$STUB_MUT_RC" ;;
esac
if [ -z "$STUB_NEW_ID" ] || [ -z "$STUB_DEP_ID" ]; then
    [ -z "$STUB_ERR" ] || printf '%s\n' "$STUB_ERR" >&2
fi
printf '%s %s\n' "$STUB_NEW_ID" "$STUB_DEP_ID"
GH
    chmod +x "$_stub/gh"
    STUB_NEW_ID="$1" STUB_DEP_ID="$2" STUB_MUT_RC="$3" STUB_ERR="$5" \
        GH_HOST=github.com TARGET_REPO=acme/widget TARGET_HOST='' \
        PATH="$_stub:$PATH" bash "${REPO_ROOT}/lib/link-deps.sh" 1 "$4" >&2
    _rc=$?
    rm -rf "$_stub"
    return "$_rc"
}
