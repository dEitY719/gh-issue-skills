#!/usr/bin/env bash
# Self-check for lib/link-deps.sh. No framework, no network, no gh auth:
#
#   bash lib/link-deps.selfcheck.sh
#
# `gh` is a stub on a temporary PATH; GH_IDS is what the aliased node-id query
# "returns", GH_MUT_RC / GH_ERR decide the mutation. The NF-1 contract is the
# point: every outcome exits 0, and each failed N yields exactly one [WARN]
# line plus its `원인:` line when the call said something.
set -u

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
TARGET="$ROOT/lib/link-deps.sh"
FAIL=0
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

chk() { # chk <label> <got> <want>
    if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1: got '$2' want '$3'"; FAIL=1; fi
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'GH'
#!/bin/sh
printf 'host=%s' "${GH_HOST:-}" >> "$GH_LOG"
kind=lookup
for a in "$@"; do
    case $a in query=*addBlockedBy*) kind=mutation ;; query=*) ;; *) printf '|%s' "$a" >> "$GH_LOG" ;; esac
done
printf '|%s\n' "$kind" >> "$GH_LOG"
if [ "$kind" = lookup ]; then
    [ -z "${GH_LOOKUP_ERR:-}" ] || { echo "$GH_LOOKUP_ERR" >&2; exit 1; }
    printf '%s\n' "${GH_IDS-I_new I_dep}"
else
    [ "${GH_MUT_RC:-0}" -eq 0 ] || { [ -z "${GH_ERR:-}" ] || echo "$GH_ERR" >&2; exit "$GH_MUT_RC"; }
    echo '{"data":{}}'
fi
GH
chmod +x "$TMP/bin/gh"

run() { # run <GH_HOST> <args...> -> stdout; rc in $?
    _h=$1; shift
    : > "$TMP/gh.log"
    env -u TARGET_HOST ${_TH:+TARGET_HOST="$_TH"} PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" GH_HOST="$_h" TARGET_REPO=acme/widget \
        bash "$TARGET" "$@" 2>/dev/null
}

W13='[WARN] Blocked by #13 링크 실패 — GH UI에서 수동 추가 필요'

# 1. Two deps, both linked: silent, exit 0, lookup+mutation per N, host pinned.
got=$(run github.com 20 13 14); rc=$?
chk "all linked exit" "$rc" 0
chk "all linked prints nothing" "$got" ""
chk "call log" "$(cat "$TMP/gh.log")" "host=github.com|api|graphql|-f|owner=acme|-f|name=widget|-F|new=20|-F|dep=13|-f|--jq|(.data.repository // {}) |
                   \"\\(.newIssue.id // \"\") \\(.depIssue.id // \"\")\"|lookup
host=github.com|api|graphql|-f|issueId=I_new|-f|blockingIssueId=I_dep|-f|mutation
host=github.com|api|graphql|-f|owner=acme|-f|name=widget|-F|new=20|-F|dep=14|-f|--jq|(.data.repository // {}) |
                   \"\\(.newIssue.id // \"\") \\(.depIssue.id // \"\")\"|lookup
host=github.com|api|graphql|-f|issueId=I_new|-f|blockingIssueId=I_dep|-f|mutation"

# 2. A dep that does not exist (null id) never reaches the mutation.
got=$(GH_IDS='I_new ' run github.com 20 13); rc=$?
chk "null dep id: exit 0" "$rc" 0
chk "null dep id: one warning, no cause" "$got" "$W13"
chk "null dep id: no mutation" "$(grep -c mutation "$TMP/gh.log")" 0

# 3. A rejected mutation carries the server's first line as 원인.
got=$(GH_MUT_RC=1 GH_ERR="$(printf 'schema says no\nsecond line')" run github.com 20 13); rc=$?
chk "mutation fail: exit 0" "$rc" 0
chk "mutation fail: warning + cause" "$got" "$W13
    원인: schema says no"

# 4. A failed lookup names itself too.
got=$(GH_LOOKUP_ERR='Could not resolve to an Issue' run github.com 20 13); rc=$?
chk "lookup fail: warning + cause" "$rc|$got" "0|$W13
    원인: Could not resolve to an Issue"

# 5. One bad N never rejects its siblings.
got=$(GH_IDS='I_new ' run github.com 20 13 14)
chk "per-N warnings" "$(printf '%s\n' "$got" | grep -c '^\[WARN\]')" 2

# 6. No GH_HOST: no gh call at all, still exit 0, one warning per N.
got=$(run "" 20 13 14); rc=$?
chk "no GH_HOST: exit 0" "$rc" 0
chk "no GH_HOST: no gh call" "$(wc -l < "$TMP/gh.log" | tr -d ' ')" 0
chk "no GH_HOST: warning per N" "$(printf '%s\n' "$got" | grep -c '^\[WARN\]')" 2

# 6b. TARGET_HOST set and != GH_HOST: no gh call, exit 0, warning + 원인 per N (#57).
got=$(_TH=ghes.example run github.com 20 13 14); rc=$?
chk "host mismatch: exit 0" "$rc" 0
chk "host mismatch: no gh call" "$(wc -l < "$TMP/gh.log" | tr -d ' ')" 0
chk "host mismatch: warning per N" "$(printf '%s\n' "$got" | grep -c '^\[WARN\]')" 2
chk "host mismatch: 원인 names both hosts" "$(printf '%s\n' "$got" | grep -c '원인: link-deps: GH_HOST (github.com) != TARGET_HOST (ghes.example)')" 2
got=$(_TH=github.com run github.com 20 13); rc=$?
chk "GH_HOST == TARGET_HOST links" "$rc|$got" "0|"

# 7. No deps: nothing to do.
got=$(run github.com 20); rc=$?
chk "no deps" "$rc|$got" "0|"

[ "$FAIL" -eq 0 ] && echo "link-deps selfcheck: all passed"
exit "$FAIL"
