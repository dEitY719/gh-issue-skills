#!/usr/bin/env bash
# lib/create-issue.sh — Step 4 issue path of gh-issue:issue-create
# (dEitY719/gh-issue-skills#53).
#
# EXECUTE it, never source it:
#
#   bash "$PLUGIN_ROOT/lib/create-issue.sh" --title "$TITLE" --body-file "$BODY" \
#       "${LABEL_ARGS[@]}" "${MILESTONE_ARGS[@]}" [--assignee @me]
#
# Reads   GH_HOST and TARGET_REPO (Step 1 bound both from one remote URL).
#         Either empty -> exit 2 and gh is never called: without both, gh CLI
#         follows its own `gh repo set-default` and on a dual-host login files
#         the issue on another server (dEitY719/dotfiles#1403). TARGET_HOST,
#         when set, must equal GH_HOST (same reason).
# Args    --title T, --body-file F (required); --label L and --assignee A
#         (repeatable), --milestone M — passed to `gh issue create` in that
#         order after --title/--body-file.
# Prints  gh's own stdout: the new issue URL.
# Exit    gh's exit code | 2 usage or host/repo binding missing.
#
# The body file already carries the ai-metrics footer (lib/ai-metrics-footer.sh,
# appended by the caller); this script adds no bytes.
#
# Self-check: lib/create-issue.selfcheck.sh
set -u

title="" body="" extra=()
while [ "$#" -gt 0 ]; do
    case $1 in
        --title|--body-file|--label|--milestone|--assignee)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                printf '[FAIL] %s needs a value\n' "$1" >&2
                exit 2
            fi
            case $1 in
                --title) title=$2 ;;
                --body-file) body=$2 ;;
                *) extra+=("$1" "$2") ;;
            esac
            shift 2 ;;
        *)
            printf '[FAIL] unknown argument: %s\n' "$1" >&2
            echo "usage: create-issue.sh --title <t> --body-file <f> [--label L]... [--milestone M] [--assignee A]" >&2
            exit 2 ;;
    esac
done

if [ -z "$title" ] || [ -z "$body" ]; then
    echo "usage: create-issue.sh --title <t> --body-file <f> [--label L]... [--milestone M] [--assignee A]" >&2
    exit 2
fi
if [ ! -f "$body" ] || [ ! -r "$body" ]; then
    printf '[FAIL] body file not readable: %s\n' "$body" >&2
    exit 2
fi
if [ -z "${GH_HOST:-}" ] || [ -z "${TARGET_REPO:-}" ]; then
    echo "[FAIL] GH_HOST and TARGET_REPO must both be set — run Step 1 (resolve-target.sh); refusing to let gh pick the host (dEitY719/dotfiles#1403)." >&2
    exit 2
fi
if [ -n "${TARGET_HOST:-}" ] && [ "$TARGET_HOST" != "$GH_HOST" ]; then
    printf '[FAIL] GH_HOST (%s) != TARGET_HOST (%s) — host and repo must come from one remote URL.\n' "$GH_HOST" "$TARGET_HOST" >&2
    exit 2
fi

GH_HOST="$GH_HOST" gh issue create --repo "$TARGET_REPO" \
    --title "$title" --body-file "$body" ${extra[@]+"${extra[@]}"}
