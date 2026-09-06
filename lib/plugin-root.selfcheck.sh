#!/usr/bin/env bash
# Self-check for the plugin-root resolution blocks the references/*.md files
# ship. No framework, no fixtures:
#
#   bash lib/plugin-root.selfcheck.sh
#
# Convention SSOT:
# https://github.com/dEitY719/harness-skills/blob/main/references/plugin-root.md
#
# Sister of lib/resolve-target.selfcheck.sh, which covers the self-locating
# *file* carrier. This one covers the *pasted-block* carrier: a fenced block an
# agent copies into a shell, where $0 is the shell and nothing can self-locate,
# so the blocks get tiers 1, 2, 5 and no $0/BASH_SOURCE tier.
#
# There is no tier 4. `${CLAUDE_PLUGIN_ROOT:-$PWD}` was retired by
# dEitY719/harness-skills#22: $PWD is caller-controlled and these skills run
# inside the repository under review, so a PR that ships
# lib/vendor/shell-common/functions/*.sh hands the reviewer's own tooling the
# file it was looking for. The "…must not resolve from the cwd" checks below are
# that regression's test — they run with the cwd set to this checkout, which
# genuinely does hold lib/vendor/shell-common, and require tier 5 anyway.
#
# The blocks are extracted from the shipped .md files rather than retyped, so a
# drift between the docs and this test fails the test instead of hiding.

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); SANDBOX=$(mktemp -d); HOME_EMPTY=$(mktemp -d)
trap 'rm -rf "$TMP" "$SANDBOX" "$HOME_EMPTY"' EXIT
fails=0

chk() { # chk <label> <expected> <got>
    if [ "$2" = "$3" ]; then
        printf 'ok    %s\n' "$1"
    else
        printf 'FAIL  %s: got %s want %s\n' "$1" "$3" "$2"; fails=$((fails + 1))
    fi
}

# Slice one block out of a doc: from the first line starting with $2 through the
# first subsequent line equal to $3. A closing fence as the end anchor takes the
# whole rest of the block and is not itself emitted.
extract() { # extract <name> <start-prefix> <end-line> <file>
    awk -v s="$2" -v e="$3" '
        !on && index($0, s) == 1 { on = 1 }
        on && $0 == e { if (e != "```") print; exit }
        on { print }
    ' "$ROOT/$4" > "$TMP/$1.sh"
    [ -s "$TMP/$1.sh" ] || { printf 'FAIL  %s: extracted nothing from %s\n' "$1" "$4"; fails=$((fails + 1)); }
}

extract create '_GD="${DOTFILES_ROOT' 'fi' \
    skills/create/references/create-cmd.md
extract discussion-convert '_GD="${DOTFILES_ROOT' 'fi' \
    skills/discussion-convert/references/convert-cmd.md
extract discussion-create '_GD="${DOTFILES_ROOT' '}' \
    skills/discussion-create/references/create-cmd.md
extract implement-claim '_SC="${SHELL_COMMON' 'fi' \
    skills/implement/references/claim.md
extract proceed-claim '_SC="${SHELL_COMMON' '```' \
    skills/proceed/references/claim.md
extract proceed-claim-head '_SC="${SHELL_COMMON' 'fi' \
    skills/proceed/references/claim.md

# 1. The gate grep: an explicitly-empty default spliced straight into a path is
#    always the defect (it collapses to the filesystem root), and so is a `$PWD`
#    default — the retired tier 4 (see header).
hits=$(cd "$ROOT" && git ls-files -z | xargs -0 grep -lE '\$\{[A-Za-z_][A-Za-z0-9_]*:?-(\$PWD)?\}/' 2>/dev/null | wc -l)
chk "no empty-default or \$PWD path splices in tracked files" 0 "$((hits))"

# Tier 5 conditions: no harness exported CLAUDE_PLUGIN_ROOT and no ~/dotfiles —
# so tiers 1 and 2 both miss. The cwd is irrelevant now that tier 4 is gone;
# section 5 pins that separately by running the same blocks from $ROOT.
run() { # run <shell> <block>  -> stderr on stdout, rc in $?
    # Braces, not `2>&1 >/dev/null`: same effect, but unambiguous to shellcheck
    # (SC2069) and to the next reader — only stderr is captured.
    ( cd "$SANDBOX" && { env -u CLAUDE_PLUGIN_ROOT -u SHELL_COMMON -u DOTFILES_ROOT \
        HOME="$HOME_EMPTY" "$1" "$TMP/$2.sh" >/dev/null; } 2>&1 )
}

