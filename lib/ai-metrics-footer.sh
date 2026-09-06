#!/bin/sh
# lib/ai-metrics-footer.sh — emit the ai-metrics footer for an Issue/PR body.
#
# SSOT for the footer's exact bytes. EXECUTE it, never source it — stdout is
# the whole product:
#
#   bash "$PLUGIN_ROOT/lib/ai-metrics-footer.sh" \
#       "$TOKENS" "$HUMAN_H" "$ELAPSED" gh-issue-create >> "$BODY"
#
# $PLUGIN_ROOT is exported by lib/resolve-target.sh in every skill's Step 1 —
# a proven root, never `${CLAUDE_PLUGIN_ROOT:-.}`, whose $PWD tier is the repo
# under review (dEitY719/harness-skills#22).
#
# Reads  $1 tokens, $2 human hours, $3 elapsed minutes, $4 optional marker
#        suffix — `gh-issue-create` yields `<!-- ai-metrics:gh-issue-create -->`,
#        omitted yields the bare `<!-- ai-metrics -->` form.
# Env    GH_DISABLE_AI_METRICS=1 — print nothing and exit 0, so no caller needs
#        its own `if` around the append.
#
# Why a script and not a pasted printf (dEitY719/gh-issue-skills#3): the
# `<details>` wrapper and the `<!-- ai-metrics -->` markers are machine-parsed
# by `gh-setup:add-ai-metrics`, so every writer has to emit byte-identical
# output. Six pasted copies could not, and had already started to drift.
#
# The chart / person / robot glyphs below are the footer's wire format, not
# decoration — the one emoji exception this repo grants (see validate.yml).
#
# Self-check: lib/ai-metrics-footer.selfcheck.sh

set -u

if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    exit 0
fi

if [ "$#" -lt 3 ]; then
    echo "usage: ai-metrics-footer.sh <tokens> <human_h> <elapsed_min> [marker]" >&2
    exit 1
fi

# The suffix lands inside an HTML comment on a line of its own, and
# `gh-setup:add-ai-metrics` parses those lines. A newline or an embedded
# comment terminator would break that format, so refuse both rather than
# emit a corrupt block (PR dEitY719/gh-issue-skills#18, codex FOLLOW-UP).
case ${4:-} in
    *"
"* | *"-->"*)
        echo "ai-metrics-footer.sh: marker must not contain a newline or '-->'" >&2
        exit 1 ;;
esac

marker=${4:+:$4}

printf '\n---\n<details>\n<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min</summary>\n\n<!-- ai-metrics%s -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics%s -->\n\n</details>\n' \
    "$1" "$2" "$3" "$marker" "$1" "$2" "$3" "$marker"
