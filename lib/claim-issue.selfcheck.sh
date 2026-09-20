#!/usr/bin/env bash
# Self-check for lib/claim-issue.sh — the behavior matrix in
# skills/implement/references/claim.md, run rather than read:
#
#   bash lib/claim-issue.selfcheck.sh
#
# No network, no gh auth, no dotfiles checkout. `gh` is a shell script on a
# temporary PATH that answers from files this test writes, and the board helper
# is a stub shell-common tree — so every substep's real control flow runs,
# only the two external programs are faked.
set -u

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
TARGET="$ROOT/lib/claim-issue.sh"
FAIL=0

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

command -v jq >/dev/null 2>&1 || { echo "FAIL  jq is required by lib/claim-issue.sh and by this check"; exit 1; }

# --- the fake `gh` -----------------------------------------------------------
# Records every invocation to $TMP/gh.log and answers from $TMP/gh.*, so a case
# can assert both what was written and what was read. GH_FAIL lists the
# sub-commands that must fail, which is how the soft-fail rows are exercised.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'GH'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_LOG"
case " ${GH_FAIL:-} " in *" $1 "*) exit 1 ;; esac
case "$1 ${2:-}" in
    "api user")  printf '%s\n' "${GH_ME:-me}" ;;
    "pr list")   [ -z "${GH_DUP_PR:-}" ] || printf '%s\n' "$GH_DUP_PR" ;;
    "issue edit") : ;;
    "issue view") printf '%s\n' "${GH_DEP_STATE:-CLOSED}" ;;
    *) exit 1 ;;
esac
GH
chmod +x "$TMP/bin/gh"

# --- the stub board helper ---------------------------------------------------
mkdir -p "$TMP/sc/functions"
cat > "$TMP/sc/functions/gh_project_status.sh" <<'SC'
_gh_project_status_sync() { printf 'sync %s\n' "$*" >> "$GH_LOG"; return 0; }
_gh_project_status_query_current() {
    [ -n "${BOARD_STATUS:-}" ] || return 1
    printf '%s\n' "$BOARD_STATUS"
}
SC

json() { # json <labels-csv> <assignees-csv> <body>
    LBL="$1" ASG="$2" BODY="$3" jq -nc '
        {number: 7, title: "t", state: "OPEN", url: "u", comments: [],
         body: env.BODY,
         labels:    (env.LBL | if . == "" then [] else split(",") | map({name: .}) end),
         assignees: (env.ASG | if . == "" then [] else split(",") | map({login: .}) end)}'
}

IMPL_DEFAULT='do-not-work,on-hold,보류,⏸️ Postpone,reference'
PROCEED_DEFAULT='do-not-work,on-hold,보류,⏸️ Postpone'

# run <json> <flags...> -> stdout+stderr on stdout, rc in $RC, gh log in $LOG
run() {
    local payload="$1"; shift
    : > "$TMP/gh.log"
    OUT=$(printf '%s' "$payload" | env PATH="$TMP/bin:$PATH" \
        GH_LOG="$TMP/gh.log" SHELL_COMMON="$TMP/sc" \
        TARGET_REPO=acme/widget TARGET_HOST=github.com \
        "${ENV_OVERRIDES[@]}" sh "$TARGET" 7 "$@" 2>&1)
    RC=$?
    LOG=$(cat "$TMP/gh.log")
}

chk() { # chk <label> <got> <want>
    if [ "$2" = "$3" ]; then printf 'ok    %s\n' "$1"
    else printf 'FAIL  %s: got %s want %s\n' "$1" "$(printf %s "$2" | head -c 400)" "$3"; FAIL=1; fi
}
has() { case "$2" in *"$3"*) chk "$1" yes yes ;; *) chk "$1" "$2" "contains: $3" ;; esac; }
hasnt() { case "$2" in *"$3"*) chk "$1" "$2" "must not contain: $3" ;; *) chk "$1" yes yes ;; esac; }

ENV_OVERRIDES=()
NORMAL=$(json '' '' 'plain body')

