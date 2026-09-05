#!/usr/bin/env bash
# Self-check for the vendored lib/vendor/shell-common/functions/parse_yaml_defaults.sh
# and the contract `skills/create/references/auto-labels.md` Step 2.5 relies on:
#
#   bash lib/parse-yaml-defaults.selfcheck.sh
#
# Runs against a throwaway `.gh-issue-defaults.yml`, so it needs no network, no
# gh auth, and no dotfiles checkout. Exits non-zero on the first regression.
#
# The parser itself is upstream's (SSOT: dEitY719/dotfiles); its own suite lives
# there. What this file pins is what a re-vendor or a careless edit here can
# break: the file being present at all, and the DOTFILES_FORCE_INIT that Step 2.5
# must pass for the helpers to exist in a non-interactive shell.
#
# Every `. "$TARGET"` below is the very thing under test, so its path is a
# runtime value by construction.
# shellcheck disable=SC1090
set -u

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
TARGET="$ROOT/lib/vendor/shell-common/functions/parse_yaml_defaults.sh"
FAIL=0

chk() { # chk <label> <got> <want>
    if [ "$2" = "$3" ]; then
        echo "ok    $1"
    else
        echo "FAIL  $1: got '$2' want '$3'"
        FAIL=1
    fi
}

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# 1. Vendored at all. A re-vendor that drops this file puts Step 2.5 straight
#    back to `command not found` on a machine with no dotfiles checkout.
chk "vendored copy present" "$([ -r "$TARGET" ] && echo yes || echo no)" "yes"
[ -r "$TARGET" ] || exit 1

# 2. Sourced the way Step 2.5 sources it, all three helpers exist.
got=$( DOTFILES_FORCE_INIT=1 sh -c '. "$1" && for f in _parse_yaml_defaults_static \
         _parse_yaml_defaults_by_prefix _parse_yaml_defaults_milestone; do
           command -v "$f" >/dev/null 2>&1 || exit 1; done; echo defined' \
       sh "$TARGET" 2>/dev/null )
chk "helpers defined with DOTFILES_FORCE_INIT" "$got" "defined"

# 3. …and do NOT exist without it. This is the whole reason the call site sets
#    it: the file carries shell-common's interactive guard, so a non-interactive
#    shell gets a silent early return and three `command not found` calls.
got=$( sh -c '. "$1" 2>/dev/null; command -v _parse_yaml_defaults_static \
         >/dev/null 2>&1 && echo defined || echo undefined' sh "$TARGET" )
chk "self-disables without DOTFILES_FORCE_INIT" "$got" "undefined"

# 4. The three keys auto-labels.md documents, inline-list form.
cat >"$TMP/inline.yml" <<'YML'
default_labels:
  static: [chore, skill]
  by_title_prefix:
    feat: [feat]
    chore: []
milestone: auto
YML
got=$( DOTFILES_FORCE_INIT=1 sh -c '. "$1"
       printf "%s|%s|%s|%s" \
         "$(_parse_yaml_defaults_static "$2" | tr "\n" ",")" \
         "$(_parse_yaml_defaults_by_prefix "$2" feat)" \
         "$(_parse_yaml_defaults_by_prefix "$2" chore)" \
         "$(_parse_yaml_defaults_milestone "$2")"' sh "$TARGET" "$TMP/inline.yml" )
chk "inline schema parses" "$got" "chore,skill,|feat||auto"

# 5. Block-list `static`, the other form auto-labels.md promises to accept.
cat >"$TMP/block.yml" <<'YML'
default_labels:
  static:
    - chore
    - skill
milestone: none
YML
got=$( DOTFILES_FORCE_INIT=1 sh -c '. "$1"
       printf "%s|%s" \
         "$(_parse_yaml_defaults_static "$2" | tr "\n" ",")" \
         "$(_parse_yaml_defaults_milestone "$2")"' sh "$TARGET" "$TMP/block.yml" )
chk "block-list schema parses" "$got" "chore,skill,|none"

# 6. A missing file is an argument error, not an empty label set: Step 2.5 must
#    be able to tell "no SSOT" from "SSOT says no labels".
got=$( DOTFILES_FORCE_INIT=1 sh -c '. "$1"
       _parse_yaml_defaults_static "$2" >/dev/null 2>&1; echo $?' \
       sh "$TARGET" "$TMP/nosuch.yml" )
chk "missing file returns non-zero" "$got" "1"

# 7. POSIX sh, not just bash — the skills run under whatever /bin/sh is.
if command -v dash >/dev/null 2>&1; then
    got=$( DOTFILES_FORCE_INIT=1 dash -c '. "$1"; _parse_yaml_defaults_milestone "$2"' \
           dash "$TARGET" "$TMP/inline.yml" 2>/dev/null )
    chk "sourced under dash" "$got" "auto"
else
    echo "skip  dash not installed"
fi

exit "$FAIL"
