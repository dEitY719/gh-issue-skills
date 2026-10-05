#!/usr/bin/env bash
# Drift guard for the per-skill copies of lib/ (dEitY719/gh-issue-skills#47).
#
# A Hermes tap or `npx skills add` installs ONE skill directory, so every
# helper a skill executes ships inside it as skills/<name>/lib/<file>. The
# SSOT stays at the repo root (lib/, where the *.selfcheck.sh files test it);
# the copies must never diverge from it.
#
#   bash tests/vendored-lib-sync.sh
#
# 1. Every file under skills/*/lib/ is byte-identical to lib/<same path>.
# 2. Every lib/<x>.sh or functions/<x>.sh a skill names — in its markdown, or
#    on a non-comment line of a script it ships — exists inside that skill, so
#    a new helper reference cannot land without its copy.
#
# Fix a failure by re-copying from the SSOT: cp -p lib/<path> skills/<name>/lib/<path>
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
fail=0 n=0

while IFS= read -r f; do
    n=$((n + 1))
    rel=${f#skills/*/lib/}
    if cmp -s -- "$f" "lib/$rel"; then
        printf 'ok    %s\n' "$f"
    else
        printf 'FAIL  %s differs from lib/%s (cp -p lib/%s %s)\n' "$f" "$rel" "$rel" "$f"
        fail=1
    fi
done < <(find skills -path 'skills/*/lib/*' -type f | sort)
# A scan that finds nothing must not read as "no drift" (6 skills, 37 copies).
[ "$n" -ge 37 ] || { printf 'FAIL  only %s vendored copies found — the scan is broken, not the tree\n' "$n"; fail=1; }

for s in skills/*/; do
    s=${s%/}
    refs=$( { find "$s" -name '*.md' -exec cat {} +
              find "$s" -name '*.sh' -exec grep -hv '^[[:space:]]*#' {} +; } |
        grep -oE '(^|[^a-z_-])(lib/[a-z-]+\.sh|functions/[a-z_]+\.sh)' |
        sed -E 's/^[^lf]*//' | sort -u) || :
    for r in $refs; do
        case $r in
            lib/*) p="$s/$r" ;;
            *) p="$s/lib/vendor/shell-common/$r" ;;
        esac
        [ -f "$p" ] || { printf 'FAIL  %s names %s but does not ship %s\n' "$s" "$r" "$p"; fail=1; }
    done
done

[ "$fail" -eq 0 ] && echo 'All vendored lib copies in sync.'
exit "$fail"
