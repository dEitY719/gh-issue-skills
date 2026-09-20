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
    skills/issue-create/references/create-cmd.md
extract discussion-convert '_GD="${DOTFILES_ROOT' 'fi' \
    skills/discussion-convert/references/convert-cmd.md
extract discussion-create '_GD="${DOTFILES_ROOT' '}' \
    skills/discussion-create/references/create-cmd.md
# The board-transition prologue used to be extracted from both claim.md files
# here. It has one home now — lib/claim-issue.sh — so the same tiers are
# asserted in lib/claim-issue.selfcheck.sh §13, against the real script rather
# than a slice of a doc (dEitY719/gh-issue-skills#21).

# 1. The gate grep: an explicitly-empty default spliced straight into a path is
#    always the defect (it collapses to the filesystem root), and so is a `$PWD`,
#    `.` or `$(pwd)` default — all three spell the retired tier 4 (see header).
#    `:-.` is the form that slipped past this grep into auto-labels.md (#26);
#    `$(pwd)` names the same caller-controlled directory a third way, and was
#    added upstream in dEitY719/harness-skills#35.
hits=$(cd "$ROOT" && git ls-files -z | xargs -0 grep -lE '\$\{[A-Za-z_][A-Za-z0-9_]*:?-(\$PWD|\$\(pwd\)|\.)?\}/' 2>/dev/null | wc -l)
chk "no empty-default, \$PWD or cwd path splices in tracked files" 0 "$((hits))"

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

    # 4. The regression this whole convention exists for: never resolve to the
    #    filesystem root, and never export an unproven SHELL_COMMON. Sourced,
    #    because that is how a poisoned export would reach later helpers.
    for block in create discussion-convert discussion-create; do
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

# A directory where the helper should be: the case a bare `-r` would accept.
DIRTRAP="$TMP/dirtrap"
mkdir -p "$DIRTRAP/lib/vendor/shell-common/functions/gh_project_status.sh"
mkdir -p "$DIRTRAP/lib/vendor/shell-common/functions/gh_discussion.sh"
mkdir -p "$DIRTRAP/lib/vendor/shell-common/functions/parse_yaml_defaults.sh"

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

done

# 6. The repo-resolution bootstrap line (dEitY719/harness-skills#24): the block
#    that locates lib/resolve-target.sh ITSELF, one step before that file's own
#    tiers (lib/resolve-target.selfcheck.sh check 9) ever get a chance to run.
#    Byte-identical across all six repo-resolution.md copies plus this file's
#    own docstring, per the issue — extracted from one copy so a drift between
#    the six fails this check instead of hiding.
dedent_block() { # dedent_block <file> -> stdout, dedented, fenced ```bash block
    awk '
        /^   ```bash$/ && !on { on = 1; next }
        on && /^   ```$/ { exit }
        on { sub(/^   /, ""); print }
    ' "$ROOT/$1"
}
dedent_block skills/issue-create/references/repo-resolution.md > "$TMP/repo-resolution.sh"
[ -s "$TMP/repo-resolution.sh" ] || { printf 'FAIL  repo-resolution: extracted nothing from skills/issue-create\n'; fails=$((fails + 1)); }
for f in skills/discussion-convert/references/repo-resolution.md \
         skills/discussion-create/references/repo-resolution.md \
         skills/implement/references/repo-resolution.md \
         skills/proceed/references/repo-resolution.md \
         skills/read/references/repo-resolution.md; do
    dedent_block "$f" > "$TMP/repo-resolution-cmp.sh"
    [ -s "$TMP/repo-resolution-cmp.sh" ] || { printf 'FAIL  repo-resolution: extracted nothing from %s\n' "$f"; fails=$((fails + 1)); }
    cmp -s "$TMP/repo-resolution.sh" "$TMP/repo-resolution-cmp.sh" \
        || { printf 'FAIL  repo-resolution: %s drifted from skills/issue-create copy\n' "$f"; fails=$((fails + 1)); }
done