for sh in sh bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || { printf 'skip  %s not installed\n' "$sh"; continue; }

    # 2. A hard-fail site stops, and says which path it tried plus the way out.
    for block in create discussion-convert discussion-create; do
        err=$(run "$sh" "$block"); rc=$?
        chk "$sh/$block stops" nonzero "$([ "$rc" -ne 0 ] && echo nonzero || echo "rc=$rc")"
        # The path tried is now the tier-1 one: with tier 4 retired there is no
        # cwd-derived path left to name.
        case "$err" in *"$HOME_EMPTY/dotfiles"*) got=named ;; *) got="$err" ;; esac
        chk "$sh/$block names the path it tried" named "$got"
        case "$err" in *CLAUDE_PLUGIN_ROOT*) got=hinted ;; *) got=no-hint ;; esac
        chk "$sh/$block names the way out" hinted "$got"
    done

    # 3. The board-transition sites are documented soft-fail: they must warn and
    #    skip the step, never abort the skill.
    err=$(run "$sh" proceed-claim); rc=$?
    chk "$sh/proceed-claim does not abort" 0 "$rc"
    case "$err" in *"board transition skipped"*) got=warned ;; *) got="$err" ;; esac
    chk "$sh/proceed-claim warns and skips" warned "$got"

    # 3b. A board-transition site must not fire an _gh_project_status_sync
    #     inherited from an earlier source once resolution has failed — that
    #     mutates a board while the warning above claims the step was skipped.
    got=$( cd "$SANDBOX" && env -u CLAUDE_PLUGIN_ROOT -u SHELL_COMMON -u DOTFILES_ROOT \
        HOME="$HOME_EMPTY" "$sh" -c '
            rm -f CALLED; : > N   # <N> in the block lexes as a redirect pair,
            #                       so the probe reports through a file, not stdout
            _gh_project_status_sync() { : > CALLED; }
            . "$1" >/dev/null 2>&1
            [ -f CALLED ] && printf called || printf skipped' _ "$TMP/proceed-claim.sh" )
    chk "$sh/proceed-claim does not call an inherited sync" skipped "$got"

    # 4. The regression this whole convention exists for: never resolve to the
    #    filesystem root, and never export an unproven SHELL_COMMON. Sourced,
    #    because that is how a poisoned export would reach later helpers.
    for block in create discussion-convert discussion-create implement-claim proceed-claim; do
        got=$( cd "$SANDBOX" && env -u CLAUDE_PLUGIN_ROOT -u SHELL_COMMON -u DOTFILES_ROOT \
            HOME="$HOME_EMPTY" "$sh" -c \
            '. "$1" >/dev/null 2>&1; printf "%s" "${SHELL_COMMON:-unset}"' _ "$TMP/$block.sh" )
        chk "$sh/$block leaves SHELL_COMMON unset" unset "$got"
        err=$(run "$sh" "$block" 2>&1)
        case "$err" in *' /lib/vendor'*|*'at /lib'*|*'under /lib'*) got=poisoned ;; *) got=clean ;; esac
        chk "$sh/$block never resolves under /" clean "$got"
    done
done

# 5. The positive path, plus the retired tier 4 (see header). Without a
#    positive case a block that always failed would pass every check above, so
#    tier 2 (CLAUDE_PLUGIN_ROOT set) must resolve and exit 0. `$ROOT` really
#    does hold lib/vendor/shell-common, so running from that cwd with
#    CLAUDE_PLUGIN_ROOT unset must still stop at tier 5.
resolves() { # resolves <shell> <block> <cwd> <plugin-root-or-empty>
    if [ -n "$4" ]; then
        ( cd "$3" && env -u SHELL_COMMON -u DOTFILES_ROOT CLAUDE_PLUGIN_ROOT="$4" \
            HOME="$HOME_EMPTY" "$1" "$TMP/$2.sh" ) >/dev/null 2>&1
    else
        ( cd "$3" && env -u CLAUDE_PLUGIN_ROOT -u SHELL_COMMON -u DOTFILES_ROOT \
            HOME="$HOME_EMPTY" "$1" "$TMP/$2.sh" ) >/dev/null 2>&1
    fi
}

# Did the block actually load the function? That, not the file's mode, is what
# the sites now prove — so it is what this asserts.
head_state() { # head_state <shell> <block> <cwd> <plugin-root-or-empty>
    _probe='[ -n "${INHERIT-}" ] && eval "_gh_project_status_sync() { :; }"
            [ -n "${SETE-}" ] && set -e
            . "$1"
            command -v _gh_project_status_sync >/dev/null 2>&1 && printf loaded || printf not-loaded'
    if [ -n "$4" ]; then
        ( cd "$3" && env -u SHELL_COMMON -u DOTFILES_ROOT CLAUDE_PLUGIN_ROOT="$4" \
            INHERIT="${INHERIT-}" SETE="${SETE-}" HOME="$HOME_EMPTY" "$1" -c "$_probe" _ "$TMP/$2.sh" 2>/dev/null )
    else
        ( cd "$3" && env -u CLAUDE_PLUGIN_ROOT -u SHELL_COMMON -u DOTFILES_ROOT \
            INHERIT="${INHERIT-}" SETE="${SETE-}" HOME="$HOME_EMPTY" "$1" -c "$_probe" _ "$TMP/$2.sh" 2>/dev/null )
    fi
}

