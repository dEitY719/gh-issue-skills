#!/usr/bin/env bash
# Self-check for lib/create-discussion.sh. No framework, no network, no gh auth:
#
#   bash lib/create-discussion.selfcheck.sh
#
# `gh` is a stub on a temporary PATH that answers the three GraphQL calls by
# which query it was handed, and the REAL vendored gh_discussion.sh runs over
# it — so the call order, the inherited GH_HOST and the stop-on-first-failure
# behaviour of the old pasted block are asserted, not re-typed.
set -u

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
TARGET="$ROOT/lib/create-discussion.sh"
FAIL=0
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
command -v jq >/dev/null 2>&1 || { echo "FAIL  jq is required by gh_discussion.sh and by this check"; exit 1; }

chk() { # chk <label> <got> <want>
    if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1: got '$2' want '$3'"; FAIL=1; fi
}

mkdir -p "$TMP/bin" "$TMP/home"
cat > "$TMP/bin/gh" <<'GH'
#!/bin/sh
case "$*" in
    *createDiscussion*) k=create ;;
    *discussionCategories*) k=category ;;
    *) k=repo ;;
esac
printf '%s host=%s\n' "$k" "${GH_HOST:-}" >> "$GH_LOG"
case " ${GH_FAIL:-} " in *" $k "*) echo "gh: $k failed" >&2; exit 1 ;; esac
case $k in
    repo) echo R_1 ;;
    category) if [ -n "${GH_CATS:-}" ]; then echo "$GH_CATS"; else echo '[{"id":"C_1","name":"Ideas"}]'; fi ;;
    create) for a in "$@"; do case $a in title=*) t=${a#title=} ;; body=@*) b=${a#body=@} ;; esac; done
            [ -r "$b" ] || exit 1
            echo "https://example.test/d/1?t=$t" ;;
esac
GH
chmod +x "$TMP/bin/gh"
BODY="$TMP/body.md"; printf 'body\n' > "$BODY"

run() { # run <GH_HOST> <args...> -> stdout; rc in $?
    _h=$1; shift
    : > "$TMP/gh.log"
    env -u SHELL_COMMON -u TARGET_HOST ${_TH:+TARGET_HOST="$_TH"} PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" GH_HOST="$_h" HOME="$TMP/home" \
        DOTFILES_ROOT=/nonexistent-dotfiles bash "${SCRIPT:-$TARGET}" "$@" 2>"$TMP/err"
}
log() { tr '\n' ',' < "$TMP/gh.log"; }

# 1. Happy path through the vendored tier: three calls in order, host inherited.
got=$(run github.com acme widget ideas "T1" "$BODY"); rc=$?
chk "happy exit" "$rc" 0
chk "happy URL" "$got" "https://example.test/d/1?t=T1"
chk "happy call order + host" "$(log)" "repo host=github.com,category host=github.com,create host=github.com,"

# 2. Empty GH_HOST: the only host selector gh api graphql has -> exit 2, no call.
run "" acme widget Ideas T "$BODY" >/dev/null; rc=$?
chk "empty GH_HOST exits 2" "$rc" 2
chk "empty GH_HOST never calls gh" "$(log)" ""

# 2b. TARGET_HOST set and != GH_HOST: host and repo came from different remotes
#     -> exit 2, no call (same guard as create-issue.sh, #57). Equal is fine.
_TH=ghes.example run github.com acme widget Ideas T "$BODY" >/dev/null; rc=$?
chk "GH_HOST != TARGET_HOST exits 2, no gh call" "$rc|$(log)" "2|"
case $(cat "$TMP/err") in "[FAIL] GH_HOST (github.com) != TARGET_HOST (ghes.example)"*) got=named ;; *) got=silent ;; esac
chk "host mismatch names both hosts" "$got" named
_TH=github.com run github.com acme widget Ideas T "$BODY" >/dev/null; rc=$?
chk "GH_HOST == TARGET_HOST passes" "$rc" 0

# 3. Usage: a missing argument or an unreadable body file -> exit 2, no call.
run github.com acme widget Ideas T >/dev/null; rc=$?
chk "missing arg exits 2" "$rc|$(log)" "2|"
run github.com acme widget Ideas T "$TMP/missing" >/dev/null; rc=$?
chk "missing body exits 2" "$rc|$(log)" "2|"

