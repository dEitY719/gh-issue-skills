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
# so the blocks get tiers 1/2/4/5 and no $0/BASH_SOURCE tier.
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
extract discussion-convert '_GD="${DOTFILES_ROOT' 'done' \
    skills/discussion-convert/references/convert-cmd.md
extract discussion-create '_GD="${DOTFILES_ROOT' '}' \
    skills/discussion-create/references/create-cmd.md
extract implement-claim '_SC="${SHELL_COMMON' '_HELPER="$_SC/functions/gh_project_status.sh"' \
    skills/implement/references/claim.md
extract proceed-claim '_SC="${SHELL_COMMON' '```' \
    skills/proceed/references/claim.md

# 1. The gate grep: an explicitly-empty default spliced straight into a path is
#    always the defect (it collapses to the filesystem root).
hits=$(cd "$ROOT" && git ls-files -z | xargs -0 grep -lE '\$\{[A-Za-z_][A-Za-z0-9_]*:?-\}/' 2>/dev/null | wc -l)
chk "no empty-default path splices in tracked files" 0 "$((hits))"

# Tier 5 conditions: no harness exported CLAUDE_PLUGIN_ROOT, no ~/dotfiles, and
# a cwd that is not the checkout — so tiers 1, 2 and 4 all miss.
run() { # run <shell> <block>  -> stderr on stdout, rc in $?
    ( cd "$SANDBOX" && env -u CLAUDE_PLUGIN_ROOT -u SHELL_COMMON -u DOTFILES_ROOT \
        HOME="$HOME_EMPTY" "$1" "$TMP/$2.sh" 2>&1 >/dev/null )
}

for sh in sh bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || { printf 'skip  %s not installed\n' "$sh"; continue; }

    # 2. A hard-fail site stops, and says which path it tried plus the way out.
    for block in create discussion-convert discussion-create; do
        err=$(run "$sh" "$block"); rc=$?
        chk "$sh/$block stops" nonzero "$([ "$rc" -ne 0 ] && echo nonzero || echo "rc=$rc")"
        case "$err" in *"$SANDBOX/lib/vendor/shell-common"*) got=named ;; *) got="$err" ;; esac
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

printf '\n'
if [ "$fails" -eq 0 ]; then printf 'ok    all checks passed\n'; else printf 'FAIL  %s check(s)\n' "$fails"; fi
exit "$((fails > 0))"
