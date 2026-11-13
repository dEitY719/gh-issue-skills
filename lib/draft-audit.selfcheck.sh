#!/usr/bin/env bash
set -eu
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' 'https://github.com/a http://inside.example/x https://inside.example/y' > "$tmp/body"
actual=$(TARGET_HOST=github.com "$ROOT/lib/draft-audit.sh" "$tmp/body")
[ "$actual" = '[WARN] draft-audit: non-target host inside.example — 근거 확인' ]
printf '%s\n' 'https://github.com/a' > "$tmp/body"
[ -z "$(TARGET_HOST=github.com "$ROOT/lib/draft-audit.sh" "$tmp/body")" ]
printf '%s\n' 'no links' > "$tmp/body"
[ -z "$(TARGET_HOST=github.com "$ROOT/lib/draft-audit.sh" "$tmp/body")" ]
printf '%s\n' 'draft-audit selfcheck: all passed'
