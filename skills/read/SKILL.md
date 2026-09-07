---
name: read
description: >-
  Fetch a GitHub issue and print a verbatim structured summary. Read-only —
  never mutates. Use for /gh-issue:read, "이슈 #N 읽고 정리해줘",
  "#16 요약". Not an implementer (gh-issue:implement) nor a protocol runner
  (gh-issue:proceed).
license: MIT
allowed-tools: Bash, Read, Grep
metadata:
  model_recommendation:
    tier: haiku
    reason: "read-only issue summary; verbatim body/comments preservation, no mutation"
    claude: prefer
    non_claude: advisory-only
---

# gh-issue:read — Issue Summary

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Fetch a single GitHub issue and print a structured summary. Read-only —
never mutate the issue. Preserve body + comments verbatim so the output
feeds downstream skills (like `gh-issue:implement`).

## Step 1: Parse Args + Resolve Repo

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 4.

Positional args: `<issue-number> [remote]` — full table in `references/help.md`
→ "Arguments".

- Missing/invalid `issue-number` → print `Run /gh-issue:read -h for usage.`, stop.
- Bind **both** `TARGET_REPO=<owner>/<repo>` and `TARGET_HOST` from that one
  remote's URL via `lib/resolve-target.sh`, then `export GH_HOST="$TARGET_HOST"` —
  every `gh` call below runs as
  `GH_HOST="$TARGET_HOST" gh ... --repo "$TARGET_REPO"` (dEitY719/dotfiles#1403).
  Missing remote → `git remote -v` + stop.

Substeps, error templates, and the host-targeting rationale in
`references/repo-resolution.md`.

## Step 2: Fetch Issue

Run the `gh issue view --json` fetch in `references/output-format.md` →
"JSON fields to fetch".

On error (issue not found, auth failure), print `gh` stderr verbatim and stop —
do not attempt fallback. A CLOSED issue needs one extra REST read for the Header
close reason: `references/output-format.md` → "Close reason".

## Step 3: Format Output

Assemble the output per `references/output-format.md`. Sections:
Header → Summary → Body → Discussion → Meta → Checklist.

- **Body** and **Discussion** are verbatim. Do NOT compress, do NOT
  rewrap, do NOT translate.
- **Summary** is your 2-4 line extraction of the ask.
- **Checklist** pulls every `- [ ]` / `- [x]` line from body + comments.
- Match the user's conversation language for section headers
  (`Summary` vs `요약` etc.) but keep content verbatim.

## Step 4: Report

Print the formatted output directly — no preamble, no trailing summary.
The output IS the deliverable. Then append the ai-metrics line (stdout only —
this skill never mutates GitHub):

```
[ai-metrics:gh-issue-read] ~{ELAPSED} min (read-only — not written to GitHub)
```

Compute `ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))` just before printing.

Then one `Next:` line, keyed off what Step 2 already fetched — omit it entirely
for a CLOSED issue, which has no follow-up:

```
Next: /gh-issue:implement <N>      # OPEN, code-change issue
Next: /gh-issue:proceed <N>        # OPEN, body carries an execution protocol
```

## Constraints

- Read-only — never call `gh issue edit`, `close`, or `comment`.
- Never call `gh` without both `GH_HOST` and `--repo` (dEitY719/dotfiles#1403).
- Never fall back to `origin` when a non-existent remote is passed.

## Related Skills

Downstream consumers — `gh-issue:implement` (code-change issues: edits files) ·
`gh-issue:proceed` (directive issues embedding an executable protocol).