# 1. Normal run: assign, board move, nothing else.
run "$NORMAL" --block-labels-default "$IMPL_DEFAULT" --duplicate-pr-guard
chk  "normal rc"                "$RC" 0
has  "normal self-assigns"      "$LOG" 'issue edit 7 --repo acme/widget --add-assignee @me'
has  "normal moves the board"   "$LOG" 'sync issue 7 In progress --only-from Backlog,Ready --repo acme/widget'
chk  "normal is silent"         "$OUT" ''

# 2. Block label: hard refusal, exit 2, BEFORE any mutation.
for L in do-not-work on-hold 보류 '⏸️ Postpone'; do
    run "$(json "$L" '' '')" --block-labels-default "$IMPL_DEFAULT" --duplicate-pr-guard
    chk "block '$L' exits 2" "$RC" 2
    chk "block '$L' mutates nothing" "$LOG" ''
    has "block '$L' names the label" "$OUT" "blocked by label '$L'"
done

# 3. `reference` is implement's default only — the one intentional divergence.
run "$(json reference '' '')" --block-labels-default "$IMPL_DEFAULT" --duplicate-pr-guard
chk "implement refuses 'reference'" "$RC" 2
run "$(json reference '' '')" --block-labels-default "$PROCEED_DEFAULT"
chk "proceed proceeds on 'reference'" "$RC" 0
has "proceed still claims it"       "$LOG" '--add-assignee @me'

# 4. GH_ISSUE_BLOCK_LABELS overrides whichever default was passed.
ENV_OVERRIDES=(GH_ISSUE_BLOCK_LABELS=custom-park)
run "$(json custom-park '' '')" --block-labels-default "$PROCEED_DEFAULT"
chk "env override refuses"        "$RC" 2
run "$(json do-not-work '' '')" --block-labels-default "$IMPL_DEFAULT"
chk "env override replaces the default" "$RC" 0
ENV_OVERRIDES=()

# 5. Assignees.
run "$(json '' me 'b')" --block-labels-default "$IMPL_DEFAULT"
chk   "already mine is a no-op" "$RC" 0
hasnt "already mine does not re-assign" "$LOG" 'issue edit'
chk   "already mine is silent"  "$OUT" ''

run "$(json '' colleague 'b')" --block-labels-default "$IMPL_DEFAULT"
chk   "other assignee proceeds"        "$RC" 0
hasnt "other assignee is not overridden" "$LOG" 'issue edit'
has   "other assignee warns"           "$OUT" '[WARN] Issue #7 is assigned to colleague; not overriding.'

# 6. Duplicate open-PR guard — implement only, silent when clean.
ENV_OVERRIDES=(GH_DUP_PR=91)
run "$NORMAL" --block-labels-default "$IMPL_DEFAULT" --duplicate-pr-guard
chk "dup PR proceeds"        "$RC" 0
has "dup PR warns"           "$OUT" 'open PR #91'
has "dup PR searches both keywords" "$LOG" '"Closes #7" OR "Fixes #7" in:body'
run "$NORMAL" --block-labels-default "$PROCEED_DEFAULT"
chk   "proceed runs no dup search" "$RC" 0
hasnt "proceed never calls pr list" "$LOG" 'pr list'
hasnt "proceed prints no dup warning" "$OUT" 'open PR'
ENV_OVERRIDES=()

ENV_OVERRIDES=(GH_DUP_PR=91 GH_ISSUE_SKIP_DUPLICATE_CHECK=1)
run "$NORMAL" --block-labels-default "$IMPL_DEFAULT" --duplicate-pr-guard
hasnt "SKIP_DUPLICATE_CHECK skips the search" "$LOG" 'pr list'
ENV_OVERRIDES=()

# A failing search is silent, not even a warn line (NF-1).
ENV_OVERRIDES=(GH_FAIL=pr)
run "$NORMAL" --block-labels-default "$IMPL_DEFAULT" --duplicate-pr-guard
chk "dup search error proceeds" "$RC" 0
chk "dup search error is silent" "$OUT" ''
ENV_OVERRIDES=()

