#!/usr/bin/env bash
# Self-check for lib/discussion-fetch.sh. No framework, no network, no gh auth:
#
#   bash lib/discussion-fetch.selfcheck.sh
#
# `gh` is a stub on a temporary PATH and the REAL vendored gh_discussion.sh runs
# over it. §5-§9 carry the tier cases lib/plugin-root.selfcheck.sh used to run
# against the pasted `_GD=` block in convert-cmd.md (#58), now against the
# executed script: tier 0/1/2 order, no cwd tier, a directory or an unreadable
# file at the helper path, and a helper that defines nothing.
set -u

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
TARGET="$ROOT/lib/discussion-fetch.sh"
FAIL=0
TMP=$(mktemp -d) || exit 1
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
command -v jq >/dev/null 2>&1 || { echo "FAIL  jq is required by gh_discussion.sh and by this check"; exit 1; }

chk() { # chk <label> <got> <want>
    if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1: got '$2' want '$3'"; FAIL=1; fi
}

mkdir -p "$TMP/bin" "$TMP/home"
cat > "$TMP/bin/gh" <<'GH'
#!/bin/sh
printf 'fetch host=%s\n' "${GH_HOST:-}" >> "$GH_LOG"
[ -z "${GH_FAIL:-}" ] || { echo "gh: fetch failed" >&2; exit 1; }
echo '{"id":"D_1","number":7,"title":"T","body":"b","url":"u","locked":false,"closed":false,"category":{"name":"Ideas"}}'
GH
chmod +x "$TMP/bin/gh"

run() { # run <GH_HOST> <args...> -> stdout; rc in $?
    _h=$1; shift
    : > "$TMP/gh.log"
    env -u SHELL_COMMON -u TARGET_HOST ${_TH:+TARGET_HOST="$_TH"} PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" GH_HOST="$_h" HOME="$TMP/home" \
        DOTFILES_ROOT="${_DR:-/nonexistent-dotfiles}" ${_SC:+SHELL_COMMON="$_SC"} bash "${SCRIPT:-$TARGET}" "$@" 2>"$TMP/err"
}
log() { tr '\n' ',' < "$TMP/gh.log"; }

# 1. Happy path through the vendored tier: one call, host inherited, category flattened.
got=$(run github.com acme widget 7); rc=$?
chk "happy exit" "$rc" 0
chk "happy JSON flattened" "$(printf '%s' "$got" | jq -r '.id + "|" + .category')" "D_1|Ideas"
chk "happy host" "$(log)" "fetch host=github.com,"

# 2. Empty GH_HOST: the only host selector gh api graphql has -> exit 2, no call.
run "" acme widget 7 >/dev/null; rc=$?
chk "empty GH_HOST exits 2, no gh call" "$rc|$(log)" "2|"

# 3. TARGET_HOST set and != GH_HOST -> exit 2, no call (#57). Equal is fine.
_TH=ghes.example run github.com acme widget 7 >/dev/null; rc=$?
chk "GH_HOST != TARGET_HOST exits 2, no gh call" "$rc|$(log)" "2|"
_TH=github.com run github.com acme widget 7 >/dev/null; rc=$?
chk "GH_HOST == TARGET_HOST passes" "$rc" 0

# 4. Usage and fetch failure.
run github.com acme widget >/dev/null; rc=$?
chk "missing arg exits 2, no gh call" "$rc|$(log)" "2|"
GH_FAIL=1 run github.com acme widget 7 >/dev/null; rc=$?
chk "fetch fail exits 1" "$rc" 1
case $(cat "$TMP/err") in *"[gh-discussion] discussion #7 not found"*) got=named ;; *) got=silent ;; esac
chk "fetch fail passes the helper's reason through" "$got" named

# 5. Tier 1 wins when DOTFILES_ROOT holds the helper; tier 0 beats it.
mkdir -p "$TMP/dot/shell-common/functions" "$TMP/sc/functions"
echo '_gh_discussion_fetch() { echo "tier1:$1:$2:$3"; }' > "$TMP/dot/shell-common/functions/gh_discussion.sh"
sed 's/tier1/tier0/' "$TMP/dot/shell-common/functions/gh_discussion.sh" > "$TMP/sc/functions/gh_discussion.sh"
chk "tier 1 (DOTFILES_ROOT)" "$(_DR="$TMP/dot" run github.com acme widget 7)" "tier1:acme:widget:7"
chk "tier 0 (SHELL_COMMON) beats tier 1" "$(_SC="$TMP/sc" _DR="$TMP/dot" run github.com acme widget 7)" "tier0:acme:widget:7"
chk "tier 0 without the helper falls to tier 1" "$(_SC="$TMP/home" _DR="$TMP/dot" run github.com acme widget 7)" "tier1:acme:widget:7"

# 6. No cwd tier (dEitY719/harness-skills#22): a copy with no vendor/ sibling
#    stops naming the path it tried, even from a cwd ($ROOT) that holds one.
mkdir -p "$TMP/bare"; cp "$TARGET" "$TMP/bare/"
(cd "$ROOT" && SCRIPT="$TMP/bare/discussion-fetch.sh" run github.com acme widget 7 >/dev/null); rc=$?
chk "no vendor -> exit 1, no gh call" "$rc|$(log)" "1|"
case $(cat "$TMP/err") in *"$TMP/bare/vendor/shell-common/functions/gh_discussion.sh"*) got=named ;; *) got=unnamed ;; esac
chk "no vendor names the path tried" "$got" named

# 7. A directory at the tier-1 path is not the helper: it falls through to the
#    vendored tier instead of being sourced.
mkdir -p "$TMP/dirtrap/shell-common/functions/gh_discussion.sh"
_DR="$TMP/dirtrap" run github.com acme widget 7 >/dev/null; rc=$?
chk "directory at tier 1 falls through to vendor" "$rc|$(log)" "0|fetch host=github.com,"

# 8. An unreadable helper is skipped the same way (root ignores mode bits).
mkdir -p "$TMP/unread/shell-common/functions"
echo '_gh_discussion_fetch() { echo poisoned; }' > "$TMP/unread/shell-common/functions/gh_discussion.sh"
chmod 000 "$TMP/unread/shell-common/functions/gh_discussion.sh"
if [ -r "$TMP/unread/shell-common/functions/gh_discussion.sh" ]; then
    echo "skip  unreadable helper (running as root)"
else
    got=$(_DR="$TMP/unread" run github.com acme widget 7)
    chk "unreadable helper at tier 1 is not sourced" "$(printf '%s' "$got" | jq -r .id 2>/dev/null)" "D_1"
fi

# 9. A helper that defines nothing fails the function proof, even with an
#    inherited exported function of the same name standing by.
: > "$TMP/dot/shell-common/functions/gh_discussion.sh"
_gh_discussion_fetch() { echo inherited; }
export -f _gh_discussion_fetch
_DR="$TMP/dot" run github.com acme widget 7 >/dev/null; rc=$?
chk "empty helper fails the function proof" "$rc|$(log)" "1|"
unset -f _gh_discussion_fetch

[ "$FAIL" -eq 0 ] && echo "discussion-fetch selfcheck: all passed"
exit "$FAIL"