# 4. Each lookup failure stops before the mutation, exit 1, helper's reason on stderr.
GH_FAIL=repo run github.com acme widget Ideas T "$BODY" >/dev/null; rc=$?
chk "repo lookup fail" "$rc|$(log)" "1|repo host=github.com,"
GH_CATS='[]' run github.com acme widget Ideas T "$BODY" >/dev/null; rc=$?
chk "discussions disabled" "$rc|$(log)" "1|repo host=github.com,category host=github.com,"
case $(cat "$TMP/err") in *"Discussions not enabled"*) got=named ;; *) got=silent ;; esac
chk "discussions disabled names itself" "$got" named
GH_CATS='[{"id":"C_1","name":"Q&A"}]' run github.com acme widget Ideas T "$BODY" >/dev/null; rc=$?
chk "unknown category exits 1" "$rc" 1
GH_FAIL=create run github.com acme widget Ideas T "$BODY" >/dev/null; rc=$?
chk "mutation fail exits 1" "$rc" 1

# 5. Tier 1 wins when DOTFILES_ROOT holds the helper.
mkdir -p "$TMP/dot/shell-common/functions"
cat > "$TMP/dot/shell-common/functions/gh_discussion.sh" <<'STUB'
_gh_discussion_repo_id() { echo R_t1; }
_gh_discussion_category_id() { echo C_t1; }
_gh_discussion_create() { echo "tier1:$1:$2:$3"; }
STUB
got=$(env -u SHELL_COMMON PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" GH_HOST=github.com HOME="$TMP/home" \
    DOTFILES_ROOT="$TMP/dot" bash "$TARGET" acme widget Ideas T "$BODY" 2>/dev/null)
chk "tier 1 (DOTFILES_ROOT)" "$got" "tier1:R_t1:C_t1:T"

# 5b. Tier 0 wins over tier 1 and tier 2: the SHELL_COMMON Step 1 proved and
#     exported (lib/resolve-target.sh), the same order discussion-post-convert.sh
#     uses (#56). A SHELL_COMMON without the helper falls through to tier 1.
mkdir -p "$TMP/sc/functions"
sed 's/tier1/tier0/' "$TMP/dot/shell-common/functions/gh_discussion.sh" > "$TMP/sc/functions/gh_discussion.sh"
got=$(env PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" GH_HOST=github.com HOME="$TMP/home" \
    SHELL_COMMON="$TMP/sc" DOTFILES_ROOT="$TMP/dot" bash "$TARGET" acme widget Ideas T "$BODY" 2>/dev/null)
chk "tier 0 (SHELL_COMMON) beats tier 1" "$got" "tier0:R_t1:C_t1:T"
got=$(env PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" GH_HOST=github.com HOME="$TMP/home" \
    SHELL_COMMON="$TMP/home" DOTFILES_ROOT="$TMP/dot" bash "$TARGET" acme widget Ideas T "$BODY" 2>/dev/null)
chk "tier 0 without the helper falls to tier 1" "$got" "tier1:R_t1:C_t1:T"

# 6. No cwd tier (dEitY719/harness-skills#22): a copy with no vendor/ sibling
#    stops naming the path it tried, even from a cwd ($ROOT) that holds one.
mkdir -p "$TMP/bare"; cp "$TARGET" "$TMP/bare/"
got=$(cd "$ROOT" && SCRIPT="$TMP/bare/create-discussion.sh" run github.com acme widget Ideas T "$BODY"); rc=$?
chk "no vendor -> exit 1, no gh call" "$rc|$(log)" "1|"
case $(cat "$TMP/err") in *"$TMP/bare/vendor/shell-common/functions/gh_discussion.sh"*) got=named ;; *) got=unnamed ;; esac
chk "no vendor names the path tried" "$got" named

# 7. A helper that defines nothing is caught by the function proof.
: > "$TMP/dot/shell-common/functions/gh_discussion.sh"
env -u SHELL_COMMON PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" GH_HOST=github.com HOME="$TMP/home" \
    DOTFILES_ROOT="$TMP/dot" bash "$TARGET" acme widget Ideas T "$BODY" >/dev/null 2>&1; rc=$?
chk "empty helper fails the function proof" "$rc" 1

[ "$FAIL" -eq 0 ] && echo "create-discussion selfcheck: all passed"
exit "$FAIL"