# 7. Board.
ENV_OVERRIDES=(BOARD_STATUS='In progress')
run "$NORMAL" --block-labels-default "$IMPL_DEFAULT"
has "board already In progress warns" "$OUT" 'Status 가 이미 "In progress"'
has "board still calls sync"          "$LOG" 'sync issue 7 In progress'
ENV_OVERRIDES=()
ENV_OVERRIDES=(BOARD_STATUS=Backlog)
run "$NORMAL" --block-labels-default "$IMPL_DEFAULT"
chk "board in Backlog is silent" "$OUT" ''
ENV_OVERRIDES=()

# No shell-common at all: warn on stderr, skip, never abort (dEitY719/dotfiles#724).
OUT=$(printf '%s' "$NORMAL" | env -u CLAUDE_PLUGIN_ROOT PATH="$TMP/bin:$PATH" \
    GH_LOG="$TMP/gh.log" SHELL_COMMON="$TMP/nonexistent" HOME="$TMP/nohome" \
    TARGET_REPO=acme/widget TARGET_HOST=github.com sh "$TARGET" 7 \
    --block-labels-default "$IMPL_DEFAULT" 2>&1); RC=$?
chk "missing board helper does not abort" "$RC" 0
has "missing board helper warns + skips"  "$OUT" 'board transition skipped'

# 8. Depends-on guard.
run "$(json '' '' 'Depends on #12')" --block-labels-default "$IMPL_DEFAULT"
chk "deps: closed dependency is silent" "$OUT" ''
ENV_OVERRIDES=(GH_DEP_STATE=OPEN)
run "$(json '' '' 'depends on #12 and DEPENDS ON #13')" --block-labels-default "$IMPL_DEFAULT"
has "deps: case-insensitive, first"  "$OUT" 'depends on #12 which is still OPEN'
has "deps: case-insensitive, second" "$OUT" 'depends on #13 which is still OPEN'
chk "deps: proceeds anyway"          "$RC" 0
run "$(json '' '' 'see #dep-3 and #1.2.3 — Depends on #14')" --block-labels-default "$IMPL_DEFAULT"
has   "deps: matches whole #<digits>" "$OUT" 'depends on #14'
hasnt "deps: ignores #dep-3"          "$OUT" '#dep-3'
ENV_OVERRIDES=()

ENV_OVERRIDES=(GH_FAIL=issue GH_DEP_STATE=OPEN)
run "$(json '' '' 'Depends on #12')" --block-labels-default "$IMPL_DEFAULT"
chk "deps: lookup error proceeds" "$RC" 0
has "deps: lookup error warns"    "$OUT" 'Could not check dependency #12'
ENV_OVERRIDES=()

# 9. Every GH_ISSUE_SKIP_* actually skips.
for pair in GH_ISSUE_SKIP_SELF_ASSIGN:'issue edit' GH_ISSUE_SKIP_BOARD_TRANSITION:'sync issue'; do
    ENV_OVERRIDES=("${pair%%:*}=1")
    run "$(json '' '' 'Depends on #12')" --block-labels-default "$IMPL_DEFAULT"
    chk   "${pair%%:*} proceeds" "$RC" 0
    hasnt "${pair%%:*} skips its step" "$LOG" "${pair#*:}"
    ENV_OVERRIDES=()
done
ENV_OVERRIDES=(GH_ISSUE_SKIP_DEPS_CHECK=1)
run "$(json '' '' 'Depends on #12')" --block-labels-default "$IMPL_DEFAULT"
hasnt "GH_ISSUE_SKIP_DEPS_CHECK skips its step" "$LOG" 'issue view'
ENV_OVERRIDES=()

# 10. Self-assign is soft-fail: a read-only token warns and the run continues.
ENV_OVERRIDES=(GH_FAIL='issue')
run "$NORMAL" --block-labels-default "$IMPL_DEFAULT"
chk "self-assign error proceeds" "$RC" 0
has "self-assign error warns"    "$OUT" 'Could not self-assign issue #7'
ENV_OVERRIDES=()

