#!/usr/bin/env bash
# Self-check for lib/create-issue.sh. No framework, no network, no gh auth:
#
#   bash lib/create-issue.selfcheck.sh
#
# `gh` is a stub on a temporary PATH that logs its host and argv, so the cases
# assert the exact `gh issue create` call the old pasted block made — and, the
# one this script exists for, that a missing host or repo binding exits 2
# without gh ever being called (dEitY719/dotfiles#1403).
set -u

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
TARGET="$ROOT/lib/create-issue.sh"
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
for a in "$@"; do printf '|%s' "$a" >> "$GH_LOG"; done
printf '\n' >> "$GH_LOG"
[ "${GH_RC:-0}" -eq 0 ] || { echo "gh: boom" >&2; exit "$GH_RC"; }
echo "https://example.test/acme/widget/issues/7"
GH
chmod +x "$TMP/bin/gh"
BODY="$TMP/body.md"; printf 'body\n' > "$BODY"

run() { # run <GH_HOST> <TARGET_REPO> <TARGET_HOST> <args...> -> stdout; rc in $?
    _h=$1 _r=$2 _t=$3; shift 3
    : > "$TMP/gh.log"
    env PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" GH_RC="${GH_RC:-0}" \
        GH_HOST="$_h" TARGET_REPO="$_r" TARGET_HOST="$_t" bash "$TARGET" "$@" 2>/dev/null
}
calls() { wc -l < "$TMP/gh.log" | tr -d ' '; }

# 1. Happy path: same argv order as the pasted block, host pinned, URL out.
got=$(run github.com acme/widget github.com --title "T 1" --body-file "$BODY" \
    --label bug --label "area: x" --milestone M1); rc=$?
chk "happy exit" "$rc" 0
chk "happy stdout is gh's URL" "$got" "https://example.test/acme/widget/issues/7"
chk "happy argv + host" "$(cat "$TMP/gh.log")" \
    "host=github.com|issue|create|--repo|acme/widget|--title|T 1|--body-file|$BODY|--label|bug|--label|area: x|--milestone|M1"

# 2. No labels / milestone: the call degrades to its original short form.
run github.com acme/widget "" --title T --body-file "$BODY" >/dev/null
chk "bare argv" "$(cat "$TMP/gh.log")" "host=github.com|issue|create|--repo|acme/widget|--title|T|--body-file|$BODY"

# 3. The release blocker: GH_HOST or TARGET_REPO empty -> exit 2, gh never called.
run "" acme/widget "" --title T --body-file "$BODY" >/dev/null; rc=$?
chk "empty GH_HOST exits 2" "$rc" 2
chk "empty GH_HOST never calls gh" "$(calls)" 0
run github.com "" "" --title T --body-file "$BODY" >/dev/null; rc=$?
chk "empty TARGET_REPO exits 2" "$rc" 2
chk "empty TARGET_REPO never calls gh" "$(calls)" 0
run github.com acme/widget ghe.example --title T --body-file "$BODY" >/dev/null; rc=$?
chk "GH_HOST != TARGET_HOST exits 2" "$rc" 2
chk "host mismatch never calls gh" "$(calls)" 0

# 4. Usage errors are exit 2 with no call.
run github.com acme/widget "" --title T --body-file "$TMP/missing" >/dev/null; rc=$?
chk "missing body file exits 2" "$rc:$(calls)" "2:0"
run github.com acme/widget "" --title T >/dev/null; rc=$?
chk "missing --body-file exits 2" "$rc:$(calls)" "2:0"
run github.com acme/widget "" --title T --body-file "$BODY" --bogus x >/dev/null; rc=$?
chk "unknown flag exits 2" "$rc:$(calls)" "2:0"
run github.com acme/widget "" --title T --body-file "$BODY" --label >/dev/null; rc=$?
chk "--label without value exits 2" "$rc:$(calls)" "2:0"

# 5. gh's own failure code passes through.
GH_RC=1 run github.com acme/widget "" --title T --body-file "$BODY" >/dev/null; rc=$?
chk "gh failure propagates" "$rc" 1

[ "$FAIL" -eq 0 ] && echo "create-issue selfcheck: all passed"
exit "$FAIL"
