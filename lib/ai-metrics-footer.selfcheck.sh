#!/usr/bin/env bash
# Self-check for lib/ai-metrics-footer.sh. No framework, no fixtures:
#
#   bash lib/ai-metrics-footer.selfcheck.sh
#
# The footer is machine-parsed by `gh-setup:add-ai-metrics`, so the assertions
# below are about exact bytes, not about the block "looking right".
set -u

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
TARGET="$ROOT/lib/ai-metrics-footer.sh"
FAIL=0

chk() { # chk <label> <got> <want>
    if [ "$2" = "$3" ]; then
        echo "ok    $1"
    else
        echo "FAIL  $1: got '$2' want '$3'"
        FAIL=1
    fi
}

# 1. Bare form: no marker argument -> `<!-- ai-metrics -->`.
got=$(bash "$TARGET" 5000 4 12 | sed -n '6p;8p')
chk "bare marker pair" "$got" "<!-- ai-metrics -->
<!-- /ai-metrics -->"

# 2. Named form: the suffix lands on both markers.
got=$(bash "$TARGET" 5000 4 12 gh-issue-create | sed -n '6p;8p')
chk "named marker pair" "$got" "<!-- ai-metrics:gh-issue-create -->
<!-- /ai-metrics:gh-issue-create -->"

# 3. Full block shape: leading blank line, rule, collapsed <details>.
got=$(bash "$TARGET" 5000 4 12 | sed -n '1p;2p;3p;10p')
chk "block skeleton" "$got" "
---
<details>
</details>"

# 4. The three values reach both the summary and the body line.
got=$(bash "$TARGET" 5000 4 12 | grep -c '~5000 tokens')
chk "values on summary and body" "$got" "2"

# 5. GH_DISABLE_AI_METRICS=1 prints nothing and still succeeds, so callers can
#    append unconditionally.
got=$(GH_DISABLE_AI_METRICS=1 bash "$TARGET" 5000 4 12 gh-issue-create; printf '|%s' "$?")
chk "GH_DISABLE_AI_METRICS silences it" "$got" "|0"

# 6. Missing arguments fail loudly rather than emitting a half-filled footer.
bash "$TARGET" 5000 4 >/dev/null 2>&1
chk "too few args returns non-zero" "$?" "1"

# 7. `metrics-helper.md` shows the shape callers copy from, and it is the one
#    other file `allow-emoji-paths` still lets carry these glyphs. Slice its
#    block out of the shipped doc instead of retyping it, so a drift between
#    the doc and this script fails here rather than hiding (same trick as
#    lib/plugin-root.selfcheck.sh's `extract`). The placeholders are just
#    strings, so they can be passed straight in as the three values.
doc=$(awk '/^### GitHub Issue \/ PR body footer$/ { on = 1 }
           on && /^```$/ { n++; if (n == 1) next; exit }
           on && n == 1' \
    "$ROOT/skills/create/references/metrics-helper.md")
chk "metrics-helper.md block matches the script" \
    "$doc" "$(bash "$TARGET" '{TOKENS}' '{HUMAN_H}' '{ELAPSED}' '<skill>' | sed '1d')"

# 7b. A marker that would break the machine-parsed block is refused rather
#     than emitted: both halves of the pair live on their own comment line.
bash "$TARGET" 5000 4 12 "$(printf 'a\nb')" >/dev/null 2>&1
chk "newline in marker returns non-zero" "$?" "1"
bash "$TARGET" 5000 4 12 'x --> y <!--' >/dev/null 2>&1
chk "comment terminator in marker returns non-zero" "$?" "1"

# 8. POSIX sh, so the five non-Claude harnesses can run it too.
if command -v dash >/dev/null 2>&1; then
    got=$(dash "$TARGET" 5000 4 12 | sed -n '6p')
    chk "runs under dash" "$got" "<!-- ai-metrics -->"
else
    echo "skip  dash not installed"
fi

exit "$FAIL"
