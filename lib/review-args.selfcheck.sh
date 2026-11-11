#!/usr/bin/env bash
# Self-check for lib/review-args.sh (#70): N / #N / GHES URL / github.com URL
# normalization, the /pull/ refusal, remote matching and lane validation.
#
#   bash lib/review-args.selfcheck.sh
#
# No network: the remotes live in a throwaway git repo.
set -u

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
TARGET="$ROOT/lib/review-args.sh"
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

chk() { # chk <label> <got> <want>
    if [ "$2" = "$3" ]; then
        echo "ok    $1"
    else
        echo "FAIL  $1: got '$2' want '$3'"
        FAIL=1
    fi
}

# run <args...> -> "<rc>|<issue>|<remote>|<host>|<repo>|<lanes>" from inside $TMP/repo
run() {
    local out rc=0
    out=$(cd "$TMP/repo" && bash "$TARGET" "$@" 2>/dev/null) || rc=$?
    printf '%s|%s|%s|%s|%s|%s\n' "$rc" \
        "$(printf '%s\n' "$out" | sed -n 's/^issue=//p')" \
        "$(printf '%s\n' "$out" | sed -n 's/^remote=//p')" \
        "$(printf '%s\n' "$out" | sed -n 's/^host=//p')" \
        "$(printf '%s\n' "$out" | sed -n 's/^repo=//p')" \
        "$(printf '%s\n' "$out" | sed -n 's/^lanes=//p')"
}

git init -q "$TMP/repo"
git -C "$TMP/repo" remote add origin https://github.com/Acme/Widget.git
git -C "$TMP/repo" remote add ghes git@ghes.example.com:team/svc.git
ALL=claude,codex,opencode,agy,hermes

# 1. Plain numbers default to origin.
chk "N"                       "$(run 7)"                 "0|7|origin|||$ALL"
chk "#N"                      "$(run '#7')"              "0|7|origin|||$ALL"
chk "N remote"                "$(run 7 ghes)"            "0|7|ghes|||$ALL"
chk "zero refused"            "$(run 0 | cut -d'|' -f1)" "2"
chk "non-number refused"      "$(run abc | cut -d'|' -f1)" "2"
chk "missing issue refused"   "$(run | cut -d'|' -f1)"   "2"

# 2. URLs: host + owner/repo from the URL, the matching remote found.
chk "github.com URL"          "$(run https://github.com/acme/widget/issues/12)" \
    "0|12|origin|github.com|acme/widget|$ALL"
chk "GHES URL"                "$(run https://ghes.example.com/team/svc/issues/3)" \
    "0|3|ghes|ghes.example.com|team/svc|$ALL"
chk "URL fragment + query"    "$(run 'https://github.com/Acme/Widget/issues/12/?x=1#issuecomment-9')" \
    "0|12|origin|github.com|Acme/Widget|$ALL"
chk "URL, no matching remote" "$(run https://github.com/other/repo/issues/5)" \
    "0|5||github.com|other/repo|$ALL"
chk "URL + matching remote"   "$(run https://github.com/acme/widget/issues/12 origin | cut -d'|' -f1-3)" "0|12|origin"
chk "URL + other remote"      "$(run https://github.com/acme/widget/issues/12 ghes | cut -d'|' -f1)" "2"
chk "URL + missing remote"    "$(run https://github.com/acme/widget/issues/12 nope | cut -d'|' -f1)" "2"

# 3. Refusals: a PR URL and any other URL shape.
chk "/pull/ URL refused"      "$(run https://github.com/acme/widget/pull/12 | cut -d'|' -f1)" "2"
msg=$(cd "$TMP/repo" && bash "$TARGET" https://github.com/acme/widget/pull/12 2>&1 >/dev/null)
case "$msg" in *gh-verify:review-all*) chk "/pull/ points at gh-verify:review-all" ok ok ;;
*) chk "/pull/ points at gh-verify:review-all" "$msg" "...gh-verify:review-all..." ;; esac
chk "/discussions/ refused"   "$(run https://github.com/acme/widget/discussions/1 | cut -d'|' -f1)" "2"
chk "/issues/ non-number"     "$(run https://github.com/acme/widget/issues/x | cut -d'|' -f1)" "2"

# 4. Flags.
chk "--lanes subset"          "$(run 7 --lanes codex,agy | cut -d'|' -f6)" "codex,agy"
chk "--lanes=form"            "$(run 7 --lanes=claude | cut -d'|' -f6)" "claude"
chk "--lanes unknown"         "$(run 7 --lanes codex,gpt | cut -d'|' -f1)" "2"
chk "--lanes repeated"        "$(run 7 --lanes codex,codex | cut -d'|' -f1)" "2"
chk "--lanes empty entry"     "$(run 7 --lanes codex, | cut -d'|' -f1)" "2"
chk "--lanes no value"        "$(run 7 --lanes | cut -d'|' -f1)" "2"
chk "--force refused (engine has no bypass)" "$(run 7 --force | cut -d'|' -f1)" "2"
chk "unknown flag"            "$(run 7 --nope | cut -d'|' -f1)" "2"
chk "third positional"        "$(run 7 origin extra | cut -d'|' -f1)" "2"
for h in -h --help help; do
    chk "$h"                  "$(cd "$TMP/repo" && bash "$TARGET" "$h")" "help=1"
done

[ "$FAIL" -eq 0 ] && echo "review-args.sh: all checks passed"
exit "$FAIL"
