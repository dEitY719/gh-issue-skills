#!/usr/bin/env bash
# Self-check for lib/resolve-target.sh. No framework, no fixtures:
#
#   bash lib/resolve-target.selfcheck.sh
#
# Runs against a throwaway git repo with synthetic remotes, so it needs no
# network, no gh auth, and no dotfiles checkout. Exits non-zero on the first
# behaviour that regressed.
#
# Every `. "$TARGET"` below is the very thing under test, so its path is a
# runtime value by construction.
# shellcheck disable=SC1090
set -u

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
TARGET="$ROOT/lib/resolve-target.sh"
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
git -C "$TMP" init -q
git -C "$TMP" remote add origin git@github.com:acme/widget.git
git -C "$TMP" remote add ghes https://github.samsungds.net/acme/widget.git

# The vendored tier is what a standalone plugin install exercises, so pin
# DOTFILES_ROOT at a path that cannot exist for every case below.
export DOTFILES_ROOT=/nonexistent-dotfiles

cd "$TMP" || exit 1

# 1. github.com remote: repo and host both read from that one URL.
got=$( CLAUDE_PLUGIN_ROOT="$ROOT" . "$TARGET" origin >/dev/null 2>&1 &&
       printf '%s|%s|%s' "$TARGET_REPO" "$TARGET_HOST" "$GH_HOST" )
chk "github.com remote" "$got" "acme/widget|github.com|github.com"

# 2. GHES remote: the host follows the URL, not the PC's setup mode. This is
#    the dEitY719/dotfiles#1403 case the whole helper exists for.
got=$( CLAUDE_PLUGIN_ROOT="$ROOT" . "$TARGET" ghes >/dev/null 2>&1 &&
       printf '%s|%s' "$TARGET_REPO" "$GH_HOST" )
chk "GHES remote picks its own host" "$got" "acme/widget|github.samsungds.net"

# 3. SHELL_COMMON names whichever tree resolved.
got=$( CLAUDE_PLUGIN_ROOT="$ROOT" . "$TARGET" origin >/dev/null 2>&1 &&
       printf '%s' "$SHELL_COMMON" )
chk "SHELL_COMMON exported" "$got" "$ROOT/lib/vendor/shell-common"

# 3b. PLUGIN_ROOT is the proven plugin root skills address lib/ helpers with.
got=$( CLAUDE_PLUGIN_ROOT="$ROOT" . "$TARGET" origin >/dev/null 2>&1 &&
       printf '%s' "$PLUGIN_ROOT" )
chk "PLUGIN_ROOT exported" "$got" "$ROOT"

# 3c. Without CLAUDE_PLUGIN_ROOT it still resolves, from this file's own path.
#     The cwd here is $TMP, not the plugin, so this also proves PLUGIN_ROOT is
#     never the caller-controlled $PWD (dEitY719/harness-skills#22).
got=$( unset CLAUDE_PLUGIN_ROOT; . "$TARGET" origin >/dev/null 2>&1;
       printf '%s' "$PLUGIN_ROOT" )
chk "PLUGIN_ROOT is proven, not \$PWD" "$got" "$ROOT"

# 4. No CLAUDE_PLUGIN_ROOT (every non-Claude harness): the vendored tree is
#    still found, via the sourced file's own path.
got=$( unset CLAUDE_PLUGIN_ROOT; . "$TARGET" origin >/dev/null 2>&1 &&
       printf '%s' "$GH_HOST" )
chk "resolves without CLAUDE_PLUGIN_ROOT" "$got" "github.com"

# 5. Unknown remote fails instead of silently falling back to origin.
( CLAUDE_PLUGIN_ROOT="$ROOT" . "$TARGET" nosuchremote ) >/dev/null 2>&1
chk "unknown remote returns non-zero" "$?" "1"

# 6. Outside a git repo, fail rather than guess.
( cd / && CLAUDE_PLUGIN_ROOT="$ROOT" . "$TARGET" origin ) >/dev/null 2>&1
chk "outside a git repo returns non-zero" "$?" "1"

# 7. A non-github remote is refused outright rather than half-resolved: the
#    caller must never proceed with an empty GH_HOST, which is precisely the
#    silent wrong-server state of dEitY719/dotfiles#1403.
git -C "$TMP" remote add other https://gitlab.com/acme/widget.git
got=$( CLAUDE_PLUGIN_ROOT="$ROOT" . "$TARGET" other >/dev/null 2>&1; printf '%s|%s' "$?" "${GH_HOST:-unset}" )
chk "non-github remote refused, GH_HOST untouched" "$got" "1|unset"

# 8. POSIX sh must be able to source it with an argument.
got=$( cd "$TMP" && CLAUDE_PLUGIN_ROOT="$ROOT" DOTFILES_ROOT=/nonexistent-dotfiles \
       dash -c ". \"$TARGET\" origin >/dev/null 2>&1 && printf '%s' \"\$GH_HOST\"" 2>/dev/null )
if command -v dash >/dev/null 2>&1; then
    chk "sourced under dash" "$got" "github.com"
else
    echo "skip  dash not installed"
fi

exit "$FAIL"
