#!/bin/sh
# lib/ai-metrics-footer.sh — emit the ai-metrics footer for an Issue/PR body.
#
# SSOT for the footer's exact bytes. EXECUTE it, never source it — stdout is
# the whole product:
#
#   bash "${CLAUDE_PLUGIN_ROOT:-.}/lib/ai-metrics-footer.sh" \
#       "$TOKENS" "$HUMAN_H" "$ELAPSED" gh-issue-create >> "$BODY"
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

marker=${4:+:$4}

printf '\n---\n<details>\n<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min</summary>\n\n<!-- ai-metrics%s -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics%s -->\n\n</details>\n' \
    "$1" "$2" "$3" "$marker" "$1" "$2" "$3" "$marker"
