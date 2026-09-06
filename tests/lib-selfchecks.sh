#!/usr/bin/env bash
# Runs every lib/*.selfcheck.sh, so the helpers in lib/ are gated by CI rather
# than by remembering to run them. Each script is self-contained: no network,
# no gh auth, no dotfiles checkout.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
for f in lib/*.selfcheck.sh; do
    echo "== $f"
    bash "$f"
done