# 11. Usage guards fail loudly rather than claiming an unclaimed issue.
ENV_OVERRIDES=()
OUT=$(printf '%s' "$NORMAL" | env PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" \
    TARGET_REPO=acme/widget TARGET_HOST=github.com sh "$TARGET" 7 2>&1); RC=$?
chk "missing --block-labels-default exits 1" "$RC" 1
OUT=$(printf '%s' "$NORMAL" | env PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" \
    sh "$TARGET" 7 --block-labels-default "$IMPL_DEFAULT" 2>&1); RC=$?
chk "unbound target exits 1" "$RC" 1
has "unbound target names the cause" "$OUT" 'TARGET_REPO and TARGET_HOST'
OUT=$(printf '' | env PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" \
    TARGET_REPO=acme/widget TARGET_HOST=github.com \
    sh "$TARGET" not-a-number --block-labels-default "$IMPL_DEFAULT" 2>&1); RC=$?
chk "non-numeric issue exits 1" "$RC" 1

# 12. The block guard is fail-closed under every shell the skills paste into.
for sh in sh bash zsh dash; do
    command -v "$sh" >/dev/null 2>&1 || { printf 'skip  %s not installed\n' "$sh"; continue; }
    got=$(printf '%s' "$(json '⏸️ Postpone' '' '')" | env PATH="$TMP/bin:$PATH" \
        GH_LOG="$TMP/gh.log" SHELL_COMMON="$TMP/sc" \
        TARGET_REPO=acme/widget TARGET_HOST=github.com \
        "$sh" "$TARGET" 7 --block-labels-default "$IMPL_DEFAULT" >/dev/null 2>&1; echo $?)
    chk "$sh: block guard exits 2" "$got" 2
done

# 13. Plugin-root tiers for the board helper (harness-skills#10 / #22).
# These assertions used to live in lib/plugin-root.selfcheck.sh against the
# `_SC="${SHELL_COMMON...` block pasted into the two claim.md files; the block
# has one home now, so they run here against the real script instead of an
# extracted copy of it. Three of that file's cases are gone because executing
# rather than pasting makes them unreachable, not untested: an executed script
# cannot inherit the caller's `set -e`, cannot inherit a stale
# _gh_project_status_sync, and cannot leave a poisoned SHELL_COMMON behind in
# the caller's shell.
SANDBOX=$(mktemp -d); HOME_EMPTY=$(mktemp -d)
DIRTRAP="$TMP/dirtrap"        # a directory where the helper should be: the
mkdir -p "$DIRTRAP/lib/vendor/shell-common/functions/gh_project_status.sh"
UNREADABLE="$TMP/unreadable"  # present but unreadable: `-f` alone accepts it
mkdir -p "$UNREADABLE/lib/vendor/shell-common/functions"
printf '#\n' > "$UNREADABLE/lib/vendor/shell-common/functions/gh_project_status.sh"
chmod 000 "$UNREADABLE/lib/vendor/shell-common/functions/gh_project_status.sh"
# Root ignores the permission bits, so that case is only meaningful unprivileged.
[ -r "$UNREADABLE/lib/vendor/shell-common/functions/gh_project_status.sh" ] \
    && CAN_TEST_UNREADABLE=0 || CAN_TEST_UNREADABLE=1

# A tier-2 root whose helper is present and readable but defines nothing: the
# case an existence test cannot tell from a good one, and the one the imposter
# below rides on.
HOLLOW="$TMP/hollow"
mkdir -p "$HOLLOW/lib/vendor/shell-common/functions"
printf '# defines nothing\n' > "$HOLLOW/lib/vendor/shell-common/functions/gh_project_status.sh"
IMPOSTER="$TMP/imposter"
mkdir -p "$IMPOSTER"
printf '#!/bin/sh\nprintf imposter\n' > "$IMPOSTER/_gh_project_status_sync"
chmod +x "$IMPOSTER/_gh_project_status_sync"

tier() { # tier <shell> <cwd> <plugin-root-or-empty> [extra-PATH-dir]
    local sh="$1" cwd="$2" pr="$3" xp="${4:-}"
    local _p="$TMP/bin:$PATH"
    [ -z "$xp" ] || _p="$xp:$_p"
    if [ -n "$pr" ]; then
        OUT=$( cd "$cwd" && { printf '%s' "$NORMAL" | env -u SHELL_COMMON -u DOTFILES_ROOT \
            CLAUDE_PLUGIN_ROOT="$pr" HOME="$HOME_EMPTY" PATH="$_p" \
            GH_LOG="$TMP/gh.log" GH_ISSUE_SKIP_SELF_ASSIGN=1 GH_ISSUE_SKIP_DEPS_CHECK=1 \
            TARGET_REPO=acme/widget TARGET_HOST=github.com \
            "$sh" "$TARGET" 7 --block-labels-default "$IMPL_DEFAULT" >/dev/null; } 2>&1 )
    else
        OUT=$( cd "$cwd" && { printf '%s' "$NORMAL" | env -u SHELL_COMMON -u DOTFILES_ROOT \
            -u CLAUDE_PLUGIN_ROOT HOME="$HOME_EMPTY" PATH="$TMP/bin:$PATH" \
            GH_LOG="$TMP/gh.log" GH_ISSUE_SKIP_SELF_ASSIGN=1 GH_ISSUE_SKIP_DEPS_CHECK=1 \
            TARGET_REPO=acme/widget TARGET_HOST=github.com \
            "$sh" "$TARGET" 7 --block-labels-default "$IMPL_DEFAULT" >/dev/null; } 2>&1 )
    fi
    RC=$?
}
skipped() { case "$OUT" in *"board transition skipped"*) echo skipped ;; *) echo loaded ;; esac; }

for sh in sh bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || { printf 'skip  %s not installed\n' "$sh"; continue; }

    tier "$sh" "$SANDBOX" "$ROOT"
    chk "$sh: tier 2 (CLAUDE_PLUGIN_ROOT) loads the helper" "$(skipped)" loaded
    chk "$sh: tier 2 does not abort"                        "$RC" 0

    # $ROOT really does hold lib/vendor/shell-common, so running from that cwd
    # with nothing exported must STILL stop — tier 4 was retired (#22).
    tier "$sh" "$ROOT" ""
    chk "$sh: no tier 4 — the cwd is not a source" "$(skipped)" skipped
    chk "$sh: no tier 4 does not abort"            "$RC" 0

    tier "$sh" "$SANDBOX" ""
    chk "$sh: tier 5 warns and skips" "$(skipped)" skipped
    chk "$sh: tier 5 does not abort"  "$RC" 0
    hasnt "$sh: tier 5 never resolves under /" "$OUT" ' /lib/vendor'

    tier "$sh" "$SANDBOX" "$DIRTRAP"
    chk "$sh: a directory at the helper path is rejected" "$(skipped)" skipped
    chk "$sh: the directory trap does not abort"          "$RC" 0

    if [ "$CAN_TEST_UNREADABLE" -eq 1 ]; then
        tier "$sh" "$SANDBOX" "$UNREADABLE"
        chk "$sh: an unreadable helper is rejected" "$(skipped)" skipped
        chk "$sh: the unreadable helper does not abort" "$RC" 0
    fi

    # The proof tests for a FUNCTION, not for a runnable name
    # (dEitY719/harness-skills#36). `command -v X >/dev/null` — the shape this
    # replaced — answers "is this name runnable", so with a helper that loads
    # but defines nothing, a PATH executable of that exact name satisfied it
    # and the board write was attempted against a helper that was never there.
    # $IMPOSTER goes on PATH ahead of everything for exactly that reason.
    tier "$sh" "$SANDBOX" "$HOLLOW" "$IMPOSTER"
    chk "$sh: a PATH executable named _gh_project_status_sync is not the helper" \
        "$(skipped)" skipped
    chk "$sh: the imposter case does not abort" "$RC" 0

    # SHELL_COMMON is already exported while gh_project_status.sh is SOURCED
    # (dEitY719/harness-skills#37). That helper resolves dotfiles_root.sh
    # through ${SHELL_COMMON:-$HOME/dotfiles/shell-common} at source time, so
    # exporting after the proof was too late for its only consumer: on this
    # tier-2 path, with HOME empty, it looked under a $HOME/dotfiles that does
    # not exist and skipped its own #1454 guard. The load succeeded either
    # way, which is why only the helper's own warning shows it.
    tier "$sh" "$SANDBOX" "$ROOT"
    hasnt "$sh: the helper finds its sibling while sourcing (no skipped guard)" \
        "$OUT" '#1454 guard skipped'
done
rm -rf "$SANDBOX" "$HOME_EMPTY"

# 14. Doc-to-script drift guard: the two claim.md call blocks are the only
# place the two skills' policies differ, so they are extracted from the shipped
# docs and RUN, not read. Rewording a flag in one doc, or dropping one from the
# script, fails here instead of at 3am in somebody's implement run.
call_block() { # call_block <claim.md path> -> the first ```bash block, dedented
    awk '/^```bash$/ {on = 1; next} on && /^```$/ {exit} on' "$ROOT/$1"
}
call_block skills/implement/references/claim.md > "$TMP/call-implement.sh"
call_block skills/proceed/references/claim.md   > "$TMP/call-proceed.sh"
for f in call-implement call-proceed; do
    [ -s "$TMP/$f.sh" ] || { printf 'FAIL  %s: no bash block extracted\n' "$f"; FAIL=1; }
done

call() { # call <block> <json> [extra env...] -> rc in $RC, gh log in $LOG
    local block="$1" payload="$2"; shift 2
    : > "$TMP/gh.log"
    OUT=$(env PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" SHELL_COMMON="$TMP/sc" \
        TARGET_REPO=acme/widget TARGET_HOST=github.com PLUGIN_ROOT="$ROOT" \
        N=7 ISSUE_JSON="$payload" "$@" sh "$TMP/$block.sh" 2>&1)
    RC=$?
    LOG=$(cat "$TMP/gh.log")
}

REFERENCE=$(json reference '' 'plain body')

call call-implement "$NORMAL"
chk "doc block (implement) runs clean"     "$RC" 0
has "doc block (implement) self-assigns"   "$LOG" '--add-assignee @me'
has "doc block (implement) keeps --duplicate-pr-guard" "$LOG" 'pr list'

call call-proceed "$NORMAL"
chk   "doc block (proceed) runs clean"        "$RC" 0
has   "doc block (proceed) self-assigns"      "$LOG" '--add-assignee @me'
hasnt "doc block (proceed) has no dup guard"  "$LOG" 'pr list'

call call-implement "$REFERENCE"
chk "doc block (implement) refuses 'reference' with exit 2" "$RC" 2
call call-proceed "$REFERENCE"
chk "doc block (proceed) proceeds on 'reference'" "$RC" 0

# Both blocks must fail loudly rather than compose a path from the cwd.
for block in call-implement call-proceed; do
    OUT=$( cd "$ROOT" && env -u PLUGIN_ROOT PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" \
        TARGET_REPO=acme/widget TARGET_HOST=github.com N=7 ISSUE_JSON="$NORMAL" \
        sh "$TMP/$block.sh" 2>&1 ); RC=$?
    chk "$block stops when PLUGIN_ROOT is unset" "$RC" 1
    has "$block names the way out"               "$OUT" 'export CLAUDE_PLUGIN_ROOT'
done

[ "$FAIL" -eq 0 ] && echo "[OK] lib/claim-issue.sh behavior matrix" || echo "[FAIL] lib/claim-issue.sh"
exit "$FAIL"
