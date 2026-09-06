#!/usr/bin/env bash
# Self-check for lib/discussion-post-convert.sh. No framework, no fixtures:
#
#   bash lib/discussion-post-convert.selfcheck.sh
#
# The four mutations are stubbed by pointing the script at a throwaway plugin
# root whose lib/vendor/shell-common/functions/*.sh define the helpers as
# recorders. That exercises the real resolution + sourcing path — no test hook
# inside the shipped script — while making the best-effort contract assertable
# instead of merely asserted in prose: exit 0 and an accurate `steps:` line even
# when every mutation errors.
#
# No network, no gh auth, no dotfiles checkout.
set -u

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
TARGET="$ROOT/lib/discussion-post-convert.sh"
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

# A fake plugin root holding stub helpers. $RC_* decide each stub's exit code;
# $TMP/calls records the call order so "best-effort" can be checked as
# behaviour rather than taken on faith.
FAKE="$TMP/plugin"
mkdir -p "$FAKE/lib/vendor/shell-common/functions"
cat > "$FAKE/lib/vendor/shell-common/functions/gh_discussion.sh" <<'STUB'
_gh_discussion_comment() { echo "comment $1" >>"$CALLS"; return "${RC_COMMENT:-0}"; }
_gh_discussion_close()   { echo "close $1 $2" >>"$CALLS"; return "${RC_CLOSE:-0}"; }
_gh_discussion_lock()    { echo "lock $1" >>"$CALLS"; return "${RC_LOCK:-0}"; }
STUB
cat > "$FAKE/lib/vendor/shell-common/functions/gh_project_status.sh" <<'STUB'
_gh_project_status_sync() { echo "board $*" >>"$CALLS"; return "${RC_BOARD:-0}"; }
STUB

CALLS="$TMP/calls"
export CALLS
# Pin the two tiers ahead of the vendored one at paths that cannot exist, so
# every case below really does exercise the CLAUDE_PLUGIN_ROOT tier.
export DOTFILES_ROOT=/nonexistent-dotfiles
unset SHELL_COMMON
export TARGET_REPO=acme/widget

# Every knob is threaded explicitly: a `VAR=x run ...` prefix on a *function*
# is a shell variable, not an exported one, so it would never reach the child.
run() { # run <args...>  -> stdout; rc in $?
    : > "$CALLS"
    CLAUDE_PLUGIN_ROOT="$FAKE" \
    RC_BOARD="${RC_BOARD:-0}" RC_COMMENT="${RC_COMMENT:-0}" \
    RC_CLOSE="${RC_CLOSE:-0}" RC_LOCK="${RC_LOCK:-0}" \
    DCLOSED="${DCLOSED:-false}" DLOCKED="${DLOCKED:-false}" \
        bash "$TARGET" "$@" 2>/dev/null
}

# 1. All four run: the happy path prints every token "on"/"synced" and exits 0.
got=$(run D_kwDO 42); rc=$?
chk "happy path exit code" "$rc" "0"
chk "happy path steps line" "$got" "  steps: comment=on, lock=on, close=on, board=synced"

# 2. The mutations really fired, in the documented 6-7-8 order, and each got
#    the ids it was handed — not a stale or empty one.
chk "board call" "$(sed -n 1p "$CALLS")" \
    "board issue 42 In progress --only-from Backlog,Ready --repo acme/widget"
chk "comment call" "$(sed -n 2p "$CALLS" | cut -d' ' -f1-2)" "comment D_kwDO"
chk "close call" "$(sed -n 3p "$CALLS")" "close D_kwDO RESOLVED"
chk "lock call" "$(sed -n 4p "$CALLS")" "lock D_kwDO"

# 3. Each --no-* flag turns exactly its own step off and touches no other.
got=$(run D_kwDO 42 1 0 0 0)
chk "--no-comment" "$got" "  steps: comment=off, lock=on, close=on, board=synced"
chk "--no-comment fires no comment" "$(grep -c '^comment ' "$CALLS")" "0"
got=$(run D_kwDO 42 0 1 0 0)
chk "--no-lock" "$got" "  steps: comment=on, lock=off, close=on, board=synced"
got=$(run D_kwDO 42 0 0 1 0)
chk "--no-close" "$got" "  steps: comment=on, lock=on, close=off, board=synced"
got=$(run D_kwDO 42 0 0 0 1)
chk "--no-board-sync" "$got" "  steps: comment=on, lock=on, close=on, board=skipped"
chk "--no-board-sync fires no sync" "$(grep -c '^board ' "$CALLS")" "0"

# 4. An already-closed / already-locked Discussion is reported as skipped and
#    not re-mutated — the idempotency half of the skill's contract.
got=$(DCLOSED=true DLOCKED=true run D_kwDO 42)
chk "already closed+locked" "$got" "  steps: comment=on, lock=skip, close=skip, board=synced"
chk "no close/lock mutation when already so" "$(grep -c '^close \|^lock ' "$CALLS")" "0"