# The docstring in lib/resolve-target.sh's own header pastes the same block
# behind `# ` comment markers (PR #27 review, agy+codex FOLLOW-UP: nothing
# above caught a drift between it and the six .md copies).
awk '
    /^#   _RT="" # no cwd fallback/ && !on { on = 1 }
    on { line = $0; sub(/^#   /, "", line); print line }
    on && /\. "\$_RT" \|\| exit 1$/ { exit }
' "$ROOT/lib/resolve-target.sh" > "$TMP/repo-resolution-docstring.sh"
[ -s "$TMP/repo-resolution-docstring.sh" ] || { printf 'FAIL  repo-resolution: extracted nothing from lib/resolve-target.sh docstring\n'; fails=$((fails + 1)); }
chk "repo-resolution: lib/resolve-target.sh docstring matches skills/issue-create copy" \
    "$(cat "$TMP/repo-resolution.sh")" "$(cat "$TMP/repo-resolution-docstring.sh")"

if command -v dash >/dev/null 2>&1; then
    # Decoy: exactly what a PR checkout under review could ship — its own
    # lib/resolve-target.sh at $PWD, poisoning TARGET_REPO if ever sourced.
    DECOY_RT="$TMP/decoy-rt"
    mkdir -p "$DECOY_RT/lib"
    cat > "$DECOY_RT/lib/resolve-target.sh" <<'DECOY'
#!/bin/sh
export TARGET_REPO="poisoned/repo"
DECOY
    RRBLOCK="$TMP/repo-resolution.sh"
    # -u TARGET_REPO (PR #27 review, codex FOLLOW-UP): an already-exported
    # TARGET_REPO in the calling shell would leak into the child and read back
    # as itself instead of "unset" even when the decoy correctly never ran.
    got=$( cd "$DECOY_RT" && env -u CLAUDE_PLUGIN_ROOT -u TARGET_REPO dash -c \
        ". \"$RRBLOCK\" >/dev/null 2>&1; printf '%s|%s' \"\$?\" \"\${TARGET_REPO:-unset}\"" )
    chk "repo-resolution bootstrap never sources cwd's own resolve-target.sh (no tier 4)" \
        "1|unset" "$got"

    # Positive path: CLAUDE_PLUGIN_ROOT pointing at the real plugin root still
    # resolves — run from $ROOT itself so the real resolve-target.sh finds a
    # git repo with an `origin` remote to read. The path is interpolated into
    # the -c script text, not forwarded as a positional: a positional would
    # become $1 inside the sourced block too, ahead of its own
    # `"${REMOTE:-origin}"` default. Asserts more than rc=0 (PR #27 review,
    # codex FOLLOW-UP): a broken block could still exit 0 without ever
    # exporting TARGET_REPO, so the real remote's owner/repo must show up too.
    # Reuse the same parser resolve-target.sh itself relies on (PR #27 review,
    # agy FOLLOW-UP: an ad-hoc regex here would be a second, driftable copy).
    # 2>/dev/null: sourcing the vendored copy directly (not via $SHELL_COMMON)
    # trips its own advisory "foreign checkout" warning (#1454) on a machine
    # that also has ~/dotfiles — harmless here, just noisy test output.
    # shellcheck disable=SC1091
    . "$ROOT/lib/vendor/shell-common/functions/gh_host.sh" 2>/dev/null
    EXPECT_REPO=$(_gh_parse_owner_repo_url "$(cd "$ROOT" && git remote get-url origin)")
    # -u DOTFILES_ROOT -u SHELL_COMMON, HOME=$HOME_EMPTY (PR #27 review, codex
    # FOLLOW-UP): matches the isolation `resolves()` above already uses — an
    # inherited ~/dotfiles could let resolve-target.sh source a DIFFERENT
    # gh_host.sh than the vendored one EXPECT_REPO was computed from.
    got=$( cd "$ROOT" && env -u TARGET_REPO -u DOTFILES_ROOT -u SHELL_COMMON \
        CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$HOME_EMPTY" dash -c \
        ". \"$RRBLOCK\" >/dev/null 2>&1; printf '%s|%s' \"\$?\" \"\${TARGET_REPO:-unset}\"" )
    chk "repo-resolution bootstrap resolves via CLAUDE_PLUGIN_ROOT (tier 1)" "0|$EXPECT_REPO" "$got"
else
    echo "skip  dash not installed"
fi

# 7. The auto-labels parser prologue (#26). A third pasted block, soft-fail like
#    the board ones: it warns and skips rather than aborting, and the observable
#    is whether the parser's helpers got defined. It shipped `${CLAUDE_PLUGIN_ROOT:-.}`
#    — a literal tier 4 — until #26, which nothing here covered because the block
#    was never extracted.
dedent_block skills/issue-create/references/auto-labels.md > "$TMP/auto-labels.sh"
[ -s "$TMP/auto-labels.sh" ] || { printf 'FAIL  auto-labels: extracted nothing\n'; fails=$((fails + 1)); }

# A parser tree that is present and readable but defines nothing: the case an
# [ -f ]/[ -r ] guard cannot tell from a real one.
PARSER_HOLLOW="$TMP/parser-hollow"
mkdir -p "$PARSER_HOLLOW/lib/vendor/shell-common/functions"
printf '# defines nothing\n' \
    > "$PARSER_HOLLOW/lib/vendor/shell-common/functions/parse_yaml_defaults.sh"

parser_state() { # parser_state <shell> <cwd> <plugin-root-or-empty>
    _probe='. "$1"
            command -v _parse_yaml_defaults_static >/dev/null 2>&1 && printf loaded || printf not-loaded'
    if [ -n "$3" ]; then
        ( cd "$2" && env -u SHELL_COMMON -u DOTFILES_ROOT CLAUDE_PLUGIN_ROOT="$3" \
            HOME="$HOME_EMPTY" "$1" -c "$_probe" _ "$TMP/auto-labels.sh" 2>/dev/null )
    else
        ( cd "$2" && env -u CLAUDE_PLUGIN_ROOT -u SHELL_COMMON -u DOTFILES_ROOT \
            HOME="$HOME_EMPTY" "$1" -c "$_probe" _ "$TMP/auto-labels.sh" 2>/dev/null )
    fi
}

for sh in sh bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || continue
    chk "$sh/auto-labels loads via CLAUDE_PLUGIN_ROOT (tier 2)" loaded \
        "$(parser_state "$sh" "$SANDBOX" "$ROOT")"
    # $ROOT really does hold lib/vendor/shell-common/functions/parse_yaml_defaults.sh,
    # which is exactly what a PR under review would ship.
    chk "$sh/auto-labels does NOT load from the cwd (no tier 4)" not-loaded \
        "$(parser_state "$sh" "$ROOT" "")"
    chk "$sh/auto-labels reports not-loaded at tier 5" not-loaded \
        "$(parser_state "$sh" "$SANDBOX" "")"
    chk "$sh/auto-labels rejects a directory at the parser path" not-loaded \
        "$(parser_state "$sh" "$SANDBOX" "$DIRTRAP")"
    # harness-skills#36: an [ -f ]/[ -r ] pair is a load guard, not a proof. A
    # parser that is present and readable but defines nothing passed it, so the
    # block printed no warning and Step 2 then died on `command not found`
    # mid-run instead of taking the documented skip. The block's own stderr is
    # the observable -- parser_state above only reports shell state, which is
    # not-loaded either way and so cannot see this.
    warn=$( cd "$SANDBOX" && env -u SHELL_COMMON -u DOTFILES_ROOT \
        CLAUDE_PLUGIN_ROOT="$PARSER_HOLLOW" HOME="$HOME_EMPTY" \
        "$sh" "$TMP/auto-labels.sh" 2>&1 >/dev/null )
    case "$warn" in *'auto-labels skipped'*) got=warned ;; *) got="${warn:-silent}" ;; esac
    chk "$sh/auto-labels warns when the parser defines nothing" warned "$got"
done

printf '\n'
if [ "$fails" -eq 0 ]; then printf 'ok    all checks passed\n'; else printf 'FAIL  %s check(s)\n' "$fails"; fi
exit "$((fails > 0))"
