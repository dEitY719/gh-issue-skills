#!/bin/sh
# Report distinct non-target HTTP(S) URL hosts in a drafted issue body.
set -eu
[ "$#" -eq 1 ] && [ -r "$1" ] && [ -n "${TARGET_HOST:-}" ] || {
    printf '%s\n' 'usage: TARGET_HOST=<host> draft-audit.sh <body-file>' >&2
    exit 2
}
# Include a port in the authority, as GHES TARGET_HOST can include one.
LC_ALL=C grep -Eo 'https?://[^][(){}<>"'"'"'[:space:]/?#]+' "$1" | \
    sed -E 's|^https?://||; s/^[^@]*@//; s/[.,;:!?]+$//' | \
    LC_ALL=C sort -fu | awk -v target="$TARGET_HOST" '
        tolower($0) != tolower(target) && length($0) {
            printf "[WARN] draft-audit: non-target host %s — 근거 확인\n", $0
        }' || {
    # grep returns 1 for a draft without URLs, which is a successful no-op.
    exit 0
}