# 5. THE contract: every mutation fails, and the script still exits 0 with a
#    truthful line. A non-zero here would let a flaky board sync abort a flow
#    whose Issue — the actual SSOT invariant — already exists.
got=$(RC_BOARD=1 RC_COMMENT=1 RC_CLOSE=1 RC_LOCK=1 run D_kwDO 42); rc=$?
chk "all mutations fail: still exit 0" "$rc" "0"
chk "all mutations fail: reported" "$got" \
    "  steps: comment=fail, lock=fail, close=fail, board=failed"

# 5b. A single failure does not stop the later steps.
got=$(RC_BOARD=1 run D_kwDO 42)
chk "board failure does not stop 7/8" "$got" \
    "  steps: comment=on, lock=on, close=on, board=failed"

# 6. Missing arguments are a usage error (exit 2), not a half-run.
CLAUDE_PLUGIN_ROOT="$FAKE" bash "$TARGET" >/dev/null 2>&1
chk "no args exits 2" "$?" "2"
CLAUDE_PLUGIN_ROOT="$FAKE" bash "$TARGET" D_kwDO >/dev/null 2>&1
chk "missing issue number exits 2" "$?" "2"
( unset TARGET_REPO; CLAUDE_PLUGIN_ROOT="$FAKE" bash "$TARGET" D_kwDO 42 ) >/dev/null 2>&1
chk "unset TARGET_REPO exits 2" "$?" "2"

# 7. No tier 4 (dEitY719/harness-skills#22, PR #18 codex BLOCKER): with no
#    plugin root exported, a cwd that DOES hold lib/vendor/shell-common must be
#    refused rather than sourced. The decoy is exactly what a repo under review
#    could ship. POSIX sh, the shape every non-bash/zsh harness runs.
DECOY="$TMP/decoy"
mkdir -p "$DECOY/lib/vendor/shell-common/functions"
cat > "$DECOY/lib/vendor/shell-common/functions/gh_discussion.sh" <<'DECOYSTUB'
_gh_discussion_comment() { echo poisoned >&2; return 0; }
_gh_discussion_close()   { return 0; }
_gh_discussion_lock()    { return 0; }
DECOYSTUB
cp "$DECOY/lib/vendor/shell-common/functions/gh_discussion.sh" \
   "$DECOY/lib/vendor/shell-common/functions/gh_project_status.sh"
out=$( cd "$DECOY" && env -u CLAUDE_PLUGIN_ROOT -u PLUGIN_ROOT -u SHELL_COMMON \
       DOTFILES_ROOT=/nonexistent-dotfiles TARGET_REPO=acme/widget \
       sh "$TARGET" D_kwDO 42 2>&1; printf '|%s' "$?" )
case "$out" in
    *"steps:"*|*poisoned*) got="sourced the cwd: $out" ;;
    *"|1")                 got=refused ;;
    *)                     got="unexpected: $out" ;;
esac
chk "cwd lib/vendor is never sourced (no tier 4)" "$got" refused

# 8. An existing-but-unreadable helper must stop too: -f alone passes it and the
#    source then fails silently. Root ignores the mode bits, so skip as root.
UNREADABLE="$TMP/unreadable"
mkdir -p "$UNREADABLE/lib/vendor/shell-common/functions"
printf '#\n' > "$UNREADABLE/lib/vendor/shell-common/functions/gh_discussion.sh"
printf '#\n' > "$UNREADABLE/lib/vendor/shell-common/functions/gh_project_status.sh"
chmod 000 "$UNREADABLE/lib/vendor/shell-common/functions/"*.sh
if [ -r "$UNREADABLE/lib/vendor/shell-common/functions/gh_discussion.sh" ]; then
    echo "skip  unreadable-helper case (running as root)"
else
    CLAUDE_PLUGIN_ROOT="$UNREADABLE" bash "$TARGET" D_kwDO 42 >/dev/null 2>&1
    chk "unreadable helper is refused" "$?" "1"
fi

# 9. A directory where the helper should be is the case a bare -r would accept.
DIRTRAP="$TMP/dirtrap"
mkdir -p "$DIRTRAP/lib/vendor/shell-common/functions/gh_discussion.sh"
mkdir -p "$DIRTRAP/lib/vendor/shell-common/functions/gh_project_status.sh"
CLAUDE_PLUGIN_ROOT="$DIRTRAP" bash "$TARGET" D_kwDO 42 >/dev/null 2>&1
chk "a directory at the helper path is refused" "$?" "1"

# 10. POSIX sh must be able to run it end to end — the five non-Claude harnesses.
if command -v dash >/dev/null 2>&1; then
    got=$( : > "$CALLS"; CLAUDE_PLUGIN_ROOT="$FAKE" dash "$TARGET" D_kwDO 42 2>/dev/null )
    chk "runs under dash" "$got" "  steps: comment=on, lock=on, close=on, board=synced"
else
    echo "skip  dash not installed"
fi

exit "$FAIL"