# A directory where the helper should be: the case a bare `-r` would accept.
DIRTRAP="$TMP/dirtrap"
mkdir -p "$DIRTRAP/lib/vendor/shell-common/functions/gh_project_status.sh"
mkdir -p "$DIRTRAP/lib/vendor/shell-common/functions/gh_discussion.sh"

# An existing but unreadable helper must not count as resolved: `-f` alone
# passes it, the source then fails, and an inherited function stays callable.
UNREADABLE="$TMP/unreadable-root"
mkdir -p "$UNREADABLE/lib/vendor/shell-common/functions"
for _fn in gh_discussion.sh gh_project_status.sh; do
    printf '#\n' > "$UNREADABLE/lib/vendor/shell-common/functions/$_fn"
    chmod 000 "$UNREADABLE/lib/vendor/shell-common/functions/$_fn"
done
# Root ignores the permission bits, so the case is only meaningful unprivileged.
if [ -r "$UNREADABLE/lib/vendor/shell-common/functions/gh_discussion.sh" ]; then
    CAN_TEST_UNREADABLE=0
else
    CAN_TEST_UNREADABLE=1
fi

for sh in sh bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || continue

    for block in create discussion-convert discussion-create; do
        resolves "$sh" "$block" "$SANDBOX" "$ROOT"
        chk "$sh/$block resolves via CLAUDE_PLUGIN_ROOT (tier 2)" 0 "$?"
        resolves "$sh" "$block" "$ROOT" ""
        chk "$sh/$block does NOT resolve from the cwd (no tier 4)" 1 "$(($? != 0))"

        if [ "$CAN_TEST_UNREADABLE" -eq 1 ]; then
            resolves "$sh" "$block" "$SANDBOX" "$UNREADABLE"
            chk "$sh/$block rejects an unreadable helper" 1 "$(($? != 0))"
        fi
    done

    # The board-transition prologues do not exit; the observable is whether
    # _gh_project_status_sync is defined after they run.
    for block in implement-claim proceed-claim-head; do
        chk "$sh/$block loads via CLAUDE_PLUGIN_ROOT (tier 2)" loaded \
            "$(head_state "$sh" "$block" "$SANDBOX" "$ROOT")"
        chk "$sh/$block does NOT load from the cwd (no tier 4)" not-loaded \
            "$(head_state "$sh" "$block" "$ROOT" "")"
        chk "$sh/$block reports not-loaded at tier 5" not-loaded \
            "$(head_state "$sh" "$block" "$SANDBOX" "")"
        if [ "$CAN_TEST_UNREADABLE" -eq 1 ]; then
            chk "$sh/$block rejects an unreadable helper" not-loaded \
                "$(head_state "$sh" "$block" "$SANDBOX" "$UNREADABLE")"
        fi
        # A directory at the probed path is the case `-r` alone would accept.
        chk "$sh/$block rejects a directory at the helper path" not-loaded \
            "$(head_state "$sh" "$block" "$SANDBOX" "$DIRTRAP")"
        # And an inherited definition must not survive into the verdict.
        chk "$sh/$block drops an inherited definition" not-loaded \
            "$(INHERIT=1 head_state "$sh" "$block" "$SANDBOX" "")"

        # Under the caller's `set -e` the same paths must still reach the
        # warn-and-skip verdict rather than aborting: this transition is
        # documented soft-fail, and a pasted block inherits shell options.
        chk "$sh/$block survives set -e at tier 5" not-loaded \
            "$(SETE=1 head_state "$sh" "$block" "$SANDBOX" "")"
        chk "$sh/$block survives set -e on the directory trap" not-loaded \
            "$(SETE=1 head_state "$sh" "$block" "$SANDBOX" "$DIRTRAP")"
        chk "$sh/$block still loads under set -e" loaded \
            "$(SETE=1 head_state "$sh" "$block" "$SANDBOX" "$ROOT")"
        if [ "$CAN_TEST_UNREADABLE" -eq 1 ]; then
            chk "$sh/$block survives set -e on an unreadable helper" not-loaded \
                "$(SETE=1 head_state "$sh" "$block" "$SANDBOX" "$UNREADABLE")"
        fi
    done
done

printf '\n'
if [ "$fails" -eq 0 ]; then printf 'ok    all checks passed\n'; else printf 'FAIL  %s check(s)\n' "$fails"; fi
exit "$((fails > 0))"
