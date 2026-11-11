#!/usr/bin/env bash
# Self-check for lib/code-tree.sh (#70): which tree the reviewer CLIs get.
#
#   bash lib/code-tree.selfcheck.sh
#
# Cases: a matching remote (HEAD worktree), no remote (clone, `gh` stubbed),
# internal + github.com (the remote's default branch, never HEAD), an
# unreadable setup-mode reader (fail closed = internal), and cleanup of each.
# No network: the "remote" is a local bare repo.
set -u

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
TARGET="$ROOT/lib/code-tree.sh"
VENDOR="$ROOT/lib/vendor/shell-common"
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" TMPDIR="$TMP/tmp"
mkdir -p "$HOME" "$TMPDIR" "$TMP/bin"

chk() { # chk <label> <got> <want>
    if [ "$2" = "$3" ]; then
        echo "ok    $1"
    else
        echo "FAIL  $1: got '$2' want '$3'"
        FAIL=1
    fi
}

g() { git -c user.name=t -c user.email=t@example.invalid "$@"; }

# Remote: one public commit on main. Local: that plus an "internal" commit.
g init -q -b main "$TMP/seed"
echo public >"$TMP/seed/f"
g -C "$TMP/seed" add f
g -C "$TMP/seed" commit -qm public
git clone -q --bare "$TMP/seed" "$TMP/remote.git"
git clone -q "$TMP/remote.git" "$TMP/local"
git -C "$TMP/local" checkout -qb feature
echo internal >"$TMP/local/f"
g -C "$TMP/local" commit -qam internal
PUBLIC=$(git -C "$TMP/remote.git" rev-parse --short main)
INTERNAL=$(git -C "$TMP/local" rev-parse --short HEAD)

# `gh repo clone <host>/<repo> <dir> -- ...` stub: clones the bare repo.
cat >"$TMP/bin/gh" <<EOF
#!/bin/sh
echo "GH_HOST=\$GH_HOST \$*" >>"$TMP/gh.log"
[ "\$1 \$2" = "repo clone" ] || exit 9
git clone -q "$TMP/remote.git" "\$4"
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

# prepare <mode|-> <host> [remote] -> "<KIND> <BASE> <TREE>"; mode `-` unsets it.
prepare() {
    local out
    if [ "$1" = - ]; then
        out=$(cd "$TMP/local" && env -u DOTFILES_SETUP_MODE bash "$TARGET" prepare "$2" acme/widget "${3-}" 2>&1)
    else
        out=$(cd "$TMP/local" && DOTFILES_SETUP_MODE="$1" bash "$TARGET" prepare "$2" acme/widget "${3-}" 2>&1)
    fi
    printf '%s %s %s\n' "$(printf '%s\n' "$out" | sed -n 's/^KIND=//p')" \
        "$(printf '%s\n' "$out" | sed -n 's/^BASE=//p')" "$(printf '%s\n' "$out" | sed -n 's/^TREE=//p')"
}
cleanup_ok() { # cleanup_ok <label> <tree>
    (cd "$TMP/local" && bash "$TARGET" cleanup "$2")
    chk "$1: tree removed" "$([ -e "$2" ] && echo present || echo gone)" gone
    chk "$1: worktree unregistered" "$(git -C "$TMP/local" worktree list --porcelain | grep -c "$2")" 0
}

export SHELL_COMMON="$VENDOR"

# 1. External PC, matching remote: a detached worktree at HEAD.
# shellcheck disable=SC2046  # split into KIND BASE TREE on purpose
set -- $(prepare external github.com origin)
chk "external + github.com: KIND" "$1" head
chk "external + github.com: BASE" "$2" "feature@$INTERNAL"
chk "external + github.com: tree holds HEAD" "$(cat "$3/f")" internal
chk "tree is not the user's tree" "$(cd -P "$3" && pwd | grep -c "$TMP/tmp/gh-issue-review-tree.")" 1
cleanup_ok "head" "$3"

# 2. Internal PC + github.com: the remote's default branch, never HEAD.
# shellcheck disable=SC2046  # split into KIND BASE TREE on purpose
set -- $(prepare internal github.com origin)
chk "internal + github.com: KIND" "$1" default-branch
chk "internal + github.com: BASE" "$2" "main@$PUBLIC"
chk "internal + github.com: no internal commit" "$(cat "$3/f")" public
cleanup_ok "default-branch" "$3"

# 3. Internal PC + GHES target: HEAD is fine.
t=$(prepare internal ghes.example.com origin)
chk "internal + GHES: KIND" "$(echo "$t" | cut -d' ' -f1)" head
cleanup_ok "ghes" "$(echo "$t" | cut -d' ' -f3)"

# 4. Reader unreadable -> fail closed: no setup_mode_read.sh anywhere.
mkdir -p "$TMP/sc/lib"
cp "$VENDOR/lib/gh_host.sh" "$VENDOR/lib/dotfiles_root.sh" "$TMP/sc/lib/"
t=$(SHELL_COMMON="$TMP/sc" prepare - github.com origin)
chk "reader missing: fail closed to default-branch" "$(echo "$t" | cut -d' ' -f1)" default-branch
cleanup_ok "reader missing" "$(echo "$t" | cut -d' ' -f3)"
t=$(SHELL_COMMON="" prepare external github.com origin)
chk "gh_host.sh missing: fail closed to default-branch" "$(echo "$t" | cut -d' ' -f1)" default-branch
cleanup_ok "gh_host missing" "$(echo "$t" | cut -d' ' -f3)"

# 5. No local remote names the repo: a depth-1 clone, host pinned.
# shellcheck disable=SC2046  # split into KIND BASE TREE on purpose
set -- $(prepare external github.com)
chk "no remote: KIND" "$1" clone
chk "no remote: BASE" "$2" "main@$PUBLIC"
chk "no remote: gh host-pinned" "$(cat "$TMP/gh.log")" "GH_HOST=github.com repo clone github.com/acme/widget $3 -- --depth 1 -q"
cleanup_ok "clone" "$3"

# 6. Failure paths leave nothing behind; cleanup refuses a foreign directory.
chk "bad remote: prepare fails" "$(cd "$TMP/local" && DOTFILES_SETUP_MODE=internal bash "$TARGET" prepare github.com acme/widget nope >/dev/null 2>&1; echo $?)" 1
chk "bad remote: no temp tree left" "$(find "$TMPDIR" -maxdepth 1 -name 'gh-issue-review-tree.*' | wc -l | tr -d ' ')" 0
mkdir -p "$TMP/foreign"
chk "cleanup refuses a foreign dir" "$(bash "$TARGET" cleanup "$TMP/foreign" 2>/dev/null; echo $?)" 1
chk "foreign dir kept" "$([ -d "$TMP/foreign" ] && echo kept)" kept

[ "$FAIL" -eq 0 ] && echo "code-tree.sh: all checks passed"
exit "$FAIL"
